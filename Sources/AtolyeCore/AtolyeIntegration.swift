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

    /// Atölye bloğunu statusline betiğinden çıkarır.
    public static func uninstallStatusline(from text: String) -> String {
        removeBlock(text, begin: begin, end: end)
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

    // MARK: Claude Code hook'ları

    /// Hook'un dinlediği olaylar. PermissionRequest cevabı bekler (terminaldeki menü de açık kalır); uzun
    /// süre beklenebilsin diye zaman aşımı bir gün. Diğerleri yalnız haber verir.
    static let hookEvents: [(event: String, timeout: Int?)] = [
        ("PermissionRequest", 86400), ("PostToolUse", nil), ("PostToolUseFailure", nil),
    ]

    /// settings.json'a Atölye hook'larını ekler (eskisinin yerine). Kullanıcının hook'larına dokunmaz;
    /// Atölye'ninkiler komutta `atolye-hook` geçmesinden tanınır. JSON okunamazsa nil (dosyaya dokunulmaz).
    public static func installHooks(into text: String, executable: String) -> String? {
        let src = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : text
        guard var root = (try? JSONSerialization.jsonObject(with: Data(src.utf8))) as? [String: Any] else { return nil }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        if root["hooks"] != nil, root["hooks"] as? [String: Any] == nil { return nil }
        hooks = removeAtolyeHooks(hooks)
        let command = "\"" + executable.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        for (event, timeout) in hookEvents {
            var handler: [String: Any] = ["type": "command", "command": command]
            if let timeout { handler["timeout"] = timeout }
            var groups = hooks[event] as? [Any] ?? []
            groups.append(["matcher": "*", "hooks": [handler]] as [String: Any])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return serialize(root)
    }

    /// Atölye hook'larını çıkarır (ayarlarda kalan başka bir şey değişmez).
    public static func uninstallHooks(from text: String) -> String? {
        guard var root = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return nil }
        guard let hooks = root["hooks"] as? [String: Any] else { return text }
        let left = removeAtolyeHooks(hooks)
        if left.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = left }
        return serialize(root)
    }

    static func removeAtolyeHooks(_ hooks: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { out[event] = value; continue }
            let kept: [Any] = groups.compactMap { g in
                guard var group = g as? [String: Any], let hs = group["hooks"] as? [Any] else { return g }
                let rest = hs.filter { h in !(((h as? [String: Any])?["command"] as? String)?.contains("atolye-hook") ?? false) }
                if rest.isEmpty { return nil }
                group["hooks"] = rest
                return group
            }
            if !kept.isEmpty { out[event] = kept }
        }
        return out
    }

    private static func serialize(_ root: [String: Any]) -> String? {
        guard let d = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: d, as: UTF8.self) + "\n"
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
