import SwiftUI

/// The welcome tour, shown the first time you open Joshu on a Mac or iPhone (and any time from Settings › General or
/// Joshu › Take the Tour): the same pictures as the App Store, the iPhone set on iPhone (swipe through) and the Mac set
/// on the Mac. They're made by `ORBIT_STORE_SHOTS` (App/StoreShots.swift) and bundled as Support/Tour/store-*.jpg.
struct TourView: View {
    var onDone: () -> Void

    @State private var index = 0
    private let phone = Platform.isPhone

    /// This device's pictures, in order.
    private let pages: [String] = {
        let prefix = Platform.isPhone ? "store-phone-" : "store-mac-"
        let urls = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: "Tour") ?? []
        return urls.map { $0.deletingPathExtension().lastPathComponent }.filter { $0.hasPrefix(prefix) }.sorted()
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            pictures
            footer
        }
        // The current picture, blurred, fills the screen behind it, so its colours run to the edges.
        .background {
            ZStack {
                Color(hex: 0xFBFBF8)
                if let img = image(pages.indices.contains(index) ? pages[index] : "") {
                    img.resizable().aspectRatio(contentMode: .fill).blur(radius: 60).opacity(0.9)
                        .animation(.easeInOut(duration: 0.4), value: index)
                }
            }
            .ignoresSafeArea()
            .clipped()
        }
        .environment(\.colorScheme, .light)
        #if os(macOS)
        .onKeyPress(.rightArrow) { go(index + 1); return .handled }
        .onKeyPress(.leftArrow) { go(index - 1); return .handled }
        .frame(width: 1040, height: 766)
        #endif
    }

    private var header: some View {
        HStack(spacing: 5) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule().fill(i <= index ? Color(hex: 0x111111) : Color(hex: 0x111111).opacity(0.14)).frame(height: 4)
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture { go(i) }
            }
            Button("Skip") { finish() }.buttonStyle(.plain).font(Theme.ui(14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x111111)).fixedSize().padding(.leading, 12)
        }
        .padding(.horizontal, phone ? 20 : 28).padding(.top, phone ? 8 : 16).padding(.bottom, 6)
    }

    @ViewBuilder private var pictures: some View {
        #if os(iOS)
        TabView(selection: $index) {
            ForEach(pages.indices, id: \.self) { i in picture(pages[i]).tag(i) }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        picture(pages.indices.contains(index) ? pages[index] : "")
            .id(index)
            .transition(.opacity)
            .contentShape(Rectangle())
            .onTapGesture { go(index + 1) }
        #endif
    }

    private func image(_ name: String) -> Image? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Tour"), let img = PlatformImage.load(url) else { return nil }
        return img.swiftUI
    }

    private func picture(_ name: String) -> some View {
        Group {
            if let img = image(name) {
                img.resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: phone ? 22 : 16, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
            } else {
                Color.clear
            }
        }
        .padding(.horizontal, phone ? 0 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if index > 0 && !phone {
                Button { go(index - 1) } label: { Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(Color(hex: 0x111111))
                    .background(Circle().fill(Color(hex: 0x111111).opacity(0.06)))
            }
            Button { index >= pages.count - 1 ? finish() : go(index + 1) } label: {
                HStack(spacing: 8) {
                    Text(index >= pages.count - 1 ? "Get started" : "Next")
                    Image(systemName: index >= pages.count - 1 ? "arrow.right.circle.fill" : "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: phone ? .infinity : 260)
        }
        .padding(.horizontal, phone ? 24 : 28).padding(.top, 8).padding(.bottom, phone ? 10 : 18)
    }

    private func go(_ i: Int) {
        guard i >= 0 else { return }
        guard i < pages.count else { finish(); return }
        withAnimation(.easeInOut(duration: 0.3)) { index = i }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "tourSeen")
        onDone()
    }
}

// MARK: - Devices (used for the App Store pictures)

/// An iPhone 17 Pro: titanium edge, black border, Dynamic Island and side buttons.
struct IPhoneFrame: View {
    let image: Image
    var zoom: CGFloat = 1
    var focus: UnitPoint = .center

    /// The whole phone's width ÷ height, worked out so the screen inside the bezels has exactly a screenshot's shape
    /// (1206 × 2622): the app shows whole, never cropped at the sides.
    static let aspect: CGFloat = 1 / ((1 - 0.13) * 2622.0 / 1206.0 + 0.13)

    var body: some View {
        GeometryReader { g in
            let aspect = Self.aspect
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
        .aspectRatio(Self.aspect, contentMode: .fit)
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
