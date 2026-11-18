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

    @Test func linesCoverVisibleRowsAndCursor() {
        let m = mirror("a\r\nb")
        #expect(m.lines().count == 24)
        #expect(m.cursorRow == 1)
        m.resize(cols: 100, rows: 10)
        #expect(m.lines().count == 10)
    }
}
