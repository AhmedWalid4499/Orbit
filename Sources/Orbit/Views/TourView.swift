import SwiftUI

/// A short animated tour of what Orbit does, shown the first time you open it on a Mac or iPhone
/// (and any time from Settings). Each page shows a real screen of the app (sample data) in a device frame
/// that zooms in on the part being explained, then back out.
struct TourView: View {
    var onDone: () -> Void

    struct Page: Identifiable {
        let id: Int
        let eyebrow: String
        let title: String
        let points: [(symbol: String, text: String)]
        let image: String
        /// Where the zoom goes (0…1 of the screenshot) and how far.
        let focus: UnitPoint
        let zoom: CGFloat
        let color: Color
    }

    static let pageSeconds = 6.5

    private var pages: [Page] {
        let ai = AssistantName.current
        return [
            Page(id: 0, eyebrow: "Welcome to Orbit", title: "Your whole life, in one calm place",
                 points: [("sun.max.fill", "Today brings your events, tasks, habits, money and reading together"),
                          ("arrow.triangle.2.circlepath", "Everything syncs between your Mac and iPhone"),
                          ("lock.fill", "Your data and keys stay yours")],
                 image: "today", focus: .init(x: 0.5, y: 0.35), zoom: 1.12, color: Theme.lime),
            Page(id: 1, eyebrow: "Your day", title: "An AI summary that keeps up with you",
                 points: [("sparkles", "A morning brief with what matters today"),
                          ("sun.horizon.fill", "“Your day” rewrites itself as you spend, read and tick things off"),
                          ("lightbulb.fill", "Gentle nudges for the next few hours")],
                 image: "today", focus: Platform.isPhone ? .init(x: 0.5, y: 0.42) : .init(x: 0.18, y: 0.38), zoom: Platform.isPhone ? 1.7 : 2.3, color: Theme.orange),
            Page(id: 2, eyebrow: "Meet \(ai)", title: "An assistant that actually does things",
                 points: [("text.bubble.fill", "Chat or talk: it adds tasks, events, notes and expenses for you"),
                          ("fork.knife", "“I'm hungry”: places nearby with prices, reviews and directions"),
                          ("cloud.sun.fill", "What to wear, calculations, and reviews of your documents")],
                 image: "assistant", focus: Platform.isPhone ? .init(x: 0.5, y: 0.3) : .init(x: 0.85, y: 0.25), zoom: Platform.isPhone ? 1.25 : 2.2, color: Theme.pink),
            Page(id: 3, eyebrow: "Plan", title: "Tasks and calendar, planned for you",
                 points: [("checklist", "Tasks with due dates, priorities and repeats"),
                          ("calendar", "Apple and Google calendars side by side"),
                          ("moon.stars.fill", "Plan tomorrow in a minute each evening")],
                 image: "calendar", focus: Platform.isPhone ? .init(x: 0.5, y: 0.5) : .init(x: 0.92, y: 0.66), zoom: Platform.isPhone ? 1.35 : 2.4, color: Theme.cyan),
            Page(id: 4, eyebrow: "Money", title: "Every pound and dollar, logged for you",
                 points: [("envelope.fill", "Receipts from your email and bank texts land in Money on their own"),
                          ("doc.viewfinder", "Snap a paper receipt; Orbit reads it"),
                          ("bell.badge.fill", "Budgets per category, with alerts before you overspend")],
                 image: "money", focus: Platform.isPhone ? .init(x: 0.5, y: 0.3) : .init(x: 0.5, y: 0.6), zoom: Platform.isPhone ? 1.5 : 1.8, color: Theme.peach),
            Page(id: 5, eyebrow: "Reading", title: "Your library, reading time and streaks",
                 points: [("book.fill", "Currently reading, with progress and a reading timer"),
                          ("arrow.down.circle.fill", "Imports from Goodreads, Apple Books and Kindle"),
                          ("highlighter", "Your highlights, all in one place")],
                 image: "reading", focus: .init(x: 0.5, y: 0.35), zoom: 1.6, color: Theme.purple),
            Page(id: 6, eyebrow: "Dreams and places", title: "A bucket list, and a map of places to go",
                 points: [("mountain.2.fill", "Dreams you want to make happen, with trips planned around them"),
                          ("mappin.and.ellipse", "Save restaurants, shops and museums you love to Go to"),
                          ("map.fill", "Share from Google or Apple Maps straight into Orbit")],
                 image: "goto", focus: .init(x: 0.5, y: 0.35), zoom: 1.5, color: Theme.mint),
            Page(id: 7, eyebrow: "Everywhere", title: "Ready when you are",
                 points: [("macbook.and.iphone", "On your Mac and iPhone, always in sync"),
                          ("square.grid.2x2.fill", "Widgets, Siri and Shortcuts for quick adds"),
                          ("hand.wave.fill", "Let's set it up: it takes a minute")],
                 image: "insights", focus: .init(x: 0.5, y: 0.4), zoom: 1.3, color: Theme.lime),
        ]
    }

    @State private var index = 0
    @State private var zoomed = false
    @State private var revealed = false
    @State private var progress = 0.0
    @State private var paused = false
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        let page = pages[index]
        ZStack {
            LinearGradient(colors: [page.color.opacity(0.55), Theme.canvas], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: index)
            VStack(spacing: 0) {
                progressBars.padding(.horizontal, 20).padding(.top, Platform.isPhone ? 8 : 18)
                HStack {
                    if index > 0 {
                        Button { go(index - 1) } label: { Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)) }
                            .buttonStyle(.plain).padding(8)
                    }
                    Spacer()
                    if index < pages.count - 1 { Button("Skip") { finish() }.buttonStyle(.plain).font(Theme.ui(14, weight: .semibold)).padding(8) }
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                content(page)
            }
        }
        .contentShape(Rectangle())
        .onAppear { start() }
        .onDisappear { timerTask?.cancel() }
        #if os(macOS)
        .onKeyPress(.rightArrow) { go(index + 1); return .handled }
        .onKeyPress(.leftArrow) { go(index - 1); return .handled }
        .onKeyPress(.space) { go(index + 1); return .handled }
        .frame(width: 1000, height: 640)
        #endif
    }

    @ViewBuilder private func content(_ page: Page) -> some View {
        if Platform.isPhone {
            VStack(spacing: 18) {
                device(page).frame(maxHeight: .infinity)
                text(page).padding(.horizontal, 24)
                nextButton.padding(.horizontal, 24).padding(.bottom, 12)
            }
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -40 { go(index + 1) } else if v.translation.width > 40 { go(index - 1) }
            })
        } else {
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer()
                    text(page)
                    nextButton.frame(width: 200)
                    Spacer()
                }
                .frame(width: 330)
                device(page).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 44).padding(.bottom, 30)
        }
    }

    private func text(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(page.eyebrow.uppercased()).font(Theme.ui(12, weight: .bold)).tracking(1.2).foregroundStyle(Theme.inkSecondary)
            Text(page.title).font(Theme.display(Platform.isPhone ? 28 : 34)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(page.points.enumerated()), id: \.offset) { i, p in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: p.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                            .frame(width: 30, height: 30).background(Circle().fill(page.color))
                        Text(p.text).font(Theme.ui(Platform.isPhone ? 14 : 15)).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 5)
                    }
                    .opacity(revealed || i == 0 ? 1 : 0.0)
                    .offset(y: revealed || i == 0 ? 0 : 8)
                    .animation(.easeOut(duration: 0.45).delay(Double(i) * 0.18), value: revealed)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(page.id)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var nextButton: some View {
        Button {
            index == pages.count - 1 ? finish() : go(index + 1)
        } label: {
            Text(index == pages.count - 1 ? "Get started" : "Next").frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    }

    /// The screenshot inside a laptop or phone frame, zooming in on the focus and floating gently.
    private func device(_ page: Page) -> some View {
        let phone = Platform.isPhone
        let aspect: CGFloat = phone ? 1206.0 / 2622.0 : 1440.0 / 900.0
        let corner: CGFloat = phone ? 34 : 12
        return Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                screenshot(page.image)
                    .resizable().aspectRatio(contentMode: .fill)
                    .scaleEffect(zoomed ? page.zoom : 1, anchor: page.focus)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Theme.ink.opacity(0.9), lineWidth: phone ? 7 : 6))
            .shadow(color: .black.opacity(0.22), radius: 30, y: 18)
            .scaleEffect(zoomed ? 1 : 0.96)
            .offset(y: zoomed ? -4 : 6)
            .padding(phone ? 8 : 0)
            .frame(maxWidth: phone ? 300 : .infinity, maxHeight: .infinity)
            .id("device-\(page.id)")
            .transition(.asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity), removal: .opacity))
    }

    private func screenshot(_ name: String) -> Image {
        let file = (Platform.isPhone ? "phone-" : "mac-") + name
        if let url = Bundle.main.url(forResource: file, withExtension: "jpg", subdirectory: "Tour"), let img = PlatformImage.load(url) {
            return img.swiftUI
        }
        return Image(systemName: "photo")
    }

    private var progressBars: some View {
        HStack(spacing: 5) {
            ForEach(pages) { p in
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.ink.opacity(0.15))
                        Capsule().fill(Theme.ink).frame(width: g.size.width * (p.id < index ? 1 : p.id == index ? progress : 0))
                    }
                }
                .frame(height: 4)
                .contentShape(Rectangle())
                .onTapGesture { go(p.id) }
            }
        }
    }

    // MARK: Timing

    private func go(_ i: Int) {
        guard i >= 0 else { return }
        guard i < pages.count else { finish(); return }
        guard i != index else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { index = i; zoomed = false; revealed = false }
        start()
    }

    /// Settles the page, zooms in to the focus after a beat, eases back out near the end, then moves on.
    private func start() {
        timerTask?.cancel()
        progress = 0
        let page = index
        timerTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.6)) { zoomed = true }
            revealed = true
            let steps = 130
            for s in 1...steps {
                try? await Task.sleep(for: .seconds(Self.pageSeconds / Double(steps)))
                guard !Task.isCancelled, index == page else { return }
                progress = Double(s) / Double(steps)
                if s == steps * 4 / 5 { withAnimation(.easeInOut(duration: 1.1)) { zoomed = false } }
            }
            if page < pages.count - 1 { go(page + 1) } else { withAnimation { zoomed = true } }
        }
    }

    private func finish() {
        timerTask?.cancel()
        UserDefaults.standard.set(true, forKey: "tourSeen")
        onDone()
    }
}
