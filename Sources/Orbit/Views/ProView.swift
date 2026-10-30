import SwiftUI

/// Joshu Pro: what you get, the two plans, restore, and the small print the App Store asks for.
struct ProSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pro = Pro.shared
    @ObservedObject private var cloud = CloudSync.shared
    @State private var plan = Pro.yearlyID

    /// Pro lives on your account (that's how the assistant reaches you on every device), so there's nothing to buy
    /// until you have one. Your own Anthropic key needs none.
    private var needsAccount: Bool { !cloud.isSignedIn && !pro.ownKey && !Snapshot.isActive }

    private var features: [(String, String, Color)] { [
        ("Your own AI assistant, named by you: ask anything, plan, write, code, by voice or text", "sparkles", Theme.lime),
        ("Morning brief and a summary of your day", "sun.max.fill", Theme.peach),
        ("Email summaries: what needs a reply, what matters", "envelope.fill", Theme.pink),
        ("Money coach and smart money insights", "chart.line.uptrend.xyaxis", Theme.mint),
        ("LinkedIn job alerts, read from your email", "briefcase.fill", Theme.cyan),
        ("Connect as many email accounts as you like", "tray.2.fill", Theme.lavender),
    ] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary).keyboardShortcut(.cancelAction)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ProLogo(size: 52)
                        Text("Joshu Pro").font(Theme.display(34))
                    }
                    Text(pro.isPro && !needsAccount ? "You're on Pro. Thanks for supporting Joshu." : "Everything in Joshu, plus your AI assistant and the smart features that save you time. No API keys, nothing to set up.")
                        .font(Theme.ui(15)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(features, id: \.0) { text, symbol, tint in
                        HStack(spacing: 12) {
                            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.stickerInk)
                                .frame(width: 32, height: 32).background(Circle().fill(tint))
                            Text(text).font(Theme.ui(14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if needsAccount {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("First, your free Joshu account").font(Theme.ui(16, weight: .semibold))
                        Text(pro.storeActive ? "Your subscription is active. Sign in or create an account to switch on your assistant."
                             : "Pro is tied to your account, so your assistant works on all your devices.")
                            .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        AuthPanel()
                    }
                } else if !pro.isPro {
                    VStack(spacing: 10) {
                        planButton(Pro.yearlyID, title: "Yearly", detail: "\(pro.price(Pro.yearlyID)) a year · save 37%")
                        planButton(Pro.monthlyID, title: "Monthly", detail: "\(pro.price(Pro.monthlyID)) a month")
                    }
                    Button { Task { await pro.buy(plan) } } label: {
                        Text(pro.busy ? "One moment…" : "Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(pro.busy)
                }
                if let m = pro.message { Text(m).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Free keeps everything else: tasks, calendar, habits, money, reading, ideas, notes, sync across your devices, and one email account.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    Text("Payment is charged to your Apple ID. The subscription renews automatically unless you cancel at least 24 hours before the end of the period; manage or cancel it in your App Store account settings. The assistant's use is fair-use limited.")
                        .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Button("Restore purchases") { Task { await pro.restore() } }
                        Link("Terms of Use", destination: URL(string: "https://ahmedwalid4499.github.io/Orbit/terms/")!)
                        Link("Privacy", destination: URL(string: "https://ahmedwalid4499.github.io/Orbit/privacy/")!)
                    }
                    .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(28)
        }
        .sheetFrame(width: 520, height: 760)
        .task { await pro.refresh() }
    }

    private func planButton(_ id: String, title: String, detail: String) -> some View {
        let on = plan == id
        return Button { plan = id } label: {
            HStack {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 18)).foregroundStyle(on ? Theme.ink : Theme.inkMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.ui(15, weight: .semibold))
                    Text(detail).font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                if id == Pro.yearlyID { Text("Best value").font(Theme.ui(11, weight: .bold)).foregroundStyle(Theme.stickerInk)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.lime)) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Theme.ink : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Shown where a Pro feature would be, for Free accounts: what it is and a button to see Pro.
struct ProUpsell: View {
    let title: String
    let detail: String
    var compact = false

    var body: some View {
        HStack(spacing: 14) {
            ProLogo(size: compact ? 32 : 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.ui(compact ? 14 : 15, weight: .semibold))
                Text(detail).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Get Pro") { AppState.current?.openPro() }.buttonStyle(PrimaryButtonStyle()).fixedSize()
        }
        .padding(compact ? 12 : 16)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}

/// Settings: your plan, with a way to upgrade or manage it.
struct ProSettingsRow: View {
    @ObservedObject private var pro = Pro.shared

    var body: some View {
        HStack(spacing: 12) {
            ProLogo(size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(pro.isPro ? "Joshu Pro" : "Joshu Free").font(.headline)
                Text(pro.isPro ? (pro.ownKey && !pro.storeActive && !pro.serverActive ? "Using your own Anthropic key" : "\(AssistantName.current) and all smart features are on")
                     : "Upgrade for your AI assistant, briefs, email summaries and more").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if pro.storeActive {
                Link("Manage", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            } else if !pro.isPro {
                Button("See Pro") { AppState.current?.openPro() }.buttonStyle(.borderedProminent)
            }
        }
        .task { await pro.refresh() }
    }
}
