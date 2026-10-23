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
        Keychain.warmUp()
        if UserDefaults.standard.string(forKey: "currencyCode") == nil {
            UserDefaults.standard.set(Fmt.currencyCode, forKey: "currencyCode")
        }
        if Snapshot.isActive {
            container = Snapshot.demoContainer()
        } else {
            let url = URL.applicationSupportDirectory.appending(path: "Orbit", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let schema = OrbitSchema.schema
            do {
                container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url.appending(path: "Orbit.store")))
            } catch {
                fatalError("Could not open data store: \(error)")
            }
        }
        OrbitStore.container = container
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
