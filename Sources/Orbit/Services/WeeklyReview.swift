import Foundation
import SwiftUI
import SwiftData

/// Numbers for one week, computed on the Mac (Ask only puts them into words).
struct WeekStats {
    let start: Date
    let end: Date
    let tasksDone: [String]
    let overdue: Int
    let habits: [(name: String, done: Int, target: Int)]
    let spent: Double
    let topCategories: [(String, Double)]
    let monthSpent: Double
    let budget: Double
    let moods: [(day: Date, mood: Int)]
    let booksFinished: [String]
    let readingMinutes: Int
    let focusMinutes: Int
    let events: Int
    let bucketDone: [String]

    var label: String {
        "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.adding(days: -1).formatted(.dateTime.day().month(.abbreviated)))"
    }

    @MainActor static func compute(context: ModelContext, apple: AppleSync, weekContaining date: Date = .now) -> WeekStats {
        let start = date.startOfWeek, end = start.adding(days: 7)
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let txns = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.isJournal }))) ?? []
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        let focus = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
        let bucket = (try? context.fetch(FetchDescriptor<BucketItem>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<EventItem>())) ?? []
        func inWeek(_ d: Date?) -> Bool { d.map { $0 >= start && $0 < end } ?? false }

        let expenses = txns.filter { $0.isExpense && inWeek($0.date) }
        let byCat = Dictionary(grouping: expenses, by: \.category).mapValues { -$0.reduce(0) { $0 + $1.amount } }
        let monthStart = date.startOfMonth
        return WeekStats(
            start: start, end: end,
            tasksDone: tasks.filter { $0.isDone && inWeek($0.completedAt) }.map(\.title),
            overdue: tasks.filter(\.isOverdue).count,
            habits: habits.map { h in (h.name, (0..<7).filter { h.isDone(on: start.adding(days: $0)) }.count, h.targetPerWeek) },
            spent: -expenses.reduce(0) { $0 + $1.amount },
            topCategories: byCat.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) },
            monthSpent: -txns.filter { $0.isExpense && $0.date >= monthStart }.reduce(0) { $0 + $1.amount },
            budget: UserDefaults.standard.object(forKey: "monthlyBudget") as? Double ?? 2000,
            moods: notes.filter { $0.mood > 0 && inWeek($0.createdAt) }.map { ($0.createdAt.startOfDay, $0.mood) }.sorted { $0.0 < $1.0 },
            booksFinished: books.filter { $0.status == .read && inWeek($0.finishedAt) }.map(\.title),
            readingMinutes: Int(sessions.filter { inWeek($0.start) }.reduce(0) { $0 + $1.minutes }),
            focusMinutes: FocusTimer.minutes(focus, since: start, until: end),
            events: events.filter { inWeek($0.start) }.count + apple.events(from: start, to: end).count
                + GoogleCalendarStore.shared.events(from: start, to: end).count,
            bucketDone: bucket.filter { $0.isDone && inWeek($0.doneAt) }.map(\.title))
    }

    var asText: String {
        var l = ["Week \(label)."]
        l.append("Tasks completed (\(tasksDone.count)): \(tasksDone.prefix(25).joined(separator: "; "))")
        l.append("Overdue now: \(overdue)")
        l.append("Habits: " + (habits.isEmpty ? "none" : habits.map { "\($0.name) \($0.done)/\($0.target)" }.joined(separator: ", ")))
        l.append("Spent this week: \(Fmt.money(spent)); top: \(topCategories.map { "\($0.0) \(Fmt.money($0.1))" }.joined(separator: ", "))")
        l.append("Month so far: \(Fmt.money(monthSpent)) of \(Fmt.money(budget)) budget")
        l.append("Mood (1-5) by day: " + (moods.isEmpty ? "not recorded" : moods.map { "\($0.day.formatted(.dateTime.weekday())) \($0.mood)" }.joined(separator: ", ")))
        l.append("Focused work: \(focusMinutes) min")
        l.append("Reading: \(readingMinutes) min; finished: \(booksFinished.isEmpty ? "none" : booksFinished.joined(separator: ", "))")
        l.append("Events: \(events). Bucket list ticked off: \(bucketDone.isEmpty ? "none" : bucketDone.joined(separator: ", "))")
        return l.joined(separator: "\n")
    }
}

/// Ask's take on the week, plus three focus items for next week.
struct WeeklyReflection: Codable, Equatable {
    struct Focus: Codable, Equatable, Identifiable {
        var id: String { title }
        let title: String
        let area: String
        let why: String
    }
    let headline: String
    let wins: [String]
    let struggles: [String]
    let insight: String
    let focus: [Focus]
}

/// One pattern found in your data, e.g. "Mood is 0.8 higher on days you work out".
struct LifePattern: Identifiable, Codable, Equatable {
    var id: String { title }
    let title: String
    let detail: String
}

@MainActor
final class ReviewStore: ObservableObject {
    static let shared = ReviewStore()

    @Published private(set) var reflection: WeeklyReflection?
    @Published private(set) var patterns: [LifePattern] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingPatterns = false
    @Published var error: String?

    private func key(_ week: Date) -> String { "weeklyReview-\(DayKey.key(week.startOfWeek))" }

    func load(week: Date) {
        reflection = UserDefaults.standard.data(forKey: key(week)).flatMap { try? JSONDecoder().decode(WeeklyReflection.self, from: $0) }
        patterns = UserDefaults.standard.data(forKey: "lifePatterns").flatMap { try? JSONDecoder().decode([LifePattern].self, from: $0) } ?? []
    }

    func reflect(on stats: WeekStats, force: Bool = false) async {
        guard !loading, !Snapshot.isActive, let claude = ClaudeClient() else { return }
        if reflection != nil && !force { return }
        loading = true
        error = nil
        defer { loading = false }
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "headline": ["type": "string"],
                "wins": ["type": "array", "items": ["type": "string"]],
                "struggles": ["type": "array", "items": ["type": "string"]],
                "insight": ["type": "string"],
                "focus": ["type": "array", "items": [
                    "type": "object",
                    "properties": ["title": ["type": "string"], "area": ["type": "string", "enum": Area.allCases.map(\.rawValue)],
                                   "why": ["type": "string"]],
                    "required": ["title", "area", "why"], "additionalProperties": false,
                ]],
            ],
            "required": ["headline", "wins", "struggles", "insight", "focus"],
            "additionalProperties": false,
        ]
        let system = """
        You are \(AssistantName.current), writing the user's weekly review in their personal organizer. Use only the data given.
        - headline: one warm sentence capturing the week.
        - wins: up to 3 specific things that went well (name tasks, habits, books).
        - struggles: up to 2 honest, kind observations about what slipped. Empty if nothing did.
        - insight: one sentence connecting two things in the data (e.g. mood and habits), only if the data supports it.
        - focus: exactly 3 concrete, small focus items for next week, each a doable task title (under 8 words), an area, and a short why.
        Plain text, no markdown. Encouraging, never preachy.
        """
        do {
            let r = try await claude.structured(WeeklyReflection.self, system: system, user: stats.asText, schema: schema, effort: "medium")
            reflection = r
            if let data = try? JSONEncoder().encode(r) { UserDefaults.standard.set(data, forKey: key(stats.start)) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Ask turns the measured patterns into plain-language insights (it may not add new claims).
    func explain(_ facts: [MoodFact]) async {
        guard !loadingPatterns, !Snapshot.isActive, let claude = ClaudeClient(), !facts.isEmpty else { return }
        loadingPatterns = true
        defer { loadingPatterns = false }
        struct Out: Decodable { let patterns: [LifePattern] }
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["patterns": ["type": "array", "items": [
                "type": "object", "properties": ["title": ["type": "string"], "detail": ["type": "string"]],
                "required": ["title", "detail"], "additionalProperties": false,
            ]]],
            "required": ["patterns"], "additionalProperties": false,
        ]
        let system = """
        You turn measured patterns from someone's own life data into up to 4 short insights for them.
        Use ONLY the facts given; never invent numbers. Prefer the strongest and most useful ones; mention how many days the pattern is based on when it's small.
        title: under 9 words, like "You're happier on gym days". detail: 1 sentence with the numbers and a gentle, practical suggestion.
        These are correlations, not proof: don't claim causes.
        """
        let text = facts.map(\.text).joined(separator: "\n")
        if let out = try? await claude.structured(Out.self, system: system, user: text, schema: schema, effort: "low") {
            patterns = out.patterns
            if let data = try? JSONEncoder().encode(out.patterns) { UserDefaults.standard.set(data, forKey: "lifePatterns") }
        }
    }
}

/// A measured difference in mood, e.g. on days a habit was done vs not.
struct MoodFact: Identifiable {
    let id = UUID()
    let text: String
    let delta: Double
}

@MainActor
enum MoodInsights {
    struct Point: Identifiable { let day: Date; let mood: Int; var id: Date { day } }

    static func series(context: ModelContext, days: Int = 90) -> [Point] {
        let since = Date.now.startOfDay.adding(days: -days)
        let notes = (try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.isJournal && $0.mood > 0 }))) ?? []
        var byDay: [Date: Int] = [:]
        for n in notes where n.createdAt >= since { byDay[n.createdAt.startOfDay] = n.mood }
        return byDay.map { Point(day: $0.key, mood: $0.value) }.sorted { $0.day < $1.day }
    }

    /// Average mood per weekday (1 = Sunday).
    static func byWeekday(_ points: [Point]) -> [(weekday: Int, mood: Double, count: Int)] {
        Dictionary(grouping: points) { Calendar.current.component(.weekday, from: $0.day) }
            .map { ($0.key, Double($0.value.reduce(0) { $0 + $1.mood }) / Double($0.value.count), $0.value.count) }
            .sorted { $0.0 < $1.0 }
    }

    /// Mood differences worth mentioning: habits done vs not, spending, busy days, reading. Needs 3+ days on each side.
    static func facts(context: ModelContext, apple: AppleSync, points: [Point]) -> [MoodFact] {
        guard points.count >= 5 else { return [] }
        var out: [MoodFact] = []
        func avg(_ xs: [Point]) -> Double { Double(xs.reduce(0) { $0 + $1.mood }) / Double(max(xs.count, 1)) }
        func compare(_ label: String, yes: [Point], no: [Point], yesName: String, noName: String) {
            guard yes.count >= 3, no.count >= 3 else { return }
            let d = avg(yes) - avg(no)
            guard abs(d) >= 0.3 else { return }
            out.append(MoodFact(text: "\(label): average mood \(String(format: "%.1f", avg(yes))) on \(yesName) (\(yes.count) days) vs \(String(format: "%.1f", avg(no))) on \(noName) (\(no.count) days).", delta: abs(d)))
        }

        for h in (try? context.fetch(FetchDescriptor<Habit>())) ?? [] {
            compare("Habit “\(h.name)”", yes: points.filter { h.isDone(on: $0.day) }, no: points.filter { !h.isDone(on: $0.day) },
                    yesName: "days it was done", noName: "days it wasn't")
        }
        let txns = ((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).filter(\.isExpense)
        let spentByDay = Dictionary(grouping: txns) { $0.date.startOfDay }.mapValues { -$0.reduce(0) { $0 + $1.amount } }
        let spends = points.map { spentByDay[$0.day] ?? 0 }.sorted()
        if let median = spends.isEmpty ? nil : spends[spends.count / 2], median > 0 {
            compare("Spending", yes: points.filter { (spentByDay[$0.day] ?? 0) > median }, no: points.filter { (spentByDay[$0.day] ?? 0) <= median },
                    yesName: "higher-spending days (over \(Fmt.money(median)))", noName: "lower-spending days")
        }
        let food = Dictionary(grouping: txns.filter { $0.category == "Food" }) { $0.date.startOfDay }
        compare("Food spending", yes: points.filter { food[$0.day] != nil }, no: points.filter { food[$0.day] == nil },
                yesName: "days with food purchases", noName: "days without")
        let local = (try? context.fetch(FetchDescriptor<EventItem>())) ?? []
        func eventCount(_ d: Date) -> Int {
            local.filter { $0.start.isSameDay(as: d) }.count + apple.events(from: d, to: d.adding(days: 1)).count
                + GoogleCalendarStore.shared.events(from: d, to: d.adding(days: 1)).count
        }
        compare("Busy days", yes: points.filter { eventCount($0.day) >= 3 }, no: points.filter { eventCount($0.day) < 3 },
                yesName: "days with 3+ events", noName: "quieter days")
        let sessions = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        let readDays = Set(sessions.map { $0.start.startOfDay })
        compare("Reading", yes: points.filter { readDays.contains($0.day) }, no: points.filter { !readDays.contains($0.day) },
                yesName: "days you read", noName: "days you didn't")
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let doneByDay = Dictionary(grouping: tasks.compactMap(\.completedAt)) { $0.startOfDay }.mapValues(\.count)
        compare("Getting things done", yes: points.filter { (doneByDay[$0.day] ?? 0) >= 3 }, no: points.filter { (doneByDay[$0.day] ?? 0) < 3 },
                yesName: "days you finished 3+ tasks", noName: "other days")
        return out.sorted { $0.delta > $1.delta }
    }
}
