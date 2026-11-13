#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

/// The focus timer on the Lock Screen and in the Dynamic Island (a Live Activity).
/// Compiled into both the iPhone app (which starts and ends it) and the widget extension (which draws it).
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
        /// The block ran to the end: the activity shows "Focus done" for a little while, then goes.
        var finished: Bool = false
    }
    /// The task being focused on; empty for a plain focus block.
    var task: String
    var minutes: Int
}

/// The Stop button on the Lock Screen and in the Dynamic Island. A LiveActivityIntent runs in the app's process,
/// where `handler` (set when the app starts) stops the timer and keeps the minutes focused so far.
struct StopFocusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop focusing"
    static var isDiscoverable = false

    @MainActor static var handler: (() -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        let handled = await MainActor.run { () -> Bool in
            guard let handler = Self.handler else { return false }
            handler()
            return true
        }
        if !handled {
            for activity in Activity<FocusActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        return .result()
    }
}
#endif
