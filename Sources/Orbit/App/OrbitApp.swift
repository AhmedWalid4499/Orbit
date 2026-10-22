import SwiftUI
import SwiftData
import AppKit

enum Tab: String, CaseIterable, Identifiable {
    case today, calendar, tasks, habits, bucket, money, notes, reading, documents, github
    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes:
            return "Journal & Notes"
        case .reading:
            let first = (UserDefaults.standard.string(forKey: "userName") ?? NSFullUserName())
                .split(separator: " ").first.map(String.init) ?? ""
            return first.isEmpty ? "Reading" : "\(first)'s Reading"
        case .github:
            return "GitHub"
        case .bucket:
            return "Bucket list"
        case .documents:
            return "Documents"
        default:
            return rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .habits: "flame.fill"
        case .money: "creditcard.fill"
        case .notes: "book.pages.fill"
        case .reading: "books.vertical.fill"
        case .bucket: "mountain.2.fill"
        case .documents: "doc.text.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Nav groups: day, plan, life.
    static let groups: [[Tab]] = [[.today], [.calendar, .tasks, .habits, .bucket], [.money, .notes, .reading, .documents, .github]]

    /// ⌘1…⌘9 for the first nine tabs (there's no ⌘10).
    var shortcutNumber: Int? { let i = Tab.allCases.firstIndex(of: self)! + 1; return i <= 9 ? i : nil }
}

@MainActor
final class AppState: ObservableObject {
    /// The window's state, for things that start outside a view (voice capture, notifications).
    static weak var current: AppState?
    init() { if AppState.current == nil { AppState.current = self } }

    @Published var tab: Tab = .today
    @Published var searchOpen = false
    @Published var settingsOpen = false
    @Published var openTodayJournal = false
    @Published var assistantOpen = false
    @Published var reviewOpen = false
    @Published var cardOpen = false
    @Published var planOpen = false
    /// A message to send as soon as the assistant opens (e.g. from "Discuss with Claude").
    @Published var assistantSeed: String?

    func openAssistant(with message: String? = nil) {
        assistantSeed = message
        assistantOpen = true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?

    /// Sign-in callbacks (com.personal.orbit://auth-callback?code=…) go straight to the account code, without opening a new window.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: string) else { return }
        Task { @MainActor in
            // Widgets open com.personal.orbit://open/<tab>; sign-in uses com.personal.orbit://auth-callback.
            if url.host == "open" {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                Reminders.shared.route = url.lastPathComponent
            } else {
                CloudAuth.handleCallback(url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIcon.make()
        // ⌥Space: a quick tap opens quick capture; holding it records your voice and Ask files what you said.
        hotKey = HotKey(onPress: { VoiceCapture.shared.keyDown() }, onRelease: { VoiceCapture.shared.keyUp() })
        _ = Reminders.shared // become the notification delegate before any notification is tapped
        // Testing hook: ORBIT_AUTO_UPDATE=1 installs any newer release without clicking.
        if ProcessInfo.processInfo.environment["ORBIT_AUTO_UPDATE"] != nil {
            Task { @MainActor in
                await Updater.shared.check(userInitiated: true)
                if Updater.shared.available != nil { await Updater.shared.install() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
}

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()
    @StateObject private var apple = AppleSync()

    let container: ModelContainer

    init() {
        Keychain.warmUp()
        // People who used Orbit before the welcome screen existed skip it.
        if UserDefaults.standard.bool(forKey: "didSeedSampleData") || Keychain.apiKey != nil {
            UserDefaults.standard.set(true, forKey: "onboarded")
        }
        // Store the currency and name explicitly (not just implied by this Mac's region), so they sync to other devices.
        if UserDefaults.standard.string(forKey: "currencyCode") == nil {
            UserDefaults.standard.set(Fmt.currencyCode, forKey: "currencyCode")
        }
        if UserDefaults.standard.string(forKey: "userName") == nil {
            UserDefaults.standard.set(NSFullUserName(), forKey: "userName")
        }
        let schema = Schema([TaskItem.self, EventItem.self, Habit.self, Transaction.self, Note.self, Book.self, BookCategory.self, BucketItem.self, ReadingSession.self, Highlight.self, Subscription.self, DocItem.self, FocusSession.self, DayPlan.self, Trip.self, Booking.self])
        let url = URL.applicationSupportDirectory.appending(path: "Orbit", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: url.appending(path: "Orbit.store"))
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open data store: \(error)")
        }
        CapturePanel.shared.container = container
        BookLibrary.migrateLibrariesIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup("Orbit", id: "main") {
            RootView()
                .environmentObject(state)
                .environmentObject(apple)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear {
                    Snapshot.runIfRequested(container: container, apple: apple)
                    SyncTest.runIfRequested()
                }
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await Updater.shared.checkAndReport() } }
            }
            CommandGroup(after: .newItem) {
                Button("Quick Capture") { CapturePanel.shared.show() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Search") { state.searchOpen = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Ask Claude") { state.assistantOpen.toggle() }
                    .keyboardShortcut("j", modifiers: .command)
            }
            CommandMenu("Go") {
                ForEach(Tab.allCases) { tab in
                    if let n = tab.shortcutNumber {
                        Button(tab.title) { state.tab = tab }.keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                    } else {
                        Button(tab.title) { state.tab = tab }
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(apple)
                .modelContainer(container)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .environmentObject(apple)
                .modelContainer(container)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Draws the app icon at runtime: black squircle with a lime orbit.
enum AppIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 40, dy: 40)
            NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1).setFill()
            NSBezierPath(roundedRect: inset, xRadius: 96, yRadius: 96).fill()
            let ring = NSBezierPath(ovalIn: inset.insetBy(dx: 88, dy: 88))
            ring.lineWidth = 34
            NSColor(srgbRed: 0.90, green: 1.0, blue: 0.12, alpha: 1).setStroke()
            ring.stroke()
            NSColor(srgbRed: 0.97, green: 0.76, blue: 0.93, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: inset.maxX - 150, y: inset.maxY - 150, width: 70, height: 70)).fill()
            return true
        }
    }
}
