import Foundation
import SwiftData
import WatchConnectivity

/// The iPhone side of Orbit on Apple Watch: sends the watch a picture of your day and carries out what you do
/// on the watch (tick off a task or habit, quick add, log an expense, ask your assistant). Your data and API key
/// stay on the iPhone; the watch only sees the summary.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private var lastSent: Data?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Builds the snapshot and sends it if the watch app is installed and anything changed.
    func push(context: ModelContext, apple: AppleSync) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let snap = Self.snapshot(context: context, apple: apple)
        var compare = snap; compare.generatedAt = .distantPast
        guard let data = snap.data, compare.data != lastSent else { return }
        lastSent = compare.data
        try? WCSession.default.updateApplicationContext([WatchSnapshot.contextKey: data])
    }

    static func snapshot(context: ModelContext, apple: AppleSync) -> WatchSnapshot {
        let now = Date.now, today = now.startOfDay, tomorrow = today.adding(days: 1)
        var s = WatchSnapshot()
        s.greetingName = Platform.userName.split(separator: " ").first.map(String.init) ?? ""
        s.assistantName = AssistantName.current
        s.currency = Fmt.currencyCode
        s.hasAI = AIAssistant.shared.hasKey

        let local = ((try? context.fetch(FetchDescriptor<EventItem>())) ?? []).filter { $0.start < tomorrow.adding(days: 1) && $0.start >= today }
        let entries = CalEntry.merge(local: local, apple: apple.events(from: today, to: tomorrow.adding(days: 1)),
                                     google: GoogleCalendarStore.shared.events(from: today, to: tomorrow.adding(days: 1)))
        s.events = entries.filter { $0.end > now }.prefix(8).map {
            .init(id: "\($0.title)\($0.start.timeIntervalSince1970)", title: $0.title, start: $0.start, end: $0.end, allDay: $0.isAllDay)
        }

        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        s.tasksDoneToday = tasks.filter { $0.isDone && ($0.completedAt ?? .distantPast) >= today }.count
        s.tasks = tasks.filter { !$0.isDone && ($0.due.map { $0 < tomorrow } ?? false) }
            .sorted { ($0.isOverdue ? 1 : 0, $0.priority) > ($1.isOverdue ? 1 : 0, $1.priority) }
            .prefix(12).map { .init(id: $0.uuid, title: $0.title, priority: $0.priority, overdue: $0.isOverdue) }

        let habits = (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        s.habits = habits.map { .init(id: $0.uuid, name: $0.name, symbol: $0.symbol, done: $0.isDone(on: today), streak: $0.currentStreak) }

        let txns = (try? context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let spentToday = -txns.filter { $0.isExpense && $0.date >= today && $0.date < tomorrow }.reduce(0) { $0 + $1.amount }
        let month = BudgetPeriod.spent(txns)
        let budget = UserDefaults.standard.object(forKey: "monthlyBudget") as? Double ?? 2000
        s.spentToday = Fmt.money(spentToday)
        s.spentMonth = Fmt.money(month)
        s.budgetLeft = Fmt.money(budget - month)
        s.budgetUsed = budget > 0 ? month / budget : 0
        s.recentExpenses = txns.filter(\.isExpense).prefix(5).map { .init(id: $0.uuid, title: $0.title, amount: Fmt.money(-$0.amount)) }

        if let b = BookLibrary.currentlyReading(context: context).first {
            s.reading = .init(title: b.title, author: b.author, progress: b.progress)
        }
        if DaySummaryStore.shared.isToday { s.dayLine = DaySummaryStore.shared.summary?.line ?? "" }
        else if AIAssistant.shared.hasTodaysBrief { s.dayLine = AIAssistant.shared.brief?.headline ?? "" }
        if let w = WeatherStore.shared.now {
            s.weather = "\(Int(w.temperature.rounded()))° \(WeatherStore.describe(w.code, isDay: w.isDay).label)"
        }
        return s
    }

    // MARK: Actions from the watch

    private func handle(_ action: WatchAction) async -> String {
        guard let container = OrbitStore.container else { return "Orbit isn't ready on your iPhone yet." }
        let context = container.mainContext
        let apple = AppleSync()
        var reply = "Done."
        switch action.kind {
        case .completeTask:
            if let t = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).first(where: { $0.uuid == action.id }) {
                t.complete(in: context); reply = "Done: \(t.title)"
            }
        case .toggleHabit:
            if let h = ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).first(where: { $0.uuid == action.id }) {
                h.toggle(.now); reply = h.isDone(on: .now) ? "\(h.name) done" : "\(h.name) undone"
            }
        case .capture:
            let summary = await CaptureEngine.capture(action.text, context: context)
            reply = summary.isEmpty ? "Nothing to add in that." : "Added: \(summary)"
        case .logExpense:
            let what = action.text.trimmingCharacters(in: .whitespaces).isEmpty ? "Expense" : action.text
            let t = Transaction(title: what, amount: -abs(action.amount), category: QuickParser.guessCategory(what))
            t.source = "watch"
            context.insert(t)
            SpendingAlerts.check(context: context)
            reply = "Logged \(Fmt.money(abs(action.amount))) for \(what)"
        case .ask:
            reply = await Self.ask(action.text, context: context, apple: apple)
        case .refresh:
            break
        }
        try? context.save()
        lastSent = nil
        push(context: context, apple: apple)
        Task { await CloudSync.shared.syncIfSignedIn(context: context) }
        return reply
    }

    /// Your assistant, answering from the wrist: it can act (add tasks, events, places…) and the chat continues on the phone.
    private static func ask(_ question: String, context: ModelContext, apple: AppleSync) async -> String {
        guard AIAssistant.shared.hasKey else { return "Add your API key in Orbit on your iPhone first." }
        let store = AssistantStore.shared
        let before = store.items.count
        await store.send(question + "\n\n(Asked from Apple Watch: answer in 1-3 short spoken sentences, no lists or links.)", context: context, apple: apple)
        let replies = store.items.dropFirst(before).filter { $0.role == .assistant }.map(\.text)
        let actions = store.items.dropFirst(before).filter { $0.role == .action }.map(\.text)
        if let last = replies.last { return last }
        if let error = store.error { return error }
        return actions.isEmpty ? "No answer this time." : actions.joined(separator: "\n")
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let c = OrbitStore.container { self.lastSent = nil; self.push(context: c.mainContext, apple: AppleSync()) }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in if let c = OrbitStore.container { self.lastSent = nil; self.push(context: c.mainContext, apple: AppleSync()) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let data = message[WatchAction.messageKey] as? Data
        Task { @MainActor in
            guard let action = WatchAction.from(data) else { replyHandler([WatchAction.replyKey: "Something went wrong."]); return }
            let reply = await self.handle(action)
            replyHandler([WatchAction.replyKey: reply])
        }
    }

    /// Queued actions (sent while the iPhone was out of reach).
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let data = userInfo[WatchAction.messageKey] as? Data
        Task { @MainActor in if let action = WatchAction.from(data) { _ = await self.handle(action) } }
    }
}
