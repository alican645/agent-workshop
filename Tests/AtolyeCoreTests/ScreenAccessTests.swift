import Testing
@testable import AtolyeCore

@Suite struct ScreenAccessTests {
    @Test func claudeTerminalIsReadable() {
        #expect(ScreenAccess.readable(kind: .claude, claimants: 1))
    }

    @Test func shellWithOneClaudeIsReadable() {
        // zsh'te `claude` yazılmış: terminalin önündeki süreç o oturum.
        #expect(ScreenAccess.readable(kind: .shell, claimants: 1))
    }

    @Test func shellWithSeveralClaudesIsNot() {
        // Ekrandaki menünün hangi oturuma ait olduğu bilinmez: cevap yanlış sürece gidebilir.
        #expect(!ScreenAccess.readable(kind: .shell, claimants: 2))
        #expect(!ScreenAccess.readable(kind: .shell, claimants: 0))
    }

    @Test func unknownTerminalIsNot() {
        #expect(!ScreenAccess.readable(kind: nil, claimants: 1))
    }
}
