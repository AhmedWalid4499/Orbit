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
        if let reminder = await captureReminder(raw, context: context) { return reminder }
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

    private struct ReminderParse: Decodable {
        let is_reminder: Bool
        let title: String
        let due_date: String
        let remind_at: String
        let remind_place: String
        let remind_on: String
    }

    /// "remind me to call mom when I get home / at 6pm / near a pharmacy": a task with a reminder.
    /// Nil when the text isn't a reminder.
    static func captureReminder(_ raw: String, context: ModelContext) async -> String? {
        let lower = raw.lowercased()
        guard lower.contains("remind") || lower.contains("when i get") || lower.contains("when i leave") || lower.contains("when i'm near")
                || lower.contains("when i am near") || lower.contains("ذكرني") else { return nil }
        var input: [String: Any]?
        if let client = ClaudeClient() {
            let system = """
            The user typed a quick note into their task app. Decide whether it asks for a reminder and pull out its parts.
            Now: \(Date.now.formatted(.iso8601)) (\(TimeZone.current.identifier)).
            - is_reminder: true if they want to be reminded of something (at a time or a place).
            - title: the thing to do, short, starting with a verb ("Call mom", "Buy batteries"), without the reminder words.
            - remind_at: local time yyyy-MM-ddTHH:mm if a time is given ("at 6", "in 2 hours", "tomorrow morning" = 09:00), else "".
            - remind_place: "home", "work", or the place or shop name ("pharmacy", "Carrefour") if a place is given, else "".
            - remind_on: "leave" if they said leaving/when I leave, else "arrive".
            - due_date: yyyy-MM-dd of the day it's for if stated or implied by remind_at, else "".
            """
            let schema: [String: Any] = ["type": "object", "properties": [
                "is_reminder": ["type": "boolean"], "title": ["type": "string"], "due_date": ["type": "string"],
                "remind_at": ["type": "string"], "remind_place": ["type": "string"], "remind_on": ["type": "string", "enum": ["arrive", "leave"]],
            ], "required": ["is_reminder", "title", "due_date", "remind_at", "remind_place", "remind_on"], "additionalProperties": false]
            if let r = try? await client.structured(ReminderParse.self, system: system, user: raw, schema: schema, effort: "low", maxTokens: 1500) {
                guard r.is_reminder, !r.title.isEmpty else { return nil }
                input = ["title": r.title, "due_date": r.due_date, "remind_at": r.remind_at, "remind_place": r.remind_place,
                         "remind_on": r.remind_on, "area": "personal", "priority": 0, "repeat": "none", "notes": ""]
            }
        }
        if input == nil {
            // Offline: home and work only.
            let leave = lower.contains("leave")
            let place = lower.contains("home") ? "home" : (lower.contains("work") || lower.contains("office")) ? "work" : ""
            guard !place.isEmpty else { return nil }
            var title = raw
            for p in [#"(?i)^\s*remind me (to )?"#, #"(?i)\s*when i (get|arrive|leave|am|'m)\b.*$"#] {
                title = title.replacingOccurrences(of: p, with: "", options: .regularExpression)
            }
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            input = ["title": title.prefix(1).uppercased() + title.dropFirst(), "remind_place": place, "remind_on": leave ? "leave" : "arrive",
                     "due_date": "", "remind_at": "", "area": "personal", "priority": 0, "repeat": "none", "notes": ""]
        }
        guard let input else { return nil }
        let out = await AssistantTools.run("create_task", input: input, context: context, apple: AppleSync())
        try? context.save()
        let what = out.action?.text ?? "Task “\(input["title"] ?? "")”"
        return out.result.contains("Couldn't") ? what + " — " + out.result.replacingOccurrences(of: "Created task. Couldn't set the place reminder: ", with: "no reminder yet: ") : what
    }
}

