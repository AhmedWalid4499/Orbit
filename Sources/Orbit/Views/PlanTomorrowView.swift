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

/// Evening routine: clear what's left today, glance at tomorrow, pick tomorrow's top three.
struct PlanTomorrowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }, sort: \TaskItem.createdAt) private var open: [TaskItem]
    @Query(sort: \EventItem.start) private var events: [EventItem]

    @State private var handled: Set<PersistentIdentifier> = []
    @State private var picks: [(title: String, task: TaskItem?)] = []
    @State private var typed = ""
    @State private var note = ""
    @State private var loaded = false

    private var today: Date { .now.startOfDay }
    private var tomorrow: Date { today.adding(days: 1) }

    private var leftovers: [TaskItem] {
        open.filter { ($0.due.map { $0 < tomorrow } ?? false) && !handled.contains($0.persistentModelID) }
            .sorted { ($0.due ?? .now) < ($1.due ?? .now) }
    }

    private var tomorrowEntries: [CalEntry] {
        CalEntry.merge(local: events.filter { $0.start.isSameDay(as: tomorrow) }, apple: apple.events(from: tomorrow, to: tomorrow.adding(days: 1)),
                       google: GoogleCalendarStore.shared.events(from: tomorrow, to: tomorrow.adding(days: 1)))
    }

    private var candidates: [TaskItem] {
        let picked = Set(picks.compactMap { $0.task?.persistentModelID })
        return open.filter { !picked.contains($0.persistentModelID) }
            .sorted {
                let a = ($0.due.map { $0 < tomorrow.adding(days: 1) } ?? false, $0.priority)
                let b = ($1.due.map { $0 < tomorrow.adding(days: 1) } ?? false, $1.priority)
                return a.0 != b.0 ? a.0 : a.1 > b.1
            }
            .prefix(14).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan tomorrow").font(Theme.display(30))
                Text(tomorrow.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            }
            .padding([.horizontal, .top], 26).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("1", "What's left from today") {
                        if leftovers.isEmpty {
                            Text("All clear ✨").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                        }
                        ForEach(leftovers) { t in
                            HStack(spacing: 8) {
                                Text(t.title).font(Theme.ui(13, weight: .medium)).lineLimit(1)
                                if t.isOverdue { Text("overdue").font(Theme.ui(10, weight: .semibold)).foregroundStyle(Theme.critical) }
                                Spacer()
                                small("Done", "checkmark") { t.complete(in: context); handled.insert(t.persistentModelID) }
                                small("Tomorrow", "arrow.right") { t.due = tomorrow; handled.insert(t.persistentModelID) }
                                small("No date", "calendar.badge.minus") { t.due = nil; handled.insert(t.persistentModelID) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                        }
                    }

                    section("2", "Tomorrow's calendar") {
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

                    section("3", "Your top 3 for tomorrow") {
                        VStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { i in
                                HStack(spacing: 10) {
                                    Text("\(i + 1)").font(Theme.ui(12, weight: .bold)).foregroundStyle(Theme.stickerInk)
                                        .frame(width: 24, height: 24).background(Circle().fill([Theme.lime, Theme.pink, Theme.cyan][i]))
                                    if i < picks.count {
                                        Text(picks[i].title).font(Theme.ui(14, weight: .medium)).lineLimit(1)
                                        Spacer()
                                        Button { picks.remove(at: i) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.inkMuted)
                                    } else {
                                        Text(i == picks.count ? "Pick a task below or type one" : "—").font(Theme.ui(13)).foregroundStyle(Theme.inkMuted)
                                        Spacer()
                                    }
                                }
                                .padding(.horizontal, 12).frame(height: 40)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                            }
                        }
                        if picks.count < 3 {
                            HStack(spacing: 8) {
                                Image(systemName: "plus").foregroundStyle(Theme.inkMuted)
                                TextField("Type a priority and press Return", text: $typed).textFieldStyle(.plain).font(Theme.ui(13))
                                    .onSubmit {
                                        let t = typed.trimmingCharacters(in: .whitespaces)
                                        if !t.isEmpty, picks.count < 3 { picks.append((t, nil)) }
                                        typed = ""
                                    }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                            FlowLayout(spacing: 6) {
                                ForEach(candidates) { t in
                                    Button { if picks.count < 3 { picks.append((t.title, t)) } } label: {
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

                    section("4", "Anything to remember?") {
                        TextField("e.g. Bring the charger, call the bank before 10", text: $note).textFieldStyle(.roundedBorder).font(Theme.ui(13))
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
                    .disabled(picks.isEmpty && note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 26).padding(.vertical, 16)
        }
        .frame(width: 640, height: 700)
        .onAppear(perform: load)
    }

    private func section(_ n: String, _ title: String, @ViewBuilder _ content: () -> some View) -> some View {
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
        guard let p = DayPlanner.plan(for: tomorrow, context: context) else { return }
        note = p.note
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        picks = p.top.enumerated().map { i, title in
            let id = i < p.taskUUIDs.count ? p.taskUUIDs[i] : ""
            return (title, id.isEmpty ? nil : all.first { $0.uuid == id })
        }
    }

    private func save() {
        let p = DayPlanner.plan(for: tomorrow, context: context) ?? { let p = DayPlan(day: DayKey.key(tomorrow)); context.insert(p); return p }()
        for pick in picks {
            guard let t = pick.task else { continue }
            if t.uuid.isEmpty { t.uuid = UUID().uuidString.lowercased() }
            if (t.due ?? .distantPast) < tomorrow { t.due = tomorrow }
        }
        p.top = picks.map(\.title)
        p.taskUUIDs = picks.map { $0.task?.uuid ?? "" }
        p.note = note.trimmingCharacters(in: .whitespaces)
        p.createdAt = .now
        try? context.save()
        dismiss()
    }
}
