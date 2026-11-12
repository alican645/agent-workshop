import Foundation

public enum HookInstallerError: Error, Equatable {
    case unreadableSettings
}

/// `~/.claude/settings.json` içine AjanTakip hook girdilerini ekler/çıkarır; başka hook'lara dokunmaz.
public enum HookInstaller {
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                "Notification", "Stop", "SessionEnd"]
    public static let marker = "ajantakip-hook.sh"
    private static let matcherEvents: Set<String> = ["PreToolUse", "PostToolUse"]

    /// Claude Code hook komutu `sh -c` ile çalışır; yolda boşluk/özel karakter olsa da tek argüman kalsın.
    public static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    public static func install(into settings: [String: Any], command: String) -> [String: Any] {
        var result = uninstall(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var list = hooks[event] as? [[String: Any]] ?? []
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            if matcherEvents.contains(event) { entry["matcher"] = "*" }
            list.append(entry)
            hooks[event] = list
        }
        result["hooks"] = hooks
        return result
    }

    public static func uninstall(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return result }
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else { continue }
            let cleaned: [[String: Any]] = list.compactMap { entry in
                guard let inner = entry["hooks"] as? [[String: Any]] else { return entry }
                let kept = inner.filter { !isOurs($0) }
                if kept.isEmpty { return nil }
                var e = entry
                e["hooks"] = kept
                return e
            }
            hooks[event] = cleaned.isEmpty ? nil : cleaned
        }
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    public static func isInstalled(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    public static func installFile(at url: URL, command: String, now: Date) throws {
        try rewrite(url, now: now) { install(into: $0, command: command) }
    }

    public static func uninstallFile(at url: URL, now: Date) throws {
        try rewrite(url, now: now) { uninstall(from: $0) }
    }

    /// Dosyayı okur (yoksa `{}`); bozuksa dokunmadan hata fırlatır.
    public static func readFile(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw HookInstallerError.unreadableSettings }
        return obj
    }

    private static func rewrite(_ url: URL, now: Date, _ transform: ([String: Any]) -> [String: Any]) throws {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let current = try readFile(at: url)
        if exists {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).bak-\(stamp(now))")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: transform(current),
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private static func isOurs(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(marker) == true
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}
