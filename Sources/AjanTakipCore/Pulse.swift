public enum Pulse {
    /// Kenarlık nabzının bir sonraki durumu.
    /// Yeni uyarı (liste kapalıysa) nabzı başlatır; bekleyen oturum kalmayınca turuncu nabız söner;
    /// yeşil nabız liste açılana kadar kalır.
    public static func next(current: AlertKind?, alert: AlertKind?, waitingCount: Int, expanded: Bool) -> AlertKind? {
        if expanded { return nil }
        if let alert { return alert }
        if current == .attention, waitingCount == 0 { return nil }
        return current
    }
}
