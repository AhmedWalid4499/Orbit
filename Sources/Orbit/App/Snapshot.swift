import SwiftUI
import SwiftData
import AppKit

/// Debug helper: `ORBIT_SNAPSHOT_DIR=/path open Orbit.app` renders every tab to PNG and quits.
@MainActor
enum Snapshot {
    /// True while rendering screenshots: no network calls, nothing written.
    static let isActive = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] != nil

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
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                for tab in Tab.allCases {
                    let state = AppState()
                    state.tab = tab
                    state.openTodayJournal = tab == .notes
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
                    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let suffix = appearance == .aqua ? "" : "-dark"
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appending(path: "\(tab.rawValue)\(suffix).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static func demoContainer() -> ModelContainer {
        let schema = Schema([TaskItem.self, EventItem.self, Habit.self, Transaction.self, Note.self, Book.self, BookCategory.self])
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
            let b = Book(title: t, author: a, status: st)
            b.rating = r; b.categories = cs; b.progress = p; b.pageCount = 300
            if st == .read { b.finishedAt = .now.adding(days: -20) }
            ctx.insert(b)
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
        return c
    }
}
