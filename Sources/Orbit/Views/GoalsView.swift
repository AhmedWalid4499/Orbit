import SwiftUI
import SwiftData

/// Bucket list › Goals: goals that fill in by themselves from Reading, Money and Habits, or from ticking off steps.
struct GoalsSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query private var books: [Book]
    @Query private var transactions: [Transaction]
    @Query private var habits: [Habit]
    @State private var editing: Goal?
    @State private var adding = false

    private var sources: GoalTracker.Sources { .init(books: books, transactions: transactions, habits: habits) }
    private var open: [Goal] { goals.filter { $0.doneAt == nil } }
    private var done: [Goal] { goals.filter { $0.doneAt != nil } }

    var body: some View {
        let s = sources
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goals").font(Theme.display(24))
                    Text("Progress fills in from your books, money and habits.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Button { adding = true } label: { Label("Add goal", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
            }
            if goals.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        EmptyHint(symbol: "flag.checkered", text: "No goals yet. Try one of these:")
                        AdaptiveStack(spacing: 8) {
                            starter("Read 24 books this year", .books, 24, deadline: endOfYear)
                            starter("Save \(Fmt.money(50000)) by June", .save, 50000, deadline: nextJune)
                            if let h = habits.first { starter("\(h.name) 30 days", .habit, 30, habit: h) }
                        }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16, alignment: .top)], spacing: 16) {
                ForEach(open) { g in
                    GoalCard(goal: g, progress: GoalTracker.progress(g, s)).onTapGesture { editing = g }
                }
            }
            if !done.isEmpty {
                Text("Reached (\(done.count))").font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.inkSecondary).padding(.top, 6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16, alignment: .top)], spacing: 16) {
                    ForEach(done) { g in GoalCard(goal: g, progress: GoalTracker.progress(g, s)).onTapGesture { editing = g } }
                }
            }
        }
        .sheet(isPresented: $adding) { GoalEditor(goal: nil) }
        .sheet(item: $editing) { GoalEditor(goal: $0) }
    }

    private var endOfYear: Date { Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: .now), month: 12, day: 31))! }
    private var nextJune: Date {
        let cal = Calendar.current, y = cal.component(.year, from: .now)
        let june = cal.date(from: DateComponents(year: y, month: 6, day: 30))!
        return june > .now ? june : cal.date(byAdding: .year, value: 1, to: june)!
    }

    private func starter(_ title: String, _ kind: GoalKind, _ target: Double, deadline: Date? = nil, habit: Habit? = nil) -> some View {
        Button {
            let g = Goal(title: title, kind: kind, target: target)
            g.deadline = deadline
            if let habit {
                if habit.uuid.isEmpty { habit.uuid = UUID().uuidString.lowercased() }
                g.habitUUID = habit.uuid
            }
            // A reading goal for the year counts from January.
            if kind == .books { g.start = Date.now.startOfYear }
            context.insert(g)
        } label: { Label(title, systemImage: kind.symbol) }
        .buttonStyle(SoftButtonStyle())
    }
}

struct GoalCard: View {
    @Bindable var goal: Goal
    let progress: GoalTracker.Progress

    private var tint: Color {
        switch goal.kind {
        case .books: Theme.lavender
        case .save: Theme.mint
        case .habit: Theme.peach
        case .steps: Theme.sand
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: goal.kind.symbol).font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.6)))
                Spacer()
                Text("\(Int(progress.fraction * 100))%").font(Theme.display(26))
            }
            Text(goal.title).font(Theme.ui(16, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.stickerInk.opacity(0.12))
                    Capsule().fill(Theme.stickerInk).frame(width: max(6, g.size.width * progress.fraction))
                }
            }
            .frame(height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(GoalTracker.describe(goal, progress)).font(Theme.ui(13, weight: .semibold))
                if let pace = GoalTracker.paceText(goal, progress) { Text(pace).font(Theme.ui(11)).opacity(0.7) }
            }
            if goal.kind == .steps && !goal.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(goal.steps.prefix(6), id: \.self) { step in
                        let on = goal.stepsDone.contains(step)
                        Button {
                            if on { goal.stepsDone.removeAll { $0 == step } } else { goal.stepsDone.append(step) }
                        } label: {
                            HStack(spacing: 8) {
                                CheckCircle(isOn: on, tint: Theme.stickerInk, size: 16)
                                Text(step).font(Theme.ui(13)).strikethrough(on).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if goal.steps.count > 6 { Text("+\(goal.steps.count - 6) more").font(Theme.ui(11)).opacity(0.7) }
                }
            }
            if progress.isComplete && goal.doneAt == nil {
                Button("Mark as reached 🎉") { goal.doneAt = .now }
                    .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.65)))
            }
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(tint))
        .opacity(goal.doneAt == nil ? 1 : 0.7)
        .contentShape(Rectangle())
    }
}

struct GoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \BucketItem.createdAt, order: .reverse) private var bucket: [BucketItem]
    let goal: Goal?
    /// Start a steps goal from a bucket-list dream.
    var from: BucketItem? = nil

    @State private var title = ""
    @State private var kind: GoalKind = .books
    @State private var target = ""
    @State private var start = Date.now.startOfDay
    @State private var hasDeadline = false
    @State private var deadline = Date.now.adding(days: 90)
    @State private var habitUUID = ""
    @State private var bucketUUID = ""
    @State private var steps: [String] = []
    @State private var newStep = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(goal == nil ? "New goal" : "Edit goal").font(Theme.display(26))
            Form {
                TextField("Goal", text: $title, prompt: Text("Read 24 books, save for a car…"))
                Picker("Tracks", selection: $kind) { ForEach(GoalKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                switch kind {
                case .books:
                    TextField("Books", text: $target, prompt: Text("24"))
                    DatePicker("Counting books finished since", selection: $start, displayedComponents: .date)
                case .save:
                    TextField("Amount (\(Fmt.currencyCode))", text: $target, prompt: Text("50000"))
                    DatePicker("Saving since", selection: $start, displayedComponents: .date)
                    Text("Counts your income minus your spending in Money since that day.").font(.caption).foregroundStyle(.secondary)
                case .habit:
                    Picker("Habit", selection: $habitUUID) {
                        Text("Choose…").tag("")
                        ForEach(habits) { Text($0.name).tag($0.uuid) }
                    }
                    TextField("Days", text: $target, prompt: Text("30"))
                    DatePicker("Counting since", selection: $start, displayedComponents: .date)
                case .steps:
                    Picker("Dream", selection: $bucketUUID) {
                        Text("None").tag("")
                        ForEach(bucket.filter { $0.kind != .place && !$0.isDone }) { Text($0.title).tag($0.uuid) }
                    }
                    ForEach(steps, id: \.self) { s in
                        HStack {
                            Text(s)
                            Spacer()
                            Button { steps.removeAll { $0 == s } } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        TextField("Add a step", text: $newStep, prompt: Text("Book flights, save for tickets…")).onSubmit(addStep)
                        Button("Add", action: addStep).disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Toggle("Deadline", isOn: $hasDeadline)
                if hasDeadline { DatePicker("By", selection: $deadline, displayedComponents: .date) }
            }
            .formStyle(.grouped)
            HStack {
                if let goal {
                    Button("Delete", role: .destructive) { context.delete(goal); dismiss() }.buttonStyle(SoftButtonStyle())
                    if goal.doneAt != nil { Button("Reopen") { goal.doneAt = nil; dismiss() }.buttonStyle(SoftButtonStyle()) }
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).fixedSize().disabled(!valid)
            }
        }
        .padding(Platform.isPhone ? 20 : 24)
        .sheetFrame(width: 500, height: 600)
        .onAppear(perform: load)
    }

    private var valid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .steps: return !steps.isEmpty
        case .habit: return !habitUUID.isEmpty && (Double(target) ?? 0) > 0
        default: return (Double(target.replacingOccurrences(of: ",", with: "")) ?? 0) > 0
        }
    }

    private func addStep() {
        let s = newStep.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !steps.contains(s) else { return }
        steps.append(s); newStep = ""
    }

    private func load() {
        // Goals point at habits and dreams by their sync id; older items may not have one yet.
        for h in habits where h.uuid.isEmpty { h.uuid = UUID().uuidString.lowercased() }
        for b in bucket where b.uuid.isEmpty { b.uuid = UUID().uuidString.lowercased() }
        if let goal {
            title = goal.title; kind = goal.kind; target = goal.target > 0 ? String(format: "%g", goal.target) : ""
            start = goal.start; hasDeadline = goal.deadline != nil; deadline = goal.deadline ?? deadline
            habitUUID = goal.habitUUID; bucketUUID = goal.bucketUUID; steps = goal.steps
        } else if let from {
            title = from.title; kind = .steps; bucketUUID = from.uuid
            if let d = from.targetDate { hasDeadline = true; deadline = d }
        }
    }

    private func save() {
        let g = goal ?? { let g = Goal(title: ""); context.insert(g); return g }()
        g.title = title.trimmingCharacters(in: .whitespaces); g.kind = kind
        g.target = kind == .steps ? Double(steps.count) : Double(target.replacingOccurrences(of: ",", with: "")) ?? 0
        g.start = start.startOfDay; g.deadline = hasDeadline ? deadline : nil
        g.habitUUID = kind == .habit ? habitUUID : ""; g.bucketUUID = kind == .steps ? bucketUUID : ""
        g.steps = kind == .steps ? steps : []
        g.stepsDone = g.stepsDone.filter { g.steps.contains($0) }
        try? context.save()
        dismiss()
    }
}

extension Date {
    var startOfYear: Date { Calendar.current.dateInterval(of: .year, for: self)!.start }
}
