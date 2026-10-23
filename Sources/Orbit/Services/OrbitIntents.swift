import AppIntents
import SwiftData
import Foundation

// Siri and Shortcuts. These run inside Orbit; the build script extracts their metadata
// (Metadata.appintents) so macOS knows about them. Phrases say the app's name, e.g. "Add to Orbit".

@MainActor
private func orbitContext() throws -> ModelContext {
    guard let container = OrbitStore.container else { throw IntentError.message("Orbit isn't ready yet. Try again in a moment.") }
    return container.mainContext
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case message(String)
    var localizedStringResource: LocalizedStringResource {
        switch self { case .message(let m): LocalizedStringResource(stringLiteral: m) }
    }
}

struct AddToOrbitIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Orbit"
    static let description = IntentDescription("Add a task, event, expense, note or journal line. Orbit works out which from what you say, e.g. “dentist Thursday at 3” or “$12 lunch”.")

    @Parameter(title: "What", requestValueDialog: "What should I add?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$text) to Orbit") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let summary = await CaptureEngine.capture(text, context: try orbitContext())
        guard !summary.isEmpty else { throw IntentError.message("I couldn't find anything to add in that.") }
        return .result(value: summary, dialog: "Added: \(summary)")
    }
}

struct TodayIntent: AppIntent {
    static let title: LocalizedStringResource = "What's on Today"
    static let description = IntentDescription("Hear your events, tasks due and habits left for today.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let context = try orbitContext()
        let today = Date.now.startOfDay, tomorrow = today.adding(days: 1)
        let local = ((try? context.fetch(FetchDescriptor<EventItem>())) ?? []).filter { $0.start >= .now && $0.start < tomorrow }
        let apple = AppleSync()
        let events = CalEntry.merge(local: local, apple: apple.events(from: .now, to: tomorrow),
                                    google: GoogleCalendarStore.shared.events(from: .now, to: tomorrow))
        let tasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isDone && ($0.due.map { $0 < tomorrow } ?? false) }
        let habits = ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).filter { !$0.isDone(on: today) }

        var parts: [String] = []
        if events.isEmpty { parts.append("Nothing else on your calendar today.") } else {
            let list = events.prefix(3).map { $0.isAllDay ? $0.title : "\($0.title) at \(Fmt.time($0.start))" }
            parts.append("Coming up: \(list.joined(separator: ", "))\(events.count > 3 ? ", and \(events.count - 3) more" : "").")
        }
        parts.append(tasks.isEmpty ? "No tasks due." : "\(tasks.count) task\(tasks.count == 1 ? "" : "s") due, starting with \(tasks.sorted { $0.priority > $1.priority }[0].title).")
        if !habits.isEmpty { parts.append("Habits left: \(habits.prefix(3).map(\.name).joined(separator: ", ")).") }
        let text = parts.joined(separator: " ")
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct AskOrbitIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Orbit"
    static let description = IntentDescription("Ask your Orbit assistant a question about your day, money, plans or anything else.")

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let context = try orbitContext()
        guard let client = ClaudeClient() else { throw IntentError.message("Add your Anthropic API key in Orbit's Settings first.") }
        let system = """
        You are \(AssistantName.current), the user's assistant in Orbit, answering through Siri or Shortcuts. Reply in 1-3 short, spoken-style sentences, plain text, no lists or markdown.
        Use the user's data below when it helps.

        \(AIAssistant.snapshot(context: context, apple: AppleSync()))
        """
        let reply = try await client.stream(system: system, messages: [["role": "user", "content": question]], effort: "low", onText: { _ in })
        return .result(value: reply.text, dialog: IntentDialog(stringLiteral: reply.text))
    }
}

struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log an Expense"
    static let description = IntentDescription("Add money you spent to Orbit.")

    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "What for", default: "Expense") var what: String

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$amount) for \(\.$what)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try orbitContext()
        let t = Transaction(title: what, amount: -abs(amount), category: QuickParser.guessCategory(what))
        context.insert(t)
        try? context.save()
        return .result(dialog: "Logged \(Fmt.money(-abs(amount))) for \(what).")
    }
}

/// For a Shortcuts automation: "When I get a message from <bank>" → Log Bank Message with the message's text.
struct LogBankMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Bank Message"
    static let description = IntentDescription("Reads a bank or card SMS and, if money was spent or received, adds it to Money. OTP codes, declined payments and balance updates are ignored, and the same message is never logged twice.")

    @Parameter(title: "Message", requestValueDialog: "Paste the bank message") var message: String
    @Parameter(title: "Sender", default: "") var sender: String

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$message) from \(\.$sender) in Orbit") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        // If Shortcuts couldn't read the sender it hands over the whole message instead: treat it as unknown.
        let from = sender.count > 40 || sender == message ? "" : sender
        let result = await BankMessages.log(message: message, sender: from, context: try orbitContext())
        return .result(value: result, dialog: IntentDialog(stringLiteral: result))
    }
}

/// For a Shortcuts automation: "When I tap any Wallet card" → Log Card Payment with Amount, Merchant and Card.
struct LogCardPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Card Payment"
    static let description = IntentDescription("Adds an Apple Pay payment to Money. Use it in a Wallet “Transaction” automation and pass the Amount, Merchant and Card it provides.")

    @Parameter(title: "Amount") var amount: String
    @Parameter(title: "Merchant", default: "") var merchant: String
    @Parameter(title: "Card", default: "") var card: String

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$amount) at \(\.$merchant) paid with \(\.$card)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let result = await BankMessages.logCardTap(amount: amount, merchant: merchant, card: card, context: try orbitContext())
        return .result(value: result, dialog: IntentDialog(stringLiteral: result))
    }
}

struct OrbitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToOrbitIntent(), phrases: [
            "Add to \(.applicationName)", "Add something to \(.applicationName)", "Capture in \(.applicationName)",
        ], shortTitle: "Add to Orbit", systemImageName: "plus.circle")
        AppShortcut(intent: TodayIntent(), phrases: [
            "What's on today in \(.applicationName)", "What's my day in \(.applicationName)", "\(.applicationName) today",
        ], shortTitle: "What's on today", systemImageName: "sun.max")
        AppShortcut(intent: AskOrbitIntent(), phrases: [
            "Ask \(.applicationName)", "Ask \(.applicationName) a question",
        ], shortTitle: "Ask Orbit", systemImageName: "sparkles")
        AppShortcut(intent: LogExpenseIntent(), phrases: [
            "Log an expense in \(.applicationName)", "Add an expense to \(.applicationName)",
        ], shortTitle: "Log expense", systemImageName: "creditcard")
        AppShortcut(intent: LogBankMessageIntent(), phrases: [
            "Log a bank message in \(.applicationName)",
        ], shortTitle: "Log bank message", systemImageName: "message.badge")
        AppShortcut(intent: LogCardPaymentIntent(), phrases: [
            "Log a card payment in \(.applicationName)",
        ], shortTitle: "Log card payment", systemImageName: "wave.3.right.circle")
    }
}
