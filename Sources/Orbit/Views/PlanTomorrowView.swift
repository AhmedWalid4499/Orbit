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

/// "Your top 3" list for today, inside the Due today card.
struct TopThreeList: View {
    @Environment(\.modelContext) private var context
    let plan: DayPlan
    @Query private var tasks: [TaskItem]
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Your top 3", systemImage: "moon.stars.fill").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                Spacer()
                if !plan.note.isEmpty { Image(systemName: "note.text").foregroundStyle(Theme.inkMuted).help(plan.note) }
            }
            ForEach(Array(plan.top.enumerated()), id: \.offset) { i, title in
                let done = { _ = tick; return DayPlanner.isDone(i, of: plan, tasks: tasks) }()
                Button {
                    withAnimation(.snappy) { DayPlanner.toggle(i, of: plan, tasks: tasks, context: context); tick += 1 }
                } label: {
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(Theme.ui(11, weight: .bold)).foregroundStyle(Theme.stickerInk)
                            .frame(width: 20, height: 20).background(Circle().fill([Theme.lime, Theme.pink, Theme.cyan][i % 3]))
                        Text(title).font(Theme.ui(13, weight: .medium)).strikethrough(done, color: Theme.inkMuted)
                            .foregroundStyle(done ? Theme.inkMuted : Theme.ink).lineLimit(1)
                        Spacer()
                        CheckCircle(isOn: done)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
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

/// Evening routine: clear what's left today, glance at tomorrow, pick tomorrow's top three, by hand or by talking it through.
struct PlanTomorrowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }, sort: \TaskItem.createdAt) private var open: [TaskItem]
    @Query(sort: \EventItem.start) private var events: [EventItem]

    @StateObject private var draft = PlanDraft()
    @StateObject private var chat = PlanChat()
    @ObservedObject private var ai = AIAssistant.shared
    @ObservedObject private var dictation = Dictation.shared
    @ObservedObject private var speaker = Speaker.shared
    @AppStorage("assistantSpeaks") private var speaks = false
    @State private var typed = ""
    @State private var message = ""
    @State private var voiceTurn = false
    @State private var loaded = false

    private var today: Date { .now.startOfDay }
    private var tomorrow: Date { today.adding(days: 1) }

    private var leftovers: [TaskItem] {
        open.filter { ($0.due.map { $0 < tomorrow } ?? false) && !draft.handled.contains($0.persistentModelID) }
            .sorted { ($0.due ?? .now) < ($1.due ?? .now) }
    }

    private var tomorrowEntries: [CalEntry] {
        CalEntry.merge(local: events.filter { $0.start.isSameDay(as: tomorrow) }, apple: apple.events(from: tomorrow, to: tomorrow.adding(days: 1)),
                       google: GoogleCalendarStore.shared.events(from: tomorrow, to: tomorrow.adding(days: 1)))
    }

    private var candidates: [TaskItem] {
        let picked = Set(draft.picks.compactMap { $0.task?.persistentModelID })
        return open.filter { !picked.contains($0.persistentModelID) }
            .sorted {
                let a = ($0.due.map { $0 < tomorrow.adding(days: 1) } ?? false, $0.priority)
                let b = ($1.due.map { $0 < tomorrow.adding(days: 1) } ?? false, $1.priority)
                return a.0 != b.0 ? a.0 : a.1 > b.1
            }
            .prefix(14).map { $0 }
    }

    var body: some View {
        HStack(spacing: 0) {
            if ai.hasKey {
                chatPane.frame(width: 380)
                Rectangle().fill(Theme.line).frame(width: 1)
            }
            form
        }
        .frame(width: ai.hasKey ? 1040 : 640, height: 720)
        .onAppear(perform: load)
        .onDisappear { dictation.cancel(); speaker.stop() }
        .onChange(of: chat.busy) { _, busy in if !busy { replyFinished() } }
    }

    // MARK: Conversation

    private var chatPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.stickerInk)
                    .frame(width: 30, height: 30).background(Circle().fill(Theme.lime))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Talk it through").font(Theme.display(20))
                    Text("Tell \(AssistantName.current) about tomorrow").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Button {
                    speaks.toggle()
                    if !speaks { speaker.stop(); voiceTurn = false }
                } label: { Image(systemName: speaks ? "speaker.wave.2.fill" : "speaker.slash") }
                    .buttonStyle(.plain).foregroundStyle(speaks ? Theme.ink : Theme.inkMuted)
                    .help(speaks ? "Reading replies aloud" : "Read replies aloud")
            }
            .padding(18)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(chat.items) { item in bubble(item).id(item.id) }
                        if chat.busy {
                            Text(chat.live.isEmpty ? "…" : chat.live).font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary).id("live")
                        }
                        if let e = chat.error { Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12)).foregroundStyle(Theme.orange) }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 10)
                }
                .scrollIndicators(.never)
                .onChange(of: chat.items.count) { withAnimation { proxy.scrollTo(chat.items.last?.id, anchor: .bottom) } }
                .onChange(of: chat.live) { proxy.scrollTo("live", anchor: .bottom) }
            }
            VStack(alignment: .leading, spacing: 6) {
                if let e = dictation.error { Text(e).font(Theme.ui(11)).foregroundStyle(Theme.orange) }
                HStack(spacing: 8) {
                    if dictation.listening {
                        Text(dictation.text.isEmpty ? "Listening…" : dictation.text).font(Theme.ui(14))
                            .foregroundStyle(dictation.text.isEmpty ? Theme.inkMuted : Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1...5)
                    } else {
                        TextField("Tomorrow I need to…", text: $message, axis: .vertical)
                            .textFieldStyle(.plain).font(Theme.ui(14)).lineLimit(1...5)
                            .onSubmit { talk(message, voice: false) }
                    }
                    MicButton { heard in talk(heard, voice: true) }.disabled(chat.busy)
                    Button { talk(message, voice: false) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.onInverse)
                            .frame(width: 30, height: 30).background(Circle().fill(Theme.inverse))
                    }
                    .buttonStyle(.plain)
                    .disabled(chat.busy || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            .padding(14)
        }
        .background(Theme.canvas)
    }

    @ViewBuilder
    private func bubble(_ item: ChatItem) -> some View {
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(item.text).font(Theme.ui(14)).foregroundStyle(Theme.onInverse)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.inverse))
            }
        case .assistant:
            Text(item.text).font(Theme.ui(14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .action:
            Label(item.text, systemImage: "checkmark.circle.fill").font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
        }
    }

    private func talk(_ text: String, voice: Bool) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { voiceTurn = false; return }
        voiceTurn = voice
        message = ""
        speaker.stop()
        Task { await chat.send(t, draft: draft, context: context, apple: apple) }
    }

    private func replyFinished() {
        guard speaks, chat.error == nil, let last = chat.items.last(where: { $0.role == .assistant }) else { voiceTurn = false; return }
        speaker.speak(last.text) {
            guard voiceTurn else { return }
            Task { await dictation.start { heard in talk(heard, voice: true) } }
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan tomorrow").font(Theme.display(30))
                Text(tomorrow.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            }
            .padding([.horizontal, .top], 26).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("What's left from today") {
                        if leftovers.isEmpty {
                            Text("All clear ✨").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                        }
                        ForEach(leftovers) { t in
                            HStack(spacing: 8) {
                                Text(t.title).font(Theme.ui(13, weight: .medium)).lineLimit(1)
                                if t.isOverdue { Text("overdue").font(Theme.ui(10, weight: .semibold)).foregroundStyle(Theme.critical) }
                                Spacer()
                                small("Done", "checkmark") { t.complete(in: context); draft.handled.insert(t.persistentModelID) }
                                small("Tomorrow", "arrow.right") { t.due = tomorrow; draft.handled.insert(t.persistentModelID) }
                                small("No date", "calendar.badge.minus") { t.due = nil; draft.handled.insert(t.persistentModelID) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                        }
                    }

                    section("Tomorrow's calendar") {
                        if tomorrowEntries.isEmpty {
                            Text("Nothing on the calendar. A good day for deep work.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                        }
                        FlowLayout(spacing: 6) {
                            ForEach(tomorrowEntries) { e in
                                HStack(spacing: 6) {
                                    Circle().fill(e.tint).frame(width: 7, height: 7)
                                    Text(e.isAllDay ? e.title : "\(Fmt.time(e.start)) \(e.title)").font(Theme.ui(12, weight: .medium)).lineLimit(1)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Theme.card))
                            }
                        }
                    }

                    section("Your top 3 for tomorrow") {
                        VStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { i in
                                HStack(spacing: 10) {
                                    Text("\(i + 1)").font(Theme.ui(12, weight: .bold)).foregroundStyle(Theme.stickerInk)
                                        .frame(width: 24, height: 24).background(Circle().fill([Theme.lime, Theme.pink, Theme.cyan][i]))
                                    if i < draft.picks.count {
                                        Text(draft.picks[i].title).font(Theme.ui(14, weight: .medium)).lineLimit(1)
                                        Spacer()
                                        Button { draft.picks.remove(at: i) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.inkMuted)
                                    } else {
                                        Text(i == draft.picks.count ? "Pick a task below, type one, or just tell \(AssistantName.current)" : "—")
                                            .font(Theme.ui(13)).foregroundStyle(Theme.inkMuted)
                                        Spacer()
                                    }
                                }
                                .padding(.horizontal, 12).frame(height: 40)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                            }
                        }
                        .animation(.snappy, value: draft.picks.map(\.title))
                        if draft.picks.count < 3 {
                            HStack(spacing: 8) {
                                Image(systemName: "plus").foregroundStyle(Theme.inkMuted)
                                TextField("Type a priority and press Return", text: $typed).textFieldStyle(.plain).font(Theme.ui(13))
                                    .onSubmit {
                                        let t = typed.trimmingCharacters(in: .whitespaces)
                                        if !t.isEmpty, draft.picks.count < 3 { draft.picks.append(.init(title: t, task: nil)) }
                                        typed = ""
                                    }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                            FlowLayout(spacing: 6) {
                                ForEach(candidates) { t in
                                    Button { if draft.picks.count < 3 { draft.picks.append(.init(title: t.title, task: t)) } } label: {
                                        HStack(spacing: 5) {
                                            Circle().fill(t.area.color).frame(width: 7, height: 7)
                                            Text(t.title).lineLimit(1)
                                            if t.priority > 0 { Text(String(repeating: "!", count: t.priority)).fontWeight(.heavy) }
                                        }
                                        .font(Theme.ui(12, weight: .medium))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Capsule().fill(Theme.card))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    section("Anything to remember?") {
                        TextField("e.g. Bring the charger, call the bank before 10", text: $draft.note).textFieldStyle(.roundedBorder).font(Theme.ui(13))
                    }
                }
                .padding(.horizontal, 26).padding(.bottom, 10)
            }
            .scrollIndicators(.never)

            HStack {
                Text("Your top 3 shows on Today and in tomorrow's morning brief.").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button("Save plan", action: save).buttonStyle(PrimaryButtonStyle()).frame(width: 120).keyboardShortcut(.defaultAction)
                    .disabled(draft.picks.isEmpty && draft.note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 26).padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.ui(15, weight: .semibold))
            content()
        }
    }

    private func small(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Label(title, systemImage: symbol).font(Theme.ui(11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(Theme.canvas))
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        chat.onSave = { save() }
        chat.greet(leftovers: leftovers, tomorrowEvents: tomorrowEntries.count)
        guard let p = DayPlanner.plan(for: tomorrow, context: context) else { return }
        draft.note = p.note
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        draft.picks = p.top.enumerated().map { i, title in
            let id = i < p.taskUUIDs.count ? p.taskUUIDs[i] : ""
            return .init(title: title, task: id.isEmpty ? nil : all.first { $0.uuid == id })
        }
    }

    private func save() {
        let p = DayPlanner.plan(for: tomorrow, context: context) ?? { let p = DayPlan(day: DayKey.key(tomorrow)); context.insert(p); return p }()
        for pick in draft.picks {
            guard let t = pick.task else { continue }
            if t.uuid.isEmpty { t.uuid = UUID().uuidString.lowercased() }
            if (t.due ?? .distantPast) < tomorrow { t.due = tomorrow }
        }
        p.top = draft.picks.map(\.title)
        p.taskUUIDs = draft.picks.map { $0.task?.uuid ?? "" }
        p.note = draft.note.trimmingCharacters(in: .whitespaces)
        p.createdAt = .now
        try? context.save()
        dismiss()
    }
}
