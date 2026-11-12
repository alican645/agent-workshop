import AjanTakipCore
import AppKit
import SwiftUI

/// CPU/RAM ayrıntısını gösteren, haptan bağımsız yüzen pencere.
final class DetailPanel: NSPanel {
    /// true ise boyut değişiminde sağ kenar sabit kalır (hap sağdayken pencere solunda açılır).
    private var anchorRight = false

    init<Content: View>(rootView: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        let host = FirstMouseHostingView(rootView: rootView)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var visibleFrame: NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let s = NSScreen.screens.first { $0.frame.contains(center) } ?? screen ?? NSScreen.main
        return s?.visibleFrame ?? .infinite
    }

    /// Hap penceresinin yanına yerleşir: hap sağ kenardaysa soluna, sol kenardaysa sağına.
    func place(nextTo pill: NSRect, pillEdge: PanelGeometry.Edge) {
        anchorRight = pillEdge == .right
        let gap: CGFloat = 8
        let x = anchorRight ? pill.minX - gap - frame.width : pill.maxX + gap
        setFrame(NSRect(x: x, y: pill.maxY - frame.height, width: frame.width, height: frame.height), display: true)
    }

    func fit(contentSize size: CGSize) {
        let w = ceil(size.width), h = ceil(size.height)
        guard w > 0, h > 0, w != frame.width || h != frame.height else { return }
        setFrame(PanelGeometry.fitted(current: frame, size: CGSize(width: w, height: h), visible: visibleFrame,
                                      edge: anchorRight ? .right : .left),
                 display: true)
    }

    func move(topLeft: NSPoint) { setFrameTopLeftPoint(topLeft) }
    var topLeft: NSPoint { NSPoint(x: frame.minX, y: frame.maxY) }
}
