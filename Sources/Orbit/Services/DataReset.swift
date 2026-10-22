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
        try? context.save()
        UserDefaults.standard.removeObject(forKey: "aiMorningBriefCache")
    }
}
