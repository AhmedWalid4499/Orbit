import SwiftUI
import SwiftData

/// Every model Orbit stores, in one place for the Mac app, the iPhone app and tests.
enum OrbitSchema {
    static let models: [any PersistentModel.Type] = [TaskItem.self, EventItem.self, Habit.self, Transaction.self, Note.self, Book.self,
                                                     BookCategory.self, BucketItem.self, ReadingSession.self, Highlight.self, Subscription.self,
                                                     DocItem.self, FocusSession.self, DayPlan.self, Trip.self, Booking.self,
                                                     Bill.self, Goal.self, BankAccount.self, IdeaProject.self, Idea.self, ChatThread.self]
    static var schema: Schema { Schema(models) }
}

enum Tab: String, CaseIterable, Identifiable {
    case today, assistant, insights, calendar, tasks, habits, bucket, money, notes, ideas, reading, documents, github, youtube, linkedin
    var id: String { rawValue }

    /// Documents and YouTube were retired as tabs (YouTube stays connected for the assistant); old links to them still open.
    static var allCases: [Tab] { [.today, .assistant, .insights, .calendar, .tasks, .habits, .bucket, .money, .notes, .ideas, .reading, .github, .linkedin] }

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
        case .youtube:
            return "YouTube"
        case .linkedin:
            return "LinkedIn"
        case .bucket:
            return "Bucket list"
        case .documents:
            return "Documents"
        case .insights:
            return "Insights"
        case .assistant:
            return AssistantName.current
        case .ideas:
            return "Ideas"
        default:
            return rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .assistant: "sparkles"
        case .ideas: "lightbulb.max.fill"
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
        case .youtube: "play.rectangle.fill"
        case .linkedin: "briefcase.fill"
        }
    }

    /// Nav groups: day, plan, life.
    static let groups: [[Tab]] = [[.today, .assistant, .insights], [.calendar, .tasks, .habits, .bucket], [.money, .notes, .ideas, .reading, .github, .linkedin]]

    /// Tabs you turned off in Settings › General › Tabs (synced). Today is always there.
    static var hidden: Set<Tab> {
        get { Set((UserDefaults.standard.string(forKey: "hiddenTabs") ?? "").split(separator: ",").compactMap { Tab(rawValue: String($0)) }) }
        set { UserDefaults.standard.set(newValue.subtracting([.today]).map(\.rawValue).sorted().joined(separator: ","), forKey: "hiddenTabs") }
    }
    static func visibleGroups(hidden: Set<Tab>) -> [[Tab]] { groups.map { $0.filter { !hidden.contains($0) } }.filter { !$0.isEmpty } }
    var canHide: Bool { self != .today }
    /// One line on what the tab is for, shown next to its switch.
    var blurb: String {
        switch self {
        case .today: "Your day at a glance"
        case .assistant: "Chat with your AI and see past chats"
        case .ideas: "Writing projects and the ideas that grow in them"
        case .insights: "Charts of your week and month"
        case .calendar: "Apple and Google calendars"
        case .tasks: "To-dos and reminders"
        case .habits: "Daily habits and streaks"
        case .bucket: "Dreams, trips and places to go"
        case .money: "Spending, budgets and subscriptions"
        case .notes: "Notes and your journal"
        case .reading: "Books from Goodreads, Apple Books or Kindle"
        case .documents: "Passports, IDs and warranties"
        case .github: "Your GitHub repos and pull requests"
        case .youtube: "Your channel's subscribers, views and videos"
        case .linkedin: "Your LinkedIn job alerts"
        }
    }

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
    /// + opens a full new task (with reminders); Quick add is inside it.
    @Published var newTaskOpen = false
    /// A message to send as soon as the assistant opens (e.g. from "Discuss with Claude").
    @Published var assistantSeed: String?

    /// ⌘J and the ✦ button: open or close the chat (on the Mac's AI tab it's already there).
    func toggleAssistant() {
        if tab == .assistant && !Platform.isPhone { assistantOpen = false } else { assistantOpen.toggle() }
    }

    func openAssistant(with message: String? = nil) {
        assistantSeed = message
        // On the Mac's AI tab the chat is already on screen.
        if tab == .assistant && !Platform.isPhone { return }
        assistantOpen = true
    }
}
