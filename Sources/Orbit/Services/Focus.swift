import Foundation
import SwiftUI
import SwiftData
import UserNotifications
import AppKit

/// Pomodoro-style focus blocks. One runs at a time; it survives restarts (an open block has no end).
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    @Published private(set) var active: FocusSession?
    /// Set when a block runs to the end, so the UI can offer to mark its task done.
    @Published var justFinished: FocusSession?
    /// Ticks every second while a block runs (drives the menu bar countdown).
    @Published private(set) var now = Date.now
    @AppStorage("focusMinutes") var length = 25

    static let lengths = [15, 25, 50]
    private var ticker: Timer?
    private weak var context: ModelContext?
    private let notificationID = "focus.end"

    func restore(context: ModelContext) {
        guard active == nil else { return }
        self.context = context
        let open = (try? context.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.end == nil }))) ?? []
        for s in open where s.plannedEnd <= .now { s.end = s.plannedEnd }
        try? context.save()
        if let s = open.first(where: { $0.end == nil }) { active = s; startTicking() }
    }

    func start(task: TaskItem? = nil, minutes: Int? = nil, context: ModelContext) {
        if active != nil { stop(context: context) }
        self.context = context
        if let task, task.uuid.isEmpty { task.uuid = UUID().uuidString.lowercased() }
        let s = FocusSession(task: task, minutes: minutes ?? length)
        context.insert(s)
        try? context.save()
        active = s
        scheduleNotification(for: s)
        startTicking()
    }

    /// Stops early. Blocks under a minute aren't kept.
    func stop(context: ModelContext) {
        guard let s = active else { return }
        s.end = min(.now, s.plannedEnd)
        if s.minutes < 1 { context.delete(s) }
        try? context.save()
        finishUp()
    }

    func remaining(at date: Date = .now) -> TimeInterval { max(0, (active?.plannedEnd ?? date).timeIntervalSince(date)) }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func minutes(_ sessions: [FocusSession], since: Date, until: Date = .distantFuture) -> Int {
        Int(sessions.filter { $0.start >= since && $0.start < until }.reduce(0) { $0 + min($1.minutes, Double($1.plannedMinutes)) })
    }

    // MARK: Private

    private func tick() {
        now = .now
        guard let s = active, s.plannedEnd <= now else { return }
        s.end = s.plannedEnd
        try? context?.save()
        NSSound(named: "Glass")?.play()
        finishUp()
        justFinished = s
    }

    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in FocusTimer.shared.tick() }
        }
    }

    private func finishUp() {
        ticker?.invalidate(); ticker = nil
        active = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    private func scheduleNotification(for s: FocusSession) {
        guard !Snapshot.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "Focus done"
        content.body = s.taskTitle.isEmpty ? "Nice work. Take a 5-minute break." : "\(s.taskTitle): nice work. Take a 5-minute break."
        content.sound = .default
        content.userInfo = ["route": "today"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, s.plannedEnd.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
    }
}

// MARK: - Views

/// Top-bar pill while a focus block runs.
struct FocusPill: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        if let s = timer.active {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(FocusTimer.clock(timer.remaining(at: ctx.date))).monospacedDigit()
                }
                Button { timer.stop(context: context) } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.plain).help("Stop focusing")
            }
            .lineLimit(1).fixedSize()
            .help(s.taskTitle.isEmpty ? "Focusing" : "Focusing on \(s.taskTitle)")
            .font(Theme.ui(12, weight: .semibold))
            .foregroundStyle(Theme.stickerInk)
            .padding(.horizontal, 12).frame(height: 42)
            .background(Capsule().fill(Theme.orange))
        }
    }
}

/// "Focus" menu: start a block of 15, 25 or 50 minutes, on a task or on nothing in particular.
struct FocusMenu<Label: View>: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var timer = FocusTimer.shared
    var task: TaskItem? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            ForEach(FocusTimer.lengths, id: \.self) { m in
                Button("\(m) minutes\(m == timer.length ? " ✓" : "")") {
                    timer.length = m
                    timer.start(task: task, minutes: m, context: context)
                }
            }
            if timer.active != nil {
                Divider()
                Button("Stop current focus") { timer.stop(context: context) }
            }
        } label: { label() }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// After a block runs to the end: a break, and maybe tick off the task.
struct FocusDoneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let session: FocusSession
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]

    private var task: TaskItem? { session.taskUUID.isEmpty ? nil : open.first { $0.uuid == session.taskUUID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Focus done 🎯").font(Theme.display(26))
            Text("\(session.plannedMinutes) minutes\(session.taskTitle.isEmpty ? "" : " on \(session.taskTitle)"). Stand up, stretch, drink some water: take 5.")
                .font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                FocusMenu { Text("Another round") }
                Spacer()
                if let task {
                    Button("Mark “\(task.title)” done") { task.complete(in: context); try? context.save(); dismiss() }
                        .buttonStyle(PrimaryButtonStyle()).fixedSize()
                }
                Button("Close") { dismiss() }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 440)
    }
}

/// Menu bar icon; shows the countdown while focusing.
struct MenuBarLabel: View {
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        if timer.active != nil {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(FocusTimer.clock(timer.remaining(at: timer.now))).monospacedDigit()
            }
        } else {
            Image(systemName: "circle.circle.fill")
        }
    }
}
