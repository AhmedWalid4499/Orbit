import SwiftUI
import SwiftData

/// Every model Orbit stores, in one place for the Mac app, the iPhone app and tests.
enum OrbitSchema {
    static let models: [any PersistentModel.Type] = [TaskItem.self, EventItem.self, Habit.self, Transaction.self, Note.self, Book.self,
                                                     BookCategory.self, BucketItem.self, ReadingSession.self, Highlight.self, Subscription.self,
                                                     DocItem.self, FocusSession.self, DayPlan.self, Trip.self, Booking.self]
    static var schema: Schema { Schema(models) }
}

enum Tab: String, CaseIterable, Identifiable {
    case today, insights, calendar, tasks, habits, bucket, money, notes, reading, documents, github
    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes:
            return "Journal & Notes"
        case .reading:
            let first = Platform.userName
                .split(separator: " ").first.map(String.init) ?? ""
            return first.isEmpty ? "Reading" : "\(first)'s Reading"
        case .github:
            return "GitHub"
        case .bucket:
            return "Bucket list"
        case .documents:
            return "Documents"
        case .insights:
            return "Insights"
        default:
            return rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .insights: "chart.xyaxis.line"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .habits: "flame.fill"
        case .money: "creditcard.fill"
        case .notes: "book.pages.fill"
        case .reading: "books.vertical.fill"
        case .bucket: "mountain.2.fill"
        case .documents: "doc.text.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Nav groups: day, plan, life.
    static let groups: [[Tab]] = [[.today, .insights], [.calendar, .tasks, .habits, .bucket], [.money, .notes, .reading, .documents, .github]]

    /// ⌘1…⌘9 for the first nine tabs (there's no ⌘10).
    var shortcutNumber: Int? { let i = Tab.allCases.firstIndex(of: self)! + 1; return i <= 9 ? i : nil }
}

@MainActor
final class AppState: ObservableObject {
    /// The window's state, for things that start outside a view (voice capture, notifications).
    static weak var current: AppState?
    init() { if AppState.current == nil { AppState.current = self } }

    @Published var tab: Tab = .today
    @Published var searchOpen = false
    /// The animated tour of what Orbit can do (first launch, or Settings › General › Take the tour).
    @Published var tourOpen = false
    @Published var settingsOpen = false
    @Published var openTodayJournal = false
    @Published var assistantOpen = false
    @Published var reviewOpen = false
    @Published var cardOpen = false
    @Published var planOpen = false
    /// iPhone: the quick-add sheet.
    @Published var captureOpen = false
    /// A message to send as soon as the assistant opens (e.g. from "Discuss with Claude").
    @Published var assistantSeed: String?

    func openAssistant(with message: String? = nil) {
        assistantSeed = message
        assistantOpen = true
    }
}
