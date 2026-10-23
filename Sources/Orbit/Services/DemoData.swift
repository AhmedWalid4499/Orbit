import SwiftUI
import SwiftData

/// Screenshot and test modes, and the made-up data they use.
@MainActor
enum Snapshot {
    /// True while rendering screenshots or running tests: no network calls, nothing written.
    nonisolated static let isActive = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] != nil
        || ProcessInfo.processInfo.environment["ORBIT_SYNC_TEST"] != nil
        || ProcessInfo.processInfo.environment["ORBIT_AI_TEST"] != nil
        || ProcessInfo.processInfo.arguments.contains("-demo")

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
            if mail { x.source = "gmail:ahmedwalid4499@gmail.com"; x.sourceID = "demo\(d)" }
            if !orig.isEmpty { x.originalAmount = 12.99; x.originalCurrency = "USD"; x.isRecurring = true }
            ctx.insert(x)
        }
        for (i, (t, h, len)) in [("Team sync", 10, 60), ("Gym", 18, 90), ("Dinner with Sara", 20, 120), ("Dentist", 15, 45)].enumerated() {
            let start = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date.now.startOfWeek.adding(days: i + 1))!
            ctx.insert(EventItem(title: t, start: start, end: start.adding(minutes: len), area: [.work, .health, .social, .health][i]))
        }
        ctx.insert(TaskItem(title: "Pay Electricity — 450 EGP", area: .money, due: Date.now.startOfDay.adding(days: 4), priority: 2))
        ctx.insert(BucketItem(title: "See the northern lights in Norway", kind: .travel, notes: "Tromsø in February", targetDate: Date.now.startOfDay.adding(days: 23), excitement: 3))
        ctx.insert(BucketItem(title: "Learn to surf", kind: .adventure, excitement: 2))
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
