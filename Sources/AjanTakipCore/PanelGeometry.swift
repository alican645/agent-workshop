import CoreGraphics

public enum PanelGeometry {
    public enum Edge: String, Sendable {
        case left, right
    }

    /// Hapın ekran kenarından boşluğu.
    public static let edgeMargin: CGFloat = 8

    /// Yeni içerik boyutu için panel çerçevesi: üst kenar sabit (aşağı büyür).
    /// Sağ kenara yaslıysa sağ kenar sabit kalır (sola büyür), değilse sol kenar.
    /// Görünür alandan taşarsa içeri kaydırılır.
    public static func fitted(current: CGRect, size: CGSize, visible: CGRect, edge: Edge? = nil) -> CGRect {
        let x = edge == .right ? current.maxX - size.width : current.minX
        let r = CGRect(x: x, y: current.maxY - size.height, width: size.width, height: size.height)
        return clamped(r, in: visible)
    }

    /// Çerçevenin merkezine en yakın yatay kenar.
    public static func nearestEdge(of frame: CGRect, in visible: CGRect) -> Edge {
        frame.midX < visible.midX ? .left : .right
    }

    /// Dikey konumu koruyarak çerçeveyi verilen kenara yaslar.
    public static func snapped(_ frame: CGRect, to edge: Edge, in visible: CGRect) -> CGRect {
        var r = frame
        r.origin.x = edge == .left ? visible.minX + edgeMargin : visible.maxX - edgeMargin - r.width
        return clamped(r, in: visible)
    }

    private static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var r = frame
        if r.maxX > visible.maxX { r.origin.x = visible.maxX - r.width }
        if r.minX < visible.minX { r.origin.x = visible.minX }
        if r.minY < visible.minY { r.origin.y = visible.minY }
        if r.maxY > visible.maxY { r.origin.y = visible.maxY - r.height }
        return r
    }
}
