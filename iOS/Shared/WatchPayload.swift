import Foundation

/// What the iPhone sends the watch (as WatchConnectivity application context) and what the watch sends back.
/// Compiled into both the iPhone app and the watch app, so keep it plain Codable with no app dependencies.
struct WatchSnapshot: Codable, Equatable {
    struct Event: Codable, Equatable, Identifiable, Hashable { var id: String; var title: String; var start: Date; var end: Date; var allDay: Bool }
    struct TaskRow: Codable, Equatable, Identifiable, Hashable { var id: String; var title: String; var priority: Int; var overdue: Bool }
    struct HabitRow: Codable, Equatable, Identifiable, Hashable { var id: String; var name: String; var symbol: String; var done: Bool; var streak: Int }
    struct Expense: Codable, Equatable, Identifiable, Hashable { var id: String; var title: String; var amount: String }
    struct Book: Codable, Equatable, Hashable { var title: String; var author: String; var progress: Double }

    var generatedAt: Date = .now
    var greetingName: String = ""
    var assistantName: String = "Ask"
    var currency: String = "USD"
    var events: [Event] = []
    var tasks: [TaskRow] = []
    var tasksDoneToday: Int = 0
    var habits: [HabitRow] = []
    var spentToday: String = ""
    var spentMonth: String = ""
    var budgetLeft: String = ""
    var budgetUsed: Double = 0
    var recentExpenses: [Expense] = []
    var reading: Book? = nil
    var dayLine: String = ""
    var weather: String = ""
    var hasAI: Bool = false

    static let contextKey = "snapshot"

    var data: Data? { try? JSONEncoder().encode(self) }
    static func from(_ data: Data?) -> WatchSnapshot? { data.flatMap { try? JSONDecoder().decode(WatchSnapshot.self, from: $0) } }
}

/// One thing done on the watch, carried out by the iPhone.
struct WatchAction: Codable {
    enum Kind: String, Codable { case completeTask, toggleHabit, capture, logExpense, ask, refresh }
    var kind: Kind
    var id: String = ""
    var text: String = ""
    var amount: Double = 0
    var sentAt: Date = .now

    static let messageKey = "action"
    static let replyKey = "reply"

    var data: Data? { try? JSONEncoder().encode(self) }
    static func from(_ data: Data?) -> WatchAction? { data.flatMap { try? JSONDecoder().decode(WatchAction.self, from: $0) } }
}
