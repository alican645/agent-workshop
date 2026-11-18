import Foundation
import Testing
@testable import AtolyeCore

private func ask(_ questions: [(q: String, multi: Bool, opts: [(String, String)])]) -> PendingTool {
    let qs: [JSONValue] = questions.map { q in
        .object(["question": .string(q.q), "header": .string("H"), "multiSelect": .bool(q.multi),
                 "options": .array(q.opts.map { .object(["label": .string($0.0), "description": .string($0.1)]) })])
    }
    return PendingTool(id: "t1", name: "AskUserQuestion", input: ["questions": .array(qs)])
}

private let colorScreen = ScreenPrompt(
    kind: .question, title: "Which color do you prefer?", detail: nil,
    options: [ScreenOption(label: "Red", stop: 0), ScreenOption(label: "Blue", stop: 1),
              ScreenOption(label: "Type something.", freeText: true, stop: 2), ScreenOption(label: "Chat about this", stop: 3)],
    selected: 0, multi: false, page: nil)

@Suite struct PromptInfoTests {
    @Test func screenWinsOverTranscriptCommand() {
        let screen = ScreenPrompt(kind: .permission, title: "Do you want to proceed?", detail: "ls -la",
                                  options: [ScreenOption(label: "Yes", stop: 0), ScreenOption(label: "No", stop: 1)],
                                  selected: 0, multi: false, page: nil)
        let pending = PendingTool(id: "x", name: "Bash", input: ["command": .string("rm -rf x")])
        let info = PromptMerge.info(screen: screen, pending: pending, hasTerminal: true, sent: false, failed: false)
        #expect(info?.detail == "ls -la")
        #expect(info?.kind == .permission)
        #expect(info?.question == "Do you want to proceed?")
        #expect(info?.options.map(\.label) == ["Yes", "No"])
        #expect(info?.answerable == true)
    }

    @Test func transcriptCommandUsedWhenOnScreen() {
        let screen = ScreenPrompt(kind: .permission, title: "Do you want to proceed?", detail: "Bash command\n  touch out.txt",
                                  options: [ScreenOption(label: "Yes", stop: 0), ScreenOption(label: "No", stop: 1)],
                                  selected: 0, multi: false, page: nil)
        let pending = PendingTool(id: "x", name: "Bash", input: ["command": .string("touch out.txt")])
        let info = PromptMerge.info(screen: screen, pending: pending, hasTerminal: true, sent: false, failed: false)
        #expect(info?.detail == "touch out.txt")
    }

    private func permission(_ detail: String, pending cmd: String) -> PromptInfo? {
        let screen = ScreenPrompt(kind: .permission, title: "Do you want to proceed?", detail: detail,
                                  options: [ScreenOption(label: "Yes", stop: 0), ScreenOption(label: "No", stop: 1)],
                                  selected: 0, multi: false, page: nil)
        return PromptMerge.info(screen: screen, pending: PendingTool(id: "x", name: "Bash", input: ["command": .string(cmd)]),
                                hasTerminal: true, sent: false, failed: false)
    }

    @Test func screenSupersetCommandKept() {
        // Alt ajan "--force" istiyor, ana kayıttaki komut daha zayıf: ekrandaki gösterilmeli.
        let detail = "Bash command\n╌╌╌╌\n git push origin x --force\n╌╌╌╌"
        #expect(permission(detail, pending: "git push origin x")?.detail == detail)
    }

    @Test func prefixOnlyCommandKept() {
        let detail = "Bash command\n swift build --product Atolye && swift test --filter Prompt"
        #expect(permission(detail, pending: "swift build --product Atolye && swift test --filter PromptInfo")?.detail == detail)
        #expect(permission("Bash command\n swift build", pending: "swift build --product Atolye")?.detail == "Bash command\n swift build")
    }

    @Test func wrappedCommandBetweenRulesMatches() {
        let detail = "Bash command\n╌╌╌╌\n echo one two\n three four\n╌╌╌╌\nDo something"
        #expect(permission(detail, pending: "echo one two three four")?.detail == "echo one two three four")
    }

    @Test func realBashPermissionUsesTranscriptCommand() throws {
        let url = try #require(Bundle.module.url(forResource: "bash-permission", withExtension: "txt", subdirectory: "Fixtures/prompts"))
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        let screen = try #require(PromptParser.parse(lines: lines, cursorRow: 0))
        let ok = PromptMerge.info(screen: screen, pending: PendingTool(id: "x", name: "Bash", input: ["command": .string("touch out.txt")]),
                                  hasTerminal: true, sent: false, failed: false)
        #expect(ok?.detail == "touch out.txt")
        let other = PromptMerge.info(screen: screen, pending: PendingTool(id: "x", name: "Bash", input: ["command": .string("touch")]),
                                     hasTerminal: true, sent: false, failed: false)
        #expect(other?.detail == screen.detail)
    }

    @Test func transcriptEnrichesQuestion() {
        // Ekran uzun sorunun yalnız son satırını gösterir; kayıttaki tam metin onunla bitiyorsa kullanılır.
        let long = "Uzun bir giriş cümlesi, ardından asıl soru:  Which color do you\n prefer?"
        let pending = ask([(q: long, multi: false, opts: [("Red", "sıcak"), ("Blue", "soğuk")])])
        let info = PromptMerge.info(screen: colorScreen, pending: pending, hasTerminal: true, sent: true, failed: false)
        #expect(info?.question == long)
        #expect(info?.options.map(\.label) == ["Red", "Blue", "Type something.", "Chat about this"])
        #expect(info?.options.map(\.description) == ["sıcak", "soğuk", nil, nil])
        #expect(info?.options.map(\.freeText) == [false, false, true, false])
        #expect(info?.sent == true && info?.answerable == true)
    }

    @Test func mismatchedTranscriptOptionsIgnored() {
        let pending = ask([(q: "Başka soru", multi: false, opts: [("Green", "g"), ("Red", "r")])])
        let info = PromptMerge.info(screen: colorScreen, pending: pending, hasTerminal: true, sent: false, failed: false)
        #expect(info?.question == "Which color do you prefer?")
        #expect(info?.options.map(\.label) == ["Red", "Blue", "Type something.", "Chat about this"])
        #expect(info?.options.allSatisfy { $0.description == nil } == true)
    }

    @Test func pagesPickMatchingQuestion() {
        var screen = colorScreen
        screen.title = "Which size?"
        screen.options = [ScreenOption(label: "Small", stop: 0), ScreenOption(label: "Large", stop: 1)]
        screen.page = (index: 1, count: 2)
        let pending = ask([(q: "Renk?", multi: false, opts: [("Red", "r"), ("Blue", "b")]),
                           (q: "Which size?", multi: false, opts: [("Small", "küçük"), ("Large", "büyük")])])
        let info = PromptMerge.info(screen: screen, pending: pending, hasTerminal: true, sent: false, failed: false)
        #expect(info?.question == "Which size?")
        #expect(info?.options.map(\.description) == ["küçük", "büyük"])
        #expect(info?.page == 1 && info?.pages == 2)
    }

    @Test func outsideSessionNotAnswerable() {
        let pending = ask([(q: "Hangi meyve?", multi: true, opts: [("Elma", "a"), ("Muz", "b")])])
        let info = PromptMerge.info(screen: nil, pending: pending, hasTerminal: false, sent: false, failed: false)
        #expect(info?.answerable == false)
        #expect(info?.kind == .question)
        #expect(info?.question == "Hangi meyve?")
        #expect(info?.multi == true)
        #expect(info?.options.map(\.label) == ["Elma", "Muz"])
        #expect(info?.options.map(\.description) == ["a", "b"])
    }

    @Test func screenIgnoredWithoutTerminal() {
        let info = PromptMerge.info(screen: colorScreen, pending: nil, hasTerminal: false, sent: false, failed: false)
        #expect(info == nil)
    }

    @Test func noScreenNoPendingIsNil() {
        #expect(PromptMerge.info(screen: nil, pending: nil, hasTerminal: true, sent: false, failed: false) == nil)
        #expect(PromptMerge.info(screen: nil, pending: nil, hasTerminal: false, sent: false, failed: false) == nil)
        // Terminal var ama ekran henüz okunmadı: kayıttan cevaplanamaz balon gösterme.
        let pending = ask([(q: "Q", multi: false, opts: [("A", "")])])
        #expect(PromptMerge.info(screen: nil, pending: pending, hasTerminal: true, sent: false, failed: false) == nil)
        // Dışarıdaki izin isteği kayıttan çizilemez.
        let bash = PendingTool(id: "x", name: "Bash", input: ["command": .string("ls")])
        #expect(PromptMerge.info(screen: nil, pending: bash, hasTerminal: false, sent: false, failed: false) == nil)
    }

    @Test func planHasPlanPathSlot() {
        let pending = PendingTool(id: "p", name: "ExitPlanMode", input: ["plan": .string("# Plan\n1. adım")])
        let outside = PromptMerge.info(screen: nil, pending: pending, hasTerminal: false, sent: false, failed: false)
        #expect(outside?.kind == .plan)
        #expect(outside?.answerable == false)
        #expect(outside?.planPath == nil)
        let screen = ScreenPrompt(kind: .plan, title: "Claude has written up a plan and is ready to execute. Would you like to proceed?",
                                  detail: nil,
                                  options: [ScreenOption(label: "Yes, and use auto mode", stop: 0),
                                            ScreenOption(label: "Tell Claude what to change", freeText: true, stop: 1)],
                                  selected: 0, multi: false, page: nil)
        let inside = PromptMerge.info(screen: screen, pending: pending, hasTerminal: true, sent: false, failed: false)
        #expect(inside?.kind == .plan)
        #expect(inside?.question == screen.title)
        #expect(inside?.options.map(\.label) == ["Yes, and use auto mode", "Tell Claude what to change"])
        #expect(inside?.answerable == true)
    }

    @Test func realScreenKeepsLabels() throws {
        let url = try #require(Bundle.module.url(forResource: "ask-pages", withExtension: "txt", subdirectory: "Fixtures/prompts"))
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        let screen = try #require(PromptParser.parse(lines: lines, cursorRow: 0))
        let pending = ask([(q: "Which color do you prefer?", multi: false, opts: [("Red", "r"), ("Blue", "b"), ("Green", "g")]),
                           (q: "Which size?", multi: false, opts: [("Small", "s"), ("Large", "l")])])
        let info = try #require(PromptMerge.info(screen: screen, pending: pending, hasTerminal: true, sent: false, failed: false))
        #expect(info.options.map(\.label) == screen.options.map(\.label))
        #expect(info.options.prefix(3).map(\.description) == ["r", "b", "g"])
        #expect(info.page == 0 && info.pages == 3)
    }

    @Test func encodesFieldNames() throws {
        let info = PromptMerge.info(screen: colorScreen, pending: nil, hasTerminal: true, sent: false, failed: true)
        let obj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(info)) as? [String: Any])
        #expect(obj["kind"] as? String == "question")
        #expect(obj["failed"] as? Bool == true)
        #expect(obj["multi"] as? Bool == false)
    }

    // Bulgu 5: gitmeyen cevap "gönderildi…" değil "gitmedi" gösterir.
    @Test func failedIsNotSent() {
        let info = PromptMerge.info(screen: colorScreen, pending: nil, hasTerminal: true, sent: true, failed: true)
        #expect(info?.sent == false && info?.failed == true)
        #expect(PromptMerge.info(screen: colorScreen, pending: nil, hasTerminal: true, sent: true, failed: false)?.sent == true)
    }

    // Bulgu 6: ekran okundu ama menü tanınmadı → cevaplanamaz balon ("terminalinden cevapla · terminali aç").
    @Test func unparsedScreenGivesOffBalloon() {
        let generic = PromptMerge.info(screen: nil, pending: nil, hasTerminal: true, screenRead: true, sent: false, failed: false)
        #expect(generic?.answerable == false)
        #expect(generic?.options.isEmpty == true && generic?.question == "")
        #expect(generic?.kind == .permission)
        let bash = PendingTool(id: "x", name: "Bash", input: ["command": .string("ls")])
        #expect(PromptMerge.info(screen: nil, pending: bash, hasTerminal: true, screenRead: true, sent: false, failed: false)?
            .answerable == false)
        let q = ask([(q: "Hangi meyve?", multi: true, opts: [("Elma", "a"), ("Muz", "b")])])
        let fromLog = PromptMerge.info(screen: nil, pending: q, hasTerminal: true, screenRead: true, sent: false, failed: false)
        #expect(fromLog?.kind == .question && fromLog?.question == "Hangi meyve?" && fromLog?.answerable == false)
        let plan = PendingTool(id: "p", name: "ExitPlanMode", input: ["plan": .string("# P")])
        #expect(PromptMerge.info(screen: nil, pending: plan, hasTerminal: true, screenRead: true, sent: false, failed: false)?
            .kind == .plan)
        // Ekran henüz okunmadıysa hâlâ balon yok (titreme olmasın).
        #expect(PromptMerge.info(screen: nil, pending: q, hasTerminal: true, screenRead: false, sent: false, failed: false) == nil)
    }

    // Bulgu 7: çizgiler varsa yalnız aralarındaki birleşik komut karşılaştırılır; kırılmış komutun ilk satırı yetmez.
    @Test func wrappedCommandFirstLineDoesNotMatch() {
        let detail = "Bash command\n╌╌╌╌\n git push origin main\n --force\n╌╌╌╌\nPush"
        #expect(permission(detail, pending: "git push origin main")?.detail == detail)
        #expect(permission(detail, pending: "git push origin main --force")?.detail == "git push origin main --force")
    }

    // Bulgu 8: aynı etiketli başka bir soru ekrandaki sorunun yerine geçmez.
    @Test func transcriptQuestionMustMatchScreenTitle() {
        let pending = ask([(q: "Başka bir soru?", multi: false, opts: [("Red", "r"), ("Blue", "b")])])
        let info = PromptMerge.info(screen: colorScreen, pending: pending, hasTerminal: true, sent: false, failed: false)
        #expect(info?.question == "Which color do you prefer?")
        #expect(info?.options.allSatisfy { $0.description == nil } == true)
        // Aynı etiketli iki sayfa: başlığı tutan seçilir.
        let two = ask([(q: "Favourite?", multi: false, opts: [("Red", "x"), ("Blue", "y")]),
                       (q: "Which color do you prefer?", multi: false, opts: [("Red", "r"), ("Blue", "b")])])
        let picked = PromptMerge.info(screen: colorScreen, pending: two, hasTerminal: true, sent: false, failed: false)
        #expect(picked?.options.prefix(2).map(\.description) == ["r", "b"])
    }

    // Bulgu 4: balon ham ekranın kimliğini taşır (birleştirilmiş/zenginleştirilmiş detay değil).
    @Test func menuIdFromRawScreen() {
        let screen = ScreenPrompt(kind: .permission, title: "Do you want to proceed?", detail: "Bash command\n  touch out.txt",
                                  options: [ScreenOption(label: "Yes", stop: 0), ScreenOption(label: "No", stop: 1)],
                                  selected: 0, multi: false, page: nil)
        let pending = PendingTool(id: "x", name: "Bash", input: ["command": .string("touch out.txt")])
        let info = PromptMerge.info(screen: screen, pending: pending, hasTerminal: true, sent: false, failed: false)
        #expect(info?.detail == "touch out.txt")
        #expect(info?.menuId == screen.menuId)
        #expect(PromptMerge.info(screen: nil, pending: ask([(q: "Q", multi: false, opts: [("A", "")])]),
                                 hasTerminal: false, sent: false, failed: false)?.menuId == "")
    }
}
