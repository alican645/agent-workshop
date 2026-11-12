import Foundation

/// `claude auth status --json` çıktısından yalnızca gereken alanlar.
public struct AuthStatus: Equatable, Sendable {
    public var loggedIn: Bool
    public var email: String?
    public var plan: String?

    public init(loggedIn: Bool, email: String?, plan: String?) {
        self.loggedIn = loggedIn; self.email = email; self.plan = plan
    }

    public static func parse(_ data: Data) -> AuthStatus? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return AuthStatus(loggedIn: o["loggedIn"] as? Bool ?? false, email: o["email"] as? String,
                          plan: o["subscriptionType"] as? String)
    }
}

/// Kabuk dosyalarına eklenen bloklar.
public enum AccountIntegration {
    /// statusline script'inin sonuna eklenir: rate_limits'i arka planda uygulamaya gönderir.
    public static func statuslineBlock(port: UInt16) -> String {
        """
        \(ShellSnippet.begin)
        ( printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null \\
          | curl -s -o /dev/null --max-time 0.3 -X POST --data-binary @- \\
            -H "X-Claude-Config-Dir: ${CLAUDE_CONFIG_DIR:-}" http://127.0.0.1:\(port)/usage >/dev/null 2>&1 & )
        \(ShellSnippet.end)

        """
    }

    /// ~/.zshrc'ye eklenir: CLAUDE_CONFIG_DIR verilmemişse AjanTakip'te seçili profili kullanır.
    public static let zshBlock = """
        \(ShellSnippet.begin)
        claude() {
          local d=""
          if [ -z "${CLAUDE_CONFIG_DIR:-}" ] && [ -r "$HOME/.config/ajantakip/active-profile" ]; then
            d=$(<"$HOME/.config/ajantakip/active-profile")
          fi
          if [ -n "$d" ]; then CLAUDE_CONFIG_DIR="$d" command claude "$@"; else command claude "$@"; fi
        }
        \(ShellSnippet.end)

        """

    /// `id` profilinin e-postası başka bir profilde zaten varsa o profilin id'si.
    public static func duplicateOf(_ id: String, emails: [String: String]) -> String? {
        guard let mine = emails[id]?.lowercased() else { return nil }
        return emails.filter { $0.key != id && $0.value.lowercased() == mine }.keys.sorted().first
    }
}
