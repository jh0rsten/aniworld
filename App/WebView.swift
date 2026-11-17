import SwiftUI
import WebKit
import Photos
import AVFoundation

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
            if (e.data && e.data.type === 'FOUND_VIDEO_URL' && e.data.url) {
                window.detectedVideoUrl = e.data.url;
                const btn = document.getElementById('custom-ipa-dl-btn');
                if (btn) {
                    btn.innerText = 'Video herunterladen (Bereit)';
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
            btn.innerText = 'Video im Player starten...';
            btn.style.cssText = 'display:block;width:100%;padding:14px;margin:12px 0;background:#444444;color:#ffffff;border:none;border-radius:8px;font-size:16px;font-weight:bold;cursor:pointer;position:relative;z-index:9999;';

            btn.onclick = (e) => {
                e.preventDefault();
                e.stopPropagation();
                const vid = document.querySelector('video');
                const dlUrl = window.detectedVideoUrl || (vid ? (vid.currentSrc || vid.src) : null);
                if (dlUrl && dlUrl.startsWith('http')) {
                    btn.innerText = 'Download gestartet...';
                    btn.style.background = '#FF9500';
                    window.webkit.messageHandlers.videoDownloader.postMessage(dlUrl);
                } else if (dlUrl && dlUrl.startsWith('blob:')) {
                    btn.innerText = 'Blob-Stream nicht direkt ladbar (anderen Hoster testen)';
                    btn.style.background = '#FF3B30';
                } else {
                    btn.innerText = 'Bitte zuerst Play im Video drücken!';
                    setTimeout(() => { btn.innerText = 'Video im Player starten...'; }, 2500);
                }
            };

            container.parentNode.insertBefore(btn, container.nextSibling);
        }, 1000);
        """
        config.userContentController.addUserScript(WKUserScript(source: mainJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        
        let iframeJS = """
        const origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
            if (typeof url === 'string' && (url.includes('.m3u8') || url.includes('.mp4'))) {
                const fullUrl = new URL(url, window.location.href).href;
                window.top.postMessage({ type: 'FOUND_VIDEO_URL', url: fullUrl }, '*');
            }
            return origOpen.apply(this, arguments);
        };
        const origFetch = window.fetch;
        window.fetch = function(input) {
            const url = typeof input === 'string' ? input : (input && input.url);
            if (url && (url.includes('.m3u8') || url.includes('.mp4'))) {
                const fullUrl = new URL(url, window.location.href).href;
                window.top.postMessage({ type: 'FOUND_VIDEO_URL', url: fullUrl }, '*');
            }
            return origFetch.apply(this, arguments);
        };
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
        config.userContentController.addUserScript(WKUserScript(source: iframeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
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
            if str.contains(".m3u8") {
                downloadHLSStream(from: videoURL)
            } else {
                downloadVideo(from: videoURL)
            }
        }
        
        private func downloadHLSStream(from url: URL) {
            let asset = AVURLAsset(url: url)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                showBanner(text: "Stream-Export nicht moeglich", color: .systemRed)
                return
            }
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)
            let dest = docs.appendingPathComponent("Anime_\(Int(Date().timeIntervalSince1970)).mp4")
            try? fm.removeItem(at: dest)
            exporter.outputURL = dest
            exporter.outputFileType = .mp4
            exporter.exportAsynchronously { [weak self] in
                guard let self = self else { return }
                if exporter.status == .completed {
                    self.saveToPhotos(fileURL: dest)
                } else {
                    self.showBanner(text: "Stream-Fehler: \(exporter.error?.localizedDescription ?? "Unbekannt")", color: .systemRed)
                }
            }
        }
        
        private func downloadVideo(from url: URL) {
            URLSession.shared.downloadTask(with: url) { [weak self] temp, _, err in
                guard let self = self else { return }
                if let err = err { self.showBanner(text: "Fehler: \(err.localizedDescription)", color: .systemRed); return }
                guard let temp = temp else { self.showBanner(text: "Download fehlgeschlagen", color: .systemRed); return }
                
                let fm = FileManager.default
                let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)
                let dest = docs.appendingPathComponent("Anime_\(Int(Date().timeIntervalSince1970)).mp4")
                try? fm.removeItem(at: dest)
                do {
                    try fm.moveItem(at: temp, to: dest)
                    self.saveToPhotos(fileURL: dest)
                } catch {
                    self.showBanner(text: "Speicherfehler: \(error.localizedDescription)", color: .systemRed)
                }
            }.resume()
        }
        
        private func saveToPhotos(fileURL: URL) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized || status == .limited {
                    PHPhotoLibrary.shared().performChanges({
