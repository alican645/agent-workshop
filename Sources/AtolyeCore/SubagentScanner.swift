import Foundation

/// Bir oturumun etkin alt ajanı (atölyede küçük yardımcı robot).
public struct Helper: Equatable, Sendable {
    public var id: String
    public var task: String
    public var lastTool: ToolUse?

    public init(id: String, task: String, lastTool: ToolUse? = nil) {
        self.id = id
        self.task = task
        self.lastTool = lastTool
    }
}

/// `<sessionId>/subagents/agent-<id>.jsonl` (+ `.meta.json`) dosyalarından etkin yardımcıları çıkarır.
/// Meta `finished: true` ise ya da dosya `staleAfter` süresince yazılmadıysa yardımcı işini bitirmiş sayılır.
public struct SubagentScanner: Sendable {
    public static let staleAfter: TimeInterval = 120
    static var fallbackTask: String { L("yardımcı") }

    private struct Known: Sendable {
        var tail = TranscriptTail()
        var lastTool: ToolUse?
        var metaMtime: Date?
        var task = SubagentScanner.fallbackTask
        var finished = false
    }
    private var known: [String: Known] = [:]

    public init() {}

    public mutating func scan(transcriptPath: String, now: Date) -> [Helper] {
        let fm = FileManager.default
        let dir = (transcriptPath.hasSuffix(".jsonl") ? String(transcriptPath.dropLast(6)) : transcriptPath) + "/subagents"
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else {
            known = [:]
            return []
        }
        var out: [Helper] = []
        var seen = Set<String>()
        for name in names.sorted() where name.hasPrefix("agent-") && name.hasSuffix(".jsonl") {
            let id = String(name.dropFirst(6).dropLast(6))
            let path = dir + "/" + name
            guard let mtime = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { continue }
            seen.insert(id)
            var k = known[id] ?? Known()
            let metaPath = dir + "/agent-" + id + ".meta.json"
            let metaMtime = (try? fm.attributesOfItem(atPath: metaPath))?[.modificationDate] as? Date
            if metaMtime != k.metaMtime {
                k.metaMtime = metaMtime
                if let data = fm.contents(atPath: metaPath),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let d = obj["description"] as? String, !d.isEmpty { k.task = d }
                    k.finished = obj["finished"] as? Bool ?? false
                }
            }
            let active = !k.finished && now.timeIntervalSince(mtime) <= Self.staleAfter
            if active, let last = k.tail.read(path: path).last { k.lastTool = last }
            known[id] = k
            if active { out.append(Helper(id: id, task: k.task, lastTool: k.lastTool)) }
        }
        known = known.filter { seen.contains($0.key) }
        return out
    }
}
