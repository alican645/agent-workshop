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
    /// `claude mcp add|add-json|add-from-claude-desktop|remove` (project kapsamı hariç) her profilde ayrı çalışır.
    public static let zshBlock = """
        \(ShellSnippet.begin)
        claude() {
          local list="$HOME/.config/ajantakip/profiles"
          if [[ "${1:-}" == mcp && "${2:-}" == (add|add-json|add-from-claude-desktop|remove) && -r "$list" ]]; then
            local a prev="" project=0
            for a in "$@"; do
              [[ "$a" == --scope=project || ( "$a" == project && "$prev" == (-s|--scope) ) ]] && project=1
              prev="$a"
            done
            if (( ! project )); then
              local dir rc=0
              while IFS= read -r dir <&3; do
                [[ -n "$dir" ]] || continue
                print -r -- "── ${dir/#$HOME/~}"
                if [[ "$dir" == "$HOME/.claude" ]]; then
                  ( unset CLAUDE_CONFIG_DIR; command claude "$@" ) || rc=1
                else
                  CLAUDE_CONFIG_DIR="$dir" command claude "$@" || rc=1
                fi
              done 3< "$list"
              return $rc
            fi
          fi
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
