import SwiftUI

/// The Joshu Pro logo: the app icon's black "j" with the orb above it, on a tile in the orb's colours instead of
/// lime. Drawn from the icon's own shapes (1024-point design, see scripts/make-pro-logo.swift), so it's sharp at any size.
struct ProLogo: View {
    var size: CGFloat = 44
    /// A square, edge-to-edge tile with no shadow: the iPhone app icon (iOS rounds the corners itself).
    var square = false
    /// The everyday Joshu icon: the same j and orb on the lime tile.
    var classic = false

    private static let rainbow: [Color] = [Color(hex: 0xC6F432), Color(hex: 0x3DDC97), Color(hex: 0x22D3EE), Color(hex: 0x8B7CF6),
                                           Color(hex: 0xF472B6), Color(hex: 0xC6F432)]

    var body: some View {
        let k = size / 1024
        ZStack {
            // The tile: the orb's colour wheel, with the icon's soft light from the top.
            // Softened, so the colours melt into each other like the orb's glow.
            Rectangle()
                .fill(classic ? AnyShapeStyle(Color(hex: 0xD4FF3A))
                              : AnyShapeStyle(AngularGradient(colors: Self.rainbow, center: UnitPoint(x: 0.4, y: 0.55), angle: .degrees(200))))
                .frame(width: size * 1.3, height: size * 1.3)
                .blur(radius: 70 * k)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: square ? 0 : 230 * k, style: .continuous))
            RoundedRectangle(cornerRadius: square ? 0 : 230 * k, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .center))
            // The j's stem and hook.
            Path { p in
                p.move(to: CGPoint(x: 600, y: 384))
                p.addLine(to: CGPoint(x: 600, y: 694))
                p.addCurve(to: CGPoint(x: 330, y: 794), control1: CGPoint(x: 600, y: 854), control2: CGPoint(x: 410, y: 864))
            }
            .applying(CGAffineTransform(scaleX: k, y: k))
            .stroke(Color(hex: 0x111114), style: StrokeStyle(lineWidth: 150 * k, lineCap: .round))
            // The dot: the orb in a black ring.
            ZStack {
                Circle().fill(Color(hex: 0x111114)).frame(width: 210 * k, height: 210 * k)
                ZStack {
                    Circle().fill(AngularGradient(colors: Self.rainbow, center: .center, angle: .degrees(60)))
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)], center: UnitPoint(x: 0.3, y: 0.28),
                                                 startRadius: 0, endRadius: 120 * k))
                    Image(systemName: "sparkle").font(.system(size: 96 * k, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 180 * k, height: 180 * k)
                .clipShape(Circle())
            }
            .position(x: 600 * k, y: 204 * k)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: .black.opacity(square ? 0 : size > 60 ? 0.18 : 0.1), radius: square ? 0 : size * 0.08, y: size * 0.04)
        .accessibilityLabel(classic ? "Joshu" : "Joshu Pro")
    }
}
