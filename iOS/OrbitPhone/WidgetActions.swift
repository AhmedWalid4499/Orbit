import Foundation
import SwiftData

/// What the widget and Control Center buttons do (iOS/Shared/WidgetIntents.swift). Installed when the app starts,
/// including when iOS wakes Joshu in the background just to run a button.
@MainActor
enum WidgetActions {
    static func install() {
        ToggleHabitIntent.handler = toggleHabit
        CompleteTaskIntent.handler = completeTask
        StartFocusIntent.handler = startFocus
    }

    private static var context: ModelContext? { OrbitStore.container?.mainContext }

    static func toggleHabit(_ id: String) {
        guard let ctx = context, !id.isEmpty,
              let habit = try? ctx.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.uuid == id })).first else { return }
        habit.toggle(.now)
        save(ctx)
    }

    static func completeTask(_ id: String) {
        guard let ctx = context, !id.isEmpty,
              let task = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.uuid == id })).first, !task.isDone else { return }
        task.complete(in: ctx)
        save(ctx)
    }

    static func startFocus() {
        guard let ctx = context else { return }
        let timer = FocusTimer.shared
        timer.restore(context: ctx)
        guard timer.active == nil else { return }   // already focusing: leave it running
        timer.start(context: ctx)
    }

    static func refreshWidgets() {
        guard let ctx = context else { return }
        WidgetBridge.refresh(context: ctx)
    }

    private static func save(_ ctx: ModelContext) {
        try? ctx.save()
        WidgetBridge.refresh(context: ctx)
    }
}
