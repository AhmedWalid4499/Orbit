import Foundation
import SwiftUI
import SwiftData
import WidgetKit

/// Writes a small summary of today into the app-group folder that Orbit's desktop widgets read
/// (Widgets/OrbitWidgets.swift has the matching WidgetSnapshot type; keep them in step).
@MainActor
enum WidgetBridge {
    #if os(iOS)
    static let appGroup = "group.com.ahmedwalid.orbit"
    #else
    static let appGroup = "Y2K55S3UA9.com.personal.orbit"
    #endif

    private struct WidgetSnapshot: Codable {
        struct Event: Codable { let title: String; let start: Date; let end: Date; let allDay: Bool; let color: String }
        struct Task: Codable { let title: String; let area: String; let overdue: Bool; let priority: Int }
        struct Habit: Codable { let name: String; let symbol: String; let done: Bool; let streak: Int; let color: String }
        struct Dream: Codable { let title: String; let date: Date }
        var generatedAt: Date
        var userName: String
        var events: [Event]
        var tasks: [Task]
        var habits: [Habit]
        var moneyLeft: Double
        var budget: Double
        var currency: String
        var lookingForward: [Dream]
    }

    private static var lastWritten: Data?

    static var folder: URL? {
        #if os(iOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        #else
        URL.homeDirectory.appending(path: "Library/Group Containers/\(appGroup)", directoryHint: .isDirectory)
        #endif
    }

    static func update(context: ModelContext, apple: AppleSync) {
        guard !Orbit.Snapshot.isActive else { return }
        let now = Date.now, today = now.startOfDay, tomorrow = today.adding(days: 1)
        let local = ((try? context.fetch(FetchDescriptor<EventItem>())) ?? []).filter { $0.start < tomorrow && $0.end > today }
        let entries = CalEntry.merge(local: local, apple: apple.events(from: today, to: tomorrow),
                                     google: GoogleCalendarStore.shared.events(from: today, to: tomorrow))
        let tasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? [])
            .filter { !$0.isDone && ($0.due.map { $0 < tomorrow } ?? false) }
            .sorted { $0.priority > $1.priority }
        let habits = (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let txns = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let budget = UserDefaults.standard.object(forKey: "monthlyBudget") as? Double ?? 2000
        let spent = -txns.filter { $0.isExpense && $0.date >= now.startOfMonth }.reduce(0) { $0 + $1.amount }
        let dreams = ((try? context.fetch(FetchDescriptor<BucketItem>())) ?? [])
            .filter { !$0.isDone && ($0.targetDate ?? .distantPast) >= today }.sorted { $0.targetDate! < $1.targetDate! }

        let snap = WidgetSnapshot(
            generatedAt: now,
            userName: Platform.userName,
            events: entries.map { .init(title: $0.title, start: $0.start, end: $0.end, allDay: $0.isAllDay, color: hex($0.tint)) },
            tasks: tasks.prefix(8).map { .init(title: $0.title, area: $0.areaRaw, overdue: $0.isOverdue, priority: $0.priority) },
            habits: habits.map { .init(name: $0.name, symbol: $0.symbol, done: $0.isDone(on: today), streak: $0.currentStreak, color: hex($0.area.color)) },
            moneyLeft: max(budget - spent, 0), budget: budget, currency: Fmt.currencyCode,
            lookingForward: dreams.prefix(3).map { .init(title: $0.title, date: $0.targetDate!) })

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        // Compare without the timestamp so widgets only reload when something actually changed.
        var comparable = snap; comparable.generatedAt = .distantPast
        guard let key = try? enc.encode(comparable), key != lastWritten, let data = try? enc.encode(snap) else { return }
        lastWritten = key
        guard let folder else { return } // iPhone builds without the app group (free accounts) have no widgets
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appending(path: "widget.json"), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func hex(_ c: Color) -> String { c.hexString ?? "#F7C2EC" }
}
