import SwiftUI
import SwiftData

/// One entry on a calendar, either from Orbit or from Apple Calendar.
struct CalEntry: Identifiable, Hashable {
    enum Source: Hashable { case local(PersistentIdentifier), apple(calendar: String), google(calendar: String) }
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let area: Area?
    let tint: Color
    let source: Source

    /// Name of the Apple or Google calendar it came from (nil for Orbit's own events).
    var calendarName: String? {
        switch source {
        case .apple(let c): c
        case .google(let c): c
        case .local: nil
        }
    }

    static func merge(local: [EventItem], apple: [AppleEvent], google: [GoogleEvent] = []) -> [CalEntry] {
        let mine = local.map {
            CalEntry(id: "\($0.persistentModelID.hashValue)", title: $0.title, start: $0.start, end: $0.end,
                     isAllDay: false, area: $0.area, tint: $0.area.color, source: .local($0.persistentModelID))
        }
        let theirs = apple.map {
            CalEntry(id: "apple-\($0.id)-\($0.start.timeIntervalSince1970)", title: $0.title, start: $0.start, end: $0.end,
                     isAllDay: $0.isAllDay, area: nil, tint: $0.color, source: .apple(calendar: $0.calendarName))
        }
        // Skip Google events that macOS Calendar already shows (same title and start), e.g. if the account is also in Internet Accounts.
        let appleKeys = Set(apple.map { "\($0.title.lowercased())|\(Int($0.start.timeIntervalSince1970))" })
        let fromGoogle = google.filter { !appleKeys.contains("\($0.title.lowercased())|\(Int($0.start.timeIntervalSince1970))") }.map {
            CalEntry(id: "google-\($0.id)-\($0.start.timeIntervalSince1970)", title: $0.title, start: $0.start, end: $0.end,
                     isAllDay: $0.isAllDay, area: nil, tint: $0.color, source: .google(calendar: $0.calendarName))
        }
        return (mine + theirs + fromGoogle).sorted { $0.start < $1.start }
    }
}
