import Foundation

/// Bir robotun sohbet kaydından ve kayıt dosyasından gelen ayrıntıları.
public struct RobotDetails: Sendable {
    public var tool: ToolUse?
    /// Eskiden yeniye.
    public var history: [ToolUse]
    public var helpers: [Helper]
    public var waitingFor: String?
    /// Ekrandaki (ya da kayıttaki) seçenek menüsü; yalnız bekleyen robotta snapshot'a girer.
    public var prompt: PromptInfo?

    public init(tool: ToolUse?, history: [ToolUse], helpers: [Helper], waitingFor: String?, prompt: PromptInfo? = nil) {
        self.tool = tool
        self.history = history
        self.helpers = helpers
        self.waitingFor = waitingFor
        self.prompt = prompt
    }
}

public struct HelperInfo: Codable, Equatable, Sendable {
    public var id: String
    public var task: String
    public var tool: String?
}

public struct RobotInfo: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var profile: String
    /// "busy" | "waiting" | "done" | "idle"
    public var state: String
    public var tool: String?
    public var waitingFor: String?
    public var helpers: [HelperInfo]
    /// Yeniden eskiye, en çok 5.
    public var history: [String]
    /// Oturum bir Atölye terminalindeyse onun kimliği.
    public var terminal: String?
    /// Oturumun (yardımcılar dahil) toplam token'ı ve API liste fiyatıyla yaklaşık maliyeti (dolar).
    public var tokens: Int? = nil
    public var cost: Double? = nil
    /// Yapılacaklardan robota verilen iş (Atölye bu terminali o işle açtıysa).
    public var task: String? = nil
    /// Bekleyen robotun seçenek menüsü (balon).
    public var prompt: PromptInfo? = nil
}

/// Atölyede açılmış düz terminal: tezgâhta bir makine.
public struct MachineInfo: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Son birkaç saniyede çıktı verdi mi.
    public var active: Bool
}

public struct ZoneInfo: Codable, Equatable, Sendable {
    /// Proje kökünün yolu.
    public var id: String
    public var name: String
    public var color: String
    public var robots: [RobotInfo]
    /// `TODO.local.md` maddeleri (bitenler dahil, dosyadaki sırayla), en çok `Workshop.todoLimit`.
    public var todos: [ZoneTodo]
    public var machines: [MachineInfo]
    public var pinned: Bool
    /// Proje bir git deposuysa durumu.
    public var git: GitBadge?
}

/// Bölgenin beyaz tahtasındaki bir madde. `line` dosyadaki satır; işaretlerken satırın değişmediği bununla denetlenir.
public struct ZoneTodo: Codable, Equatable, Sendable {
    public var line: Int
    public var text: String
    public var done: Bool

    public init(line: Int, text: String, done: Bool) {
        self.line = line
        self.text = text
        self.done = done
    }
}

/// Bölgenin git özeti (sol panel, tabela ve akış olayları için).
public struct GitBadge: Codable, Equatable, Sendable {
    public var branch: String
    public var changed: Int
    public var ahead: Int
    public var behind: Int
    /// Son commit'in kısa kimliği ve başlığı; değişince akışa "commit" düşer.
    public var head: String?
    public var headSubject: String?

    public init(branch: String, changed: Int, ahead: Int, behind: Int, head: String?, headSubject: String?) {
        self.branch = branch
        self.changed = changed
        self.ahead = ahead
        self.behind = behind
        self.head = head
        self.headSubject = headSubject
    }
}

public struct WorkshopSnapshot: Codable, Equatable, Sendable {
    public var zones: [ZoneInfo]
    /// Açık robotların havuzu (hazır ve kendi robotları); sahne yeni robotları buradan seçer.
    public var robots: [PoolRobot]? = nil
}

/// Oturumları atölye bölgelerine (projeler) ve robotlara çevirir.
public enum Workshop {
    static let historyLimit = 5
    static let todoLimit = 40
    /// Makinenin "çalışıyor" ışığı için son çıktıdan bu yana süre.
    static let machineActiveWindow: TimeInterval = 3

    /// `cwd`'den yukarı doğru `.git` içeren ilk klasör; yoksa `cwd`.
    public static func projectRoot(cwd: String, fileExists: (String) -> Bool) -> String {
        var dir = cwd
        while dir.count > 1 && dir.hasSuffix("/") { dir.removeLast() }
        var cur = dir
        while true {
            if fileExists(cur == "/" ? "/.git" : cur + "/.git") { return cur }
            let parent = (cur as NSString).deletingLastPathComponent
            if parent == cur || parent.isEmpty { return dir }
            cur = parent
        }
    }

    /// Proje adından her gün aynı kalan yumuşak bir renk.
    public static func color(for name: String) -> String {
        var h: UInt32 = 2_166_136_261
        for b in name.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        let hue = Double(h % 360) / 360, s = 0.45, l = 0.62
        func f(_ n: Double) -> Int {
            let k = (n + hue * 12).truncatingRemainder(dividingBy: 12)
            let a = s * min(l, 1 - l)
            return Int(((l - a * max(-1, min(k - 3, 9 - k, 1))) * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", f(0), f(8), f(4))
    }

    public static func toolText(_ t: ToolUse) -> String {
        let icon = switch t.name {
        case "Read": "📖"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": "✏️"
        case "Bash": "⌘"
        case "Grep", "Glob": "🔎"
        case "WebFetch", "WebSearch": "🌐"
        case "Agent", "Task": "↳"
        default: "🔧"
        }
        return icon + " " + (t.target.isEmpty ? t.name : t.target)
    }

    static func stateName(_ s: SessionState) -> String {
        switch s {
        case .working: "busy"
        case .waiting: "waiting"
        case .done: "done"
        case .idle: "idle"
        }
    }

    public static func build(sessions: [Session], details: [String: RobotDetails], todos: [String: [TodoItem]],
                             terminals: [TerminalInfo] = [], terminalOf: [String: String] = [:], tasks: [String: String] = [:], pinned: [String] = [],
                             git: [String: GitBadge] = [:], usage: [String: SessionUsage] = [:], now: Date = Date(), fileExists: (String) -> Bool) -> WorkshopSnapshot {
        var groups: [String: [(Session, String)]] = [:]
        for s in sessions {
            guard let cwd = s.cwd, !cwd.isEmpty else { continue }
            let root = projectRoot(cwd: cwd, fileExists: fileExists)
            groups[root, default: []].append((s, cwd))
        }
        var machines: [String: [MachineInfo]] = [:]
        for t in terminals where t.kind == .shell {
            let root = projectRoot(cwd: t.cwd, fileExists: fileExists)
            let active = t.running && (t.lastOutputAt.map { now.timeIntervalSince($0) <= machineActiveWindow } ?? false)
            machines[root, default: []].append(MachineInfo(id: t.id, title: t.title, active: active))
            if groups[root] == nil { groups[root] = [] }
        }
        let pinnedSet = Set(pinned)
        for p in pinned where groups[p] == nil { groups[p] = [] }
        let zones = groups.map { root, members -> ZoneInfo in
            let name = (root as NSString).lastPathComponent.isEmpty ? root : (root as NSString).lastPathComponent
            var used: [String: Int] = [:]
            let robots = members.sorted { $0.0.id < $1.0.id }.map { s, cwd -> RobotInfo in
                var base = cwd.hasPrefix(root + "/") ? String(cwd.dropFirst(root.count + 1)) : ""
                while base.hasSuffix("/") { base.removeLast() }
                if base.isEmpty { base = name }
                used[base, default: 0] += 1
                let label = used[base]! > 1 ? "\(base) \(used[base]!)" : base
                let d = details[s.id]
                return RobotInfo(
                    id: s.id, label: label, profile: s.profileName, state: stateName(s.state),
                    tool: d?.tool.map(toolText),
                    waitingFor: s.state == .waiting ? d?.waitingFor : nil,
                    helpers: (d?.helpers ?? []).map { HelperInfo(id: $0.id, task: $0.task, tool: $0.lastTool.map(toolText)) },
                    history: (d?.history ?? []).suffix(historyLimit).reversed().map(toolText),
                    terminal: terminalOf[s.id],
                    tokens: usage[s.id]?.tokens.total, cost: usage[s.id]?.cost,
                    task: terminalOf[s.id].flatMap { tasks[$0] },
                    prompt: s.state == .waiting ? d?.prompt : nil)
            }
            let list = (todos[root] ?? []).prefix(todoLimit).map { ZoneTodo(line: $0.line, text: $0.text, done: $0.done) }
            return ZoneInfo(id: root, name: name, color: color(for: name), robots: robots, todos: Array(list),
                            machines: machines[root] ?? [], pinned: pinnedSet.contains(root), git: git[root])
        }
        return WorkshopSnapshot(zones: zones.sorted { ($0.name, $0.id) < ($1.name, $1.id) })
    }
}
