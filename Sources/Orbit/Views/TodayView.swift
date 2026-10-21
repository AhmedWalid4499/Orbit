import SwiftUI
import SwiftData

/// One entry on a calendar, either from Orbit or from Apple Calendar.
struct CalEntry: Identifiable, Hashable {
    enum Source: Hashable { case local(PersistentIdentifier), apple(calendar: String), google(calendar: String) }
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let area: Area?
    let tint: Color
    let source: Source

    /// Name of the Apple or Google calendar it came from (nil for Orbit's own events).
    var calendarName: String? {
        switch source {
        case .apple(let c): c
        case .google(let c): c
        case .local: nil
        }
    }

    static func merge(local: [EventItem], apple: [AppleEvent], google: [GoogleEvent] = []) -> [CalEntry] {
        let mine = local.map {
            CalEntry(id: "\($0.persistentModelID.hashValue)", title: $0.title, start: $0.start, end: $0.end,
                     isAllDay: false, area: $0.area, tint: $0.area.color, source: .local($0.persistentModelID))
        }
        let theirs = apple.map {
            CalEntry(id: "apple-\($0.id)-\($0.start.timeIntervalSince1970)", title: $0.title, start: $0.start, end: $0.end,
                     isAllDay: $0.isAllDay, area: nil, tint: $0.color, source: .apple(calendar: $0.calendarName))
        }
        // Skip Google events that macOS Calendar already shows (same title and start), e.g. if the account is also in Internet Accounts.
        let appleKeys = Set(apple.map { "\($0.title.lowercased())|\(Int($0.start.timeIntervalSince1970))" })
        let fromGoogle = google.filter { !appleKeys.contains("\($0.title.lowercased())|\(Int($0.start.timeIntervalSince1970))") }.map {
            CalEntry(id: "google-\($0.id)-\($0.start.timeIntervalSince1970)", title: $0.title, start: $0.start, end: $0.end,
                     isAllDay: $0.isAllDay, area: nil, tint: $0.color, source: .google(calendar: $0.calendarName))
        }
        return (mine + theirs + fromGoogle).sorted { $0.start < $1.start }
    }
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL

    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \EventItem.start) private var events: [EventItem]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]
    @Query(filter: #Predicate<BucketItem> { !$0.isDone }) private var dreams: [BucketItem]

    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var gh = GitHubStore.shared
    @ObservedObject private var google = GoogleCalendarStore.shared
    @ObservedObject private var ai = AIAssistant.shared

    @AppStorage("monthlyBudget") private var monthlyBudget = 2000.0
    @AppStorage("userName") private var userName = NSFullUserName()
    @AppStorage("readingGoal") private var readingGoal = 24

    @State private var capture = ""
    @State private var capturing = false
    @State private var captureResult: String?
    @State private var newTask = ""

    private var today: Date { .now.startOfDay }

    private var openToday: [TaskItem] {
        tasks.filter { !$0.isDone && ($0.due.map { $0 < today.adding(days: 1) } ?? false) }
            .sorted { ($0.priority, $1.due ?? .now) > ($1.priority, $0.due ?? .now) }
    }

    private var todayEntries: [CalEntry] {
        _ = apple.revision
        let local = events.filter { $0.start.isSameDay(as: today) }
        return CalEntry.merge(local: local, apple: apple.events(from: today, to: today.adding(days: 1)), google: GoogleCalendarStore.shared.events(from: today, to: today.adding(days: 1)))
    }

    private var tomorrowEntries: [CalEntry] {
        _ = apple.revision
        let t = today.adding(days: 1)
        return CalEntry.merge(local: events.filter { $0.start.isSameDay(as: t) }, apple: apple.events(from: t, to: t.adding(days: 1)), google: GoogleCalendarStore.shared.events(from: t, to: t.adding(days: 1)))
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
        VStack(alignment: .leading, spacing: 14) {
            header
            statRow
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    BriefCard()
                    agendaCard.frame(minHeight: 150, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 14) {
                    tasksCard
                    habitsStrip
                    lookingForwardCard.frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 14) {
                    inboxCard.frame(maxHeight: .infinity)
                    readingCard
                    HStack(spacing: 14) {
                        moneyMini
                        journalMini
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 390)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
        .padding(.bottom, 22)
        .task {
            if gh.isConnected, gh.lastRefresh == nil { await gh.refresh() }
            await inbox.refreshIfDue(context: context)
        }
    }

    // MARK: Header + capture

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Theme.display(32))
                Text(headline).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 16)
            ClockWeather()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: capturing ? "hourglass" : (ai.smartCaptureActive ? "sparkles" : "plus"))
                        .foregroundStyle(Theme.inkSecondary)
                    TextField(ai.smartCaptureActive ? "Add anything — “gym tomorrow 7am, pay rent friday, $12 lunch”" : "Add a task, event, expense or note…",
                              text: $capture)
                        .textFieldStyle(.plain)
                        .font(Theme.ui(14))
                        .disabled(capturing)
                        .onSubmit(runCapture)
                    Text("↩").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minWidth: 280, maxWidth: 440)
                .background(Capsule().fill(Theme.card))
                if let captureResult {
                    Text(captureResult).font(Theme.ui(11, weight: .medium)).foregroundStyle(Theme.good).lineLimit(1)
                        .transition(.opacity)
                }
            }
        }
    }

    private var headline: String {
        var parts = ["\(greeting)."]
        if let next = todayEntries.first(where: { $0.start > .now && !$0.isAllDay }) {
            parts.append("Next up: \(next.title) \(next.start.formatted(.relative(presentation: .named))).")
        } else {
            parts.append("Nothing else on the calendar today.")
        }
        let overdue = tasks.filter(\.isOverdue).count
        if overdue > 0 { parts.append("\(overdue) overdue.") }
        return parts.joined(separator: " ")
    }

    private func runCapture() {
        let raw = capture.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !capturing else { return }
        capturing = true
        Task {
            let summary = await CaptureEngine.capture(raw, context: context)
            capture = ""
            capturing = false
            withAnimation { captureResult = "Saved — \(summary)" }
            try? await Task.sleep(for: .seconds(4))
            withAnimation { captureResult = nil }
        }
    }

    // MARK: Stats

    private var statRow: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(openToday.count)", label: "Due today", symbol: "sun.max.fill", color: Theme.peach) { state.tab = .tasks }
            StatTile(value: "\(habits.filter { $0.isDone(on: today) }.count)/\(habits.count)", label: "Habits today",
                     symbol: "flame.fill", color: Theme.lime) { state.tab = .habits }
            StatTile(value: Fmt.money(spentThisMonth), label: "Spent this month", symbol: "creditcard.fill", color: Theme.cyan) { state.tab = .money }
            StatTile(value: inbox.isConnected ? "\(inbox.digest?.needsReply.count ?? 0)" : "—", label: "Emails to answer",
                     symbol: "envelope.fill", color: Theme.pink) {}
            StatTile(value: "\(readThisYear)/\(readingGoal)", label: "Books this year", symbol: "books.vertical.fill", color: Theme.purple) { state.tab = .reading }
            if gh.isConnected {
                StatTile(value: "\(gh.pullRequests.count)", label: "Open PRs", symbol: "arrow.triangle.pull", color: Theme.orange) { state.tab = .github }
            } else {
                StatTile(value: "\(tasks.filter { $0.isDone && ($0.completedAt ?? .distantPast) >= Date.now.startOfWeek }.count)",
                         label: "Done this week", symbol: "checkmark", color: Theme.orange) { state.tab = .tasks }
            }
        }
    }

    // MARK: Column 1

    private var agendaCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Agenda", trailing: "Calendar") { state.tab = .calendar }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if todayEntries.isEmpty {
                            EmptyHint(symbol: "sun.max", text: apple.calendarEnabled ? "Nothing scheduled today." : "Nothing scheduled. Connect Apple Calendar in Settings.")
                        }
                        ForEach(todayEntries) { AgendaRow(entry: $0) }
                        if !tomorrowEntries.isEmpty {
                            Text("Tomorrow").font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.inkMuted).padding(.top, 6)
                            ForEach(tomorrowEntries.prefix(4)) { AgendaRow(entry: $0, dim: true) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    // MARK: Column 2

    private var tasksCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Due today", trailing: "All tasks") { state.tab = .tasks }
                HStack(spacing: 8) {
                    Image(systemName: "plus").foregroundStyle(Theme.inkMuted)
                    TextField("Add a task for today", text: $newTask)
                        .textFieldStyle(.plain).font(Theme.ui(13))
                        .onSubmit {
                            var p = QuickParser.parse(newTask)
                            guard !p.title.isEmpty else { return }
                            if p.kind == .event || p.kind == .task { p.kind = .task; if p.date == nil { p.date = today } }
                            p.save(in: context)
                            newTask = ""
                        }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
                ScrollView {
                    VStack(spacing: 6) {
                        let reminders = apple.reminders.filter { ($0.due ?? .distantFuture) < today.adding(days: 1) }
                        if openToday.isEmpty && reminders.isEmpty {
                            EmptyHint(symbol: "checkmark.seal", text: "Nothing due. Nice.")
                        }
                        ForEach(openToday) { TaskRow(task: $0, showDue: $0.isOverdue) }
                        ForEach(reminders) { ReminderRow(reminder: $0) }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 190)
                .fixedSize(horizontal: false, vertical: openToday.count + apple.reminders.count < 4)
            }
        }
    }

    /// Dated bucket-list items coming up, or a nudge to dream if there are none.
    private var lookingForwardCard: some View {
        let upcoming = dreams.filter { ($0.targetDate ?? .distantPast) >= today }.sorted { $0.targetDate! < $1.targetDate! }
        let someday = dreams.filter { $0.targetDate == nil }.sorted { $0.excitement > $1.excitement }
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Looking forward to", trailing: "Bucket list") { state.tab = .bucket }
                if dreams.isEmpty {
                    EmptyHint(symbol: "mountain.2", text: "Add things you want to do in life to your bucket list.")
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(upcoming.prefix(4)) { item in
                            let days = Calendar.current.dateComponents([.day], from: today, to: item.targetDate!.startOfDay).day ?? 0
                            HStack(spacing: 12) {
                                Text(days == 0 ? "🎉" : "\(days)d").font(Theme.display(17)).frame(width: 46)
                                    .padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 10).fill(item.kind.color))
                                    .foregroundStyle(Theme.stickerInk)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(Theme.ui(13, weight: .semibold)).lineLimit(1)
                                    Text(item.targetDate!.formatted(.dateTime.weekday(.abbreviated).day().month())).font(Theme.ui(10)).foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                            }
                        }
                        ForEach(someday.prefix(max(0, 3 - upcoming.count))) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.kind.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                                    .frame(width: 46, height: 30).background(RoundedRectangle(cornerRadius: 10).fill(item.kind.color.opacity(0.7)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(Theme.ui(13, weight: .semibold)).lineLimit(1)
                                    Text("Someday").font(Theme.ui(10)).foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
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
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(habits) { h in
                                let done = h.isDone(on: today)
                                Button { withAnimation(.snappy) { h.toggle(today) } } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: done ? "checkmark" : h.symbol).font(.system(size: 11, weight: .bold))
                                        Text(h.name).font(Theme.ui(12, weight: .semibold)).lineLimit(1)
                                        if h.currentStreak > 1 { Text("\(h.currentStreak)🔥").font(Theme.ui(11)) }
                                    }
                                    .foregroundStyle(done ? Theme.stickerInk : Theme.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(done ? h.area.color : Theme.canvas))
                                    .overlay(Capsule().strokeBorder(h.area.color, lineWidth: done ? 0 : 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    // MARK: Column 3

    private var inboxCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Inbox").font(Theme.display(22))
                    if inbox.accounts.count > 1 {
                        Text("\(inbox.accounts.count) accounts").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    if inbox.loading { ProgressView().controlSize(.small) }
                    else if inbox.isConnected {
                        Button { Task { await inbox.refresh() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)) }
                            .buttonStyle(.plain).help("Refresh inbox summary")
                    }
                }
                if !inbox.isConnected {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect Gmail and \(AssistantName.current) sums up both inboxes for you: what needs a reply, what matters, what can wait.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                        SettingsLink { Text("Connect Gmail") }.buttonStyle(SoftButtonStyle())
                    }
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if let error = inbox.error {
                                Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(11)).foregroundStyle(Theme.orange)
                            }
                            if let d = inbox.digest {
                                Text(d.overview).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                                if !d.needsReply.isEmpty {
                                    Text("Needs a reply").font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.inkMuted).padding(.top, 2)
                                    ForEach(d.needsReply) { MailRow(item: $0, tint: Theme.pink, multi: inbox.accounts.count > 1) }
                                }
                                if !d.important.isEmpty {
                                    Text("Worth knowing").font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.inkMuted).padding(.top, 2)
                                    ForEach(d.important) { MailRow(item: $0, tint: Theme.cyan, multi: inbox.accounts.count > 1) }
                                }
                                Text("\(d.scanned) emails scanned · \(d.otherCount) routine · updated \(d.generatedAt.formatted(.relative(presentation: .named)))")
                                    .font(Theme.ui(10)).foregroundStyle(Theme.inkMuted).padding(.top, 2)
                            } else if !inbox.loading {
                                EmptyHint(symbol: "envelope", text: ai.hasKey ? "Refresh to summarise your inbox." : "Add your Anthropic API key to get summaries.")
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    private var readingCard: some View {
        let current = books.first { $0.status == .reading }
        return Button { state.tab = .reading } label: {
            HStack(spacing: 12) {
                if let current {
                    BookCover(book: current).frame(width: 40, height: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reading").font(Theme.ui(10, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                        Text(current.title).font(Theme.ui(13, weight: .semibold)).lineLimit(1)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.line)
                                Capsule().fill(Theme.ink).frame(width: max(4, g.size.width * current.progress))
                            }
                        }
                        .frame(height: 5)
                        Text("\(Int(current.progress * 100))% · \(readThisYear) of \(readingGoal) books this year")
                            .font(Theme.ui(10)).foregroundStyle(Theme.inkSecondary)
                    }
                } else {
                    Image(systemName: "books.vertical.fill").frame(width: 40, height: 40).background(Circle().fill(Theme.purple))
                        .foregroundStyle(Theme.stickerInk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(readThisYear) of \(readingGoal) books this year").font(Theme.ui(13, weight: .semibold))
                        Text("Nothing on the go. Pick your next read.").font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary)
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

    private var moneyMini: some View {
        let ratio = monthlyBudget > 0 ? min(spentThisMonth / monthlyBudget, 1) : 0
        return Button { state.tab = .money } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Left to spend").font(Theme.ui(11, weight: .semibold))
                Text(Fmt.money(max(monthlyBudget - spentThisMonth, 0))).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.6)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.12))
                        Capsule().fill(Color(hex: 0x111111)).frame(width: g.size.width * ratio)
                    }
                }
                .frame(height: 6)
                Text("of \(Fmt.money(monthlyBudget))").font(Theme.ui(10)).opacity(0.7)
            }
            .foregroundStyle(Theme.stickerInk)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.lime))
        }
        .buttonStyle(.plain)
    }

    private var journalMini: some View {
        let entry = notes.first { $0.isJournal && $0.createdAt.isToday }
        return VStack(alignment: .leading, spacing: 8) {
            Text("How's today?").font(Theme.ui(11, weight: .semibold))
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { m in
                    Button { setMood(m) } label: {
                        Text(Mood.faces[m]).font(.system(size: 17))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(entry?.mood == m ? Theme.lime : .clear))
                            .opacity(entry == nil || entry?.mood == 0 || entry?.mood == m ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .help(Mood.words[m])
                }
            }
            Button {
                state.openTodayJournal = true
                state.tab = .notes
            } label: {
                Label(entry?.chat == nil ? "Check in" : "Journal", systemImage: "bubble.left.and.text.bubble.right")
                    .font(Theme.ui(11, weight: .semibold))
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
}

private struct AgendaRow: View {
    let entry: CalEntry
    var dim = false

    var body: some View {
        let past = entry.end < .now
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.isAllDay ? "All day" : Fmt.time(entry.start)).font(Theme.ui(12, weight: .semibold))
                if !entry.isAllDay { Text(Fmt.time(entry.end)).font(Theme.ui(10)).foregroundStyle(Theme.inkMuted) }
            }
            .frame(width: 60, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(entry.tint).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(Theme.ui(13, weight: .medium)).lineLimit(1)
                if let cal = entry.calendarName { Text(cal).font(Theme.ui(10)).foregroundStyle(Theme.inkMuted) }
            }
            Spacer()
            if let area = entry.area { AreaPill(area: area, compact: true) }
            if entry.start <= .now && entry.end > .now {
                Text("Now").font(Theme.ui(10, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.critical))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
        .opacity(past || dim ? 0.5 : 1)
    }
}

private struct MailRow: View {
    let item: InboxDigest.Item
    let tint: Color
    let multi: Bool
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        Button { if let u = InboxStore.link(item) { openURL(u) } } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(tint).frame(width: 8, height: 8).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.from).font(Theme.ui(12, weight: .semibold)).lineLimit(1)
                        if multi {
                            Text(item.account.split(separator: "@").first.map(String.init) ?? item.account)
                                .font(Theme.ui(9, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().strokeBorder(Theme.line))
                        }
                    }
                    Text(item.note).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkMuted).opacity(hovering ? 1 : 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Theme.cardHover : Theme.canvas))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.subject)
    }
}

/// Small colourful stat tile in the Today row; tapping jumps to that area.
private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(Theme.display(24)).minimumScaleFactor(0.5).lineLimit(1)
                    Text(label).font(Theme.ui(11, weight: .semibold)).lineLimit(1).opacity(0.8)
                }
                Spacer(minLength: 2)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.5)))
            }
            .foregroundStyle(Theme.stickerInk)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.spring(response: 0.25), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Shared rows

struct TaskRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var task: TaskItem
    var showDue = true
    var onSelect: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    if task.isDone { task.isDone = false; task.completedAt = nil } else { task.complete(in: context) }
                }
            } label: { CheckCircle(isOn: task.isDone) }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(Theme.ui(14, weight: .medium))
                    .strikethrough(task.isDone, color: Theme.inkMuted)
                    .foregroundStyle(task.isDone ? Theme.inkMuted : Theme.ink)
                HStack(spacing: 8) {
                    if showDue, let due = task.due {
                        Label(Fmt.relativeDay(due), systemImage: "calendar")
                            .foregroundStyle(task.isOverdue ? Theme.critical : Theme.inkMuted)
                    }
                    if task.recurrence != .none {
                        Label(task.recurrence.title, systemImage: "repeat").foregroundStyle(Theme.inkMuted)
                    }
                }
                .font(Theme.ui(11))
                .labelStyle(.titleAndIcon)
            }
            Spacer()
            if task.priority > 0 {
                Text(String(repeating: "!", count: task.priority))
                    .font(Theme.ui(13, weight: .heavy))
                    .foregroundStyle(task.priority == 3 ? Theme.critical : Theme.inkSecondary)
            }
            AreaPill(area: task.area, compact: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
        .contextMenu {
            Menu("Area") { ForEach(Area.allCases) { a in Button(a.title) { task.area = a } } }
            Menu("Priority") {
                ForEach(0..<4) { p in Button(p == 0 ? "None" : String(repeating: "!", count: p)) { task.priority = p } }
            }
            Menu("Due") {
                Button("Today") { task.due = .now.startOfDay }
                Button("Tomorrow") { task.due = .now.startOfDay.adding(days: 1) }
                Button("Next week") { task.due = .now.startOfDay.adding(days: 7) }
                Button("No date") { task.due = nil }
            }
            Divider()
            Button("Delete", role: .destructive) { context.delete(task) }
        }
    }
}

struct ReminderRow: View {
    @EnvironmentObject private var apple: AppleSync
    let reminder: AppleReminder

    var body: some View {
        HStack(spacing: 12) {
            Button { withAnimation { apple.complete(reminder) } } label: { CheckCircle(isOn: false, tint: reminder.color) }
                .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title).font(Theme.ui(14, weight: .medium))
                HStack(spacing: 6) {
                    Image(systemName: "applelogo")
                    Text(reminder.listName)
                    if let due = reminder.due { Text("· \(Fmt.relativeDay(due))") }
                }
                .font(Theme.ui(11))
                .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Circle().fill(reminder.color).frame(width: 8, height: 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
    }
}

// MARK: - Claude morning brief

private struct BriefCard: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var ai = AIAssistant.shared

    private let ink = Color(hex: 0xF4F4F5)
    private let bg = Color(hex: 0x141416)

    var body: some View {
        Group {
            if !ai.hasKey {
                setupCard
            } else if ai.morningBriefEnabled {
                briefCard
            }
        }
        // Generates once per day, and right after a key is added or the brief is switched on.
        .task(id: "\(DayKey.key(.now))-\(ai.hasKey)-\(ai.morningBriefEnabled)") {
            await ai.refreshBrief(context: context, apple: apple)
        }
    }

    private var setupCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40).background(Circle().fill(Theme.lime)).foregroundStyle(Theme.stickerInk)
            VStack(alignment: .leading, spacing: 2) {
                Text("Get a morning brief from \(AssistantName.current)").font(Theme.ui(15, weight: .semibold))
                Text("Add your Anthropic API key in Settings › AI to turn on the daily brief and smart capture.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            SettingsLink { Text("Set up") }.buttonStyle(SoftButtonStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private var briefCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.lime)
                Text("Morning brief").font(Theme.ui(12, weight: .semibold)).opacity(0.7)
                Spacer()
                if let b = ai.brief, ai.hasTodaysBrief, ai.briefState != .loading {
                    Text("Updated \(Fmt.time(b.generatedAt))").font(Theme.ui(11)).opacity(0.5)
                }
                Button {
                    Task { await ai.refreshBrief(context: context, apple: apple, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .disabled(ai.briefState == .loading)
                .help("Regenerate")
            }

            switch ai.briefState {
            case .loading where !ai.hasTodaysBrief:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(ink)
                    Text("\(AssistantName.current) is reading your day…").font(Theme.display(20, weight: .regular))
                }
                .padding(.vertical, 6)
            case .failed(let message) where !ai.hasTodaysBrief:
                Label(message, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(13))
            default:
                if let b = ai.brief, ai.hasTodaysBrief { content(b) }
            }
            if case .loading = ai.briefState, ai.hasTodaysBrief {
                Text("Refreshing…").font(Theme.ui(11)).opacity(0.5)
            }
        }
        .foregroundStyle(ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(bg))
        .animation(.easeOut(duration: 0.2), value: ai.brief)
    }

    private func content(_ b: MorningBrief) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(b.headline).font(Theme.display(21)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(b.summary).font(Theme.ui(13)).lineSpacing(2).opacity(0.85).lineLimit(3).help(b.summary)
            if !b.focus.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(b.focus.prefix(3).enumerated()), id: \.offset) { i, item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(Theme.display(14)).foregroundStyle(Theme.stickerInk)
                                .frame(width: 22, height: 22).background(Circle().fill([Theme.lime, Theme.pink, Theme.cyan][i % 3]))
                            Text(item).font(Theme.ui(13, weight: .medium)).lineLimit(2)
                        }
                    }
                }
            }
            if !b.heads_up.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.orange)
                    Text(b.heads_up).font(Theme.ui(13)).opacity(0.85)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
            }
        }
    }
}
