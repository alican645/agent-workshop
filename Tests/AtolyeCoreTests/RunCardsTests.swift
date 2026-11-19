import Foundation
import Testing
@testable import AtolyeCore

private func terminal(_ id: String, cwd: String = "/p/x", running: Bool, code: Int32?, card: String? = nil) -> TerminalInfo {
    TerminalInfo(id: id, cwd: cwd, title: "zsh", kind: .shell, pid: 1, running: running, exitCode: code, lastOutputAt: nil,
                 run: card.map { RunSpec(cardID: $0, name: $0, command: "x") })
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

    @Test func latestTerminalPicksNewestForCardAndRoot() {
        let ts = [terminal("a1", running: false, code: 0, card: "a"),
                  terminal("other-root", cwd: "/p/y", running: true, code: nil, card: "a"),
                  terminal("b1", running: true, code: nil, card: "b"),
                  terminal("plain", running: true, code: nil),
                  terminal("a2", running: true, code: nil, card: "a")]
        #expect(RunCards.latestTerminal(card: "a", root: "/p/x", in: ts)?.id == "a2")
        #expect(RunCards.latestTerminal(card: "b", root: "/p/x", in: ts)?.id == "b1")
        #expect(RunCards.latestTerminal(card: "c", root: "/p/x", in: ts) == nil)
    }

    @Test func decide() {
        let ask = RunCard(id: "a", name: "Deploy", command: "./deploy.sh", confirm: true)
        let quiet = RunCard(id: "a", name: "Deploy", command: "./deploy.sh", confirm: false)
        #expect(RunLaunch.decide(card: RunCard(id: "a", name: "x", command: "  \n"), latest: nil) == .invalid)
        #expect(RunLaunch.decide(card: ask, latest: terminal("t", running: true, code: nil, card: "a")) == .focus(terminal: "t"))
        #expect(RunLaunch.decide(card: quiet, latest: terminal("t", running: true, code: nil, card: "a")) == .focus(terminal: "t"))
        #expect(RunLaunch.decide(card: ask, latest: terminal("t", running: false, code: 0, card: "a")) == .ask)
        #expect(RunLaunch.decide(card: ask, latest: nil) == .ask)
        #expect(RunLaunch.decide(card: quiet, latest: nil) == .start)
    }

    private func tmpRoot() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("runcards-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    /// Elle yazılmış, kimliği olmayan kart kaybolmaz; kimliği her okumada aynıdır (çark karta bağlı kalsın).
    @Test func cardWithoutIdGetsStableId() {
        let json = #"{"cards":[{"name":"Deploy","command":"./deploy.sh"},{"id":"b","name":"T","command":"t"}]}"#
        let a = RunCardFile.parse(Data(json.utf8)), b = RunCardFile.parse(Data(json.utf8))
        #expect(a.count == 2 && a.map(\.name) == ["Deploy", "T"])
        #expect(!a[0].id.isEmpty && a[0].id == b[0].id)
    }

    /// Bozuk dosya "okunamadı" olarak bildirilir; dosya yoksa boş liste.
    @Test func loadDistinguishesUnreadableFromMissing() throws {
        let root = try tmpRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(RunCardFile.load(root: root) == [])
        try "{bozuk".write(toFile: RunCardFile.path(root: root), atomically: true, encoding: .utf8)
        #expect(RunCardFile.load(root: root) == nil)
    }

    /// Bozuk dosyaya yazılmaz: kullanıcının elle yazdıkları kaybolmasın.
    @Test func updateRefusesUnreadableFile() throws {
        let root = try tmpRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try "{bozuk".write(toFile: RunCardFile.path(root: root), atomically: true, encoding: .utf8)
        #expect(throws: RunCardFile.Unreadable.self) { try RunCardFile.update(root: root) { $0.append(RunCard(name: "x", command: "y")) } }
        #expect(try String(contentsOfFile: RunCardFile.path(root: root), encoding: .utf8) == "{bozuk")
    }

    /// Değişiklik dosyanın son haline uygulanır (pencerede eski kopya olsa da başka alan geri dönmez).
    @Test func updateEditsFreshContents() throws {
        let root = try tmpRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try RunCardFile.write([RunCard(id: "a", name: "Deploy", command: "./deploy.sh", confirm: false)], root: root)
        try RunCardFile.update(root: root) { $0[0].confirm = true }
        try RunCardFile.update(root: root) { list in if let i = list.firstIndex(where: { $0.id == "a" }) { list[i].name = "Yayınla" } }
        #expect(RunCardFile.cards(root: root) == [RunCard(id: "a", name: "Yayınla", command: "./deploy.sh", confirm: true)])
    }

    /// Başlatılmış ama host'tan henüz cevap gelmemiş kart ikinci kez başlatılmaz.
    @Test func decidePendingWaits() {
        let quiet = RunCard(id: "a", name: "Deploy", command: "./deploy.sh", confirm: false)
        #expect(RunLaunch.decide(card: quiet, latest: nil, pending: true) == .pending)
        #expect(RunLaunch.decide(card: quiet, latest: nil, pending: false) == .start)
    }
}
