import AtolyeCore
import AppKit
import WebKit

/// Robotlar penceresindeki robot resimleri. Görünmez bir WKWebView `preview.html` ile her robotu
/// atölyedeki kodla çizer; hazır robotlar bellekte, kendi robotları `robots/<id>.png` olarak saklanır.
@MainActor @Observable
final class RobotPreviews: NSObject, WKScriptMessageHandler {
    private(set) var images: [String: NSImage] = [:]
    private(set) var errors: [String: String] = [:]

    @ObservationIgnored private var web: WKWebView?
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var pending: [[String: Any]] = []
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored let dir: URL

    init(dir: URL) { self.dir = dir }

    private func cacheURL(_ id: String, flipped: Bool) -> URL {
        dir.appendingPathComponent("\(id)\(flipped ? "-flip" : "").png")
    }

    /// Eksik resimleri iste. `customs` kendi robotları (yön değişince resim de değişir).
    func request(customs: [CustomRobot]) {
        var list: [[String: Any]] = []
        for b in RobotPool.builtins where images[b.id] == nil && !requested.contains(b.id) {
            list.append(["id": b.id, "builtin": true])
        }
        for c in customs {
            let key = c.id + (c.flipped ? "-flip" : "")
            if images[key] != nil || requested.contains(key) { continue }
            if let img = NSImage(contentsOf: cacheURL(c.id, flipped: c.flipped)) { images[key] = img; continue }
            list.append(["id": c.id, "builtin": false, "url": "atolye://app/robots/\(c.id).glb", "flipped": c.flipped, "key": key])
        }
        guard !list.isEmpty else { return }
        for r in list { requested.insert(r["key"] as? String ?? r["id"] as! String) }
        pending += list
        start()
        flush()
    }

    func image(for c: CustomRobot) -> NSImage? { images[c.id + (c.flipped ? "-flip" : "")] }

    /// Silinen robotun önbelleğini temizle.
    func forget(_ id: String) {
        for f in [false, true] { try? FileManager.default.removeItem(at: cacheURL(id, flipped: f)) }
        images[id] = nil; images[id + "-flip"] = nil; errors[id] = nil
        requested.remove(id); requested.remove(id + "-flip")
    }

    private func start() {
        guard web == nil else { return }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(WebFiles(root: SceneView.webRoot(), robotsRoot: WorkshopModel.robotsDir), forURLScheme: "atolye")
        config.userContentController.addUserScript(AppLanguage.webScript)
        config.userContentController.add(self, name: "atolye")
        let w = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 340), configuration: config)
        // WebGL'in çizmesi için görünmez ama pencereye bağlı olmalı.
        let win = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 340), styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentView = w
        win.orderBack(nil)
        window = win
        web = w
        w.load(URLRequest(url: URL(string: "atolye://app/preview.html")!))
    }

    private func flush() {
        guard ready, let web, !pending.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: pending.map { $0.filter { $0.key != "key" } }) else { return }
        let keys = Dictionary(uniqueKeysWithValues: pending.map { ($0["id"] as! String, $0["key"] as? String ?? $0["id"] as! String) })
        pendingKeys.merge(keys) { $1 }
        pending = []
        web.evaluateJavaScript("window.renderRobots(\(String(decoding: data, as: UTF8.self)))")
    }
    @ObservationIgnored private var pendingKeys: [String: String] = [:]

    nonisolated func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            let images = body["images"] as? [String: String] ?? [:]
            let errors = body["errors"] as? [String: String] ?? [:]
            switch type {
            case "ready":
                ready = true
                flush()
            case "previews":
                for (id, url) in images {
                    guard let i = url.range(of: "base64,"), let data = Data(base64Encoded: String(url[i.upperBound...])),
                          let img = NSImage(data: data) else { continue }
                    let key = pendingKeys[id] ?? id
                    self.images[key] = img
                    if RobotPool.builtins.contains(where: { $0.id == id }) == false {
                        try? data.write(to: dir.appendingPathComponent("\(key).png"), options: .atomic)
                    }
                }
                for (id, e) in errors { self.errors[id] = e }
            default: break
            }
        }
    }
}
