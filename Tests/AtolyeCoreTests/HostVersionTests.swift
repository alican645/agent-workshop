import Foundation
import Testing
@testable import AtolyeCore

@Suite struct HostVersionTests {
    private func file(_ text: String) throws -> String {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("hv-\(UUID().uuidString)").path
        try text.write(toFile: p, atomically: true, encoding: .utf8)
        return p
    }

    @Test func sameContentSameHash() throws {
        let a = try file("yardımcı v1"), b = try file("yardımcı v1"), c = try file("yardımcı v2")
        defer { for p in [a, b, c] { try? FileManager.default.removeItem(atPath: p) } }
        let ha = try #require(HostVersion.of(executable: a))
        #expect(ha.count == 64)
        #expect(HostVersion.of(executable: b) == ha)
        #expect(HostVersion.of(executable: c) != ha)
        #expect(HostVersion.of(executable: "/yok/boyle/bir/dosya") == nil)
    }

    @Test func outdatedBranches() {
        #expect(!HostVersion.outdated(running: nil, bundled: nil))   // paket okunamadı: alarm yok
        #expect(!HostVersion.outdated(running: "a", bundled: nil))
        #expect(HostVersion.outdated(running: nil, bundled: "a"))    // eski yardımcı sürüm bildirmiyor
        #expect(!HostVersion.outdated(running: "a", bundled: "a"))
        #expect(HostVersion.outdated(running: "a", bundled: "b"))
    }

    /// Yalnız Atölye terminalinde (yardımcıda) çalışan ve yeri bilinen oturumlar geri açılır; sıra korunur.
    @Test func resumableKeepsOnlyHostedSessions() {
        let cs = [ProfileMove.Candidate(sessionID: "s1", profileID: "p1", terminal: "t1", terminalKind: .claude, working: true, cwd: "/p/a"),
                  ProfileMove.Candidate(sessionID: "cmux", profileID: "p1", terminal: nil, terminalKind: nil, working: false, cwd: "/p/a"),
                  ProfileMove.Candidate(sessionID: "gone", profileID: "p1", terminal: "tx", terminalKind: nil, working: false, cwd: "/p/a"),
                  ProfileMove.Candidate(sessionID: "nocwd", profileID: "p1", terminal: "t2", terminalKind: .claude, working: false, cwd: nil),
                  ProfileMove.Candidate(sessionID: "s2", profileID: "p2", terminal: "t3", terminalKind: .shell, working: false, cwd: "/p/b")]
        #expect(HostRestart.resumable(cs) == [
            HostRestart.Resume(sessionID: "s1", cwd: "/p/a", profileID: "p1", terminal: "t1"),
            HostRestart.Resume(sessionID: "s2", cwd: "/p/b", profileID: "p2", terminal: "t3")])
    }
}
