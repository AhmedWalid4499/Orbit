import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
import AuthenticationServices
typealias PlatformImage = UIImage
#endif

/// The few things that differ between the Mac and iPhone apps, so shared code stays the same on both.
@MainActor
enum Platform {
    nonisolated static var isPhone: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// The account's full name on a Mac; on iPhone the name comes from Settings (synced as "userName").
    nonisolated static var fullUserName: String {
        #if os(macOS)
        NSFullUserName()
        #else
        ""
        #endif
    }

    /// The name Orbit calls you, with the Mac account name as a fallback.
    nonisolated static var userName: String {
        let saved = UserDefaults.standard.string(forKey: "userName") ?? ""
        return saved.isEmpty ? fullUserName : saved
    }

    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    static func bringToFront() {
        #if os(macOS)
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }

    #if os(iOS)
    private static var session: ASWebAuthenticationSession?
    private static let anchor = AuthAnchor()
    #endif

    /// Opens a sign-in page. On the Mac it's the browser and the result comes back through Orbit's URL scheme or a
    /// loopback server; on iPhone it's an in-app browser sheet, and a redirect to `callbackScheme` is returned here.
    static func webAuth(_ url: URL, callbackScheme: String?) async -> URL? {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        return nil
        #else
        return await withCheckedContinuation { (c: CheckedContinuation<URL?, Never>) in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme ?? "orbit-loopback") { callback, _ in
                Task { @MainActor in session = nil }
                c.resume(returning: callback)
            }
            s.presentationContextProvider = anchor
            s.prefersEphemeralWebBrowserSession = false
            session = s
            s.start()
        }
        #endif
    }

    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    static func copy(image: PlatformImage) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #else
        UIPasteboard.general.image = image
        #endif
    }

    /// Closes the iPhone sign-in sheet once a loopback server has the result.
    static func endWebAuth() {
        #if os(iOS)
        session?.cancel()
        session = nil
        #endif
    }
}

#if os(iOS)
private final class AuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
#endif

// MARK: - Images

extension PlatformImage {
    static func load(_ url: URL) -> PlatformImage? {
        #if os(macOS)
        NSImage(contentsOf: url)
        #else
        UIImage(contentsOfFile: url.path)
        #endif
    }

    var cg: CGImage? {
        #if os(macOS)
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        if let cgImage { return cgImage }
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { _ in draw(at: .zero) }.cgImage
        #endif
    }

    /// Scaled so the longer side is at most `maxSide`, on white, as JPEG.
    func jpeg(maxSide: CGFloat, quality: CGFloat = 0.82) -> Data? {
        guard let cg else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h))
        return ImageData.encode(cg, size: CGSize(width: (w * scale).rounded(), height: (h * scale).rounded()), type: .jpeg, quality: quality, crop: nil)
    }

    /// Center-cropped square of at most `side` pixels, as PNG or JPEG.
    func square(side: CGFloat, type: UTType = .png, quality: CGFloat = 0.85) -> Data? {
        guard let cg else { return nil }
        let s = min(cg.width, cg.height)
        let out = min(side, CGFloat(s))
        return ImageData.encode(cg, size: CGSize(width: out, height: out), type: type, quality: quality,
                                crop: CGRect(x: (cg.width - s) / 2, y: (cg.height - s) / 2, width: s, height: s))
    }

    static func from(_ cg: CGImage) -> PlatformImage {
        #if os(macOS)
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #else
        UIImage(cgImage: cg)
        #endif
    }

    /// A SwiftUI image for either platform.
    var swiftUI: Image {
        #if os(macOS)
        Image(nsImage: self)
        #else
        Image(uiImage: self)
        #endif
    }
}

enum ImageData {
    static func encode(_ cg: CGImage, size: CGSize, type: UTType, quality: CGFloat, crop: CGRect?) -> Data? {
        let source = crop.flatMap { cg.cropping(to: $0) } ?? cg
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        if type == .jpeg { ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size)) }
        ctx.draw(source, in: CGRect(origin: .zero, size: size))
        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

// MARK: - Colours

extension Color {
    /// A colour that switches between light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
        }
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let (r, g, b) = rgb(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
        #else
        self.init(uiColor: UIColor { traits in
            let (r, g, b) = rgb(traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #endif
    }

    /// "#RRGGBB" of a colour, for files the widgets read.
    var hexString: String? {
        #if os(macOS)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #endif
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

extension ToggleStyle where Self == OrbitCheckboxStyle {
    /// A checkbox on the Mac; a tappable check circle on iPhone (which has no checkbox style).
    static var orbitCheckbox: OrbitCheckboxStyle { OrbitCheckboxStyle() }
}

struct OrbitCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
        #else
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                    .foregroundStyle(configuration.isOn ? Theme.ink : Theme.inkMuted)
                configuration.label
            }
        }
        .buttonStyle(.plain)
        #endif
    }
}

/// Opens Orbit's settings: the Settings window on the Mac, the settings sheet on iPhone.
struct OpenSettingsLink<Label: View>: View {
    @ViewBuilder var label: () -> Label

    var body: some View {
        #if os(macOS)
        SettingsLink(label: label)
        #else
        Button { AppState.current?.settingsOpen = true } label: { label() }
        #endif
    }
}

extension View {
    /// A sheet's size on the Mac. On iPhone, sheets fill the screen, so this does nothing there.
    func sheetFrame(width: CGFloat, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }
}

extension View {
    /// Esc closes things on the Mac; iPhone has no Esc key.
    func onEscape(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}

/// A text link button: the Mac's link style, or plain tinted text on iPhone.
struct OrbitLinkStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Button(configuration).buttonStyle(.link)
        #else
        Button(configuration).buttonStyle(.borderless).foregroundStyle(Color.accentColor)
        #endif
    }
}

extension PrimitiveButtonStyle where Self == OrbitLinkStyle {
    static var orbitLink: OrbitLinkStyle { OrbitLinkStyle() }
}

extension View {
    /// Lets a sheet built for a tall Mac window scroll on a phone screen.
    @ViewBuilder func phoneScrollable() -> some View {
        #if os(iOS)
        ScrollView { self }.scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }
}

extension View {
    /// Scrolls on the Mac, where it sits in a fixed-size pane; on iPhone the whole screen already scrolls.
    @ViewBuilder func macScrollable() -> some View {
        #if os(macOS)
        ScrollView { self }.scrollIndicators(.never)
        #else
        self
        #endif
    }
}

/// A row when it fits; otherwise a two-column grid (`grid`) or a column.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 12
    var grid = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content() }
            if grid {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)], spacing: spacing) { content() }
            } else {
                VStack(alignment: .leading, spacing: spacing) { content() }
            }
        }
    }
}

/// A page or section title with its buttons: one row when it fits, otherwise the buttons wrap under the title.
/// On iPhone a page title (`isPage`) is left to the navigation bar.
struct PageHeader<Subtitle: View, Actions: View>: View {
    let title: String
    var size: CGFloat = 22
    var isPage = false
    @ViewBuilder var subtitle: () -> Subtitle
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                heading
                Spacer(minLength: 8)
                HStack(spacing: 8) { actions() }.fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                heading
                FlowLayout(spacing: 8) { actions() }
            }
        }
    }

    @ViewBuilder private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !(isPage && Platform.isPhone) { Text(title).font(Theme.display(size)) }
            subtitle()
        }
    }
}

extension PageHeader where Subtitle == EmptyView {
    init(title: String, size: CGFloat = 22, isPage: Bool = false, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(title: title, size: size, isPage: isPage, subtitle: { EmptyView() }, actions: actions)
    }
}
