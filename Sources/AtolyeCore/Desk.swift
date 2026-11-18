import Foundation

/// Uygulama alanına oranlı (0–1) dikdörtgen; sol üst köşe + boyut.
public struct FloatRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public static let full = FloatRect(x: 0, y: 0, w: 1, h: 1)
}

/// Atölyenin üstünde yüzen bir pencere: tek bir içerik (terminal, Git, markdown).
public struct DeskWindow: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var tab: RoomTab
    /// Ait olduğu proje kökü (başlık rengi, yeni pencerenin dizini).
    public var root: String
    /// Tam boyutta değilkenki yeri; tam boyuttan dönünce buraya gelir.
    public var frame: FloatRect
    public var maximized = false
    public var minimized = false
}

/// Yüzen pencerelerin masası. `windows` sırası üst üste diziliştir: sonuncusu en üstte.
public struct Desk: Codable, Equatable, Sendable {
    public var windows: [DeskWindow] = []
    /// Ajanı olmasa da atölyede görünen projeler.
    public var pinned: [String] = []

    public static let minSize = 0.15
    static let base = FloatRect(x: 0.06, y: 0.06, w: 0.56, h: 0.62)
    static let cascadeStep = 0.035

    public init() {}

    /// Eski oda düzeninden: her projenin sekmeleri sırayla kademeli pencereler olur.
    public init(migrating rooms: RoomStore) {
        pinned = rooms.pinned
        for root in rooms.rooms.keys.sorted() {
            for pane in rooms.rooms[root]?.panes ?? [] {
                for tab in pane.tabs { _ = open(tab, root: root) }
            }
        }
    }

    /// Öndeki (en üstteki küçültülmemiş) pencere.
    public var front: DeskWindow? { windows.last { !$0.minimized } }

    public func window(_ id: String) -> DeskWindow? { windows.first { $0.id == id } }

    public func window(of tab: RoomTab) -> DeskWindow? { windows.first { $0.tab == tab } }

    /// İçerik zaten bir penceredeyse onu öne getirir; yoksa kademeli yeni pencere açar. Pencere kimliğini döndürür.
    @discardableResult
    public mutating func open(_ tab: RoomTab, root: String) -> String {
        if let w = window(of: tab) {
            raise(w.id)
            return w.id
        }
        let n = Double(windows.count % 8) * Self.cascadeStep
        let f = Self.base
        let w = DeskWindow(id: UUID().uuidString, tab: tab, root: root, frame: FloatRect(x: f.x + n, y: f.y + n, w: f.w, h: f.h))
        windows.append(w)
        return w.id
    }

    /// En üste alır ve küçültülmüşse geri açar.
    public mutating func raise(_ id: String) {
        guard let i = windows.firstIndex(where: { $0.id == id }) else { return }
        var w = windows.remove(at: i)
        w.minimized = false
        windows.append(w)
    }

    /// Projenin bütün pencerelerini kendi sıralarıyla öne getirir; hiç yoksa false.
    @discardableResult
    public mutating func raiseAll(root: String) -> Bool {
        let ids = windows.filter { $0.root == root }.map(\.id)
        for id in ids { raise(id) }
        return !ids.isEmpty
    }

    public mutating func minimize(_ id: String) {
        update(id) { $0.minimized = true }
    }

    public mutating func toggleMaximize(_ id: String) {
        update(id) { $0.maximized.toggle() }
        raise(id)
    }

    /// Yeni yer/boyut: en küçük boyuta ve alanın içine sığdırılır; tam boyuttan çıkar.
    public mutating func setFrame(_ id: String, _ f: FloatRect) {
        let w = min(1, max(Self.minSize, f.w)), h = min(1, max(Self.minSize, f.h))
        let r = FloatRect(x: min(1 - w, max(0, f.x)), y: min(1 - h, max(0, f.y)), w: w, h: h)
        update(id) {
            $0.frame = r
            $0.maximized = false
        }
    }

    public mutating func close(_ id: String) {
        windows.removeAll { $0.id == id }
    }

    /// Pencerenin içeriğini yerinde değiştirir (konum, boyut, sıra korunur). Pencere yoksa false.
    @discardableResult
    public mutating func retarget(_ old: RoomTab, to new: RoomTab) -> Bool {
        guard let i = windows.firstIndex(where: { $0.tab == old }) else { return false }
        windows[i].tab = new
        return true
    }

    public mutating func remove(_ tab: RoomTab) {
        windows.removeAll { $0.tab == tab }
    }

    /// Artık yaşamayan terminallerin pencerelerini kaldırır.
    public mutating func prune(liveTerminals: Set<String>) {
        windows.removeAll {
            if case let .terminal(id) = $0.tab { return !liveTerminals.contains(id) }
            return false
        }
    }

    /// Görünür pencereler arasında sırayla geçer (alttakini öne alarak).
    public mutating func cycle(by step: Int) {
        let visible = windows.filter { !$0.minimized }
        guard visible.count > 1 else { return }
        if step > 0 { raise(visible[0].id) } else {
            // Öndekini en alta indir.
            if let top = visible.last, let i = windows.firstIndex(where: { $0.id == top.id }) {
                windows.insert(windows.remove(at: i), at: 0)
            }
        }
    }

    /// Sürüklerken imleç alanın kenarındaysa yapışacağı yer: sol/sağ yarı, üst tam, köşe çeyrek.
    public static func snap(pointer p: (x: Double, y: Double), in size: (w: Double, h: Double),
                            edge: Double = 16, corner: Double = 60) -> FloatRect? {
        let left = p.x <= edge, right = p.x >= size.w - edge
        let top = p.y <= edge, bottom = p.y >= size.h - edge
        let nearTopZone = p.y <= corner, nearBottomZone = p.y >= size.h - corner
        let nearLeftZone = p.x <= corner, nearRightZone = p.x >= size.w - corner
        func quarter(_ r: Bool, _ b: Bool) -> FloatRect { FloatRect(x: r ? 0.5 : 0, y: b ? 0.5 : 0, w: 0.5, h: 0.5) }
        if (left || right) && (nearTopZone || nearBottomZone) { return quarter(right, nearBottomZone) }
        if (top || bottom) && (nearLeftZone || nearRightZone) { return quarter(nearRightZone, bottom) }
        if left || right { return FloatRect(x: right ? 0.5 : 0, y: 0, w: 0.5, h: 1) }
        if top { return .full }
        return nil
    }

    private mutating func update(_ id: String, _ change: (inout DeskWindow) -> Void) {
        guard let i = windows.firstIndex(where: { $0.id == id }) else { return }
        change(&windows[i])
    }

    // MARK: Kayıt

    /// Dosya yoksa ya da okunamıyorsa nil (çağıran eski odalardan taşıyabilsin).
    public static func load(from url: URL) -> Desk? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Desk.self, from: data)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
