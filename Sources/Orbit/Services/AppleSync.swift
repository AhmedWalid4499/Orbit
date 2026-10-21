import Foundation
import EventKit
import SwiftUI

/// A calendar entry from Apple Calendar (iCloud, Google, Exchange… whatever is set up in macOS).
struct AppleEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarName: String
    let color: Color
}

/// A reminder from Apple Reminders.
struct AppleReminder: Identifiable, Hashable {
    let id: String
    let title: String
    let due: Date?
    let listName: String
    let color: Color
}

/// Reads Apple Calendar and Reminders through EventKit and writes back reminder completion.
@MainActor
final class AppleSync: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var calendarAccess: Access = .unknown
    @Published private(set) var remindersAccess: Access = .unknown
    @Published private(set) var reminders: [AppleReminder] = []
    @Published private(set) var revision = 0

    @AppStorage("appleCalendarEnabled") var calendarEnabled = false
    @AppStorage("appleRemindersEnabled") var remindersEnabled = false

    private let store = EKEventStore()

    init() {
        refreshStatus()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.revision += 1
                await self?.loadReminders()
            }
        }
        Task { await loadReminders() }
    }

    func refreshStatus() {
        calendarAccess = Self.map(EKEventStore.authorizationStatus(for: .event))
        remindersAccess = Self.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    private static func map(_ s: EKAuthorizationStatus) -> Access {
        switch s {
        case .fullAccess, .authorized: .granted
        case .denied, .restricted, .writeOnly: .denied
        default: .unknown
        }
    }

    func connectCalendar() async {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        refreshStatus()
        calendarEnabled = ok
        revision += 1
    }

    func connectReminders() async {
        let ok = (try? await store.requestFullAccessToReminders()) ?? false
        refreshStatus()
        remindersEnabled = ok
        await loadReminders()
    }

    func events(from start: Date, to end: Date) -> [AppleEvent] {
        guard calendarEnabled, calendarAccess == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            AppleEvent(id: $0.eventIdentifier ?? UUID().uuidString,
                       title: $0.title ?? "Untitled",
                       start: $0.startDate, end: $0.endDate,
                       isAllDay: $0.isAllDay,
                       calendarName: $0.calendar.title,
                       color: Color(cgColor: $0.calendar.cgColor))
        }
    }

    func loadReminders() async {
        guard remindersEnabled, remindersAccess == .granted else { reminders = []; return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let items: [AppleReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { result in
                let mapped = (result ?? []).map {
                    AppleReminder(id: $0.calendarItemIdentifier,
                                  title: $0.title ?? "Untitled",
                                  due: $0.dueDateComponents?.date,
                                  listName: $0.calendar.title,
                                  color: Color(cgColor: $0.calendar.cgColor))
                }
                cont.resume(returning: mapped)
            }
        }
        reminders = items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    func complete(_ reminder: AppleReminder) {
        guard let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        try? store.save(item, commit: true)
        reminders.removeAll { $0.id == reminder.id }
    }

    func disconnectCalendar() { calendarEnabled = false; revision += 1 }
    func disconnectReminders() { remindersEnabled = false; reminders = [] }
}
