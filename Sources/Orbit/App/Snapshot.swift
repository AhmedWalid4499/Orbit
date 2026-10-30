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
                guard let rep = Snapshot.retinaRep(host) else { return }
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
            withDefault("moneyTab", "overview") { render("money-overview", tab: .money, appearance: .aqua) }
            withDefault("moneyTab", "bills") { render("money-bills", tab: .money, appearance: .aqua); render("money-bills", tab: .money, appearance: .darkAqua) }
            withDefault("bucketSection", "goals") { render("goals", tab: .bucket, appearance: .aqua); render("goals", tab: .bucket, appearance: .darkAqua) }
            render("assistant", tab: .today, appearance: .aqua) { $0.assistantOpen = true }
            // Sample profile card (made-up details), rendered the way the share button exports it.
            var demo = ProfileCard()
            demo.name = "Sara Hassan"; demo.headline = "Product Designer"; demo.company = "Studio Nile"; demo.location = "Cairo, Egypt"
            demo.email = "sara@example.com"; demo.bio = "Designing calm software. Coffee, books and long walks."
            demo.links = [.init(kind: .linkedin, value: "linkedin.com/in/sarahassan"), .init(kind: .website, value: "sarahassan.design"),
                          .init(kind: .instagram, value: "@sara.designs"), .init(kind: .github, value: "sarahassan")]
            // ORBIT_SNAPSHOT_CARDPHOTO=<image> renders the photo style with that picture.
            let sample = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_CARDPHOTO"].flatMap { NSImage(contentsOfFile: $0) }
            for (name, style, back) in [("card", "photo", false), ("card-back", "photo", true), ("card-color", "color", false)] {
                var c = demo
                c.style = style
                let face = ImageRenderer(content: CardFace(card: c, photo: nil, qr: ProfileCardSheet.qr(c.qrPayload), backdrop: sample, startOnBack: back).padding(20))
                face.scale = 2
                if let cg = face.cgImage {
                    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
                }
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
                if let rep = Snapshot.retinaRep(host) {
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
                }
            }
            renderAlone("review", width: 920, height: 740, ReviewView(startOnInsights: false))
            renderAlone("review-insights", width: 920, height: 740, ReviewView(startOnInsights: true))
            for (i, t) in [0.2, 0.8, 1.6].enumerated() { renderAlone("splash-\(i)", width: size.width, height: size.height, SplashView(time: t)) }
            renderAlone("plan-tomorrow", width: 1040, height: 720, PlanTomorrowSheet())
            if let acct = try? container.mainContext.fetch(FetchDescriptor<BankAccount>(sortBy: [SortDescriptor(\.createdAt)])).first {
                renderAlone("account", width: 720, height: 760, AccountPage(account: acct))
            }
            renderAlone("goto", width: 1100, height: 820, wait: 3, ScrollView { GoToSection().padding(28) })
            renderAlone("money-rules", width: 560, height: 720, MoneyRulesSheet())
            renderAlone("tour", width: 1040, height: 766, wait: 1.5, TourView {})
            renderAlone("signed-out", width: 1280, height: 800, wait: 1, SignedOutWelcome())
            renderAlone("pro-welcome", width: 760, height: 780, wait: 1.2, ProWelcome())
            renderAlone("ai-consent", width: 480, height: 520, wait: 0.5, AIConsentSheet())
            for i in 0..<6 { renderAlone("setup-\(i)", width: 620, height: 640, wait: 0.6, SetupFlow(startAt: i)) }
            // The tour's MacBook screens: a smaller window, so text stays readable when the picture is shown small.
            if ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_TOUR"] != nil {
                let tourSize = CGSize(width: 1280, height: 800)
                @MainActor func tourShot(_ name: String, _ tab: Tab, _ configure: @escaping @MainActor (AppState) -> Void = { _ in }) {
                    let state = AppState(); state.tab = tab; configure(state)
                    renderAlone("tour-\(name)", width: tourSize.width, height: tourSize.height, wait: 1.2,
                                RootView().environmentObject(state).frame(width: tourSize.width, height: tourSize.height))
                }
                tourShot("today", .today)
                tourShot("assistant", .today) { $0.assistantOpen = true }
                tourShot("calendar", .calendar)
                tourShot("money", .money)
                tourShot("reading", .reading)
                tourShot("insights", .insights)
                renderAlone("tour-day", width: 760, height: 475, wait: 0.8,
                            VStack(spacing: 14) { DaySummaryCard(); BriefCard() }.padding(20).frame(width: 760, height: 475, alignment: .top).background(Theme.canvas))
                renderAlone("tour-goto", width: 1100, height: 688, wait: 3, ScrollView { GoToSection().padding(28) }.background(Theme.canvas))
            }
            renderAlone("auth", width: 480, height: 620, ScrollView { AuthPanel().padding(28) })
            renderAlone("github-connect", width: 640, height: 520, ScrollView { GitHubConnectCard().padding(24) })
            renderAlone("tabs", width: 520, height: 720, Form { TabsSection() }.formStyle(.grouped))
            renderAlone("inbox-window", width: 520, height: 360, Form { InboxWindowControls() }.formStyle(.grouped))
            renderAlone("memory", width: 520, height: 420, Form { MemorySection() }.formStyle(.grouped))
            renderAlone("brands", width: 720, height: 300, LazyVGrid(columns: Array(repeating: GridItem(.fixed(64)), count: 10), spacing: 14) {
                ForEach(Brand.allCases, id: \.self) { b in VStack(spacing: 4) { BrandLogo(brand: b, size: 36); BrandLogo(brand: b, size: 20, style: .glyph) } }
            }.padding(16).background(Theme.canvas))
            renderAlone("mail", width: 620, height: 720, wait: 1, MailSheet(id: "demo1", account: "alex@example.com"))
            renderAlone("place-chat", width: 420, height: 320, wait: 2.5, PlaceChatCard(place: ChatPlace(name: "Zooba", address: "26 Taha Hussein, Zamalek", category: "food", lat: 30.0612, lon: 31.2195), note: "Saved to Go to") {}.padding(20))
            renderAlone("shared-lists", width: 760, height: 640, wait: 1, ScrollView { SharedListsView().padding(28) }.background(Theme.canvas))
            renderAlone("bill-editor", width: 460, height: 540, BillEditor(bill: nil))
            renderAlone("goal-editor", width: 500, height: 600, GoalEditor(goal: nil))
            if let trip = try? container.mainContext.fetch(FetchDescriptor<Trip>()).first {
                renderAlone("trip", width: 820, height: 720, TripSheet(trip: trip))
            }
            if let csv = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_STATEMENT"] {
                renderAlone("statement", width: 860, height: 700, wait: 2.5, StatementImportSheet(url: URL(fileURLWithPath: csv)))
            }
            FocusTimer.shared.start(context: container.mainContext)
            render("today-focus", tab: .today, appearance: .aqua)
            FocusTimer.shared.stop(context: container.mainContext)
            renderAlone("splash-dark", width: size.width, height: size.height, appearance: .darkAqua, SplashView(time: 1.6))
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
            print("FAIL  Quit Joshu before running the sync test.")
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
                check("Mac B gets bank accounts (\(count(BankAccount.self, b))/\(count(BankAccount.self, a)))", count(BankAccount.self, a) == count(BankAccount.self, b) && count(BankAccount.self, a) > 0)
                let cibB = try b.fetch(FetchDescriptor<BankAccount>()).first { $0.name == "CIB" }
                let linked = try b.fetch(FetchDescriptor<Transaction>()).filter { $0.account == cibB?.uuid }.count
                check("Balances and linked payments come across (\(linked) on CIB)", cibB?.balance == 45210.5 && cibB?.last4 == "1234" && linked > 0)
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

                // The same chat under upper- and lower-case ids: one row reaches the server (it refuses two), the newest.
                let chatID = UUID().uuidString
                let oldCopy = ChatThread(uuid: chatID.lowercased()), newCopy = ChatThread(uuid: chatID)
                oldCopy.title = "Older copy"; oldCopy.updatedAt = .now.addingTimeInterval(-60)
                newCopy.title = "Newer copy"
                a.insert(oldCopy); a.insert(newCopy)
                try a.save()
                let chatSynced = await cloud.sync(context: a)
                let chatsHere = try a.fetch(FetchDescriptor<ChatThread>()).filter { $0.uuid.lowercased() == chatID.lowercased() }
                check("Two copies of a chat don't stop the upload (\(cloud.status ?? "-"))", chatSynced)
                check("One copy of the chat stays, the newest", chatsHere.count == 1 && chatsHere.first?.title == "Newer copy" && chatsHere.first?.uuid == chatID.lowercased())
                await cloud.sync(context: a)
                check("…and it stays one after another sync", try a.fetch(FetchDescriptor<ChatThread>()).filter { $0.uuid.lowercased() == chatID.lowercased() }.count == 1)

                // Deleted on one device while edited on the other: the edit wins and comes back everywhere.
                let editedA = try a.fetch(FetchDescriptor<TaskItem>()).first { $0.title != "Edited on Mac B" }!
                let contested = editedA.uuid
                editedA.title = "Edited on A, deleted on B"
                try a.save()
                cloud.deviceTag = "-testB"
                b.delete(try b.fetch(FetchDescriptor<TaskItem>()).first { $0.uuid == contested }!)
                try b.save()
                await cloud.sync(context: b)
                cloud.deviceTag = "-testA"
                await cloud.sync(context: a)
                check("An edit survives a deletion elsewhere", try a.fetch(FetchDescriptor<TaskItem>()).contains { $0.title == "Edited on A, deleted on B" })
                cloud.deviceTag = "-testB"
                await cloud.sync(context: b)
                check("…and comes back on the other device", try b.fetch(FetchDescriptor<TaskItem>()).contains { $0.title == "Edited on A, deleted on B" })
                cloud.deviceTag = "-testA"

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

                // Removing a key stays removed, here and on the other device, while a key added elsewhere still arrives.
                cloud.deviceTag = "-testA"
                await cloud.sync(context: a)
                Keychain.write("gone-value", account: "orbit-test-gone")
                await cloud.sync(context: a)
                cloud.deviceTag = "-testB"
                await cloud.sync(context: b)
                cloud.deviceTag = "-testA"
                Keychain.delete("orbit-test-gone")
                await cloud.sync(context: a)
                await cloud.sync(context: a)
                check("A removed key doesn't come back", Keychain.read("orbit-test-gone") == nil)
                cloud.deviceTag = "-testB"
                Keychain.write("gone-value", account: "orbit-test-gone")   // the two devices share one Keychain here
                await cloud.sync(context: b)
                check("A key removed elsewhere is removed here too", Keychain.read("orbit-test-gone") == nil)

                // Clearing a setting reaches the other device, and that device still takes later changes.
                let realGoodreads = UserDefaults.standard.object(forKey: "goodreadsUser")
                UserDefaults.standard.set("test-reader", forKey: "goodreadsUser")
                cloud.deviceTag = "-testA"
                await cloud.sync(context: a)
                cloud.deviceTag = "-testB"
                await cloud.sync(context: b)
                UserDefaults.standard.removeObject(forKey: "goodreadsUser")
                await cloud.sync(context: b)
                var clearedRows: [[String: Any]] = []
                var clearedReq = URLRequest(url: URL(string: "\(SupabaseConfig.url)/rest/v1/orbit_records?select=data,kind")!)
                clearedReq.setValue("Bearer tok", forHTTPHeaderField: "Authorization")
                clearedRows = (try JSONSerialization.jsonObject(with: try await URLSession.shared.data(for: clearedReq).0) as? [[String: Any]]) ?? []
                let clearedRow = clearedRows.compactMap { $0["data"] as? [String: Any] }.first { $0["key"] as? String == "goodreadsUser" }
                check("A cleared setting reaches the account", clearedRow != nil && clearedRow?["value"] is NSNull)
                cloud.deviceTag = "-testA"
                UserDefaults.standard.set("test-reader", forKey: "goodreadsUser")   // still set on A: one settings store here
                await cloud.sync(context: a)
                check("…and is cleared on the other device", UserDefaults.standard.object(forKey: "goodreadsUser") == nil)
                UserDefaults.standard.set(realGoodreads, forKey: "goodreadsUser")

                // A server that's down or busy never ends the sign-in; only a refusal does.
                func refreshAnswers(_ status: Int) async throws {
                    var r = URLRequest(url: URL(string: "\(SupabaseConfig.url)/test/refresh")!)
                    r.httpMethod = "POST"
                    r.httpBody = try JSONSerialization.data(withJSONObject: ["status": status])
                    _ = try await URLSession.shared.data(for: r)
                }
                let goodSession = CloudAuth.session
                var expired = goodSession
                expired?.expiresAt = .distantPast
                CloudAuth.session = expired
                try await refreshAnswers(503)
                _ = try? await CloudAuth.accessToken()
                check("A server outage keeps you signed in", CloudAuth.session != nil)
                try await refreshAnswers(429)
                _ = try? await CloudAuth.accessToken()
                check("A busy server keeps you signed in", CloudAuth.session != nil)
                try await refreshAnswers(200)
                _ = try? await CloudAuth.accessToken()
                check("A Wi-Fi login page keeps you signed in", CloudAuth.session != nil)
                try await refreshAnswers(400)
                _ = try? await CloudAuth.accessToken()
                check("A refused sign-in ends it", CloudAuth.session == nil)
                try await refreshAnswers(0)
                CloudAuth.session = goodSession

                // Signing out removes this device's copy, but only after a last sync, and deletes nothing from the account.
                func serverRows(_ token: String) async throws -> [[String: Any]] {
                    var r = URLRequest(url: URL(string: "\(SupabaseConfig.url)/rest/v1/orbit_records?select=data,kind,deleted")!)
                    r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    return (try JSONSerialization.jsonObject(with: try await URLSession.shared.data(for: r).0) as? [[String: Any]]) ?? []
                }
                func deletions(_ token: String) async throws -> Int { try await serverRows(token).filter { J.bool($0["deleted"]) }.count }
                cloud.deviceTag = "-testA"
                let deletedBefore = try await deletions("tok")
                let tasksBefore = count(TaskItem.self, a), booksBefore = count(Book.self, a)
                try await cloud.signOut(context: a, keepOnDevice: false)
                check("Sign-out removes this device's copy (\(count(TaskItem.self, a)) tasks, \(count(Book.self, a)) books left)",
                      count(TaskItem.self, a) == 0 && count(Book.self, a) == 0 && CloudAuth.session == nil)
                let deletedAfterOut = try await deletions("tok")
                check("Sign-out deletes nothing from the account (\(deletedAfterOut - deletedBefore) new deletions)", deletedAfterOut == deletedBefore)
                try await cloud.signIn(email: "test@example.com", password: "secret1", context: a)
                check("Signing in again brings it all back (\(count(TaskItem.self, a))/\(tasksBefore) tasks, \(count(Book.self, a))/\(booksBefore) books)",
                      tasksBefore > 0 && count(TaskItem.self, a) == tasksBefore && count(Book.self, a) == booksBefore)
                let deletedAfterIn = try await deletions("tok")
                check("Signing in again deletes nothing (\(deletedAfterIn - deletedBefore) new deletions)", deletedAfterIn == deletedBefore)

                // Keeping a copy, then someone else signs in here: the copy is cleared first and never reaches their account.
                try await cloud.signOut(context: a, keepOnDevice: true)
                check("Keeping a copy leaves it on this device (\(count(TaskItem.self, a)) tasks)", count(TaskItem.self, a) == tasksBefore)
                try await cloud.signIn(email: "other@example.com", password: "secret2", context: a)
                let otherTasks = try await serverRows("tok2").filter { $0["kind"] as? String == "task" }.count
                check("Another account gets none of it (\(otherTasks) tasks uploaded, \(count(TaskItem.self, a)) left here)",
                      otherTasks == 0 && count(TaskItem.self, a) == 0)
                let deletedAfterSwitch = try await deletions("tok")
                check("The first account loses nothing (\(deletedAfterSwitch - deletedBefore) new deletions)", deletedAfterSwitch == deletedBefore)

                // Deleting an account keeps what's on this device, and the next account takes it over instead of clearing it.
                let keptTask = TaskItem(title: "Kept after deleting the account")
                a.insert(keptTask)
                try a.save()
                await cloud.sync(context: a)
                try await cloud.deleteAccount()
                check("Deleting the account keeps this device's copy", count(TaskItem.self, a) == 1)
                try await cloud.signIn(email: "other@example.com", password: "secret2", context: a)
                let carried = try await serverRows("tok2").filter { $0["kind"] as? String == "task" && !J.bool($0["deleted"]) }.count
                check("The next account keeps it (\(count(TaskItem.self, a)) here, \(carried) uploaded)", count(TaskItem.self, a) == 1 && carried == 1)
            } catch {
                results.append("FAIL  \(error.localizedDescription)")
            }
            // Leave no trace: sign out and remove the test sync state.
            for tag in ["-testA", "-testB", "-testC"] { cloud.deviceTag = tag; if let s = CloudAuth.session {
                try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "Orbit/sync-\(s.userID)\(tag).json")) } }
            cloud.signOut()
            let orbitFolder = URL.applicationSupportDirectory.appending(path: "Orbit", directoryHint: .isDirectory)
            for f in (try? FileManager.default.contentsOfDirectory(at: orbitFolder, includingPropertiesForKeys: nil)) ?? []
            where f.lastPathComponent.hasPrefix("sync-") && f.lastPathComponent.contains("-test") { try? FileManager.default.removeItem(at: f) }
            for tag in ["-testA", "-testB", "-testC"] { UserDefaults.standard.removeObject(forKey: "sync.owner" + tag) }
            cloud.deviceTag = ""
            Keychain.delete("orbit-test-secret")
            Keychain.delete("orbit-test-gone")
            if let realPassphrase { Keychain.write(realPassphrase, account: "sync-passphrase") } else { Keychain.delete("sync-passphrase") }
            if let realSession { Keychain.write(realSession, account: "supabase-session") }
            cloud.syncSecrets = realKeySync

            // Budget months: payday on the 31st, and stepping through months of different lengths.
            let realAnchor = UserDefaults.standard.object(forKey: BudgetPeriod.key)
            func day(_ y: Int, _ m: Int, _ d: Int) -> Date { Calendar.current.date(from: DateComponents(year: y, month: m, day: d))! }
            func dayOf(_ d: Date) -> Int { Calendar.current.component(.day, from: d) }
            let anchor = Income.paydayAnchor(31, now: day(2027, 7, 1).addingTimeInterval(3600))   // set on 1 July
            check("Payday 31 set in June counts from a real 31st", dayOf(anchor) == 31)
            let febAnchor = Income.paydayAnchor(30, now: day(2027, 3, 1))
            check("Payday 30 set after February counts from a real 30th", dayOf(febAnchor) == 30)
            BudgetPeriod.anchor = anchor
            let june = BudgetPeriod.period(containing: day(2027, 6, 15))
            let august = BudgetPeriod.period(containing: day(2027, 8, 15))
            check("Budget months run from the 31st or the month's last day", dayOf(june.start) == 31 && dayOf(august.start) == 31)
            var step = BudgetPeriod.period(containing: day(2027, 1, 15)), starts: [Int] = []
            for _ in 0..<14 { step = BudgetPeriod.shifted(step, by: 1); starts.append(Calendar.current.component(.month, from: step.start)) }
            check("The forward arrow never sticks (\(starts))", Set(starts).count == 12 && zip(starts, starts.dropFirst()).allSatisfy { $0 != $1 })
            let there = BudgetPeriod.shifted(june, by: 3)
            check("Back undoes forward", BudgetPeriod.shifted(there, by: -3).start == june.start)
            UserDefaults.standard.set(realAnchor, forKey: BudgetPeriod.key)
            print(results.joined(separator: "\n"))
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}

extension Snapshot {
    /// A 2× bitmap of a view (offscreen windows render at 1×, which looks blurry on Retina).
    static func retinaRep(_ view: NSView) -> NSBitmapImageRep? {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

}

/// Read-only check: `ORBIT_SYNC_REPORT=1 ORBIT_SNAPSHOT_DEMO=1 build/Orbit.app/Contents/MacOS/Orbit` prints what your
/// account holds on the sync server (items by kind, live and deleted, and when things were deleted), using this Mac's
/// sign-in. It changes nothing: no data is opened (demo mode) and nothing is written.
@MainActor
enum SyncReport {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["ORBIT_SYNC_REPORT"] != nil else { return }
        Task {
            var counts: [String: (live: Int, deleted: Int)] = [:]
            var deletedDays: [String: [String: Int]] = [:]   // kind → day → deletions
            var cursor = "", lastID: String?, rowsSeen = 0
            do {
                while true {
                    var c = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/orbit_records")!
                    c.queryItems = [.init(name: "select", value: ProcessInfo.processInfo.environment["ORBIT_SYNC_REPORT_DATA"] != nil ? "id,kind,deleted,updated_at,data" : "id,kind,deleted,updated_at"), .init(name: "order", value: "updated_at.asc,id.asc"),
                                    .init(name: "limit", value: "1000")] + CloudSync.after(cursor: cursor, id: lastID)
                    c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
                    let rows = try await CloudSync.shared.rest(c.url!, method: "GET") as? [[String: Any]] ?? []
                    for r in rows {
                        let kind = r["kind"] as? String ?? "?"
                        let del = J.bool(r["deleted"])
                        if kind == "book", !del, let d = r["data"] as? [String: Any] {
                            print("BOOK \(r["id"] ?? "") \(r["updated_at"] ?? "") keys=\(d.keys.sorted().joined(separator: ",")) source=\(d["source"] ?? "-") library=\(d["library"] ?? "-")")
                        }
                        if ["bucket", "subscription"].contains(kind) { print("ROW \(kind) \(r["id"] ?? "") \(del ? "deleted" : "live") \(r["updated_at"] ?? "")") }
                        rowsSeen += 1
                        var n = counts[kind] ?? (0, 0)
                        if del { n.deleted += 1; deletedDays[kind, default: [:]][String((r["updated_at"] as? String ?? "").prefix(13)), default: 0] += 1 } else { n.live += 1 }
                        counts[kind] = n
                    }
                    cursor = rows.last?["updated_at"] as? String ?? cursor
                    lastID = rows.last?["id"] as? String ?? lastID
                    if rows.isEmpty { break }   // not "fewer than asked for": a server may send smaller pages
                }
                print("ROWS \(rowsSeen)")
                for (k, n) in counts.sorted(by: { $0.key < $1.key }) { print("KIND \(k): \(n.live) live, \(n.deleted) deleted") }
                for (k, days) in deletedDays.sorted(by: { $0.key < $1.key }) where ["book", "bucket", "subscription"].contains(k) {
                    print("DELETED \(k) by hour (UTC): \(days.sorted(by: { $0.key < $1.key }).map { "\($0.key)h=\($0.value)" }.joined(separator: ", "))")
                }
                var s = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/orbit_records")!
                s.queryItems = [.init(name: "select", value: "data,updated_at"), .init(name: "kind", value: "eq.setting")]
                for r in try await CloudSync.shared.rest(s.url!, method: "GET") as? [[String: Any]] ?? [] {
                    if let d = r["data"] as? [String: Any], d["key"] as? String == "assistantName" {
                        print("SETTING assistantName = \(d["value"] ?? "nil") at \(d["at"] ?? "-") (row updated \(r["updated_at"] ?? ""))")
                    }
                }
            } catch {
                print("REPORT FAILED: \(error.localizedDescription)")
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}
