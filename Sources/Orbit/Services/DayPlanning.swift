import SwiftUI
import SwiftData

/// Day plans: tomorrow's top three, chosen the evening before.
@MainActor
enum DayPlanner {
    static func plan(for day: Date, context: ModelContext) -> DayPlan? {
        let key = DayKey.key(day)
        return ((try? context.fetch(FetchDescriptor<DayPlan>(predicate: #Predicate { $0.day == key }))) ?? [])
            .max { $0.createdAt < $1.createdAt }
    }

    /// Typed-in priorities have no task, so their ticks are kept on this device.
    static func isDone(_ index: Int, of plan: DayPlan, tasks: [TaskItem]) -> Bool {
        let id = index < plan.taskUUIDs.count ? plan.taskUUIDs[index] : ""
        if !id.isEmpty, let t = tasks.first(where: { $0.uuid == id }) { return t.isDone }
        return (UserDefaults.standard.array(forKey: "planDone-\(plan.day)") as? [Int] ?? []).contains(index)
    }

    static func toggle(_ index: Int, of plan: DayPlan, tasks: [TaskItem], context: ModelContext) {
        let id = index < plan.taskUUIDs.count ? plan.taskUUIDs[index] : ""
        if !id.isEmpty, let t = tasks.first(where: { $0.uuid == id }) {
            if t.isDone { t.isDone = false; t.completedAt = nil } else { t.complete(in: context) }
            return
        }
        var done = Set(UserDefaults.standard.array(forKey: "planDone-\(plan.day)") as? [Int] ?? [])
        if done.contains(index) { done.remove(index) } else { done.insert(index) }
        UserDefaults.standard.set(Array(done), forKey: "planDone-\(plan.day)")
    }

    /// For the morning brief.
    static func briefLines(context: ModelContext) -> [String] {
        guard let p = plan(for: .now, context: context), !p.top.isEmpty else { return [] }
        var lines = ["\nThe plan the user made last night for today (their top priorities, in order):"]
        lines += p.top.enumerated().map { "\($0.offset + 1). \($0.element)" }
        if !p.note.isEmpty { lines.append("Their note: \(p.note)") }
        return lines
    }
}

/// What's being planned, shared by the form and the AI conversation.
@MainActor
final class PlanDraft: ObservableObject {
    struct Pick { var title: String; var task: TaskItem? }
    @Published var picks: [Pick] = []
    @Published var handled: Set<PersistentIdentifier> = []
    @Published var note = ""
}

/// Plan tomorrow by talking: the AI reads your leftovers, calendar and tasks and fills in the plan with tools.
@MainActor
final class PlanChat: ObservableObject {
    @Published private(set) var items: [ChatItem] = []
    @Published private(set) var busy = false
    @Published private(set) var live = ""
    @Published var error: String?

    private var messages: [[String: Any]] = []
    /// Short ids the AI uses for tasks ("L1" leftovers, "T1" other open tasks).
    private var ids: [String: TaskItem] = [:]
    var onSave: () -> Void = {}

    func greet(leftovers: [TaskItem], tomorrowEvents: Int) {
        guard items.isEmpty else { return }
        var t = "Let's set up tomorrow."
        if leftovers.isEmpty { t += " Today is all clear." } else {
            t += " You have \(leftovers.count) thing\(leftovers.count == 1 ? "" : "s") left from today: \(leftovers.prefix(3).map(\.title).joined(separator: ", "))\(leftovers.count > 3 ? "…" : "")."
        }
        t += tomorrowEvents == 0 ? " Your calendar is free." : " You have \(tomorrowEvents) event\(tomorrowEvents == 1 ? "" : "s") on the calendar."
        t += " What do you most want to get done?"
        items.append(ChatItem(role: .assistant, text: t))
        messages.append(["role": "user", "content": "(I opened Plan tomorrow.)"])
        messages.append(["role": "assistant", "content": t])
    }

    func send(_ text: String, draft: PlanDraft, context: ModelContext, apple: AppleSync) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        guard let client = ClaudeClient() else { error = "Add your Anthropic API key in Settings › AI to plan with \(AssistantName.current)."; return }
        items.append(ChatItem(role: .user, text: text))
        messages.append(["role": "user", "content": text])
        busy = true
        error = nil
        defer { busy = false; live = "" }

        for _ in 0..<6 {
            let system = prompt(draft: draft, context: context, apple: apple)
            let turn: ClaudeClient.Turn
            do {
                turn = try await client.streamTurn(system: system, messages: messages, tools: Self.tools, effort: "low") { [weak self] t in self?.live = t }
            } catch {
                self.error = error.localizedDescription
                return
            }
            live = ""
            messages.append(["role": "assistant", "content": turn.replayBlocks])
            let said = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !said.isEmpty { items.append(ChatItem(role: .assistant, text: said)) }
            guard turn.stopReason == "tool_use", !turn.toolCalls.isEmpty else { return }
            var results: [[String: Any]] = []
            var saving = false
            for call in turn.toolCalls {
                let (result, action) = run(call.name, call.input ?? [:], draft: draft, context: context)
                if let action, !items.suffix(8).contains(where: { $0.role == .action && $0.text == action }) {
                    items.append(ChatItem(role: .action, text: action, symbol: "checkmark"))
                }
                if call.name == "save_plan" { saving = true }
                results.append(["type": "tool_result", "tool_use_id": call.id, "content": result])
            }
            messages.append(["role": "user", "content": results])
            if saving { onSave(); return }
        }
    }

    private static let tools: [[String: Any]] = [
        ["name": "set_top3", "description": "Set tomorrow's top priorities (1-3, most important first). Use task_id for an existing task, or \"\" for something new.",
         "input_schema": ["type": "object", "additionalProperties": false, "required": ["items"], "properties": [
            "items": ["type": "array", "items": ["type": "object", "additionalProperties": false, "required": ["title", "task_id"],
                                                 "properties": ["title": ["type": "string"], "task_id": ["type": "string"]]]]]]],
        ["name": "update_task", "description": "Handle a task: mark it done, move it to tomorrow, or remove its date.",
         "input_schema": ["type": "object", "additionalProperties": false, "required": ["task_id", "action"], "properties": [
            "task_id": ["type": "string"], "action": ["type": "string", "enum": ["done", "tomorrow", "no_date"]]]]],
        ["name": "add_task", "description": "Create a new task, due tomorrow unless the user wants no date. Returns its task_id.",
         "input_schema": ["type": "object", "additionalProperties": false, "required": ["title", "priority", "due"], "properties": [
            "title": ["type": "string"], "priority": ["type": "integer", "description": "0 none … 3 high"],
            "due": ["type": "string", "enum": ["tomorrow", "none"]]]]],
        ["name": "set_note", "description": "Set the note for tomorrow (things to remember).",
         "input_schema": ["type": "object", "additionalProperties": false, "required": ["note"], "properties": ["note": ["type": "string"]]]],
        ["name": "save_plan", "description": "Save the plan and close, when the user says they're done or asks to save.",
         "input_schema": ["type": "object", "additionalProperties": false, "properties": [:]]],
    ]

    private func run(_ name: String, _ input: [String: Any], draft: PlanDraft, context: ModelContext) -> (String, String?) {
        let tomorrow = Date.now.startOfDay.adding(days: 1)
        func str(_ k: String) -> String { (input[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        switch name {
        case "set_top3":
            let list = (input["items"] as? [[String: Any]] ?? []).prefix(3)
            draft.picks = list.map { i in
                let id = (i["task_id"] as? String ?? "").uppercased()
                return PlanDraft.Pick(title: (i["title"] as? String ?? "").trimmingCharacters(in: .whitespaces), task: ids[id])
            }.filter { !$0.title.isEmpty }
            let top = draft.picks.map(\.title).joined(separator: " · ")
            return ("Done: the top 3 is now \(top).", "Top 3: " + top)
        case "update_task":
            guard let t = ids[str("task_id").uppercased()] else { return ("No task with that id.", nil) }
            switch str("action") {
            case "done": t.complete(in: context)
            case "tomorrow": t.due = tomorrow
            default: t.due = nil
            }
            draft.handled.insert(t.persistentModelID)
            let what = ["done": "marked done", "tomorrow": "moved to tomorrow"][str("action")] ?? "date removed"
            return ("Done: “\(t.title)” \(what).", "\(t.title): \(what)")
        case "add_task":
            let t = TaskItem(title: str("title"), due: str("due") == "none" ? nil : tomorrow,
                             priority: max(0, min(3, (input["priority"] as? NSNumber)?.intValue ?? 0)))
            t.uuid = UUID().uuidString.lowercased()
            context.insert(t)
            let id = "N\(ids.keys.filter { $0.hasPrefix("N") }.count + 1)"
            ids[id] = t
            return ("Created with task_id \(id).", "New task: \(t.title)")
        case "set_note":
            draft.note = str("note")
            return ("Done: note saved.", "Note: \(draft.note)")
        case "save_plan":
            return ("Saved.", "Plan saved")
        default:
            return ("Unknown tool.", nil)
        }
    }

    private func prompt(draft: PlanDraft, context: ModelContext, apple: AppleSync) -> String {
        let today = Date.now.startOfDay, tomorrow = today.adding(days: 1)
        let open = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isDone }
        let leftovers = open.filter { ($0.due.map { $0 < tomorrow } ?? false) && !draft.handled.contains($0.persistentModelID) }
        let others = open.filter { t in !leftovers.contains { $0 === t } }
            .sorted { ($0.due ?? .distantFuture, -$0.priority) < ($1.due ?? .distantFuture, -$1.priority) }.prefix(30)
        let news = ids.filter { $0.key.hasPrefix("N") }
        ids = news
        func line(_ id: String, _ t: TaskItem) -> String {
            ids[id] = t
            return "- \(id): \(t.title)\(t.priority > 0 ? " (priority \(t.priority))" : "")\(t.due.map { " due \(Fmt.relativeDay($0))" } ?? "")"
        }
        let events = CalEntry.merge(local: ((try? context.fetch(FetchDescriptor<EventItem>())) ?? []).filter { $0.start.isSameDay(as: tomorrow) },
                                    apple: apple.events(from: tomorrow, to: tomorrow.adding(days: 1)),
                                    google: GoogleCalendarStore.shared.events(from: tomorrow, to: tomorrow.adding(days: 1)))
        let name = (UserDefaults.standard.string(forKey: "userName") ?? "").split(separator: " ").first.map(String.init) ?? "the user"
        return """
        You are \(AssistantName.current), helping \(name) plan tomorrow (\(tomorrow.formatted(.dateTime.weekday(.wide).day().month(.wide)))) in Orbit's evening planner. They may be typing or talking out loud.
        Goal, in a short, friendly back-and-forth:
        1. Deal with what's left from today: ask, or act on what they say (update_task done / tomorrow / no_date).
        2. Understand what tomorrow needs, then set up to 3 priorities with set_top3, most important first. Use existing task ids when a priority matches a task; add_task for anything new that should be tracked.
        3. Anything to remember goes in set_note.
        Act as soon as what they said is clear; don't ask permission for each step. Every tool call takes effect immediately, so never repeat a call that already succeeded.
        If they asked you to save, call save_plan right after the other changes, in the same turn. Keep replies to 1-3 short, spoken-style sentences, one question at a time, no lists or markdown.
        Be realistic: if tomorrow is packed with events, suggest fewer or smaller priorities. When the plan looks complete, say so in a sentence and ask if they want to save; call save_plan when they agree or ask to save.

        Left from today:
        \(leftovers.isEmpty ? "(none)" : leftovers.enumerated().map { line("L\($0.offset + 1)", $0.element) }.joined(separator: "\n"))
        Other open tasks:
        \(others.isEmpty ? "(none)" : others.enumerated().map { line("T\($0.offset + 1)", $0.element) }.joined(separator: "\n"))
        \(news.isEmpty ? "" : "Tasks created in this chat:\n" + news.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value.title)" }.joined(separator: "\n"))
        Tomorrow's calendar:
        \(events.isEmpty ? "(nothing)" : events.map { "- \($0.isAllDay ? "all day" : "\(Fmt.time($0.start))–\(Fmt.time($0.end))") \($0.title)" }.joined(separator: "\n"))
        Current plan: \(draft.picks.isEmpty ? "no priorities yet" : draft.picks.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "; ")). Note: \(draft.note.isEmpty ? "none" : draft.note)
        Now: \(Date.now.formatted(.dateTime.weekday(.wide).hour().minute())).
        """
    }
}
