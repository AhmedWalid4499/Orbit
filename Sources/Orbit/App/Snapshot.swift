import SwiftUI
import SwiftData
import AppKit

/// Debug helper: `ORBIT_SNAPSHOT_DIR=/path open Orbit.app` renders every tab to PNG and quits.
extension Snapshot {

    static func runIfRequested(container: ModelContainer, apple: AppleSync) {
        guard let dir = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] else { return }
        if ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_AI"] != nil { Snapshot.previewAI() }
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
            // Sheets don't show up offscreen, so render them on their own.
            @MainActor func renderAlone(_ name: String, width: Double, height: Double, appearance: NSAppearance.Name = .aqua, wait: Double = 0.6, _ view: some View) {
                let host = NSHostingView(rootView: view.environmentObject(AppState()).environmentObject(apple).modelContainer(container))
                host.appearance = NSAppearance(named: appearance)
                host.frame = NSRect(x: 0, y: 0, width: width, height: height)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: .now + wait)
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
                }
            }
            renderAlone("review", width: 920, height: 740, ReviewView(startOnInsights: false))
            renderAlone("review-insights", width: 920, height: 740, ReviewView(startOnInsights: true))
            for (i, a) in [0.6, 2.2, 4.0].enumerated() { renderAlone("splash-\(i)", width: size.width, height: size.height, SplashView(angle: a)) }
            renderAlone("plan-tomorrow", width: 1040, height: 720, PlanTomorrowSheet())
            renderAlone("goto", width: 1100, height: 820, wait: 3, ScrollView { GoToSection().padding(28) })
            renderAlone("money-rules", width: 560, height: 720, MoneyRulesSheet())
            renderAlone("tour", width: 1000, height: 640, wait: 3.2, TourView {})
            if let trip = try? container.mainContext.fetch(FetchDescriptor<Trip>()).first {
                renderAlone("trip", width: 820, height: 720, TripSheet(trip: trip))
            }
            if let csv = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_STATEMENT"] {
                renderAlone("statement", width: 860, height: 700, wait: 2.5, StatementImportSheet(url: URL(fileURLWithPath: csv)))
            }
            FocusTimer.shared.start(context: container.mainContext)
            render("today-focus", tab: .today, appearance: .aqua)
            FocusTimer.shared.stop(context: container.mainContext)
            renderAlone("splash-dark", width: size.width, height: size.height, appearance: .darkAqua, SplashView(angle: 0.9))
            NSApp.terminate(nil)
        }
    }
}

/// Test hook: `ORBIT_AI_TEST=<file>` runs the planning conversation and a file question against Claude with demo data,
/// prints what happened and quits. Nothing is saved to your real data or chat history.
@MainActor
enum AITest {
    static func runIfRequested(apple: AppleSync) {
        guard let file = ProcessInfo.processInfo.environment["ORBIT_AI_TEST"] else { return }
        Task {
            let container = Snapshot.demoContainer()
            let context = container.mainContext
            let draft = PlanDraft(), chat = PlanChat()
            var saved = false
            chat.onSave = { saved = true }
            chat.greet(leftovers: [], tomorrowEvents: 0)
            await chat.send("Move the electricity bill to tomorrow. Tomorrow I really need to finish the budget review deck, call my mom, and go to the gym. Remind me to bring my charger. That's it, save it.",
                            draft: draft, context: context, apple: apple)
            for i in chat.items { print("PLAN [\(i.role.rawValue)] \(i.text)") }
            print("PLAN top: \(draft.picks.map(\.title)) note: \(draft.note) saved: \(saved) error: \(chat.error ?? "-")")
            if let client = ClaudeClient(), let a = try? ChatAttachment.load(URL(fileURLWithPath: file)) {
                let reply = try? await client.stream(system: "Answer in one sentence.", messages: [["role": "user", "content": [a.block, ["type": "text", "text": "What is this document about, and what's the due date in it?"]]]],
                                                     effort: "low", onText: { _ in })
                print("FILE [\(a.kind)] \(reply?.text ?? "no reply")")
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}

/// Test hook: `ORBIT_SYNC_TEST=1 ORBIT_SUPABASE_URL=http://127.0.0.1:8799` plays two Macs against a stand-in server.
@MainActor
enum SyncTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["ORBIT_SYNC_TEST"] != nil,
              SupabaseConfig.url.hasPrefix("http://127.0.0.1") else { return }
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }) {
            // The test borrows the keychain the real app uses; running both could leave the real app signed out.
            print("FAIL  Quit Orbit before running the sync test.")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        Task {
            var results: [String] = []
            func check(_ name: String, _ ok: Bool) { results.append("\(ok ? "PASS" : "FAIL")  \(name)") }
            let cloud = CloudSync.shared
            // Never touch the real key-sync setup: set it aside now and put it back at the end.
            let realPassphrase = Keychain.read("sync-passphrase")
            let realSession = Keychain.read("supabase-session")
            let realKeySync = cloud.syncSecrets
            cloud.syncSecrets = false
            let schema = OrbitSchema.schema
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
                check("Mac B gets focus sessions (\(count(FocusSession.self, b))/\(count(FocusSession.self, a)))", count(FocusSession.self, a) == count(FocusSession.self, b))
                check("Mac B gets day plans (\(count(DayPlan.self, b))/\(count(DayPlan.self, a)))", count(DayPlan.self, a) == count(DayPlan.self, b))
                check("Mac B gets trips and bookings (\(count(Trip.self, b))+\(count(Booking.self, b)))", count(Trip.self, a) == count(Trip.self, b) && count(Booking.self, a) == count(Booking.self, b))
                let tripB = try b.fetch(FetchDescriptor<Trip>()).first
                let bookingsB = try b.fetch(FetchDescriptor<Booking>()).filter { $0.tripUUID == tripB?.uuid }
                check("Packing list and bookings stay linked (\(tripB?.packed.count ?? 0) packed, \(bookingsB.count) bookings)", tripB?.packed.count == 3 && bookingsB.count == 3)
                let planB = try b.fetch(FetchDescriptor<DayPlan>()).first
                check("Top 3 comes across", planB?.top.count == 3 && planB?.note == "Bring the charger")
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

                // Key sync. An older Orbit left a passphrase vault; the Mac that still has the passphrase converts it,
                // then a second device gets the keys with nothing to type, and the server never holds a key in the clear.
                let testSecret = "test-secret-value-123"
                cloud.syncSecrets = true
                cloud.deviceTag = "-testA"
                try await cloud.storeLegacyVaultForTest(["secrets": ["orbit-test-secret": testSecret], "config": [String: Any]()], passphrase: "test-pass-123")
                Keychain.write("test-pass-123", account: "sync-passphrase")
                await cloud.sync(context: a)
                check("Old passphrase vault is converted (\(cloud.vaultState))", cloud.vaultState == .on && Keychain.read("sync-passphrase") == nil)
                var req = URLRequest(url: URL(string: "\(SupabaseConfig.url)/rest/v1/orbit_records?select=data,kind")!)
                req.setValue("Bearer tok", forHTTPHeaderField: "Authorization")
                let (raw, _) = try await URLSession.shared.data(for: req)
                let rows = (try JSONSerialization.jsonObject(with: raw) as? [[String: Any]]) ?? []
                let vaultRow = rows.first { $0["kind"] as? String == "vault" }?["data"] as? [String: Any]
                let stored = String(decoding: try JSONSerialization.data(withJSONObject: vaultRow ?? [:]), as: UTF8.self)
                let secrets = Keychain.syncable().values.filter { $0.count >= 8 }
                check("Vault is in the new format", vaultRow?["v"] as? Int == 2)
                check("Server holds no readable key (\(secrets.count) checked)", vaultRow != nil && !secrets.contains { stored.contains($0) })

                // A Mac that has the keys but forgot the passphrase replaces an old vault instead of getting stuck.
                try await cloud.storeLegacyVaultForTest(["secrets": [String: String](), "config": [String: Any]()], passphrase: "lost-pass")
                cloud.deviceTag = "-testC"
                await cloud.sync(context: a)
                check("Old vault without its passphrase is replaced (\(cloud.vaultState))", cloud.vaultState == .on)

                cloud.deviceTag = "-testB"
                Keychain.delete("orbit-test-secret")
                await cloud.sync(context: b)
                check("New device gets the keys with nothing to type (\(cloud.vaultState))",
                      cloud.vaultState == .on && Keychain.read("orbit-test-secret") == testSecret)
            } catch {
                results.append("FAIL  \(error.localizedDescription)")
            }
            // Leave no trace: sign out and remove the test sync state.
            for tag in ["-testA", "-testB", "-testC"] { cloud.deviceTag = tag; if let s = CloudAuth.session {
                try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "Orbit/sync-\(s.userID)\(tag).json")) } }
            cloud.signOut()
            cloud.deviceTag = ""
            Keychain.delete("orbit-test-secret")
            if let realPassphrase { Keychain.write(realPassphrase, account: "sync-passphrase") } else { Keychain.delete("sync-passphrase") }
            if let realSession { Keychain.write(realSession, account: "supabase-session") }
            cloud.syncSecrets = realKeySync
            print(results.joined(separator: "\n"))
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}
