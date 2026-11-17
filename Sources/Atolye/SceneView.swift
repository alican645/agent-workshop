import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// three.js sahnesini barındıran web görünümü. Sayfa `atolye://app/index.html`'den yüklenir;
/// uygulama `window.atolye.update(snapshot)` ile durumu iter, sayfa `atolye` mesajlarıyla tıklamaları bildirir.
struct SceneView: NSViewRepresentable {
    let model: WorkshopModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(WebFiles(root: Self.webRoot()), forURLScheme: "atolye")
        config.userContentController.add(context.coordinator, name: "atolye")
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        web.isInspectable = true
        #endif
        context.coordinator.web = web
        web.load(URLRequest(url: URL(string: "atolye://app/index.html")!))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.push(model.snapshotJSON)
    }

    /// Paketlenmiş uygulamada `Contents/Resources/Web`, geliştirmede kaynak klasörü.
    static func webRoot() -> URL {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Web"),
           FileManager.default.fileExists(atPath: res.appendingPathComponent("index.html").path) {
            return res
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Web")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        let model: WorkshopModel
        weak var web: WKWebView? {
            didSet { observeWindow() }
        }
        private var ready = false
        private var pending: String?
        private var lastSent: String?
        private var observers: [NSObjectProtocol] = []

        init(model: WorkshopModel) { self.model = model }

        func push(_ json: String) {
            pending = json
            flush()
        }

        private func flush() {
            guard ready, let json = pending, json != lastSent, let web else { return }
            lastSent = json
            web.evaluateJavaScript("window.atolye && window.atolye.update(\(json))")
        }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                lastSent = nil
                flush()
                updateActive()
            case "focus":
                if let id = body["id"] as? String { model.open(sessionID: id) }
            case "openZone":
                if let id = body["id"] as? String { model.openZone(id) }
            case "openTerminal":
                if let id = body["id"] as? String { model.openTerminal(id) }
            case "newWindow":
                guard let root = body["root"] as? String else { break }
                switch body["kind"] as? String {
                case "claude": model.newWindow(.claude, in: root)
                case "git": model.addGit(in: root)
                default: model.newWindow(.shell, in: root)
                }
            case "addProject":
                model.addProject()
            case "unpin":
                if let id = body["id"] as? String { model.unpin(id) }
            default:
                break
            }
        }

        /// Pencere görünmezken sahneyi yavaşlatır.
        private func observeWindow() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSApplication.didHideNotification,
                         NSApplication.didUnhideNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateActive() }
                }
            }
        }

        private func updateActive() {
            guard ready, let web else { return }
            let visible = (web.window.map { $0.occlusionState.contains(.visible) && !$0.isMiniaturized } ?? false)
            web.evaluateJavaScript("window.atolye && window.atolye.setActive(\(visible))")
        }
    }
}

/// `atolye://app/<yol>` isteklerini Web klasöründen karşılar.
final class WebFiles: NSObject, WKURLSchemeHandler {
    let root: URL

    init(root: URL) { self.root = root.standardizedFileURL }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let rel = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let file = root.appendingPathComponent(rel.isEmpty ? "index.html" : rel).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = switch file.pathExtension {
        case "js", "mjs": "text/javascript"
        case "glb": "model/gltf-binary"
        default: UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"])!
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
