import Foundation
import SwiftUI
#if os(iOS)
import PassKit
#endif

/// Your card as an Apple Wallet pass. Joshu's server makes and signs it (supabase/functions/wallet-pass), so the pass
/// certificate never ships in the app; you need to be signed in to your Joshu account.
@MainActor
enum WalletPass {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether the server can make passes (the function is deployed and its certificate set up). Asked once per launch.
    private static var readyCache: Bool?
    static func isReady() async -> Bool {
        if let readyCache { return readyCache }
        guard let url = URL(string: "\(SupabaseConfig.url)/functions/v1/wallet-pass"), SupabaseConfig.isConfigured else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(SupabaseConfig.key)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return false }  // offline: ask again later
        let ready = (response as? HTTPURLResponse)?.statusCode == 200
            && (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["ready"] as? Bool ?? false)
        readyCache = ready
        return ready
    }

    static func make(_ card: ProfileCard, photo: PlatformImage?) async throws -> Data {
        guard CloudAuth.session != nil else { throw Failure(message: "Sign in to your Joshu account (Settings › Account) to add your card to Wallet.") }
        guard let url = URL(string: "\(SupabaseConfig.url)/functions/v1/wallet-pass") else { throw Failure(message: "Joshu's server isn't set up in this copy.") }
        var images: [String: String] = [:]
        let look = WalletLook(card: card, hasPhoto: (CardPhoto.image ?? photo) != nil)
        // The app icon for notifications; the "joshu" word mark at the top of the pass, like on your card.
        for (name, side) in [("icon.png", 29.0), ("icon@2x.png", 58), ("icon@3x.png", 87)] {
            if let png = render(OrbitMark(size: side), size: CGSize(width: side, height: side), scale: 1) { images[name] = png.base64EncodedString() }
        }
        for (suffix, scale) in [("", 1.0), ("@2x", 2), ("@3x", 3)] {
            if let png = render(WalletWordmark(ink: look.ink, dot: look.accent), size: CGSize(width: 90, height: 50), scale: scale) {
                images["logo\(suffix).png"] = png.base64EncodedString()
            }
            // The banner: the top of your card (its photo or colour, your name and what you do), drawn by the app.
            if let png = render(WalletStrip(card: card, photo: photo, backdrop: CardPhoto.image), size: WalletStrip.size, scale: scale) {
                images["strip\(suffix).png"] = png.base64EncodedString()
            }
        }
        let body: [String: Any] = [
            "card": [
                "name": card.name, "headline": card.headline, "company": card.company, "email": card.email, "phone": card.phone,
                "location": card.location, "bio": card.bio,
                "links": card.filledLinks.map { ["title": $0.kind == .other ? "Link" : $0.kind.title, "url": $0.url, "handle": $0.handle] },
            ],
            "qr": card.qrPayload,
            "qrText": card.qrTarget == "contact" ? "Scan to save my contact" : "Scan to open my link",
            "color": look.background, "ink": look.inkHex, "label": look.labelHex,
            "layout": "strip",
            "images": images,
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(try await CloudAuth.accessToken())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
            if status == 404 || status == 503 { throw Failure(message: "Wallet passes aren't switched on yet. (Owner: run scripts/setup-wallet-pass.sh.)") }
            throw Failure(message: msg ?? "Couldn't make the pass (\(status)).")
        }
        return data
    }

    private static func render(_ view: some View, size: CGSize, scale: CGFloat) -> Data? {
        let r = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        r.scale = scale
        guard let cg = r.cgImage else { return nil }
        return ImageData.encode(cg, size: CGSize(width: cg.width, height: cg.height), type: .png, quality: 1, crop: nil)
    }
}

/// The pass's colours, the same as the card in the app: the photo card's dark panel with its accent, or the colour card.
struct WalletLook {
    let card: ProfileCard
    /// Whether there's a picture for the photo card (its own background, or your profile photo).
    let hasPhoto: Bool
    var isPhoto: Bool { card.style == "photo" && card.showPhoto && hasPhoto }
    var background: String { isPhoto ? "#111113" : (card.isDark ? "#141416" : (card.color.hexString ?? "#E6FF1F")) }
    var ink: Color { isPhoto || card.isDark ? Color(hex: 0xF4F4F5) : Theme.stickerInk }
    var inkHex: String { isPhoto || card.isDark ? "#F4F4F5" : "#111111" }
    var accent: Color { isPhoto ? (card.isDark ? Theme.orange : card.color) : (card.isDark ? Theme.lime : Theme.stickerInk) }
    /// Field labels: the accent on the photo card, a softer ink on the colour card.
    var labelHex: String {
        if isPhoto { return card.isDark ? "#EDAA2F" : (card.color.hexString ?? "#E6FF1F") }
        return card.isDark ? "#A1A1AA" : "#3C3C43"
    }
}

/// "joshu" with its coloured dot, as on the card.
struct WalletWordmark: View {
    let ink: Color
    let dot: Color
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            Text("joshu").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(ink)
            Circle().fill(dot).frame(width: 6, height: 6).offset(y: 6)
            Spacer(minLength: 0)
        }
    }
}

/// The top of your card as Wallet's banner (375 × 144 points): the same photo, colours, name and role.
struct WalletStrip: View {
    static let size = CGSize(width: 375, height: 144)
    let card: ProfileCard
    let photo: PlatformImage?
    let backdrop: PlatformImage?

    private var look: WalletLook { WalletLook(card: card, hasPhoto: (backdrop ?? photo) != nil) }
    private var role: String {
        [card.headline, card.company].filter { !$0.isEmpty }.joined(separator: card.headline.isEmpty || card.company.isEmpty ? "" : " at ")
    }

    var body: some View {
        if look.isPhoto, let cover = backdrop ?? photo { photoStrip(cover) } else { colorStrip }
    }

    private func photoStrip(_ cover: PlatformImage) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: 0x111113)
            cover.swiftUI.resizable().scaledToFill().frame(width: Self.size.width, height: Self.size.height).clipped()
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.3),
                                   .init(color: Color(hex: 0x111113).opacity(0.8), location: 0.75), .init(color: Color(hex: 0x111113), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                if !card.location.isEmpty {
                    Text(card.location.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.8).opacity(0.85).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(card.name.isEmpty ? "My card" : card.name).font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 15)).foregroundStyle(look.accent)
                }
                if !role.isEmpty { Text(role).font(.system(size: 13)).opacity(0.85).lineLimit(1) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private var colorStrip: some View {
        HStack(spacing: 14) {
            if card.showPhoto, let photo {
                photo.swiftUI.resizable().scaledToFill()
                    .frame(width: 76, height: 76).clipShape(Circle())
                    .overlay(Circle().strokeBorder(look.ink.opacity(0.15), lineWidth: 3))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name.isEmpty ? "My card" : card.name).font(.system(size: 26, weight: .bold, design: .serif))
                    .lineLimit(2).minimumScaleFactor(0.6)
                let sub = [card.headline, card.company].filter { !$0.isEmpty }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.system(size: 13, weight: .medium)).opacity(0.8).lineLimit(2) }
                if !card.location.isEmpty {
                    Label(card.location, systemImage: "mappin").font(.system(size: 11, weight: .medium)).opacity(0.65).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(look.ink)
        .padding(.horizontal, 18)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(card.isDark ? Color(hex: 0x141416) : card.color)
    }
}

/// "Add to Apple Wallet": Apple's own button on iPhone; on the Mac, the pass is made and handed to the share menu
/// (AirDrop it to your iPhone) since Wallet lives on the phone.
struct AddToWalletButton: View {
    let card: ProfileCard
    let photo: PlatformImage?
    @State private var busy = false
    @State private var error: String?
    @State private var ready = Snapshot.isDemo
    #if os(iOS)
    @State private var pass: PKPass?
    #else
    @State private var file: URL?
    #endif

    var body: some View {
        VStack(spacing: 6) {
            #if os(iOS)
            if ready && PKAddPassesViewController.canAddPasses() {
                WalletBadge { Task { await make() } }
                    .frame(height: 48).opacity(busy ? 0.5 : 1).disabled(busy)
                    .sheet(isPresented: Binding(get: { pass != nil }, set: { if !$0 { pass = nil } })) {
                        if let pass { AddPassSheet(pass: pass).ignoresSafeArea() }
                    }
            }
            #else
            if ready {
            HStack(spacing: 10) {
                Button { Task { await make() } } label: {
                    Label(busy ? "Making the pass…" : "Apple Wallet pass", systemImage: "wallet.pass.fill")
                }
                .buttonStyle(SoftButtonStyle()).disabled(busy)
                if let file {
                    ShareLink(item: file) { Label("Send to iPhone…", systemImage: "square.and.arrow.up") }.buttonStyle(SoftButtonStyle())
                }
            }
            }
            #endif
            if let error { Text(error).font(Theme.ui(11)).foregroundStyle(Theme.orange).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
        }
        .task { if !ready { ready = await WalletPass.isReady() } }
    }

    private func make() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let data = try await WalletPass.make(card, photo: photo)
            #if os(iOS)
            pass = try PKPass(data: data)
            #else
            let url = FileManager.default.temporaryDirectory.appending(path: "\(card.name.isEmpty ? "My card" : card.name).pkpass")
            try data.write(to: url)
            file = url
            #endif
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if os(iOS)
/// Apple's "Add to Apple Wallet" button (its look is required by Apple's guidelines).
private struct WalletBadge: UIViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> PKAddPassButton {
        let b = PKAddPassButton(addPassButtonStyle: .black)
        b.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return b
    }
    func updateUIView(_ uiView: PKAddPassButton, context: Context) { context.coordinator.action = action }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

private struct AddPassSheet: UIViewControllerRepresentable {
    let pass: PKPass
    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}
#endif
