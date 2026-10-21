import Foundation
import SwiftData

// MARK: - Life areas

enum Area: String, CaseIterable, Codable, Identifiable {
    case health, work, study, money, home, social, personal

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .health: "heart.fill"
        case .work: "briefcase.fill"
        case .study: "book.fill"
        case .money: "dollarsign.circle.fill"
        case .home: "house.fill"
        case .social: "person.2.fill"
        case .personal: "sparkles"
        }
    }
}

enum Recurrence: String, CaseIterable, Codable, Identifiable {
    case none, daily, weekly, monthly
    var id: String { rawValue }
    var title: String { self == .none ? "Never" : rawValue.capitalized }

    func next(after date: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .none: return nil
        case .daily: return cal.date(byAdding: .day, value: 1, to: date)
        case .weekly: return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
        }
    }
}

// MARK: - Tasks

@Model
final class TaskItem {
    var title: String
    var notes: String
    var areaRaw: String
    var due: Date?
    /// 0 none, 1 low, 2 medium, 3 high
    var priority: Int
    var isDone: Bool
    var completedAt: Date?
    var createdAt: Date
    var recurrenceRaw: String

    init(title: String, area: Area = .personal, due: Date? = nil, priority: Int = 0,
         notes: String = "", recurrence: Recurrence = .none) {
        self.title = title
        self.notes = notes
        self.areaRaw = area.rawValue
        self.due = due
        self.priority = priority
        self.isDone = false
        self.completedAt = nil
        self.createdAt = .now
        self.recurrenceRaw = recurrence.rawValue
    }

    var area: Area {
        get { Area(rawValue: areaRaw) ?? .personal }
        set { areaRaw = newValue.rawValue }
    }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    var isOverdue: Bool {
        guard let due, !isDone else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    /// Marks the task done; for repeating tasks, schedules the next occurrence.
    func complete(in context: ModelContext) {
        isDone = true
        completedAt = .now
        if let due, let next = recurrence.next(after: due) {
            context.insert(TaskItem(title: title, area: area, due: next, priority: priority,
                                    notes: notes, recurrence: recurrence))
        }
    }
}

// MARK: - Events

@Model
final class EventItem {
    var title: String
    var start: Date
    var end: Date
    var areaRaw: String
    var location: String
    var notes: String

    init(title: String, start: Date, end: Date, area: Area = .personal, location: String = "", notes: String = "") {
        self.title = title
        self.start = start
        self.end = end
        self.areaRaw = area.rawValue
        self.location = location
        self.notes = notes
    }

    var area: Area {
        get { Area(rawValue: areaRaw) ?? .personal }
        set { areaRaw = newValue.rawValue }
    }
}

// MARK: - Habits

@Model
final class Habit {
    var name: String
    var symbol: String
    var areaRaw: String
    var targetPerWeek: Int
    var createdAt: Date
    /// Completed days as "yyyy-MM-dd" keys.
    var doneDays: [String]

    init(name: String, symbol: String = "checkmark", area: Area = .health, targetPerWeek: Int = 7) {
        self.name = name
        self.symbol = symbol
        self.areaRaw = area.rawValue
        self.targetPerWeek = targetPerWeek
        self.createdAt = .now
        self.doneDays = []
    }

    var area: Area {
        get { Area(rawValue: areaRaw) ?? .health }
        set { areaRaw = newValue.rawValue }
    }

    func isDone(on day: Date) -> Bool { doneDays.contains(DayKey.key(day)) }

    func toggle(_ day: Date) {
        let key = DayKey.key(day)
        if let i = doneDays.firstIndex(of: key) { doneDays.remove(at: i) } else { doneDays.append(key) }
    }

    /// Consecutive days completed, ending today (or yesterday if today isn't done yet).
    var currentStreak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if !isDone(on: day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while isDone(on: day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    var doneThisWeek: Int {
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now)!
        return (0..<7).filter { isDone(on: week.start.adding(days: $0)) }.count
    }
}

// MARK: - Money

@Model
final class Transaction {
    var title: String
    /// Negative = expense, positive = income.
    var amount: Double
    var category: String
    var date: Date
    var isRecurring: Bool
    /// "" for manual entries, "gmail:<address>" for ones imported from email.
    var source: String = ""
    /// Gmail message id, used to never import the same email twice.
    var sourceID: String = ""
    /// What the receipt said before converting to your currency (e.g. 12.99 USD).
    var originalAmount: Double = 0
    var originalCurrency: String = ""

    init(title: String, amount: Double, category: String = "General", date: Date = .now, isRecurring: Bool = false) {
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.isRecurring = isRecurring
    }

    var isExpense: Bool { amount < 0 }
    var fromEmail: Bool { source.hasPrefix("gmail:") }
}

enum MoneyCategory {
    static let all = ["Food", "Transport", "Bills", "Shopping", "Health", "Fun", "Subscriptions", "Income", "General"]
}

// MARK: - Notes & journal

@Model
final class Note {
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var isJournal: Bool
    var pinned: Bool
    /// 0 = not set, 1 (rough) … 5 (great). Used by the journal.
    var mood: Int = 0
    /// True once the user picks a mood themselves, so Claude's estimate never overrides it.
    var moodSetByUser: Bool = false
    /// Journal check-in conversation with Claude, encoded `[JournalTurn]`.
    var chatData: Data? = nil

    init(title: String, body: String = "", isJournal: Bool = false, date: Date = .now) {
        self.title = title
        self.body = body
        self.createdAt = date
        self.updatedAt = date
        self.isJournal = isJournal
        self.pinned = false
    }
}

// MARK: - Reading

enum ReadingStatus: String, CaseIterable, Codable, Identifiable {
    case reading, toRead, read, dnf
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reading: "Reading"
        case .toRead: "To read"
        case .read: "Read"
        case .dnf: "Didn't finish"
        }
    }
    var symbol: String {
        switch self {
        case .reading: "book.fill"
        case .toRead: "bookmark.fill"
        case .read: "checkmark.seal.fill"
        case .dnf: "xmark.circle.fill"
        }
    }
}

@Model
final class Book {
    var title: String = ""
    var author: String = ""
    var statusRaw: String = ReadingStatus.toRead.rawValue
    /// 0 = unrated, 1…5 stars
    var rating: Int = 0
    var categories: [String] = []
    var notes: String = ""
    var coverURL: String = ""
    var isbn: String = ""
    var pageCount: Int = 0
    /// 0…1
    var progress: Double = 0
    var year: Int = 0
    var addedAt: Date = Date.now
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    /// manual, openlibrary, goodreads, apple-books, kindle
    var source: String = "manual"
    /// Stable key used to avoid duplicate imports.
    var externalID: String = ""

    init(title: String, author: String, status: ReadingStatus = .toRead, source: String = "manual") {
        self.title = title
        self.author = author
        self.statusRaw = status.rawValue
        self.source = source
        self.addedAt = .now
    }

    var status: ReadingStatus {
        get { ReadingStatus(rawValue: statusRaw) ?? .toRead }
        set {
            if newValue == .reading, startedAt == nil { startedAt = .now }
            if newValue == .read {
                if finishedAt == nil { finishedAt = .now }
                progress = 1
            }
            statusRaw = newValue.rawValue
        }
    }

    /// Lowercased "title|author" used to match books across sources.
    var matchKey: String { Book.matchKey(title: title, author: author) }

    static func matchKey(title: String, author: String) -> String {
        let t = title.lowercased().components(separatedBy: CharacterSet(charactersIn: ":(")).first ?? ""
        let a = author.lowercased().split(separator: " ").last.map(String.init) ?? ""
        return t.trimmingCharacters(in: .whitespaces) + "|" + a
    }
}

@Model
final class BookCategory {
    var name: String = ""
    var colorIndex: Int = 0
    var symbol: String = "tag.fill"
    var createdAt: Date = Date.now

    init(name: String, colorIndex: Int, symbol: String = "tag.fill") {
        self.name = name
        self.colorIndex = colorIndex
        self.symbol = symbol
        self.createdAt = .now
    }
}

// MARK: - Date helpers

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(_ date: Date) -> String { formatter.string(from: date) }
}

extension Date {
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self)! }
    func adding(minutes: Int) -> Date { Calendar.current.date(byAdding: .minute, value: minutes, to: self)! }
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    func isSameDay(as other: Date) -> Bool { Calendar.current.isDate(self, inSameDayAs: other) }
    var startOfWeek: Date { Calendar.current.dateInterval(of: .weekOfYear, for: self)!.start }
    var startOfMonth: Date { Calendar.current.dateInterval(of: .month, for: self)!.start }
}
