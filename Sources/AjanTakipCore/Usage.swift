import Foundation

/// Milyon token başına dolar (Anthropic API liste fiyatı).
public struct Price: Equatable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    /// 5 dakikalık önbelleğe yazma: girdinin 1,25 katı; 1 saatlik: 2 katı.
    public var write5m: Double { input * 1.25 }
    public var write1h: Double { input * 2 }
}

/// Model kimliğinden fiyat. Claude Code abonelikle kullanılsa da "API karşılığı" tahmini için.
public enum ModelPricing {
    /// Önce daha özel önekler.
    static let table: [(prefix: String, price: Price)] = [
        ("claude-fable-5-2", Price(input: 8, output: 40, cacheRead: 0.20)),
        ("claude-mythos-5-2", Price(input: 8, output: 40, cacheRead: 0.20)),
        ("claude-fable-5", Price(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-mythos-5", Price(input: 10, output: 50, cacheRead: 1.0)),
        ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-8", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-7", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-6", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-5", Price(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4", Price(input: 15, output: 75, cacheRead: 1.50)),
        ("claude-sonnet-5-5", Price(input: 2, output: 10, cacheRead: 0.10)),
        ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-3-7-sonnet", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-3-5-sonnet", Price(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-5-5", Price(input: 0.10, output: 0.50, cacheRead: 0.01)),
        ("claude-haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.10)),
        ("claude-3-5-haiku", Price(input: 0.80, output: 4, cacheRead: 0.08)),
    ]

    public static func price(model: String) -> Price? {
        table.first { model.hasPrefix($0.prefix) }?.price
    }
}

public struct TokenUsage: Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    public var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

    public func cost(_ p: Price) -> Double {
        (Double(input) * p.input + Double(output) * p.output + Double(cacheRead) * p.cacheRead
            + Double(cacheWrite5m) * p.write5m + Double(cacheWrite1h) * p.write1h) / 1_000_000
    }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output, cacheRead: a.cacheRead + b.cacheRead,
                   cacheWrite5m: a.cacheWrite5m + b.cacheWrite5m, cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h)
    }
}

/// Bir oturumun (yardımcıları dahil) toplam kullanımı.
public struct SessionUsage: Sendable {
    public var tokens = TokenUsage()
    /// Dolar, API liste fiyatıyla.
    public var cost = 0.0
    var dated: [(at: Date, cost: Double)] = []

    public init() {}

    /// Yerel güne göre maliyet ("yyyy-MM-dd").
    public func costByDay(calendar: Calendar = .current) -> [String: Double] {
        var out: [String: Double] = [:]
        for d in dated { out[UsageMeter.dayKey(d.at, calendar: calendar), default: 0] += d.cost }
        return out
    }
}

/// Oturum kaydını (ve `<oturum>/subagents/*.jsonl` yardımcı kayıtlarını) baştan, artımlı okuyup token
/// kullanımını toplar. Claude Code aynı mesajı birkaç satırda yazar; mesaj kimliğiyle tekilleştirilir.
public struct UsageMeter: Sendable {
    private struct Message: Sendable {
        var usage: TokenUsage
        var model: String
        var at: Date?
    }

    private var offsets: [String: UInt64] = [:]
    private var messages: [String: Message] = [:]

    public init() {}

    public mutating func read(transcript path: String) -> SessionUsage {
        var files = [path]
        let sub = (path.hasSuffix(".jsonl") ? String(path.dropLast(6)) : path) + "/subagents"
        if let names = try? FileManager.default.contentsOfDirectory(atPath: sub) {
            files += names.filter { $0.hasSuffix(".jsonl") }.sorted().map { sub + "/" + $0 }
        }
        for f in files { readNew(f) }
        return summary()
    }

    private mutating func readNew(_ path: String) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64 else { return }
        var offset = offsets[path] ?? 0
        if size < offset { offset = 0 } // dosya kısaldı: baştan
        guard size > offset, let h = FileHandle(forReadingAtPath: path) else { return }
        defer { try? h.close() }
        do { try h.seek(toOffset: offset) } catch { return }
        guard let data = try? h.read(upToCount: Int(size - offset)),
              let lastNL = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = data[data.startIndex...lastNL]
        offsets[path] = offset + UInt64(complete.count)
        let marker = Data("\"usage\"".utf8)
        for line in complete.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        where line.range(of: marker) != nil {
            if let (id, m) = Self.parse(line) { messages[id] = m }
        }
    }

    private static func parse(_ line: Data.SubSequence) -> (String, Message)? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any], let id = msg["id"] as? String,
              let u = msg["usage"] as? [String: Any] else { return nil }
        func n(_ k: String, _ d: [String: Any] = u) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        let creation = u["cache_creation"] as? [String: Any]
        let w1h = creation.map { n("ephemeral_1h_input_tokens", $0) } ?? 0
        // Ayrıntı yoksa önbelleğe yazmanın tamamını 5 dakikalık say.
        let w5m = creation.map { n("ephemeral_5m_input_tokens", $0) } ?? n("cache_creation_input_tokens")
        let usage = TokenUsage(input: n("input_tokens"), output: n("output_tokens"), cacheRead: n("cache_read_input_tokens"),
                               cacheWrite5m: w5m, cacheWrite1h: w1h)
        let at = (obj["timestamp"] as? String).flatMap { try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0) }
        return (id, Message(usage: usage, model: msg["model"] as? String ?? "", at: at))
    }

    private func summary() -> SessionUsage {
        var s = SessionUsage()
        for m in messages.values {
            s.tokens = s.tokens + m.usage
            guard let p = ModelPricing.price(model: m.model) else { continue }
            let c = m.usage.cost(p)
            s.cost += c
            if let at = m.at { s.dated.append((at, c)) }
        }
        return s
    }

    public static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
