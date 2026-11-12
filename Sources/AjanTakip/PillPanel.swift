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

    /// İçerik boyutuna uyar; üst kenarı sabit tutar (aşağı doğru büyür).
    func fit(contentSize size: CGSize) {
        let w = ceil(size.width), h = ceil(size.height)
        guard w > 0, h > 0, w != frame.width || h != frame.height else { return }
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        setFrame(PanelGeometry.fitted(current: frame, size: CGSize(width: w, height: h), visible: visible),
                 display: true)
    }

    /// Sürükleme: ekran koordinatlarında üst-sol noktayı taşır.
    func move(topLeft: NSPoint) {
        setFrameTopLeftPoint(topLeft)
        clampToScreen()
        UserDefaults.standard.set([frame.minX, frame.maxY], forKey: Self.originKey)
    }

    var topLeft: NSPoint { NSPoint(x: frame.minX, y: frame.maxY) }

    private func restorePosition() {
        if let saved = UserDefaults.standard.array(forKey: Self.originKey) as? [Double], saved.count == 2 {
            setFrameTopLeftPoint(NSPoint(x: saved[0], y: saved[1]))
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            setFrameTopLeftPoint(NSPoint(x: v.maxX - frame.width - Self.margin, y: v.maxY - Self.margin))
        }
        clampToScreen()
    }

    @objc private func screensChanged() { clampToScreen() }

    /// Hap hiçbir ekranın görünür alanında değilse en yakın ekrana geri çeker.
    func clampToScreen() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        if screens.contains(where: { $0.visibleFrame.contains(NSPoint(x: frame.midX, y: frame.maxY - 1)) }) {
            return
        }
        let target = screens.min { distance($0.visibleFrame) < distance($1.visibleFrame) } ?? screens[0]
        let v = target.visibleFrame
        let x = min(max(frame.minX, v.minX + Self.margin), v.maxX - frame.width - Self.margin)
        let y = min(max(frame.maxY, v.minY + frame.height + Self.margin), v.maxY - Self.margin)
        setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    private func distance(_ r: NSRect) -> CGFloat {
        hypot(r.midX - frame.midX, r.midY - frame.midY)
    }
}

/// Odakta olmayan panelde ilk tıklamanın da SwiftUI'a ulaşmasını sağlar.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
