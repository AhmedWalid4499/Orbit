import SwiftUI

/// Launch splash: the lime dot from the logo orbits the word "orbit", then the window fades in.
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
            Ellipse().stroke(Theme.ink.opacity(0.12), lineWidth: 1.5)
                .frame(width: rx * 2, height: ry * 2)
                .rotationEffect(.radians(tilt))
            if depth <= 0 { dot }
            Text("orbit")
                .font(.system(size: 104, weight: .black, design: .rounded))
                .tracking(-3)
                .foregroundStyle(Theme.ink)
            // The near half of the track crosses in front of the letters.
            Ellipse().trim(from: 0, to: 0.5).stroke(Theme.ink.opacity(0.22), lineWidth: 1.5)
                .frame(width: rx * 2, height: ry * 2)
                .rotationEffect(.radians(tilt))
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
                    .task {
                        try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 1.7))
                        withAnimation(.easeOut(duration: 0.35)) { visible = false }
                    }
            }
        }
    }
}
