import Foundation
import Testing
@testable import AtolyeCore

@Suite struct PromptKeysTests {
    private let up = "\u{1b}[A", down = "\u{1b}[B"

    private func screen(_ name: String) throws -> ScreenPrompt {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt",
                                                 subdirectory: "Fixtures/prompts"))
        var l = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }
        return try #require(PromptParser.parse(lines: l, cursorRow: l.count - 1))
    }

    /// Fikstürün satırlarında `from` → `to` değiştirilip ayrıştırılır (ör. sekme şeridini oynatmak için).
    private func screen(_ name: String, replacing from: String, with to: String) throws -> ScreenPrompt {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt",
                                                 subdirectory: "Fixtures/prompts"))
        var l = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: from, with: to)
            .components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }
        return try #require(PromptParser.parse(lines: l, cursorRow: l.count - 1))
    }

    private func str(_ d: Data?) -> String? { d.flatMap { String(data: $0, encoding: .utf8) } }

    private func ans(_ s: ScreenPrompt, option: Int? = nil, checks: [Int] = [], text: String? = nil) -> PromptAnswer {
        PromptAnswer(option: option, checks: checks, text: text, labels: s.options.map(\.label), menuId: s.menuId)
    }

    @Test func downTwiceThenEnter() throws {
        let s = try screen("bash-permission")
        #expect(str(PromptKeys.keys(for: ans(s, option: 2), on: s)) == down + down + "\r")
    }

    @Test func upOnce() throws {
        let s = try screen("bash-permission-down")   // selected 1
        #expect(str(PromptKeys.keys(for: ans(s, option: 0), on: s)) == up + "\r")
    }

    @Test func sameOptionJustEnter() throws {
        let s = try screen("bash-permission")
        #expect(str(PromptKeys.keys(for: ans(s, option: 0), on: s)) == "\r")
    }

    @Test func nilWhenLabelsDiffer() throws {
        let s = try screen("bash-permission")
        var a = ans(s, option: 1); a.labels[0] = "Başka"
        #expect(PromptKeys.keys(for: a, on: s) == nil)
        #expect(PromptKeys.keys(for: ans(s, option: 1), on: nil) == nil)
    }

    @Test func nilWhenOptionOutOfRange() throws {
        let s = try screen("bash-permission")
        #expect(PromptKeys.keys(for: ans(s, option: 9), on: s) == nil)
        #expect(PromptKeys.keys(for: ans(s, option: -1), on: s) == nil)
        #expect(PromptKeys.keys(for: ans(s), on: s) == nil)   // option yok
    }

    @Test func singleStopsSkipSeparator() throws {
        // ask-single-below: imleç 5. seçenekte (stop ayracı atlar); 1. seçeneğe gitmek stop farkı kadar ↑
        let s = try screen("ask-single-below")
        let target = s.options[0].stop, from = s.options[s.selected].stop
        #expect(str(PromptKeys.keys(for: ans(s, option: 0), on: s))
                == String(repeating: up, count: from - target) + "\r")
    }

    @Test func mismatchedKindIsNil() throws {
        let single = try screen("ask-single")
        #expect(PromptKeys.keys(for: ans(single, checks: [0]), on: single) == nil)
        let multi = try screen("ask-multi")
        #expect(PromptKeys.keys(for: ans(multi, option: 0), on: multi) == nil)
    }

    @Test func freeTextTypesAndSubmits() throws {
        let s = try screen("ask-single")
        let i = try #require(s.options.firstIndex(where: { $0.freeText }))
        let n = s.options[i].stop - s.options[s.selected].stop
        #expect(str(PromptKeys.keys(for: ans(s, option: i, text: "hello"), on: s))
                == String(repeating: down, count: n) + "hello\r")
    }

    @Test func freeTextOnNonFreeTextOptionIsNil() throws {
        let s = try screen("bash-permission")
        #expect(PromptKeys.keys(for: ans(s, option: 0, text: "x"), on: s) == nil)
    }

    @Test func emptySanitizedTextIsNil() throws {
        let s = try screen("ask-single")
        let i = try #require(s.options.firstIndex(where: { $0.freeText }))
        #expect(PromptKeys.keys(for: ans(s, option: i, text: "\u{1b}[A"), on: s) == nil)
        #expect(PromptKeys.keys(for: ans(s, option: i, text: ""), on: s) == nil)
    }

    // Kural: ESC [ … son bayt dizisi atılır (boşluk bırakmaz); \n ve \t boşluğa döner.
    // "a\nb" + ESC[A + "c\t" → "a b" + "c " = "a bc "
    @Test func freeTextStripsControlCharacters() {
        #expect(PromptKeys.sanitize("a\nb\u{1b}[Ac\t") == "a bc ")
        #expect(PromptKeys.sanitize("x\u{1b}Oy") == "xy")          // ESC + tek karakter
        #expect(PromptKeys.sanitize("a\u{7f}b\r") == "a b ")        // DEL, CR
        #expect(PromptKeys.sanitize("Merhaba şğ") == "Merhaba şğ")
    }

    @Test func multiChecks() throws {
        let s = try screen("ask-multi")   // imleç 1'de, hiçbiri işaretli değil
        let submit = try #require(s.submitStop)
        let a = s.options[0].stop, c = s.options[2].stop
        let expected = " " + String(repeating: down, count: c - a) + " "
            + String(repeating: down, count: submit - c) + "\r\r"
        #expect(str(PromptKeys.keys(for: ans(s, checks: [0, 2]), on: s)) == expected)
    }

    @Test func multiVerifiedReadmeSequence() throws {
        // README: 1. seçeneği işaretle + ↓×4 (Submit) + Enter + Enter
        let s = try screen("ask-multi")
        #expect(str(PromptKeys.keys(for: ans(s, checks: [0]), on: s))
                == " " + String(repeating: down, count: 4) + "\r\r")
    }

    @Test func multiTogglesOnlyDifferences() throws {
        // ask-multi-checked: 1. ve 3. işaretli, imleç 3'te. Hedef {0}: yalnız 3. kapanır, 1. dokunulmaz.
        let s = try screen("ask-multi-checked")
        #expect(s.options[0].checked == true && s.options[2].checked == true && s.selected == 2)
        let submit = try #require(s.submitStop)
        let c = s.options[2].stop
        #expect(str(PromptKeys.keys(for: ans(s, checks: [0]), on: s))
                == " " + String(repeating: down, count: submit - c) + "\r\r")
    }

    @Test func multiFreeTextTypesWithoutSpace() throws {
        let s = try screen("ask-multi")
        let i = try #require(s.options.firstIndex(where: { $0.freeText }))
        let submit = try #require(s.submitStop)
        let start = s.options[s.selected].stop, t = s.options[i].stop
        #expect(str(PromptKeys.keys(for: ans(s, checks: [i], text: "kiwi"), on: s))
                == String(repeating: down, count: t - start) + "kiwi"
                + String(repeating: down, count: submit - t) + "\r\r")
    }

    @Test func multiWithoutSubmitStopIsNil() throws {
        var s = try screen("ask-multi")
        s.submitStop = nil
        #expect(PromptKeys.keys(for: ans(s, checks: [0]), on: s) == nil)
    }

    @Test func prefilledFreeTextRowRejectsNewText() throws {
        let s = try screen("ask-single-typed")   // serbest satırın etiketi "hello"
        let i = try #require(s.options.firstIndex(where: { $0.freeText }))
        #expect(s.options[i].label == "hello")
        #expect(PromptKeys.keys(for: ans(s, option: i, text: "x"), on: s) == nil)
        // Yeni metinsiz seçim serbest: ekrandakini gönderir.
        #expect(PromptKeys.keys(for: ans(s, option: i), on: s) != nil)
    }

    @Test func prefilledMultiFreeTextRowRejectsNewText() throws {
        var s = try screen("ask-multi")
        let i = try #require(s.options.firstIndex(where: { $0.freeText }))
        s.options[i].label = "kiwi"; s.options[i].checked = true
        #expect(PromptKeys.keys(for: ans(s, checks: [i], text: "x"), on: s) == nil)
    }

    // Bulgu 1: plan menüsünde "Tell Claude what to change" sıradan seçenektir; metin yazmak doğrulanmadı
    // (harfler plan menüsünün kısayollarına gidebilir). Metinli cevap reddedilir, metinsiz seçim + Enter.
    @Test func planFreeTextRowAcceptsNoText() throws {
        let s = try screen("plan-approval")
        let i = try #require(s.options.firstIndex(where: { $0.label == "Tell Claude what to change" }))
        #expect(PromptKeys.keys(for: ans(s, option: i, text: "daha kısa"), on: s) == nil)
        let n = s.options[i].stop - s.options[s.selected].stop
        #expect(str(PromptKeys.keys(for: ans(s, option: i), on: s)) == String(repeating: down, count: n) + "\r")
    }

    @Test func permissionFreeTextRowAcceptsNoText() {
        // Eski sürümlerin "No, and tell Claude …" seçeneği: izinlerde metin yazma doğrulanmadı.
        let s = ScreenPrompt(kind: .permission, title: "Do you want to proceed?", detail: "ls",
                             options: [ScreenOption(label: "Yes", stop: 0),
                                       ScreenOption(label: "No, and tell Claude what to do differently", freeText: true, stop: 1)],
                             selected: 0, multi: false, page: nil)
        #expect(PromptKeys.keys(for: ans(s, option: 1, text: "x"), on: s) == nil)
    }

    // Bulgu 2: çoklu seçimde kutusuz satır ("Chat about this") işaretlenemez; boş serbest satır metinsiz işaretlenemez.
    @Test func multiRejectsRowWithoutCheckbox() throws {
        let s = try screen("ask-multi")
        let chat = try #require(s.options.firstIndex(where: { $0.label == "Chat about this" }))
        #expect(s.options[chat].checked == nil)
        #expect(PromptKeys.keys(for: ans(s, checks: [chat]), on: s) == nil)
        #expect(PromptKeys.keys(for: ans(s, checks: [0, chat]), on: s) == nil)
    }

    @Test func multiRejectsPlaceholderFreeRowWithoutText() throws {
        let s = try screen("ask-multi")
        let i = try #require(s.options.firstIndex(where: { $0.freeText }))
        #expect(PromptKeys.keys(for: ans(s, checks: [i]), on: s) == nil)
        #expect(PromptKeys.keys(for: ans(s, checks: [0, i]), on: s) == nil)
    }

    // Bulgu 3: çok sorulu çağrıda inceleme sayfası yalnız son cevapsız sorudan sonra gelir.
    @Test func multiOnLastPageSubmitsAndConfirms() throws {
        let s = try screen("ask-pages-q3")   // ☒ Color ☒ Size ☐ Fruits
        #expect(s.finalPage)
        let submit = try #require(s.submitStop)
        #expect(str(PromptKeys.keys(for: ans(s, checks: [0]), on: s))
                == " " + String(repeating: down, count: submit - s.options[0].stop) + "\r\r")
    }

    @Test func multiOnEarlierPageSubmitsOnce() throws {
        // Başka cevapsız sekme var: Submit sonraki soruya geçer; ikinci Enter onu körlemesine cevaplardı.
        let s = try screen("ask-pages-q3", replacing: "☒", with: "☐")
        #expect(!s.finalPage && s.page?.index == 0)
        let submit = try #require(s.submitStop)
        #expect(str(PromptKeys.keys(for: ans(s, checks: [0]), on: s))
                == " " + String(repeating: down, count: submit - s.options[0].stop) + "\r")
    }

    // Bulgu 4: cevap gösterilen menünün kimliğini taşır; aynı etiketli başka bir menüye gitmez.
    @Test func nilWhenMenuIdDiffers() throws {
        let s = try screen("bash-permission")
        var a = ans(s, option: 0); a.menuId = "başka"
        #expect(PromptKeys.keys(for: a, on: s) == nil)
        var other = s; other.detail = (s.detail ?? "") + " --force"
        #expect(PromptKeys.keys(for: ans(s, option: 0), on: other) == nil)
    }
}
