import Foundation
import Testing
@testable import AtolyeCore

struct ProfileMoveTests {
    private func c(_ id: String, profile: String = "p1", terminal: String? = "t-\(UUID().uuidString.prefix(4))",
                   kind: TerminalKind = .claude, working: Bool = false, cwd: String? = "/proje") -> ProfileMove.Candidate {
        ProfileMove.Candidate(sessionID: id, profileID: profile, terminal: terminal, terminalKind: kind,
                              working: working, cwd: cwd)
    }

    @Test func movesIdleAtolyeSessionsOfOtherProfiles() {
        let p = ProfileMove.plan([c("a"), c("b", profile: "p2")], to: "p2")
        #expect(p.now.map(\.sessionID) == ["a"])
        #expect(p.now.first?.cwd == "/proje")
        #expect(p.later.isEmpty)
    }

    /// Çalışan oturum yarıda kesilmez: işi bitince taşınır.
    @Test func workingSessionsWaitUntilDone() {
        let p = ProfileMove.plan([c("a", working: true)], to: "p2")
        #expect(p.now.isEmpty)
        #expect(p.later == ["a"])
    }

    /// cmux gibi Atölye dışında açılmış oturumlara, düz terminalde elle açılmış Claude'a ve dizinsiz oturuma dokunulmaz.
    @Test func skipsOutsideShellAndUnknownCwd() {
        let p = ProfileMove.plan([c("a", terminal: nil), c("b", kind: .shell), c("d", cwd: nil)], to: "p2")
        #expect(p.now.isEmpty && p.later.isEmpty)
    }

    @Test func resumeArgs() {
        #expect(ProfileMove.resumeArgs("abc") == ["--resume", "abc"])
    }
}
