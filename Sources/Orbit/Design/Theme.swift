import SwiftUI

// Visual language: white canvas, soft grey cards, bold serif numerals,
// pill navigation and saturated "sticker" colours per life area.

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    /// Side margin of full pages: roomy on the Mac, tighter on a phone.
    static var pagePadding: CGFloat { Platform.isPhone ? 16 : 32 }

    // Neutrals
    static let canvas = Color(light: 0xFFFFFF, dark: 0x111113)
    static let card = Color(light: 0xF2F2F2, dark: 0x1E1E21)
    static let cardHover = Color(light: 0xEAEAEA, dark: 0x27272B)
    static let line = Color(light: 0xE6E6E6, dark: 0x2C2C30)
    static let ink = Color(light: 0x111111, dark: 0xF4F4F5)
    static let inkSecondary = Color(light: 0x5C5C63, dark: 0xA1A1AA)
    static let inkMuted = Color(light: 0x9A9AA2, dark: 0x6B6B73)
    static let blush = Color(light: 0xF6E8E5, dark: 0x2A2124)
    static let inverse = Color(light: 0x111111, dark: 0xF4F4F5)
    static let onInverse = Color(light: 0xFFFFFF, dark: 0x111111)
    static let dashed = Color(hex: 0xB89BF7)

    // Sticker colours (always used with dark ink on top)
    static let pink = Color(hex: 0xF7C2EC)
    static let lime = Color(hex: 0xE6FF1F)
    static let orange = Color(hex: 0xEDAA2F)
    static let purple = Color(hex: 0xB58CF7)
    static let cyan = Color(hex: 0x27D3F6)
    static let mint = Color(hex: 0x8EEDBF)
    static let peach = Color(hex: 0xFFC6A3)
    static let lavender = Color(hex: 0xD9C8FF)
    static let sand = Color(hex: 0xF3DE9E)
    static let silver = Color(hex: 0xD4D4D8)
    static let stickerInk = Color(hex: 0x111111)

    static let good = Color(hex: 0x16A34A)
    static let critical = Color(hex: 0xE5484D)

    // Type
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let radius: CGFloat = 18
}

extension Area {
    var color: Color {
        switch self {
        case .health: Theme.pink
        case .work: Theme.cyan
        case .study: Theme.lime
        case .money: Theme.orange
        case .home: Theme.purple
        case .social: Theme.mint
        case .personal: Theme.peach
        }
    }
}

// MARK: - Reusable pieces

struct AreaPill: View {
    let area: Area
    var compact = false
    var selected = true

    var body: some View {
        Text(area.title)
            .font(Theme.ui(compact ? 11 : 13, weight: .medium))
            .foregroundStyle(Theme.stickerInk)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 3 : 6)
            .background(Capsule().fill(area.color.opacity(selected ? 1 : 0.35)))
    }
}

struct Card<Content: View>: View {
    var fill: Color = Theme.card
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(fill))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.display(22))
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action)
                    .buttonStyle(.plain)
                    .font(Theme.ui(12, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .foregroundStyle(Theme.ink)
    }
}

struct CircleIconButton: View {
    let symbol: String
    var filled = false
    var size: CGFloat = 40
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(filled ? Theme.onInverse : Theme.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? Theme.inverse : (hovering ? Theme.cardHover : Theme.card)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(13, weight: .semibold))
            .foregroundStyle(Theme.onInverse)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Theme.inverse))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(13, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(configuration.isPressed ? Theme.cardHover : Theme.card))
    }
}

/// Round check-off control used for tasks and habits.
struct CheckCircle: View {
    let isOn: Bool
    var tint: Color = Theme.ink
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? tint : Theme.inkMuted, lineWidth: 1.5)
            if isOn {
                Circle().fill(tint)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(tint == Theme.ink ? Theme.canvas : Theme.stickerInk)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isOn)
    }
}

/// Diagonal hatching used for free calendar slots.
struct Hatch: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let step: CGFloat = 9
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            ctx.stroke(path, with: .color(Theme.inkMuted.opacity(0.35)), lineWidth: 0.8)
        }
    }
}

struct EmptyHint: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(Theme.ui(13))
        .foregroundStyle(Theme.inkMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

// MARK: - Formatting

enum Fmt {
    static var currencyCode: String {
        UserDefaults.standard.string(forKey: "currencyCode") ?? (Locale.current.currency?.identifier ?? "USD")
    }

    static func money(_ value: Double, signed: Bool = false) -> String {
        let s = abs(value).formatted(.currency(code: currencyCode).precision(.fractionLength(0...2)))
        guard signed else { return value < 0 ? "-\(s)" : s }
        return value < 0 ? "−\(s)" : "+\(s)"
    }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    static func relativeDay(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: Date.now.startOfDay, to: d.startOfDay).day ?? 0
        if days > 0 && days < 7 { return d.formatted(.dateTime.weekday(.wide)) }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The Joshu app icon drawn in SwiftUI.
struct OrbitMark: View {
    var size: CGFloat = 56

    /// The Joshu app icon (lime tile, black j, the orb as its dot), drawn like the Pro logo.
    var body: some View { ProLogo(size: size, classic: true) }
}

/// Your profile photo, or your initials on a gradient.
struct Avatar: View {
    let name: String
    var size: CGFloat = 44
    @ObservedObject private var profile = ProfileStore.shared

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Group {
            if let photo = profile.photo {
                photo.swiftUI.resizable().scaledToFill()
            } else {
                Text(initials.isEmpty ? "Me" : initials)
                    .font(Theme.ui(size * 0.36, weight: .bold))
                    .foregroundStyle(Theme.stickerInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [Theme.pink, Theme.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
