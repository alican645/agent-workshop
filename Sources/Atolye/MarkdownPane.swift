import AtolyeCore
import AppKit
import SwiftUI
import WebKit

/// Bir markdown dosyasını salt okunur gösterir; dosya değişince yeniler.
struct MarkdownPane: NSViewRepresentable {
    let path: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.web = web
        let root = SceneView.webRoot()
        web.loadFileURL(root.appendingPathComponent("markdown.html"), allowingReadAccessTo: root)
        context.coordinator.watch(path)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.watch(path)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var web: WKWebView? {
            didSet { web?.navigationDelegate = self }
        }
        private var path: String?
        private var mtime: Date?
        private var loaded = false
        private var timer: Timer?

        func watch(_ p: String) {
            guard p != path else { return }
            path = p
            mtime = nil
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
            reload()
        }

        func stop() { timer?.invalidate() }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            mtime = nil
            reload()
        }

        private func reload() {
            guard loaded, let path, let web else { return }
            let m = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            guard m != mtime || m == nil else { return }
            mtime = m
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? L("*Dosya okunamadı:* `{0}`", path)
            guard let json = try? JSONEncoder().encode([text]), let s = String(data: json, encoding: .utf8) else { return }
            web.evaluateJavaScript("render(\(s)[0], \((try? String(data: JSONEncoder().encode(path), encoding: .utf8)) ?? "\"\""))")
        }
    }
}
