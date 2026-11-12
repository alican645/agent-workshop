import CoreGraphics

public enum PanelGeometry {
    /// Yeni içerik boyutu için panel çerçevesi: üst-sol sabit (aşağı/sağa büyür),
    /// ama görünür alandan taşarsa sola/yukarı kaydırılır.
    public static func fitted(current: CGRect, size: CGSize, visible: CGRect) -> CGRect {
        var r = CGRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
        if r.maxX > visible.maxX { r.origin.x = visible.maxX - r.width }
        if r.minX < visible.minX { r.origin.x = visible.minX }
        if r.minY < visible.minY { r.origin.y = visible.minY }
        if r.maxY > visible.maxY { r.origin.y = visible.maxY - r.height }
        return r
    }
}
