import SwiftUI
import SwiftData
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?

    /// Sign-in callbacks (com.personal.orbit://auth-callback?code=…) go straight to the account code, without opening a new window.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        reclaimLinkScheme()
    }

    /// Makes the installed Orbit the app that opens com.personal.orbit:// links again, if something else took them
    /// (the Windows version's Electron build does when it's run on this Mac). Only the copy in Applications does this.
    private func reclaimLinkScheme() {
        guard !Snapshot.isActive, Bundle.main.bundlePath.hasPrefix("/Applications/"),
              let probe = URL(string: "com.personal.orbit://check") else { return }
        if NSWorkspace.shared.urlForApplication(toOpen: probe)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL { return }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "com.personal.orbit") { _ in }
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

    static func fitWindowsToScreen() {
        for w in NSApp.windows where w.canBecomeMain && w.isVisible && !w.styleMask.contains(.fullScreen) {
            guard let visible = (w.screen ?? NSScreen.main)?.visibleFrame else { continue }
            var f = w.frame
            f.size.width = min(f.width, visible.width)
            f.size.height = min(f.height, visible.height)
            f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
            f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
            if f != w.frame { w.setFrame(f, display: true, animate: false) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIcon.make()
        // ⌥Space: a quick tap opens quick capture; holding it records your voice and Ask files what you said.
        hotKey = HotKey(onPress: { VoiceCapture.shared.keyDown() }, onRelease: { VoiceCapture.shared.keyUp() })
        _ = Reminders.shared // become the notification delegate before any notification is tapped
        // The window is never taller than the screen (or its top, with the tabs, would sit above the edge).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Self.fitWindowsToScreen() }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Self.fitWindowsToScreen() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Self.fitWindowsToScreen() }
        }
        // Testing hook: `-windowHeight 600` resizes the main window, to check small screens.
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-windowHeight"), i + 1 < ProcessInfo.processInfo.arguments.count,
           let h = Double(ProcessInfo.processInfo.arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if let w = NSApp.windows.first(where: { $0.canBecomeMain }) { var f = w.frame; f.size.height = h; w.setFrame(f, display: true) }
            }
        }
        // Testing hook: `-fullscreen` opens the main window in full screen.
        if ProcessInfo.processInfo.arguments.contains("-fullscreen") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.windows.first { $0.canBecomeMain }?.toggleFullScreen(nil) }
        }
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
        Snapshot.applyDemoDefaults()
        Keychain.warmUp()
        // People who used Orbit before the welcome screen existed skip it.
        if UserDefaults.standard.bool(forKey: "didSeedSampleData") || Keychain.apiKey != nil {
            UserDefaults.standard.set(true, forKey: "onboarded")
        }
        // The tour is for new people; anyone already set up can open it from Orbit › Take the Tour.
        if UserDefaults.standard.bool(forKey: "onboarded") && UserDefaults.standard.object(forKey: "tourSeen") == nil {
            UserDefaults.standard.set(true, forKey: "tourSeen")
        }
        // Store the currency and name explicitly (not just implied by this Mac's region), so they sync to other devices.
        if UserDefaults.standard.string(forKey: "currencyCode") == nil {
            UserDefaults.standard.set(Fmt.currencyCode, forKey: "currencyCode")
        }
        if UserDefaults.standard.string(forKey: "userName") == nil {
            UserDefaults.standard.set(NSFullUserName(), forKey: "userName")
        }
        let schema = OrbitSchema.schema
        let url = URL.applicationSupportDirectory.appending(path: "Orbit", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: url.appending(path: "Orbit.store"))
        if Snapshot.isDemo {
            container = Snapshot.demoContainer()   // `-demo`: sample data in memory, your store isn't opened
        } else {
            do {
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Could not open data store: \(error)")
            }
        }
        CapturePanel.shared.container = container
        OrbitStore.container = container
        BookLibrary.migrateLibrariesIfNeeded(context: container.mainContext)
        BookLibrary.cleanUpKindleIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup("Orbit", id: "main") {
            RootView()
                .environmentObject(state)
                .environmentObject(apple)
                .frame(minWidth: 1180, minHeight: 640)
                .onAppear {
                    Snapshot.runIfRequested(container: container, apple: apple)
                    SyncTest.runIfRequested()
                    AITest.runIfRequested(apple: apple)
                    BankTest.runIfRequested()
                    AskTest.runIfRequested(apple: apple)
                    SmartsTest.runIfRequested()
                }
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await Updater.shared.checkAndReport() } }
                Button("Take the Tour…") { state.tourOpen = true }
            }
            CommandGroup(after: .newItem) {
                Button("Quick Capture") { CapturePanel.shared.show() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Search") { state.searchOpen = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Ask Claude") { state.toggleAssistant() }
                    .keyboardShortcut("j", modifiers: .command)
            }
            CommandMenu("Go") {
                ForEach(Tab.allCases.filter { !Tab.hidden.contains($0) }) { tab in
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
                .environmentObject(state)
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
