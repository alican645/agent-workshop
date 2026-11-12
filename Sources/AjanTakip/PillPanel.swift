import AjanTakipCore
import AppKit
import SwiftUI

/// Her şeyin üstünde duran, çerçevesiz, odak çalmayan hap paneli.
final class PillPanel: NSPanel {
    private static let originKey = "pillOrigin"
    private static let margin: CGFloat = 16

    init<Content: View>(rootView: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 28),
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

        restorePosition()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Yalnızca liste açıkken (Esc için) key olur; aksi hâlde klavye odağını çalmaz.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    private static let edgeKey = "pillEdge"

    /// Hapın yaslı olduğu yatay kenar.
    private(set) var edge: PanelGeometry.Edge =
        PanelGeometry.Edge(rawValue: UserDefaults.standard.string(forKey: "pillEdge") ?? "") ?? .right

    private var visibleFrame: NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let s = NSScreen.screens.first { $0.frame.contains(center) } ?? screen ?? NSScreen.main
        return s?.visibleFrame ?? .infinite
    }

    /// Boyut kim tarafından değişirse değişsin (AppKit dahil) sağa yaslıyken sağ kenarı korur.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var r = frameRect
        if edge == .right, r.size.width != frame.width, abs(r.minX - frame.minX) < 0.5, frame.width > 0 {
            r.origin.x = frame.maxX - r.width
        }
        super.setFrame(r, display: flag)
    }

    /// İçerik boyutuna uyar; üst kenar ve yaslı olunan yan kenar sabit kalır.
    func fit(contentSize size: CGSize) {
        let w = ceil(size.width), h = ceil(size.height)
        guard w > 0, h > 0, w != frame.width || h != frame.height else { return }
        setFrame(PanelGeometry.fitted(current: frame, size: CGSize(width: w, height: h),
                                      visible: visibleFrame, edge: edge),
                 display: true)
    }

    /// Sürükleme sırasında: üst-sol noktayı serbestçe taşır.
    func move(topLeft: NSPoint) {
        setFrameTopLeftPoint(topLeft)
    }

    /// Sürükleme bitince: en yakın sol/sağ kenara yaslanır (dikey konum korunur) ve kaydedilir.
    func snapToNearestEdge(animated: Bool = true) {
        let visible = visibleFrame
        edge = PanelGeometry.nearestEdge(of: frame, in: visible)
        let target = PanelGeometry.snapped(frame, to: edge, in: visible)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true)
        }
        UserDefaults.standard.set(edge.rawValue, forKey: Self.edgeKey)
        UserDefaults.standard.set(Double(target.maxY), forKey: Self.originKey)
    }

    var topLeft: NSPoint { NSPoint(x: frame.minX, y: frame.maxY) }

    private func restorePosition() {
        let v = NSScreen.main?.visibleFrame ?? .zero
        let top = UserDefaults.standard.object(forKey: Self.originKey) as? Double ?? Double(v.maxY - Self.margin)
        setFrameTopLeftPoint(NSPoint(x: edge == .left ? v.minX : v.maxX - frame.width, y: top))
        snapToNearestEdge(animated: false)
    }

    @objc private func screensChanged() { snapToNearestEdge(animated: false) }

}

/// Odakta olmayan panelde ilk tıklamanın da SwiftUI'a ulaşmasını sağlar.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
