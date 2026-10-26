import SwiftUI
import WatchConnectivity
import AVFoundation
import WidgetKit

/// Orbit on Apple Watch. It shows the day your iPhone sends over and asks the iPhone to do things,
/// so all your data, sync and your assistant stay on the phone.
@main
struct OrbitWatchApp: App {
    @StateObject private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRoot().environmentObject(store)
        }
    }
}

@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()

    @Published private(set) var snapshot: WatchSnapshot?
    @Published var toast: String?
    @Published private(set) var reachable = false
    /// Things ticked off here that the iPhone hasn't confirmed yet, so the list updates straight away.
    @Published var pendingDone: Set<String> = []
    @Published var pendingHabits: Set<String> = []

    private let cacheKey = "watchSnapshot"
    static let groupID = "group.com.ahmedwalid.orbit"

    override private init() {
        super.init()
        snapshot = WatchSnapshot.from(UserDefaults.standard.data(forKey: cacheKey))
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func refresh() { send(WatchAction(kind: .refresh), quiet: true) }

    /// Sends an action. With the iPhone in reach the reply comes back at once; otherwise it's queued and runs
    /// as soon as the watch and phone reconnect (asking your assistant needs the phone in reach).
    func send(_ action: WatchAction, quiet: Bool = false, onReply: ((String) -> Void)? = nil) {
        guard let data = action.data else { return }
        let session = WCSession.default
        if session.activationState == .activated, session.isReachable {
            session.sendMessage([WatchAction.messageKey: data], replyHandler: { reply in
                let text = reply[WatchAction.replyKey] as? String ?? "Done."
                Task { @MainActor in
                    if let onReply { onReply(text) } else if !quiet { self.flash(text) }
                }
            }, errorHandler: { error in
                Task { @MainActor in
                    if action.kind == .ask { onReply?("Couldn't reach your iPhone. Try again in a moment.") }
                    else { session.transferUserInfo([WatchAction.messageKey: data]); if !quiet { self.flash("Saved. It'll sync with your iPhone.") } }
                }
            })
        } else if action.kind == .ask {
            onReply?("Your iPhone is out of reach. Keep it nearby to ask \(snapshot?.assistantName ?? "Joshu").")
        } else if action.kind != .refresh {
            session.transferUserInfo([WatchAction.messageKey: data])
            if !quiet { flash("Saved. It'll sync when your iPhone is nearby.") }
        }
    }

    func flash(_ text: String) {
        withAnimation { toast = text }
        Task { try? await Task.sleep(for: .seconds(2.5)); withAnimation { if self.toast == text { self.toast = nil } } }
    }

    private func apply(_ data: Data?) {
        guard let snap = WatchSnapshot.from(data) else { return }
        snapshot = snap
        pendingDone = pendingDone.filter { id in snap.tasks.contains { $0.id == id } }
        pendingHabits = []
        UserDefaults.standard.set(data, forKey: cacheKey)
        // The watch face complications read the same snapshot.
        UserDefaults(suiteName: Self.groupID)?.set(data, forKey: cacheKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext[WatchSnapshot.contextKey] as? Data
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            if let context { self.apply(context) }
            self.refresh()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let data = context[WatchSnapshot.contextKey] as? Data
        Task { @MainActor in self.apply(data) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable; if reachable { self.refresh() } }
    }
}

/// Reads your assistant's replies aloud on the watch.
@MainActor
enum WatchVoice {
    private static let synth = AVSpeechSynthesizer()
    static func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        u.voice = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }.max { $0.quality.rawValue < $1.quality.rawValue }
        synth.speak(u)
    }
    static func stop() { synth.stopSpeaking(at: .immediate) }
}
