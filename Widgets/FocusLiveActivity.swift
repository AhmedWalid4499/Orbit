#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The running focus block on the Lock Screen and in the Dynamic Island: what you're on, a live countdown that keeps
/// going while the app is closed, a progress bar, and Stop. FocusActivityAttributes lives in iOS/Shared.
struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLockScreen(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(W.ink)
                .activitySystemActionForegroundColor(W.lime)
                .widgetURL(URL(string: "com.personal.orbit://open/today"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(s.finished ? "Done" : "Focus") } icon: { Image(systemName: s.finished ? "checkmark.circle.fill" : "timer") }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(W.lime)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusClock(state: s)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.attributes.task.isEmpty ? "\(context.attributes.minutes)-minute focus" : context.attributes.task)
                            .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 10) {
                            FocusBar(state: s)
                            if !s.finished { StopButton(compact: true) }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: s.finished ? "checkmark.circle.fill" : "timer").foregroundStyle(W.lime)
            } compactTrailing: {
                FocusClock(state: s)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(W.lime)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: s.finished ? "checkmark.circle.fill" : "timer").foregroundStyle(W.lime)
            }
            .widgetURL(URL(string: "com.personal.orbit://open/today"))
            .keylineTint(W.lime)
        }
    }
}

/// Counts down by itself (the system redraws it every second, even with Joshu closed).
private struct FocusClock: View {
    let state: FocusActivityAttributes.ContentState
    var body: some View {
        if state.finished || state.end <= .now {
            Text("0:00").monospacedDigit()
        } else {
            Text(timerInterval: state.start...state.end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct FocusBar: View {
    let state: FocusActivityAttributes.ContentState
    var body: some View {
        Group {
            if state.finished || state.end <= .now {
                ProgressView(value: 1)
            } else {
                ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            }
        }
        .progressViewStyle(.linear)
        .tint(W.lime)
    }
}

private struct StopButton: View {
    var compact = false
    var body: some View {
        Button(intent: StopFocusIntent()) {
            Label("Stop", systemImage: "stop.fill")
                .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, compact ? 10 : 12).padding(.vertical, compact ? 5 : 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(W.ink)
        .background(Capsule().fill(W.lime))
    }
}

private struct FocusLockScreen: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(W.lime).frame(width: 38, height: 38)
                    Image(systemName: state.finished ? "checkmark" : "timer")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(W.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.finished ? "Focus done · take 5" : "Focusing")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(W.lime)
                    Text(attributes.task.isEmpty ? "\(attributes.minutes)-minute focus" : attributes.task)
                        .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 8)
                FocusClock(state: state)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            HStack(spacing: 12) {
                FocusBar(state: state)
                if !state.finished { StopButton() }
            }
        }
        .padding(16)
    }
}
#endif
