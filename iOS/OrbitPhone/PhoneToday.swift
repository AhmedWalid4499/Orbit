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
    @Query(filter: #Predicate<BucketItem> { !$0.isDone }) private var dreams: [BucketItem]
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
        -transactions.filter { $0.isExpense && $0.date >= Date.now.startOfMonth }.reduce(0) { $0 + $1.amount }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(greeting)").font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary)
                    actions
                }
                captureField
                stats
                BriefCard()
                if let todaysPlan { TopThreeList(plan: todaysPlan) }
                dueToday
                agenda
                habitsStrip
                HStack(alignment: .top, spacing: 12) {
                    moneyMini
                    moodMini
                }
                .fixedSize(horizontal: false, vertical: true)
                readingCard
                lookingForward
                if inbox.isConnected { inboxCard }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .refreshable { await CloudSync.shared.syncIfSignedIn(context: context) }
        .phoneChrome("Today")
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
                Image(systemName: capturing ? "hourglass" : (ai.smartCaptureActive ? "sparkles" : "plus")).foregroundStyle(Theme.inkSecondary)
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

    private var stats: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                StatTile(value: "\(openToday.count)", label: "Due today", symbol: "sun.max.fill", color: Theme.peach) { state.tab = .tasks }
                    .frame(width: 150)
                StatTile(value: "\(habits.filter { $0.isDone(on: today) }.count)/\(habits.count)", label: "Habits today",
                         symbol: "flame.fill", color: Theme.lime) { state.tab = .habits }.frame(width: 150)
                StatTile(value: Fmt.money(spentThisMonth), label: "Spent this month", symbol: "creditcard.fill", color: Theme.cyan) { state.tab = .money }
                    .frame(width: 170)
                StatTile(value: "\(readThisYear)/\(readingGoal)", label: "Books this year", symbol: "books.vertical.fill", color: Theme.purple) { state.tab = .reading }
                    .frame(width: 150)
                if inbox.isConnected {
                    StatTile(value: "\(inbox.digest?.needsReply.count ?? 0)", label: "Emails to answer", symbol: "envelope.fill", color: Theme.pink) {}
                        .frame(width: 160)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var dueToday: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Due today", trailing: "All tasks") { state.tab = .tasks }
                let reminders = apple.reminders.filter { ($0.due ?? .distantFuture) < today.adding(days: 1) }
                if openToday.isEmpty && reminders.isEmpty { EmptyHint(symbol: "checkmark.seal", text: "Nothing due. Nice.") }
                ForEach(openToday) { TaskRow(task: $0, showDue: $0.isOverdue) }
                ForEach(reminders) { ReminderRow(reminder: $0) }
            }
        }
    }

    private var agenda: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Agenda", trailing: "Calendar") { state.tab = .calendar }
                if todayEntries.isEmpty {
                    EmptyHint(symbol: "sun.max", text: apple.calendarEnabled ? "Nothing scheduled today." : "Nothing scheduled. Connect Apple Calendar in Settings.")
                }
                ForEach(todayEntries) { AgendaRow(entry: $0) }
            }
        }
    }

    private var habitsStrip: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Habits", trailing: habits.isEmpty ? "Add habit" : "View all") { state.tab = .habits }
                if habits.isEmpty {
                    EmptyHint(symbol: "repeat", text: "Build a streak: add your first habit.")
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(habits) { h in
                            let done = h.isDone(on: today)
                            Button { withAnimation(.snappy) { h.toggle(today) } } label: {
                                HStack(spacing: 8) {
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
                }
            }
        }
    }

    private var moneyMini: some View {
        let ratio = monthlyBudget > 0 ? min(spentThisMonth / monthlyBudget, 1) : 0
        return Button { state.tab = .money } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Left to spend").font(Theme.ui(12, weight: .semibold))
                Text(Fmt.money(max(monthlyBudget - spentThisMonth, 0))).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.5)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.12))
                        Capsule().fill(Color(hex: 0x111111)).frame(width: g.size.width * ratio)
                    }
                }
                .frame(height: 6)
                Text("of \(Fmt.money(monthlyBudget))").font(Theme.ui(11)).opacity(0.7)
            }
            .foregroundStyle(Theme.stickerInk)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.lime))
        }
        .buttonStyle(.plain)
    }

    private var moodMini: some View {
        let entry = notes.first { $0.isJournal && $0.createdAt.isToday }
        return VStack(alignment: .leading, spacing: 8) {
            Text("How's today?").font(Theme.ui(12, weight: .semibold))
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { m in
                    Button { setMood(m) } label: {
                        Text(Mood.faces[m]).font(.system(size: 20))
                            .frame(width: 30, height: 32)
                            .background(Circle().fill(entry?.mood == m ? Theme.lime : .clear))
                            .opacity(entry == nil || entry?.mood == 0 || entry?.mood == m ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { state.openTodayJournal = true; state.tab = .notes } label: {
                Label(entry?.chat == nil ? "Check in" : "Journal", systemImage: "bubble.left.and.text.bubble.right").font(Theme.ui(12, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.blush))
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

    private var readingCard: some View {
        let current = books.first { $0.status == .reading }
        return Button { state.tab = .reading } label: {
            HStack(spacing: 12) {
                if let current {
                    BookCover(book: current).frame(width: 40, height: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reading").font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                        Text(current.title).font(Theme.ui(14, weight: .semibold)).lineLimit(1)
                        ProgressView(value: current.progress).tint(Theme.ink)
                        Text("\(Int(current.progress * 100))% · \(readThisYear) of \(readingGoal) books this year").font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary)
                    }
                } else {
                    Image(systemName: "books.vertical.fill").frame(width: 40, height: 40).background(Circle().fill(Theme.purple)).foregroundStyle(Theme.stickerInk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(readThisYear) of \(readingGoal) books this year").font(Theme.ui(14, weight: .semibold))
                        Text("Nothing on the go. Pick your next read.").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lookingForward: some View {
        let upcoming = dreams.filter { ($0.targetDate ?? .distantPast) >= today }.sorted { $0.targetDate! < $1.targetDate! }
        return Group {
            if !upcoming.isEmpty {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Looking forward to", trailing: "Bucket list") { state.tab = .bucket }
                        ForEach(upcoming.prefix(4)) { item in
                            let days = Calendar.current.dateComponents([.day], from: today, to: item.targetDate!.startOfDay).day ?? 0
                            HStack(spacing: 12) {
                                Text(days == 0 ? "🎉" : "\(days)d").font(Theme.display(17)).frame(width: 50)
                                    .padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 10).fill(item.kind.color))
                                    .foregroundStyle(Theme.stickerInk)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(Theme.ui(14, weight: .semibold)).lineLimit(1)
                                    Text(item.targetDate!.formatted(.dateTime.weekday(.abbreviated).day().month())).font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private var inboxCard: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Inbox").font(Theme.display(22))
                    Spacer()
                    if inbox.loading { ProgressView() } else {
                        Button { Task { await inbox.refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain)
                    }
                }
                if let d = inbox.digest {
                    InboxSummary(digest: d, multi: inbox.accounts.count > 1)
                } else if let error = inbox.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12)).foregroundStyle(Theme.orange)
                } else {
                    EmptyHint(symbol: "envelope", text: "Pull down to refresh your inbox summary.")
                }
            }
        }
    }
}
