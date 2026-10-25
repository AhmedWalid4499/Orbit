import SwiftUI

/// Shows voice mode over the window. Kept in its own small view so the rest of the app doesn't redraw while the
/// microphone is listening.
struct VoiceOrbHost: View {
    @ObservedObject private var wake = WakeListener.shared
    var body: some View {
        ZStack {
            if wake.inConversation { VoiceOrbView().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.25), value: wake.inConversation)
    }
}

/// Voice mode: the assistant's orb in the middle of the screen. It pulses with your voice while it listens,
/// swirls while it thinks and moves with its words while it answers. Say "stop" or tap ✕ to end.
struct VoiceOrbView: View {
    @ObservedObject private var wake = WakeListener.shared
    @ObservedObject private var store = AssistantStore.shared
    @ObservedObject private var speaker = Speaker.shared

    private enum Phase { case listening, thinking, speaking }
    private var phase: Phase { speaker.speaking ? .speaking : store.busy ? .thinking : .listening }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Theme.canvas.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                orb
                    .onTapGesture { wake.interrupt() }
                    .accessibilityLabel(phase == .speaking ? "Stop talking" : AssistantName.current)
                caption
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 28)
                    .animation(.easeOut(duration: 0.2), value: phase)
                Spacer()
                VStack(spacing: 10) {
                    Button { withAnimation(.easeOut(duration: 0.25)) { wake.endConversation() } } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
                            .frame(width: 56, height: 56).background(Circle().fill(Theme.card))
                            .overlay(Circle().strokeBorder(Theme.line))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("End conversation")
                    Text(phase == .speaking ? "Tap the orb to interrupt · say “stop” to end" : "Say “stop” or tap ✕ to end")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: Orb

    private var orb: some View {
        TimelineView(.animation) { t in
            let time = t.date.timeIntervalSinceReferenceDate
            let size: CGFloat = Platform.isPhone ? 200 : 230
            ZStack {
                switch phase {
                case .listening:
                    // Rings ripple out, and the orb swells with your voice.
                    ForEach(0..<3, id: \.self) { i in
                        let p = (time * 0.55 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle().strokeBorder(glow.opacity(0.55 * (1 - p)), lineWidth: 2)
                            .frame(width: size * (1 + p * 0.75), height: size * (1 + p * 0.75))
                    }
                case .thinking:
                    // A comet circling the orb.
                    Circle().trim(from: 0, to: 0.28)
                        .stroke(AngularGradient(colors: [glow.opacity(0), glow], center: .center), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: size * 1.28, height: size * 1.28)
                        .rotationEffect(.degrees(time * 220))
                case .speaking:
                    // A soft halo that breathes with the words.
                    Circle().fill(RadialGradient(colors: [glow.opacity(0.45), glow.opacity(0)], center: .center, startRadius: size * 0.3, endRadius: size * 0.95))
                        .frame(width: size * 1.9, height: size * 1.9)
                        .scaleEffect(1 + 0.08 * CGFloat(abs(sin(time * 5.3))))
                }
                AssistantAvatar(size: size, busy: phase != .listening)
                    .scaleEffect(scale(time))
                    .shadow(color: glow.opacity(0.45), radius: 30)
            }
            .frame(width: size * 1.9, height: size * 1.9)
        }
        .animation(.easeOut(duration: 0.12), value: wake.level)
    }

    private var glow: Color { phase == .thinking ? Theme.purple : phase == .speaking ? Theme.cyan : Theme.lime }

    private func scale(_ time: Double) -> CGFloat {
        switch phase {
        case .listening: 1 + CGFloat(wake.level) * 0.22 + 0.015 * CGFloat(sin(time * 2))
        case .thinking: 1 + 0.04 * CGFloat(sin(time * 3))
        // Two waves together so it moves like speech rather than a metronome.
        case .speaking: 1 + 0.035 * CGFloat(sin(time * 9)) + 0.025 * CGFloat(sin(time * 13.7))
        }
    }

    // MARK: Words

    @ViewBuilder private var caption: some View {
        VStack(spacing: 10) {
            switch phase {
            case .listening:
                Text(wake.heard.isEmpty ? "Listening…" : wake.heard)
                    .font(Theme.display(wake.heard.isEmpty ? 26 : 24))
                    .foregroundStyle(wake.heard.isEmpty ? Theme.inkSecondary : Theme.ink)
                    .multilineTextAlignment(.center).lineLimit(4)
                if wake.heard.isEmpty {
                    Text("Ask \(AssistantName.current) anything").font(Theme.ui(14)).foregroundStyle(Theme.inkMuted)
                }
            case .thinking:
                if !wake.lastQuestion.isEmpty {
                    Text("“\(wake.lastQuestion)”").font(Theme.ui(15)).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center).lineLimit(3)
                }
                Text("Thinking…").font(Theme.display(24)).foregroundStyle(Theme.ink)
            case .speaking:
                Text(Speaker.plain(answer)).font(Theme.ui(18, weight: .medium)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center).lineLimit(6).lineSpacing(3)
            }
            if let e = store.error ?? wake.error {
                Text(e).font(Theme.ui(12)).foregroundStyle(Theme.orange).multilineTextAlignment(.center)
            }
        }
    }

    /// The reply being said: the live text while it's written, then the finished message.
    private var answer: String {
        if !store.revealed.isEmpty { return store.revealed }
        return store.items.last(where: { $0.role == .assistant })?.text ?? ""
    }
}
