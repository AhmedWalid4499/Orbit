import SwiftUI
import SwiftData

/// Tasks on iPhone: the Mac's filters as chips, the same smart add bar, swipe to complete or delete.
struct PhoneTasks: View {
    typealias Filter = TasksView.Filter

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var sharedLists = SharedListStore.shared
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @State private var filter: Filter = .today
    @AppStorage("tasksArea") private var areaRaw = ""
    private var area: Area? { Area(rawValue: areaRaw) }
    @State private var draft = ""
    @State private var editing: TaskItem?
    @FocusState private var adding: Bool

    private var tomorrow: Date { Date.now.startOfDay.adding(days: 1) }

    private func items(for f: Filter) -> [TaskItem] {
        let open = tasks.filter { !$0.isDone && (area == nil || $0.area == area) }
        let list: [TaskItem]
        switch f {
        case .today: list = open.filter { ($0.due ?? .distantFuture) < tomorrow }
        case .upcoming: list = open.filter { ($0.due ?? .distantPast) >= tomorrow }
        case .inbox: list = open.filter { $0.due == nil }
        case .all: list = open
        case .completed: return tasks.filter { $0.isDone && (area == nil || $0.area == area) }.sorted { ($0.completedAt ?? .now) > ($1.completedAt ?? .now) }
        case .area(let a): list = open.filter { $0.area == a }
        case .reminders, .shared: return []
        }
        return list.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture)
        }
    }

    private var filters: [Filter] {
        [.today, .upcoming, .inbox, .completed] + (sharedLists.isSetUp ? [.shared] : []) + (apple.remindersEnabled ? [.reminders] : [])
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { f in
                            let n = f == .reminders ? apple.reminders.count : f == .shared ? 0 : items(for: f).count
                            Button { withAnimation(.snappy) { filter = f } } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: f.symbol).font(.system(size: 11, weight: .semibold))
                                    Text(f.title)
                                    if n > 0 && f != .completed { Text("\(n)").opacity(0.6) }
                                }
                                .font(Theme.ui(13, weight: .semibold))
                                .foregroundStyle(filter == f ? Theme.onInverse : Theme.ink)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(filter == f ? Theme.inverse : Theme.card))
                            }
                            .buttonStyle(.plain)
                        }
                        // One menu for the seven areas, instead of a chip each.
                        Menu {
                            Button("All areas") { areaRaw = "" }
                            ForEach(Area.allCases) { a in Button { areaRaw = a.rawValue } label: { Label(a.title, systemImage: a.symbol) } }
                        } label: {
                            HStack(spacing: 5) {
                                Circle().fill(area?.color ?? Theme.inkMuted).frame(width: 7, height: 7)
                                Text(area?.title ?? "Area")
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                            }
                            .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(area == nil ? Theme.card : area!.color.opacity(0.35)))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.never)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if filter != .shared {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").foregroundStyle(Theme.inkMuted)
                        TextField("Add a task: “pay rent friday #money !!”", text: $draft)
                            .font(Theme.ui(15)).focused($adding).submitLabel(.done).onSubmit(add)
                        MicButton { heard in draft = heard; add() }
                    }
                    .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    if !draft.isEmpty {
                        Text(QuickParser.parse(draft).summary).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listRowSeparator(.hidden)

            if filter == .shared {
                SharedListsView().padding(.horizontal, 16).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if filter == .reminders {
                if apple.reminders.isEmpty { hint("applelogo", "No open reminders.") }
                ForEach(apple.reminders) { ReminderRow(reminder: $0).plainRow() }
            } else if filter == .upcoming {
                let groups = Dictionary(grouping: items(for: .upcoming)) { $0.due!.startOfDay }
                if groups.isEmpty { hint("calendar", "Nothing planned yet.") }
                ForEach(groups.keys.sorted(), id: \.self) { day in
                    Section {
                        ForEach(groups[day]!) { row($0, showDue: false) }
                    } header: {
                        Text(Fmt.relativeDay(day) + " · " + day.formatted(.dateTime.day().month())).font(Theme.ui(13, weight: .semibold))
                    }
                }
            } else {
                let list = items(for: filter)
                if list.isEmpty { hint(filter == .completed ? "checkmark.circle" : "checkmark.seal", filter == .completed ? "Nothing completed yet." : "Nothing here. Nice.") }
                ForEach(list) { row($0, showDue: filter != .today || $0.isOverdue) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .sheet(item: $editing) { TaskEditor(task: $0) }
        .task { await sharedLists.refresh() }
        .onChange(of: sharedLists.isSetUp) { _, ready in if !ready && filter == .shared { filter = .today } }
        .phoneChrome("Tasks")
    }

    private func row(_ t: TaskItem, showDue: Bool) -> some View {
        TaskRow(task: t, showDue: showDue) { editing = t }
            .plainRow()
            .swipeActions(edge: .leading) {
                Button { withAnimation { if t.isDone { t.isDone = false; t.completedAt = nil } else { t.complete(in: context) } } } label: {
                    Label(t.isDone ? "Undo" : "Done", systemImage: t.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(Theme.good)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { context.delete(t) } label: { Label("Delete", systemImage: "trash") }
                Button { t.due = tomorrow } label: { Label("Tomorrow", systemImage: "arrow.right") }.tint(Theme.orange)
                if !t.isDone { Button { FocusTimer.shared.start(task: t, context: context) } label: { Label("Focus", systemImage: "timer") }.tint(Theme.purple) }
            }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        EmptyHint(symbol: symbol, text: text).plainRow()
    }

    private func add() {
        var parsed = QuickParser.parse(draft)
        guard !parsed.title.isEmpty else { return }
        if parsed.kind == .event { parsed.kind = .task }
        if parsed.kind == .task {
            if let a = area, parsed.area == nil { parsed.area = a }
            if filter == .today, parsed.date == nil { parsed.date = .now.startOfDay }
        }
        parsed.save(in: context)
        draft = ""
    }
}

extension View {
    /// A list row without the list's own inset, background or separator.
    func plainRow() -> some View {
        listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
