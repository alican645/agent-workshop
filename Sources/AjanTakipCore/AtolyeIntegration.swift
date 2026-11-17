import Foundation

/// Atölye'nin Claude kurulumuna eklediği parçalar ve AjanTakip'ten kalanların temizliği.
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

    /// AjanTakip'in HTTP bloğunu kaldırır, Atölye bloğunu (yoksa) sona ekler.
    public static func installStatusline(into text: String) -> String {
        var t = removeBlock(text, begin: ShellSnippet.begin, end: ShellSnippet.end)
        t = removeBlock(t, begin: begin, end: end)
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

    /// settings.json'dan AjanTakip kancalarını çıkarır; değişiklik yoksa `nil`.
    public static func removingAjanTakipHooks(_ data: Data) -> Data? {
        guard var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = obj["hooks"] as? [String: Any] else { return nil }
        var changed = false
        for (event, raw) in hooks {
            guard let groups = raw as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for var g in groups {
                let hs = (g["hooks"] as? [[String: Any]]) ?? []
                let left = hs.filter { !(($0["command"] as? String) ?? "").contains("ajantakip-hook") }
                if left.count != hs.count { changed = true }
                if left.isEmpty && !hs.isEmpty { continue }
                g["hooks"] = left
                kept.append(g)
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        guard changed else { return nil }
        obj["hooks"] = hooks.isEmpty ? nil : hooks
        return try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// `.zshrc`'den AjanTakip bloğunu çıkarır; yoksa `nil`.
    public static func removingAjanTakipZsh(_ text: String) -> String? {
        ShellSnippet.contains(in: text) ? ShellSnippet.remove(from: text) : nil
    }

    /// Profilin girişli hesabı (`.claude.json` → oauthAccount.emailAddress).
    public static func loggedInEmail(globalConfig path: String) -> String? {
        guard let d = FileManager.default.contents(atPath: path),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return (o["oauthAccount"] as? [String: Any])?["emailAddress"] as? String
    }
}
