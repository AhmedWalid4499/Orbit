import Foundation
import SwiftData

/// When you open Orbit, the assistant says hello and reads you the day's brief out loud.
/// At most once an hour, so switching back and forth stays quiet; off in Settings › AI › Voice.
@MainActor
enum WelcomeVoice {
    static var isOn: Bool { UserDefaults.standard.object(forKey: "welcome.speak") as? Bool ?? true }
    private static var lastSpoken: Double {
        get { UserDefaults.standard.double(forKey: "welcome.lastSpoken") }
        set { UserDefaults.standard.set(newValue, forKey: "welcome.lastSpoken") }
    }

    static func greetIfDue(context: ModelContext, apple: AppleSync) async {
        let ai = AIAssistant.shared
        guard isOn, ai.hasKey, !Snapshot.isActive, Date.now.timeIntervalSince1970 - lastSpoken > 3600 else { return }
        lastSpoken = Date.now.timeIntervalSince1970
        if ai.morningBriefEnabled {
            await ai.refreshBrief(context: context, apple: apple)
            // The Today screen may be writing it already: wait for that (up to 40 s) rather than skip the brief.
            for _ in 0..<80 where ai.briefState == .loading { try? await Task.sleep(for: .milliseconds(500)) }
        }
        Speaker.shared.speak(script(ai.hasTodaysBrief ? ai.brief : nil), quiet: true)
    }

    static func script(_ brief: MorningBrief?) -> String {
        let h = Calendar.current.component(.hour, from: .now)
        let part = h < 5 ? "You're up late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        let first = Platform.userName.split(separator: " ").first.map(String.init) ?? ""
        var lines = ["\(part)\(first.isEmpty ? "" : ", \(first)"). Welcome back to Orbit."]
        guard let b = brief else { return (lines + ["Tap me whenever you need anything."]).joined(separator: " ") }
        lines.append("Here's your day. \(b.headline).")
        lines.append(b.summary)
        if !b.focus.isEmpty {
            let ordinals = ["First", "Then", "And"]
            lines.append("Your focus: " + b.focus.prefix(3).enumerated().map { "\(ordinals[$0.offset]), \($0.element)." }.joined(separator: " "))
        }
        if !b.heads_up.isEmpty { lines.append("One heads up: \(b.heads_up)") }
        return lines.joined(separator: " ")
    }
}
