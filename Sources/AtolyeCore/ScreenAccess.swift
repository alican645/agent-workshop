/// Atölye terminalinin ekranı bir Claude oturumu adına okunup ona tuş gönderilebilir mi.
public enum ScreenAccess {
    /// `claimants`: ortamında bu terminalin kimliği (`ATOLYE_TERMINAL_ID`) olan canlı oturum sayısı.
    /// Claude terminali her zaman; kabuk terminali yalnız içinde tek bir Claude çalışıyorsa (zsh'te `claude`
    /// yazılmış). İki oturum aynı kabuğu sahiplenirse ekrandaki menünün hangisine ait olduğu bilinmez.
    public static func readable(kind: TerminalKind?, claimants: Int) -> Bool {
        switch kind {
        case .claude: true
        case .shell: claimants == 1
        case nil: false
        }
    }
}
