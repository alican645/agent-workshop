import Foundation
import Testing
@testable import AtolyeHostKit

@Suite struct ScreenMirrorTests {
    private func mirror(_ s: String...) -> ScreenMirror {
        let m = ScreenMirror(cols: 80, rows: 24)
        for x in s { m.feed(Data(x.utf8)) }
        return m
    }

    @Test func plainText() {
        #expect(mirror("hello\r\nworld").lines().prefix(2) == ["hello", "world"])
    }

    @Test func colorsStripped() {
        #expect(mirror("\u{1b}[31mred\u{1b}[0m").lines()[0] == "red")
    }

    @Test func clearScreen() {
        let m = mirror("a\r\nb", "\u{1b}[2J\u{1b}[H❯ 1. Yes")
        #expect(m.lines()[0] == "❯ 1. Yes")
        #expect(m.lines()[1] == "")
    }

    @Test func skippedCellsBecomeSpaces() {
        // Claude kelimeleri imleç atlamasıyla yerleştirir; aradaki hücreler hiç yazılmaz.
        // Sondaki boyalı boşluklar da kırpılır.
        #expect(mirror("Do\u{1b}[4Gyou\u{1b}[44m   \u{1b}[0m").lines()[0] == "Do you")
        #expect(mirror("❯\u{1b}[3G1. Yes").lines()[0] == "❯ 1. Yes")
        #expect(mirror("界\u{1b}[4Gx").lines()[0] == "界 x")
    }

    @Test func repliesGoToCallbackWhenGiven() {
        var got: [UInt8] = []
        let m = ScreenMirror(cols: 80, rows: 24, onReply: { got += $0 })
        m.feed(Data("ab\u{1b}[6n".utf8))   // imleç konumu sorusu
        #expect(String(decoding: got, as: UTF8.self) == "\u{1b}[1;3R")
        ScreenMirror(cols: 80, rows: 24).feed(Data("\u{1b}[6n".utf8))   // cevapsız: çökmez
    }

    @Test func linesCoverVisibleRowsAndCursor() {
        let m = mirror("a\r\nb")
        #expect(m.lines().count == 24)
        #expect(m.cursorRow == 1)
        m.resize(cols: 100, rows: 10)
        #expect(m.lines().count == 10)
    }
}
