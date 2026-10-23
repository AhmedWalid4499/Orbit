import Foundation
import SwiftData
import SwiftUI

/// "Your day": an AI-written, always-current summary on Today: what you're reading, what you've spent today,
/// tasks, habits, calendar, focus and anything to watch. It's rewritten whenever your data changes
/// (at most every 20 minutes), so it follows you through the day.
struct DaySummary: Codable, Equatable {
    struct Tile: Codable, Equatable, Hashable {
        /// reading, money, tasks, habits, calendar, focus, mood, trips, places, other
        var kind: String
        var title: String
        var value: String
        var detail: String
    }
    var line: String
    var tiles: [Tile]
    var nudge: String
    var day: String = ""
    var fingerprint: String = ""
    var generatedAt: Date = .now

    enum CodingKeys: String, CodingKey { case line, tiles, nudge, day, fingerprint, generatedAt }

    init(line: String, tiles: [Tile], nudge: String) { self.line = line; self.tiles = tiles; self.nudge = nudge }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = try c.decode(String.self, forKey: .line)
        tiles = try c.decode([Tile].self, forKey: .tiles)
        nudge = try c.decode(String.self, forKey: .nudge)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now
    }
}

@MainActor
final class DaySummaryStore: ObservableObject {
    static let shared = DaySummaryStore()

    @Published private(set) var summary: DaySummary?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private let cacheKey = "daySummaryCache"

    private init() {
        if let d = UserDefaults.standard.data(forKey: cacheKey), let s = try? JSONDecoder().decode(DaySummary.self, from: d) { summary = s }
    }

    var isToday: Bool { summary?.day == DayKey.key(.now) }

    /// Debug snapshots only.
    func preview(_ s: DaySummary) { var s = s; s.day = DayKey.key(.now); summary = s }

    /// Rewrites the summary when something changed since the last one (or when forced).
    func refreshIfNeeded(context: ModelContext, apple: AppleSync, force: Bool = false) async {
        guard AIAssistant.shared.hasKey, !loading, !Snapshot.isActive, let client = ClaudeClient() else { return }
        let print = Self.fingerprint(context: context)
        if !force, isToday, let s = summary {
            if s.fingerprint == print { return }
            if Date.now.timeIntervalSince(s.generatedAt) < 20 * 60 { return }
        }
        loading = true
        error = nil
        defer { loading = false }
        let data = AIAssistant.snapshot(context: context, apple: apple) + "\n" + Self.extra(context: context)
        let system = """
        You write the "Your day" panel on the Today screen of \(Platform.userName.split(separator: " ").first.map(String.init) ?? "the user")'s life-organizer app. \
        It's a live picture of their day so far, rewritten every time something changes, so describe where things stand right now (it's \(Date.now.formatted(.dateTime.hour().minute()))).
        Use only the data given; never invent numbers, books, events or places. Sound like a friend glancing at their day, not a report.
        - line: one short, human sentence on how the day is going (max 16 words). No greeting like "Good morning".
        - tiles: 4 to 6, the most useful right now, in this order of preference when they have something to say: \
          money (what they've spent today, with the biggest merchant, and how the month is pacing), reading (the book they're on and how far, minutes read today), \
          tasks (done vs left today, the next important one), calendar (what's next and when), habits (what's left today), focus (minutes today), \
          mood (from today's journal), trips (an upcoming trip), places (a Go to place worth trying). Skip a tile when there's nothing meaningful.
          title: 1-3 words. value: the key fact, short (max 22 characters, e.g. "EGP 350 today", "62% · Atomic Habits", "3 of 5 done"). detail: one short line of context or a tip (max 60 characters).
        - nudge: one gentle, specific suggestion for the next few hours, or "" if nothing stands out.
        Plain text only. Use the home currency \(Fmt.currencyCode).
        """
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "line": ["type": "string"],
                "tiles": ["type": "array", "items": [
                    "type": "object",
                    "properties": [
                        "kind": ["type": "string", "enum": ["money", "reading", "tasks", "calendar", "habits", "focus", "mood", "trips", "places", "other"]],
                        "title": ["type": "string"], "value": ["type": "string"], "detail": ["type": "string"],
                    ],
                    "required": ["kind", "title", "value", "detail"], "additionalProperties": false,
                ]],
                "nudge": ["type": "string"],
            ],
            "required": ["line", "tiles", "nudge"], "additionalProperties": false,
        ]
        do {
            var s = try await client.structured(DaySummary.self, system: system, user: data, schema: schema, effort: "low", maxTokens: 3000)
            s.day = DayKey.key(.now)
            s.fingerprint = print
            s.generatedAt = .now
            summary = s
            if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: cacheKey) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// What the summary depends on; when it changes, the summary is rewritten.
    static func fingerprint(context: ModelContext) -> String {
        let today = Date.now.startOfDay
        let txns = ((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).filter { $0.date >= today }
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let reading = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        let books = BookLibrary.currentlyReading((try? context.fetch(FetchDescriptor<Book>())) ?? [], sessions: reading)
        let focus = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
        let events = ((try? context.fetch(FetchDescriptor<EventItem>())) ?? []).filter { $0.start >= today && $0.start < today.adding(days: 1) }
        let parts: [String] = [
            "\(txns.count):\(Int(txns.reduce(0) { $0 + $1.amount }))",
            "\(tasks.filter(\.isDone).count)/\(tasks.count)",
            "\(habits.filter { $0.isDone(on: today) }.count)",
            books.map { "\($0.title)\(Int($0.progress * 100))" }.joined(separator: ","),
            "\(ReadingTimer.minutes(reading, since: today))",
            "\(FocusTimer.minutes(focus, since: today))",
            "\(events.count)",
            // The next event changes as the day goes on.
            "\(events.filter { $0.start > .now }.count)",
        ]
        return "v2|" + parts.joined(separator: "|")
    }

    /// Data the morning brief doesn't carry: today's spending, reading, focus, mood, trips and places.
    static func extra(context: ModelContext) -> String {
        let today = Date.now.startOfDay
        var lines: [String] = []
        let txns = ((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).filter { $0.date >= today && $0.date < today.adding(days: 1) }
        let spent = txns.filter(\.isExpense)
        lines.append("\nSpent today: \(Fmt.money(-spent.reduce(0) { $0 + $1.amount })) in \(spent.count) payments")
        lines += spent.sorted { $0.amount < $1.amount }.prefix(6).map { "- \($0.title): \(Fmt.money(-$0.amount)) [\($0.category)]" }
        if let budgets = Optional(SpendingAlerts.budgets), !budgets.isEmpty {
            let month = ((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).filter { $0.isExpense && $0.date >= Date.now.startOfMonth }
            lines.append("Category budgets this month: " + budgets.map { c, limit in
                "\(c) \(Fmt.money(-month.filter { $0.category == c }.reduce(0) { $0 + $1.amount })) of \(Fmt.money(limit))"
            }.joined(separator: "; "))
        }

        let sessions = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        let books = BookLibrary.currentlyReading((try? context.fetch(FetchDescriptor<Book>())) ?? [], sessions: sessions)
        if let main = books.first {
            lines.append("\nThe book they're reading now (use this one for the reading tile): \(main.title) by \(main.author), \(Int(main.progress * 100))%\(main.pageCount > 0 ? " of \(main.pageCount) pages" : "")")
            if books.count > 1 { lines.append("Also on the Currently reading shelf: " + books.dropFirst().prefix(3).map(\.title).joined(separator: ", ")) }
        } else {
            lines.append("\nReading now: (nothing)")
        }
        lines.append("Minutes read today: \(ReadingTimer.minutes(sessions, since: today)); this week: \(ReadingTimer.minutes(sessions, since: Date.now.startOfWeek)); streak \(ReadingTimer.streak(sessions)) days")

        let focus = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
        lines.append("\nFocus today: \(FocusTimer.minutes(focus, since: today)) minutes")

        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        if let j = notes.first(where: { $0.isJournal && $0.createdAt >= today }) {
            lines.append("\nToday's journal\(j.mood > 0 ? " (mood \(j.mood)/5)" : ""): \(j.body.prefix(300))")
        }

        let trips = ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).filter { ($0.start ?? .distantPast) >= today }
        if let t = trips.min(by: { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }), let start = t.start {
            lines.append("\nNext trip: \(t.title) in \(Calendar.current.dateComponents([.day], from: today, to: start.startOfDay).day ?? 0) days")
        }
        let places = ((try? context.fetch(FetchDescriptor<BucketItem>())) ?? []).filter { $0.kind == .place && !$0.isDone }
        if !places.isEmpty {
            lines.append("\nGo to places saved: " + places.prefix(5).map { "\($0.title) (\($0.placeCategory.title))" }.joined(separator: ", "))
        }
        if let w = WeatherStore.shared.now {
            lines.append("\nWeather: \(Int(w.temperature.rounded()))° in \(w.place)")
        }
        return lines.joined(separator: "\n")
    }
}
