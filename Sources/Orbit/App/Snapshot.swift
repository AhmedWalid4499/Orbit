import SwiftUI
import SwiftData
import AppKit

/// Debug helper: `ORBIT_SNAPSHOT_DIR=/path open Orbit.app` renders every tab to PNG and quits.
@MainActor
enum Snapshot {
    /// True while rendering screenshots: no network calls, nothing written.
    static let isActive = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] != nil || ProcessInfo.processInfo.environment["ORBIT_SYNC_TEST"] != nil

    static func runIfRequested(container: ModelContainer, apple: AppleSync) {
        guard let dir = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] else { return }
        if ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_AI"] != nil,
           let data = #"{"headline":"Busy morning, easy evening","summary":"You have a budget review at 7 PM and four tasks due, including the electricity bill. Your water streak is at 7 days.","focus":["Pay the electricity bill before noon","Reply to your landlord — it's a day overdue","Do 20 minutes on chapter 4 notes"],"heads_up":"You've used 89% of this month's budget with 10 days left.","day":"\#(DayKey.key(.now))"}"#.data(using: .utf8),
           let brief = try? JSONDecoder().decode(MorningBrief.self, from: data) {
            AIAssistant.shared.previewBrief(brief)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Demo data lives in memory only, so screenshots never touch the real store.
            let container = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DEMO"] != nil ? demoContainer() : container
            // ORBIT_SNAPSHOT_SIZE=1180x760 renders at another window size.
            let dims = (ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_SIZE"] ?? "1440x900").split(separator: "x").compactMap { Double($0) }
            let size = CGSize(width: dims.first ?? 1440, height: dims.last ?? 900)
            @MainActor func render(_ name: String, tab: Tab, appearance: NSAppearance.Name, configure: @MainActor (AppState) -> Void = { _ in }) {
                let state = AppState()
                state.tab = tab
                state.openTodayJournal = tab == .notes
                configure(state)
                let view = RootView()
                    .environmentObject(state)
                    .environmentObject(apple)
                    .modelContainer(container)
                    .frame(width: size.width, height: size.height)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: appearance)
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: .now + 0.4)
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appending(path: "\(name)\(appearance == .aqua ? "" : "-dark").png"))
            }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for tab in Tab.allCases { render(tab.rawValue, tab: tab, appearance: appearance) }
            }
            // View modes kept in preferences: switch them for one shot each, then put them back.
            func withDefault(_ key: String, _ value: Any, _ body: () -> Void) {
                let previous = UserDefaults.standard.object(forKey: key)
                UserDefaults.standard.set(value, forKey: key)
                body()
                UserDefaults.standard.set(previous, forKey: key)
            }
            withDefault("calendarMode", "month") { render("calendar-month", tab: .calendar, appearance: .aqua) }
            withDefault("calendarMode", "day") { render("calendar-day", tab: .calendar, appearance: .aqua) }
            withDefault("moneyTab", "calendar") { render("money-calendar", tab: .money, appearance: .aqua) }
            withDefault("moneyTab", "subscriptions") { render("money-subscriptions", tab: .money, appearance: .aqua) }
            render("assistant", tab: .today, appearance: .aqua) { $0.assistantOpen = true }
            // Sample profile card (made-up details), rendered the way the share button exports it.
            var demo = ProfileCard()
            demo.name = "Sara Hassan"; demo.headline = "Product Designer"; demo.company = "Studio Nile"; demo.location = "Cairo, Egypt"
            demo.email = "sara@example.com"; demo.bio = "Designing calm software. Coffee, books and long walks."
            demo.links = [.init(kind: .linkedin, value: "linkedin.com/in/sarahassan"), .init(kind: .website, value: "sarahassan.design"),
                          .init(kind: .instagram, value: "@sara.designs"), .init(kind: .github, value: "sarahassan")]
            let face = ImageRenderer(content: CardFace(card: demo, photo: nil, qr: ProfileCardSheet.qr(demo.qrPayload)).padding(20))
            face.scale = 2
            if let cg = face.cgImage {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appending(path: "card.png"))
            }
            // Sheets don't show up offscreen, so render the review screens on their own.
            for (name, insights) in [("review", false), ("insights", true)] {
                let state = AppState()
                let host = NSHostingView(rootView: ReviewView(startOnInsights: insights)
                    .environmentObject(state).environmentObject(apple).modelContainer(container))
                host.appearance = NSAppearance(named: .aqua)
                host.frame = NSRect(x: 0, y: 0, width: 920, height: 740)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: .now + 0.6)
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }

    static func demoContainer() -> ModelContainer {
        let schema = Schema([TaskItem.self, EventItem.self, Habit.self, Transaction.self, Note.self, Book.self, BookCategory.self, BucketItem.self, ReadingSession.self, Highlight.self, Subscription.self, DocItem.self])
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

        return c
    }
}

/// Test hook: `ORBIT_SYNC_TEST=1 ORBIT_SUPABASE_URL=http://127.0.0.1:8799` plays two Macs against a stand-in server.
@MainActor
enum SyncTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["ORBIT_SYNC_TEST"] != nil,
              SupabaseConfig.url.hasPrefix("http://127.0.0.1") else { return }
        Task {
            var results: [String] = []
            func check(_ name: String, _ ok: Bool) { results.append("\(ok ? "PASS" : "FAIL")  \(name)") }
            let cloud = CloudSync.shared
            // Never touch the real key-sync setup: set it aside now and put it back at the end.
            let realPassphrase = Keychain.read("sync-passphrase")
            let realSession = Keychain.read("supabase-session")
            let realKeySync = cloud.syncSecrets
            cloud.syncSecrets = false
            let schema = Schema([TaskItem.self, EventItem.self, Habit.self, Transaction.self, Note.self, Book.self, BookCategory.self, BucketItem.self, ReadingSession.self, Highlight.self, Subscription.self, DocItem.self])
            do {
                // Keep the containers alive for the whole test; a context is only valid while its container exists.
                let containerA = Snapshot.demoContainer()
                let containerB = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
                let a = containerA.mainContext
                let b = containerB.mainContext

                cloud.deviceTag = "-testA"
                try await cloud.signIn(email: "test@example.com", password: "secret1", context: a)
                check("Mac A uploads (\(cloud.status ?? "-"))", cloud.status?.contains("up") == true)

                cloud.deviceTag = "-testB"
                await cloud.sync(context: b)
                func count<T: PersistentModel>(_ t: T.Type, _ c: ModelContext) -> Int { (try? c.fetchCount(FetchDescriptor<T>())) ?? -1 }
                check("Mac B gets all tasks (\(count(TaskItem.self, b))/\(count(TaskItem.self, a)))", count(TaskItem.self, a) == count(TaskItem.self, b))
                check("Mac B gets all books (\(count(Book.self, b))/\(count(Book.self, a)))", count(Book.self, a) == count(Book.self, b))
                check("Mac B gets money (\(count(Transaction.self, b))/\(count(Transaction.self, a)))", count(Transaction.self, a) == count(Transaction.self, b))
                check("Mac B gets bucket list (\(count(BucketItem.self, b))/\(count(BucketItem.self, a)))", count(BucketItem.self, a) == count(BucketItem.self, b))
                check("Mac B gets subscriptions (\(count(Subscription.self, b))/\(count(Subscription.self, a)))", count(Subscription.self, a) == count(Subscription.self, b))
                check("Mac B gets documents (\(count(DocItem.self, b))/\(count(DocItem.self, a)))", count(DocItem.self, a) == count(DocItem.self, b))
                let trialB = try b.fetch(FetchDescriptor<Subscription>()).first { $0.status == "trial" }
                check("Trial end date comes across", trialB?.trialEnds != nil)
                let journalB = try b.fetch(FetchDescriptor<Note>()).first { $0.isJournal && $0.chatData != nil }
                check("Journal chat comes across", journalB?.chat?.turns.count == 4)

                // Edit and delete on B, then let A catch up.
                let taskB = try b.fetch(FetchDescriptor<TaskItem>()).first!
                taskB.title = "Edited on Mac B"
                let bookB = try b.fetch(FetchDescriptor<Book>()).first!
                let deletedTitle = bookB.title
                b.delete(bookB)
                try b.save()
                await cloud.sync(context: b)
                await cloud.sync(context: b)
                check("Second sync on B finds nothing new (\(cloud.status ?? "-"))", cloud.status == "Up to date")

                cloud.deviceTag = "-testA"
                await cloud.sync(context: a)
                let tasksA = try a.fetch(FetchDescriptor<TaskItem>())
                check("Edit reaches Mac A", tasksA.contains { $0.title == "Edited on Mac B" })
                check("Deletion reaches Mac A", !(try a.fetch(FetchDescriptor<Book>())).contains { $0.title == deletedTitle })

                // Key sync: A turns it on, B must give the same passphrase; the server never sees a key in the clear.
                let errA = await cloud.setPassphrase("test-pass-123", context: a)
                check("Keys upload, encrypted (\(errA ?? "ok"))", errA == nil && cloud.vaultState == .on)
                var req = URLRequest(url: URL(string: "\(SupabaseConfig.url)/rest/v1/orbit_records?select=data,kind")!)
                req.setValue("Bearer tok", forHTTPHeaderField: "Authorization")
                let (raw, _) = try await URLSession.shared.data(for: req)
                let stored = String(decoding: raw, as: UTF8.self)
                let secrets = Keychain.syncable().values.filter { $0.count >= 8 }
                check("Server holds no readable key (\(secrets.count) checked)", stored.contains("\"vault\"") && !secrets.contains { stored.contains($0) })
                cloud.deviceTag = "-testB"
                Keychain.delete("sync-passphrase")
                let wrong = await cloud.setPassphrase("not-the-pass", context: b)
                check("Wrong passphrase is refused", wrong != nil)
                let right = await cloud.setPassphrase("test-pass-123", context: b)
                check("Right passphrase unlocks on Mac B (\(right ?? "ok"))", right == nil && cloud.vaultState == .on)
            } catch {
                results.append("FAIL  \(error.localizedDescription)")
            }
            // Leave no trace: sign out and remove the test sync state.
            for tag in ["-testA", "-testB"] { cloud.deviceTag = tag; if let s = CloudAuth.session {
                try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "Orbit/sync-\(s.userID)\(tag).json")) } }
            cloud.signOut()
            cloud.deviceTag = ""
            if let realPassphrase { Keychain.write(realPassphrase, account: "sync-passphrase") } else { Keychain.delete("sync-passphrase") }
            if let realSession { Keychain.write(realSession, account: "supabase-session") }
            cloud.syncSecrets = realKeySync
            print(results.joined(separator: "\n"))
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}
