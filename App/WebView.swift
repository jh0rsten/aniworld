import AVFoundation
import Photos
import SwiftUI
import WebKit

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

    // 1. Aggressiver Anti-Popup & Anti-Redirect Script (läuft in Hauptseite UND allen iFrames)
    let antiAdJS = """
      (function() {
          // Blockiert window.open komplett
          window.open = function() { return null; };
          
          // Verhindert, dass Links neue Tabs erzwingen
          document.addEventListener('click', function(e) {
              const a = e.target.closest('a');
              if (a) {
                  const href = a.getAttribute('href') || '';
                  if (a.target === '_blank' || href.startsWith('javascript:') || href.includes('redirect') || href.includes('ads')) {
                      if (!href.includes('aniworld.to') && !href.startsWith('/') && !href.startsWith('#')) {
                          e.preventDefault();
                          e.stopPropagation();
                          return false;
                      }
                  }
                  a.removeAttribute('target');
              }
          }, true);

          // Entfernt regelmäßig unsichtbare Klick-Overlays über dem Player
          setInterval(() => {
              document.querySelectorAll('div, a, iframe').forEach(el => {
                  const style = window.getComputedStyle(el);
                  const z = parseInt(style.zIndex, 10);
                  // Typische Werbe-Overlays haben extrem hohen z-index und liegen über dem Player
                  if (z > 1000 && el.id !== 'custom-ipa-dl-btn' && !el.querySelector('video')) {
                      if (style.position === 'fixed' || style.position === 'absolute') {
                          el.remove();
                      }
                  }
              });
          }, 800);
      })();
      """
    config.userContentController.addUserScript(
      WKUserScript(source: antiAdJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))

    // 2. Dein bestehendes Download-Button-Skript
    let mainJS = """
      window.detectedVideoData = null;
      window.addEventListener('message', (e) => {
          if (e.data && e.data.type === 'FOUND_VIDEO_URL' && e.data.url) {
              window.detectedVideoData = { url: e.data.url, referer: e.data.referer || window.location.href };
              const btn = document.getElementById('custom-ipa-dl-btn');
              if (btn) { btn.innerText = 'Video herunterladen (Bereit)'; btn.style.background = '#007AFF'; }
          }
      });
      setInterval(() => {
          if (document.getElementById('custom-ipa-dl-btn')) return;
          let bestFrame = null, maxArea = 0;
          document.querySelectorAll('iframe, video').forEach(el => {
              const r = el.getBoundingClientRect(), area = r.width * r.height;
              if (r.width > 200 && r.height > 120 && area > maxArea) { maxArea = area; bestFrame = el; }
          });
          if (!bestFrame) return;
          let container = bestFrame.closest('.inSiteWebStream, .hosterSiteVideo, .stream-wrapper') || bestFrame.parentElement;
          while (container && container.parentElement && getComputedStyle(container).overflow === 'hidden') { container = container.parentElement; }
          if (!container || !container.parentNode) return;
          const btn = document.createElement('button');
          btn.id = 'custom-ipa-dl-btn'; btn.type = 'button'; btn.innerText = 'Video im Player starten...';
          btn.style.cssText = 'display:block;width:100%;padding:14px;margin:12px 0;background:#444;color:#fff;border:none;border-radius:8px;font-size:16px;font-weight:bold;cursor:pointer;position:relative;z-index:9999;';
          btn.onclick = (e) => {
              e.preventDefault(); e.stopPropagation();
              const vid = document.querySelector('video');
              const data = window.detectedVideoData || (vid && (vid.currentSrc || vid.src) ? { url: (vid.currentSrc || vid.src), referer: window.location.href } : null);
              if (data && data.url.startsWith('http')) {
                  btn.innerText = 'Download läuft...'; btn.style.background = '#FF9500';
                  window.webkit.messageHandlers.videoDownloader.postMessage(data);
              } else {
                  btn.innerText = 'Bitte zuerst Play im Video drücken!';
                  setTimeout(() => { btn.innerText = 'Video im Player starten...'; }, 2500);
              }
          };
          container.parentNode.insertBefore(btn, container.nextSibling);
      }, 1000);
      """
    config.userContentController.addUserScript(
      WKUserScript(source: mainJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

    // 3. Video-URL Sniffer in iFrames
    let iframeJS = """
      const sendUrl = (u) => {
          if (typeof u === 'string' && (u.includes('.m3u8') || u.includes('.mp4'))) {
              window.top.postMessage({ type: 'FOUND_VIDEO_URL', url: new URL(u, window.location.href).href, referer: window.location.href }, '*');
          }
      };
      const origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(m, u) { sendUrl(u); return origOpen.apply(this, arguments); };
      const origFetch = window.fetch;
      window.fetch = function(i) { sendUrl(typeof i === 'string' ? i : (i && i.url)); return origFetch.apply(this, arguments); };
      setInterval(() => {
          document.querySelectorAll('video').forEach(v => {
              const s = v.querySelector('source');
              const src = v.currentSrc || v.src || (s ? s.src : null);
              if (src && src.startsWith('http')) sendUrl(src);
          });
      }, 1000);
      """
    config.userContentController.addUserScript(
      WKUserScript(source: iframeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    config.userContentController.add(context.coordinator, name: "videoDownloader")

    // 4. Nativer Safari Content Blocker (blockiert Werbenetzwerke auf Netzwerkebene)
    let blockRules = """
      [
          {"trigger": {"url-filter": ".*(doubleclick|googlesyndication|adsystem|adnxs|popads|popcash|exoclick|juicyads|trafficjunky|propellerads|mgid|taboola|outbrain|adsterra|hilltopads|clickadu|monetag).*"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": ".*", "resource-type": ["popup"]}, "action": {"type": "block"}}
      ]
      """

    let web = WKWebView(frame: .zero, configuration: config)
    web.allowsBackForwardNavigationGestures = true
    web.uiDelegate = context.coordinator
    web.navigationDelegate = context.coordinator
    context.coordinator.webView = web

    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "AdBlockRules", encodedContentRuleList: blockRules
    ) { ruleList, _ in
      if let ruleList = ruleList {
        web.configuration.userContentController.add(ruleList)
      }
      web.load(URLRequest(url: url))
    }

    return web
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}

  final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    weak var webView: WKWebView?

    // Erlaubte Hosts für die Hauptseite & bekannte Video-Hoster-iFrames
    static let allowedMainHosts = ["aniworld.to"]
    static let allowedVideoHosts = [
      "voe.sx", "dood", "streamtape", "vidoza", "filemoon", "vidmoly", "speedfiles", "luluvdo",
      "mixdrop",
    ]

    static func isAllowedMain(_ url: URL?) -> Bool {
      guard let host = url?.host?.lowercased() else { return false }
      return allowedMainHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isAllowedSubframe(_ url: URL?) -> Bool {
      guard let host = url?.host?.lowercased() else { return true }
      if isAllowedMain(url) { return true }
      return allowedVideoHosts.contains { host.contains($0) }
    }

    // Blockiert JEDES neue Fenster / Tab komplett (nicht neu laden!)
    func webView(
      _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      return nil
    }

    // Kontrolliert Hauptseite UND iFrame-Navigationen
    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      let targetURL = navigationAction.request.url
      let isMain = navigationAction.targetFrame?.isMainFrame ?? true

      if isMain {
        decisionHandler(Coordinator.isAllowedMain(targetURL) ? .allow : .cancel)
      } else {
        // Erlaubt im iFrame nur bekannte Video-Player, blockiert Werbe-Weiterleitungen
        decisionHandler(Coordinator.isAllowedSubframe(targetURL) ? .allow : .cancel)
      }
    }

    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      guard
        message.name == "videoDownloader",
        let dict = message.body as? [String: String],
        let str = dict["url"],
        let videoURL = URL(string: str)
      else {
        return
      }

      let referer = dict["referer"] ?? "https://aniworld.to"
      showBanner(text: "Video wird heruntergeladen...", color: .systemOrange)

      if str.contains(".m3u8") {
        downloadHLSStream(from: videoURL, referer: referer)
      } else {
        downloadVideo(from: videoURL, referer: referer)
      }
    }

    private func downloadHLSStream(from url: URL, referer: String) {
      let headers = [
        "Referer": referer,
        "User-Agent":
          "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
      ]

      let asset = AVURLAsset(
        url: url,
        options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
      )

      guard
        let exporter = AVAssetExportSession(
          asset: asset,
          presetName: AVAssetExportPresetPassthrough
        )
      else {
        showBanner(text: "Stream-Export nicht möglich", color: .systemRed)
        return
      }

      let fileManager = FileManager.default
      let destinationURL =
        fileManager
        .urls(for: .documentDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent(
          "Anime_\(Int(Date().timeIntervalSince1970)).mp4"
        )

      try? fileManager.removeItem(at: destinationURL)

      exporter.outputURL = destinationURL
      exporter.outputFileType = .mp4

      exporter.exportAsynchronously { [weak self] in
        guard let self else { return }

        if exporter.status == .completed {
          self.saveToPhotos(fileURL: destinationURL)
        } else {
          let errorMessage = exporter.error?.localizedDescription ?? "Unbekannt"
          self.showBanner(
            text: "Stream-Fehler: \(errorMessage)",
            color: .systemRed
          )
        }
      }
    }

    private func downloadVideo(from url: URL, referer: String) {
      var request = URLRequest(url: url)
      request.setValue(referer, forHTTPHeaderField: "Referer")
      request.setValue(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        forHTTPHeaderField: "User-Agent"
      )

      URLSession.shared.downloadTask(with: request) { [weak self] temporaryURL, _, error in
        guard let self else { return }

        if let error {
          self.showBanner(
            text: "Fehler: \(error.localizedDescription)",
            color: .systemRed
          )
          return
        }

        guard let temporaryURL else {
          self.showBanner(
            text: "Download fehlgeschlagen",
            color: .systemRed
          )
          return
        }

        let fileManager = FileManager.default
        let destinationURL =
          fileManager
          .urls(for: .documentDirectory, in: .userDomainMask)
          .first!
          .appendingPathComponent(
            "Anime_\(Int(Date().timeIntervalSince1970)).mp4"
          )

        try? fileManager.removeItem(at: destinationURL)

        do {
          try fileManager.moveItem(at: temporaryURL, to: destinationURL)
          self.saveToPhotos(fileURL: destinationURL)
        } catch {
          self.showBanner(
            text: "Speicherfehler: \(error.localizedDescription)",
            color: .systemRed
          )
        }
      }
      .resume()
    }

    private func saveToPhotos(fileURL: URL) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
          self.showBanner(
            text: "In der Dateien-App gespeichert.",
            color: .systemGreen
          )
          return
        }

        PHPhotoLibrary.shared().performChanges {
          PHAssetChangeRequest.creationRequestForAssetFromVideo(
            atFileURL: fileURL
          )
        } completionHandler: { success, _ in
          self.showBanner(
            text: success
              ? "Fertig! In Fotos & Dateien gespeichert."
              : "In der Dateien-App gespeichert.",
            color: .systemGreen
          )
        }
      }
    }

    private func showBanner(text: String, color: UIColor) {
      DispatchQueue.main.async {
        guard let web = self.webView else { return }

        web.viewWithTag(98765)?.removeFromSuperview()

        let label = UILabel()
        label.tag = 98765
        label.text = text
        label.textColor = .white
        label.backgroundColor = color.withAlphaComponent(0.95)
        label.font = .boldSystemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.frame = CGRect(
          x: 16,
          y: web.safeAreaInsets.top + 12,
          width: web.bounds.width - 32,
          height: 48
        )

        web.addSubview(label)

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
          label.removeFromSuperview()
        }
      }
    }
  }
}
