import Foundation
import SwiftTerm

/// Başsız bir terminal: PTY çıktısını işleyip ekranda şu an GÖRÜNEN metni verir (renksiz, sağ boşluksuz).
/// Claude'un seçenek menülerini okumak için; çizim yok, yalnız SwiftTerm'in durum makinesi.
/// Tüm çağrılar tek bir kuyruktan (sunucunun seri kuyruğu) gelmelidir.
public final class ScreenMirror {
    private let delegate: ReplyDelegate
    private let terminal: Terminal

    /// `onReply`: terminalin sorgulara verdiği cevaplar (imleç konumu, cihaz özellikleri…).
    /// Host'ta nil kalır — oradaki gerçek TerminalView zaten cevaplar; yalnız tek başına çalışan
    /// yakalama aracı bunları sürece geri iletir (yoksa Claude cevap bekleyip farklı çizebilir).
    public init(cols: Int, rows: Int, onReply: ((ArraySlice<UInt8>) -> Void)? = nil) {
        delegate = ReplyDelegate(onReply)
        terminal = Terminal(delegate: delegate,
                            options: TerminalOptions(cols: max(cols, 1), rows: max(rows, 1), scrollback: 0))
    }

    public func feed(_ d: Data) { terminal.feed(buffer: ArraySlice([UInt8](d))) }

    public func resize(cols: Int, rows: Int) { terminal.resize(cols: max(cols, 1), rows: max(rows, 1)) }

    /// Görünen satırlar, yukarıdan aşağı; her birinin sağındaki boşluklar kırpılmıştır.
    /// İmleç atlamasıyla (ör. `ESC [12G`) hiç yazılmamış hücreler NUL değil boşluk olarak gelir —
    /// Claude ekranı böyle çizer; NUL kalsa metin eşleşmeleri bozulur.
    public func lines() -> [String] {
        (0..<terminal.rows).map { row in
            let s = terminal.getLine(row: row)?.translateToString(trimRight: true, skipNullCellsFollowingWide: true) ?? ""
            var out = s.replacingOccurrences(of: "\u{0}", with: " ")
            while out.last?.isWhitespace == true { out.removeLast() }
            return out
        }
    }

    /// İmlecin görünen ekrandaki satırı (0 tabanlı).
    public var cursorRow: Int { terminal.getCursorLocation().y }
}

/// Terminalin cevapları (`send`): `onReply` verilmişse ona gider, yoksa yok sayılır.
private final class ReplyDelegate: TerminalDelegate {
    let onReply: ((ArraySlice<UInt8>) -> Void)?
    init(_ onReply: ((ArraySlice<UInt8>) -> Void)?) { self.onReply = onReply }
    func send(source: Terminal, data: ArraySlice<UInt8>) { onReply?(data) }
}
