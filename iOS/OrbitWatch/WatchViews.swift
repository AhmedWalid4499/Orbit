import WatchKit
import SwiftUI

enum WatchTheme {
    static let lime = Color(red: 0.90, green: 1.0, blue: 0.12)
    static let pink = Color(red: 0.97, green: 0.76, blue: 0.93)
    static let cyan = Color(red: 0.15, green: 0.83, blue: 0.96)
    static let orange = Color(red: 0.93, green: 0.67, blue: 0.18)
    static let peach = Color(red: 1.0, green: 0.78, blue: 0.62)
    static let purple = Color(red: 0.75, green: 0.60, blue: 0.98)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.08)
}

struct WatchRoot: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        NavigationStack {
            TabView {
                TodayPage()
                TasksPage()
                HabitsPage()
                MoneyPage()
                AskPage()
            }
            .tabViewStyle(.verticalPage)
        }
        .overlay(alignment: .bottom) {
            if let t = store.toast {
                Text(t).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 4)
            }
        }
    }
}

/// When nothing has come over yet.
struct WaitingView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.radiowaves.left.and.right").font(.title2).foregroundStyle(WatchTheme.lime)
            Text("Open Orbit on your iPhone once").font(.headline).multilineTextAlignment(.center)
            Text("Your day appears here as soon as they connect.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

// MARK: - Today

struct TodayPage: View {
    @EnvironmentObject private var store: WatchStore
    @State private var adding = ""

    var body: some View {
        ScrollView {
            if let s = store.snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day())).font(.headline)
                        Spacer()
                        if !s.weather.isEmpty { Text(s.weather).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    if !s.dayLine.isEmpty {
                        Text(s.dayLine).font(.system(.footnote, design: .serif).weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let e = s.events.first {
                        card(WatchTheme.cyan) {
                            Label(e.allDay ? "All day" : e.start.formatted(date: .omitted, time: .shortened), systemImage: "calendar").font(.caption2.weight(.semibold))
                            Text(e.title).font(.footnote.weight(.semibold)).lineLimit(2)
                            if s.events.count > 1 { Text("+\(s.events.count - 1) more").font(.caption2).opacity(0.7) }
                        }
                    }
                    HStack(spacing: 6) {
                        mini("\(s.tasks.count)", "to do", WatchTheme.lime)
                        mini("\(s.habits.filter(\.done).count)/\(s.habits.count)", "habits", WatchTheme.orange)
                    }
                    card(WatchTheme.peach) {
                        Label("Spent today", systemImage: "creditcard.fill").font(.caption2.weight(.semibold))
                        Text(s.spentToday).font(.title3.weight(.bold)).minimumScaleFactor(0.6).lineLimit(1)
                        Text("\(s.budgetLeft) left this month").font(.caption2).opacity(0.75)
                    }
                    if let b = s.reading {
                        card(WatchTheme.purple) {
                            Label("Reading", systemImage: "book.fill").font(.caption2.weight(.semibold))
                            Text(b.title).font(.footnote.weight(.semibold)).lineLimit(2)
                            ProgressView(value: b.progress).tint(WatchTheme.ink)
                            Text("\(Int(b.progress * 100))%").font(.caption2).opacity(0.75)
                        }
                    }
                    QuickAddField(placeholder: "Add anything")
                }
            } else {
                WaitingView()
            }
        }
        .navigationTitle("Orbit")
        .refreshable { store.refresh() }
    }

    private func mini(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.headline.weight(.bold))
            Text(label).font(.caption2).opacity(0.75)
        }
        .foregroundStyle(WatchTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(color))
    }

    private func card<Content: View>(_ color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3, content: content)
            .foregroundStyle(WatchTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(color))
    }
}

/// Type, scribble or dictate; the iPhone files it as a task, event, expense or note.
struct QuickAddField: View {
    @EnvironmentObject private var store: WatchStore
    var placeholder: String
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .submitLabel(.done)
            .onSubmit {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                text = ""
                store.send(WatchAction(kind: .capture, text: t))
            }
    }
}

// MARK: - Tasks

struct TasksPage: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        List {
            if let s = store.snapshot {
                let open = s.tasks.filter { !store.pendingDone.contains($0.id) }
                if open.isEmpty {
                    Label(s.tasksDoneToday > 0 ? "All done for today" : "Nothing due today", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(WatchTheme.lime)
                }
                ForEach(open) { t in
                    Button {
                        withAnimation { _ = store.pendingDone.insert(t.id) }
                        WKInterfaceDeviceHaptic.success()
                        store.send(WatchAction(kind: .completeTask, id: t.id), quiet: true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "circle").foregroundStyle(t.overdue ? WatchTheme.orange : WatchTheme.lime)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).font(.footnote).lineLimit(3)
                                if t.overdue { Text("Overdue").font(.caption2).foregroundStyle(WatchTheme.orange) }
                            }
                        }
                    }
                }
                if s.tasksDoneToday + store.pendingDone.count > 0 {
                    Text("\(s.tasksDoneToday + store.pendingDone.count) done today").font(.caption2).foregroundStyle(.secondary)
                }
                QuickAddField(placeholder: "New task")
            } else {
                WaitingView()
            }
        }
        .navigationTitle("Tasks")
    }
}

// MARK: - Habits

struct HabitsPage: View {
    @EnvironmentObject private var store: WatchStore
    private let colors = [WatchTheme.lime, WatchTheme.pink, WatchTheme.cyan, WatchTheme.orange, WatchTheme.purple, WatchTheme.peach]

    var body: some View {
        ScrollView {
            if let s = store.snapshot {
                if s.habits.isEmpty { Text("No habits yet. Add them in Orbit on your iPhone.").font(.footnote).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(Array(s.habits.enumerated()), id: \.element.id) { i, h in
                        let done = h.done != store.pendingHabits.contains(h.id)
                        Button {
                            withAnimation {
                                if store.pendingHabits.contains(h.id) { store.pendingHabits.remove(h.id) } else { store.pendingHabits.insert(h.id) }
                            }
                            WKInterfaceDeviceHaptic.click()
                            store.send(WatchAction(kind: .toggleHabit, id: h.id), quiet: true)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: done ? "checkmark" : h.symbol).font(.title3.weight(.semibold))
                                Text(h.name).font(.caption2.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                                if h.streak > 0 { Text("\(h.streak + (done && !h.done ? 1 : 0))🔥").font(.caption2) }
                            }
                            .foregroundStyle(done ? WatchTheme.ink : .primary)
                            .frame(maxWidth: .infinity, minHeight: 78)
                            .background(RoundedRectangle(cornerRadius: 14).fill(done ? colors[i % colors.count] : Color.gray.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                WaitingView()
            }
        }
        .navigationTitle("Habits")
    }
}

// MARK: - Money

struct MoneyPage: View {
    @EnvironmentObject private var store: WatchStore
    @State private var amount = 0.0
    @State private var what = ""
    @State private var logging = false

    var body: some View {
        ScrollView {
            if let s = store.snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.spentToday).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                    Text("spent today").font(.caption2).foregroundStyle(.secondary)
                    ProgressView(value: min(1, s.budgetUsed)).tint(s.budgetUsed >= 1 ? .red : s.budgetUsed >= 0.8 ? WatchTheme.orange : WatchTheme.lime)
                    Text("\(s.spentMonth) this month · \(s.budgetLeft) left").font(.caption2).foregroundStyle(.secondary)
                    Button { logging = true } label: { Label("Log expense", systemImage: "plus") }
                        .tint(WatchTheme.lime)
                    if !s.recentExpenses.isEmpty {
                        Text("Recent").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                        ForEach(s.recentExpenses) { e in
                            HStack { Text(e.title).font(.caption).lineLimit(1); Spacer(); Text(e.amount).font(.caption.weight(.semibold)) }
                        }
                    }
                }
            } else {
                WaitingView()
            }
        }
        .navigationTitle("Money")
        .sheet(isPresented: $logging) { expenseSheet }
    }

    private var expenseSheet: some View {
        VStack(spacing: 8) {
            Text(amount.formatted(.number.precision(.fractionLength(0...2))) + " " + (store.snapshot?.currency ?? ""))
                .font(.title2.weight(.bold)).focusable()
                .digitalCrownRotation($amount, from: 0, through: 50000, by: 5, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            Text("Turn the crown").font(.caption2).foregroundStyle(.secondary)
            TextField("What for?", text: $what)
            Button("Log") {
                store.send(WatchAction(kind: .logExpense, text: what, amount: amount))
                amount = 0; what = ""; logging = false
            }
            .tint(WatchTheme.lime).disabled(amount <= 0)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Ask

struct AskPage: View {
    @EnvironmentObject private var store: WatchStore
    @State private var question = ""
    @State private var answer = ""
    @State private var asked = ""
    @State private var thinking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if store.snapshot?.hasAI == false {
                    Text("Add your API key in Orbit on your iPhone to ask questions here.").font(.footnote).foregroundStyle(.secondary)
                }
                TextField("Ask \(store.snapshot?.assistantName ?? "Ask")…", text: $question)
                    .submitLabel(.send)
                    .onSubmit(ask)
                if thinking { HStack { ProgressView(); Text("Thinking…").font(.footnote) } }
                if !asked.isEmpty { Text(asked).font(.caption2).foregroundStyle(.secondary) }
                if !answer.isEmpty {
                    Text(answer).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Button { WatchVoice.speak(answer) } label: { Label("Read aloud", systemImage: "speaker.wave.2.fill") }
                }
                if answer.isEmpty && !thinking {
                    Text("Try “what should I wear today?”, “find coffee near me” or “move the gym to 8pm”.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(store.snapshot?.assistantName ?? "Ask")
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        asked = q; question = ""; answer = ""; thinking = true
        store.send(WatchAction(kind: .ask, text: q)) { reply in
            thinking = false
            answer = reply
            WatchVoice.speak(reply)
        }
    }
}

/// Small haptic helpers.
enum WKInterfaceDeviceHaptic {
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func click() { WKInterfaceDevice.current().play(.click) }
}
