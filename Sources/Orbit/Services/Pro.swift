import Foundation
import StoreKit
import SwiftUI

/// Joshu Pro: the subscription that unlocks the AI assistant (named by you) and everything built on it.
///
/// Free: everything except the AI. That means no assistant, morning brief, email summaries, day summary, money coach,
/// LinkedIn tab (it's the AI reading your Gmail) or AI extras, and one email account.
/// Pro ($7.99 a month or $59.99 a year): all of it, with the AI paid for by Joshu through its own server, so there's
/// no key to set up.
///
/// You're Pro when the App Store says so (StoreKit), when the Joshu server has a grant for your account (a purchase
/// made on another device, or one given by hand), or when you use your own Anthropic key (the owner's setup).
@MainActor
final class Pro: ObservableObject {
    static let shared = Pro()

    static let monthlyID = "joshu.pro.monthly"
    static let yearlyID = "joshu.pro.yearly"
    static let productIDs = [monthlyID, yearlyID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var storeActive = false
    @Published private(set) var serverActive = UserDefaults.standard.bool(forKey: "pro.server")
    @Published private(set) var busy = false
    @Published var message: String?
    /// The one-time "Welcome to Joshu Pro" page: shown the first time Pro is on for this account.
    @Published private(set) var showWelcome = false

    private var updates: Task<Void, Never>?

    private init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
    }

    /// Your own Anthropic key: the AI works on it directly (no subscription needed for you).
    var ownKey: Bool { Keychain.apiKey != nil }
    var isPro: Bool { storeActive || serverActive || ownKey || Snapshot.isDemo }

    /// The AI through Joshu's server (Pro without your own key). Read by the AI client, so it's kept in UserDefaults.
    nonisolated static var serverAI: Bool { UserDefaults.standard.bool(forKey: "pro.serverAI") }

    /// Free accounts connect one email; Pro, as many as they like.
    func canAddEmail(existing: Int) -> Bool { isPro || existing == 0 }

    /// Joshu Pro gets the Pro icon: on iPhone the app icon itself (iOS shows a short note when it changes), on the
    /// Mac the Dock icon while Joshu runs (the app's own file keeps the usual icon, so its signature stays intact).
    func applyIcon() {
        guard !Snapshot.isActive else { return }
        #if os(iOS)
        let want: String? = isPro ? "AppIconPro" : nil
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != want else { return }
        UIApplication.shared.setAlternateIconName(want) { _ in }
        #else
        NSApp.applicationIconImage = isPro ? Self.macProIcon
            : Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:)) ?? AppIcon.make()
        // And while Joshu is closed: the Dock asks the plug-in in Contents/PlugIns, which reads this.
        if UserDefaults.standard.bool(forKey: "pro.dockIcon") != isPro {
            UserDefaults.standard.set(isPro, forKey: "pro.dockIcon")
            UserDefaults.standard.synchronize()
            DistributedNotificationCenter.default().postNotificationName(.init("com.personal.orbit.dockIcon"), object: nil, deliverImmediately: true)
        }
        #endif
    }

    #if os(macOS)
    /// The Pro logo with the margin Mac icons have around their tile.
    private static let macProIcon: NSImage? = {
        let renderer = ImageRenderer(content: ProLogo(size: 824).padding(100).frame(width: 1024, height: 1024))
        renderer.scale = 1
        return renderer.nsImage
    }()
    #endif

    private var welcomeKey: String { "pro.welcomed." + (CloudAuth.session?.userID ?? "device") }

    func welcomeDone() {
        UserDefaults.standard.set(true, forKey: welcomeKey)
        showWelcome = false
    }

    // MARK: Status

    /// Checks the App Store and the Joshu server, and loads prices.
    func refresh() async {
        if products.isEmpty { products = ((try? await Product.products(for: Self.productIDs)) ?? []).sorted { $0.price < $1.price } }
        var active = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result, Self.productIDs.contains(t.productID), t.revocationDate == nil else { continue }
            if (t.expirationDate ?? .distantFuture) > .now {
                active = true
                await report(result)
            }
        }
        storeActive = active
        await checkServer()
        // Not before there's an account: without one the assistant can't reach Joshu's server yet.
        if (storeActive || serverActive) && CloudAuth.session != nil && !Snapshot.isActive && !UserDefaults.standard.bool(forKey: welcomeKey) { showWelcome = true }
        UserDefaults.standard.set((storeActive || serverActive) && CloudAuth.session != nil, forKey: "pro.serverAI")
        applyIcon()
        AIAssistant.shared.reloadKey()
    }

    /// The Joshu server's record for this account (purchases from other devices, or a grant).
    private func checkServer() async {
        guard !Snapshot.isActive, Keychain.isAvailable else { return }
        guard let session = CloudAuth.session else {
            // Signed out: a grant or purchase on the server belongs to the account, not this device.
            serverActive = false
            UserDefaults.standard.set(false, forKey: "pro.server")
            return
        }
        guard var c = URLComponents(string: "\(SupabaseConfig.url)/rest/v1/entitlements") else { return }
        c.queryItems = [.init(name: "select", value: "pro_until"), .init(name: "user_id", value: "eq.\(session.userID)")]
        guard let url = c.url, let token = try? await CloudAuth.accessToken() else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
        let until = rows.first.flatMap { J.date($0["pro_until"]) }
        serverActive = (until ?? .distantPast) > .now
        UserDefaults.standard.set(serverActive, forKey: "pro.server")
    }

    /// Tells the Joshu server about an App Store purchase (signed by Apple), so the AI server knows you're Pro
    /// and your other devices do too.
    private func report(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard CloudAuth.session != nil, let token = try? await CloudAuth.accessToken(),
              let url = URL(string: "\(SupabaseConfig.url)/functions/v1/subscription") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["signedTransaction": result.jwsRepresentation])
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: Buying

    func buy(_ id: String) async {
        message = nil
        if products.isEmpty { products = ((try? await Product.products(for: Self.productIDs)) ?? []).sorted { $0.price < $1.price } }
        guard let product = products.first(where: { $0.id == id }) else {
            message = "The App Store isn't answering right now. Check your connection and try again."
            return
        }
        busy = true
        defer { busy = false }
        do {
            // Ties the purchase to your Joshu account, so renewals and refunds reach the right account.
            let options: Set<Product.PurchaseOption> = CloudAuth.session.flatMap { UUID(uuidString: $0.userID) }.map { [.appAccountToken($0)] } ?? []
            switch try await product.purchase(options: options) {
            case .success(let result):
                if case .verified(let t) = result { await t.finish() }
                await refresh()
                message = isPro ? "Welcome to Joshu Pro." : nil
            case .pending: message = "Your purchase is waiting for approval."
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = isPro ? "Your Pro subscription is back." : "No Pro subscription found for this Apple ID."
    }

    /// Price shown on a plan button: the App Store's (in your currency), or the list price until that loads.
    func price(_ id: String) -> String {
        if let p = products.first(where: { $0.id == id }) { return p.displayPrice }
        return id == Self.yearlyID ? "$59.99" : "$7.99"
    }
}
