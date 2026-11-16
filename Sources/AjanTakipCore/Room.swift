import Foundation

/// Odadaki bir sekme: yardımcıdaki bir terminal ya da okunacak bir markdown dosyası.
public enum Tab: Codable, Equatable, Hashable, Sendable {
    case terminal(String)
    case markdown(String)
}

public struct Pane: Codable, Equatable, Sendable {
    public var tabs: [Tab]
    public var selected: Int
    /// Pencere genişliğine oranı (bölmelerin toplamı 1).
    public var width: Double

    public var current: Tab? { tabs.indices.contains(selected) ? tabs[selected] : tabs.first }
}

/// Bir projenin odası: soldan sağa bölmeler, her bölmede sekmeler.
public struct Room: Codable, Equatable, Sendable {
    public static let maxPanes = 3
    public var panes: [Pane] = []
    public var focusedPane = 0

    public init() {}

    /// 3 bölmeye kadar yeni bölme, sonra son bölmeye sekme; eklenen seçilir ve odaklanır.
    public mutating func add(_ t: Tab) {
        if panes.count < Self.maxPanes {
            panes.append(Pane(tabs: [t], selected: 0, width: 0))
            equalize()
        } else {
            panes[panes.count - 1].tabs.append(t)
            panes[panes.count - 1].selected = panes[panes.count - 1].tabs.count - 1
        }
        focusedPane = panes.count - 1
    }

    public mutating func remove(_ t: Tab) {
        for i in panes.indices {
            guard let j = panes[i].tabs.firstIndex(of: t) else { continue }
            panes[i].tabs.remove(at: j)
            if panes[i].tabs.isEmpty {
                panes.remove(at: i)
                equalize()
                focusedPane = max(0, min(focusedPane, panes.count - 1))
            } else {
                if j < panes[i].selected { panes[i].selected -= 1 }
                panes[i].selected = min(panes[i].selected, panes[i].tabs.count - 1)
            }
            return
        }
    }

    /// Sekmeyi bulursa onu seçer ve bölmesine odaklanır.
    public mutating func focus(_ t: Tab) -> Bool {
        for i in panes.indices {
            if let j = panes[i].tabs.firstIndex(of: t) {
                panes[i].selected = j
                focusedPane = i
                return true
            }
        }
        return false
    }

    /// Yardımcıda artık olmayan terminallerin sekmelerini siler.
    public mutating func prune(liveTerminals: Set<String>) {
        let dead = panes.flatMap(\.tabs).filter { if case let .terminal(id) = $0 { !liveTerminals.contains(id) } else { false } }
        for t in dead { remove(t) }
    }

    private mutating func equalize() {
        for i in panes.indices { panes[i].width = 1 / Double(panes.count) }
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
