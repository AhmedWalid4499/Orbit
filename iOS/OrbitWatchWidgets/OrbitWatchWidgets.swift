import WidgetKit
import SwiftUI

/// Watch face complications. They read the snapshot the watch app saved from the iPhone.
struct WatchEntry: TimelineEntry {
    let date: Date
    let snap: WatchSnapshot?
}

struct WatchProvider: TimelineProvider {
    static func load() -> WatchSnapshot? {
        WatchSnapshot.from(UserDefaults(suiteName: "group.com.ahmedwalid.orbit")?.data(forKey: "watchSnapshot"))
    }
    func placeholder(in context: Context) -> WatchEntry { WatchEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntry(date: .now, snap: context.isPreview ? .sample : Self.load() ?? .sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let snap = Self.load()
        // Re-render when each upcoming event starts, so "next" stays right; the app also reloads on new data.
        var dates = [Date.now]
        dates += (snap?.events ?? []).map(\.end).filter { $0 > .now }.prefix(6)
        let entries = dates.map { WatchEntry(date: $0, snap: snap) }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

extension WatchSnapshot {
    static var sample: WatchSnapshot {
        var s = WatchSnapshot()
        s.tasks = [.init(id: "1", title: "Call the landlord", priority: 2, overdue: false), .init(id: "2", title: "Pay rent", priority: 3, overdue: false)]
        s.events = [.init(id: "e", title: "Gym", start: .now.addingTimeInterval(3600), end: .now.addingTimeInterval(7200), allDay: false)]
        s.spentToday = "EGP 350"; s.budgetUsed = 0.62
        s.habits = [.init(id: "h", name: "Water", symbol: "drop.fill", done: true, streak: 5), .init(id: "h2", name: "Read", symbol: "book.fill", done: false, streak: 2)]
        return s
    }
    func next(after date: Date) -> Event? { events.first { $0.end > date } }
}

struct TasksComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitTasks", provider: WatchProvider()) { e in
            TasksView(entry: e).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tasks left")
        .description("How many tasks are due today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct TasksView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry
    var body: some View {
        let left = entry.snap?.tasks.count ?? 0
        let done = entry.snap?.tasksDoneToday ?? 0
        switch family {
        case .accessoryInline:
            Text(left == 0 ? "All tasks done" : "\(left) tasks left")
        case .accessoryCorner:
            Image(systemName: "checklist").font(.title3)
                .widgetLabel { Gauge(value: Double(done), in: 0...Double(max(1, done + left))) { Text("Tasks") } currentValueLabel: { Text("\(left)") } }
        default:
            Gauge(value: Double(done), in: 0...Double(max(1, done + left))) {
                Image(systemName: "checklist")
            } currentValueLabel: { Text("\(left)") }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }
}

struct DayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitDay", provider: WatchProvider()) { e in
            DayView(entry: e).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Your day")
        .description("Next event, tasks and habits left.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct DayView: View {
    let entry: WatchEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let e = entry.snap?.next(after: entry.date) {
                Text(e.allDay ? "All day" : e.start.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                Text(e.title).font(.headline).lineLimit(1)
            } else {
                Text("Orbit").font(.caption2).foregroundStyle(.secondary)
                Text("No more events").font(.headline).lineLimit(1)
            }
            let s = entry.snap
            Text("\(s?.tasks.count ?? 0) tasks · \(s?.habits.filter { !$0.done }.count ?? 0) habits left").font(.caption2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SpendComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitSpend", provider: WatchProvider()) { e in
            SpendView(entry: e).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Spent today")
        .description("Today's spending and the month's budget.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct SpendView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry
    var body: some View {
        let s = entry.snap
        if family == .accessoryInline {
            Text("\(s?.spentToday ?? "–") today")
        } else {
            Gauge(value: min(1, s?.budgetUsed ?? 0)) {
                Image(systemName: "creditcard.fill")
            } currentValueLabel: {
                Text("\(Int((s?.budgetUsed ?? 0) * 100))%")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}

@main
struct OrbitWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        DayComplication()
        TasksComplication()
        SpendComplication()
    }
}
