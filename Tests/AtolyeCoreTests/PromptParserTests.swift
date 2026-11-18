import Foundation
import Testing
@testable import AtolyeCore

/// Gerçek Claude Code 2.1.327 ekranları üzerinde (bkz. Fixtures/prompts/README.md).
@Suite struct PromptParserTests {
    private func lines(_ name: String) throws -> [String] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt",
                                                 subdirectory: "Fixtures/prompts"))
        var l = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }   // dosyanın son satır sonu
        return l
    }

    private func parse(_ name: String) throws -> ScreenPrompt? {
        let l = try lines(name)
        return PromptParser.parse(lines: l, cursorRow: l.count - 1)
    }

    @Test func bashPermission() throws {
        let p = try #require(try parse("bash-permission"))
        #expect(p.kind == .permission)
        #expect(p.title == "Do you want to proceed?")
        #expect(p.options.map(\.label) == [
            "Yes",
            "Yes, and always allow access to /private/tmp/claude-501/-Users-exampleuser-Downloads-Projeler-AjanTakip/68319abe-69fe-4efd-beff-a339819227c9/scratchpad/demo from this project",
            "Yes, and switch to auto mode · auto mode handles these prompts for you",
            "No",
        ])
        #expect(p.selected == 0)
        #expect(p.multi == false)
        #expect(p.page == nil)
        // 2.1.327'de izinde serbest metin seçeneği yok ("Tab to amend" ile yapılır).
        #expect(p.options.allSatisfy { !$0.freeText && $0.checked == nil })
        #expect(p.detail?.contains("touch out.txt") == true)
        #expect(p.detail?.contains("Tip:") == false)
    }

    @Test func dontAskVariant() throws {
        let p = try #require(try parse("bash-permission-dont-ask"))
        #expect(p.kind == .permission)
        #expect(p.options.count == 4)
        #expect(p.options[1].label == "Yes, and don’t ask again for: git add *")
        #expect(p.detail?.contains("git add notes.txt") == true)
    }

    @Test func editPermission() throws {
        let p = try #require(try parse("edit-permission"))
        #expect(p.kind == .permission)
        #expect(p.title == "Do you want to make this edit to notes.txt?")
        #expect(p.options.map(\.label) == [
            "Yes",
            "Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)",
            "No",
        ])
        #expect(p.detail?.contains("notes.txt") == true)
    }

    @Test func readOutsidePermission() throws {
        let p = try #require(try parse("read-outside-permission"))
        #expect(p.kind == .permission)
        #expect(p.options.count == 3)
        #expect(p.detail?.contains("Read(") == true)
    }

    @Test func askSingle() throws {
        let p = try #require(try parse("ask-single"))
        #expect(p.kind == .question)
        #expect(p.title == "Which color do you prefer?")
        #expect(p.multi == false)
        #expect(p.page == nil)
        #expect(p.selected == 0)
        #expect(p.options.map(\.label) == ["Red", "Blue", "Green", "Type something.", "Chat about this"])
        #expect(p.options.map(\.freeText) == [false, false, false, true, false])
        #expect(p.options.allSatisfy { $0.checked == nil })
    }

    @Test func askSingleTypedKeepsFreeText() throws {
        // Serbest metin satırına yazılınca etiket yazılan metin olur; yine de freeText kalır.
        let p = try #require(try parse("ask-single-typed"))
        #expect(p.options[3].label == "hello")
        #expect(p.options[3].freeText)
        #expect(p.selected == 3)
    }

    @Test func askMulti() throws {
        let p = try #require(try parse("ask-multi"))
        #expect(p.kind == .question)
        #expect(p.multi)
        #expect(p.title == "Which fruits do you like?")
        #expect(p.options.map(\.label) == ["Apple", "Banana", "Cherry", "Type something", "Chat about this"])
        #expect(p.options.map(\.checked) == [false, false, false, false, nil])
        #expect(p.options.map(\.freeText) == [false, false, false, true, false])
        // Tek sorulu çoklu seçimde şeritte yalnız bir soru var → sayfa yok.
        #expect(p.page == nil)
    }

    @Test func askMultiChecked() throws {
        let p = try #require(try parse("ask-multi-checked"))
        #expect(p.options.map(\.checked) == [true, false, true, false, nil])
        #expect(p.selected == 2)
    }

    @Test func multiStopsCountSubmitRow() throws {
        // Gerçek: Apple→Banana→Cherry→Type something→Submit = 4 kez ↓, bir ↓ daha "Chat about this".
        let p = try #require(try parse("ask-multi"))
        #expect(p.options.map(\.stop) == [0, 1, 2, 3, 5])
        #expect(p.submitStop == 4)
        // Çok sorulu çağrının 3. sayfası (çoklu): Apple, Banana, Type something, Submit, Chat about this.
        let q3 = try #require(try parse("ask-pages-q3"))
        #expect(q3.page?.index == 2 && q3.page?.count == 3)
        #expect(q3.options.map(\.stop) == [0, 1, 2, 4])
        #expect(q3.submitStop == 3)
    }

    @Test func singleStopsAreConsecutive() throws {
        // Gerçek: "Type something." satırından bir ↓ ayracı atlayıp "Chat about this"e gider (ask-single-below).
        let p = try #require(try parse("ask-single"))
        #expect(p.options.map(\.stop) == [0, 1, 2, 3, 4])
        #expect(p.submitStop == nil)
        let below = try #require(try parse("ask-single-below"))
        #expect(below.selected == 4 && below.options[4].label == "Chat about this")
        #expect(try parse("bash-permission")?.options.map(\.stop) == [0, 1, 2, 3])
        #expect(try parse("bash-permission")?.submitStop == nil)
    }

    @Test func multiWithoutSubmitRowIsNil() throws {
        var l = try lines("ask-multi")
        let i = try #require(l.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "Submit" })
        l.remove(at: i)
        #expect(PromptParser.parse(lines: l, cursorRow: 0) == nil)
    }

    @Test func questionTitledLikePermissionIsQuestion() throws {
        var l = try lines("ask-single")
        let i = try #require(l.firstIndex { $0 == "Which color do you prefer?" })
        l[i] = "Do you want to use Redis?"
        let p = try #require(PromptParser.parse(lines: l, cursorRow: 0))
        #expect(p.kind == .question)
        #expect(p.title == "Do you want to use Redis?")
        #expect(p.detail == nil)
        #expect(p.options[3].freeText)
    }

    @Test func cursorOnSubmitRowIsNil() throws {
        #expect(try parse("ask-multi-submit-row") == nil)
    }

    @Test func askPages() throws {
        let p = try #require(try parse("ask-pages"))
        #expect(p.kind == .question)
        #expect(p.page?.count == 3)
        #expect(p.page?.index == 0)
        #expect(p.title == "Which color do you prefer?")
        let q2 = try #require(try parse("ask-pages-q2"))
        #expect(q2.page?.index == 1 && q2.page?.count == 3)
        #expect(q2.options.map(\.label) == ["Small", "Large", "Type something.", "Chat about this"])
    }

    @Test func reviewPageIsNil() throws {
        // İpucu satırı yok → tanınmaz.
        #expect(try parse("ask-pages-review") == nil)
    }

    @Test func planApproval() throws {
        let p = try #require(try parse("plan-approval"))
        #expect(p.kind == .plan)
        #expect(p.options.count >= 2)
        // Plan gövdesindeki "1. Read notes.txt…" satırları menüye karışmaz.
        #expect(p.options.map(\.label) == ["Yes, and use auto mode", "Yes, manually approve edits",
                                           "Tell Claude what to change"])
        #expect(p.options.map(\.freeText) == [false, false, true])
        #expect(p.selected == 0)
    }

    @Test func idleIsNil() throws { #expect(try parse("idle-input") == nil) }
    @Test func partialMenuIsNil() throws { #expect(try parse("partial") == nil) }
    @Test func staleMenuAboveInputIsNil() throws { #expect(try parse("stale-above-input") == nil) }

    @Test func selectedFollowsCursor() throws {
        var l = try lines("bash-permission")
        let i = try #require(l.firstIndex { $0.contains("❯ 1. Yes") })
        l[i] = l[i].replacingOccurrences(of: "❯ 1.", with: "  1.")
        l[i + 1] = l[i + 1].replacingOccurrences(of: "  2.", with: "❯ 2.")
        #expect(PromptParser.parse(lines: l, cursorRow: 0)?.selected == 1)
        #expect(try parse("bash-permission-down")?.selected == 1)
    }

    @Test func brokenNumberingIsNil() throws {
        var l = try lines("bash-permission")
        let i = try #require(l.firstIndex { $0.contains("3. Yes, and switch") })
        l.remove(at: i)   // 1, 2, 4
        #expect(PromptParser.parse(lines: l, cursorRow: 0) == nil)
    }

    @Test func twoCursorsIsNil() throws {
        var l = try lines("bash-permission")
        let i = try #require(l.firstIndex { $0.contains("4. No") })
        l[i] = l[i].replacingOccurrences(of: "  4.", with: "❯ 4.")
        #expect(PromptParser.parse(lines: l, cursorRow: 0) == nil)
    }

    @Test func unknownTitleIsNil() throws {
        var l = try lines("bash-permission")
        let i = try #require(l.firstIndex { $0.contains("Do you want to proceed?") })
        l[i] = " Something new?"
        #expect(PromptParser.parse(lines: l, cursorRow: 0) == nil)
    }

    @Test func emptyIsNil() {
        #expect(PromptParser.parse(lines: [], cursorRow: 0) == nil)
    }
}
