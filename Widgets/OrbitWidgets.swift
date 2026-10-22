import WidgetKit
import SwiftUI

// Orbit's desktop widgets. Built by scripts/build-widgets.sh into Orbit.app/Contents/PlugIns/OrbitWidgets.appex.
// The app writes widget.json into the shared app-group folder (WidgetBridge.swift); keep these types in step with it.

let appGroup = "Y2K55S3UA9.com.personal.orbit"

struct WidgetSnapshot: Codable {
    struct Event: Codable { let title: String; let start: Date; let end: Date; let allDay: Bool; let color: String }
    struct Task: Codable { let title: String; let area: String; let overdue: Bool; let priority: Int }
    struct Habit: Codable { let name: String; let symbol: String; let done: Bool; let streak: Int; let color: String }
    struct Dream: Codable { let title: String; let date: Date }
    var generatedAt: Date
    var userName: String
    var events: [Event]
    var tasks: [Task]
    var habits: [Habit]
    var moneyLeft: Double
    var budget: Double
    var currency: String
    var lookingForward: [Dream]

    static func load() -> WidgetSnapshot? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              let data = try? Data(contentsOf: dir.appending(path: "widget.json")) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - Look

enum W {
    static let lime = Color(red: 0.90, green: 1.0, blue: 0.12)
    static let pink = Color(red: 0.97, green: 0.76, blue: 0.93)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.07)
    static func color(_ hex: String) -> Color {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return pink }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now, snapshot: WidgetSnapshot.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = WidgetSnapshot.load()
        // One entry now and one at each upcoming event start, so "next up" moves along on its own.
        var dates = [Date.now]
        dates += (snap?.events ?? []).map(\.start).filter { $0 > .now }.prefix(6)
        let entries = dates.map { Entry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Today widget

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if let s = entry.snapshot {
            let upcoming = s.events.filter { $0.end > entry.date }
            switch family {
            case .systemSmall: small(s, upcoming)
            case .systemLarge: large(s, upcoming)
            default: medium(s, upcoming)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("orbit").font(.system(size: 20, weight: .black, design: .rounded))
                Text("Open Orbit once to fill this widget.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.date.formatted(.dateTime.weekday(.wide))).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(entry.date.formatted(.dateTime.day().month())).font(.system(size: 13, weight: .bold, design: .serif))
        }
    }

    private func small(_ s: WidgetSnapshot, _ upcoming: [WidgetSnapshot.Event]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(s)
            if let next = upcoming.first {
                Text(next.allDay ? "Today" : W.time(next.start)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(next.title).font(.system(size: 16, weight: .bold, design: .serif)).lineLimit(2)
            } else {
                Text("No more events").font(.system(size: 15, weight: .bold, design: .serif))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                pill("\(s.tasks.count)", "due", W.pink)
                pill("\(s.habits.filter(\.done).count)/\(s.habits.count)", "habits", W.lime)
            }
        }
    }

    private func medium(_ s: WidgetSnapshot, _ upcoming: [WidgetSnapshot.Event]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header(s)
                if upcoming.isEmpty { Text("Nothing else today").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(upcoming.prefix(3).enumerated()), id: \.offset) { _, e in eventRow(e) }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Due today").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                if s.tasks.isEmpty { Text("All clear 🎉").font(.caption) }
                ForEach(Array(s.tasks.prefix(4).enumerated()), id: \.offset) { _, t in taskRow(t) }
                Spacer(minLength: 0)
                habitsDots(s)
            }
        }
    }

    private func large(_ s: WidgetSnapshot, _ upcoming: [WidgetSnapshot.Event]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(s)
            Text("Agenda").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if upcoming.isEmpty { Text("Nothing else today").font(.caption) }
            ForEach(Array(upcoming.prefix(4).enumerated()), id: \.offset) { _, e in eventRow(e) }
            Divider()
            Text("Due today").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if s.tasks.isEmpty { Text("All clear 🎉").font(.caption) }
            ForEach(Array(s.tasks.prefix(4).enumerated()), id: \.offset) { _, t in taskRow(t) }
            Spacer(minLength: 0)
            HStack {
                habitsDots(s)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Left to spend").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(s.moneyLeft.formatted(.currency(code: s.currency).precision(.fractionLength(0)))).font(.system(size: 15, weight: .bold, design: .serif))
                }
            }
        }
    }

    private func eventRow(_ e: WidgetSnapshot.Event) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(W.color(e.color)).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(e.allDay ? "All day" : "\(W.time(e.start)) – \(W.time(e.end))").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func taskRow(_ t: WidgetSnapshot.Task) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "circle").font(.system(size: 9, weight: .semibold))
            Text(t.title).font(.system(size: 12)).lineLimit(1)
            if t.overdue { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)).foregroundStyle(.red) }
        }
    }

    private func habitsDots(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(s.habits.prefix(6).enumerated()), id: \.offset) { _, h in
                Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13)).foregroundStyle(h.done ? W.color(h.color) : .secondary)
            }
        }
    }

    private func pill(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value).font(.system(size: 12, weight: .bold))
            Text(label).font(.system(size: 10))
        }
        .foregroundStyle(W.ink)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(color))
    }
}

// MARK: - Habits widget

struct HabitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        let habits = entry.snapshot?.habits ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Habits").font(.system(size: 15, weight: .bold, design: .serif))
                Spacer()
                Text("\(habits.filter(\.done).count)/\(habits.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            if habits.isEmpty { Text("Add habits in Orbit.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(habits.prefix(family == .systemSmall ? 4 : 6).enumerated()), id: \.offset) { _, h in
                HStack(spacing: 8) {
                    Image(systemName: h.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(h.done ? W.color(h.color) : .secondary)
                    Text(h.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if h.streak > 1 && family != .systemSmall { Text("\(h.streak)🔥").font(.system(size: 11)) }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Looking forward widget

struct CountdownWidgetView: View {
    let entry: Entry

    var body: some View {
        if let d = entry.snapshot?.lookingForward.first {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date),
                                                       to: Calendar.current.startOfDay(for: d.date)).day ?? 0
            VStack(alignment: .leading, spacing: 4) {
                Text("Looking forward to").font(.system(size: 11, weight: .semibold)).foregroundStyle(W.ink.opacity(0.7))
                Spacer(minLength: 0)
                Text(days <= 0 ? "Today 🎉" : "\(days)").font(.system(size: days <= 0 ? 26 : 44, weight: .bold, design: .serif))
                if days > 0 { Text(days == 1 ? "day to go" : "days to go").font(.system(size: 11, weight: .semibold)) }
                Text(d.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            }
            .foregroundStyle(W.ink)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Looking forward to").font(.system(size: 11, weight: .semibold))
                Text("Give a bucket-list dream a date in Orbit to count down to it.").font(.caption)
            }
            .foregroundStyle(W.ink)
        }
    }
}

// MARK: - Widgets

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitToday", provider: Provider()) { entry in
            TodayWidgetView(entry: entry).containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "com.personal.orbit://open/today"))
        }
        .configurationDisplayName("Orbit Today")
        .description("Your next events, what's due and your habits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitHabits", provider: Provider()) { entry in
            HabitsWidgetView(entry: entry).containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "com.personal.orbit://open/habits"))
        }
        .configurationDisplayName("Orbit Habits")
        .description("Today's habits and streaks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitCountdown", provider: Provider()) { entry in
            CountdownWidgetView(entry: entry).containerBackground(W.lime, for: .widget)
                .widgetURL(URL(string: "com.personal.orbit://open/bucket"))
        }
        .configurationDisplayName("Looking forward to")
        .description("Counts down to the next date on your bucket list.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct OrbitWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        HabitsWidget()
        CountdownWidget()
    }
}
