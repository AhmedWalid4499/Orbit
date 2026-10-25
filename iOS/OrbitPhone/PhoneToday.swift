import SwiftUI
import SwiftData

/// Today on iPhone: the same pieces as the Mac's Today, stacked for a phone.
struct PhoneToday: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @EnvironmentObject private var state: AppState

    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \EventItem.start) private var events: [EventItem]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]
    @Query(filter: #Predicate<BucketItem> { !$0.isDone && $0.kindRaw != "place" }) private var dreams: [BucketItem]
    @Query private var plans: [DayPlan]
    @Query private var focusSessions: [FocusSession]

    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var ai = AIAssistant.shared

    @AppStorage("monthlyBudget") private var monthlyBudget = 2000.0
    @AppStorage("userName") private var userName = ""
    @AppStorage("readingGoal") private var readingGoal = 24

    @State private var capture = ""
    @State private var capturing = false
    @State private var captureResult: String?

    private var today: Date { .now.startOfDay }
    private var isEvening: Bool { Calendar.current.component(.hour, from: .now) >= 17 }
    private var todaysPlan: DayPlan? { plans.filter { $0.day == DayKey.key(today) && !$0.top.isEmpty }.max { $0.createdAt < $1.createdAt } }
    private var planForTomorrow: Bool { plans.contains { $0.day == DayKey.key(today.adding(days: 1)) && !$0.top.isEmpty } }
    private var focusToday: Int { FocusTimer.minutes(focusSessions, since: today) }

    private var openToday: [TaskItem] {
        tasks.filter { !$0.isDone && ($0.due.map { $0 < today.adding(days: 1) } ?? false) }
            .sorted { ($0.priority, $1.due ?? .now) > ($1.priority, $0.due ?? .now) }
    }

    private var todayEntries: [CalEntry] {
        _ = apple.revision
        return CalEntry.merge(local: events.filter { $0.start.isSameDay(as: today) }, apple: apple.events(from: today, to: today.adding(days: 1)),
                              google: GoogleCalendarStore.shared.events(from: today, to: today.adding(days: 1)))
    }

    private var spentThisMonth: Double {
        BudgetPeriod.spent(transactions)
    }

    private var readThisYear: Int {
        let y = Calendar.current.component(.year, from: .now)
        return books.filter { $0.status == .read && ($0.finishedAt.map { Calendar.current.component(.year, from: $0) == y } ?? false) }.count
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        let first = userName.split(separator: " ").first.map(String.init) ?? ""
        let part = h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        return first.isEmpty ? part : "\(part), \(first)"
    }

    @Query private var readingSessions: [ReadingSession]

    @State private var briefOpen = false
    @State private var mailOpen = false
    @ObservedObject private var health = HealthStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(greeting)").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                    actions
                }
                captureField
                glance
                brief
                upNext
                habitsRow
                CheckInCard()
                if isEvening { DaySummaryCard(compact: true) }
                alsoToday
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .refreshable { await CloudSync.shared.syncIfSignedIn(context: context) }
        .sheet(isPresented: $mailOpen) { MailboxSheet() }
        .phoneChrome("Today")
    }

    // MARK: Summary

    /// Four small numbers in one row; each opens its section.
    private var glance: some View {
        HStack(spacing: 8) {
            mini("\(openToday.count)", "Due", Theme.peach) { state.tab = .tasks }
            mini("\(habits.filter { $0.isDone(on: today) }.count)/\(habits.count)", "Habits", Theme.lime) { state.tab = .habits }
            mini(Fmt.money(max(monthlyBudget - spentThisMonth, 0)), "Left", Theme.cyan) { state.tab = .money }
            if health.hasData {
                mini(health.today.steps >= 1000 ? String(format: "%.1fk", Double(health.today.steps) / 1000) : "\(health.today.steps)", "Steps", Theme.mint) { state.tab = .insights }
            } else {
                mini("\(readThisYear)/\(readingGoal)", "Books", Theme.purple) { state.tab = .reading }
            }
        }
    }

    private func mini(_ value: String, _ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.5)
                Text(label).font(Theme.ui(11, weight: .semibold)).opacity(0.75)
            }
            .foregroundStyle(Theme.stickerInk)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color))
        }
        .buttonStyle(.plain)
    }

    /// The morning brief in two lines; tap for the whole thing.
    @ViewBuilder private var brief: some View {
        if let b = ai.brief, ai.hasTodaysBrief {
            Button { withAnimation(.snappy) { briefOpen.toggle() } } label: {
                HStack(alignment: .top, spacing: 10) {
                    AssistantAvatar(size: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.headline).font(Theme.ui(15, weight: .semibold)).lineLimit(briefOpen ? nil : 1)
                        Text(b.summary).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).lineLimit(briefOpen ? nil : 2)
                        if briefOpen {
                            ForEach(Array(b.focus.enumerated()), id: \.offset) { i, f in
                                Text("\(i + 1). \(f)").font(Theme.ui(13, weight: .medium)).padding(.top, 2)
                            }
                            if !b.heads_up.isEmpty { Label(b.heads_up, systemImage: "exclamationmark.circle").font(Theme.ui(12)).foregroundStyle(Theme.orange) }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: briefOpen ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.inkMuted)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if ai.hasKey {
            BriefCard()
        }
    }

    /// Top 3, what's due and what's next on the calendar, a few of each, in one card.
    private var upNext: some View {
        let reminders = apple.reminders.filter { ($0.due ?? .distantFuture) < today.adding(days: 1) }
        let next = todayEntries.filter { $0.end > .now }
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Up next", trailing: "All tasks") { state.tab = .tasks }
                if let todaysPlan { TopThreeList(plan: todaysPlan) }
                if openToday.isEmpty && reminders.isEmpty && next.isEmpty && todaysPlan == nil {
                    EmptyHint(symbol: "checkmark.seal", text: "Nothing due and nothing on the calendar. Nice.")
                }
                ForEach(openToday.prefix(3)) { TaskRow(task: $0, showDue: $0.isOverdue) }
                ForEach(reminders.prefix(max(0, 3 - openToday.count))) { ReminderRow(reminder: $0) }
                if openToday.count + reminders.count > 3 {
                    Button("+\(openToday.count + reminders.count - 3) more due today") { state.tab = .tasks }
                        .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                }
                if !next.isEmpty {
                    Divider().padding(.vertical, 2)
                    ForEach(next.prefix(2)) { AgendaRow(entry: $0) }
                    if next.count > 2 {
                        Button("+\(next.count - 2) more today") { state.tab = .calendar }
                            .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
    }

    /// Habits as one line of chips to tick off.
    @ViewBuilder private var habitsRow: some View {
        if !habits.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(habits) { h in
                        let done = h.isDone(on: today)
                        Button { withAnimation(.snappy) { h.toggle(today) } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: done ? "checkmark" : h.symbol).font(.system(size: 11, weight: .bold))
                                Text(h.name).font(Theme.ui(13, weight: .semibold)).lineLimit(1)
                                if h.currentStreak > 1 { Text("\(h.currentStreak)🔥").font(Theme.ui(11)) }
                            }
                            .foregroundStyle(done ? Theme.stickerInk : Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(done ? h.area.color : Theme.canvas))
                            .overlay(Capsule().strokeBorder(h.area.color, lineWidth: done ? 0 : 1.5))
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.success, trigger: done)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
        }
    }

    /// Everything else as small chips: mood, reading, the next thing to look forward to, email.
    private var alsoToday: some View {
        let entry = notes.first { $0.isJournal && $0.createdAt.isToday }
        let current = BookLibrary.currentlyReading(books, sessions: readingSessions).first
        let upcoming = dreams.filter { ($0.targetDate ?? .distantPast) >= today }.min { $0.targetDate! < $1.targetDate! }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("How's today?").font(Theme.ui(13, weight: .semibold))
                Spacer()
                ForEach(1...5, id: \.self) { m in
                    Button { setMood(m) } label: {
                        Text(Mood.faces[m]).font(.system(size: 20)).frame(width: 34, height: 34)
                            .background(Circle().fill(entry?.mood == m ? Theme.lime : .clear))
                            .opacity(entry == nil || entry?.mood == 0 || entry?.mood == m ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.blush))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if let current {
                        smallChip("\(current.title) · \(Int(current.progress * 100))%", "book.fill", Theme.purple) { state.tab = .reading }
                    }
                    if let upcoming, let d = upcoming.targetDate {
                        let days = Calendar.current.dateComponents([.day], from: today, to: d.startOfDay).day ?? 0
                        smallChip("\(upcoming.title) · \(days == 0 ? "today" : "\(days)d")", upcoming.kind.symbol, upcoming.kind.color) { state.tab = .bucket }
                    }
                    if inbox.isConnected, let n = inbox.digest?.needsReply.count, n > 0 {
                        smallChip("\(n) email\(n == 1 ? "" : "s") to answer", "envelope.fill", Theme.pink) { mailOpen = true }
                    }
                    smallChip("Journal", "bubble.left.and.text.bubble.right", Theme.peach) { state.openTodayJournal = true; state.tab = .notes }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func smallChip(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.stickerInk)
                    .frame(width: 22, height: 22).background(Circle().fill(color))
                Text(title).font(Theme.ui(13, weight: .medium)).lineLimit(1)
            }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private var actions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button { state.planOpen = true } label: {
                    chip(planForTomorrow ? "Tomorrow planned" : "Plan tomorrow", planForTomorrow ? "checkmark.circle.fill" : "moon.stars.fill",
                         fill: isEvening && !planForTomorrow ? Theme.lime : Theme.card)
                }
                FocusMenu { chip(focusToday > 0 ? "Focus · \(focusToday) min" : "Focus", "timer", fill: Theme.card) }
                Button { state.reviewOpen = true } label: { chip("Week in review", "chart.line.uptrend.xyaxis", fill: Theme.card) }
            }
            .buttonStyle(.plain)
        }
        .scrollIndicators(.never)
    }

    private func chip(_ title: String, _ symbol: String, fill: Color) -> some View {
        Label(title, systemImage: symbol).font(Theme.ui(13, weight: .semibold)).lineLimit(1)
            .foregroundStyle(fill == Theme.card ? Theme.ink : Theme.stickerInk)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(fill))
    }

    private var captureField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if ai.smartCaptureActive {
                    AssistantAvatar(size: 22, busy: capturing)
                } else {
                    Image(systemName: capturing ? "hourglass" : "plus").foregroundStyle(Theme.inkSecondary)
                }
                TextField(ai.smartCaptureActive ? "Add anything: “gym tomorrow 7am”" : "Add a task, event, expense or note…", text: $capture)
                    .font(Theme.ui(15)).disabled(capturing).submitLabel(.done).onSubmit(runCapture)
                MicButton { heard in capture = heard; runCapture() }
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
            .background(Capsule().fill(Theme.card))
            if let captureResult {
                Text(captureResult).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.good).lineLimit(2).padding(.leading, 12)
            }
        }
    }

    private func runCapture() {
        let raw = capture.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !capturing else { return }
        capturing = true
        Task {
            let summary = await CaptureEngine.capture(raw, context: context)
            capture = ""
            capturing = false
            withAnimation { captureResult = "Saved: \(summary)" }
            try? await Task.sleep(for: .seconds(4))
            withAnimation { captureResult = nil }
        }
    }







    private func setMood(_ m: Int) {
        let entry = notes.first { $0.isJournal && $0.createdAt.isToday } ?? {
            let n = Note(title: Date.now.formatted(date: .complete, time: .omitted), isJournal: true)
            context.insert(n)
            return n
        }()
        entry.mood = entry.mood == m ? 0 : m
        entry.moodSetByUser = entry.mood != 0
    }




}
