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
        // Icon and logo: the Joshu mark; thumbnail: your photo.
        for (name, side) in [("icon.png", 29.0), ("icon@2x.png", 58), ("icon@3x.png", 87), ("logo.png", 50), ("logo@2x.png", 100), ("logo@3x.png", 150)] {
            if let png = render(OrbitMark(size: side), side: side) { images[name] = png.base64EncodedString() }
        }
        if card.showPhoto, let photo = CardPhoto.image ?? photo {
            if let t = photo.square(side: 90, type: .png) { images["thumbnail.png"] = t.base64EncodedString() }
            if let t = photo.square(side: 180, type: .png) { images["thumbnail@2x.png"] = t.base64EncodedString() }
            if let t = photo.square(side: 270, type: .png) { images["thumbnail@3x.png"] = t.base64EncodedString() }
        }
        let body: [String: Any] = [
            "card": [
                "name": card.name, "headline": card.headline, "company": card.company, "email": card.email, "phone": card.phone,
                "location": card.location, "bio": card.bio,
                "links": card.filledLinks.map { ["title": $0.kind == .other ? "Link" : $0.kind.title, "url": $0.url, "handle": $0.handle] },
            ],
            "qr": card.qrPayload,
            "color": card.isDark ? "#141416" : (card.color.hexString ?? "#E6FF1F"),
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

    private static func render(_ view: some View, side: CGFloat) -> Data? {
        let r = ImageRenderer(content: view.frame(width: side, height: side))
        r.scale = 1
        guard let cg = r.cgImage else { return nil }
        return ImageData.encode(cg, size: CGSize(width: cg.width, height: cg.height), type: .png, quality: 1, crop: nil)
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
