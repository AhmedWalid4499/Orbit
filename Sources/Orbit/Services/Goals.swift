import Foundation
import SwiftData

/// Works out a goal's progress from the rest of Orbit: books finished, money saved, habit days, or steps ticked off.
enum GoalTracker {
    struct Progress {
        let value: Double
        let target: Double
        /// 0…1
        var fraction: Double { target > 0 ? min(1, max(0, value / target)) : 0 }
        var isComplete: Bool { target > 0 && value >= target }
        /// Ahead (> 0) or behind (< 0) the even pace to the deadline, as a share of the target. nil without a deadline.
        let pace: Double?
    }

    struct Sources {
        var books: [Book] = []
        var transactions: [Transaction] = []
        var habits: [Habit] = []

        @MainActor static func load(_ context: ModelContext) -> Sources {
            Sources(books: (try? context.fetch(FetchDescriptor<Book>())) ?? [],
                    transactions: (try? context.fetch(FetchDescriptor<Transaction>())) ?? [],
                    habits: (try? context.fetch(FetchDescriptor<Habit>())) ?? [])
        }
    }

    static func progress(_ g: Goal, _ s: Sources, now: Date = .now) -> Progress {
        let start = g.start.startOfDay
        let value: Double
        var target = g.target
        switch g.kind {
        case .books:
            value = Double(s.books.filter { $0.status == .read && ($0.finishedAt ?? .distantPast) >= start }.count)
        case .save:
            value = max(0, s.transactions.filter { $0.date >= start }.reduce(0) { $0 + $1.amount })
        case .habit:
            let startKey = DayKey.key(start)
            value = Double(s.habits.first { $0.uuid == g.habitUUID }?.doneDays.filter { $0 >= startKey }.count ?? 0)
        case .steps:
            target = Double(g.steps.count)
            value = Double(g.steps.filter { g.stepsDone.contains($0) }.count)
        }
        var pace: Double?
        if let deadline = g.deadline, deadline > start, target > 0 {
            let elapsed = min(1, max(0, now.timeIntervalSince(start) / deadline.timeIntervalSince(start)))
            pace = value / target - elapsed
        }
        return Progress(value: value, target: target, pace: pace)
    }

    /// "12 of 24 books", "EGP 8,000 of EGP 50,000", "18 of 30 days", "2 of 5 steps".
    static func describe(_ g: Goal, _ p: Progress) -> String {
        switch g.kind {
        case .books: "\(Int(p.value)) of \(Int(p.target)) books"
        case .save: "\(Fmt.money(p.value)) of \(Fmt.money(p.target))"
        case .habit: "\(Int(p.value)) of \(Int(p.target)) days"
        case .steps: "\(Int(p.value)) of \(Int(p.target)) steps"
        }
    }

    static func paceText(_ g: Goal, _ p: Progress) -> String? {
        if p.isComplete { return "Done 🎉" }
        guard let pace = p.pace, let deadline = g.deadline else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date.now.startOfDay, to: deadline.startOfDay).day ?? 0
        if days < 0 { return "Deadline passed" }
        if pace >= 0.05 { return "Ahead of pace · \(days) days left" }
        if pace <= -0.1 { return "Behind pace · \(days) days left" }
        return "On track · \(days) days left"
    }

    /// For the assistant and the morning brief.
    @MainActor static func summary(_ context: ModelContext) -> String {
        let goals = ((try? context.fetch(FetchDescriptor<Goal>())) ?? []).filter { $0.doneAt == nil }
        guard !goals.isEmpty else { return "Goals: none." }
        let s = Sources.load(context)
        return "Goals: " + goals.prefix(10).map { g in
            let p = progress(g, s)
            return "\(g.title) (\(describe(g, p))\(g.deadline.map { ", by \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))"
        }.joined(separator: "; ") + "."
    }
}
