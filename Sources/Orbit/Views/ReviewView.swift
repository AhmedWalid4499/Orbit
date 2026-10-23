import SwiftUI
import SwiftData
import Charts

/// Weekly review (Sunday) and mood & life insights.
struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @EnvironmentObject private var state: AppState
    @ObservedObject private var store = ReviewStore.shared
    @ObservedObject private var ai = AIAssistant.shared

    @State private var section: String

    init(startOnInsights: Bool = false) { _section = State(initialValue: startOnInsights ? "insights" : "week") }
    @State private var week = Date.now.startOfWeek
    @State private var added: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(section == "week" ? "Week in review" : "Mood & life insights").font(Theme.display(Platform.isPhone ? 22 : 28))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack(spacing: 2) {
                    ForEach([("week", "This week"), ("insights", "Insights")], id: \.0) { id, title in
                        Button(title) { withAnimation(.snappy) { section = id } }
                            .buttonStyle(.plain).font(Theme.ui(13, weight: .semibold)).lineLimit(1).fixedSize()
                            .foregroundStyle(section == id ? Theme.onInverse : Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(section == id ? Theme.inverse : .clear))
                    }
                }
                .padding(3).background(Capsule().fill(Theme.card))
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            .padding(Platform.isPhone ? 16 : 24)
            ScrollView {
                if section == "week" { weekView } else { InsightsView() }
            }
            .scrollIndicators(.never)
        }
        .sheetFrame(width: 920, height: 740)
        .background(Theme.canvas)
        .onAppear { store.load(week: week) }
    }

    // MARK: This week

    private var weekView: some View {
        let s = WeekStats.compute(context: context, apple: apple, weekContaining: week)
        let habitPct = s.habits.isEmpty ? nil : Int(Double(s.habits.reduce(0) { $0 + min($1.done, $1.target) }) / Double(max(1, s.habits.reduce(0) { $0 + $1.target })) * 100)
        let avgMood = s.moods.isEmpty ? nil : Double(s.moods.reduce(0) { $0 + $1.mood }) / Double(s.moods.count)
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { week = week.adding(days: -7); store.load(week: week); added = [] } label: { Image(systemName: "chevron.left") }
                Text(s.label).font(Theme.ui(14, weight: .semibold))
                Button { week = week.adding(days: 7); store.load(week: week); added = [] } label: { Image(systemName: "chevron.right") }
                    .disabled(week >= Date.now.startOfWeek)
                Spacer()
            }
            .buttonStyle(.plain)

            AdaptiveStack(grid: true) {
                tile("\(s.tasksDone.count)", "Tasks done", Theme.pink)
                tile(habitPct.map { "\($0)%" } ?? "—", "Habits kept", Theme.lime)
                tile(Fmt.money(s.spent), "Spent this week", Theme.cyan)
                tile(avgMood.map { "\(Mood.faces[Int($0.rounded())]) \(String(format: "%.1f", $0))" } ?? "—", "Average mood", Theme.peach)
                tile("\(s.readingMinutes) min", s.booksFinished.isEmpty ? "Reading" : "Read · \(s.booksFinished.count) finished", Theme.purple)
                tile("\(s.focusMinutes) min", "Focused", Theme.orange)
            }

            moodStrip(s)

            if ai.hasKey { reflectionCard(s) } else {
                Text("Add your Anthropic API key in Settings › AI and \(AssistantName.current) will write your review and suggest next week's focus.")
                    .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            }

            AdaptiveStack(spacing: 16) {
                listCard("Finished", items: s.tasksDone + s.booksFinished.map { "📖 \($0)" } + s.bucketDone.map { "⛰ \($0)" },
                         empty: "Nothing ticked off this week.")
                listCard("Habits", items: s.habits.map { "\($0.name): \($0.done) of \($0.target)" }, empty: "No habits yet.")
                listCard("Money", items: ["Month: \(Fmt.money(s.monthSpent)) of \(Fmt.money(s.budget))"]
                         + s.topCategories.map { "\($0.0): \(Fmt.money($0.1))" }, empty: "")
            }
        }
        .padding(.horizontal, Platform.isPhone ? 16 : 24).padding(.bottom, 24)
        .task(id: week) { if ai.hasKey { await store.reflect(on: s) } }
    }

    private func moodStrip(_ s: WeekStats) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                let day = s.start.adding(days: i)
                let m = s.moods.first { $0.day.isSameDay(as: day) }?.mood
                VStack(spacing: 4) {
                    Text(m.map { Mood.faces[$0] } ?? "·").font(.system(size: 22)).frame(height: 28)
                    Text(day.formatted(.dateTime.weekday(.abbreviated))).font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(day.isToday ? Theme.blush : Theme.card))
            }
        }
    }

    private func reflectionCard(_ s: WeekStats) -> some View {
        let ink = Color(hex: 0xF4F4F5)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.lime)
                Text("\(AssistantName.current)'s take").font(Theme.ui(12, weight: .semibold)).opacity(0.7)
                Spacer()
                if store.loading { ProgressView().controlSize(.small).tint(ink) }
                Button { Task { await store.reflect(on: s, force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(store.loading)
            }
            if let r = store.reflection {
                Text(r.headline).font(Theme.display(22)).fixedSize(horizontal: false, vertical: true)
                if !r.wins.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(r.wins, id: \.self) { Label($0, systemImage: "checkmark.circle.fill").font(Theme.ui(13)) }
                    }
                }
                ForEach(r.struggles, id: \.self) { Label($0, systemImage: "arrow.uturn.left.circle").font(Theme.ui(13)).opacity(0.85) }
                if !r.insight.isEmpty {
                    Text(r.insight).font(Theme.display(15, weight: .regular)).italic().opacity(0.85)
                }
                Text("Focus for next week").font(Theme.ui(12, weight: .semibold)).opacity(0.7).padding(.top, 4)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(r.focus) { f in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(f.title).font(Theme.ui(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                            Text(f.why).font(Theme.ui(11)).opacity(0.75).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button(added.contains(f.title) ? "Added ✓" : "Add to next week") { addFocus(f) }
                                .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.lime))
                                .disabled(added.contains(f.title))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                    }
                }
                HStack {
                    Button("Talk it through with \(AssistantName.current)") {
                        dismiss()
                        state.openAssistant(with: "Let's talk about my week (\(s.label)). Here's how it went:\n\(s.asText)")
                    }
                    .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
                    Spacer()
                    Button("Save review to journal") { saveToJournal(r, s) }.buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
                }
                .padding(.top, 4)
            } else if let e = store.error {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12))
            } else {
                Text("\(AssistantName.current) is looking back at your week…").font(Theme.display(18, weight: .regular))
            }
        }
        .foregroundStyle(ink)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0x141416)))
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(Theme.ui(11, weight: .semibold)).opacity(0.8).lineLimit(1)
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(color))
    }

    private func listCard(_ title: String, items: [String], empty: String) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.display(17))
                if items.isEmpty && !empty.isEmpty { Text(empty).font(Theme.ui(12)).foregroundStyle(Theme.inkMuted) }
                ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, t in
                    Text("• \(t)").font(Theme.ui(12)).lineLimit(2)
                }
                if items.count > 8 { Text("+\(items.count - 8) more").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted) }
            }
        }
    }

    private func addFocus(_ f: WeeklyReflection.Focus) {
        let nextWeek = Date.now.startOfWeek.adding(days: 7)
        context.insert(TaskItem(title: f.title, area: Area(rawValue: f.area) ?? .personal, due: nextWeek, priority: 2, notes: f.why))
        try? context.save()
        added.insert(f.title)
    }

    private func saveToJournal(_ r: WeeklyReflection, _ s: WeekStats) {
        let body = ([r.headline, ""] + r.wins.map { "• \($0)" } + r.struggles.map { "• \($0)" }
                    + ["", r.insight, "", "Next week:"] + r.focus.map { "• \($0.title): \($0.why)" }).joined(separator: "\n")
        context.insert(Note(title: "Week in review · \(s.label)", body: body))
        try? context.save()
    }
}

// MARK: - Insights

struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var store = ReviewStore.shared
    @ObservedObject private var ai = AIAssistant.shared
    @State private var hovered: Date?

    var body: some View {
        let points = MoodInsights.series(context: context)
        let facts = MoodInsights.facts(context: context, apple: apple, points: points)
        return VStack(alignment: .leading, spacing: 18) {
            if points.count < 5 {
                VStack(spacing: 10) {
                    Text("🙂").font(.system(size: 44))
                    Text("Rate your mood in the journal (or let \(AssistantName.current) pick it up in your check-ins) for a few days, and patterns start showing here.")
                        .font(Theme.ui(14)).multilineTextAlignment(.center).foregroundStyle(Theme.inkSecondary)
                    Text("\(points.count) of 5 days so far").font(Theme.ui(12, weight: .semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 60)
            } else {
                moodChart(points)
                HStack(alignment: .top, spacing: 16) {
                    weekdayChart(points).frame(width: 380)
                    patternsCard(facts)
                }
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
        .task { if ai.hasKey && store.patterns.isEmpty { await store.explain(facts) } }
    }

    private func moodChart(_ points: [MoodInsights.Point]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Mood, last 90 days").font(Theme.display(20))
                    Spacer()
                    if let d = hovered, let p = points.first(where: { $0.day.isSameDay(as: d) }) {
                        Text("\(p.day.formatted(.dateTime.weekday().day().month())) · \(Mood.faces[p.mood]) \(Mood.words[p.mood])")
                            .font(Theme.ui(12, weight: .medium))
                    } else {
                        Text("Hover for details").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                    }
                }
                Chart(points) { p in
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("Mood", p.mood))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.ink)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Day", p.day, unit: .day), y: .value("Mood", p.mood))
                        .foregroundStyle(Theme.ink)
                        .symbolSize(hovered.map { $0.isSameDay(as: p.day) } == true ? 90 : 30)
                }
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [1, 2, 3, 4, 5]) { v in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel { if let i = v.as(Int.self) { Text(Mood.faces[i]) } }
                    }
                }
                .chartXSelection(value: $hovered)
                .frame(height: 200)
            }
        }
    }

    private func weekdayChart(_ points: [MoodInsights.Point]) -> some View {
        let data = MoodInsights.byWeekday(points)
        let symbols = Calendar.current.shortWeekdaySymbols
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("By day of the week").font(Theme.display(18))
                Chart(data, id: \.weekday) { d in
                    BarMark(x: .value("Day", symbols[d.weekday - 1]), y: .value("Mood", d.mood), width: .ratio(0.55))
                        .foregroundStyle(Theme.ink)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                        .annotation(position: .top) { Text(String(format: "%.1f", d.mood)).font(Theme.ui(10)).foregroundStyle(Theme.inkSecondary) }
                }
                .chartYScale(domain: 0...5)
                .chartYAxis(.hidden)
                .frame(height: 170)
            }
        }
    }

    private func patternsCard(_ facts: [MoodFact]) -> some View {
        Card(fill: Theme.blush) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Patterns").font(Theme.display(18))
                    Spacer()
                    if store.loadingPatterns { ProgressView().controlSize(.small) }
                    if ai.hasKey {
                        Button { Task { await store.explain(facts) } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.plain).disabled(store.loadingPatterns || facts.isEmpty)
                    }
                }
                if facts.isEmpty {
                    Text("No clear patterns yet. They appear once there are a few days on both sides (e.g. gym days and rest days).")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                } else if !store.patterns.isEmpty {
                    ForEach(store.patterns) { p in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(Theme.ui(14, weight: .semibold))
                            Text(p.detail).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
                    }
                } else {
                    ForEach(facts.prefix(5)) { f in
                        Text("• \(f.text)").font(Theme.ui(12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Patterns are correlations from your own data, not causes.").font(Theme.ui(10)).foregroundStyle(Theme.inkMuted)
            }
        }
    }
}
