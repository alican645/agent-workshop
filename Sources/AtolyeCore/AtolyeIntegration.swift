import Foundation

/// Atölye'nin Claude kurulumuna eklediği parçalar.
public enum AtolyeIntegration {
    public static let begin = "# >>> atolye >>>"
    public static let end = "# <<< atolye <<<"

    /// statusline betiğinin sonuna: `rate_limits`'i profil başına bir dosyaya yazar (Atölye çalışmasa da).
    public static let statuslineBlock = """
        \(begin)
        ( _d="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _o="$HOME/Library/Application Support/Atolye/limits"
          _r=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
          if [ -n "$_r" ]; then
            mkdir -p "$_o" && _f="$_o/$(printf '%s' "${_d%/}" | tr '/ ' '__').json" \\
              && printf '%s' "$_r" > "$_f.$$" && mv -f "$_f.$$" "$_f"
          fi ) >/dev/null 2>&1
        \(end)

        """

    static func removeBlock(_ text: String, begin: String, end: String) -> String {
        guard let b = text.range(of: begin), let e = text.range(of: end, range: b.upperBound..<text.endIndex) else { return text }
        var upper = e.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        var t = text.replacingCharacters(in: b.lowerBound..<upper, with: "")
        while t.hasSuffix("\n\n") { t.removeLast() }
        return t
    }

    /// Atölye bloğunu (eskisinin yerine) sona ekler.
    public static func installStatusline(into text: String) -> String {
        var t = removeBlock(text, begin: begin, end: end)
        if !t.isEmpty && !t.hasSuffix("\n") { t += "\n" }
        return t + "\n" + statuslineBlock
    }

    public static func limitFileName(configDir: String) -> String {
        var d = configDir
        while d.count > 1 && d.hasSuffix("/") { d.removeLast() }
        return d.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_") + ".json"
    }

    public static func readLimits(path: String) -> AccountUsage? {
        guard let data = FileManager.default.contents(atPath: path),
              let mtime = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return nil }
        return UsageReport.parse(body: data, headers: [:], now: mtime)?.usage
    }

    /// Profilde hesaba giriş: tarayıcıda giriş sayfası beklenen e-posta dolu açılır.
    public static func loginCommand(email: String?) -> String {
        guard let email, !email.isEmpty else { return "claude auth login" }
        return "claude auth login --email '" + email.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Profilin girişli hesabı (`.claude.json` → oauthAccount.emailAddress).
    public static func loggedInEmail(globalConfig path: String) -> String? {
        guard let d = FileManager.default.contents(atPath: path),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return (o["oauthAccount"] as? [String: Any])?["emailAddress"] as? String
    }
}
