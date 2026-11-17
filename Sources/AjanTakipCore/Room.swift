import Foundation

/// Odadaki bir sekme: yardımcıdaki bir terminal ya da okunacak bir markdown dosyası.
public enum RoomTab: Codable, Equatable, Hashable, Sendable {
    case terminal(String)
    case markdown(String)
    /// Proje kökünün salt okunur git görünümü.
    case git(String)
}

public struct Pane: Codable, Equatable, Sendable {
    public var id: String
    public var tabs: [RoomTab]
    public var selected: Int

    public init(id: String = UUID().uuidString, tabs: [RoomTab], selected: Int = 0) {
        self.id = id
        self.tabs = tabs
        self.selected = selected
    }

    public var current: RoomTab? { tabs.indices.contains(selected) ? tabs[selected] : tabs.first }
}

/// `horizontal`: yan yana (soldan sağa), `vertical`: alt alta.
public enum SplitAxis: String, Codable, Sendable { case horizontal, vertical }

/// Sürüklenen sekmenin bırakıldığı yer: bölmenin ortası (sekme olur) ya da bir kenarı (bölme bölünür).
public enum DropEdge: Sendable { case center, left, right, top, bottom }

/// Odanın düzeni: yaprakları bölme olan ikili ağaç. `ratio` ilk çocuğun payı.
public indirect enum LayoutNode: Codable, Equatable, Sendable {
    case pane(Pane)
    case split(id: String, axis: SplitAxis, ratio: Double, first: LayoutNode, second: LayoutNode)
}

/// Bir projenin odası: iç içe bölünmüş bölmeler, her bölmede sekmeler (cmux gibi).
public struct Room: Codable, Equatable, Sendable {
    public var root: LayoutNode?
    public var focusedPaneID: String?

    public init() {}

    /// Bölmeler, soldan sağa / yukarıdan aşağı sırayla.
    public var panes: [Pane] { root.map(Self.leaves) ?? [] }
    public var focusedPane: Pane? { panes.first { $0.id == focusedPaneID } }
    public func paneID(of t: RoomTab) -> String? { panes.first { $0.tabs.contains(t) }?.id }
    public func contains(_ t: RoomTab) -> Bool { paneID(of: t) != nil }

    /// Odaklı bölmeye yeni sekme (oda boşsa ilk bölme); eklenen seçilir.
    public mutating func add(_ t: RoomTab) {
        guard root != nil, let id = focusedPane?.id ?? panes.last?.id else {
            let p = Pane(tabs: [t])
            root = .pane(p)
            focusedPaneID = p.id
            return
        }
        insert(t, into: id, at: nil)
    }

    /// `paneID` bölmesinin `edge` kenarında yeni bir bölme açıp sekmeyi oraya koyar.
    public mutating func split(_ t: RoomTab, beside paneID: String, edge: DropEdge) {
        guard edge != .center else { return insert(t, into: paneID, at: nil) }
        guard let root else { return add(t) }
        let new = Pane(tabs: [t])
        let axis: SplitAxis = edge == .left || edge == .right ? .horizontal : .vertical
        let newFirst = edge == .left || edge == .top
        self.root = Self.replacing(paneID, in: root) { old in
            .split(id: UUID().uuidString, axis: axis, ratio: 0.5,
                   first: newFirst ? .pane(new) : old, second: newFirst ? old : .pane(new))
        }
        focusedPaneID = new.id
    }

    /// Sürükle-bırak: sekmeyi hedef bölmenin ortasına (sekme olarak, `index` sırasına) ya da kenarına taşır.
    public mutating func move(_ t: RoomTab, to target: String, edge: DropEdge, index: Int? = nil) {
        guard let source = paneID(of: t), panes.contains(where: { $0.id == target }) else { return }
        if edge != .center, source == target, panes.first(where: { $0.id == source })?.tabs.count == 1 { return }
        root = root.flatMap { Self.removing(t, from: $0) }
        if edge == .center { insert(t, into: target, at: index) } else { split(t, beside: target, edge: edge) }
    }

    public mutating func remove(_ t: RoomTab) {
        root = root.flatMap { Self.removing(t, from: $0) }
        if focusedPane == nil { focusedPaneID = panes.last?.id }
    }

    /// Sekmeyi bulursa seçer ve bölmesine odaklanır.
    @discardableResult
    public mutating func focus(_ t: RoomTab) -> Bool {
        guard let id = paneID(of: t) else { return false }
        update(id) { $0.selected = $0.tabs.firstIndex(of: t)! }
        focusedPaneID = id
        return true
    }

    public mutating func focusPane(_ id: String) {
        if panes.contains(where: { $0.id == id }) { focusedPaneID = id }
    }

    public mutating func select(_ index: Int, inPane id: String) {
        update(id) { if $0.tabs.indices.contains(index) { $0.selected = index } }
        focusPane(id)
    }

    /// Odaklı bölmede sonraki/önceki sekme (başa sarar).
    public mutating func cycleTab(by step: Int) {
        guard let id = focusedPaneID else { return }
        update(id) { p in
            let n = p.tabs.count
            if n > 0 { p.selected = ((p.selected + step) % n + n) % n }
        }
    }

    public mutating func setRatio(_ splitID: String, _ ratio: Double) {
        let r = min(0.9, max(0.1, ratio))
        func walk(_ n: LayoutNode) -> LayoutNode {
            guard case let .split(id, axis, old, a, b) = n else { return n }
            return .split(id: id, axis: axis, ratio: id == splitID ? r : old, first: walk(a), second: walk(b))
        }
        root = root.map(walk)
    }

    /// Yardımcıda artık olmayan terminallerin sekmelerini siler.
    public mutating func prune(liveTerminals: Set<String>) {
        let dead = panes.flatMap(\.tabs).filter { if case let .terminal(id) = $0 { !liveTerminals.contains(id) } else { false } }
        for t in dead { remove(t) }
    }

    // MARK: Ağaç yardımcıları

    private mutating func insert(_ t: RoomTab, into id: String, at index: Int?) {
        update(id) { p in
            let i = min(max(index ?? p.tabs.count, 0), p.tabs.count)
            p.tabs.insert(t, at: i)
            p.selected = i
        }
        focusedPaneID = id
    }

    private mutating func update(_ id: String, _ change: (inout Pane) -> Void) {
        guard let root else { return }
        self.root = Self.replacing(id, in: root) { node in
            guard case var .pane(p) = node else { return node }
            change(&p)
            return .pane(p)
        }
    }

    private static func leaves(_ n: LayoutNode) -> [Pane] {
        switch n {
        case let .pane(p): [p]
        case let .split(_, _, _, a, b): leaves(a) + leaves(b)
        }
    }

    private static func replacing(_ paneID: String, in n: LayoutNode, with f: (LayoutNode) -> LayoutNode) -> LayoutNode {
        switch n {
        case let .pane(p): p.id == paneID ? f(n) : n
        case let .split(id, axis, ratio, a, b):
            .split(id: id, axis: axis, ratio: ratio, first: replacing(paneID, in: a, with: f), second: replacing(paneID, in: b, with: f))
        }
    }

    /// Sekmeyi çıkarır; boşalan bölme kalkar ve bölünme kardeşine dönüşür. Ağaç boşalırsa nil.
    private static func removing(_ t: RoomTab, from n: LayoutNode) -> LayoutNode? {
        switch n {
        case var .pane(p):
            guard let j = p.tabs.firstIndex(of: t) else { return n }
            p.tabs.remove(at: j)
            if p.tabs.isEmpty { return nil }
            if j < p.selected { p.selected -= 1 }
            p.selected = min(p.selected, p.tabs.count - 1)
            return .pane(p)
        case let .split(id, axis, ratio, a, b):
            let na = removing(t, from: a), nb = removing(t, from: b)
            guard let na else { return nb }
            guard let nb else { return na }
            return .split(id: id, axis: axis, ratio: ratio, first: na, second: nb)
        }
    }

    // MARK: Kayıt (eski sütun biçimini de okur)

    private enum CodingKeys: String, CodingKey { case root, focusedPaneID, panes, focusedPane }
    private struct LegacyPane: Decodable { var tabs: [RoomTab]; var selected: Int }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let legacy = try c.decodeIfPresent([LegacyPane].self, forKey: .panes) {
            let ps = legacy.filter { !$0.tabs.isEmpty }.map { Pane(tabs: $0.tabs, selected: $0.selected) }
            var node: LayoutNode? = nil
            for (k, p) in ps.enumerated().reversed() {
                node = node.map { .split(id: UUID().uuidString, axis: .horizontal, ratio: 1 / Double(ps.count - k), first: .pane(p), second: $0) } ?? .pane(p)
            }
            root = node
            let f = (try? c.decodeIfPresent(Int.self, forKey: .focusedPane)) ?? 0
            focusedPaneID = ps.indices.contains(f ?? 0) ? ps[f ?? 0].id : ps.last?.id
        } else {
            root = try c.decodeIfPresent(LayoutNode.self, forKey: .root)
            focusedPaneID = try c.decodeIfPresent(String.self, forKey: .focusedPaneID)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(root, forKey: .root)
        try c.encodeIfPresent(focusedPaneID, forKey: .focusedPaneID)
    }
}

/// Kalıcı oda düzenleri (proje kökü → oda) ve sabitlenmiş projeler.
public struct RoomStore: Codable, Equatable, Sendable {
    public var rooms: [String: Room] = [:]
    public var pinned: [String] = []

    public init() {}

    public static func load(from url: URL) -> RoomStore {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(RoomStore.self, from: data) else {
            return RoomStore()
        }
        return s
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
