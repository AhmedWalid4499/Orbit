import SwiftUI
import SwiftData

/// Screenshot and test modes, and the made-up data they use.
@MainActor
enum Snapshot {
    /// True while rendering screenshots or running tests: no network calls, nothing written.
    nonisolated static let isActive = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] != nil
        || ProcessInfo.processInfo.environment["ORBIT_SYNC_TEST"] != nil
        || ProcessInfo.processInfo.environment["ORBIT_AI_TEST"] != nil
        || ProcessInfo.processInfo.environment["ORBIT_ASK_TEST"] != nil
        || ProcessInfo.processInfo.arguments.contains("-demo")
    /// Sample data only: no saved caches (chat, inbox, money coach, photo, name) are shown, so screenshots never
    /// carry personal data. On for demo screenshots and the iPhone `-demo` launch.
    nonisolated static let isDemo = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DEMO"] != nil
        || ProcessInfo.processInfo.arguments.contains("-demo")

    /// In demo mode, your own settings (name, what you call your AI, budget) are covered by sample ones for this run only.
    nonisolated static func applyDemoDefaults() {
        guard isDemo else { return }
        let sample: [String: Any] = ["userName": "Alex Morgan", "assistantName": "Ask", "monthlyBudget": 6000.0, "profileCard": "", "readingGoal": 24,
                                     "assistant.memory": #"["Vegetarian","Gym on Tuesdays and Thursdays","Prefers cafés in Zamalek","Sister Mona, birthday 12 March"]"#]
        // Keep launch options (-open, -moneyTab…) that are already in the argument domain.
        let args = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(sample.merging(args) { _, launch in launch }, forName: UserDefaults.argumentDomain)
    }

    /// Canned AI cards (morning brief, Your day) for screenshots, without calling the API.
    static func previewAI() {
        if let data = #"{"headline":"Busy morning, easy evening","summary":"You have a budget review at 7 PM and four tasks due, including the electricity bill. Your water streak is at 7 days.","focus":["Pay the electricity bill before noon","Reply to your landlord — it's a day overdue","Do 20 minutes on chapter 4 notes"],"heads_up":"You've used 89% of this month's budget with 10 days left.","day":"\#(DayKey.key(.now))"}"#.data(using: .utf8),
           let brief = try? JSONDecoder().decode(MorningBrief.self, from: data) {
            AIAssistant.shared.previewBrief(brief)
        }
        DaySummaryStore.shared.preview(DaySummary(line: "A calm afternoon, and you're ahead on tasks.", tiles: [
            .init(kind: "money", title: "Spent today", value: "EGP 350", detail: "Mostly Carrefour; month on pace"),
            .init(kind: "reading", title: "Reading", value: "42% · Atomic Habits", detail: "15 min today, 4-day streak"),
            .init(kind: "tasks", title: "Tasks", value: "3 of 5 done", detail: "Next: call the landlord"),
            .init(kind: "calendar", title: "Next up", value: "Gym · 7:00 PM", detail: "Then nothing else tonight"),
        ], nudge: "Twenty minutes of reading before the gym keeps your streak going."))
    }

    /// Sample data, in memory only.
    static func demoContainer() -> ModelContainer {
        let schema = OrbitSchema.schema
        let c = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let cats = [("Philosophy", 3, "brain.head.profile"), ("Favourites", 0, "heart.fill"), ("Business", 4, "briefcase.fill")]
        for (n, i, s) in cats { ctx.insert(BookCategory(name: n, colorIndex: i, symbol: s)) }
        let books: [(String, String, ReadingStatus, Int, [String], Double)] = [
            ("Meditations", "Marcus Aurelius", .read, 5, ["Philosophy", "Favourites"], 1),
            ("Atomic Habits", "James Clear", .reading, 0, ["Business"], 0.42),
            ("The Pragmatic Programmer", "David Thomas", .reading, 0, [], 0.7),
            ("Sapiens", "Yuval Noah Harari", .toRead, 0, [], 0),
            ("Deep Work", "Cal Newport", .read, 4, ["Business"], 1),
            ("The Alchemist", "Paulo Coelho", .read, 4, ["Favourites"], 1),
        ]
        for (t, a, st, r, cs, p) in books {
            let b = Book(title: t, author: a, status: st, source: ["kindle", "goodreads", "apple-books"][abs(t.count) % 3])
            b.sources = [b.source]
            b.rating = r; b.categories = cs; b.progress = p; b.pageCount = 300
            if st == .read { b.finishedAt = .now.adding(days: -20) }
            ctx.insert(b)
        }
        for (t, a, c, d, mail, orig) in [("Uber", -86.0, "Transport", 0, true, ""), ("Netflix", -620.0, "Subscriptions", 1, true, "12.99 USD"),
                                         ("Carrefour", -1250.0, "Food", 2, true, ""), ("Coffee", -95.0, "Food", 2, false, "")] {
            let x = Transaction(title: t, amount: a, category: c, date: .now.adding(days: -d))
            if mail { x.source = "gmail:alex@example.com"; x.sourceID = "demo\(d)" }
            if !orig.isEmpty { x.originalAmount = 12.99; x.originalCurrency = "USD"; x.isRecurring = true }
            ctx.insert(x)
        }
        // A believable week from today, so Today, Calendar and the planner have something to show.
        for (t, day, h, m, len, area) in [("Team standup", 0, 10, 0, 30, Area.work), ("Lunch with Omar", 0, 13, 30, 60, .social), ("Gym", 0, 19, 0, 75, .health),
                                          ("Dentist", 1, 15, 0, 45, .health), ("Design review", 1, 11, 0, 60, .work), ("Dinner with Sara", 2, 20, 0, 120, .social),
                                          ("Team sync", 3, 10, 0, 60, .work), ("Yoga", 4, 8, 0, 60, .health), ("Movie night", 5, 21, 0, 150, .social)] {
            let start = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date.now.startOfDay.adding(days: day))!
            ctx.insert(EventItem(title: t, start: start, end: start.adding(minutes: len), area: area))
        }
        ctx.insert(TaskItem(title: "Pay Electricity — 450 EGP", area: .money, due: Date.now.startOfDay.adding(days: 4), priority: 2))
        ctx.insert(TaskItem(title: "Send the project update", area: .work, due: Date.now.startOfDay, priority: 3))
        ctx.insert(TaskItem(title: "Book a table for Saturday", area: .personal, due: Date.now.startOfDay, priority: 1))
        ctx.insert(TaskItem(title: "Buy a birthday gift for Sara", area: .personal, due: Date.now.startOfDay.adding(days: 1), priority: 2))
        ctx.insert(TaskItem(title: "Renew passport", area: .personal, due: Date.now.startOfDay.adding(days: 9), priority: 1))
        let finished = TaskItem(title: "Reply to the landlord", area: .personal, due: Date.now.startOfDay, priority: 2)
        finished.isDone = true; finished.completedAt = .now.adding(minutes: -90)
        ctx.insert(finished)
        ctx.insert(BucketItem(title: "See the northern lights in Norway", kind: .travel, notes: "Tromsø in February", targetDate: Date.now.startOfDay.adding(days: 23), excitement: 3))
        ctx.insert(BucketItem(title: "Learn to surf", kind: .adventure, excitement: 2))
        for (name, cat, addr, lat, lon, note, been) in [
            ("Zooba", PlaceCategory.food, "26 Taha Hussein, Zamalek", 30.0611, 31.2194, "Get the koshary and the taameya sandwich", false),
            ("Grand Egyptian Museum", .museum, "Kafr Nassar, Giza", 29.9947, 31.1186, "Book the Tutankhamun galleries", false),
            ("Café Riche", .cafe, "Talaat Harb, Downtown", 30.0476, 31.2393, "", true),
            ("Cairo Festival City Mall", .shop, "New Cairo", 30.0288, 31.4082, "", false),
        ] {
            let p = BucketItem(title: name, kind: .place, notes: note)
            p.placeCategory = cat; p.address = addr; p.latitude = lat; p.longitude = lon
            if been { p.isDone = true; p.doneAt = .now.adding(days: -12) }
            ctx.insert(p)
        }
        ctx.insert(BucketItem(title: "Read 50 books in a year", kind: .learn, excitement: 2))
        ctx.insert(BucketItem(title: "Concert with friends", kind: .people, targetDate: Date.now.startOfDay.adding(days: 6), excitement: 3))
        let done = BucketItem(title: "Climb Mount Sinai at sunrise", kind: .adventure, excitement: 3)
        done.isDone = true; done.doneAt = .now.adding(days: -40)
        ctx.insert(done)
        // Two weeks of moods, reading sessions and a few highlights for the review and insights screens.
        let gym = Habit(name: "Workout", symbol: "figure.run", area: .health, targetPerWeek: 4)
        for d in 1...16 {
            let day = Date.now.startOfDay.adding(days: -d)
            let worked = d % 2 == 0
            if worked { gym.doneDays.append(DayKey.key(day)) }
            let n = Note(title: "Journal", body: "Day \(d)", isJournal: true, date: day.adding(minutes: 21 * 60))
            n.mood = worked ? [4, 5, 4][d % 3] : [3, 2, 3][d % 3]
            ctx.insert(n)
            if d % 3 == 0 {
                let s = ReadingSession(); s.bookTitle = "Atomic Habits"; s.start = day.adding(minutes: 22 * 60); s.end = s.start.adding(minutes: 25 + d)
                ctx.insert(s)
            }
        }
        ctx.insert(gym)
        for (name, symbol, doneToday, streak) in [("Drink water", "drop.fill", true, 9), ("Read 20 minutes", "book.fill", false, 4), ("Meditate", "brain.head.profile", true, 3)] {
            let h = Habit(name: name, symbol: symbol, area: .health, targetPerWeek: 7)
            for d in (doneToday ? 0 : 1)...streak { h.doneDays.append(DayKey.key(Date.now.startOfDay.adding(days: -d))) }
            ctx.insert(h)
        }
        for (t, b) in [("You do not rise to the level of your goals. You fall to the level of your systems.", "Atomic Habits"),
                       ("Every action you take is a vote for the type of person you wish to become.", "Atomic Habits"),
                       ("You have power over your mind, not outside events. Realize this, and you will find strength.", "Meditations")] {
            let h = Highlight(bookTitle: b, author: b == "Meditations" ? "Marcus Aurelius" : "James Clear", text: t, source: "kindle-clippings")
            h.location = "Location \(t.count * 7)"
            ctx.insert(h)
        }
        let j = Note(title: Date.now.formatted(date: .complete, time: .omitted), isJournal: true)
        j.mood = 4
        j.chat = JournalChat(system: "", turns: [
            JournalTurn(role: "user", text: "I just opened today's journal.", hidden: true),
            JournalTurn(role: "assistant", text: "Hey! How are you feeling today, honestly?"),
            JournalTurn(role: "user", text: "Pretty good, a bit tired. Got a lot done at work."),
            JournalTurn(role: "assistant", text: "Tired-but-productive is a good kind of tired. What was the thing you're most glad you finished?"),
        ])
        ctx.insert(j)

        let today = Date.now.startOfDay
        for (n, amt, cyc, days) in [("Netflix", 240.0, BillingCycle.monthly, 5), ("Spotify", 100.0, .monthly, 12), ("iCloud+", 50.0, .monthly, 20),
                                    ("Gym membership", 1200.0, .monthly, 2), ("Adobe Creative Cloud", 9000.0, .yearly, 64)] {
            let s = Subscription(name: n, amount: amt, cycle: cyc)
            s.nextDate = today.adding(days: days); s.lastCharged = today.adding(days: days - 30)
            if n == "Netflix" { s.previousAmount = 200; s.priceChangedAt = today.adding(days: -25) }
            ctx.insert(s)
        }
        let trial = Subscription(name: "Duolingo Max", amount: 450)
        trial.status = "trial"; trial.trialEnds = today.adding(days: 3)
        ctx.insert(trial)

        for (t, k, days, issuer) in [("Egyptian passport", DocKind.passport, 150, "Passport Office"), ("Driving licence", .license, 410, "Traffic Dept."),
                                     ("Car insurance", .insurance, 21, "Allianz"), ("MacBook Pro", .warranty, 290, "Apple"),
                                     ("National ID", .id, 1300, "Civil Registry")] {
            let d = DocItem(title: t, kind: k, expires: today.adding(days: days))
            d.issuer = issuer; d.number = "4821"
            ctx.insert(d)
        }

        // Bills (one already paid by a bank text) and goals that fill in from the data above.
        for (dBack, t, a, c) in [(3, "Vodafone bill", -350.0, "Bills"), (5, "Talabat", -420.0, "Food"), (9, "Carrefour", -1640.0, "Food"),
                                 (10, "Uber", -240.0, "Transport"), (11, "Zara", -1900.0, "Shopping"), (12, "Talabat", -380.0, "Food")] {
            let x = Transaction(title: t, amount: a, category: c, date: today.adding(days: -dBack).adding(minutes: 13 * 60))
            x.source = "sms"
            x.account = ["Zara", "Uber"].contains(t) ? "demo-nbe" : "demo-cib"
            ctx.insert(x)
        }
        let pay = Transaction(title: "Salary", amount: 18000, category: "Income", date: today.startOfMonth.adding(minutes: 10 * 60)); pay.source = "sms"
        pay.account = "demo-nbe"
        ctx.insert(pay)
        // Two banks, as if learnt from their texts.
        for (id, name, last4, kind, color, bal) in [("demo-cib", "CIB", "1234", "card", 0, 45210.5), ("demo-nbe", "NBE", "5678", "account", 2, 8400.0),
                                                    ("demo-vf", "Vodafone Cash", "", "wallet", 3, 0.0)] {
            let acct = BankAccount(name: name, last4: last4, kind: kind)
            acct.uuid = id; acct.colorIndex = color
            if bal > 0 { acct.balance = bal; acct.balanceAt = .now.adding(minutes: -95) }
            ctx.insert(acct)
        }
        let dom = Calendar.current.component(.day, from: today)
        func day(_ ahead: Int) -> Int { Calendar.current.component(.day, from: today.adding(days: ahead)) }
        for (n, amt, d, match) in [("Rent", 8000.0, day(4), "rent"), ("Internet", 650.0, day(9), "we, telecom egypt"),
                                   ("Vodafone", 350.0, max(1, dom - 2), "vodafone"), ("Electricity", 900.0, day(18), "electricity")] {
            let b = Bill(name: n, amount: amt, dueDay: d); b.match = match
            ctx.insert(b)
        }
        let readGoal = Goal(title: "Read 24 books this year", kind: .books, target: 24); readGoal.start = today.startOfYear
        readGoal.deadline = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: today), month: 12, day: 31))
        ctx.insert(readGoal)
        let save = Goal(title: "Save for a new laptop", kind: .save, target: 40000); save.start = today.startOfMonth; save.deadline = today.adding(days: 120)
        ctx.insert(save)
        let norway = Goal(title: "Northern lights in Norway", kind: .steps)
        norway.steps = ["Pick dates in February", "Book flights to Tromsø", "Find a cabin", "Buy thermal layers"]
        norway.stepsDone = ["Pick dates in February"]; norway.target = 4; norway.deadline = today.adding(days: 23)
        ctx.insert(norway)

        // Focus blocks this week, tomorrow's plan, and a trip with bookings.
        for (dayBack, mins) in [(0, 25), (0, 50), (1, 25), (2, 25), (3, 50)] {
            let f = FocusSession(); f.start = today.adding(days: -dayBack).adding(minutes: 9 * 60 + dayBack * 30); f.plannedMinutes = mins
            f.end = f.plannedEnd; f.taskTitle = "Chapter 4 notes"
            ctx.insert(f)
        }
        let plan = DayPlan(day: DayKey.key(today))
        plan.top = ["Finish the budget review deck", "Call the landlord about the lease", "30 minutes of Spanish"]
        plan.taskUUIDs = ["", "", ""]; plan.note = "Bring the charger"
        ctx.insert(plan)
        let trip = Trip(title: "Lisbon long weekend", destination: "Lisbon")
        trip.uuid = "demo-trip"; trip.start = today.adding(days: 19); trip.end = today.adding(days: 23); trip.budget = 45000
        trip.packing = ["Passport", "Phone charger", "Power adapter", "Sunglasses", "Light jacket", "Walking shoes", "3 T-shirts", "Camera"]
        trip.packed = ["Passport", "Power adapter", "Camera"]
        ctx.insert(trip)
        for (t, k, prov, ref, dayIn, hour, amt) in [("Cairo → Lisbon, MS777", BookingKind.flight, "EgyptAir", "K7XQ2P", 19, 9, 18500.0),
                                                     ("Hotel Avenida Palace", .hotel, "Booking.com", "4471902", 19, 15, 16800.0),
                                                     ("Lisbon → Cairo, MS778", .flight, "EgyptAir", "K7XQ2P", 23, 18, 0.0)] {
            let b = Booking(title: t, kind: k); b.tripUUID = "demo-trip"; b.provider = prov; b.confirmation = ref
            b.start = today.adding(days: dayIn).adding(minutes: hour * 60); b.amount = amt; b.source = "email"
            ctx.insert(b)
        }
        let loose = Booking(title: "Sintra palace tour", kind: .activity); loose.location = "Sintra"; loose.source = "email"
        loose.start = today.adding(days: 40).adding(minutes: 10 * 60)
        ctx.insert(loose)

        return c
    }
}

/// Test hook: `ORBIT_ASK_TEST="question"` asks the assistant once with sample data, prints the reply, the tool
/// activity and any error, and quits. The chat isn't saved.
@MainActor
enum AskTest {
    static func runIfRequested(apple: AppleSync) {
        guard let q = ProcessInfo.processInfo.environment["ORBIT_ASK_TEST"] else { return }
        Task {
            let container = Snapshot.demoContainer()
            let store = AssistantStore.shared
            store.newChat()
            await store.send(q, context: container.mainContext, apple: apple)
            for i in store.items { print("ASK [\(i.role.rawValue)] \(i.text)") }
            print("ASK blocks: " + store.debugBlockTypes.joined(separator: ", "))
            print("ASK error: \(store.error ?? "-")")
            fflush(stdout)
            withExtendedLifetime(container) { exit(0) }
        }
    }
}
