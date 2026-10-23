import Foundation
import SwiftData
import SwiftUI

extension QuickParser.Result {
    /// Saves the parsed item into the store.
    func save(in context: ModelContext) {
        switch kind {
        case .task:
            context.insert(TaskItem(title: title, area: area ?? .personal, due: date, priority: priority))
        case .event:
            let start = date ?? .now
            context.insert(EventItem(title: title, start: start, end: start.adding(minutes: durationMinutes ?? 60), area: area ?? .personal))
        case .expense, .income:
            context.insert(Transaction(title: title.isEmpty ? (category ?? "Expense") : title,
                                       amount: amount ?? 0, category: category ?? "General"))
        case .note:
            context.insert(Note(title: title.isEmpty ? "Untitled" : title))
        case .journal:
            let today = Date.now.startOfDay
            let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.isJournal && $0.createdAt >= today })
            if let entry = try? context.fetch(descriptor).first {
                entry.body += (entry.body.isEmpty ? "" : "\n") + title
                entry.updatedAt = .now
            } else {
                context.insert(Note(title: Date.now.formatted(date: .complete, time: .omitted), body: title, isJournal: true))
            }
        }
        try? context.save()
    }
}

/// The app's data store, for code that runs outside a view (Siri, Shortcuts, voice capture).
@MainActor
enum OrbitStore {
    static var container: ModelContainer?
}

// MARK: - Capture engine (shared by ⌥Space, the Today bar, Siri and the iPhone app)

@MainActor
enum CaptureEngine {
    /// Saves free text as one or more items, using Claude when smart capture is on and the offline parser otherwise.
    /// Returns a short summary of what was saved.
    static func capture(_ raw: String, context: ModelContext) async -> String {
        var items = [QuickParser.parse(raw)]
        var note = ""
        if AIAssistant.shared.smartCaptureActive {
            do {
                let smart = try await AIAssistant.shared.smartParse(raw)
                if !smart.isEmpty { items = smart }
            } catch {
                note = " (offline parser)"
            }
        }
        let valid = items.filter { !$0.title.isEmpty || $0.amount != nil }
        valid.forEach { $0.save(in: context) }
        return valid.map(\.summary).joined(separator: "  |  ") + note
    }
}

