import SwiftUI

/// The animated tour of what Orbit does, shown the first time you open it on a Mac or iPhone (and any time from
/// Settings › General or Orbit › Take the Tour). Each page shows a real screen of the app (sample data) on a real
/// iPhone or MacBook that zooms in on what's being explained, with cards popping out around it.
struct TourView: View {
    var onDone: () -> Void

    struct Sticker {
        let symbol: String
        let text: String
        let color: Color
        /// Where it floats, relative to the device (0…1, can go a little outside).
        let at: UnitPoint
    }

    struct Page: Identifiable {
        let id: Int
        let eyebrow: String
        let title: String
        let points: [(symbol: String, text: String)]
        let image: String
        /// Where the Mac screenshot zooms in (it's too small to read whole), and by how much.
        let focus: UnitPoint
        let zoom: CGFloat
        let color: Color
        let accent: Color
        let stickers: [Sticker]
        var both = false
    }

    private let phone = Platform.isPhone

    private var pages: [Page] {
        let ai = AssistantName.current
        return [
            Page(id: 0, eyebrow: "Welcome to Joshu", title: "Your whole life, in one calm place",
                 points: [("sun.max.fill", "Events, tasks, habits, money and reading on one screen"),
                          ("arrow.triangle.2.circlepath", "Always in sync between your Mac and iPhone"),
                          ("lock.fill", "Your data and keys stay yours")],
                 image: "today", focus: .init(x: 0, y: 0.1), zoom: 1.6, color: Theme.lime, accent: Theme.cyan,
                 stickers: [.init(symbol: "checkmark.circle.fill", text: "3 of 5 done", color: Theme.lime, at: .init(x: -0.08, y: 0.22)),
                            .init(symbol: "flame.fill", text: "9-day streak", color: Theme.orange, at: .init(x: 1.06, y: 0.42)),
                            .init(symbol: "calendar", text: "Gym · 7:00 PM", color: Theme.cyan, at: .init(x: -0.04, y: 0.78))]),
            Page(id: 1, eyebrow: "Your day", title: "An AI summary that keeps up with you",
                 points: [("sparkles", "A morning brief with what matters today"),
                          ("sun.horizon.fill", "“Your day” rewrites itself as you spend, read and tick things off"),
                          ("lightbulb.fill", "A gentle nudge for the next few hours")],
                 image: "day", focus: .center, zoom: 1, color: Theme.orange, accent: Theme.pink,
                 stickers: [.init(symbol: "creditcard.fill", text: "EGP 350 today", color: Theme.peach, at: .init(x: 1.05, y: 0.25)),
                            .init(symbol: "book.fill", text: "42% · Atomic Habits", color: Theme.purple, at: .init(x: -0.06, y: 0.62))]),
            Page(id: 2, eyebrow: "Meet \(ai)", title: "An assistant that actually does things",
                 points: [("text.bubble.fill", "Chat or talk: it adds tasks, events, notes and expenses"),
                          ("fork.knife", "“I'm hungry”: places nearby, with prices and reviews"),
                          ("doc.text.magnifyingglass", "What to wear, quick maths, and reviews of your documents")],
                 image: "assistant", focus: .init(x: 1, y: 0), zoom: 2.3, color: Theme.pink, accent: Theme.purple,
                 stickers: [.init(symbol: "mic.fill", text: "“Move the gym to 8”", color: Theme.lime, at: .init(x: -0.08, y: 0.2)),
                            .init(symbol: "mappin.and.ellipse", text: "Zooba · 2 min away", color: Theme.mint, at: .init(x: 1.06, y: 0.55)),
                            .init(symbol: "cloud.sun.fill", text: "T-shirt + light jacket", color: Theme.cyan, at: .init(x: -0.05, y: 0.85))]),
            Page(id: 3, eyebrow: "Plan", title: "Tasks, calendar and reminders that find you",
                 points: [("calendar", "Apple and Google calendars side by side"),
                          ("location.fill", "“Remind me when I get home” or when you're near a shop"),
                          ("moon.stars.fill", "Plan tomorrow in a minute each evening")],
                 image: "calendar", focus: .init(x: 0.6, y: 1), zoom: 2, color: Theme.cyan, accent: Theme.lime,
                 stickers: [.init(symbol: "location.fill", text: "When you get home", color: Theme.lime, at: .init(x: -0.08, y: 0.3)),
                            .init(symbol: "alarm.fill", text: "Call mom · 6:00 PM", color: Theme.peach, at: .init(x: 1.05, y: 0.7))]),
            Page(id: 4, eyebrow: "Money", title: "Every pound, logged for you",
                 points: [("envelope.fill", "Receipts from email and bank texts land in Money by themselves"),
                          ("doc.viewfinder", "Snap a paper receipt; Joshu reads it"),
                          ("bell.badge.fill", "Budgets per category, with alerts before you overspend")],
                 image: "money", focus: .init(x: 0, y: 0.11), zoom: 1.8, color: Theme.peach, accent: Theme.orange,
                 stickers: [.init(symbol: "message.fill", text: "CIB · EGP 220 logged", color: Theme.cyan, at: .init(x: -0.08, y: 0.25)),
                            .init(symbol: "exclamationmark.triangle.fill", text: "80% of Food budget", color: Theme.orange, at: .init(x: 1.05, y: 0.48)),
                            .init(symbol: "wave.3.right", text: "Apple Pay · Starbucks", color: Theme.lime, at: .init(x: -0.04, y: 0.8))]),
            Page(id: 5, eyebrow: "Reading", title: "Your library, reading time and streaks",
                 points: [("book.fill", "Currently reading, with progress and a timer"),
                          ("arrow.down.circle.fill", "From Goodreads, Apple Books and Kindle"),
                          ("highlighter", "Your highlights, all in one place")],
                 image: "reading", focus: .init(x: 0.5, y: 0.3), zoom: 1.55, color: Theme.purple, accent: Theme.pink,
                 stickers: [.init(symbol: "timer", text: "15 min today", color: Theme.orange, at: .init(x: 1.05, y: 0.3)),
                            .init(symbol: "books.vertical.fill", text: "3 of 24 this year", color: Theme.pink, at: .init(x: -0.06, y: 0.7))]),
            Page(id: 6, eyebrow: "Dreams and places", title: "A bucket list, and a map of places to go",
                 points: [("mountain.2.fill", "Dreams you want to make happen, with trips around them"),
                          ("mappin.and.ellipse", "Save restaurants, shops and museums to Go to"),
                          ("map.fill", "Share straight from Google or Apple Maps")],
                 image: "goto", focus: .init(x: 0, y: 0.2), zoom: 1.6, color: Theme.mint, accent: Theme.cyan,
                 stickers: [.init(symbol: "fork.knife", text: "Zooba · Food", color: Theme.orange, at: .init(x: -0.08, y: 0.35)),
                            .init(symbol: "building.columns.fill", text: "Grand Egyptian Museum", color: Theme.cyan, at: .init(x: 1.06, y: 0.62))]),
            Page(id: 7, eyebrow: "Everywhere", title: "On your Mac and iPhone, always in sync",
                 points: [("macbook.and.iphone", "Start on one, finish on the other"),
                          ("square.grid.2x2.fill", "Widgets, Siri and Shortcuts for quick adds"),
                          ("hand.wave.fill", "Let's set it up: it takes a minute")],
                 image: "insights", focus: .init(x: 0.5, y: 0.4), zoom: 1.0, color: Theme.lime, accent: Theme.purple,
                 stickers: [.init(symbol: "arrow.triangle.2.circlepath", text: "Synced just now", color: Theme.lime, at: .init(x: 0.5, y: -0.06))],
                 both: true),
        ]
    }

    @State private var index = 0
    @State private var zoomed = false
    @State private var revealed = false
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        let page = pages[index]
        ZStack {
            AuroraBackground(a: page.color, b: page.accent).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content(page)
            }
        }
        .onAppear { start() }
        .onDisappear { timerTask?.cancel() }
        #if os(macOS)
        .onKeyPress(.rightArrow) { go(index + 1); return .handled }
        .onKeyPress(.leftArrow) { go(index - 1); return .handled }
        .onKeyPress(.space) { go(index + 1); return .handled }
        .frame(width: 1040, height: 660)
        #endif
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(pages) { p in
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.ink.opacity(0.14))
                            Capsule().fill(Theme.ink).frame(width: p.id <= index ? g.size.width : 0)
                        }
                    }
                    .frame(height: 4)
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture { go(p.id) }
                }
            }
            HStack {
                Button { go(index - 1) } label: { Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).frame(width: 30, height: 30) }
                    .buttonStyle(.plain).opacity(index > 0 ? 1 : 0).disabled(index == 0)
                Text(String(format: "%02d / %02d", index + 1, pages.count)).font(Theme.ui(12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                if index < pages.count - 1 {
                    Button("Skip") { finish() }.buttonStyle(.plain).font(Theme.ui(14, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, phone ? 20 : 28).padding(.top, phone ? 8 : 18)
    }

    @ViewBuilder private func content(_ page: Page) -> some View {
        if phone {
            VStack(spacing: 14) {
                stage(page).frame(maxHeight: .infinity).padding(.top, 6)
                text(page).padding(.horizontal, 24)
                nextButton.padding(.horizontal, 24).padding(.bottom, 10)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -40 { go(index + 1) } else if v.translation.width > 40 { go(index - 1) }
            })
        } else {
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 26) {
                    Spacer()
                    text(page)
                    nextButton.frame(width: 210)
                    Spacer()
                }
                .frame(width: 340)
                stage(page).frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 20)
            }
            .padding(.leading, 48).padding(.trailing, 36).padding(.bottom, 18)
        }
    }

    // MARK: Text

    private func text(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: phone ? 12 : 16) {
            Text(page.eyebrow.uppercased()).font(Theme.ui(12, weight: .bold)).tracking(1.4)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(page.color))
                .foregroundStyle(Theme.stickerInk)
            Text(page.title).font(Theme.display(phone ? 29 : 38)).fixedSize(horizontal: false, vertical: true)
                .opacity(revealed ? 1 : 0).animation(.easeOut(duration: 0.35), value: revealed)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(page.points.enumerated()), id: \.offset) { i, p in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: p.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.stickerInk)
                            .frame(width: 28, height: 28).background(Circle().fill(page.color))
                        Text(p.text).font(Theme.ui(phone ? 14 : 15)).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
                    }
                    .opacity(revealed ? 1 : 0)
                    .offset(x: revealed ? 0 : -14)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35 + Double(i) * 0.14), value: revealed)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("text-\(page.id)")
        .transition(.opacity)
    }

    private var nextButton: some View {
        Button { index == pages.count - 1 ? finish() : go(index + 1) } label: {
            HStack(spacing: 8) {
                Text(index == pages.count - 1 ? "Get started" : "Next")
                Image(systemName: index == pages.count - 1 ? "arrow.right.circle.fill" : "arrow.right")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    }

    // MARK: Devices

    /// Both devices on every page, with stickers popping out around them. The device you're on is the big one,
    /// zoomed in on what the page is about so the text reads clearly; the other sits beside it.
    @ViewBuilder private func stage(_ page: Page) -> some View {
        let macZoom = page.both ? 1 : (zoomed ? page.zoom : 1)
        Group {
            if phone {
                ZStack(alignment: .bottomLeading) {
                    IPhoneFrame(image: shot("phone-" + page.image)).padding(.leading, 70)
                    MacBookFrame(image: shot("mac-" + page.image))
                        .frame(width: 200, height: 140)
                        .offset(x: -2, y: 8)
                }
                .padding(.horizontal, 26)
                .overlay { stickers(page) }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    MacBookFrame(image: shot("mac-" + page.image), zoom: macZoom, focus: page.focus)
                        .animation(.spring(response: 0.9, dampingFraction: 0.9), value: zoomed)
                        .padding(.trailing, 70)
                    IPhoneFrame(image: shot("phone-" + page.image))
                        .frame(height: 330)
                        .offset(x: 10, y: 36)
                }
                .overlay { stickers(page) }
            }
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 12)
        .animation(.easeOut(duration: 0.4), value: revealed)
        .id("stage-\(page.id)")
        .transition(.opacity)
    }

    private func stickers(_ page: Page) -> some View {
        GeometryReader { g in
            ForEach(Array(page.stickers.enumerated()), id: \.offset) { i, s in
                StickerChip(sticker: s, shown: zoomed, delay: 0.9 + Double(i) * 0.35, bob: i)
                    // Keep the cards over the devices' edges so none spill off the screen or out of the window.
                    .position(x: g.size.width * (phone ? min(0.76, max(0.24, s.at.x)) : min(0.9, max(0.1, s.at.x))), y: g.size.height * s.at.y)
            }
        }
        .allowsHitTesting(false)
    }

    private func shot(_ file: String) -> Image {
        if let url = Bundle.main.url(forResource: file, withExtension: "jpg", subdirectory: "Tour"), let img = PlatformImage.load(url) {
            return img.swiftUI
        }
        return Image(systemName: "photo")
    }

    // MARK: Timing

    private func go(_ i: Int) {
        guard i >= 0 else { return }
        guard i < pages.count else { finish(); return }
        guard i != index else { return }
        withAnimation(.easeInOut(duration: 0.35)) { index = i; zoomed = false; revealed = false }
        start()
    }

    /// Shows the page: the screen fades in, then the text and the cards. You move on with Next.
    private func start() {
        timerTask?.cancel()
        let page = index
        timerTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            revealed = true
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, index == page else { return }
            zoomed = true   // shows the cards
        }
    }

    private func finish() {
        timerTask?.cancel()
        UserDefaults.standard.set(true, forKey: "tourSeen")
        onDone()
    }
}

// MARK: - Pieces

/// Slowly drifting blobs of the page's colours behind everything.
private struct AuroraBackground: View {
    let a: Color
    let b: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    Theme.canvas
                    Circle().fill(a.opacity(0.75)).frame(width: w * 0.9).blur(radius: 90)
                        .offset(x: cos(t / 5) * w * 0.25 - w * 0.2, y: sin(t / 6) * h * 0.12 - h * 0.25)
                    Circle().fill(b.opacity(0.45)).frame(width: w * 0.7).blur(radius: 100)
                        .offset(x: sin(t / 7) * w * 0.25 + w * 0.3, y: cos(t / 5.5) * h * 0.15 + h * 0.2)
                    Circle().fill(a.opacity(0.35)).frame(width: w * 0.5).blur(radius: 80)
                        .offset(x: cos(t / 4) * w * 0.2, y: sin(t / 4.5) * h * 0.2 + h * 0.35)
                }
                .frame(width: w, height: h)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: a)
    }
}

/// A headline that arrives word by word.
private struct WordReveal: View {
    let text: String
    let font: Font
    let shown: Bool

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        FlowLayout(spacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                Text(w + " ").font(font)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 14)
                    .blur(radius: shown ? 0 : 4)
                    .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(i) * 0.06), value: shown)
            }
        }
    }
}

/// A small card that pops out next to the device and bobs gently.
private struct StickerChip: View {
    let sticker: TourView.Sticker
    let shown: Bool
    let delay: Double
    let bob: Int

    var body: some View {
        Group {
            HStack(spacing: 7) {
                Image(systemName: sticker.symbol).font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.55)))
                Text(sticker.text).font(Theme.ui(Platform.isPhone ? 12 : 13, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Theme.stickerInk)
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
            .background(Capsule().fill(sticker.color))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .opacity(shown ? 1 : 0)
        .animation(.easeOut(duration: 0.35).delay(shown ? delay * 0.4 : 0), value: shown)
    }
}

/// An iPhone 17 Pro: titanium edge, black border, Dynamic Island and side buttons.
struct IPhoneFrame: View {
    let image: Image
    var zoom: CGFloat = 1
    var focus: UnitPoint = .center

    var body: some View {
        GeometryReader { g in
            let aspect = 1206.0 / 2622.0
            let h = min(g.size.height, g.size.width / aspect), w = h * aspect
            let edge = w * 0.035, border = w * 0.03
            let outer = w * 0.17
            ZStack {
                // Side buttons: action and volume on the left, side button on the right.
                button(w: edge * 0.9, h: h * 0.05).offset(x: -w / 2 - edge * 0.35, y: -h * 0.24)
                button(w: edge * 0.9, h: h * 0.085).offset(x: -w / 2 - edge * 0.35, y: -h * 0.13)
                button(w: edge * 0.9, h: h * 0.085).offset(x: -w / 2 - edge * 0.35, y: -h * 0.03)
                button(w: edge * 0.9, h: h * 0.12).offset(x: w / 2 + edge * 0.35, y: -h * 0.12)
                // Titanium body
                RoundedRectangle(cornerRadius: outer, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x8E8E93), Color(hex: 0xD8D8DC), Color(hex: 0x6E6E73), Color(hex: 0xBDBDC2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: w, height: h)
                RoundedRectangle(cornerRadius: outer - edge, style: .continuous).fill(Color.black)
                    .frame(width: w - edge * 2, height: h - edge * 2)
                // Screen. The status bar stays put while the app underneath zooms, like a real phone.
                let sw = w - (edge + border) * 2, sh = h - (edge + border) * 2
                ZStack(alignment: .top) {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .scaleEffect(zoom, anchor: focus)
                        .frame(width: sw, height: sh)
                        .clipped()
                    if zoom > 1.01 {
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: sw, height: sh, alignment: .top)
                            .frame(width: sw, height: sh * 0.058, alignment: .top)
                            .clipped()
                            .background(Theme.canvas)
                            .transition(.opacity)
                    }
                }
                .frame(width: sw, height: sh)
                .clipShape(RoundedRectangle(cornerRadius: outer - edge - border, style: .continuous))
                // Dynamic Island
                Capsule().fill(Color.black)
                    .frame(width: w * 0.29, height: w * 0.085)
                    .overlay(alignment: .trailing) { Circle().fill(Color(hex: 0x1C1C2E)).frame(width: w * 0.035).padding(.trailing, w * 0.025) }
                    .offset(y: -h / 2 + edge + border + w * 0.065)
                // Glass glare
                RoundedRectangle(cornerRadius: outer - edge - border, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.13), .clear, .clear], startPoint: .topLeading, endPoint: .center))
                    .frame(width: w - (edge + border) * 2, height: h - (edge + border) * 2)
                    .allowsHitTesting(false)
            }
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(0.3), radius: 28, y: 20)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(1206.0 / 2622.0, contentMode: .fit)
    }

    private func button(w: CGFloat, h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: w / 2).fill(Color(hex: 0x9A9AA0)).frame(width: w, height: h)
    }
}

/// A MacBook Pro: thin black border with a notch, aluminium base with the thumb cut-out.
struct MacBookFrame: View {
    let image: Image
    var zoom: CGFloat = 1
    var focus: UnitPoint = .center

    var body: some View {
        GeometryReader { g in
            let screenAspect = 1440.0 / 900.0
            let total = min(g.size.width, g.size.height * screenAspect * 1.02)
            let lidW = total * 0.86, border = lidW * 0.018
            let screenW = lidW - border * 2, screenH = screenW / screenAspect
            let lidH = screenH + border * 2.2
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: lidW * 0.025, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x2A2A2E), Color(hex: 0x111113)], startPoint: .top, endPoint: .bottom))
                        .frame(width: lidW, height: lidH)
                        .overlay(RoundedRectangle(cornerRadius: lidW * 0.025, style: .continuous).strokeBorder(Color(hex: 0x6E6E73), lineWidth: 1.2))
                    image.resizable().aspectRatio(contentMode: .fill)
                        .scaleEffect(zoom, anchor: focus)
                        .frame(width: screenW, height: screenH)
                        .clipShape(RoundedRectangle(cornerRadius: lidW * 0.01, style: .continuous))
                        .padding(.top, border)
                    // Notch with camera
                    UnevenRoundedRectangle(bottomLeadingRadius: lidW * 0.008, bottomTrailingRadius: lidW * 0.008)
                        .fill(Color.black)
                        .frame(width: lidW * 0.09, height: border * 1.6)
                        .overlay { Circle().fill(Color(hex: 0x1C1C2E)).frame(width: border * 0.55) }
                        .padding(.top, border * 0.5)
                }
                // Hinge
                Rectangle().fill(LinearGradient(colors: [Color(hex: 0x3A3A3C), Color(hex: 0x8E8E93)], startPoint: .top, endPoint: .bottom))
                    .frame(width: lidW * 0.96, height: total * 0.008)
                // Base
                ZStack(alignment: .top) {
                    UnevenRoundedRectangle(bottomLeadingRadius: total * 0.02, bottomTrailingRadius: total * 0.02)
                        .fill(LinearGradient(colors: [Color(hex: 0xE3E3E6), Color(hex: 0xB0B0B5)], startPoint: .top, endPoint: .bottom))
                        .frame(width: total, height: total * 0.028)
                    UnevenRoundedRectangle(bottomLeadingRadius: total * 0.008, bottomTrailingRadius: total * 0.008)
                        .fill(Color(hex: 0xA5A5AA))
                        .frame(width: total * 0.14, height: total * 0.009)
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 30, y: 22)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(1440.0 / 900.0 * 0.98, contentMode: .fit)
    }
}
