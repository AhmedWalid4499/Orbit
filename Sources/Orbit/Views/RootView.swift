import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var apple: AppleSync
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = NSFullUserName()
    @AppStorage("tourSeen") private var tourSeen = false
    @AppStorage("hiddenTabs") private var hiddenTabs = ""
    @AppStorage("assistantName") private var assistantName = "Ask"
    @AppStorage("onboarded") private var onboarded = false
    @ObservedObject private var focus = FocusTimer.shared
    /// In full screen the window has no title bar, so keep the tabs below the camera notch.
    @State private var fullScreenTopInset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            TopBar(userName: userName)
                .padding(.horizontal, 32)
                .padding(.top, 22 + fullScreenTopInset)
                .padding(.bottom, 18)

            Group {
                switch state.tab {
                case .today: TodayView()
                case .insights: InsightsDashboard()
                case .calendar: CalendarWeekView()
                case .tasks: TasksView()
                case .habits: HabitsView()
                case .money: MoneyView()
                case .notes: NotesView()
                case .reading: ReadingView()
                case .documents: DocumentsView()
                case .bucket: BucketListView()
                case .github: GitHubView()
                case .youtube: YouTubeView()
                }
            }
            // Content that's taller than the window is cut at the bottom, never pushing the top bar out of view.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .sheet(isPresented: $state.cardOpen) { ProfileCardSheet() }
        .sheet(isPresented: $state.planOpen) { PlanTomorrowSheet() }
        // First launch: the tour, then a few quick settings.
        .sheet(isPresented: Binding(get: { !onboarded && !Snapshot.isActive }, set: { if !$0 { onboarded = true } })) {
            if tourSeen { WelcomeView() } else { TourView { tourSeen = true } }
        }
        .sheet(isPresented: $state.tourOpen) { TourView { state.tourOpen = false } }
        .sheet(isPresented: $state.newTaskOpen) {
            NewTaskSheet { state.newTaskOpen = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { CapturePanel.shared.show() } }
        }
        .task { if ProcessInfo.processInfo.arguments.contains("-tour") { state.tourOpen = true } }
        .sheet(item: Binding(get: { focus.justFinished }, set: { focus.justFinished = $0 })) { FocusDoneSheet(session: $0) }
        .modifier(SplashOverlay())
        // A tab you hid closes if you were on it.
        .onChange(of: hiddenTabs) { _, raw in if raw.split(separator: ",").contains(Substring(state.tab.rawValue)) { state.tab = .today } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { n in
            fullScreenTopInset = (n.object as? NSWindow)?.screen?.safeAreaInsets.top ?? 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in fullScreenTopInset = 0 }
        .task {
            // Orbit can reopen already in full screen (macOS restores it), with no "entered" notification.
            try? await Task.sleep(for: .seconds(1))
            if let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.styleMask.contains(.fullScreen) }) {
                fullScreenTopInset = w.screen?.safeAreaInsets.top ?? 0
            }
        }
        .task { focus.restore(context: context) }
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
            case "plan": state.tab = .today; state.planOpen = true
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
                SubscriptionTracker.detect(context: context)
                await Updater.shared.checkIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }
}

struct TopBar: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("assistantName") private var assistantName = "Ask"
    let userName: String

    var body: some View {
        HStack {
            HStack(spacing: 2) {
                Text("orbit")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(-1)
                Circle().fill(Theme.lime).frame(width: 9, height: 9).offset(y: 9)
            }
            .padding(.leading, 70) // traffic lights
            Spacer(minLength: 16)
            // The current tab always shows its name; narrower windows get tighter spacing instead.
            ViewThatFits(in: .horizontal) { NavDock(density: 0); NavDock(density: 1); NavDock(density: 2) }
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                FocusPill()
                ReadingTimerPill()
                UpdatePill()
                Button { state.assistantOpen.toggle() } label: {
                    HStack(spacing: 7) {
                        AssistantAvatar(size: 26)
                        Text(assistantName)
                    }
                    .font(Theme.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.stickerInk)
                    .padding(.leading, 8).padding(.trailing, 14).frame(height: 42)
                    // The same colours as the assistant's orb in the chat.
                    .background(Capsule().fill(LinearGradient(colors: [Theme.lime, Theme.mint, Theme.cyan.opacity(0.85), Theme.lavender, Theme.pink],
                                                              startPoint: .leading, endPoint: .trailing)))
                }
                .buttonStyle(.plain)
                .help("\(assistantName) (⌘J)")
                CircleIconButton(symbol: "magnifyingglass", size: 42) { state.searchOpen = true }
                    .help("Search (⌘K)")
                CircleIconButton(symbol: "plus", size: 42) { state.newTaskOpen = true }
                    .help("New task (Quick add: ⌥Space)")
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
            .fixedSize()
        }
    }
}

/// Compact navigation: icons in one capsule, the current tab expands to show its name.
struct NavDock: View {
    @EnvironmentObject private var state: AppState
    /// 0 roomy, 1 tighter, 2 tightest.
    let density: Int
    @Namespace private var ns
    @AppStorage("hiddenTabs") private var hiddenRaw = ""
    private var hidden: Set<Tab> { Set(hiddenRaw.split(separator: ",").compactMap { Tab(rawValue: String($0)) }) }

    var body: some View {
        HStack(spacing: [4, 2, 0][density]) {
            ForEach(Array(Tab.visibleGroups(hidden: hidden).enumerated()), id: \.offset) { i, group in
                if i > 0 {
                    Capsule().fill(Theme.line).frame(width: 1.5, height: 22).padding(.horizontal, density == 0 ? 4 : 2)
                }
                ForEach(group) { tab in
                    DockItem(tab: tab, selected: state.tab == tab, density: density, ns: ns) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { state.tab = tab }
                    }
                }
            }
        }
        .padding(5)
        .background(Capsule().fill(Theme.card))
    }
}

struct DockItem: View {
    let tab: Tab
    let selected: Bool
    let density: Int
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.symbol).font(.system(size: 14, weight: .semibold))
                if selected {
                    Text(tab.title).font(Theme.ui(density == 2 ? 13 : 14, weight: .semibold)).lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(selected ? Theme.onInverse : (hovering ? Theme.ink : Theme.inkSecondary))
            .padding(.horizontal, selected ? [16, 14, 12][density] : 0)
            .frame(minWidth: [40, 36, 33][density], minHeight: 40)
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
        .help(tab.shortcutNumber.map { "\(tab.title)  ⌘\($0)" } ?? tab.title)
    }
}

/// Avatar in the top bar; click it to change your photo.
struct ProfileMenu: View {
    let name: String
    @ObservedObject private var profile = ProfileStore.shared

    var body: some View {
        Menu {
            Button("My Card…") { AppState.current?.cardOpen = true }
            Divider()
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
