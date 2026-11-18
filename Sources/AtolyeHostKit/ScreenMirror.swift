import Foundation
import SwiftTerm

/// Başsız bir terminal: PTY çıktısını işleyip ekranda şu an GÖRÜNEN metni verir (renksiz, sağ boşluksuz).
/// Claude'un seçenek menülerini okumak için; çizim yok, yalnız SwiftTerm'in durum makinesi.
/// Tüm çağrılar tek bir kuyruktan (sunucunun seri kuyruğu) gelmelidir.
public final class ScreenMirror {
    private let delegate = NullDelegate()
    private let terminal: Terminal

    public init(cols: Int, rows: Int) {
        terminal = Terminal(delegate: delegate,
                            options: TerminalOptions(cols: max(cols, 1), rows: max(rows, 1), scrollback: 0))
    }

    public func feed(_ d: Data) { terminal.feed(buffer: ArraySlice([UInt8](d))) }

    public func resize(cols: Int, rows: Int) { terminal.resize(cols: max(cols, 1), rows: max(rows, 1)) }

    /// Görünen satırlar, yukarıdan aşağı; her birinin sağındaki boşluklar kırpılmıştır.
    public func lines() -> [String] {
        (0..<terminal.rows).map { terminal.getLine(row: $0)?.translateToString(trimRight: true) ?? "" }
    }

    /// İmlecin görünen ekrandaki satırı (0 tabanlı).
    public var cursorRow: Int { terminal.getCursorLocation().y }
}

/// Mirror'ın dışarıya söyleyeceği bir şey yok; `send` (terminalin cevapları) yok sayılır.
private final class NullDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
