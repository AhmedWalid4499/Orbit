import SwiftUI
import SwiftData

// MARK: - Quick capture (⌥Space panel)

struct QuickCaptureView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var ai = AIAssistant.shared
    @State private var text = ""
    @State private var saved: String?
    @State private var working = false
    @FocusState private var focused: Bool

    private var parsed: QuickParser.Result { QuickParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if working {
                    ProgressView().controlSize(.small).frame(width: 22)
                } else {
                    Image(systemName: ai.smartCaptureActive ? "sparkles" : "circle.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(Theme.ink).frame(width: 22)
                }
                TextField("Capture anything…  “dentist thu 3pm #health”, “$12 lunch”", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.ui(22))
                    .focused($focused)
                    .disabled(working)
                    .onSubmit(save)
            }
            HStack(spacing: 8) {
                if let saved {
                    Label(saved, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good).lineLimit(2)
                } else if working {
                    Text("\(AssistantName.current) is sorting this…").foregroundStyle(Theme.inkSecondary)
                } else if text.isEmpty && ai.smartCaptureActive {
                    Text("Type naturally — \(AssistantName.current) sorts it into tasks, events, money and notes. Several at once works too.")
                        .foregroundStyle(Theme.inkMuted)
                } else if text.isEmpty {
                    Text("Task · Event (with a time) · $ expense · +income · note: · journal:")
                        .foregroundStyle(Theme.inkMuted)
                } else {
                    Text("→ \(parsed.summary)")
                    if !parsed.title.isEmpty { Text("“\(parsed.title)”").foregroundStyle(Theme.inkSecondary).lineLimit(1) }
                }
                Spacer()
                Text("↩ save   esc close").foregroundStyle(Theme.inkMuted)
            }
            .font(Theme.ui(13, weight: .medium))
        }
        .padding(22)
        .frame(width: 620)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.canvas))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line))
        .foregroundStyle(Theme.ink)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .captureOpened)) { _ in
            saved = nil
            focused = true
        }
    }

    private func save() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !working else { return }
        guard ai.smartCaptureActive else { return finish([parsed], note: nil) }

        working = true
        Task {
            do {
                let items = try await ai.smartParse(raw)
                finish(items.isEmpty ? [QuickParser.parse(raw)] : items, note: nil)
            } catch {
                // Offline or API trouble: never lose the capture, fall back to the local parser.
                finish([QuickParser.parse(raw)], note: "used offline parser: \(error.localizedDescription)")
            }
            working = false
        }
    }

    private func finish(_ items: [QuickParser.Result], note: String?) {
        let valid = items.filter { !$0.title.isEmpty || $0.amount != nil }
        guard !valid.isEmpty else { return }
        valid.forEach { $0.save(in: context) }
        saved = "Saved — " + valid.map(\.summary).joined(separator: "  |  ") + (note.map { " (\($0))" } ?? "")
        text = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + (note == nil ? 1.2 : 3)) { CapturePanel.shared.hide() }
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject private var apple: AppleSync
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \EventItem.start) private var events: [EventItem]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]

    private var next: CalEntry? {
        let now = Date.now
        let local = events.filter { $0.end > now && $0.start < now.adding(days: 2) }
        return CalEntry.merge(local: local, apple: apple.events(from: now, to: now.adding(days: 2)), google: GoogleCalendarStore.shared.events(from: now, to: now.adding(days: 2))).first { $0.end > now }
    }

    private var dueToday: [TaskItem] {
        open.filter { ($0.due ?? .distantFuture) < Date.now.startOfDay.adding(days: 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Theme.display(20))
            if let next {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(next.tint).frame(width: 4, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(Theme.ui(14, weight: .semibold))
                        Text("\(Fmt.relativeDay(next.start)) · \(Fmt.time(next.start))").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                    }
                }
            } else {
                Text("No upcoming events").font(Theme.ui(13)).foregroundStyle(Theme.inkMuted)
            }
            Divider()
            Text("\(dueToday.count) task\(dueToday.count == 1 ? "" : "s") due today").font(Theme.ui(13, weight: .semibold))
            ForEach(dueToday.prefix(5)) { t in
                HStack(spacing: 8) {
                    Circle().fill(t.area.color).frame(width: 8, height: 8)
                    Text(t.title).font(Theme.ui(13)).lineLimit(1)
                }
            }
            Divider()
            MenuFocusRow(tasks: dueToday)
            Divider()
            HStack {
                Button("Quick capture") { CapturePanel.shared.show() }.buttonStyle(SoftButtonStyle())
                Spacer()
                Button("Open Joshu") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
        .padding(18)
        .frame(width: 300)
    }
}

/// Focus controls in the menu bar: the countdown while running, otherwise start on a task due today.
struct MenuFocusRow: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var timer = FocusTimer.shared
    let tasks: [TaskItem]

    var body: some View {
        if let s = timer.active {
            HStack(spacing: 10) {
                Image(systemName: "timer").foregroundStyle(Theme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(FocusTimer.clock(timer.remaining(at: timer.now))) left").font(Theme.ui(14, weight: .semibold)).monospacedDigit()
                    if !s.taskTitle.isEmpty { Text(s.taskTitle).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).lineLimit(1) }
                }
                Spacer()
                Button("Stop") { timer.stop(context: context) }.buttonStyle(SoftButtonStyle())
            }
        } else {
            HStack {
                Text("Focus").font(Theme.ui(13, weight: .semibold))
                Spacer()
                Menu("Start \(timer.length) min") {
                    Button("Without a task") { timer.start(context: context) }
                    if !tasks.isEmpty { Divider() }
                    ForEach(tasks.prefix(8)) { t in Button(t.title) { timer.start(task: t, context: context) } }
                }
                .fixedSize()
            }
        }
    }
}
