import SwiftUI

/// A company's real logo: the mark on its own (`.glyph`), or white on the brand colour like an app icon (`.badge`).
struct BrandLogo: View {
    enum Style { case glyph, badge }
    let brand: Brand
    var size: CGFloat = 28
    var style: Style = .badge
    @Environment(\.colorScheme) private var scheme

    private var color: Color { Color(hex: brand.hex) }
    /// Near-black marks (GitHub, X, Apple…) would vanish on a dark background.
    private var isDark: Bool {
        let r = Double((brand.hex >> 16) & 0xFF), g = Double((brand.hex >> 8) & 0xFF), b = Double(brand.hex & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.2
    }

    var body: some View {
        switch brand {
        case .appleBooks:
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFA43B), Color(hex: 0xFF7A00)], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "book.fill").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
                .frame(width: size, height: size)
        case .kindle:
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x232F3E), Color(hex: 0x0F1111)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    VStack(spacing: size * 0.02) {
                        Text("kindle").font(.system(size: size * 0.26, weight: .semibold)).foregroundStyle(.white)
                        Capsule().fill(Color(hex: 0xFF9900)).frame(width: size * 0.42, height: size * 0.05)
                            .rotationEffect(.degrees(-6))
                    }
                )
                .frame(width: size, height: size)
        case .appleCalendar:
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(.white)
                .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                .overlay(VStack(spacing: -size * 0.04) {
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.system(size: size * 0.2, weight: .semibold)).foregroundStyle(Color(hex: 0xFF3B30))
                    Text(Date.now.formatted(.dateTime.day())).font(.system(size: size * 0.5, weight: .regular)).foregroundStyle(.black)
                })
                .frame(width: size, height: size)
        case .appleReminders:
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(.white)
                .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                .overlay(VStack(alignment: .leading, spacing: size * 0.08) {
                    ForEach([0x007AFF, 0xFF3B30, 0xFF9500] as [UInt32], id: \.self) { c in
                        HStack(spacing: size * 0.08) {
                            Circle().fill(Color(hex: c)).frame(width: size * 0.15, height: size * 0.15)
                            Capsule().fill(Color.black.opacity(0.18)).frame(width: size * 0.38, height: size * 0.05)
                        }
                    }
                })
                .frame(width: size, height: size)
        case .appleMaps:
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x8EE07A), Color(hex: 0x5BC2F0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Image(systemName: "location.north.fill").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
                    .rotationEffect(.degrees(45)).shadow(color: .black.opacity(0.2), radius: 1))
                .frame(width: size, height: size)
        default:
            switch style {
            case .glyph:
                SVGPathShape(data: brand.path)
                    .fill(isDark && scheme == .dark ? Color.white : color, style: FillStyle(eoFill: false))
                    .frame(width: size, height: size)
            case .badge:
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(brand == .instagram
                          ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFEDA75), Color(hex: 0xFA7E1E), Color(hex: 0xD62976), Color(hex: 0x962FBF), Color(hex: 0x4F5BD5)],
                                                         startPoint: .bottomLeading, endPoint: .topTrailing))
                          : AnyShapeStyle(color))
                    .overlay(SVGPathShape(data: brand.path).fill(brand.hex == 0xFFBB00 || brand.hex == 0xFFFC00 ? Color.black : .white)
                        .padding(size * 0.2))
                    .frame(width: size, height: size)
            }
        }
    }
}

extension Brand {
    /// The logo for a reading library key ("goodreads", "kindle", "apple-books" or "apple").
    static func forLibrary(_ key: String) -> Brand? {
        switch key {
        case "goodreads": .goodreads
        case "kindle": .kindle
        case "apple-books", "apple": .appleBooks
        default: nil
        }
    }
}

/// Draws SVG path data (M L H V C S Q T A Z, absolute and relative) scaled from a 24 × 24 grid to the frame.
struct SVGPathShape: Shape {
    let data: String
    var canvas: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let p = Self.parse(data)
        let s = min(rect.width, rect.height) / canvas
        return p.applying(CGAffineTransform(translationX: rect.midX - canvas * s / 2, y: rect.midY - canvas * s / 2).scaledBy(x: s, y: s))
    }

    private static var cache: [String: Path] = [:]
    private static let lock = NSLock()

    static func parse(_ d: String) -> Path {
        lock.lock(); defer { lock.unlock() }
        if let p = cache[d] { return p }
        let p = build(d)
        cache[d] = p
        return p
    }

    private static func build(_ d: String) -> Path {
        // Split into commands and numbers ("1.5.5" is two numbers, "-.3" one).
        var tokens: [String] = []
        var num = ""
        func flush() { if !num.isEmpty { tokens.append(num); num = "" } }
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" { flush(); tokens.append(String(ch)) }
            else if ch == "-" { if num.last == "e" || num.last == "E" { num.append(ch) } else { flush(); num = "-" } }
            else if ch == "." { if num.contains(".") && !num.contains("e") { flush(); num = "." } else { num.append(ch) } }
            else if ch == "," || ch == " " || ch == "\n" || ch == "\t" { flush() }
            else { num.append(ch) }
        }
        flush()

        var path = Path()
        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint? = nil, lastQuad: CGPoint? = nil
        func n() -> CGFloat { defer { i += 1 }; return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0 }
        func flag() -> Bool {
            // Arc flags may be written without separators ("a1 1 0 011 1").
            guard i < tokens.count else { return false }
            var t = tokens[i]
            let f = t.first == "1"
            t.removeFirst()
            if t.isEmpty { i += 1 } else { tokens[i] = t }
            return f
        }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = c; i += 1 }
            let rel = cmd.isLowercase
            let o = rel ? cur : .zero
            switch cmd.uppercased() {
            case "M":
                cur = CGPoint(x: o.x + n(), y: o.y + n()); start = cur
                path.move(to: cur)
                cmd = rel ? "l" : "L"
                lastCtrl = nil; lastQuad = nil
            case "L":
                cur = CGPoint(x: o.x + n(), y: o.y + n()); path.addLine(to: cur); lastCtrl = nil; lastQuad = nil
            case "H":
                cur = CGPoint(x: (rel ? cur.x : 0) + n(), y: cur.y); path.addLine(to: cur); lastCtrl = nil; lastQuad = nil
            case "V":
                cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + n()); path.addLine(to: cur); lastCtrl = nil; lastQuad = nil
            case "C":
                let c1 = CGPoint(x: o.x + n(), y: o.y + n()), c2 = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                path.addCurve(to: e, control1: c1, control2: c2); cur = e; lastCtrl = c2; lastQuad = nil
            case "S":
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                path.addCurve(to: e, control1: c1, control2: c2); cur = e; lastCtrl = c2; lastQuad = nil
            case "Q":
                let c = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                path.addQuadCurve(to: e, control: c); cur = e; lastQuad = c; lastCtrl = nil
            case "T":
                let c = lastQuad.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let e = CGPoint(x: o.x + n(), y: o.y + n())
                path.addQuadCurve(to: e, control: c); cur = e; lastQuad = c; lastCtrl = nil
            case "A":
                let rx = abs(n()), ry = abs(n()), rot = n()
                let large = flag(), sweep = flag()
                let e = CGPoint(x: o.x + n(), y: o.y + n())
                arc(&path, from: cur, to: e, rx: rx, ry: ry, angle: rot, large: large, sweep: sweep)
                cur = e; lastCtrl = nil; lastQuad = nil
            case "Z":
                path.closeSubpath(); cur = start; lastCtrl = nil; lastQuad = nil
            default:
                i += 1
            }
        }
        return path
    }

    /// SVG elliptical arc → cubic Béziers (the endpoint-to-centre conversion from the SVG spec).
    private static func arc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, angle: CGFloat, large: Bool, sweep: Bool) {
        guard rx0 > 0, ry0 > 0, p0 != p1 else { path.addLine(to: p1); return }
        var rx = rx0, ry = ry0
        let phi = angle * .pi / 180, cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2, cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let t1 = ang(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var dt = ang((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && dt > 0 { dt -= 2 * .pi } else if sweep && dt < 0 { dt += 2 * .pi }
        let segments = max(1, Int(ceil(abs(dt) / (.pi / 2))))
        let step = dt / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var t = t1
        func point(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(a) * cosP - ry * sin(a) * sinP, y: cy + rx * cos(a) * sinP + ry * sin(a) * cosP)
        }
        func deriv(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosP - ry * cos(a) * sinP, y: -rx * sin(a) * sinP + ry * cos(a) * cosP)
        }
        for _ in 0..<segments {
            let a0 = t, a1 = t + step
            let s = point(a0), e = point(a1), d0 = deriv(a0), d1 = deriv(a1)
            path.addCurve(to: e, control1: CGPoint(x: s.x + k * d0.x, y: s.y + k * d0.y), control2: CGPoint(x: e.x - k * d1.x, y: e.y - k * d1.y))
            t = a1
        }
    }
}
