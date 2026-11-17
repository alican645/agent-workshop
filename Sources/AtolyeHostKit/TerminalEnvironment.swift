/// Atölye terminallerine geçen ortam. Yardımcı bir Claude Code oturumunun ya da cmux'un içinden
/// başlatılmış olabilir; onların değişkenleri sızarsa terminalde açılan claude kendini "çocuk oturum"
/// sanıp oturum kaydını (`sessions/<pid>.json`) yazmaz ve atölyede robot olarak görünmez.
public enum TerminalEnvironment {
    static let exact: Set<String> = [
        "CLAUDECODE", "AI_AGENT", "COREPACK_ENABLE_AUTO_PIN",
        "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE",
    ]

    public static func clean(_ env: [String: String]) -> [String: String] {
        env.filter { k, v in
            !k.hasPrefix("CMUX_") && !k.hasPrefix("CLAUDE_") && !exact.contains(k)
                && !(k == "GIT_EDITOR" && v == "true") // Claude Code'un koyduğu değer
        }
    }
}
