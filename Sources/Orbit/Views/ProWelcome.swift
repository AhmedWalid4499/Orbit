import SwiftUI

/// Shown once, the first time Joshu Pro is on for an account (bought, or given from the admin page):
/// a welcome, what's now unlocked, and a name for the assistant.
struct ProWelcome: View {
    var onDone: () -> Void = {}
    @AppStorage("assistantName") private var assistantName = "Joshu"
    @State private var name = AssistantName.current
    @State private var shown = false

    private let unlocked: [(String, String, String, Color)] = [
        ("sparkles", "Your own assistant", "Ask, plan, write and code, by voice or text", Theme.lime),
        ("sun.max.fill", "Morning brief", "What matters today, ready when you wake up", Theme.peach),
        ("envelope.fill", "Email summaries", "What needs a reply, and what can wait", Theme.pink),
        ("chart.line.uptrend.xyaxis", "Money coach", "Where your money goes, and how to keep more", Theme.mint),
        ("waveform", "Hands-free", "Just say “Hey” and its name", Theme.cyan),
        ("briefcase.fill", "LinkedIn job alerts", "Every alert, laid out job by job", Theme.lavender),
    ]

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            GeometryReader { g in
                ZStack {
                    Circle().fill(Theme.lime.opacity(0.5)).frame(width: g.size.width * 0.7).blur(radius: 90)
                        .offset(x: -g.size.width * 0.3, y: -g.size.height * 0.35)
                    Circle().fill(Theme.purple.opacity(0.35)).frame(width: g.size.width * 0.6).blur(radius: 100)
                        .offset(x: g.size.width * 0.35, y: -g.size.height * 0.1)
                    Circle().fill(Theme.cyan.opacity(0.3)).frame(width: g.size.width * 0.5).blur(radius: 90)
                        .offset(x: 0, y: g.size.height * 0.45)
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .ignoresSafeArea().allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 26) {
                    orb.padding(.top, Platform.isPhone ? 30 : 10)
                    VStack(spacing: 10) {
                        Text("Welcome to Joshu Pro").font(Theme.display(Platform.isPhone ? 34 : 40)).multilineTextAlignment(.center)
                        Text("Your assistant is ready. Everything below is now on, on your Mac and iPhone.")
                            .font(Theme.ui(16)).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 10)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Platform.isPhone ? 150 : 200), spacing: 12)], spacing: 12) {
                        ForEach(Array(unlocked.enumerated()), id: \.offset) { i, item in
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: item.0).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.stickerInk)
                                    .frame(width: 32, height: 32).background(Circle().fill(item.3))
                                Text(item.1).font(Theme.ui(15, weight: .semibold))
                                Text(item.2).font(Theme.ui(12.5)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card.opacity(0.9)))
                            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.25 + Double(i) * 0.06), value: shown)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What would you like to call your assistant?").font(Theme.ui(14, weight: .semibold))
                        TextField("Joshu", text: $name)
                            .textFieldStyle(.plain).font(Theme.ui(17, weight: .medium))
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                            .onSubmit(start)
                        Text("You can change it any time in Settings.").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                    }
                    .frame(maxWidth: 420)

                    Text("Your assistant works by sending what each request needs (your message, and the parts of your day, money, notes or email it's about) to Anthropic's Claude AI. It isn't used to train their models.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460)
                    VStack(spacing: 10) {
                        Button(action: start) {
                            Text("Allow and say hello to \(trimmedName)").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 420).keyboardShortcut(.defaultAction)
                        Button("Maybe later") { finish(openAssistant: false) }.buttonStyle(.orbitLink).font(Theme.ui(14))
                    }
                }
                .padding(.horizontal, Platform.isPhone ? 22 : 44).padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
        .sheetFrame(width: 760, height: 780)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { shown = true } }
    }

    /// The Joshu Pro logo, with a glow in the orb's colours behind it.
    private var orb: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [Color(hex: 0xC6F432), Color(hex: 0x3DDC97), Color(hex: 0x22D3EE), Color(hex: 0x8B7CF6),
                                               Color(hex: 0xF472B6), Color(hex: 0xC6F432)], center: .center))
                .frame(width: 170, height: 170).blur(radius: 34).opacity(0.7)
            ProLogo(size: 112)
        }
        .scaleEffect(shown ? 1 : 0.6)
        .animation(.spring(response: 0.6, dampingFraction: 0.6), value: shown)
    }

    private var trimmedName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Joshu" : n
    }

    private func start() { AIConsent.shared.answer(true); finish(openAssistant: true) }

    private func finish(openAssistant: Bool) {
        assistantName = trimmedName
        Pro.shared.welcomeDone()
        onDone()
        if openAssistant {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                AppState.current?.openAssistant(with: nil)
            }
        }
    }
}
