import AppKit
import SwiftTerm
import SwiftUI

/// Bir terminalin görünümünü (HostConnection'da yaşayan) bu bölmeye yerleştirir.
struct TerminalPane: NSViewRepresentable {
    let host: HostConnection
    let id: String
    let focused: Bool

    func makeNSView(context: Context) -> NSView {
        let c = NSView()
        c.wantsLayer = true
        return c
    }

    func updateNSView(_ c: NSView, context: Context) {
        let v = host.view(for: id)
        if v.superview !== c {
            c.subviews.forEach { $0.removeFromSuperview() }
            v.removeFromSuperview()
            v.frame = c.bounds
            v.autoresizingMask = [.width, .height]
            c.addSubview(v)
        }
        if focused, v.window?.firstResponder !== v {
            DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        }
    }
}
