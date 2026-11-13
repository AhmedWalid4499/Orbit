import SwiftUI
import SwiftData

/// Orbit for iPhone. It shares the Mac app's models, sync, assistant and services (compiled from Sources/Orbit),
/// so everything stays linked through your Orbit account.
@main
struct OrbitPhoneApp: App {
    @StateObject private var state = AppState()
    @StateObject private var apple = AppleSync()
    let container: ModelContainer

    init() {
        Snapshot.applyDemoDefaults()
        // The tour is for new people; anyone already set up can open it from Settings › General.
        let d = UserDefaults.standard
        if d.object(forKey: "tourSeen") == nil && (d.bool(forKey: "phoneOnboarded") || CloudAuth.session != nil) {
            d.set(true, forKey: "tourSeen")
        }
        Keychain.warmUp()
        if UserDefaults.standard.string(forKey: "currencyCode") == nil {
            UserDefaults.standard.set(Fmt.currencyCode, forKey: "currencyCode")
        }
        if Snapshot.isActive {
            container = Snapshot.demoContainer()
        } else {
            let url = URL.applicationSupportDirectory.appending(path: "Orbit", directoryHint: .isDirectory)  // the data folder keeps its old name
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let schema = OrbitSchema.schema
            let store = url.appending(path: "Orbit.store")
            if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: store)) {
                container = c
            } else {
                // A store this version can't open (e.g. after a change SwiftData can't migrate): keep it aside and start
                // fresh rather than crashing on every launch; signed-in data comes back from sync.
                let aside = url.appending(path: "Orbit-\(Int(Date.now.timeIntervalSince1970)).store")
                for suffix in ["", "-shm", "-wal"] {
                    try? FileManager.default.moveItem(at: URL(fileURLWithPath: store.path + suffix), to: URL(fileURLWithPath: aside.path + suffix))
                }
                container = (try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: store)))
                    ?? (try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
            }
        }
        OrbitStore.container = container
        BookLibrary.cleanUpKindleIfNeeded(context: container.mainContext)
        WatchBridge.shared.activate()
        StopFocusIntent.handler = { FocusTimer.shared.stopFromLockScreen() }
        _ = Reminders.shared // become the notification delegate before launch ends, so a tap that opened the app is handled
    }

    var body: some Scene {
        WindowGroup {
            PhoneRoot()
                .environmentObject(state)
                .environmentObject(apple)
                .modifier(SplashOverlay())
        }
        .modelContainer(container)
    }
}
