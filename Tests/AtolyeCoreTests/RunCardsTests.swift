import Foundation
import Testing
@testable import AtolyeCore

private func terminal(_ id: String, cwd: String = "/p/x", running: Bool, code: Int32?, card: String? = nil) -> TerminalInfo {
    TerminalInfo(id: id, cwd: cwd, title: "zsh", kind: .shell, pid: 1, running: running, exitCode: code, lastOutputAt: nil)
}

@Suite struct RunCardsTests {
    @Test func parsesCards() {
        let json = #"{"cards":[{"id":"a","name":"Deploy","command":"./deploy.sh","confirm":false}]}"#
        let cards = RunCardFile.parse(Data(json.utf8))
        #expect(cards == [RunCard(id: "a", name: "Deploy", command: "./deploy.sh", confirm: false)])
    }

    @Test func missingConfirmDefaultsTrue() {
        let json = #"{"cards":[{"id":"a","name":"Deploy","command":"./deploy.sh"}]}"#
        #expect(RunCardFile.parse(Data(json.utf8)).first?.confirm == true)
    }

    @Test func invalidJSONIsEmpty() {
        #expect(RunCardFile.parse(Data("{bozuk".utf8)).isEmpty)
        #expect(RunCardFile.parse(Data("[]".utf8)).isEmpty)
    }

    @Test func roundTripsThroughDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("runcards-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(RunCardFile.cards(root: root).isEmpty)
        let cards = [RunCard(id: "a", name: "Deploy", command: "./deploy.sh", confirm: true),
                     RunCard(id: "b", name: "Test", command: "swift test", confirm: false)]
        try RunCardFile.write(cards, root: root)
        #expect(RunCardFile.path(root: root) == root + "/RUN.local.json")
        #expect(RunCardFile.cards(root: root) == cards)
    }

    @Test func stateFromTerminal() {
        #expect(RunCards.state(of: nil) == .idle)
        #expect(RunCards.state(of: terminal("t", running: true, code: nil)) == .running)
        #expect(RunCards.state(of: terminal("t", running: false, code: 0)) == .ok)
        #expect(RunCards.state(of: terminal("t", running: false, code: 3)) == .failed)
        #expect(RunCards.state(of: terminal("t", running: false, code: nil)) == .failed)
    }
}
