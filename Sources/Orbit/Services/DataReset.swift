import Foundation
import SwiftData

enum DataReset {
    /// Removes everything Orbit stores locally. Apple Calendar and Reminders are never touched.
    static func clearAll(_ context: ModelContext) {
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
        try? context.delete(model: Goal.self)
        try? context.save()
        UserDefaults.standard.removeObject(forKey: "aiMorningBriefCache")
        UserDefaults.standard.removeObject(forKey: AssistantMemory.key)
    }
}
