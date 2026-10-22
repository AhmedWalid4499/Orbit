import SwiftUI
import AVFoundation

/// Launch splash: the lime dot from the logo circles the word "orbit" with a little chime, then the window fades in.
struct SplashView: View {
    /// A fixed angle (radians) for screenshots; nil animates.
    var angle: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date.now

    /// Seconds per lap.
    static let lap = 1.1

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if let angle {
                orbit(angle)
            } else if reduceMotion {
                orbit(.pi / 2)
            } else {
                TimelineView(.animation) { ctx in
                    // Start on the near side, at the right, and go anticlockwise as seen from above.
                    orbit(ctx.date.timeIntervalSince(startedAt) / Self.lap * 2 * .pi + .pi / 4)
                }
            }
        }
    }

    private func orbit(_ theta: Double) -> some View {
        let word = CGSize(width: 290, height: 110)
        let rx = word.width * 0.62, ry = word.height * 0.42
        // sin > 0 is the near half (in front of the word).
        let depth: Double = sin(theta)
        let near: Double = (depth + 1) / 2
        let tilt: Double = -10.0 * .pi / 180
        let x0: Double = rx * cos(theta)
        let y0: Double = ry * depth
        let x: Double = x0 * cos(tilt) - y0 * sin(tilt)
        let y: Double = x0 * sin(tilt) + y0 * cos(tilt)
        let dot = Circle().fill(Theme.lime)
            .frame(width: 22, height: 22)
            .scaleEffect(0.8 + 0.25 * near)
            .opacity(0.75 + 0.25 * near)
            .shadow(color: Theme.lime.opacity(0.6), radius: depth > 0 ? 10 : 4)
            .offset(x: x, y: y)
        return ZStack {
            if depth <= 0 { dot }
            Text("orbit")
                .font(.system(size: 104, weight: .black, design: .rounded))
                .tracking(-3)
                .foregroundStyle(Theme.ink)
            if depth > 0 { dot }
        }
        .frame(width: word.width * 1.6, height: word.height * 1.6)
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
                    .onAppear { if UserDefaults.standard.object(forKey: "launchSound") as? Bool ?? true { LaunchChime.play() } }
                    .task {
                        try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 1.7))
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
