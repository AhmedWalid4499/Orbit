import SwiftUI
import SwiftData
import Charts

/// Insights: how your weeks are going across tasks, focus, reading, money, habits and mood. Mac tab and iPhone screen.
struct InsightsDashboard: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var review = ReviewStore.shared
    @Query private var tasks: [TaskItem]
    @Query private var txns: [Transaction]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var focus: [FocusSession]
    @Query private var reading: [ReadingSession]
    @Query private var books: [Book]
    @AppStorage("monthlyBudget") private var budget = 2000.0

    private var today: Date { .now.startOfDay }
    private var weekStart: Date { Date.now.startOfWeek }
    private var lastWeekStart: Date { weekStart.adding(days: -7) }

    var body: some View {
        let mood = MoodInsights.series(context: context)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Insights", size: 38, isPage: true) {
                    Text("This week compared with last, and the trends behind it.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                } actions: { EmptyView() }
                tiles(mood)
                HealthCard()
                YouTubeCard()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Platform.isPhone ? 300 : 360), spacing: 16, alignment: .top)], spacing: 16) {
                    spendingByMonth
                    spendingByCategory
                    tasksPerWeek
                    timePerDay
                    habitsKept
                    moodTrend(mood)
                    moodByWeekday(mood)
                    booksPerMonth
                    patterns(mood)
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .onAppear { review.load(week: .now) }
    }

    // MARK: Tiles

    private func tiles(_ mood: [MoodInsights.Point]) -> some View {
        func inWeek(_ d: Date?, _ start: Date) -> Bool { d.map { $0 >= start && $0 < start.adding(days: 7) } ?? false }
        let done = tasks.filter { $0.isDone && inWeek($0.completedAt, weekStart) }.count
        let doneLast = tasks.filter { $0.isDone && inWeek($0.completedAt, lastWeekStart) }.count
        let focusNow = FocusTimer.minutes(focus, since: weekStart)
        let focusLast = FocusTimer.minutes(focus, since: lastWeekStart, until: weekStart)
        let readNow = Int(reading.filter { inWeek($0.start, weekStart) }.reduce(0) { $0 + $1.minutes })
        let readLast = Int(reading.filter { inWeek($0.start, lastWeekStart) }.reduce(0) { $0 + $1.minutes })
        let spentNow = -txns.filter { $0.isExpense && inWeek($0.date, weekStart) }.reduce(0) { $0 + $1.amount }
        let spentLast = -txns.filter { $0.isExpense && inWeek($0.date, lastWeekStart) }.reduce(0) { $0 + $1.amount }
        let recent = mood.filter { $0.day >= today.adding(days: -30) }
        let avgMood = recent.isEmpty ? nil : Double(recent.reduce(0) { $0 + $1.mood }) / Double(recent.count)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            tile("\(done)", "Tasks done", delta(Double(done), Double(doneLast)), Theme.pink)
            tile("\(focusNow) min", "Focused", delta(Double(focusNow), Double(focusLast)), Theme.orange)
            tile("\(readNow) min", "Reading", delta(Double(readNow), Double(readLast)), Theme.purple)
            tile(Fmt.money(spentNow), "Spent", delta(spentNow, spentLast, lowerIsBetter: true), Theme.cyan)
            tile(avgMood.map { "\(Mood.faces[Int($0.rounded())]) \(String(format: "%.1f", $0))" } ?? "—", "Mood, 30 days", nil, Theme.peach)
            tile(habitRate.map { "\($0)%" } ?? "—", "Habits kept, 30 days", nil, Theme.lime)
        }
    }

    /// "↑ 20% vs last week", coloured by whether that's good.
    private func delta(_ now: Double, _ before: Double, lowerIsBetter: Bool = false) -> (String, Bool)? {
        guard before > 0 else { return now > 0 ? ("New this week", true) : nil }
        let change = (now - before) / before
        if abs(change) < 0.05 { return ("Same as last week", true) }
        let good = lowerIsBetter ? change < 0 : change > 0
        return ("\(change > 0 ? "↑" : "↓") \(Int(abs(change) * 100))% vs last week", good)
    }

    private func tile(_ value: String, _ label: String, _ delta: (String, Bool)?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(Theme.ui(12, weight: .semibold)).opacity(0.8).lineLimit(1)
            Text(delta?.0 ?? " ").font(Theme.ui(11, weight: .semibold)).lineLimit(1)
                .foregroundStyle(delta.map { $0.1 ? Color(hex: 0x14532D) : Color(hex: 0x7F1D1D) } ?? .clear)
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color))
    }

    private var habitRate: Int? {
        guard !habits.isEmpty else { return nil }
        let days = (0..<30).map { today.adding(days: -$0) }
        let done = habits.reduce(0) { sum, h in sum + days.filter { h.isDone(on: $0) }.count }
        let target = habits.reduce(0.0) { $0 + Double($1.targetPerWeek) * 30 / 7 }
        return target > 0 ? min(100, Int(Double(done) / target * 100)) : nil
    }

    // MARK: Charts

    private func card<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.display(19))
                    Text(subtitle).font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
                content()
            }
        }
    }

    private struct Bar: Identifiable { let id = UUID(); let x: Date; let y: Double; var series = "" }

    private var spendingByMonth: some View {
        let months = (0..<6).reversed().map { Calendar.current.date(byAdding: .month, value: -$0, to: Date.now.startOfMonth)! }
        let bars = months.map { m -> Bar in
            let end = Calendar.current.date(byAdding: .month, value: 1, to: m)!
            return Bar(x: m, y: -txns.filter { $0.isExpense && $0.date >= m && $0.date < end }.reduce(0) { $0 + $1.amount })
        }
        return card("Spending by month", "Last 6 months, against your \(Fmt.money(budget)) budget") {
            Chart {
                ForEach(bars) { b in
                    BarMark(x: .value("Month", b.x, unit: .month), y: .value("Spent", b.y), width: .ratio(0.6))
                        .foregroundStyle(b.y > budget ? Theme.orange : Theme.cyan).cornerRadius(5)
                }
                RuleMark(y: .value("Budget", budget)).foregroundStyle(Theme.inkMuted).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel() } }
            .frame(height: 170)
        }
    }

    private var spendingByCategory: some View {
        let month = Date.now.startOfMonth
        let rows = Dictionary(grouping: txns.filter { $0.isExpense && $0.date >= month }, by: \.category)
            .map { (cat: $0.key, total: -$0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }.prefix(6)
        let colors = [Theme.pink, Theme.cyan, Theme.lime, Theme.orange, Theme.purple, Theme.mint]
        return card("Where the money went", "This month, by category") {
            if rows.isEmpty {
                EmptyHint(symbol: "creditcard", text: "No spending this month yet.")
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(Array(rows.enumerated()), id: \.element.cat) { i, r in
                        SectorMark(angle: .value("Spent", r.total), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(colors[i % colors.count]).cornerRadius(3)
                    }
                    .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(rows.enumerated()), id: \.element.cat) { i, r in
                            HStack(spacing: 6) {
                                Circle().fill(colors[i % colors.count]).frame(width: 8, height: 8)
                                Text(r.cat).font(Theme.ui(12)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Fmt.money(r.total)).font(Theme.ui(12, weight: .semibold)).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var tasksPerWeek: some View {
        let weeks = (0..<8).reversed().map { weekStart.adding(days: -7 * $0) }
        let bars = weeks.map { w in Bar(x: w, y: Double(tasks.filter { $0.isDone && ($0.completedAt.map { $0 >= w && $0 < w.adding(days: 7) } ?? false) }.count)) }
        return card("Tasks done", "Per week, last 8 weeks") {
            if bars.allSatisfy({ $0.y == 0 }) { EmptyHint(symbol: "checkmark.circle", text: "Tick off tasks and your weekly count shows here.") } else {
            Chart(bars) { b in
                BarMark(x: .value("Week", b.x, unit: .weekOfYear), y: .value("Done", b.y), width: .ratio(0.6))
                    .foregroundStyle(b.x == weekStart ? Theme.pink : Theme.ink.opacity(0.75)).cornerRadius(5)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel() } }
            .frame(height: 160)
            }
        }
    }

    private var timePerDay: some View {
        let days = (0..<14).reversed().map { today.adding(days: -$0) }
        var bars: [Bar] = []
        for d in days {
            let next = d.adding(days: 1)
            bars.append(Bar(x: d, y: Double(FocusTimer.minutes(focus, since: d, until: next)), series: "Focus"))
            bars.append(Bar(x: d, y: reading.filter { $0.start >= d && $0.start < next }.reduce(0) { $0 + $1.minutes }, series: "Reading"))
        }
        return card("Focus and reading", "Minutes per day, last 2 weeks") {
            if bars.allSatisfy({ $0.y == 0 }) { EmptyHint(symbol: "timer", text: "Start a focus block or a reading session to see your time here.") } else {
            Chart(bars) { b in
                BarMark(x: .value("Day", b.x, unit: .day), y: .value("Minutes", b.y))
                    .foregroundStyle(by: .value("Kind", b.series)).cornerRadius(3)
            }
            .chartForegroundStyleScale(["Focus": Theme.orange, "Reading": Theme.purple])
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel() } }
            .frame(height: 170)
            }
        }
    }

    private var habitsKept: some View {
        let days = (0..<30).map { today.adding(days: -$0) }
        let rows = habits.map { h -> (name: String, rate: Double, color: Color) in
            let target = Double(h.targetPerWeek) * 30 / 7
            return (h.name, min(1, Double(days.filter { h.isDone(on: $0) }.count) / max(target, 1)), h.area.color)
        }
        return card("Habits kept", "Last 30 days, against each habit's weekly target") {
            if rows.isEmpty {
                EmptyHint(symbol: "repeat", text: "Add a habit to see how well you keep it.")
            } else {
                VStack(spacing: 9) {
                    ForEach(rows, id: \.name) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(r.name).font(Theme.ui(13, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text("\(Int(r.rate * 100))%").font(Theme.ui(12, weight: .semibold))
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.line)
                                    Capsule().fill(r.color).frame(width: max(6, g.size.width * r.rate))
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
        }
    }

    private func moodTrend(_ points: [MoodInsights.Point]) -> some View {
        card("Mood", "Last 90 days, from your journal") {
            if points.count < 3 {
                EmptyHint(symbol: "face.smiling", text: "Rate your mood in the journal for a few days to see it here.")
            } else {
                Chart(points) { p in
                    AreaMark(x: .value("Day", p.day, unit: .day), yStart: .value("Base", 1), yEnd: .value("Mood", p.mood))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.purple.opacity(0.35), Theme.purple.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("Mood", p.mood))
                        .interpolationMethod(.monotone).foregroundStyle(Theme.ink).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [1, 3, 5]) { v in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel { if let i = v.as(Int.self) { Text(Mood.faces[i]) } }
                    }
                }
                .frame(height: 160)
            }
        }
    }

    private func moodByWeekday(_ points: [MoodInsights.Point]) -> some View {
        let data = MoodInsights.byWeekday(points)
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let best = data.max { $0.mood < $1.mood }?.weekday
        return card("Best days", "Average mood by day of the week") {
            if data.isEmpty {
                EmptyHint(symbol: "calendar", text: "Appears after a couple of weeks of mood check-ins.")
            } else {
                Chart(data, id: \.weekday) { d in
                    BarMark(x: .value("Day", symbols[d.weekday - 1]), y: .value("Mood", d.mood), width: .ratio(0.5))
                        .foregroundStyle(d.weekday == best ? Theme.lime : Theme.ink.opacity(0.7)).cornerRadius(5)
                }
                .chartYScale(domain: 0...5)
                .chartYAxis(.hidden)
                .frame(height: 140)
            }
        }
    }

    private var booksPerMonth: some View {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: .now))!
        let months = (0..<12).map { Calendar.current.date(byAdding: .month, value: $0, to: start)! }
        let bars = months.map { m in
            Bar(x: m, y: Double(books.filter { $0.status == .read && ($0.finishedAt.map { Calendar.current.isDate($0, equalTo: m, toGranularity: .month) } ?? false) }.count))
        }
        let total = Int(bars.reduce(0) { $0 + $1.y })
        return card("Books finished", "\(total) this year") {
            Chart(bars) { b in
                BarMark(x: .value("Month", b.x, unit: .month), y: .value("Books", b.y), width: .ratio(0.55))
                    .foregroundStyle(Theme.purple).cornerRadius(4)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel() } }
            .frame(height: 130)
        }
    }

    private func patterns(_ points: [MoodInsights.Point]) -> some View {
        let facts = MoodInsights.facts(context: context, apple: apple, points: points)
        return card("Patterns", "Things that go together in your data (not causes)") {
            if !review.patterns.isEmpty {
                ForEach(review.patterns.prefix(4)) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(Theme.ui(13, weight: .semibold))
                        Text(p.detail).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if facts.isEmpty {
                EmptyHint(symbol: "sparkle.magnifyingglass", text: "Patterns show up once there are a few weeks of mood, habits and spending.")
            } else {
                ForEach(facts.prefix(4)) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.inkMuted).frame(width: 5, height: 5).offset(y: -2)
                        Text(f.text).font(Theme.ui(12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
