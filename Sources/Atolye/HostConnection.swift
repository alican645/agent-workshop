import AjanTakipCore
import AppKit
import AtolyeHostKit
import Observation
import SwiftTerm

/// Arka plan yardımcısına bağlantı ve terminal görünümleri. Her terminalin tek bir `TerminalView`'ı vardır;
/// odalar arasında geçerken aynı görünüm yeniden kullanılır, böylece geriye kaydırma geçmişi korunur.
@MainActor @Observable
final class HostConnection {
    private(set) var terminals: [String: TerminalInfo] = [:]
    /// Terminalin kendi koyduğu başlık (Claude görev adını yazar).
    private(set) var titles: [String: String] = [:]
    /// Yardımcıdan ilk liste geldi mi (o zamana kadar odalardaki sekmeler budanmaz).
    private(set) var listed = false
    private(set) var connected = false

    @ObservationIgnored private var client: HostClient?
    @ObservationIgnored private var views: [String: TerminalView] = [:]
    @ObservationIgnored private var bridges: [String: Bridge] = [:]
    @ObservationIgnored private var pendingCreates: [(TerminalInfo) -> Void] = []

    func start() {
        guard client == nil else { return }
        connect()
    }

    private func connect() {
        let c = HostClient(socketPath: HostPaths.socket, hostExecutable: Self.hostExecutable()) { [weak self] e in
            Task { @MainActor in self?.handle(e) }
        }
        do {
            try FileManager.default.createDirectory(atPath: HostPaths.supportDir, withIntermediateDirectories: true)
            try c.connect()
        } catch {
            retry()
            return
        }
        client = c
        connected = true
        c.send(.list)
        // Yeniden bağlanınca: görünümleri sıfırla, tampon baştan gelsin.
        for (id, v) in views {
            // Tam sıfırlama (RIS) + geriye kaydırmayı temizle; tampon yeniden oynatılacak.
            v.feed(text: "\u{1b}c\u{1b}[3J")
            c.send(.attach(id: id))
        }
    }

    private func retry() {
        client?.close()
        client = nil
        connected = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.connect() }
    }

    private func handle(_ e: HostEvent) {
        switch e {
        case let .terminals(list):
            terminals = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            listed = true
        case let .created(info):
            terminals[info.id] = info
            if !pendingCreates.isEmpty { pendingCreates.removeFirst()(info) }
        case let .output(id, data):
            // lastOutputAt'i burada güncelleme: her parçada arayüz yeniden çizilirdi; saniyelik liste getiriyor.
            views[id]?.feed(byteArray: ArraySlice([UInt8](data)))
        case let .exited(id, code):
            terminals[id]?.running = false
            terminals[id]?.exitCode = code
        case let .error(msg):
            if msg == HostClient.disconnected { retry() }
        }
    }

    /// Yardımcının listesini tazeler (makine ışıkları için çıktı zamanları).
    func refresh() { client?.send(.list) }

    func create(_ kind: TerminalKind, cwd: String, env: [String: String] = [:], args: [String]? = nil,
                then: @escaping (TerminalInfo) -> Void) {
        pendingCreates.append(then)
        client?.send(.create(kind: kind, cwd: cwd, cols: 120, rows: 32, env: env.isEmpty ? nil : env, args: args))
    }

    func kill(_ id: String) {
        client?.send(.kill(id: id))
        terminals[id] = nil
        views[id]?.removeFromSuperview()
        views[id] = nil
        bridges[id] = nil
    }

    func killAll() {
        client?.send(.killAll)
        for v in views.values { v.removeFromSuperview() }
        terminals = [:]
        views = [:]
        bridges = [:]
    }

    func title(_ id: String) -> String {
        let t = titles[id]?.trimmingCharacters(in: .whitespaces) ?? ""
        return t.isEmpty ? (terminals[id]?.title ?? "terminal") : t
    }

    /// Terminalin görünümü; ilk istekte oluşturulur ve yardımcıya bağlanır.
    func view(for id: String) -> TerminalView {
        if let v = views[id] { return v }
        let v = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        Self.style(v)
        let b = Bridge(id: id, connection: self)
        v.terminalDelegate = b
        bridges[id] = b
        views[id] = v
        client?.send(.attach(id: id))
        return v
    }

    /// Tıklanan görünüm hangi terminalin içinde?
    func terminalID(containing view: NSView) -> String? {
        var v: NSView? = view
        while let cur = v {
            if let id = views.first(where: { $0.value === cur })?.key { return id }
            v = cur.superview
        }
        return nil
    }

    /// Terminale metin yazar (kullanıcı yazmış gibi).
    func type(_ id: String, _ text: String) { client?.send(.input(id: id, data: Data(text.utf8))) }

    fileprivate func input(_ id: String, _ data: ArraySlice<UInt8>) {
        client?.send(.input(id: id, data: Data(data)))
    }

    fileprivate func resize(_ id: String, cols: Int, rows: Int) {
        // Yerleşim sırasında görünüm bir an sıfır boyutlu olabilir; kabuğu 1 sütuna küçültme.
        guard cols >= 10, rows >= 3 else { return }
        client?.send(.resize(id: id, cols: UInt16(clamping: cols), rows: UInt16(clamping: rows)))
    }

    fileprivate func setTitle(_ id: String, _ t: String) { titles[id] = t }

    static func style(_ v: TerminalView) {
        v.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        v.nativeBackgroundColor = NSColor(srgbRed: 0.165, green: 0.149, blue: 0.133, alpha: 1)
        v.nativeForegroundColor = NSColor(srgbRed: 0.937, green: 0.902, blue: 0.847, alpha: 1)
        v.caretColor = NSColor(srgbRed: 1, green: 0.62, blue: 0.27, alpha: 1)
        // Türkçe klavyede @ [ ] { } | ~ Option ile yazılır; Option meta tuşu olmasın.
        v.optionAsMetaKey = false
    }

    /// Paketlenmiş uygulamada yanımızdaki `atolye-host`, geliştirmede derleme klasöründeki.
    static func hostExecutable() -> String? {
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let p = dir.appendingPathComponent("atolye-host").path
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        var dir = URL(fileURLWithPath: #filePath)
        while dir.path != "/" {
            dir.deleteLastPathComponent()
            for conf in ["debug", "release"] {
                let p = dir.appendingPathComponent(".build/\(conf)/atolye-host").path
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }
}

/// SwiftTerm görünümünden gelen tuşları ve boyut değişikliklerini yardımcıya iletir.
@MainActor
private final class Bridge: TerminalViewDelegate {
    let id: String
    weak var connection: HostConnection?

    init(id: String, connection: HostConnection) {
        self.id = id
        self.connection = connection
    }

    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        MainActor.assumeIsolated { connection?.input(id, data) }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated { connection?.resize(id, cols: newCols, rows: newRows) }
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {
        MainActor.assumeIsolated { connection?.setTitle(id, title) }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { MainActor.assumeIsolated { _ = NSWorkspace.shared.open(url) } }
    }

    nonisolated func bell(source: TerminalView) {}

    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        guard let s = String(data: content, encoding: .utf8) else { return }
        MainActor.assumeIsolated {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s, forType: .string)
        }
    }

    nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}
