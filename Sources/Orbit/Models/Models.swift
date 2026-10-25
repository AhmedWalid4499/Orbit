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
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
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
    /// A reminder at an exact time ("remind me at 6pm").
    var remindAt: Date? = nil
    /// A reminder at a place: "when I get home", "when I'm near Carrefour". Empty name means none.
    var placeName: String = ""
    var placeLat: Double = 0
    var placeLon: Double = 0
    /// Remind when leaving the place instead of arriving.
    var placeOnLeave: Bool = false

    var hasPlaceReminder: Bool { !placeName.isEmpty && (placeLat != 0 || placeLon != 0) }
    var placeReminderText: String {
        let home = placeName == "Home"
        if placeOnLeave { return home ? "When you leave home" : "When you leave \(placeName)" }
        return home ? "When you get home" : placeName == "Work" ? "When you get to work" : "When you get to \(placeName)"
    }

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
            let t = TaskItem(title: title, area: area, due: next, priority: priority, notes: notes, recurrence: recurrence)
            t.placeName = placeName; t.placeLat = placeLat; t.placeLon = placeLon; t.placeOnLeave = placeOnLeave
            if let r = remindAt { t.remindAt = next.startOfDay.addingTimeInterval(r.timeIntervalSince(r.startOfDay)) }
            context.insert(t)
        }
    }
}

// MARK: - Events

@Model
final class EventItem {
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
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
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
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
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
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
    /// The bank account or card it went through (a BankAccount uuid), "" if unknown.
    var account: String = ""

    init(title: String, amount: Double, category: String = "General", date: Date = .now, isRecurring: Bool = false) {
        self.title = title
        self.amount = amount
        // A category you taught Orbit for this merchant wins over any guess (see MerchantRules).
        self.category = amount < 0 ? MerchantRules.category(for: title) ?? category : category
        self.date = date
        self.isRecurring = isRecurring
    }

    var isExpense: Bool { amount < 0 }
    var fromEmail: Bool { source.hasPrefix("gmail:") }
    /// Logged by a Shortcuts automation from a bank SMS ("sms") or an Apple Pay tap ("wallet").
    var fromBank: Bool { source == "sms" || source == "wallet" }
}

enum MoneyCategory {
    static let all = ["Food", "Transport", "Bills", "Shopping", "Health", "Fun", "Subscriptions", "Income", "General"]
}

// MARK: - Notes & journal

@Model
final class Note {
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
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
        case .reading: "Currently reading"
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
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
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
    /// manual, openlibrary, goodreads, apple-books, kindle (where the book first came from)
    var source: String = "manual"
    /// Every library this book appears in (a Kindle book can also be on Goodreads).
    var sources: [String] = []
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
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
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

// MARK: - Reading sessions & highlights

/// Time spent reading a book (started and stopped with the reading timer).
@Model
final class ReadingSession {
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
    var bookUUID: String = ""
    var bookTitle: String = ""
    var start: Date = Date.now
    var end: Date? = nil
    var pagesRead: Int = 0

    init() {}

    init(book: Book) {
        self.bookUUID = book.uuid
        self.bookTitle = book.title
        self.start = .now
    }

    var minutes: Double { ((end ?? .now).timeIntervalSince(start)) / 60 }
}

/// A passage you highlighted (from Kindle or added by hand).
@Model
final class Highlight {
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
    var bookUUID: String = ""
    var bookTitle: String = ""
    var author: String = ""
    var text: String = ""
    var note: String = ""
    var location: String = ""
    var createdAt: Date = Date.now
    /// kindle-clippings, kindle-notebook, kindle-app, manual
    var source: String = "manual"
    /// Stable key so re-importing doesn't duplicate highlights.
    var externalID: String = ""

    init(bookTitle: String, author: String, text: String, source: String = "manual") {
        self.bookTitle = bookTitle
        self.author = author
        self.text = text
        self.source = source
        self.createdAt = .now
    }
}

// MARK: - Subscriptions

enum BillingCycle: String, CaseIterable, Codable, Identifiable {
    case weekly, monthly, quarterly, yearly
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// How many charges per month, for monthly totals.
    var perMonth: Double {
        switch self { case .weekly: 52.0 / 12; case .monthly: 1; case .quarterly: 1.0 / 3; case .yearly: 1.0 / 12 }
    }
    func next(after d: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .weekly: return cal.date(byAdding: .day, value: 7, to: d)!
        case .monthly: return cal.date(byAdding: .month, value: 1, to: d)!
        case .quarterly: return cal.date(byAdding: .month, value: 3, to: d)!
        case .yearly: return cal.date(byAdding: .year, value: 1, to: d)!
        }
    }
}

/// A recurring charge: found in your transactions or email, or added by hand.
@Model
final class Subscription {
    /// Permanent id used to sync this item between devices.
    var uuid: String = ""
    var name: String = ""
    /// Per charge, in your home currency.
    var amount: Double = 0
    var originalAmount: Double = 0
    var originalCurrency: String = ""
    var cycleRaw: String = BillingCycle.monthly.rawValue
    var nextDate: Date? = nil
    var lastCharged: Date? = nil
    var category: String = "Subscriptions"
    /// active, trial, cancelled
    var status: String = "active"
    var trialEnds: Date? = nil
    /// Set when a charge comes in at a different price.
    var previousAmount: Double = 0
    var priceChangedAt: Date? = nil
    /// manual, detected (from transactions), email
    var source: String = "manual"
    var notes: String = ""
    var createdAt: Date = Date.now

    init(name: String, amount: Double, cycle: BillingCycle = .monthly) {
        self.name = name
        self.amount = amount
        self.cycleRaw = cycle.rawValue
        self.createdAt = .now
    }

    var cycle: BillingCycle {
        get { BillingCycle(rawValue: cycleRaw) ?? .monthly }
        set { cycleRaw = newValue.rawValue }
    }
    var monthlyCost: Double { status == "cancelled" ? 0 : amount * cycle.perMonth }
    var priceWentUp: Bool { previousAmount > 0 && amount > previousAmount * 1.01 }
}

// MARK: - Bills

/// A bill that's due on the same day every month (rent, internet, phone). It counts as paid when you mark it,
/// or when a matching expense comes in (a bank text, an email receipt, one you logged).
@Model
final class Bill {
    /// Permanent id used to sync this item between devices.
    var uuid: String = ""
    var name: String = ""
    /// Usual amount in your home currency (0 = it varies).
    var amount: Double = 0
    /// Day of the month it's due, 1–31 (the last day in shorter months).
    var dueDay: Int = 1
    /// Remind this many days before.
    var remindDays: Int = 3
    /// Words in the expense that mean this bill was paid, comma separated ("vodafone, vf cash"). Empty: the name.
    var match: String = ""
    var category: String = "Bills"
    /// Months marked paid by hand, as yyyy-MM.
    var paidMonths: [String] = []
    var notes: String = ""
    var createdAt: Date = Date.now

    init(name: String, amount: Double = 0, dueDay: Int = 1) {
        self.name = name
        self.amount = amount
        self.dueDay = dueDay
        self.createdAt = .now
    }

    /// The words to look for in an expense's title.
    var matchWords: [String] {
        let words = (match.isEmpty ? name : match).lowercased().split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 2 }
        return words
    }
}

// MARK: - Bank accounts

/// A bank account, card or wallet. Orbit adds them by itself from bank texts and Apple Pay (bank + last 4 digits),
/// and keeps the available balance the latest text mentioned. You can also add, rename and recolour them.
@Model
final class BankAccount {
    /// Permanent id used to sync this item between devices.
    var uuid: String = ""
    /// "CIB", "NBE", "Vodafone Cash"…
    var name: String = ""
    var last4: String = ""
    /// card, account, wallet or cash
    var kind: String = "card"
    var colorIndex: Int = 0
    /// Latest available balance (or credit left) seen in a bank text; 0 with no date means unknown.
    var balance: Double = 0
    var balanceAt: Date? = nil
    var createdAt: Date = Date.now

    init(name: String, last4: String = "", kind: String = "card") {
        self.name = name
        self.last4 = last4
        self.kind = kind
        self.createdAt = .now
    }

    var title: String { last4.isEmpty ? name : "\(name) ••\(last4)" }
}

// MARK: - Goals

enum GoalKind: String, CaseIterable, Identifiable {
    /// Books finished since the goal started.
    case books
    /// Money saved (income minus spending) since the goal started.
    case save
    /// Days a habit was done since the goal started.
    case habit
    /// A checklist of steps (also used for bucket-list dreams).
    case steps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .books: "Read books"
        case .save: "Save money"
        case .habit: "Keep a habit"
        case .steps: "Steps"
        }
    }
    var symbol: String {
        switch self {
        case .books: "books.vertical.fill"
        case .save: "banknote.fill"
        case .habit: "flame.fill"
        case .steps: "checklist"
        }
    }
}

/// A goal whose progress fills in by itself from Reading, Money or a habit, or from ticking off steps.
@Model
final class Goal {
    /// Permanent id used to sync this item between devices.
    var uuid: String = ""
    var title: String = ""
    var kindRaw: String = GoalKind.steps.rawValue
    /// Books, amount of money or days. Steps goals use the number of steps.
    var target: Double = 0
    /// Progress counts from this day.
    var start: Date = Date.now
    var deadline: Date? = nil
    /// The habit a habit goal follows.
    var habitUUID: String = ""
    /// The bucket-list dream this goal makes happen ("" if none).
    var bucketUUID: String = ""
    var steps: [String] = []
    /// Steps from `steps` that are done.
    var stepsDone: [String] = []
    var doneAt: Date? = nil
    var createdAt: Date = Date.now

    init(title: String, kind: GoalKind = .steps, target: Double = 0) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.target = target
        self.start = Date.now.startOfDay
        self.createdAt = .now
    }

    var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .steps }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Documents

enum DocKind: String, CaseIterable, Codable, Identifiable {
    case passport, id, license, visa, car, insurance, warranty, membership, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .id: "ID card"
        case .license: "Driving licence"
        case .car: "Car registration"
        default: rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .passport: "globe.europe.africa.fill"
        case .id: "person.text.rectangle.fill"
        case .license: "car.fill"
        case .visa: "airplane"
        case .car: "car.side.fill"
        case .insurance: "shield.lefthalf.filled"
        case .warranty: "checkmark.seal.fill"
        case .membership: "creditcard.fill"
        case .other: "doc.text.fill"
        }
    }
}

/// Something with an expiry date: passport, ID, licence, insurance, a warranty…
@Model
final class DocItem {
    /// Permanent id used to sync this item between devices.
    var uuid: String = ""
    var title: String = ""
    var kindRaw: String = DocKind.other.rawValue
    /// Keep this short (e.g. last 4 digits); Orbit isn't a password manager.
    var number: String = ""
    var issuer: String = ""
    var issued: Date? = nil
    var expires: Date? = nil
    /// Remind this many days before it expires.
    var remindDays: Int = 30
    var notes: String = ""
    /// manual, email
    var source: String = "manual"
    /// Gmail message id for warranties found in email (avoids duplicates).
    var sourceID: String = ""
    var createdAt: Date = Date.now

    init(title: String, kind: DocKind = .other, expires: Date? = nil) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.expires = expires
        self.createdAt = .now
    }

    var kind: DocKind {
        get { DocKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
    var daysLeft: Int? {
        expires.map { Calendar.current.dateComponents([.day], from: Date.now.startOfDay, to: $0.startOfDay).day ?? 0 }
    }
}

// MARK: - Focus

/// A focus (Pomodoro) block, optionally on a task. An open block has no end; it survives restarts.
@Model
final class FocusSession {
    /// Permanent id used to sync this item between devices.
    var uuid: String = ""
    var taskUUID: String = ""
    var taskTitle: String = ""
    var start: Date = Date.now
    var end: Date? = nil
    var plannedMinutes: Int = 25

    init() {}

    init(task: TaskItem?, minutes: Int) {
        self.taskUUID = task?.uuid ?? ""
        self.taskTitle = task?.title ?? ""
        self.start = .now
        self.plannedMinutes = minutes
    }

    var plannedEnd: Date { start.addingTimeInterval(Double(plannedMinutes) * 60) }
    var minutes: Double { ((end ?? .now).timeIntervalSince(start)) / 60 }
}

// MARK: - Evening plan

/// Tomorrow's top three, chosen the evening before. `day` is yyyy-MM-dd of the day it's for.
@Model
final class DayPlan {
    /// Permanent id used to sync this item between devices.
    var uuid: String = ""
    var day: String = ""
    /// Up to three priorities, in order.
    var top: [String] = []
    /// The task each priority came from ("" for one typed in).
    var taskUUIDs: [String] = []
    var note: String = ""
    var createdAt: Date = Date.now

    init(day: String) {
        self.day = day
        self.createdAt = .now
    }
}

// MARK: - Trips

/// A trip, often from a travel item on the bucket list.
@Model
final class Trip {
    /// Permanent id used to sync this item between devices.
    var uuid: String = ""
    var title: String = ""
    var destination: String = ""
    var start: Date? = nil
    var end: Date? = nil
    /// The bucket-list item this trip makes happen ("" if none).
    var bucketUUID: String = ""
    /// Budget in the home currency (0 = none).
    var budget: Double = 0
    var notes: String = ""
    var packing: [String] = []
    /// Items from `packing` that are packed.
    var packed: [String] = []
    var createdAt: Date = Date.now

    init(title: String, destination: String = "") {
        self.title = title
        self.destination = destination
        self.createdAt = .now
    }

    var nights: Int? {
        guard let start, let end else { return nil }
        return Calendar.current.dateComponents([.day], from: start.startOfDay, to: end.startOfDay).day
    }
}

enum BookingKind: String, CaseIterable, Identifiable {
    case flight, hotel, train, car, activity, other
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .flight: "airplane"
        case .hotel: "bed.double.fill"
        case .train: "tram.fill"
        case .car: "car.fill"
        case .activity: "ticket.fill"
        case .other: "suitcase.fill"
        }
    }
}

/// A flight, hotel or other booking, added by hand or found in email.
@Model
final class Booking {
    /// Permanent id used to sync this item between devices.
    var uuid: String = ""
    /// The trip it belongs to ("" while unassigned).
    var tripUUID: String = ""
    var kindRaw: String = BookingKind.other.rawValue
    var title: String = ""
    var provider: String = ""
    var confirmation: String = ""
    var location: String = ""
    var start: Date? = nil
    var end: Date? = nil
    /// Cost in the home currency (positive).
    var amount: Double = 0
    /// manual or email
    var source: String = "manual"
    /// Gmail message id for bookings found in email.
    var sourceID: String = ""
    var createdAt: Date = Date.now

    init(title: String, kind: BookingKind = .other) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.createdAt = .now
    }

    var kind: BookingKind {
        get { BookingKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Bucket list

enum BucketKind: String, CaseIterable, Identifiable {
    case travel, experience, adventure, learn, create, people, other
    /// A real place you want to go back to or try: lives in Bucket list › Go to, with a map pin.
    case place
    var id: String { rawValue }
    var title: String { self == .people ? "People" : self == .place ? "Go to" : rawValue.capitalized }
    /// The dream kinds (everything except Go to places).
    static var dreams: [BucketKind] { allCases.filter { $0 != .place } }
    var symbol: String {
        switch self {
        case .travel: "airplane"
        case .experience: "sparkles"
        case .adventure: "mountain.2.fill"
        case .learn: "graduationcap.fill"
        case .create: "paintbrush.fill"
        case .people: "person.2.fill"
        case .other: "star.fill"
        case .place: "mappin.and.ellipse"
        }
    }
}

/// What kind of place a Go to pin is.
enum PlaceCategory: String, CaseIterable, Identifiable {
    case food, cafe, bar, shop, museum, park, attraction, hotel, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .food: "Food"
        case .cafe: "Café"
        case .bar: "Bar"
        case .shop: "Shop"
        case .museum: "Museum"
        case .park: "Park"
        case .attraction: "Sight"
        case .hotel: "Stay"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .bar: "wineglass.fill"
        case .shop: "bag.fill"
        case .museum: "building.columns.fill"
        case .park: "leaf.fill"
        case .attraction: "star.fill"
        case .hotel: "bed.double.fill"
        case .other: "mappin"
        }
    }
}

@Model
final class BucketItem {
    /// Permanent id used to sync this item between devices (assigned on first launch for older items).
    var uuid: String = ""
    var title: String = ""
    var notes: String = ""
    var kindRaw: String = BucketKind.experience.rawValue
    /// When you plan or hope to do it (optional). Items with a date show up under "Looking forward to".
    var targetDate: Date? = nil
    /// 1 = nice to do … 3 = can't wait
    var excitement: Int = 2
    var isDone: Bool = false
    var doneAt: Date? = nil
    var createdAt: Date = Date.now
    // Go to places only (kind == .place). isDone means "been there".
    var placeCategoryRaw: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    /// Link the place came from (Google or Apple Maps), or an Apple Maps link Orbit made.
    var mapURL: String = ""

    var placeCategory: PlaceCategory {
        get { PlaceCategory(rawValue: placeCategoryRaw) ?? .other }
        set { placeCategoryRaw = newValue.rawValue }
    }
    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    init(title: String, kind: BucketKind = .experience, notes: String = "", targetDate: Date? = nil, excitement: Int = 2) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.notes = notes
        self.targetDate = targetDate
        self.excitement = excitement
        self.createdAt = .now
    }

    var kind: BucketKind {
        get { BucketKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
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
