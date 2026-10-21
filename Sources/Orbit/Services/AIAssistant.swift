import Foundation
import SwiftData
import SwiftUI

struct MorningBrief: Codable, Equatable {
    var headline: String
    var summary: String
    var focus: [String]
    var heads_up: String
    var day: String = ""
    var generatedAt: Date = .now

    enum CodingKeys: String, CodingKey { case headline, summary, focus, heads_up, day, generatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headline = try c.decode(String.self, forKey: .headline)
        summary = try c.decode(String.self, forKey: .summary)
        focus = try c.decode([String].self, forKey: .focus)
        heads_up = try c.decode(String.self, forKey: .heads_up)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now
    }
}

/// Claude-powered features: the morning brief and smart quick capture.
@MainActor
final class AIAssistant: ObservableObject {
    static let shared = AIAssistant()

    enum BriefState: Equatable { case idle, loading, failed(String) }

    @Published private(set) var hasKey = Keychain.apiKey != nil
    @Published private(set) var brief: MorningBrief?
    @Published private(set) var briefState: BriefState = .idle

    @AppStorage("aiSmartCapture") var smartCaptureEnabled = true
    @AppStorage("aiMorningBrief") var morningBriefEnabled = true

    private let briefKey = "aiMorningBriefCache"

    private init() {
        if let data = UserDefaults.standard.data(forKey: briefKey),
           let cached = try? JSONDecoder().decode(MorningBrief.self, from: data) {
            brief = cached
        }
    }

    var smartCaptureActive: Bool { hasKey && smartCaptureEnabled }

    /// Debug snapshots only: shows a canned brief without calling the API.
    func previewBrief(_ b: MorningBrief) {
        hasKey = true
        brief = b
    }
    var hasTodaysBrief: Bool { brief?.day == DayKey.key(.now) }

    func setKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = Keychain.save(trimmed)
        hasKey = Keychain.apiKey != nil
        return ok
    }

    func reloadKey() { hasKey = Keychain.apiKey != nil }

    func removeKey() {
        Keychain.delete()
        hasKey = false
    }

    /// Cheap round trip to confirm the key works.
    func testConnection() async -> String {
        struct Pong: Decodable { let ok: Bool }
        guard let client = ClaudeClient() else { return ClaudeClient.Failure.noKey.localizedDescription }
        do {
            _ = try await client.structured(Pong.self, system: "Reply with ok=true.", user: "ping",
                                            schema: ["type": "object", "properties": ["ok": ["type": "boolean"]],
                                                     "required": ["ok"], "additionalProperties": false],
                                            effort: "low", maxTokens: 2000)
            return "Connected to \(ClaudeClient.model)."
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Morning brief

    /// Generates today's brief once per day unless `force` is set.
    func refreshBrief(context: ModelContext, apple: AppleSync, force: Bool = false) async {
        guard hasKey, morningBriefEnabled, briefState != .loading, !Snapshot.isActive else { return }
        guard force || !hasTodaysBrief else { return }
        guard let client = ClaudeClient() else { return }

        briefState = .loading
        let snapshot = Self.snapshot(context: context, apple: apple)
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "headline": ["type": "string"],
                "summary": ["type": "string"],
                "focus": ["type": "array", "items": ["type": "string"]],
                "heads_up": ["type": "string"],
            ],
            "required": ["headline", "summary", "focus", "heads_up"],
            "additionalProperties": false,
        ]
        let system = """
        You write the morning brief at the top of a personal life-organizer app. The reader is the app's owner.
        Use only the data provided; never invent events, tasks or numbers. Write like a thoughtful friend: warm, concrete, short.
        - headline: at most 8 words capturing the shape of the day.
        - summary: 2-3 sentences covering what's on today and anything time-sensitive.
        - focus: up to 3 specific, doable suggestions for today, drawn from the tasks, habits, and money data. Each under 14 words.
        - heads_up: one thing that could slip (overdue task, budget pace, broken streak), or an empty string if nothing stands out.
        Plain text only, no markdown.
        """
        do {
            var result = try await client.structured(MorningBrief.self, system: system, user: snapshot,
                                                     schema: schema, effort: "medium")
            result.day = DayKey.key(.now)
            result.generatedAt = .now
            brief = result
            if let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: briefKey) }
            briefState = .idle
        } catch {
            briefState = .failed(error.localizedDescription)
        }
    }

    /// Plain-text summary of the user's day for the brief prompt.
    static func snapshot(context: ModelContext, apple: AppleSync) -> String {
        let now = Date.now, today = now.startOfDay, tomorrow = today.adding(days: 1)
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<EventItem>(sortBy: [SortDescriptor(\.start)]))) ?? []
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let txns = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let budget = UserDefaults.standard.object(forKey: "monthlyBudget") as? Double ?? 2000

        var lines: [String] = []
        lines.append("Now: \(now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()))")

        let todays = CalEntry.merge(local: events.filter { $0.start >= today && $0.start < tomorrow },
                                    apple: apple.events(from: today, to: tomorrow), google: GoogleCalendarStore.shared.events(from: today, to: tomorrow))
        lines.append("\nToday's events:")
        lines += todays.isEmpty ? ["(none)"] : todays.map {
            "- \($0.isAllDay ? "all day" : "\(Fmt.time($0.start))-\(Fmt.time($0.end))") \($0.title)\($0.area.map { " [\($0.title)]" } ?? "")"
        }

        let open = tasks.filter { !$0.isDone }
        let overdue = open.filter(\.isOverdue)
        let dueToday = open.filter { ($0.due.map { $0 >= today && $0 < tomorrow }) ?? false }
        let upcoming = open.filter { ($0.due.map { $0 >= tomorrow && $0 < today.adding(days: 7) }) ?? false }
        func taskLine(_ t: TaskItem) -> String {
            "- \(t.title) [\(t.area.title)]\(t.priority > 0 ? " priority \(t.priority)/3" : "")\(t.due.map { " due \(Fmt.relativeDay($0))" } ?? "")"
        }
        lines.append("\nOverdue tasks:"); lines += overdue.isEmpty ? ["(none)"] : overdue.map(taskLine)
        lines.append("\nDue today:"); lines += dueToday.isEmpty ? ["(none)"] : dueToday.map(taskLine)
        lines.append("\nDue in the next 7 days:"); lines += upcoming.isEmpty ? ["(none)"] : upcoming.prefix(10).map(taskLine)
        lines.append("\nUndated open tasks: \(open.filter { $0.due == nil }.count)")
        let reminders = apple.reminders.filter { ($0.due ?? .distantFuture) < tomorrow }
        if !reminders.isEmpty {
            lines.append("\nApple Reminders due:"); lines += reminders.map { "- \($0.title)" }
        }

        lines.append("\nHabits:")
        lines += habits.isEmpty ? ["(none)"] : habits.map {
            "- \($0.name): streak \($0.currentStreak) days, \($0.doneThisWeek)/\($0.targetPerWeek) this week, done today: \($0.isDone(on: today) ? "yes" : "no")"
        }

        let monthStart = now.startOfMonth
        let spent = -txns.filter { $0.isExpense && $0.date >= monthStart }.reduce(0) { $0 + $1.amount }
        let dayOfMonth = Calendar.current.component(.day, from: now)
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: now)!.count
        lines.append("\nMoney this month: spent \(Fmt.money(spent)) of \(Fmt.money(budget)) budget; day \(dayOfMonth) of \(daysInMonth).")

        if let journal = notes.filter({ $0.isJournal && $0.createdAt >= today.adding(days: -1) && $0.createdAt < today }).first,
           !journal.body.isEmpty {
            lines.append("\nYesterday's journal: \(journal.body.prefix(600))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Smart capture

    private struct CaptureItems: Decodable {
        struct Item: Decodable {
            let kind: String
            let title: String
            let area: String
            let date: String
            let has_time: Bool
            let duration_minutes: Int
            let amount: Double
            let category: String
            let priority: Int
        }
        let items: [Item]
    }

    private static let localISO: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    /// Turns free text into one or more items. Throws on API failure so callers can fall back to the local parser.
    func smartParse(_ text: String) async throws -> [QuickParser.Result] {
        guard let client = ClaudeClient() else { throw ClaudeClient.Failure.noKey }
        let areas = Area.allCases.map(\.rawValue)
        let kinds = ["task", "event", "expense", "income", "note", "journal"]
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "kind": ["type": "string", "enum": kinds],
                            "title": ["type": "string"],
                            "area": ["type": "string", "enum": areas],
                            "date": ["type": "string"],
                            "has_time": ["type": "boolean"],
                            "duration_minutes": ["type": "integer"],
                            "amount": ["type": "number"],
                            "category": ["type": "string", "enum": MoneyCategory.all],
                            "priority": ["type": "integer"],
                        ],
                        "required": ["kind", "title", "area", "date", "has_time", "duration_minutes", "amount", "category", "priority"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["items"],
            "additionalProperties": false,
        ]
        let now = Date.now
        let system = """
        You turn a quick note typed into a personal organizer into structured items.
        Current local time: \(Self.localISO.string(from: now)) (\(now.formatted(.dateTime.weekday(.wide)))), time zone \(TimeZone.current.identifier).
        Currency: \(Fmt.currencyCode).

        Rules:
        - Split the input into separate items only when it clearly contains several things ("dentist thu 3pm and buy milk" = 2 items). Otherwise return exactly one item.
        - kind: "event" when there is a specific time of day; "task" for things to do (with or without a date); "expense"/"income" when money changes hands; "note" for information to keep; "journal" for reflections about the user's own day or feelings.
        - title: short and clean, sentence case, without the date, time, amount, tags or priority marks.
        - area: the best fit among \(areas.joined(separator: ", ")). A #tag in the text wins.
        - date: local time as yyyy-MM-ddTHH:mm, resolving relative words ("tomorrow", "next fri") from the current time. Use 00:00 when there is a day but no time. Empty string when there is no date.
        - has_time: true only if a time of day was given or clearly implied ("lunch with Sam tomorrow" implies 12:30).
        - duration_minutes: for events, the stated or a sensible duration (default 60); otherwise 0.
        - amount: positive number for expense/income, otherwise 0.
        - category: money category for expense/income; "General" otherwise.
        - priority: 0-3. "!" marks = that many; words like "urgent" or "asap" = 3; otherwise 0.
        """
        let parsed = try await client.structured(CaptureItems.self, system: system, user: text,
                                                 schema: schema, effort: "low", maxTokens: 4000)
        return parsed.items.map { item in
            let kind: QuickParser.Kind = switch item.kind {
            case "event": .event
            case "expense": .expense
            case "income": .income
            case "note": .note
            case "journal": .journal
            default: .task
            }
            var date = item.date.isEmpty ? nil : Self.localISO.date(from: item.date)
            if let d = date, !item.has_time { date = d.startOfDay }
            let amount: Double? = switch kind {
            case .expense: -abs(item.amount)
            case .income: abs(item.amount)
            default: nil
            }
            return QuickParser.Result(kind: kind == .event && date == nil ? .task : kind,
                                      title: item.title, area: Area(rawValue: item.area), date: date,
                                      hasTime: item.has_time, amount: amount,
                                      category: amount == nil ? nil : item.category,
                                      priority: max(0, min(3, item.priority)),
                                      durationMinutes: item.duration_minutes > 0 ? item.duration_minutes : nil)
        }
    }
}
