import Foundation

/// Sohbet kaydındaki bir araç çağrısı: araç adı ve kısa hedefi ("InvoiceService.cs", "swift test --filter").
public struct ToolUse: Equatable, Sendable {
    public var name: String
    public var target: String
    public var at: Date?

    public init(name: String, target: String, at: Date? = nil) {
        self.name = name
        self.target = target
        self.at = at
    }
}

public enum ToolSummary {
    static let maxLength = 40

    /// Araç girdisinden ekranda gösterilecek kısa hedef.
    public static func target(name: String, input: [String: Any]) -> String {
        func str(_ k: String) -> String? { (input[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        var out = ""
        if let path = str("file_path") ?? str("notebook_path") ?? str("path"), !["Grep", "Glob"].contains(name) {
            out = (path as NSString).lastPathComponent
        }
        if out.isEmpty {
            switch name {
            case "Bash":
                var cmd = Substring(str("command") ?? "")
                // Baştaki `cd <klasör> &&` asıl komutu gizlemesin.
                if cmd.hasPrefix("cd "), let r = cmd.range(of: "&&") { cmd = cmd[r.upperBound...] }
                out = cmd.split(whereSeparator: \.isWhitespace).prefix(3).joined(separator: " ")
            case "Grep", "Glob":
                out = str("pattern") ?? ""
            case "WebFetch":
                out = str("url").flatMap { URL(string: $0)?.host } ?? ""
            case "WebSearch":
                out = str("query") ?? ""
            case "Agent", "Task":
                out = str("description") ?? ""
            default:
                out = ""
            }
        }
        return String(out.prefix(maxLength))
    }
}

/// Sohbet kaydını (`<sessionId>.jsonl`) artımlı okur: her çağrıda yalnız yeni eklenen tam satırlardaki
/// `tool_use` bloklarını döner. İlk okumada büyük dosyanın yalnız sonu okunur.
public struct TranscriptTail: Sendable {
    static let initialWindow: UInt64 = 256 * 1024
    /// Sonucu beklenen en çok bu kadar çağrı tutulur (paralel araç çağrıları için).
    static let unansweredKeep = 16
    private var path: String?
    private var offset: UInt64 = 0
    /// tool_result'ı henüz gelmemiş çağrılar, eskiden yeniye.
    private var unanswered: [PendingTool] = []
    /// Cevaplanmamış son araç çağrısı (izin, AskUserQuestion, ExitPlanMode beklerken bu olur).
    public var pending: PendingTool? { unanswered.last }

    public init() {}

    public mutating func read(path: String) -> [ToolUse] {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64,
              let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        var skipFirstLine = false
        if self.path != path || size < offset {
            self.path = path
            offset = size > Self.initialWindow ? size - Self.initialWindow : 0
            skipFirstLine = offset > 0
            unanswered = []
        }
        guard size > offset else { return [] }
        do { try h.seek(toOffset: offset) } catch { return [] }
        guard let data = try? h.read(upToCount: Int(size - offset)), !data.isEmpty else { return [] }
        guard let lastNL = data.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        let complete = data[data.startIndex...lastNL]
        offset += UInt64(complete.count)
        var lines = complete.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if skipFirstLine, !lines.isEmpty { lines.removeFirst() }
        var out: [ToolUse] = []
        for line in lines { out += process(line) }
        return out
    }

    /// Satırdaki araç çağrılarını döner; çağrı/sonuç eşleşmesiyle `pending`'i günceller.
    private mutating func process(_ line: Data.SubSequence) -> [ToolUse] {
        // Ucuz ön eleme: araç çağrısı ya da sonucu olmayan satırları JSON'a çevirme.
        guard line.count > 20, let s = String(data: Data(line), encoding: .utf8),
              s.contains("\"tool_use\"") || s.contains("\"tool_result\""),
              let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]] else { return [] }
        let type = obj["type"] as? String
        if type == "user" {
            let done = Set(content.compactMap { b in
                b["type"] as? String == "tool_result" ? b["tool_use_id"] as? String : nil
            })
            if !done.isEmpty { unanswered.removeAll { done.contains($0.id) } }
            return []
        }
        guard type == "assistant" else { return [] }
        let at = (obj["timestamp"] as? String).flatMap(Self.parseDate)
        return content.compactMap { b in
            guard b["type"] as? String == "tool_use", let name = b["name"] as? String else { return nil }
            let input = b["input"] as? [String: Any] ?? [:]
            if let id = b["id"] as? String {
                unanswered.append(PendingTool(id: id, name: name, input: input.mapValues(JSONValue.init(any:))))
                if unanswered.count > Self.unansweredKeep { unanswered.removeFirst(unanswered.count - Self.unansweredKeep) }
            }
            return ToolUse(name: name, target: ToolSummary.target(name: name, input: input), at: at)
        }
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// `<configDir>/projects/*/<sessionID>.jsonl`
    public static func findTranscript(configDir: String, sessionID: String) -> String? {
        let root = configDir + "/projects"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: root) else { return nil }
        for d in dirs.sorted() {
            let p = root + "/" + d + "/" + sessionID + ".jsonl"
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }
}
