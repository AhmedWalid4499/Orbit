#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

// Joshu in Control Center, on the Lock Screen's bottom corners and on the Action button (iOS 18 controls).
// The intents live in iOS/Shared/WidgetIntents.swift.

/// Starts a focus block; the countdown appears on the Lock Screen and in the Dynamic Island.
struct FocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ahmedwalid.orbit.focus") {
            ControlWidgetButton(action: StartFocusIntent()) {
                Label("Start focus", systemImage: "timer")
            }
        }
        .displayName("Start focus")
        .description("Start a Joshu focus block without opening the app.")
    }
}

/// Opens Joshu ready to add a task, event, expense or note.
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ahmedwalid.orbit.quickadd") {
            ControlWidgetButton(action: QuickAddIntent()) {
                Label("Add to Joshu", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Add to Joshu")
        .description("Jot down a task, event, expense or note.")
    }
}
#endif
