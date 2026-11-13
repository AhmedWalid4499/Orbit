import SwiftUI
import AppKit

/// App Store screenshots for iPhone (6.9-inch, 1320 × 2868): a headline and the app, whole, on an iPhone.
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
        /// Small pills under the headline: the other things this part of Joshu does.
        var tags: [String] = []
    }

    /// Ten shots (the App Store's limit), one per part of Joshu; the tags name everything else it does.
    static let shots: [Shot] = [
        Shot(file: "today", eyebrow: "Your day", title: "Your whole day,\nin one calm place",
             detail: "Open Joshu and know exactly where you stand.",
             colors: (Theme.lime, Theme.cyan),
             tags: ["Due today", "Calendar", "Habits", "Budget left", "Weather", "Mood", "Plan tomorrow", "Week in review"]),
        Shot(file: "calendar", eyebrow: "Plan", title: "Tasks, calendar\nand reminders",
             detail: "Every calendar on your iPhone, next to your tasks.",
             colors: (Theme.cyan, Theme.purple),
             tags: ["Add in one line", "Top 3 for the day", "Repeating tasks", "Apple Reminders", "Place reminders", "Shared lists"]),
        Shot(file: "habits", eyebrow: "Habits", title: "Habits\nthat stick",
             detail: "Streaks and weekly targets, ticked off in a tap.",
             colors: (Theme.pink, Theme.lime),
             tags: ["Streaks", "Weekly targets", "Apple Health", "Insights and trends", "Tap to tick in widgets"]),
        Shot(file: "focus", eyebrow: "Focus", title: "Focus that\nfollows you",
             detail: "A live countdown in the Dynamic Island and on your Lock Screen.",
             colors: (Theme.orange, Theme.purple),
             tags: ["Lock Screen timer", "Stop anywhere", "Control Center", "Action button", "Focus filters", "Lock Screen widgets"]),
        Shot(file: "money", eyebrow: "Money", title: "Every expense,\nin one place",
             detail: "Know what's left to spend before the month ends.",
             colors: (Theme.mint, Theme.lime),
             tags: ["Monthly budget", "Bills", "Subscriptions", "Bank texts", "Apple Pay via Shortcuts", "Scan receipts", "Money calendar"]),
        Shot(file: "assistant", eyebrow: "Joshu Pro", title: "Ask anything.\nIt gets it done.",
             detail: "Your own AI assistant: it plans, writes and adds things to Joshu.",
             colors: (Theme.pink, Theme.purple),
             tags: ["Voice or text", "“Hey” hands-free", "Morning brief", "Day summary", "Money coach", "Smart capture"]),
        Shot(file: "ideas", eyebrow: "Notes", title: "Notes, journal\nand ideas",
             detail: "Write it down, track your mood, grow your ideas.",
             colors: (Theme.peach, Theme.pink),
             tags: ["Daily journal", "Mood", "Ideas and projects", "Documents", "Search everything"]),
        Shot(file: "reading", eyebrow: "Reading", title: "A bookshelf\nyou'll love",
             detail: "Your shelf, your reading time and this year's goal.",
             colors: (Theme.orange, Theme.peach),
             tags: ["Reading timer", "Yearly goal", "Book covers", "Goodreads import", "Bookshelf widget"]),
        Shot(file: "bucket", eyebrow: "Dreams", title: "Dreams and trips,\nplanned",
             detail: "A bucket list, trips and the places you want to go.",
             colors: (Theme.cyan, Theme.mint),
             tags: ["Bucket list", "Goals", "Trips and packing", "Places to go", "Countdowns"]),
        Shot(file: "card", eyebrow: "Your card", title: "A business card\nalways on you",
             detail: "Share it with a QR code, or keep it in Apple Wallet.",
             colors: (Theme.lime, Theme.pink),
             tags: ["QR code", "Your own web page", "Apple Wallet", "Save my contact", "Syncs with your Mac", "Siri and Shortcuts"]),
    ]

    /// `ORBIT_PRO_LOGO=<file.png>`: the Joshu Pro logo at 1024 × 1024, for the website and the Brand folder.
    static func renderProLogoIfRequested() -> Bool {
        guard let file = ProcessInfo.processInfo.environment["ORBIT_PRO_LOGO"] else { return false }
        // "…-icon.png": the square iPhone icon; "…-mac.png": the Mac icon (with the margin Mac icons have);
        // anything else: the rounded logo.
        let view: AnyView = file.hasSuffix("-mac.png")
            ? AnyView(ProLogo(size: 824).padding(100).frame(width: 1024, height: 1024))
            : AnyView(ProLogo(size: 1024, square: file.hasSuffix("-icon.png")))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        if let cg = renderer.cgImage { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file)) }
        print("Pro logo written to \(file)")
        fflush(stdout)
        NSApp.terminate(nil)
        return true
    }

    static func renderIfRequested() {
        if renderProLogoIfRequested() { return }
        guard let dir = ProcessInfo.processInfo.environment["ORBIT_STORE_SHOTS"] else { return }
        let input = URL(fileURLWithPath: dir), out = input.appending(path: "out")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (i, shot) in shots.enumerated() {
            guard let screen = NSImage(contentsOf: input.appending(path: "\(shot.file).png")) else { continue }
            // Mac screens (landscape) go in a MacBook at 2880 × 1800; iPhone screens in an iPhone at 1320 × 2868.
            let mac = screen.size.width > screen.size.height
            let view: AnyView = mac
                ? AnyView(MacStoreShotView(shot: shot, screen: Image(nsImage: screen)).frame(width: 1440, height: 900))
                : AnyView(StoreShotView(shot: shot, screen: Image(nsImage: screen)).frame(width: 440, height: 956))
            let renderer = ImageRenderer(content: view)
            renderer.scale = mac ? 2 : 3
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

    static let phoneTop: CGFloat = 352
    static let phoneHeight: CGFloat = 572


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
                    if !shot.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(shot.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white.opacity(0.85)))
                                    .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.08)))
                            }
                        }
                        .frame(maxWidth: 400)
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 46)
                Spacer(minLength: 0)
            }
            // The whole phone, with room around it: 352–924 of the 956-point-tall image. Nothing covers the app.
            IPhoneFrame(image: screen)
                .frame(height: Self.phoneHeight)
                .position(x: 220, y: Self.phoneTop + Self.phoneHeight / 2)
        }
        .frame(width: 440, height: 956)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}

/// The same look for the Mac: a one-line headline above the app on a MacBook.
struct MacStoreShotView: View {
    let shot: StoreShots.Shot
    let screen: Image

    var body: some View {
        ZStack {
            Color(hex: 0xFBFBF8)
                .overlay {
                    Circle().fill(shot.colors.0.opacity(0.7)).frame(width: 900, height: 900).blur(radius: 140).offset(x: -420, y: -300)
                    Circle().fill(shot.colors.1.opacity(0.5)).frame(width: 800, height: 800).blur(radius: 150).offset(x: 460, y: 320)
                }
                .frame(width: 1440, height: 900)
                .clipped()
            VStack(spacing: 12) {
                Text(shot.eyebrow.uppercased())
                    .font(.system(size: 14, weight: .heavy)).tracking(1.8)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.ink)).foregroundStyle(.white)
                Text(shot.title.replacingOccurrences(of: "\n", with: " "))
                    .font(Theme.display(52)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(shot.detail)
                    .font(Theme.ui(19, weight: .medium)).foregroundStyle(Color(hex: 0x55555C)).lineLimit(1)
            }
            .frame(maxWidth: 1200)
            .position(x: 720, y: 140)
            // The whole laptop, with room around it: 250–860 of the 900-point-tall image.
            MacBookFrame(image: screen)
                .frame(width: 1110, height: 610)
                .position(x: 720, y: 555)
        }
        .frame(width: 1440, height: 900)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}
