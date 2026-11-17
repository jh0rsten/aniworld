import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    // Nur diese Domains (und Subdomains) dürfen als Hauptseite geladen werden.
    static let allowedHosts = [
        "youtube.com",
        "youtu.be",
        "accounts.google.com",
        "google.com"
    ]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Verhindert, dass Seiten per JavaScript Popup-Fenster öffnen.
        let script = WKUserScript(
            source: "window.open = function() { return null; };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(script)

        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.uiDelegate = context.coordinator
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {

        static func isAllowed(_ url: URL?) -> Bool {
            guard let host = url?.host?.lowercased() else { return false }
            return WebView.allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }

        // Neue Fenster (target=_blank / window.open): nie ein Popup,
        // erlaubte Links werden stattdessen im selben Fenster geöffnet.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if Coordinator.isAllowed(navigationAction.request.url) {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // Fremde Domains als Hauptseite blockieren.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if !isMainFrame || Coordinator.isAllowed(navigationAction.request.url) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
