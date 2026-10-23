import Foundation
import SwiftUI
import SwiftData
import UserNotifications
#if os(macOS)
import ServiceManagement
import AppKit
#endif

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
    @AppStorage("notify.subscriptions") var subscriptions = true
    @AppStorage("notify.documents") var documents = true
    @AppStorage("notify.evening") var evening = true
    @AppStorage("notify.trips") var trips = true
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

        func within(_ d: Date) -> Bool { d > now && d < dayAfter.adding(days: 1) }

        if subscriptions {
            for s in (try? context.fetch(FetchDescriptor<Subscription>())) ?? [] where s.status != "cancelled" {
                if s.status == "trial", let ends = s.trialEnds {
                    let when = at(ends.adding(days: -2), 10)
                    if within(when) {
                        add("trial-\(s.uuid.isEmpty ? s.name : s.uuid)", "\(s.name) trial ends in 2 days",
                            "Then it charges \(Fmt.money(s.amount)) \(s.cycle.title.lowercased()). Cancel before \(ends.formatted(.dateTime.weekday(.wide))) if you don't want it.",
                            at: when, route: "money")
                    }
                } else if let next = s.nextDate, s.cycle == .yearly || s.cycle == .quarterly {
                    let when = at(next.adding(days: -1), 10)
                    if within(when) {
                        add("renew-\(s.uuid.isEmpty ? s.name : s.uuid)", "\(s.name) renews tomorrow", "\(Fmt.money(s.amount)) for another \(s.cycle == .yearly ? "year" : "quarter").",
                            at: when, route: "money")
                    }
                }
            }
        }

        if documents {
            for d in (try? context.fetch(FetchDescriptor<DocItem>())) ?? [] {
                guard let exp = d.expires else { continue }
                let early = at(exp.adding(days: -d.remindDays), 10)
                if within(early) {
                    add("doc-\(d.uuid.isEmpty ? d.title : d.uuid)", "\(d.title) expires in \(d.remindDays) days",
                        "On \(exp.formatted(date: .long, time: .omitted)). Time to renew.", at: early, route: "documents")
                }
                let onDay = at(exp, 9)
                if within(onDay) {
                    add("docday-\(d.uuid.isEmpty ? d.title : d.uuid)", "\(d.title) expires today", d.kind == .warranty ? "Your warranty ends today." : "Renew it if you haven't yet.",
                        at: onDay, route: "documents")
                }
            }
        }

        if trips {
            let allTrips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
            for t in allTrips {
                guard let start = t.start else { continue }
                let eve = at(start.adding(days: -1), 19)
                let left = t.packing.count - t.packed.count
                if within(eve) {
                    add("pack-\(t.uuid.isEmpty ? t.title : t.uuid)", "\(t.title) is tomorrow ✈️",
                        left > 0 ? "\(left) thing\(left == 1 ? "" : "s") left to pack." : "All packed. Have a great trip!", at: eve, route: "bucket")
                }
            }
            let flights = ((try? context.fetch(FetchDescriptor<Booking>())) ?? []).filter { $0.kind == .flight }
            for f in flights {
                guard let dep = f.start else { continue }
                let when = dep.addingTimeInterval(-3 * 3600)
                if within(when) {
                    add("flight-\(f.uuid.isEmpty ? f.title : f.uuid)", "Flight in 3 hours", "\(f.title)\(f.confirmation.isEmpty ? "" : " · ref \(f.confirmation)")",
                        at: when, route: "bucket")
                }
            }
        }

        if evening {
            // 8:30 pm: plan tomorrow, unless it's already planned.
            for day in [today, today.adding(days: 1)] {
                let when = cal.date(bySettingHour: 20, minute: 30, second: 0, of: day)!
                guard within(when), DayPlanner.plan(for: day.adding(days: 1), context: context) == nil else { continue }
                add("plan-\(DayKey.key(day))", "Plan tomorrow", "Two minutes: clear what's left and pick tomorrow's top 3.", at: when, route: "plan")
            }
        }

        if review {
            // Next Sunday at 6 pm.
            var next = today
            while cal.component(.weekday, from: next) != 1 || at(next, 18) <= now { next = next.adding(days: 1) }
            add("review-\(DayKey.key(next))", "Your week in review", "See how the week went and pick three things for next week.",
                at: at(next, 18), route: "review")
        }

        // Your own reminders (at a time or a place) always get a slot; the automatic ones fill the rest.
        let smart = SmartReminders.requests(tasks: allTasks, prefix: prefix)
        requests += smart.timed
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for r in smart.places { try? await center.add(r) }
        for r in requests.sorted(by: { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
                                      < ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture }).prefix(60 - smart.places.count) {
            try? await center.add(r)
        }
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo["route"] as? String
        await MainActor.run {
            #if os(macOS)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            #endif
            self.route = route
        }
    }

    #if os(macOS)
    // MARK: Open at login

    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
            objectWillChange.send()
        }
    }
    #endif
}

/// Notification preferences, shown in Settings › Notifications.
struct NotificationSettingsView: View {
    @ObservedObject private var r = Reminders.shared
    @AppStorage("launchSound") private var launchSound = true

    var body: some View {
        Form {
            if r.authorized == false {
                Section {
                    Label("Notifications are off for Orbit.", systemImage: "bell.slash")
                    HStack {
                        Button("Allow notifications") { Task { await r.requestAuthorization() } }
                        Button("Open System Settings") {
                            Platform.open(URL(string: Platform.isPhone ? "app-settings:" : "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
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
                Toggle("Free trials ending and yearly renewals", isOn: $r.subscriptions)
                Toggle("Documents and warranties about to expire", isOn: $r.documents)
                Toggle("Evening nudge to plan tomorrow", isOn: $r.evening)
                Toggle("Trips: packing and flights", isOn: $r.trips)
                Toggle("Spending reaching a budget (80% and 100%)", isOn: Binding(
                    get: { SpendingAlerts.budgetAlerts }, set: { UserDefaults.standard.set($0, forKey: "notify.budgets"); r.objectWillChange.send() }))
                Toggle("Unusually large charges", isOn: Binding(
                    get: { SpendingAlerts.bigChargeAlerts }, set: { UserDefaults.standard.set($0, forKey: "notify.bigCharges"); r.objectWillChange.send() }))
            }
            Section("Times") {
                Picker("Morning summary", selection: $r.morningHour) { ForEach(5..<13) { Text("\($0):00").tag($0) } }
                Picker("Habit nudge", selection: $r.habitHour) { ForEach(16..<23) { Text("\($0):00").tag($0) } }
                Picker("Journal check-in", selection: $r.journalHour) { ForEach(18..<24) { Text("\($0):00").tag($0) } }
                Picker("Before events", selection: $r.eventLead) { ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) } }
            }
            #if os(macOS)
            Section {
                Toggle("Open Orbit when I log in", isOn: Binding(get: { r.openAtLogin }, set: { r.openAtLogin = $0 }))
                Text("Orbit schedules the next two days of reminders ahead, so they arrive even when it's closed. Opening it at login keeps them up to date.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #endif
            Section {
                Toggle("Play a little chime when Orbit opens", isOn: $launchSound)
            }
        }
        .formStyle(.grouped)
    }
}
