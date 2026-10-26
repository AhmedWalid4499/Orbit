import SwiftUI
import AVFoundation

/// Launch splash: the assistant's orb drops in before the word "joshu", hops over it and lands at the end like a full
/// stop, with a little chime on landing. Then the window fades in.
struct SplashView: View {
    /// A fixed moment (seconds into the animation) for screenshots; nil animates.
    var time: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date.now
    @State private var wordWidth: CGFloat = 290

    /// When the orb touches down at the end of the word.
    static let landing = 1.25
    /// The whole animation, settle included.
    static let length = 1.55
    static let orb: CGFloat = 34

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if let time {
                frame(time)
            } else if reduceMotion {
                frame(Self.length)
            } else {
                TimelineView(.animation) { ctx in frame(ctx.date.timeIntervalSince(startedAt)) }
            }
        }
    }

    /// The orb's offset from its resting place after the word (x, y; negative y is up) and its squash, at time t.
    private func pose(_ t: Double) -> (x: Double, y: Double, sx: Double, sy: Double, spin: Double) {
        let startX = -Double(wordWidth + Self.orb * 0.9)
        func ease(_ v: Double) -> Double { v * v * (3 - 2 * v) }
        switch t {
        case ..<0.32:  // falls in from above, before the "j"
            let p = max(t, 0) / 0.32
            return (startX, -170 * (1 - p * p), 1, 1, 0)
        case ..<0.42:  // squashes on touching down
            let p = (t - 0.32) / 0.1
            let k = sin(p * .pi)
            return (startX, 0, 1 + 0.22 * k, 1 - 0.25 * k, 0)
        case ..<Self.landing:  // one big hop over the word
            let p = (t - 0.42) / (Self.landing - 0.42)
            let x = startX * (1 - ease(p))
            let y = -160 * 4 * p * (1 - p)
            let stretch = 0.12 * sin(p * .pi)
            return (x, y, 1 - stretch, 1 + stretch, 360 * ease(p))
        case ..<(Self.landing + 0.12):  // lands: squash
            let k = sin((t - Self.landing) / 0.12 * .pi)
            return (0, 0, 1 + 0.28 * k, 1 - 0.3 * k, 360)
        case ..<Self.length:  // a small settling bounce
            let p = (t - Self.landing - 0.12) / (Self.length - Self.landing - 0.12)
            return (0, -16 * 4 * p * (1 - p), 1, 1, 360)
        default:
            return (0, 0, 1, 1, 360)
        }
    }

    private func frame(_ t: Double) -> some View {
        let p = pose(t)
        return HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("joshu")
                .font(.system(size: 104, weight: .black, design: .rounded))
                .tracking(-3)
                .foregroundStyle(Theme.ink)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { wordWidth = $0 }
            AssistantAvatar(size: Self.orb)
                .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
                .rotationEffect(.degrees(p.spin))
                .scaleEffect(x: p.sx, y: p.sy, anchor: .bottom)
                .shadow(color: Theme.lime.opacity(0.5), radius: p.y < -20 ? 14 : 6, y: 3)
                .offset(x: p.x, y: p.y)
        }
        .offset(x: -Self.orb / 2)
    }
}

/// Shows the splash over the window at launch, then fades it away.
struct SplashOverlay: ViewModifier {
    @State private var visible = !Snapshot.isActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if visible {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .task {
                        let sound = UserDefaults.standard.object(forKey: "launchSound") as? Bool ?? true
                        if !reduceMotion { try? await Task.sleep(for: .seconds(SplashView.landing)) }
                        if sound { LaunchChime.play() }
                        try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : SplashView.length - SplashView.landing + 0.45))
                        withAnimation(.easeOut(duration: 0.35)) { visible = false }
                    }
            }
        }
    }
}

/// A short, soft three-note chime, synthesised so there's no sound file to ship.
@MainActor
enum LaunchChime {
    private static var player: AVAudioPlayer?

    static func play() {
        guard !Snapshot.isActive else { return }
        player = try? AVAudioPlayer(data: wav())
        player?.volume = 0.35
        player?.play()
    }

    /// G5, C6, E6 bell tones that overlap a little, as 16-bit mono WAV.
    static func wav() -> Data {
        let rate = 44_100.0
        let notes: [(freq: Double, start: Double)] = [(783.99, 0), (1046.5, 0.09), (1318.5, 0.18)]
        let length = Int(rate * 0.9)
        var samples = [Double](repeating: 0, count: length)
        for n in notes {
            let s0 = Int(n.start * rate)
            for i in s0..<length {
                let t = Double(i - s0) / rate
                let attack = min(1, t / 0.006)
                let env = attack * exp(-t * 7)
                // A touch of the octave makes it bell-like rather than a plain beep.
                samples[i] += env * (sin(2 * .pi * n.freq * t) + 0.25 * sin(4 * .pi * n.freq * t)) * 0.28
            }
        }
        var pcm = Data(capacity: length * 2)
        for v in samples {
            var x = Int16(max(-1, min(1, v)) * 32_000).littleEndian
            withUnsafeBytes(of: &x) { pcm.append(contentsOf: $0) }
        }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var d = Data("RIFF".utf8); d += le32(UInt32(36 + pcm.count)); d += Data("WAVEfmt ".utf8)
        d += le32(16); d += le16(1); d += le16(1); d += le32(UInt32(rate)); d += le32(UInt32(rate) * 2); d += le16(2); d += le16(16)
        d += Data("data".utf8); d += le32(UInt32(pcm.count)); d += pcm
        return d
    }
}
