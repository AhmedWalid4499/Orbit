import SwiftUI
import WebKit

/// An email shown the way Gmail shows it: its own layout, pictures and links, on a white page.
/// Plain-text emails get the same page with links made clickable. Links open in your browser.
struct EmailBodyView: View {
    let html: String
    let text: String

    var body: some View {
        EmailWebView(page: Self.page(html: html, text: text))
    }

    static func page(html: String, text: String) -> String {
        let content: String
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            let linked = escaped.replacingOccurrences(of: #"(https?://[^\s<]+)"#, with: "<a href=\"$1\">$1</a>", options: .regularExpression)
            content = "<div class=\"plain\">\(linked)</div>"
        } else {
            // Scripts never run in an email.
            content = html.replacingOccurrences(of: #"(?is)<script[^>]*>.*?</script>"#, with: "", options: .regularExpression)
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; padding: 0; background: #ffffff; color: #202124; }
          body { font: 14px/1.55 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; padding: 18px 20px; word-wrap: break-word; }
          img { max-width: 100% !important; height: auto !important; }
          table { max-width: 100% !important; }
          a { color: #1a73e8; }
          .plain { white-space: pre-wrap; font-size: 15px; }
          blockquote { margin: 0 0 0 8px; padding-left: 10px; border-left: 2px solid #dadce0; color: #5f6368; }
        </style></head><body>\(content)</body></html>
        """
    }
}

#if os(macOS)
private struct EmailWebView: NSViewRepresentable {
    let page: String
    func makeCoordinator() -> EmailLinkHandler { EmailLinkHandler() }
    func makeNSView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero, configuration: EmailLinkHandler.configuration)
        v.navigationDelegate = context.coordinator
        v.setValue(false, forKey: "drawsBackground")
        return v
    }
    func updateNSView(_ v: WKWebView, context: Context) {
        guard context.coordinator.loaded != page else { return }
        context.coordinator.loaded = page
        v.loadHTMLString(page, baseURL: nil)
    }
}
#else
private struct EmailWebView: UIViewRepresentable {
    let page: String
    func makeCoordinator() -> EmailLinkHandler { EmailLinkHandler() }
    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero, configuration: EmailLinkHandler.configuration)
        v.navigationDelegate = context.coordinator
        v.isOpaque = false
        v.backgroundColor = .white
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) {
        guard context.coordinator.loaded != page else { return }
        context.coordinator.loaded = page
        v.loadHTMLString(page, baseURL: nil)
    }
}
#endif

final class EmailLinkHandler: NSObject, WKNavigationDelegate {
    var loaded = ""

    static var configuration: WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.defaultWebpagePreferences.allowsContentJavaScript = false
        c.websiteDataStore = .nonPersistent()
        return c
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // The email itself loads; any link you click opens in the browser.
        if action.navigationType == .linkActivated, let url = action.request.url {
            Platform.open(url)
            return .cancel
        }
        return .allow
    }
}
