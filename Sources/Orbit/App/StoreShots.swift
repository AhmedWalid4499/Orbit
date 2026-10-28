import SwiftUI
import AppKit

/// App Store screenshots for iPhone (6.9-inch, 1320 × 2868): a headline, the app on an iPhone, and a few highlights.
/// `ORBIT_STORE_SHOTS=<folder with raw simulator screenshots> build/Orbit.app/Contents/MacOS/Orbit` writes them to
/// <folder>/out. Raw screens come from `scripts/run-ios-sim.sh -demo -demoAI -open <tab>` at 1206 × 2622.
@MainActor
enum StoreShots {
    struct Shot {
        let file: String
        let eyebrow: String
        let title: String
        let detail: String
        let colors: (Color, Color)
        let chips: [(String, String, Color, CGPoint)]   // symbol, text, colour, position as a fraction of the phone
    }

    static let shots: [Shot] = [
        Shot(file: "today", eyebrow: "Your day", title: "Your whole life,\nin one calm place",
             detail: "Tasks, calendar, habits, money and reading on one screen.",
             colors: (Theme.lime, Theme.cyan),
             chips: [("checkmark.circle.fill", "3 of 5 done", Theme.lime, .init(x: -0.06, y: 0.36)),
                     ("sun.max.fill", "27° and sunny", Theme.peach, .init(x: 1.04, y: 0.15)),
                     ("flame.fill", "10-day streak", Theme.orange, .init(x: 1.02, y: 0.62))]),
        Shot(file: "assistant", eyebrow: "Your assistant", title: "Ask anything.\nIt gets it done.",
             detail: "It plans, writes, searches and adds things to Joshu for you.",
             colors: (Theme.pink, Theme.purple),
             chips: [("mappin.and.ellipse", "Saved to Go to", Theme.mint, .init(x: -0.05, y: 0.5)),
                     ("cloud.sun.fill", "T-shirt + light jacket", Theme.cyan, .init(x: 1.0, y: 0.74))]),
        Shot(file: "voice", eyebrow: "Hands-free", title: "Just say\n“Hey Joshu”",
             detail: "Talk while you cook, drive or walk. It answers out loud.",
             colors: (Theme.cyan, Theme.lime),
             chips: [("waveform", "Listening…", Theme.lime, .init(x: -0.04, y: 0.2))]),
        Shot(file: "money", eyebrow: "Money", title: "Every expense,\nlogged for you",
             detail: "Bank texts, Apple Pay and receipts land in Money by themselves.",
             colors: (Theme.mint, Theme.lime),
             chips: [("message.fill", "Card payment logged", Theme.cyan, .init(x: -0.05, y: 0.42)),
                     ("bell.badge.fill", "Rent due in 4 days", Theme.peach, .init(x: 1.03, y: 0.66))]),
        Shot(file: "calendar", eyebrow: "Plan", title: "Your calendar,\ntasks and reminders",
             detail: "Apple, Google and Outlook calendars side by side.",
             colors: (Theme.cyan, Theme.purple),
             chips: [("location.fill", "Remind me at home", Theme.lime, .init(x: -0.05, y: 0.62)),
                     ("calendar", "Gym · 7:00 PM", Theme.pink, .init(x: 1.02, y: 0.36))]),
        Shot(file: "ideas", eyebrow: "Ideas", title: "Ideas that\ngrow with you",
             detail: "Projects for your writing. Your assistant adds and grows them.",
             colors: (Theme.purple, Theme.pink),
             chips: [("sparkles", "Grown from an idea", Theme.lime, .init(x: 1.02, y: 0.48))]),
        Shot(file: "reading", eyebrow: "Reading", title: "A bookshelf\nyou'll love",
             detail: "Goodreads, Kindle and Apple Books, with your reading time and goal.",
             colors: (Theme.orange, Theme.peach),
             chips: [("timer", "28 min this week", Theme.lime, .init(x: -0.04, y: 0.56)),
                     ("books.vertical.fill", "3 of 24 this year", Theme.pink, .init(x: 1.02, y: 0.8))]),
        Shot(file: "bucket", eyebrow: "Dreams", title: "Dreams and trips,\nplanned",
             detail: "A bucket list, trips with bookings from your email, places to go.",
             colors: (Theme.cyan, Theme.mint),
             chips: [("airplane", "Lisbon in 19 days", Theme.lime, .init(x: 1.02, y: 0.3)),
                     ("envelope.fill", "Booking found in email", Theme.peach, .init(x: -0.05, y: 0.56))]),
        Shot(file: "insights", eyebrow: "Insights", title: "See the trends\nbehind your weeks",
             detail: "Spending, focus, reading, habits and mood over time.",
             colors: (Theme.lime, Theme.purple),
             chips: [("figure.walk", "8,432 steps", Theme.mint, .init(x: -0.05, y: 0.58)),
                     ("timer", "175 min focused", Theme.orange, .init(x: 1.02, y: 0.3))]),
    ]

    static func renderIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["ORBIT_STORE_SHOTS"] else { return }
        let input = URL(fileURLWithPath: dir), out = input.appending(path: "out")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (i, shot) in shots.enumerated() {
            guard let screen = NSImage(contentsOf: input.appending(path: "\(shot.file).png")) else { print("missing \(shot.file).png"); continue }
            let renderer = ImageRenderer(content: StoreShotView(shot: shot, screen: Image(nsImage: screen)).frame(width: 440, height: 956))
            renderer.scale = 3
            guard let cg = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: out.appending(path: String(format: "%02d-%@.png", i + 1, shot.file)))
        }
        print("Store shots written to \(out.path)")
        fflush(stdout)
        NSApp.terminate(nil)
    }
}

struct StoreShotView: View {
    let shot: StoreShots.Shot
    let screen: Image

    static let phoneTop: CGFloat = 300
    static let phoneHeight: CGFloat = 590

    private func chipView(_ chip: (String, String, Color, CGPoint)) -> some View {
        HStack(spacing: 8) {
            Image(systemName: chip.0).font(.system(size: 13, weight: .bold))
                .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.55)))
            Text(chip.1).font(.system(size: 15, weight: .bold)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(Color(hex: 0x111111))
        .padding(.leading, 7).padding(.trailing, 14).padding(.vertical, 7)
        .background(Capsule().fill(chip.2))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    var body: some View {
        ZStack {
            // Soft colour glows behind the phone, kept inside the image so they don't widen the layout.
            Color(hex: 0xFBFBF8)
                .overlay {
                    Circle().fill(shot.colors.0.opacity(0.75)).frame(width: 520, height: 520).blur(radius: 90).offset(x: -150, y: -260)
                    Circle().fill(shot.colors.1.opacity(0.55)).frame(width: 460, height: 460).blur(radius: 100).offset(x: 170, y: 260)
                }
                .frame(width: 440, height: 956)
                .clipped()
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text(shot.eyebrow.uppercased())
                        .font(.system(size: 13, weight: .heavy)).tracking(1.6)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.ink)).foregroundStyle(.white)
                    Text(shot.title)
                        .font(Theme.display(40)).multilineTextAlignment(.center).lineSpacing(-2)
                        .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    Text(shot.detail)
                        .font(Theme.ui(16, weight: .medium)).multilineTextAlignment(.center)
                        .foregroundStyle(Color(hex: 0x55555C)).frame(maxWidth: 360).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 58)
                Spacer(minLength: 0)
            }
            // The whole phone, with room around it: 300–890 of the 956-point-tall image.
            IPhoneFrame(image: screen)
                .frame(height: Self.phoneHeight)
                .position(x: 220, y: Self.phoneTop + Self.phoneHeight / 2)
            // Highlights overlap the phone's sides but always stay well inside the image.
            ForEach(Array(shot.chips.enumerated()), id: \.offset) { _, chip in
                HStack(spacing: 0) {
                    if chip.3.x >= 0.5 { Spacer(minLength: 0) }
                    chipView(chip)
                    if chip.3.x < 0.5 { Spacer(minLength: 0) }
                }
                .padding(.horizontal, 30)
                .frame(width: 440)
                .position(x: 220, y: Self.phoneTop + Self.phoneHeight * chip.3.y)
            }
        }
        .frame(width: 440, height: 956)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}
