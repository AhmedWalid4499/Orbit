import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var apple: AppleSync
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = NSFullUserName()
    @AppStorage("assistantName") private var assistantName = "Ask"
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(userName: userName)
                .padding(.horizontal, 32)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Group {
                switch state.tab {
                case .today: TodayView()
                case .calendar: CalendarWeekView()
                case .tasks: TasksView()
                case .habits: HabitsView()
                case .money: MoneyView()
                case .notes: NotesView()
                case .reading: ReadingView()
                case .bucket: BucketListView()
                case .github: GitHubView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .animation(.easeOut(duration: 0.15), value: state.tab)
        .overlay(alignment: .trailing) {
            if state.assistantOpen {
                AssistantPanel()
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: state.assistantOpen)
        .sheet(isPresented: $state.searchOpen) { SearchView() }
        .sheet(isPresented: $state.reviewOpen) { ReviewView() }
        .sheet(isPresented: Binding(get: { !onboarded && !Snapshot.isActive }, set: { if !$0 { onboarded = true } })) { WelcomeView() }
        .task {
            // Keep the next two days of notifications current.
            while !Task.isCancelled {
                await Reminders.shared.reschedule(context: context, apple: apple)
                WidgetBridge.update(context: context, apple: apple)
                try? await Task.sleep(for: .seconds(120))
            }
        }
        .onReceive(Reminders.shared.$route.compactMap { $0 }) { route in
            Reminders.shared.route = nil
            switch route {
            case "journal": state.openTodayJournal = true; state.tab = .notes
            case "review": state.tab = .today; state.reviewOpen = true
            default: if let t = Tab(rawValue: route) { state.tab = t }
            }
        }
        .task {
            // Sync with your Orbit account every two minutes while signed in.
            while !Task.isCancelled {
                await CloudSync.shared.syncIfSignedIn(context: context)
                try? await Task.sleep(for: .seconds(120))
            }
        }
        .task {
            // Daily background refresh for reading sources and the inbox while Orbit is open.
            while !Task.isCancelled {
                await ReadingSync.shared.syncIfDue(context: context)
                await InboxStore.shared.refreshIfDue(context: context)
                await EmailExpenses.shared.syncIfDue(context: context)
                await GoogleCalendarStore.shared.refreshIfDue()
                await Updater.shared.checkIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }
}

private struct TopBar: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("assistantName") private var assistantName = "Ask"
    let userName: String

    var body: some View {
        ZStack {
            HStack {
                HStack(spacing: 2) {
                    Text("orbit")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-1)
                    Circle().fill(Theme.lime).frame(width: 9, height: 9).offset(y: 9)
                }
                .padding(.leading, 70) // traffic lights
                Spacer()
                HStack(spacing: 10) {
                    ReadingTimerPill()
                    UpdatePill()
                    Button { state.assistantOpen.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text(assistantName)
                        }
                        .font(Theme.ui(13, weight: .semibold))
                        .foregroundStyle(Theme.stickerInk)
                        .padding(.horizontal, 14).frame(height: 42)
                        .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    .help("\(assistantName) (⌘J)")
                    CircleIconButton(symbol: "magnifyingglass", size: 42) { state.searchOpen = true }
                        .help("Search (⌘K)")
                    CircleIconButton(symbol: "plus", size: 42) { CapturePanel.shared.show() }
                        .help("Quick capture (⌥Space)")
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Theme.card))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    ProfileMenu(name: userName)
                }
            }
            NavDock()
        }
    }
}

/// Compact navigation: icons in one capsule, the current tab expands to show its name.
private struct NavDock: View {
    @EnvironmentObject private var state: AppState
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Tab.groups.enumerated()), id: \.offset) { i, group in
                if i > 0 {
                    Capsule().fill(Theme.line).frame(width: 1.5, height: 22).padding(.horizontal, 4)
                }
                ForEach(group) { tab in
                    DockItem(tab: tab, selected: state.tab == tab, ns: ns) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { state.tab = tab }
                    }
                }
            }
        }
        .padding(5)
        .background(Capsule().fill(Theme.card))
    }
}

private struct DockItem: View {
    let tab: Tab
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.symbol).font(.system(size: 14, weight: .semibold))
                if selected {
                    Text(tab.title).font(Theme.ui(14, weight: .semibold)).lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(selected ? Theme.onInverse : (hovering ? Theme.ink : Theme.inkSecondary))
            .padding(.horizontal, selected ? 16 : 0)
            .frame(minWidth: 40, minHeight: 40)
            .background {
                if selected {
                    Capsule().fill(Theme.inverse).matchedGeometryEffect(id: "dock", in: ns)
                } else if hovering {
                    Circle().fill(Theme.cardHover)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(tab.title)  ⌘\(Tab.allCases.firstIndex(of: tab)! + 1)")
    }
}

/// Avatar in the top bar; click it to change your photo.
private struct ProfileMenu: View {
    let name: String
    @ObservedObject private var profile = ProfileStore.shared

    var body: some View {
        Menu {
            Button(profile.photo == nil ? "Add Profile Photo…" : "Change Profile Photo…") { profile.choosePhoto() }
            if profile.photo != nil { Button("Remove Photo", role: .destructive) { profile.removePhoto() } }
            Divider()
            SettingsLink { Text("Settings…") }
        } label: {
            Avatar(name: name, size: 42)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Profile")
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 44
    @ObservedObject private var profile = ProfileStore.shared

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Group {
            if let photo = profile.photo {
                Image(nsImage: photo).resizable().scaledToFill()
            } else {
                Text(initials.isEmpty ? "Me" : initials)
                    .font(Theme.ui(size * 0.36, weight: .bold))
                    .foregroundStyle(Theme.stickerInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [Theme.pink, Theme.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
