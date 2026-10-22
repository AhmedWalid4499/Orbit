import Foundation
import SwiftUI
import SwiftData

/// A line in the assistant chat as the user sees it.
struct ChatItem: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant, action }
    enum Undo: Codable, Equatable { case models([PersistentIdentifier]), budget(Double) }
    var id = UUID()
    var role: Role
    var text: String
    var symbol: String = ""
    var undo: Undo? = nil
    var undone = false
}

/// Claude as a general assistant that can act inside Orbit (create tasks, habits, events, notes,
/// expenses; add books) through tools. The conversation is kept in a file and replayed append-only.
@MainActor
final class AssistantStore: ObservableObject {
    static let shared = AssistantStore()

    @Published private(set) var items: [ChatItem] = []
    @Published private(set) var busy = false
    @Published private(set) var revealed = ""      // text of the reply being written, shown at a calm pace
    @Published var error: String?

    private var system = ""
    private var messages: [[String: Any]] = []
    private var received = ""
    private var streamDone = true
    private let fileURL = URL.applicationSupportDirectory.appending(path: "Orbit/assistant.json")

    private init() { load() }

    // MARK: Conversation

    func newChat() {
        items = []
        messages = []
        system = ""
        error = nil
        save()
    }

    func send(_ text: String, context: ModelContext, apple: AppleSync) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        guard let client = ClaudeClient() else { error = "Add your Anthropic API key in Settings › AI first."; return }
        if system.isEmpty { system = Self.systemPrompt(context: context, apple: apple) }

        items.append(ChatItem(role: .user, text: text))
        messages.append(["role": "user", "content": text])
        save()
        busy = true
        error = nil
        defer { busy = false; save() }

        for _ in 0..<8 {
            received = ""
            revealed = ""
            streamDone = false
            let reveal = Task { await revealLoop() }
            let turn: ClaudeClient.Turn
            do {
                turn = try await client.streamTurn(system: system, messages: messages, tools: AssistantTools.definitions,
                                                   effort: "medium") { [weak self] t in self?.received = t }
            } catch {
                streamDone = true
                reveal.cancel()
                revealed = ""
                self.error = error.localizedDescription
                return
            }
            streamDone = true
            await reveal.value
            revealed = ""
            messages.append(["role": "assistant", "content": turn.replayBlocks])
            if !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(ChatItem(role: .assistant, text: turn.text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }

            let calls = turn.toolCalls
            guard turn.stopReason == "tool_use", !calls.isEmpty else {
                if turn.stopReason == "max_tokens" { error = "\(AssistantName.current)'s reply was cut off. Ask it to continue." }
                return
            }
            var results: [[String: Any]] = []
            for call in calls {
                let outcome: AssistantTools.Outcome
                if let input = call.input {
                    outcome = await AssistantTools.run(call.name, input: input, context: context, apple: apple)
                } else {
                    outcome = .init(result: "INVALID_JSON: the tool input wasn't valid JSON. Call the tool again.", isError: true)
                }
                if let action = outcome.action { items.append(action) }
                results.append(["type": "tool_result", "tool_use_id": call.id, "content": outcome.result, "is_error": outcome.isError])
            }
            try? context.save()
            messages.append(["role": "user", "content": results])
            save()
        }
    }

    /// Reveals streamed text a few characters at a time so replies read calmly.
    private func revealLoop() async {
        while !Task.isCancelled {
            if revealed.count < received.count {
                let next = received.dropFirst(revealed.count).prefix(3)
                revealed += next
                try? await Task.sleep(for: .milliseconds(next.contains(where: { ".?!\n".contains($0) }) ? 160 : 22))
            } else if streamDone {
                return
            } else {
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    func undo(_ item: ChatItem, context: ModelContext) {
        guard let i = items.firstIndex(of: item), let undo = item.undo, !item.undone else { return }
        switch undo {
        case .models(let ids):
            for id in ids { if let m = context.model(for: id) as (any PersistentModel)? { context.delete(m) } }
        case .budget(let previous):
            UserDefaults.standard.set(previous, forKey: "monthlyBudget")
        }
        try? context.save()
        items[i].undone = true
        // Let Claude know, so it doesn't assume the thing still exists.
        messages.append(["role": "user", "content": "(I undid this: \(item.text))"])
        messages.append(["role": "assistant", "content": "Got it."])
        save()
    }

    // MARK: Persistence

    private struct Saved: Codable {
        var system: String
        var messages: Data
        var items: [ChatItem]
    }

    private func save() {
        let saved = Saved(system: system, messages: (try? JSONSerialization.data(withJSONObject: messages)) ?? Data(), items: items)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        system = saved.system
        messages = (try? JSONSerialization.jsonObject(with: saved.messages) as? [[String: Any]]) ?? []
        items = saved.items
        // A conversation saved mid tool-call can't be continued; start fresh rather than send a broken history.
        if let last = messages.last, last["role"] as? String == "assistant",
           (last["content"] as? [[String: Any]])?.contains(where: { $0["type"] as? String == "tool_use" }) == true {
            newChat()
        }
    }

    // MARK: Prompt

    static func systemPrompt(context: ModelContext, apple: AppleSync) -> String {
        let name = (UserDefaults.standard.string(forKey: "userName") ?? NSFullUserName()).split(separator: " ").first.map(String.init) ?? "the user"
        return """
        You are \(AssistantName.current), \(name)'s personal assistant inside Orbit (you're built on Claude, by Anthropic), their life-organizer app on the Mac. You can talk things through and you can act in the app with tools: create tasks, events, habits, notes and transactions, add books to their reading list, set the monthly budget, and look up their data.

        How to work:
        - When \(name) wants something done, or clearly would benefit from it, just do it with the tools; no need to ask permission for creating things (each action shows an Undo button). Then say briefly what you did.
        - When they're talking about a struggle ("I can't read every day"), first acknowledge it, then suggest something small and realistic and set it up (e.g. a habit with a modest weekly target, maybe a reminder task), unless they only want to talk.
        - Book recommendations: suggest 3-5 real, well-known books with one line each on why, and add them to their To read list under a category that fits the topic (e.g. "Japanese culture"), unless they ask only for ideas. Check list_books first so you don't recommend books they already have.
        - Bucket list: when they mention something they dream of doing someday (travel, experiences, skills), offer to add it, or add it if they ask.
        - Use get_overview or get_money_summary when you need their current data instead of guessing.
        - Dates: resolve "tomorrow", "next Friday" from the current date below. Use 24-hour times in tool inputs.
        - Style: warm, calm, concise. Short paragraphs; simple bullets with "•" when listing. Never more than one question at a time.

        Current date and time: \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())) (\(TimeZone.current.identifier)). Currency: \(Fmt.currencyCode).
        """
    }
}

/// What the user calls their AI ("Ask" unless they rename it in Settings › AI).
enum AssistantName {
    static var current: String {
        let n = (UserDefaults.standard.string(forKey: "assistantName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Ask" : n
    }
}

// MARK: - Tools

@MainActor
enum AssistantTools {
    struct Outcome {
        var result: String
        var isError = false
        var action: ChatItem? = nil
    }

    static let habitSymbols = ["checkmark", "figure.run", "book.fill", "drop.fill", "bed.double.fill", "leaf.fill", "brain.head.profile",
                               "creditcard", "fork.knife", "dumbbell.fill", "pencil", "moon.stars.fill", "phone.down.fill", "sun.max.fill",
                               "music.note", "heart.fill"]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String]? = nil) -> [String: Any] {
        [
            "name": name,
            "description": description,
            // Inputs stream as they're written; run() validates every field before acting.
            "eager_input_streaming": true,
            "input_schema": ["type": "object", "properties": properties, "required": required ?? Array(properties.keys),
                             "additionalProperties": false],
        ]
    }

    static var definitions: [[String: Any]] {
        let areas = Area.allCases.map(\.rawValue)
        return [
            tool("get_overview", "Today's events, tasks, habits and streaks, reading shelves and budget. Use before planning or advising.", [:]),
            tool("get_money_summary", "Spending by category and merchant for the last three months, subscriptions and bills due.", [:]),
            tool("list_books", "Books in the user's library, filtered by shelf.", [
                "shelf": ["type": "string", "enum": ["all", "reading", "toRead", "read", "dnf"]],
            ]),
            tool("create_task", "Create a task. due_date yyyy-MM-dd or empty for no date.", [
                "title": ["type": "string"], "area": ["type": "string", "enum": areas], "due_date": ["type": "string"],
                "priority": ["type": "integer", "description": "0 none, 1 low, 2 medium, 3 high"],
                "repeat": ["type": "string", "enum": Recurrence.allCases.map(\.rawValue)], "notes": ["type": "string"],
            ]),
            tool("create_event", "Add an event to the calendar. start is local time yyyy-MM-ddTHH:mm.", [
                "title": ["type": "string"], "start": ["type": "string"], "duration_minutes": ["type": "integer"],
                "area": ["type": "string", "enum": areas],
            ]),
            tool("create_habit", "Create a habit to track. Keep targets realistic.", [
                "name": ["type": "string"], "symbol": ["type": "string", "enum": habitSymbols], "area": ["type": "string", "enum": areas],
                "target_per_week": ["type": "integer", "description": "1-7 days a week"],
            ]),
            tool("add_books", "Add books to the reading list. category is optional (empty string for none) and is created if missing.", [
                "books": ["type": "array", "items": [
                    "type": "object",
                    "properties": ["title": ["type": "string"], "author": ["type": "string"],
                                   "shelf": ["type": "string", "enum": ["toRead", "reading", "read"]], "category": ["type": "string"]],
                    "required": ["title", "author", "shelf", "category"], "additionalProperties": false,
                ]],
            ]),
            tool("create_note", "Save a note.", ["title": ["type": "string"], "body": ["type": "string"]]),
            tool("add_document", "Track a document or warranty with an expiry date so Orbit reminds the user. expires yyyy-MM-dd or empty.", [
                "title": ["type": "string"], "kind": ["type": "string", "enum": DocKind.allCases.map(\.rawValue)], "expires": ["type": "string"],
            ]),
            tool("add_subscription", "Track a subscription. amount per charge in the home currency; next_date yyyy-MM-dd or empty.", [
                "name": ["type": "string"], "amount": ["type": "number"],
                "cycle": ["type": "string", "enum": BillingCycle.allCases.map(\.rawValue)],
                "status": ["type": "string", "enum": ["active", "trial", "cancelled"]], "next_date": ["type": "string"],
            ]),
            tool("add_bucket_item", "Add something to the user's bucket list (things they want to do in life). target_date yyyy-MM-dd or empty.", [
                "title": ["type": "string"], "kind": ["type": "string", "enum": BucketKind.allCases.map(\.rawValue)],
                "notes": ["type": "string"], "target_date": ["type": "string"],
                "excitement": ["type": "integer", "description": "1 nice to do, 2 really want to, 3 can't wait"],
            ]),
            tool("add_transaction", "Log money spent or received. date yyyy-MM-dd.", [
                "title": ["type": "string"], "amount": ["type": "number", "description": "positive number in the home currency"],
                "kind": ["type": "string", "enum": ["expense", "income"]], "category": ["type": "string", "enum": MoneyCategory.all],
                "date": ["type": "string"],
            ]),
            tool("set_monthly_budget", "Change the monthly spending budget (home currency).", ["amount": ["type": "number"]]),
        ]
    }

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let dayTime: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
    }()

    static func run(_ name: String, input: [String: Any], context: ModelContext, apple: AppleSync) async -> Outcome {
        func str(_ k: String) -> String { (input[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func num(_ k: String) -> Double { (input[k] as? NSNumber)?.doubleValue ?? 0 }
        func area(_ k: String) -> Area { Area(rawValue: str(k)) ?? .personal }

        switch name {
        case "get_overview":
            return Outcome(result: overview(context: context, apple: apple))

        case "get_money_summary":
            return Outcome(result: MoneyCoach.summary(context: context))

        case "list_books":
            let shelf = str("shelf")
            let books = ((try? context.fetch(FetchDescriptor<Book>())) ?? []).filter { shelf == "all" || $0.statusRaw == shelf }
            if books.isEmpty { return Outcome(result: "No books on that shelf.") }
            return Outcome(result: books.prefix(150).map {
                "\($0.title) — \($0.author) [\($0.status.title)\($0.categories.isEmpty ? "" : "; " + $0.categories.joined(separator: ", "))]"
            }.joined(separator: "\n"))

        case "create_task":
            let title = str("title")
            guard !title.isEmpty else { return Outcome(result: "title is required", isError: true) }
            let t = TaskItem(title: title, area: area("area"), due: day.date(from: str("due_date")),
                             priority: max(0, min(3, Int(num("priority")))), notes: str("notes"),
                             recurrence: Recurrence(rawValue: str("repeat")) ?? .none)
            context.insert(t)
            let when = t.due.map { " · due \(Fmt.relativeDay($0))" } ?? ""
            return Outcome(result: "Created task.", action: ChatItem(role: .action, text: "Task “\(title)”\(when)", symbol: "checklist",
                                                                    undo: .models([t.persistentModelID])))

        case "create_event":
            guard let start = dayTime.date(from: str("start")) else { return Outcome(result: "start must be yyyy-MM-ddTHH:mm", isError: true) }
            let minutes = max(5, Int(num("duration_minutes")))
            let e = EventItem(title: str("title"), start: start, end: start.adding(minutes: minutes), area: area("area"))
            context.insert(e)
            return Outcome(result: "Added event.", action: ChatItem(role: .action,
                text: "Event “\(e.title)” · \(Fmt.relativeDay(start)) \(Fmt.time(start))", symbol: "calendar", undo: .models([e.persistentModelID])))

        case "create_habit":
            guard !str("name").isEmpty else { return Outcome(result: "name is required", isError: true) }
            let h = Habit(name: str("name"), symbol: habitSymbols.contains(str("symbol")) ? str("symbol") : "checkmark",
                          area: Area(rawValue: str("area")) ?? .health, targetPerWeek: max(1, min(7, Int(num("target_per_week")))))
            context.insert(h)
            return Outcome(result: "Created habit.", action: ChatItem(role: .action,
                text: "Habit “\(h.name)” · \(h.targetPerWeek)× a week", symbol: "flame.fill", undo: .models([h.persistentModelID])))

        case "add_books":
            let list = input["books"] as? [[String: Any]] ?? []
            guard !list.isEmpty else { return Outcome(result: "books is empty", isError: true) }
            // Look up covers and details on Open Library (a few at a time).
            var imported: [ImportedBook] = []
            await withTaskGroup(of: ImportedBook.self) { group in
                for b in list.prefix(12) {
                    group.addTask {
                        let title = (b["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                        let author = (b["author"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                        var item = ImportedBook(title: title, author: author)
                        item.status = ReadingStatus(rawValue: b["shelf"] as? String ?? "") ?? .toRead
                        let category = (b["category"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                        if !category.isEmpty { item.categories = [category] }
                        if let hit = try? await OpenLibrary.search("\(title) \(author)").first {
                            item.coverURL = hit.coverURL; item.pages = hit.pages; item.year = hit.year; item.isbn = hit.isbn
                            item.externalID = "openlibrary:\(hit.id)"
                        }
                        if item.status == .read { item.progress = 1; item.finishedAt = .now }
                        return item
                    }
                }
                for await item in group { imported.append(item) }
            }
            let before = Set(((try? context.fetch(FetchDescriptor<Book>())) ?? []).map(\.persistentModelID))
            let out = BookLibrary.merge(imported, source: "openlibrary", category: nil, context: context)
            let added = ((try? context.fetch(FetchDescriptor<Book>())) ?? []).filter { !before.contains($0.persistentModelID) }
            let names = imported.map(\.title).joined(separator: ", ")
            return Outcome(result: "Added \(out.added) new, \(out.updated) were already in the library.",
                           action: ChatItem(role: .action, text: "Added to reading list: \(names)", symbol: "books.vertical.fill",
                                            undo: added.isEmpty ? nil : .models(added.map(\.persistentModelID))))

        case "add_document":
            guard !str("title").isEmpty else { return Outcome(result: "title is required", isError: true) }
            let d = DocItem(title: str("title"), kind: DocKind(rawValue: str("kind")) ?? .other, expires: day.date(from: str("expires")))
            context.insert(d)
            return Outcome(result: "Saved.", action: ChatItem(role: .action,
                text: "Document “\(d.title)”\(d.expires.map { " · expires \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")",
                symbol: "doc.text.fill", undo: .models([d.persistentModelID])))

        case "add_subscription":
            guard !str("name").isEmpty else { return Outcome(result: "name is required", isError: true) }
            let s = Subscription(name: str("name"), amount: abs(num("amount")), cycle: BillingCycle(rawValue: str("cycle")) ?? .monthly)
            s.status = ["active", "trial", "cancelled"].contains(str("status")) ? str("status") : "active"
            s.nextDate = day.date(from: str("next_date"))
            if s.status == "trial" { s.trialEnds = s.nextDate }
            context.insert(s)
            return Outcome(result: "Saved.", action: ChatItem(role: .action, text: "Subscription “\(s.name)” \(Fmt.money(s.amount)) \(s.cycle.title.lowercased())",
                                                             symbol: "repeat", undo: .models([s.persistentModelID])))

        case "add_bucket_item":
            guard !str("title").isEmpty else { return Outcome(result: "title is required", isError: true) }
            let b = BucketItem(title: str("title"), kind: BucketKind(rawValue: str("kind")) ?? .other, notes: str("notes"),
                               targetDate: day.date(from: str("target_date")), excitement: max(1, min(3, Int(num("excitement")))))
            context.insert(b)
            return Outcome(result: "Added to bucket list.", action: ChatItem(role: .action, text: "Bucket list: “\(b.title)”",
                                                                            symbol: "mountain.2.fill", undo: .models([b.persistentModelID])))

        case "create_note":
            let n = Note(title: str("title"), body: str("body"))
            context.insert(n)
            return Outcome(result: "Saved note.", action: ChatItem(role: .action, text: "Note “\(n.title)”", symbol: "doc.text",
                                                                  undo: .models([n.persistentModelID])))

        case "add_transaction":
            let amount = abs(num("amount"))
            guard amount > 0 else { return Outcome(result: "amount must be positive", isError: true) }
            let income = str("kind") == "income"
            let t = Transaction(title: str("title"), amount: income ? amount : -amount,
                                category: income ? "Income" : (MoneyCategory.all.contains(str("category")) ? str("category") : "General"),
                                date: day.date(from: str("date")).map { $0.adding(minutes: 720) } ?? .now)
            context.insert(t)
            return Outcome(result: "Logged.", action: ChatItem(role: .action, text: "\(income ? "Income" : "Expense") “\(t.title)” \(Fmt.money(t.amount, signed: true))",
                                                              symbol: "creditcard", undo: .models([t.persistentModelID])))

        case "set_monthly_budget":
            let amount = num("amount")
            guard amount > 0 else { return Outcome(result: "amount must be positive", isError: true) }
            let previous = UserDefaults.standard.object(forKey: "monthlyBudget") as? Double ?? 2000
            UserDefaults.standard.set(amount, forKey: "monthlyBudget")
            return Outcome(result: "Budget set.", action: ChatItem(role: .action, text: "Monthly budget → \(Fmt.money(amount))",
                                                                  symbol: "target", undo: .budget(previous)))

        default:
            return Outcome(result: "Unknown tool \(name)", isError: true)
        }
    }

    private static func overview(context: ModelContext, apple: AppleSync) -> String {
        var text = AIAssistant.snapshot(context: context, apple: apple)
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let cats = ((try? context.fetch(FetchDescriptor<BookCategory>())) ?? []).map(\.name)
        let reading = books.filter { $0.status == .reading }.map { "\($0.title) (\(Int($0.progress * 100))%)" }
        text += "\n\nReading: \(reading.isEmpty ? "nothing in progress" : reading.joined(separator: ", ")). "
        text += "To read: \(books.filter { $0.status == .toRead }.count). Read: \(books.filter { $0.status == .read }.count). "
        let bucket = ((try? context.fetch(FetchDescriptor<BucketItem>())) ?? [])
        text += "Bucket list: \(bucket.filter { !$0.isDone }.prefix(20).map(\.title).joined(separator: "; ")) (\(bucket.filter(\.isDone).count) done). "
        text += "\n"
        let docs = ((try? context.fetch(FetchDescriptor<DocItem>())) ?? []).filter { ($0.daysLeft ?? 999) <= 90 }
        text += "Documents expiring within 90 days: \(docs.isEmpty ? "none" : docs.map { "\($0.title) (\($0.daysLeft ?? 0) days)" }.joined(separator: ", ")). "
        let subs = ((try? context.fetch(FetchDescriptor<Subscription>())) ?? []).filter { $0.status != "cancelled" }
        text += "Subscriptions: \(subs.count), \(Fmt.money(SubscriptionTracker.monthlyTotal(subs))) a month (\(subs.map { "\($0.name) \(Fmt.money($0.amount))/\($0.cycle.rawValue)" }.prefix(15).joined(separator: ", "))). "
        text += "Book categories: \(cats.isEmpty ? "none" : cats.joined(separator: ", ")). Yearly goal: \(UserDefaults.standard.integer(forKey: "readingGoal") == 0 ? 24 : UserDefaults.standard.integer(forKey: "readingGoal")) books."
        return text
    }
}
