import Foundation
import SwiftUI
import WebKit

/// Sends your reading back to Goodreads: progress, shelf (reading / read) and your review with stars.
/// Goodreads closed its public API in 2020, so Orbit does what you'd do on the website: you sign in to Goodreads once
/// inside Orbit, and Orbit then posts through that sign-in in the background. Nothing opens in front of you.
/// If Goodreads changes its website this can stop working; Orbit then says so instead of failing quietly.
@MainActor
final class GoodreadsSync: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = GoodreadsSync()

    @Published private(set) var signedIn = UserDefaults.standard.bool(forKey: "goodreads.signedIn")
    /// Push progress automatically when it changes in Orbit (on by default once signed in).
    @Published var autoProgress = UserDefaults.standard.object(forKey: "goodreads.autoProgress") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoProgress, forKey: "goodreads.autoProgress") }
    }
    @Published var status: String?

    private var web: WKWebView?
    private var loaded: CheckedContinuation<URL?, Never>?
    /// Goodreads book IDs found for your books, by Orbit book.
    private var ids: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "goodreads.ids") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "goodreads.ids") }
    }
    /// Last progress sent per book, so the same number isn't posted twice.
    private var sent: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "goodreads.sent") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "goodreads.sent") }
    }

    static let signInURL = URL(string: "https://www.goodreads.com/user/sign_in")!

    func markSignedIn(_ on: Bool) {
        signedIn = on
        UserDefaults.standard.set(on, forKey: "goodreads.signedIn")
    }

    func signOut() async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records.filter { $0.displayName.contains("goodreads") })
        markSignedIn(false)
    }

    // MARK: What Orbit sends

    private var pending: [String: Task<Void, Never>] = [:]
    /// Sends progress a few seconds after it stops changing (dragging the slider sends once, not fifty times).
    func schedule(_ book: Book) {
        guard signedIn, autoProgress else { return }
        let key = book.uuid.isEmpty ? book.matchKey : book.uuid
        pending[key]?.cancel()
        pending[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.pushProgress(book)
        }
    }

    /// Your progress on `book` (and its shelf), when it changed since last time.
    @discardableResult
    func pushProgress(_ book: Book, force: Bool = false) async -> String {
        guard signedIn else { return "Sign in to Goodreads in Settings › Connections first." }
        let percent = Int((book.progress * 100).rounded())
        let key = book.uuid.isEmpty ? book.matchKey : book.uuid
        guard force || sent[key] != percent else { return "Goodreads already has \(percent)%." }
        guard let id = await goodreadsID(for: book) else { return "Couldn't find “\(book.title)” on Goodreads." }
        guard await open("https://www.goodreads.com/review/edit/\(id)") else { return signedOutMessage }
        var result = await post(path: "/shelf/add_to_shelf", fields: ["name": shelf(for: book), "book_id": id, "a": ""])
        if book.status != .read, percent > 0, percent < 100 {
            var fields = ["user_status[book_id]": id, "user_status[body]": ""]
            if book.pageCount > 0 { fields["user_status[page]"] = "\(Int((book.progress * Double(book.pageCount)).rounded()))" }
            else { fields["user_status[percent]"] = "\(percent)" }
            result = await post(path: "/user_status", fields: fields)
        }
        guard result else { return "Goodreads didn't accept the update. Try again later." }
        sent[key] = percent
        status = "Sent \(book.status == .read ? "“read”" : "\(percent)%") for “\(book.title)” to Goodreads."
        return status ?? ""
    }

    /// Posts (or replaces) your review and star rating for `book` on Goodreads.
    func postReview(_ book: Book, text: String, rating: Int) async -> String {
        guard signedIn else { return "Sign in to Goodreads in Settings › Connections first." }
        guard let id = await goodreadsID(for: book) else { return "Couldn't find “\(book.title)” on Goodreads." }
        guard await open("https://www.goodreads.com/review/edit/\(id)") else { return signedOutMessage }
        // Fill Goodreads' own review form on that page and send it, keeping any fields it has (shelves, dates).
        let js = """
        const area = document.querySelector('textarea[name="review[review]"]');
        if (!area) return 'noform';
        const form = area.form;
        const data = new FormData(form);
        data.set('review[review]', text);
        if (rating > 0) data.set('review[rating]', String(rating));
        const res = await fetch(form.action, { method: 'POST', body: data, credentials: 'include', redirect: 'follow' });
        return (res.ok && !res.url.includes('sign_in') && !res.url.includes('/user/new')) ? 'ok' : ('status ' + res.status);
        """
        let out = (try? await web?.callAsyncJavaScript(js, arguments: ["text": text, "rating": rating], contentWorld: .page)) as? String
        switch out {
        case "ok":
            status = "Posted your review of “\(book.title)” to Goodreads."
            return status ?? ""
        case "noform": return "Goodreads' review page has changed, so Joshu couldn't post it. Your review is saved in Joshu."
        default: return "Goodreads didn't accept the review (\(out ?? "no answer")). It's saved in Joshu."
        }
    }

    private var signedOutMessage: String {
        markSignedIn(false)
        return "Your Goodreads sign-in ran out. Sign in again in Settings › Connections › Goodreads."
    }

    private func shelf(for book: Book) -> String {
        switch book.status {
        case .read: "read"
        case .reading: "currently-reading"
        default: "to-read"
        }
    }

    // MARK: Finding the book

    /// The Goodreads ID: from the Goodreads import, a cached match, or Goodreads' own search.
    func goodreadsID(for book: Book) async -> String? {
        if book.externalID.hasPrefix("goodreads:") { return String(book.externalID.dropFirst(10)) }
        let key = book.uuid.isEmpty ? book.matchKey : book.uuid
        if let id = ids[key] { return id }
        let q = book.isbn.isEmpty ? "\(book.title.split(separator: ":").first ?? "") \(book.author)" : book.isbn
        var c = URLComponents(string: "https://www.goodreads.com/book/auto_complete")!
        c.queryItems = [.init(name: "format", value: "json"), .init(name: "q", value: q)]
        guard let (data, _) = try? await URLSession.shared.data(from: c.url!),
              let hits = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let id = hits.first?["bookId"] as? String else { return nil }
        ids[key] = id
        return id
    }

    // MARK: The hidden browser

    /// Loads a Goodreads page in the background; false when it sends you to sign in.
    private func open(_ address: String) async -> Bool {
        let w = web ?? {
            let v = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: WKWebViewConfiguration())
            v.navigationDelegate = self
            web = v
            return v
        }()
        let final: URL? = await withCheckedContinuation { c in
            loaded?.resume(returning: nil)
            loaded = c
            w.load(URLRequest(url: URL(string: address)!))
        }
        guard let u = final?.absoluteString else { return false }
        return !u.contains("sign_in") && !u.contains("/user/new")
    }

    /// POSTs a form to Goodreads from the loaded page, with its security token.
    private func post(path: String, fields: [String: String]) async -> Bool {
        let js = """
        const token = document.querySelector('meta[name="csrf-token"]')?.content || '';
        const data = new FormData();
        data.append('authenticity_token', token);
        for (const [k, v] of Object.entries(fields)) data.append(k, v);
        const res = await fetch(path, { method: 'POST', body: data, credentials: 'include', headers: { 'X-CSRF-Token': token } });
        return res.ok && !res.url.includes('sign_in') && !res.url.includes('/user/new');
        """
        return (try? await web?.callAsyncJavaScript(js, arguments: ["path": path, "fields": fields], contentWorld: .page)) as? Bool ?? false
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.loaded?.resume(returning: webView.url)
            self.loaded = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.loaded?.resume(returning: nil); self.loaded = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.loaded?.resume(returning: nil); self.loaded = nil }
    }
}

/// Goodreads' own sign-in page inside Orbit; closes by itself once you're in.
struct GoodreadsSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sync = GoodreadsSync.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Goodreads").font(Theme.ui(15, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
            }
            .padding(14)
            GoodreadsLoginWeb { dismiss() }
        }
        .sheetFrame(width: 520, height: 700)
    }
}

#if os(macOS)
private struct GoodreadsLoginWeb: NSViewRepresentable {
    let done: () -> Void
    func makeCoordinator() -> LoginWatcher { LoginWatcher(done: done) }
    func makeNSView(context: Context) -> WKWebView {
        let v = WKWebView()
        v.navigationDelegate = context.coordinator
        v.load(URLRequest(url: GoodreadsSync.signInURL))
        return v
    }
    func updateNSView(_ v: WKWebView, context: Context) {}
}
#else
private struct GoodreadsLoginWeb: UIViewRepresentable {
    let done: () -> Void
    func makeCoordinator() -> LoginWatcher { LoginWatcher(done: done) }
    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView()
        v.navigationDelegate = context.coordinator
        v.load(URLRequest(url: GoodreadsSync.signInURL))
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
#endif

/// Watches the sign-in page: once Goodreads moves on to your home page, you're signed in.
final class LoginWatcher: NSObject, WKNavigationDelegate {
    let done: () -> Void
    init(done: @escaping () -> Void) { self.done = done }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let u = webView.url, u.host?.contains("goodreads.com") == true else { return }
        let path = u.path
        let stillSigningIn = path.contains("sign_in") || path.contains("/user/new") || path.contains("/ap/") || path.isEmpty && u.query != nil
        if !stillSigningIn && !path.contains("sign_up") {
            Task { @MainActor in
                GoodreadsSync.shared.markSignedIn(true)
                self.done()
            }
        }
    }
}

/// Settings › Connections › Goodreads: sign in so Orbit can update your progress and post reviews.
struct GoodreadsSyncRow: View {
    @ObservedObject private var sync = GoodreadsSync.shared
    @State private var signingIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                BrandLogo(brand: .goodreads, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goodreads updates").font(.headline)
                    Text(sync.signedIn ? "Joshu sends your progress and reviews to Goodreads." : "Sign in once so Joshu can update your progress and post your reviews.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if sync.signedIn {
                    Button("Sign out", role: .destructive) { Task { await sync.signOut() } }
                } else {
                    Button("Sign in") { signingIn = true }.buttonStyle(.borderedProminent)
                }
            }
            if sync.signedIn { Toggle("Send my progress automatically", isOn: $sync.autoProgress).font(.caption) }
            if let s = sync.status { Text(s).font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $signingIn) { GoodreadsSignInSheet() }
    }
}
