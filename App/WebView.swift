import SwiftUI
import WebKit
import Photos

struct WebView: UIViewRepresentable {
    let url: URL
    static let allowedHosts = ["aniworld.to"]
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let popupScript = WKUserScript(source: "window.open = () => null;", injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(popupScript)
        
        let mainJS = """
        window.detectedVideoUrl = null;
        window.addEventListener('message', (e) => {
            if (e.data && e.data.type === 'FOUND_VIDEO_URL') {
                window.detectedVideoUrl = e.data.url;
                const btn = document.getElementById('custom-ipa-dl-btn');
                if (btn) {
                    btn.innerText = 'Video herunterladen';
                    btn.style.background = '#007AFF';
                }
            }
        });
        setInterval(() => {
            if (document.getElementById('custom-ipa-dl-btn')) return;

            let bestFrame = null;
            let maxArea = 0;
            document.querySelectorAll('iframe, video').forEach(el => {
                const rect = el.getBoundingClientRect();
                const area = rect.width * rect.height;
                if (rect.width > 200 && rect.height > 120 && area > maxArea) {
                    maxArea = area;
                    bestFrame = el;
                }
            });

            if (!bestFrame) return;

            let container = bestFrame.closest('.inSiteWebStream, .hosterSiteVideo, .stream-wrapper') || bestFrame.parentElement;
            while (container && container.parentElement && getComputedStyle(container).overflow === 'hidden') {
                container = container.parentElement;
            }
            if (!container || !container.parentNode) return;

            const btn = document.createElement('button');
            btn.id = 'custom-ipa-dl-btn';
            btn.type = 'button';
            btn.innerText = 'Video starten zum Herunterladen';
            btn.style.cssText = 'display:block;width:100%;padding:14px;margin:12px 0;background:#444444;color:#ffffff;border:none;border-radius:8px;font-size:16px;font-weight:bold;cursor:pointer;position:relative;z-index:9999;';

            btn.onclick = (e) => {
                e.preventDefault();
                e.stopPropagation();
                const vid = document.querySelector('video');
                const dlUrl = window.detectedVideoUrl || (vid ? (vid.currentSrc || vid.src) : null);
                if (dlUrl && !dlUrl.startsWith('blob:')) {
                    btn.innerText = 'Download läuft...';
                    btn.style.background = '#FF9500';
                    window.webkit.messageHandlers.videoDownloader.postMessage(dlUrl);
                } else {
                    alert('Bitte starte zuerst das Video im Player.');
                }
            };

            container.parentNode.insertBefore(btn, container.nextSibling);
        }, 1000);
        """
        config.userContentController.addUserScript(WKUserScript(source: mainJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        
        let iframeJS = """
        setInterval(() => {
            document.querySelectorAll('video').forEach(v => {
                const s = v.querySelector('source');
                const src = v.currentSrc || v.src || (s ? s.src : null);
                if (src && src.startsWith('http')) {
                    window.top.postMessage({ type: 'FOUND_VIDEO_URL', url: src }, '*');
                }
            });
        }, 1000);
        """
        config.userContentController.addUserScript(WKUserScript(source: iframeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        config.userContentController.add(context.coordinator, name: "videoDownloader")
        
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.uiDelegate = context.coordinator
        web.navigationDelegate = context.coordinator
        context.coordinator.webView = web
        web.load(URLRequest(url: url))
        return web
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        
        static func isAllowed(_ url: URL?) -> Bool {
            guard let host = url?.host?.lowercased() else { return false }
            return WebView.allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if Coordinator.isAllowed(navigationAction.request.url) { webView.load(navigationAction.request) }
            return nil
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let isMain = navigationAction.targetFrame?.isMainFrame ?? true
            decisionHandler((!isMain || Coordinator.isAllowed(navigationAction.request.url)) ? .allow : .cancel)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "videoDownloader", let str = message.body as? String, let videoURL = URL(string: str) else { return }
            showBanner(text: "Video wird heruntergeladen...", color: .systemOrange)
            downloadVideo(from: videoURL)
        }
        
        private func downloadVideo(from url: URL) {
            URLSession.shared.downloadTask(with: url) { [weak self] temp, _, err in
                guard let self = self else { return }
                if let err = err { self.showBanner(text: "Fehler: \(err.localizedDescription)", color: .systemRed); return }
                guard let temp = temp else { self.showBanner(text: "Download fehlgeschlagen", color: .systemRed); return }
                
                let fm = FileManager.default
                let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let dest = docs.appendingPathComponent("Anime_\(Int(Date().timeIntervalSince1970)).mp4")
                try? fm.removeItem(at: dest)
                do {
                    try fm.moveItem(at: temp, to: dest)
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                        if status == .authorized || status == .limited {
                            PHPhotoLibrary.shared().performChanges({
                                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: dest)
                            }) { ok, _ in
                                self.showBanner(text: ok ? "Fertig! In Fotos & Dateien gespeichert." : "In der Dateien-App gespeichert.", color: .systemGreen)
                            }
                        } else {
                            self.showBanner(text: "In der Dateien-App gespeichert.", color: .systemGreen)
                        }
                    }
                } catch {
                    self.showBanner(text: "Speicherfehler: \(error.localizedDescription)", color: .systemRed)
                }
            }.resume()
        }
        
        private func showBanner(text: String, color: UIColor) {
            DispatchQueue.main.async {
                guard let web = self.webView else { return }
                web.viewWithTag(98765)?.removeFromSuperview()
                let lbl = UILabel()
                lbl.tag = 98765
                lbl.text = text
                lbl.textColor = .white
                lbl.backgroundColor = color.withAlphaComponent(0.95)
                lbl.font = .boldSystemFont(ofSize: 14)
                lbl.textAlignment = .center
                lbl.numberOfLines = 2
                lbl.layer.cornerRadius = 12
                lbl.clipsToBounds = true
                lbl.frame = CGRect(x: 16, y: web.safeAreaInsets.top + 12, width: web.bounds.width - 32, height: 48)
                web.addSubview(lbl)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { lbl.removeFromSuperview() }
            }
        }
    }
}
