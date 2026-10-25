import SwiftUI
import SwiftData

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
    @State private var phoneTalking = true

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
        Group {
            #if os(iOS)
            VStack(spacing: 0) {
                if ai.hasKey {
                    Picker("", selection: $phoneTalking) { Text("Talk it through").tag(true); Text("Plan").tag(false) }
                        .pickerStyle(.segmented).padding(.horizontal, 16).padding(.top, 14)
                }
                if ai.hasKey && phoneTalking { chatPane } else { form }
            }
            #else
            HStack(spacing: 0) {
                if ai.hasKey {
                    chatPane.frame(width: 380)
                    Rectangle().fill(Theme.line).frame(width: 1)
                }
                form
            }
            #endif
        }
        .sheetFrame(width: ai.hasKey ? 1040 : 640, height: 720)
        .onAppear(perform: load)
        .onDisappear { dictation.cancel(); speaker.stop() }
        .onChange(of: chat.busy) { _, busy in if !busy { replyFinished() } }
    }

    // MARK: Conversation

    private var chatPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AssistantAvatar(size: 30, busy: chat.busy)
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
            .padding([.horizontal, .top], Platform.isPhone ? 18 : 26).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("What's left from today") {
                        if leftovers.isEmpty {
                            Text("All clear ✨").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                        }
                        ForEach(leftovers) { t in
                            // Side by side when there's room; on a phone the title gets its own line, the actions below.
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    leftoverTitle(t).lineLimit(1)
                                    Spacer()
                                    leftoverActions(t)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    leftoverTitle(t).lineLimit(2)
                                    leftoverActions(t)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                                        Text(i == draft.picks.count ? (Platform.isPhone ? "Pick a task below or type one" : "Pick a task below, type one, or just tell \(AssistantName.current)") : "—")
                                            .font(Theme.ui(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
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
                .padding(.horizontal, Platform.isPhone ? 18 : 26).padding(.bottom, 10)
            }
            .scrollIndicators(.never)

            if Platform.isPhone {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Button { dismiss() } label: { Text("Cancel").frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle())
                        saveButton
                    }
                    Text("Your top 3 shows on Today and in tomorrow's morning brief.").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
            } else {
                HStack {
                    Text("Your top 3 shows on Today and in tomorrow's morning brief.").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                    saveButton.frame(width: 120)
                }
                .padding(.horizontal, 26).padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.ui(15, weight: .semibold))
            content()
        }
    }

    private var saveButton: some View {
        Button("Save plan", action: save).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            .disabled(draft.picks.isEmpty && draft.note.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func leftoverTitle(_ t: TaskItem) -> some View {
        HStack(spacing: 6) {
            Text(t.title).font(Theme.ui(13, weight: .medium))
            if t.isOverdue { Text("overdue").font(Theme.ui(10, weight: .semibold)).foregroundStyle(Theme.critical).fixedSize() }
        }
    }

    private func leftoverActions(_ t: TaskItem) -> some View {
        HStack(spacing: 6) {
            small("Done", "checkmark") { t.complete(in: context); draft.handled.insert(t.persistentModelID) }
            small("Tomorrow", "arrow.right") { t.due = tomorrow; draft.handled.insert(t.persistentModelID) }
            small("No date", "calendar.badge.minus") { t.due = nil; draft.handled.insert(t.persistentModelID) }
        }
    }

    private func small(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Label(title, systemImage: symbol).font(Theme.ui(11, weight: .semibold)).lineLimit(1).fixedSize()
                .padding(.horizontal, 9).padding(.vertical, 6)
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
