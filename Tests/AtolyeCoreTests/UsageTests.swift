import Foundation
import Testing
@testable import AtolyeCore

@Suite struct PricingTests {
    @Test func looksUpByModelFamily() throws {
        let o55 = try #require(ModelPricing.price(model: "claude-opus-5-5"))
        #expect(o55.input == 4 && o55.output == 20 && o55.cacheRead == 0.20)
        #expect(ModelPricing.price(model: "claude-opus-4-1-20250805")?.input == 15)
        #expect(ModelPricing.price(model: "claude-sonnet-4-5-20250929")?.output == 15)
        #expect(ModelPricing.price(model: "claude-sonnet-5-5")?.cacheRead == 0.10)
        #expect(ModelPricing.price(model: "claude-haiku-4-5-20251001")?.input == 1)
        #expect(ModelPricing.price(model: "claude-fable-5-2")?.output == 40)
        #expect(ModelPricing.price(model: "<synthetic>") == nil)
    }

    @Test func costUsesCacheMultipliers() throws {
        let p = try #require(ModelPricing.price(model: "claude-opus-5-5"))
        let m = 1_000_000
        #expect(TokenUsage(input: m).cost(p) == 4)
        #expect(TokenUsage(output: m).cost(p) == 20)
        #expect(TokenUsage(cacheRead: m).cost(p) == 0.2)
        #expect(TokenUsage(cacheWrite5m: m).cost(p) == 5)
        #expect(TokenUsage(cacheWrite1h: m).cost(p) == 8)
    }
}

@Suite struct UsageMeterTests {
    private func line(_ id: String, model: String = "claude-opus-5-5", input: Int = 0, output: Int, read: Int = 0,
                      w1h: Int = 0, at: String = "2026-11-17T09:00:00.000Z") -> String {
        """
        {"type":"assistant","timestamp":"\(at)","message":{"id":"\(id)","model":"\(model)","content":[],"usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(read),"cache_creation_input_tokens":\(w1h),"cache_creation":{"ephemeral_1h_input_tokens":\(w1h),"ephemeral_5m_input_tokens":0}}}}
        """
    }

    private func dir() throws -> String {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: d + "/s1/subagents", withIntermediateDirectories: true)
        return d
    }

    @Test func dedupesMessagesAndIncludesSubagents() throws {
        let d = try dir()
        let main = d + "/s1.jsonl"
        try ([line("m1", output: 10), line("m1", input: 1_000_000, output: 1_000_000),
              #"{"type":"user","message":{"content":"merhaba"}}"#,
              line("m2", model: "<synthetic>", output: 5)].joined(separator: "\n") + "\n")
            .write(toFile: main, atomically: true, encoding: .utf8)
        try (line("a1", model: "claude-haiku-4-5-20251001", input: 1_000_000, output: 0) + "\n")
            .write(toFile: d + "/s1/subagents/agent-x.jsonl", atomically: true, encoding: .utf8)
        var m = UsageMeter()
        let u = m.read(transcript: main)
        #expect(u.tokens.input == 2_000_000 && u.tokens.output == 1_000_005)
        // opus 5.5: 1M girdi $4 + 1M çıktı $20; haiku 4.5: 1M girdi $1; <synthetic> fiyatsız.
        #expect(abs(u.cost - 25) < 1e-9)
    }

    @Test func readsIncrementallyAndWaitsForCompleteLines() throws {
        let d = try dir()
        let main = d + "/s1.jsonl"
        try (line("m1", output: 1_000_000) + "\n").write(toFile: main, atomically: true, encoding: .utf8)
        var m = UsageMeter()
        #expect(abs(m.read(transcript: main).cost - 20) < 1e-9)
        let h = try #require(FileHandle(forWritingAtPath: main))
        h.seekToEndOfFile()
        let half = line("m2", output: 1_000_000)
        h.write(Data(half.prefix(40).utf8))
        #expect(abs(m.read(transcript: main).cost - 20) < 1e-9)
        h.write(Data((half.dropFirst(40) + "\n").utf8))
        try h.close()
        #expect(abs(m.read(transcript: main).cost - 40) < 1e-9)
    }

    @Test func splitsCostByLocalDay() throws {
        let d = try dir()
        let main = d + "/s1.jsonl"
        try ([line("m1", output: 1_000_000, at: "2026-11-16T10:00:00.000Z"),
              line("m2", output: 500_000, at: "2026-11-17T10:00:00.000Z")].joined(separator: "\n") + "\n")
            .write(toFile: main, atomically: true, encoding: .utf8)
        var m = UsageMeter()
        let u = m.read(transcript: main)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let day = UsageMeter.dayKey(Date(timeIntervalSince1970: 1_794_909_600), calendar: cal) // 2026-11-17 ~13:00 TR
        #expect(u.costByDay(calendar: cal)[day] == 10)
    }
}
