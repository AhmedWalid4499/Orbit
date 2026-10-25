import Foundation
#if os(macOS)
import AppKit
#endif

/// On the Mac the assistant can see the page you have open in Chrome (or Safari) to help with it.
@MainActor
enum Browser {
    static let chromeID = "com.google.Chrome"

    struct Tab { var title: String; var url: String; var text: String }

    /// The tab you're looking at in Chrome (or Safari): its title, link and, when the browser allows it, the page's text.
    /// Mac only; macOS asks you once to let Orbit control Chrome.
    static func currentTab() async -> Result<Tab, BrowserError> {
        #if os(macOS)
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let app: String
        if running.contains(chromeID) { app = "Google Chrome" }
        else if running.contains("com.apple.Safari") { app = "Safari" }
        else { return .failure(BrowserError("Chrome isn't open.")) }
        let isChrome = app == "Google Chrome"
        let tabRef = isChrome ? "active tab of front window" : "current tab of front window"
        let info = isChrome
            ? "tell application \"Google Chrome\" to if (count of windows) > 0 then return (title of active tab of front window) & \"\n\" & (URL of active tab of front window)"
            : "tell application \"Safari\" to if (count of windows) > 0 then return (name of current tab of front window) & \"\n\" & (URL of current tab of front window)"
        guard let head = await run(info) else {
            return .failure(BrowserError("Orbit isn't allowed to see \(app) yet. Allow it in System Settings › Privacy & Security › Automation › Orbit › \(app)."))
        }
        let parts = head.components(separatedBy: "\n")
        guard parts.count >= 2 else { return .failure(BrowserError("\(app) has no window open.")) }
        // The page's text needs Chrome's View › Developer › Allow JavaScript from Apple Events; without it, the link is enough.
        let js = isChrome
            ? "tell application \"Google Chrome\" to execute \(tabRef) javascript \"document.body.innerText.slice(0, 60000)\""
            : "tell application \"Safari\" to do JavaScript \"document.body.innerText.slice(0, 60000)\" in \(tabRef)"
        let text = await run(js) ?? ""
        return .success(Tab(title: parts[0], url: parts[1], text: text))
        #else
        return .failure(BrowserError("Reading your browser tab only works on the Mac."))
        #endif
    }

    #if os(macOS)
    /// Runs AppleScript off the main thread; nil when it fails (not allowed, no window…).
    private static func run(_ source: String) async -> String? {
        await Task.detached {
            var error: NSDictionary?
            let out = NSAppleScript(source: source)?.executeAndReturnError(&error)
            return error == nil ? out?.stringValue : nil
        }.value
    }
    #endif
}

struct BrowserError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
