import SwiftUI

/// Before anything goes to the AI (Anthropic's Claude), the person says yes once (Apple requires it for apps that
/// send personal data to a third-party AI). The answer is a synced setting, so it's asked once per account.
@MainActor
final class AIConsent: ObservableObject {
    static let shared = AIConsent()
    nonisolated static let key = "ai.consent"

    nonisolated static var granted: Bool { UserDefaults.standard.bool(forKey: key) || Snapshot.isActive }

    /// Showing the question.
    @Published private(set) var asking = false
    private var askedThisLaunch = false

    /// Asks, unless they already said yes. Background features ask at most once per launch; something the person
    /// just did (sending a message) asks again (`force`).
    nonisolated static func ask(force: Bool = false) {
        Task { @MainActor in
            guard !granted, force || !shared.askedThisLaunch else { return }
            shared.askedThisLaunch = true
            shared.asking = true
        }
    }

    func answer(_ yes: Bool) {
        if yes { UserDefaults.standard.set(true, forKey: Self.key) }
        asking = false
    }
}

/// The question itself.
struct AIConsentSheet: View {
    @ObservedObject private var consent = AIConsent.shared

    private let shared: [(String, String)] = [
        ("text.bubble.fill", "What you ask or say to your assistant, and files you give it"),
        ("calendar", "The parts of your day it needs: events, tasks, habits, money, notes or reading"),
        ("envelope.fill", "Emails being summarised, if you connect Gmail"),
        ("heart.fill", "A short Health summary (steps, sleep, workouts) in your morning brief, if you connect Apple Health"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AssistantAvatar(size: 52)
                Text("Before your assistant starts").font(Theme.display(Platform.isPhone ? 26 : 28)).fixedSize(horizontal: false, vertical: true)
            }
            Text("To answer you, Joshu sends what each request needs to Anthropic's Claude AI:")
                .font(Theme.ui(15)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(shared, id: \.1) { symbol, text in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.stickerInk)
                            .frame(width: 26, height: 26).background(Circle().fill(Theme.lime))
                        Text(text).font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true).padding(.top, 3)
                    }
                }
            }
            Text("Only when you use an AI feature. Anthropic doesn't use it to train its models, and Joshu's server doesn't keep it.")
                .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            Link("Privacy policy", destination: URL(string: "https://ahmedwalid4499.github.io/Orbit/privacy/")!)
                .font(Theme.ui(13, weight: .semibold))
            HStack(spacing: 10) {
                Button("Not now") { consent.answer(false) }.buttonStyle(SoftButtonStyle())
                Button("Allow") { consent.answer(true) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(Platform.isPhone ? 24 : 30)
        .sheetFrame(width: 480)
        .interactiveDismissDisabled()
    }
}
