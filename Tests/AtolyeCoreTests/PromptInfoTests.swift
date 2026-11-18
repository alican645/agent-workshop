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

    @Test func transcriptEnrichesQuestion() {
        let pending = ask([(q: "Hangi renk? (uzun soru metni)", multi: false, opts: [("Red", "sıcak"), ("Blue", "soğuk")])])
        let info = PromptMerge.info(screen: colorScreen, pending: pending, hasTerminal: true, sent: true, failed: false)
        #expect(info?.question == "Hangi renk? (uzun soru metni)")
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
                           (q: "Boy?", multi: false, opts: [("Small", "küçük"), ("Large", "büyük")])])
        let info = PromptMerge.info(screen: screen, pending: pending, hasTerminal: true, sent: false, failed: false)
        #expect(info?.question == "Boy?")
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
}
