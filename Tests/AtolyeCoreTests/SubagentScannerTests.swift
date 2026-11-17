import Foundation
import Testing
@testable import AtolyeCore

/// Geçici bir sohbet kaydı + `subagents/` klasörü; kaydın yolunu döner.
private func tmpTranscript() throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sa-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: dir + "/s1/subagents", withIntermediateDirectories: true)
    try "".write(toFile: dir + "/s1.jsonl", atomically: true, encoding: .utf8)
    return dir + "/s1.jsonl"
}

private func addAgent(_ transcript: String, id: String, meta: String?, body: String = "", age: TimeInterval = 0, now: Date) throws {
    let base = String(transcript.dropLast(6)) + "/subagents/agent-" + id
    try body.write(toFile: base + ".jsonl", atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: base + ".jsonl")
    if let meta { try meta.write(toFile: base + ".meta.json", atomically: true, encoding: .utf8) }
}

@Suite struct SubagentScannerTests {
    let now = Date()

    @Test func activeHelperHasTaskFromMeta() throws {
        let t = try tmpTranscript()
        try addAgent(t, id: "a1", meta: #"{"description":"testleri yaz","finished":false}"#, now: now)
        var sc = SubagentScanner()
        #expect(sc.scan(transcriptPath: t, now: now) == [Helper(id: "a1", task: "testleri yaz", lastTool: nil)])
    }

    @Test func finishedOrStaleHelperDisappears() throws {
        let t = try tmpTranscript()
        try addAgent(t, id: "a1", meta: #"{"description":"x","finished":true}"#, now: now)
        try addAgent(t, id: "a2", meta: #"{"description":"y"}"#, age: 121, now: now)
        try addAgent(t, id: "a3", meta: #"{"description":"z"}"#, age: 60, now: now)
        var sc = SubagentScanner()
        #expect(sc.scan(transcriptPath: t, now: now).map(\.id) == ["a3"])
    }

    @Test func missingMetaUsesFallbackTask() throws {
        let t = try tmpTranscript()
        try addAgent(t, id: "a1", meta: nil, now: now)
        var sc = SubagentScanner()
        #expect(sc.scan(transcriptPath: t, now: now).map(\.task) == ["yardımcı"])
    }

    @Test func helperCarriesLastTool() throws {
        let t = try tmpTranscript()
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/B.swift"}}]}}"# + "\n"
        try addAgent(t, id: "a1", meta: #"{"description":"d"}"#, body: line, now: now)
        var sc = SubagentScanner()
        let h = sc.scan(transcriptPath: t, now: now)
        #expect(h.first?.lastTool?.name == "Edit" && h.first?.lastTool?.target == "B.swift")
        // Yeni araç yoksa son araç korunur.
        #expect(sc.scan(transcriptPath: t, now: now).first?.lastTool?.name == "Edit")
    }

    @Test func noSubagentsDirIsEmpty() {
        var sc = SubagentScanner()
        #expect(sc.scan(transcriptPath: "/nonexistent-\(UUID()).jsonl", now: now).isEmpty)
    }
}
