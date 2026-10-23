import SwiftUI
import SwiftData

/// The iPhone's sections. The Mac's other tabs live under More.
enum PhoneTab: Hashable { case today, calendar, tasks, money, more }

struct PhoneRoot: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var apple: AppleSync
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var cloud = CloudSync.shared
    @ObservedObject private var focus = FocusTimer.shared
    @ObservedObject private var reading = ReadingTimer.shared
    @AppStorage("phoneOnboarded") private var onboarded = false

    @State private var tab: PhoneTab = .today
    @State private var morePath: [Tab] = []

    var body: some View {
        Group {
            if !onboarded && !cloud.isSignedIn && !Snapshot.isActive {
                PhoneWelcome { onboarded = true }
            } else {
                tabs
            }
        }
        .tint(Theme.ink)
        .sheet(isPresented: $state.assistantOpen) { AssistantPanel().presentationDragIndicator(.visible) }
        .sheet(isPresented: $state.searchOpen) { SearchView() }
        .sheet(isPresented: $state.settingsOpen) { PhoneSettings() }
        .sheet(isPresented: $state.reviewOpen) { ReviewView() }
        .sheet(isPresented: $state.cardOpen) { PhoneCardSheet() }
        .sheet(isPresented: $state.planOpen) { PlanTomorrowSheet() }
        .sheet(isPresented: $state.captureOpen) { PhoneCapture().presentationDetents([.medium, .large]) }
        .sheet(item: Binding(get: { focus.justFinished }, set: { focus.justFinished = $0 })) { FocusDoneSheet(session: $0).presentationDetents([.medium]) }
        .sheet(item: Binding(get: { reading.justFinished }, set: { reading.justFinished = $0 })) { FinishedReadingSheet(session: $0).presentationDetents([.medium]) }
        .onChange(of: state.tab) { _, t in show(t) }
        .onReceive(Reminders.shared.$route.compactMap { $0 }) { route in
            Reminders.shared.route = nil
            switch route {
            case "journal": state.openTodayJournal = true; show(.notes)
            case "review": tab = .today; state.reviewOpen = true
            case "plan": tab = .today; state.planOpen = true
            default: if let t = Tab(rawValue: route) { show(t) }
            }
        }
        .onOpenURL { url in
            // Widget taps: com.personal.orbit://open/<tab>
            if url.host == "open", let t = Tab(rawValue: url.lastPathComponent) { show(t) } else { CloudAuth.handleCallback(url) }
        }
        .task {
            focus.restore(context: context); reading.restore(context: context)
            BankTest.runIfRequested()
            // For testing: `-open habits` (or any tab), `-sheet plan|review|card|assistant|settings|capture|search`.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-open"), i + 1 < args.count, let t = Tab(rawValue: args[i + 1]) { show(t) }
            if let i = args.firstIndex(of: "-sheet"), i + 1 < args.count {
                switch args[i + 1] {
                case "plan": state.planOpen = true
                case "review": state.reviewOpen = true
                case "card": state.cardOpen = true
                case "assistant": state.assistantOpen = true
                case "settings": state.settingsOpen = true
                case "capture": state.captureOpen = true
                case "search": state.searchOpen = true
                default: break
                }
            }
        }
        .task(id: phase) {
            // While Orbit is open: sync every two minutes, keep reminders current, refresh email and reading now and then.
            guard phase == .active, !Snapshot.isActive else { return }
            var rounds = 0
            while !Task.isCancelled {
                await cloud.syncIfSignedIn(context: context)
                await apple.requestAccessIfEnabled()
                await Reminders.shared.reschedule(context: context, apple: apple)
                WidgetBridge.update(context: context, apple: apple)
                if rounds % 30 == 0 {
                    await AIAssistant.shared.refreshBrief(context: context, apple: apple)
                    await ReadingSync.shared.syncIfDue(context: context)
                    await InboxStore.shared.refreshIfDue(context: context)
                    await EmailExpenses.shared.syncIfDue(context: context)
                    await GoogleCalendarStore.shared.refreshIfDue()
                    SubscriptionTracker.detect(context: context)
                }
                rounds += 1
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            SwiftUI.Tab("Today", systemImage: "sun.max.fill", value: PhoneTab.today) {
                NavigationStack { PhoneToday() }
            }
            SwiftUI.Tab("Calendar", systemImage: "calendar", value: PhoneTab.calendar) {
                NavigationStack { PhoneCalendar() }
            }
            SwiftUI.Tab("Tasks", systemImage: "checklist", value: PhoneTab.tasks) {
                NavigationStack { PhoneTasks() }
            }
            SwiftUI.Tab("Money", systemImage: "creditcard.fill", value: PhoneTab.money) {
                NavigationStack { PhoneMoney() }
            }
            SwiftUI.Tab("More", systemImage: "square.grid.2x2.fill", value: PhoneTab.more) {
                NavigationStack(path: $morePath) {
                    PhoneMore()
                        .navigationDestination(for: Tab.self) { PhoneSection(tab: $0) }
                }
            }
        }
    }

    /// Jumps to a Mac-style section (from a notification, Siri or a tile).
    private func show(_ t: Tab) {
        switch t {
        case .today: tab = .today
        case .calendar: tab = .calendar
        case .tasks: tab = .tasks
        case .money: tab = .money
        default:
            tab = .more
            morePath = [t]
        }
    }
}

/// The screen for a section listed under More.
struct PhoneSection: View {
    let tab: Tab

    var body: some View {
        switch tab {
        case .insights: InsightsDashboard().phoneChrome("Insights")
        case .habits: PhoneHabits()
        case .notes: PhoneNotes()
        case .reading: PhoneReading()
        case .bucket: PhoneBucket()
        case .documents: PhoneDocuments()
        case .github: PhoneGitHub()
        default: EmptyView()
        }
    }
}

// MARK: - Chrome

extension View {
    /// The bar every iPhone screen shares: title, your avatar menu, quick add and the assistant, plus running timers.
    func phoneChrome(_ title: String) -> some View { modifier(PhoneChrome(title: title)) }
}

struct PhoneChrome: ViewModifier {
    let title: String
    @EnvironmentObject private var state: AppState
    @ObservedObject private var focus = FocusTimer.shared
    @ObservedObject private var reading = ReadingTimer.shared
    @AppStorage("userName") private var userName = ""

    func body(content: Content) -> some View {
        content
            .background(Theme.canvas)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            .safeAreaInset(edge: .top, spacing: 0) {
                if focus.active != nil || reading.active != nil {
                    HStack(spacing: 8) {
                        FocusPill()
                        ReadingTimerPill()
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(.bar)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { state.captureOpen = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Quick add")
                    Button { state.openAssistant() } label: {
                        Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.stickerInk)
                            .frame(width: 30, height: 30).background(Circle().fill(Theme.lime))
                    }
                    .accessibilityLabel(AssistantName.current)
                    Menu {
                        Button { state.cardOpen = true } label: { Label("My Card", systemImage: "person.text.rectangle") }
                        Button { state.reviewOpen = true } label: { Label("Week in review", systemImage: "chart.line.uptrend.xyaxis") }
                        Button { state.searchOpen = true } label: { Label("Search", systemImage: "magnifyingglass") }
                        Button { state.settingsOpen = true } label: { Label("Settings", systemImage: "gearshape") }
                    } label: {
                        Avatar(name: userName.isEmpty ? "Me" : userName, size: 30)
                    }
                    .accessibilityLabel("Profile and settings")
                }
            }
    }
}
