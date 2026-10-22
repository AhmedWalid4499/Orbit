import Foundation
import SwiftUI
import SwiftData
import UserNotifications
import ServiceManagement
import AppKit

/// Native Mac notifications: tasks due, events starting soon, bills due tomorrow, habit and journal nudges,
/// and the Sunday weekly review. The next two days are scheduled ahead, so alerts still arrive if Orbit is closed.
@MainActor
final class Reminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    @AppStorage("notify.tasks") var tasks = true
    @AppStorage("notify.events") var events = true
    @AppStorage("notify.bills") var bills = true
    @AppStorage("notify.habits") var habits = true
    @AppStorage("notify.journal") var journal = true
    @AppStorage("notify.review") var review = true
    @AppStorage("notify.morningHour") var morningHour = 9
    @AppStorage("notify.habitHour") var habitHour = 20
    @AppStorage("notify.journalHour") var journalHour = 21
    @AppStorage("notify.eventLead") var eventLead = 10

    @Published private(set) var authorized: Bool?
    /// Where a tapped notification wants to go; RootView picks this up.
    @Published var route: String?

    private let center = UNUserNotificationCenter.current()
    private let prefix = "orbit."

    override private init() {
        super.init()
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    // MARK: Scheduling

    /// Replaces Orbit's pending notifications with the ones for the next ~48 hours.
    func reschedule(context: ModelContext, apple: AppleSync) async {
        guard !Snapshot.isActive else { return }
        if authorized == nil { await refreshAuthorization() }
        if authorized == false {
            // Ask once, the first time there's something to remind about.
            if !UserDefaults.standard.bool(forKey: "notify.asked") {
                UserDefaults.standard.set(true, forKey: "notify.asked")
                await requestAuthorization()
            }
            guard authorized == true else { return }
        }

        var requests: [UNNotificationRequest] = []
        let now = Date.now, cal = Calendar.current
        let today = now.startOfDay, tomorrow = today.adding(days: 1), dayAfter = today.adding(days: 2)
        func at(_ day: Date, _ hour: Int) -> Date { cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)! }
        func add(_ id: String, _ title: String, _ body: String, at date: Date, route: String) {
            guard date > now.addingTimeInterval(5) else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["route": route]
            content.threadIdentifier = route
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            requests.append(UNNotificationRequest(identifier: prefix + id, content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }

        let allTasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isDone }

        if tasks {
            for day in [today, tomorrow] {
                let due = allTasks.filter { $0.area != .money && ($0.due?.isSameDay(as: day) ?? false) }
                    .sorted { $0.priority > $1.priority }
                if !due.isEmpty {
                    add("tasks-\(DayKey.key(day))", due.count == 1 ? "Due today: \(due[0].title)" : "\(due.count) tasks due today",
                        due.prefix(4).map(\.title).joined(separator: " · "), at: at(day, morningHour), route: "tasks")
                }
            }
            let overdue = allTasks.filter(\.isOverdue)
            if !overdue.isEmpty {
                let next = at(today, morningHour) > now ? at(today, morningHour) : at(tomorrow, morningHour)
                add("overdue", "\(overdue.count) overdue task\(overdue.count == 1 ? "" : "s")",
                    overdue.prefix(4).map(\.title).joined(separator: " · "), at: next, route: "tasks")
            }
        }

        if bills {
            for t in allTasks where t.area == .money {
                guard let due = t.due, due >= tomorrow, due < dayAfter.adding(days: 1) else { continue }
                add("bill-\(t.uuid.isEmpty ? t.title : t.uuid)", "Bill due tomorrow", t.title.replacingOccurrences(of: "Pay ", with: ""),
                    at: at(due.adding(days: -1), 18), route: "money")
            }
        }

        if events {
            let local = ((try? context.fetch(FetchDescriptor<EventItem>())) ?? []).filter { $0.start > now && $0.start < dayAfter }
            let entries = CalEntry.merge(local: local, apple: apple.events(from: now, to: dayAfter),
                                         google: GoogleCalendarStore.shared.events(from: now, to: dayAfter))
            for e in entries where !e.isAllDay && e.start > now {
                add("event-\(e.id)", e.title, "In \(eventLead) minutes · \(Fmt.time(e.start))\(e.calendarName.map { " · \($0)" } ?? "")",
                    at: e.start.adding(minutes: -eventLead), route: "calendar")
            }
        }

        if habits {
            let list = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            for day in [today, tomorrow] {
                let left = list.filter { !$0.isDone(on: day) }
                if !left.isEmpty {
                    add("habits-\(DayKey.key(day))", "Still time for your habits", left.prefix(4).map(\.name).joined(separator: " · "),
                        at: at(day, habitHour), route: "habits")
                }
            }
        }

        if journal {
            let notes = (try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.isJournal }))) ?? []
            for day in [today, tomorrow] {
                let written = notes.contains { $0.createdAt.isSameDay(as: day) && (!$0.body.isEmpty || $0.chatData != nil) }
                if !written {
                    add("journal-\(DayKey.key(day))", "How was today?", "Take two minutes to check in with \(AssistantName.current).",
                        at: at(day, journalHour), route: "journal")
                }
            }
        }

        if review {
            // Next Sunday at 6 pm.
            var next = today
            while cal.component(.weekday, from: next) != 1 || at(next, 18) <= now { next = next.adding(days: 1) }
            add("review-\(DayKey.key(next))", "Your week in review", "See how the week went and pick three things for next week.",
                at: at(next, 18), route: "review")
        }

        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for r in requests.sorted(by: { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
                                      < ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture }).prefix(60) {
            try? await center.add(r)
        }
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo["route"] as? String
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            self.route = route
        }
    }

    // MARK: Open at login

    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
            objectWillChange.send()
        }
    }
}

/// Notification preferences, shown in Settings › Notifications.
struct NotificationSettingsView: View {
    @ObservedObject private var r = Reminders.shared

    var body: some View {
        Form {
            if r.authorized == false {
                Section {
                    Label("Notifications are off for Orbit.", systemImage: "bell.slash")
                    HStack {
                        Button("Allow notifications") { Task { await r.requestAuthorization() } }
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
            }
            Section("Remind me about") {
                Toggle("Tasks due today and overdue tasks", isOn: $r.tasks)
                Toggle("Events about to start", isOn: $r.events)
                Toggle("Bills due tomorrow", isOn: $r.bills)
                Toggle("Habits not done yet, in the evening", isOn: $r.habits)
                Toggle("Journal check-in at night", isOn: $r.journal)
                Toggle("Weekly review on Sunday evening", isOn: $r.review)
            }
            Section("Times") {
                Picker("Morning summary", selection: $r.morningHour) { ForEach(5..<13) { Text("\($0):00").tag($0) } }
                Picker("Habit nudge", selection: $r.habitHour) { ForEach(16..<23) { Text("\($0):00").tag($0) } }
                Picker("Journal check-in", selection: $r.journalHour) { ForEach(18..<24) { Text("\($0):00").tag($0) } }
                Picker("Before events", selection: $r.eventLead) { ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) } }
            }
            Section {
                Toggle("Open Orbit when I log in", isOn: Binding(get: { r.openAtLogin }, set: { r.openAtLogin = $0 }))
                Text("Orbit schedules the next two days of reminders ahead, so they arrive even when it's closed. Opening it at login keeps them up to date.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
