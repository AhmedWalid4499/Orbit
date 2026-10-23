import SwiftUI
import SwiftData

struct TasksView: View {
    enum Filter: Hashable {
        case today, upcoming, inbox, all, completed, area(Area), reminders, shared

        var title: String {
            switch self {
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .inbox: "No date"
            case .all: "All open"
            case .completed: "Completed"
            case .area(let a): a.title
            case .reminders: "Apple Reminders"
            case .shared: "Shared lists"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max.fill"
            case .upcoming: "calendar"
            case .inbox: "tray.fill"
            case .all: "list.bullet"
            case .completed: "checkmark.circle.fill"
            case .area(let a): a.symbol
            case .reminders: "applelogo"
            case .shared: "person.2.fill"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @State private var filter: Filter = .today
    @State private var draft = ""
    @State private var editing: TaskItem?

    private var tomorrow: Date { Date.now.startOfDay.adding(days: 1) }

    private func items(for f: Filter) -> [TaskItem] {
        let open = tasks.filter { !$0.isDone }
        let list: [TaskItem]
        switch f {
        case .today: list = open.filter { ($0.due ?? .distantFuture) < tomorrow }
        case .upcoming: list = open.filter { ($0.due ?? .distantPast) >= tomorrow }
        case .inbox: list = open.filter { $0.due == nil }
        case .all: list = open
        case .completed: return tasks.filter(\.isDone).sorted { ($0.completedAt ?? .now) > ($1.completedAt ?? .now) }
        case .area(let a): list = open.filter { $0.area == a }
        case .reminders, .shared: return []
        }
        return list.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            sidebar.frame(width: 260)
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text(filter.title).font(Theme.display(38))
                    Text(filter == .shared ? "" : "\(filter == .reminders ? apple.reminders.count : items(for: filter).count)")
                        .font(Theme.display(38, weight: .regular))
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                }
                if filter != .reminders && filter != .completed && filter != .shared { addBar }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if filter == .shared {
                            SharedListsView()
                        } else if filter == .reminders {
                            remindersList
                        } else if filter == .upcoming {
                            upcomingGrouped
                        } else {
                            let list = items(for: filter)
                            if list.isEmpty { EmptyHint(symbol: "checkmark.seal", text: "Nothing here.").padding(.top, 8) }
                            ForEach(list) { t in TaskRow(task: t) { editing = t } }
                        }
                    }
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 10)
        .sheet(item: $editing) { TaskEditor(task: $0) }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach([Filter.today, .upcoming, .inbox, .all, .completed], id: \.self) { f in
                    FilterRow(filter: f, count: f == .completed ? nil : items(for: f).count, selected: filter == f) { filter = f }
                }
                Text("Areas").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .padding(.top, 18).padding(.bottom, 4).padding(.leading, 12)
                ForEach(Area.allCases) { a in
                    FilterRow(filter: .area(a), count: items(for: .area(a)).count, selected: filter == .area(a), tint: a.color) {
                        filter = .area(a)
                    }
                }
                FilterRow(filter: .shared, count: nil, selected: filter == .shared) { filter = .shared }
                    .padding(.top, 14)
                Text("Connected").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .padding(.top, 18).padding(.bottom, 4).padding(.leading, 12)
                if apple.remindersEnabled {
                    FilterRow(filter: .reminders, count: apple.reminders.count, selected: filter == .reminders) { filter = .reminders }
                } else {
                    Button { Task { await apple.connectReminders() } } label: {
                        Label("Connect Apple Reminders", systemImage: "link")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .padding(.leading, 6)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var addBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus").foregroundStyle(Theme.inkMuted)
            TextField("Add a task — try “pay rent friday #money !!”", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.ui(15))
                .onSubmit(add)
            if !draft.isEmpty {
                Text(QuickParser.parse(draft).summary).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }

    private func add() {
        var parsed = QuickParser.parse(draft)
        guard !parsed.title.isEmpty else { return }
        // In the task list everything becomes a task; a time just sets the due date.
        if parsed.kind == .event { parsed.kind = .task }
        if parsed.kind == .task {
            if case .area(let a) = filter, parsed.area == nil { parsed.area = a }
            if filter == .today, parsed.date == nil { parsed.date = .now.startOfDay }
        }
        parsed.save(in: context)
        draft = ""
    }

    @ViewBuilder
    private var upcomingGrouped: some View {
        let groups = Dictionary(grouping: items(for: .upcoming)) { $0.due!.startOfDay }
        if groups.isEmpty { EmptyHint(symbol: "calendar", text: "Nothing planned yet.") }
        ForEach(groups.keys.sorted(), id: \.self) { day in
            Text(Fmt.relativeDay(day) + " · " + day.formatted(.dateTime.day().month()))
                .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            ForEach(groups[day]!) { t in TaskRow(task: t, showDue: false) { editing = t } }
        }
    }

    @ViewBuilder
    private var remindersList: some View {
        if apple.reminders.isEmpty { EmptyHint(symbol: "applelogo", text: "No open reminders.") }
        ForEach(apple.reminders) { ReminderRow(reminder: $0) }
    }
}

struct FilterRow: View {
    let filter: TasksView.Filter
    let count: Int?
    let selected: Bool
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: filter.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint != nil ? Theme.stickerInk : (selected ? Theme.onInverse : Theme.ink))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(tint ?? .clear))
                Text(filter.title).font(Theme.ui(14, weight: .medium))
                Spacer()
                if let count, count > 0 { Text("\(count)").font(Theme.ui(12, weight: .semibold)).opacity(0.7) }
            }
            .foregroundStyle(selected ? Theme.onInverse : Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? Theme.inverse : (hovering ? Theme.card : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var task: TaskItem
    /// Opened from + : the task is new, Cancel throws it away, and Quick add is offered.
    var isNew = false
    var onQuickAdd: (() -> Void)? = nil
    @State private var hasDue = false
    @State private var saved = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if isNew {
                HStack {
                    Text("New task").font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    if let onQuickAdd {
                        Button { discard(); onQuickAdd() } label: { Label("Quick add", systemImage: "sparkles") }
                            .buttonStyle(.orbitLink).font(Theme.ui(13))
                    }
                }
            }
            TextField(isNew ? "What do you need to do?" : "Title", text: $task.title).textFieldStyle(.plain).font(Theme.display(26))
                .focused($titleFocused)
            AreaPicker(selection: $task.area)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Due").foregroundStyle(Theme.inkSecondary)
                    HStack {
                        Toggle("", isOn: $hasDue).labelsHidden()
                        if hasDue {
                            DatePicker("", selection: Binding(get: { task.due ?? .now }, set: { task.due = $0 }),
                                       displayedComponents: .date).labelsHidden()
                        }
                    }
                }
                GridRow {
                    Text("Priority").foregroundStyle(Theme.inkSecondary)
                    Picker("", selection: $task.priority) {
                        Text("None").tag(0); Text("Low").tag(1); Text("Medium").tag(2); Text("High").tag(3)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                }
                GridRow {
                    Text("Repeat").foregroundStyle(Theme.inkSecondary)
                    Picker("", selection: $task.recurrence) {
                        ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 140)
                }
            }
            .font(Theme.ui(13))
            ReminderSection(task: task)
            Text("Notes").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            TextEditor(text: $task.notes)
                .font(Theme.ui(14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                .frame(height: 120)
            HStack {
                if isNew {
                    Button("Cancel") { discard(); dismiss() }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
                } else {
                    Button("Delete", role: .destructive) { context.delete(task); dismiss() }.buttonStyle(SoftButtonStyle())
                }
                Spacer()
                Button(isNew ? "Add task" : "Done") { saved = true; finish(); dismiss() }
                    .buttonStyle(PrimaryButtonStyle()).frame(width: 120).keyboardShortcut(.defaultAction)
                    .disabled(isNew && task.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(28)
        .sheetFrame(width: 520)
        .onAppear { hasDue = task.due != nil; if isNew { titleFocused = true } }
        // Swiped away or closed without adding: a new, empty task isn't kept.
        .onDisappear { if isNew && !saved && task.title.trimmingCharacters(in: .whitespaces).isEmpty { discard() } else { finish() } }
        .onChange(of: hasDue) { _, on in task.due = on ? (task.due ?? .now.startOfDay) : nil }
    }

    private func discard() {
        if isNew { context.delete(task); try? context.save(); saved = true }
    }

    /// Saves and schedules any reminder right away.
    private func finish() {
        try? context.save()
        if task.remindAt != nil || task.hasPlaceReminder {
            Task { await Reminders.shared.reschedule(context: context, apple: AppleSync()) }
        }
    }
}

/// + : a new task with dates, priority and reminders (Quick add is one tap away inside).
struct NewTaskSheet: View {
    @Environment(\.modelContext) private var context
    var onQuickAdd: (() -> Void)?
    @State private var task: TaskItem?

    var body: some View {
        Group {
            if let task { TaskEditor(task: task, isNew: true, onQuickAdd: onQuickAdd) }
        }
        .onAppear {
            guard task == nil else { return }
            let t = TaskItem(title: "", due: .now.startOfDay)
            context.insert(t)
            task = t
        }
    }
}
