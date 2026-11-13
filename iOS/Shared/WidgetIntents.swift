#if os(iOS)
import AppIntents
import Foundation

// Buttons in Joshu's Home Screen and Lock Screen widgets and in Control Center. Compiled into both the iPhone app and
// the widget extension. They are LiveActivityIntents so the system runs them in the app's process (woken in the
// background if needed), where the handlers set in OrbitPhoneApp (WidgetActions) change your data and refresh the widgets.

/// Ticks a habit off for today, or unticks it.
struct ToggleHabitIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Tick off a habit"
    static var isDiscoverable = false

    @Parameter(title: "Habit") var habitID: String

    @MainActor static var handler: ((String) -> Void)?

    init() {}
    init(habitID: String) { self.habitID = habitID }

    func perform() async throws -> some IntentResult {
        let id = habitID
        await MainActor.run { Self.handler?(id) }
        return .result()
    }
}

/// Marks a task done.
struct CompleteTaskIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete a task"
    static var isDiscoverable = false

    @Parameter(title: "Task") var taskID: String

    @MainActor static var handler: ((String) -> Void)?

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        let id = taskID
        await MainActor.run { Self.handler?(id) }
        return .result()
    }
}

/// Starts a focus block (your usual length) without opening Joshu. Control Center and the Action button.
struct StartFocusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start focusing"
    static var description = IntentDescription("Starts a focus block in Joshu. The countdown shows on your Lock Screen.")

    @MainActor static var handler: (() -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { Self.handler?() }
        return .result()
    }
}

/// Opens Joshu straight to "Add a task, event, expense or note". Control Center and the Action button.
struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Joshu"
    static var description = IntentDescription("Opens Joshu ready to add a task, event, expense or note.")
    static var openAppWhenRun = true

    /// Read by the app (PhoneRoot) when it comes to the front. Written to the app group too, in case iOS runs this
    /// in the widget extension rather than in Joshu.
    static let pendingKey = "quickAdd.pending"
    static let groupDefaults = UserDefaults(suiteName: "group.com.ahmedwalid.orbit")

    @MainActor static var handler: (() -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: Self.pendingKey)
        Self.groupDefaults?.set(true, forKey: Self.pendingKey)
        await MainActor.run { Self.handler?() }
        return .result()
    }

    /// True once after the button was pressed.
    static func takePending() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: pendingKey) || (groupDefaults?.bool(forKey: pendingKey) ?? false)
        UserDefaults.standard.removeObject(forKey: pendingKey)
        groupDefaults?.removeObject(forKey: pendingKey)
        return pending
    }
}
#endif
