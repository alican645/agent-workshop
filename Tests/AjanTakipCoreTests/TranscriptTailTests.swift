import Foundation
import Testing
@testable import AjanTakipCore

private func toolLine(_ name: String, _ input: String = "{}") -> String {
    #"{"type":"assistant","timestamp":"2026-11-11T16:32:49.226Z","message":{"content":[{"type":"text","text":"x"},{"type":"tool_use","name":"\#(name)","input":\#(input)}]}}"# + "\n"
}

private func tmpFile(_ body: String = "") throws -> String {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent("tt-\(UUID().uuidString).jsonl").path
    try body.write(toFile: p, atomically: true, encoding: .utf8)
    return p
}

private func append(_ path: String, _ s: String) throws {
    let h = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try h.seekToEnd()
    try h.write(contentsOf: Data(s.utf8))
    try h.close()
}

@Suite struct TranscriptTailTests {
    @Test func targetRules() {
        #expect(ToolSummary.target(name: "Edit", input: ["file_path": "/a/b/InvoiceService.cs"]) == "InvoiceService.cs")
        #expect(ToolSummary.target(name: "Read", input: ["file_path": "/x/y.swift"]) == "y.swift")
        #expect(ToolSummary.target(name: "Bash", input: ["command": "swift test --filter Foo && echo ok"]) == "swift test --filter")
        #expect(ToolSummary.target(name: "Bash", input: ["command": "cd /Users/x/Proje && swift build --product Atolye"]) == "swift build --product")
        #expect(ToolSummary.target(name: "Grep", input: ["pattern": "applyRegistry"]) == "applyRegistry")
        #expect(ToolSummary.target(name: "WebFetch", input: ["url": "https://docs.swift.org/x"]) == "docs.swift.org")
        #expect(ToolSummary.target(name: "Agent", input: ["description": "Review Task 3"]) == "Review Task 3")
        #expect(ToolSummary.target(name: "Mystery", input: [:]) == "")
        #expect(ToolSummary.target(name: "Bash", input: ["command": String(repeating: "a", count: 90)]).count == 40)
    }

    @Test func readsOnlyNewCompleteLines() throws {
        let p = try tmpFile(toolLine("Read", #"{"file_path":"/a/A.swift"}"#) + toolLine("Edit", #"{"file_path":"/a/B.swift"}"#))
        var t = TranscriptTail()
        #expect(t.read(path: p).map(\.target) == ["A.swift", "B.swift"])
        let half = toolLine("Grep", #"{"pattern":"zzz"}"#)
        try append(p, toolLine("Bash", #"{"command":"ls"}"#) + half.prefix(30))
        #expect(t.read(path: p).map(\.name) == ["Bash"])
        try append(p, String(half.dropFirst(30)))
        #expect(t.read(path: p).map(\.target) == ["zzz"])
        #expect(t.read(path: p).isEmpty)
    }

    @Test func ignoresNonToolLines() throws {
        let p = try tmpFile(#"{"type":"user","message":{"content":"hi"}}"# + "\n"
            + #"{"type":"attachment","attachment":{}}"# + "\n"
            + #"{"type":"assistant","message":{"content":[{"type":"text","text":"x"}]}}"# + "\n" + "not json\n")
        var t = TranscriptTail()
        #expect(t.read(path: p).isEmpty)
    }

    @Test func parsesTimestamp() throws {
        let p = try tmpFile(toolLine("Read"))
        var t = TranscriptTail()
        #expect(t.read(path: p).first?.at != nil)
    }

    @Test func firstReadOfHugeFileReadsTail() throws {
        let filler = String(repeating: toolLine("Read", #"{"file_path":"/old.swift"}"#), count: 5000)
        let p = try tmpFile(filler + toolLine("Edit", #"{"file_path":"/new.swift"}"#))
        var t = TranscriptTail()
        let r = t.read(path: p)
        #expect(r.last?.target == "new.swift")
        #expect(r.count < 5000)
    }

    @Test func truncatedFileRestarts() throws {
        let p = try tmpFile(toolLine("Read") + toolLine("Read"))
        var t = TranscriptTail()
        _ = t.read(path: p)
        try toolLine("Bash", #"{"command":"ls"}"#).write(toFile: p, atomically: false, encoding: .utf8)
        #expect(t.read(path: p).map(\.name) == ["Bash"])
    }

    @Test func missingFileIsEmpty() {
        var t = TranscriptTail()
        #expect(t.read(path: "/nonexistent-\(UUID())").isEmpty)
    }

    @Test func findsTranscriptInAnyProjectDir() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tt-cfg-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir + "/projects/-x-erp", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dir + "/projects/-x-other", withIntermediateDirectories: true)
        try "".write(toFile: dir + "/projects/-x-erp/s1.jsonl", atomically: true, encoding: .utf8)
        #expect(TranscriptTail.findTranscript(configDir: dir, sessionID: "s1") == dir + "/projects/-x-erp/s1.jsonl")
        #expect(TranscriptTail.findTranscript(configDir: dir, sessionID: "s2") == nil)
    }
}
