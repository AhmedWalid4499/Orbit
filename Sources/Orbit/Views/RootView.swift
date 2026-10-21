import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = NSFullUserName()

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
                case .github: GitHubView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .animation(.easeOut(duration: 0.15), value: state.tab)
        .sheet(isPresented: $state.searchOpen) { SearchView() }
        .task {
            // Daily background refresh for reading sources and the inbox while Orbit is open.
            while !Task.isCancelled {
                await ReadingSync.shared.syncIfDue(context: context)
                await InboxStore.shared.refreshIfDue(context: context)
                await EmailExpenses.shared.syncIfDue(context: context)
                await Updater.shared.checkIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }
}

private struct TopBar: View {
    @EnvironmentObject private var state: AppState
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
                    UpdatePill()
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
                    Avatar(name: userName, size: 42)
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

struct Avatar: View {
    let name: String
    var size: CGFloat = 44

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Text(initials.isEmpty ? "Me" : initials)
            .font(Theme.ui(size * 0.36, weight: .bold))
            .foregroundStyle(Theme.stickerInk)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [Theme.pink, Theme.purple],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}
