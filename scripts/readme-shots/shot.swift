// README görselleri: sahneyi (Sources/Atolye/Web) sahte demo verisiyle açar, docs/images için PNG ve GIF kareleri alır.
// Gerçek oturum verisi kullanmaz. Pencere çekim boyunca (~15 sn) ekranda görünür (WebGL ekran dışında çizmiyor).
//   ./scripts/readme-shots/make.sh

import AppKit
import WebKit
import UniformTypeIdentifiers

// Kullanım: shot <webRoot> <demo.json> <en.json> <outDir>
let a = CommandLine.arguments
let root = URL(fileURLWithPath: a[1]), demo = try! String(contentsOfFile: a[2], encoding: .utf8)
let en = try! String(contentsOfFile: a[3], encoding: .utf8), out = a[4]

final class Files: NSObject, WKURLSchemeHandler {
    let root: URL
    init(_ r: URL) { root = r }
    func webView(_ w: WKWebView, start t: any WKURLSchemeTask) {
        let rel = String(t.request.url!.path.dropFirst())
        let f = root.appendingPathComponent(rel)
        guard let d = try? Data(contentsOf: f) else { t.didFailWithError(URLError(.fileDoesNotExist)); return }
        let mime = switch f.pathExtension { case "mjs", "js": "text/javascript"; case "html": "text/html"; case "json": "application/json"
            default: UTType(filenameExtension: f.pathExtension)?.preferredMIMEType ?? "application/octet-stream" }
        t.didReceive(HTTPURLResponse(url: t.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mime])!)
        t.didReceive(d); t.didFinish()
    }
    func webView(_ w: WKWebView, stop t: any WKURLSchemeTask) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let W: CGFloat = 1600, H: CGFloat = 960
let cfg = WKWebViewConfiguration()
let files = Files(root)
cfg.setURLSchemeHandler(files, forURLScheme: "atolye")
cfg.userContentController.addUserScript(WKUserScript(source: "window.LANG='en'; window.I18N=\(en); const _gc=HTMLCanvasElement.prototype.getContext; HTMLCanvasElement.prototype.getContext=function(t,o){ if(t&&t.startsWith('webgl')) o=Object.assign({},o||{},{preserveDrawingBuffer:true}); return _gc.call(this,t,o); };", injectionTime: .atDocumentStart, forMainFrameOnly: true))
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: W, height: H), configuration: cfg)
let win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: W, height: H), styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = web
win.level = .floating
win.orderFrontRegardless()
web.load(URLRequest(url: URL(string: "atolye://app/index.html")!))

@MainActor func save(_ name: String, rect: CGRect? = nil, width: CGFloat? = nil) async {
    let c = WKSnapshotConfiguration()
    if let rect { c.rect = rect }
    if let width { c.snapshotWidth = NSNumber(value: Double(width)) }
    guard let img = try? await web.takeSnapshot(configuration: c),
          let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("snapshot failed", name); return }
    try! png.write(to: URL(fileURLWithPath: out + "/" + name))
}

Task { @MainActor in
    try? await Task.sleep(for: .seconds(4))
    _ = try? await web.evaluateJavaScript("window.atolye.update(\(demo))")
    try? await Task.sleep(for: .seconds(6))
    await save("workshop.png")
    // Balon yakın plan: balonun ve robotun çevresi.
    if let r = try? await web.evaluateJavaScript("(() => { const e=[...document.querySelectorAll('.pbal')].find(e=>e.offsetParent); if(!e) return ''; const x=e.getBoundingClientRect(); return [x.x,x.y,x.width,x.height].join(','); })()") as? String, !r.isEmpty {
        let v = r.split(separator: ",").compactMap { Double($0) }
        let m = 60.0
        await save("balloon.png", rect: CGRect(x: max(0, v[0] - m), y: max(0, v[1] - m), width: v[2] + 2 * m, height: v[3] + 2.6 * m))
    }
    for i in 0..<60 { await save(String(format: "f%03d.png", i), width: 800); try? await Task.sleep(for: .milliseconds(70)) }
    print("done")
    exit(0)
}
app.run()
