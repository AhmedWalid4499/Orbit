import Foundation
import SwiftData

enum DataReset {
    /// Removes everything Orbit stores locally. Apple Calendar and Reminders are never touched.
    /// `settings: false` leaves the brief and the assistant's memory (the sync test, which runs on a real Mac).
    static func clearAll(_ context: ModelContext, settings: Bool = true) {
        try? context.delete(model: TaskItem.self)
        try? context.delete(model: EventItem.self)
        try? context.delete(model: Habit.self)
        try? context.delete(model: Transaction.self)
        try? context.delete(model: Note.self)
        try? context.delete(model: Book.self)
        try? context.delete(model: BookCategory.self)
        try? context.delete(model: BucketItem.self)
        try? context.delete(model: ReadingSession.self)
        try? context.delete(model: Highlight.self)
        try? context.delete(model: Subscription.self)
        try? context.delete(model: DocItem.self)
        try? context.delete(model: FocusSession.self)
        try? context.delete(model: DayPlan.self)
        try? context.delete(model: Trip.self)
        try? context.delete(model: Booking.self)
        try? context.delete(model: Bill.self)
        try? context.delete(model: BankAccount.self)
        try? context.delete(model: IdeaProject.self)
        try? context.delete(model: Idea.self)
        try? context.delete(model: ChatThread.self)
        try? context.delete(model: Goal.self)
        try? context.save()
        guard settings else { return }
        UserDefaults.standard.removeObject(forKey: "aiMorningBriefCache")
        UserDefaults.standard.removeObject(forKey: AssistantMemory.key)
    }
}
