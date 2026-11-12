import Foundation

public enum HookEventName: Equatable, Sendable {
    case sessionStart, userPromptSubmit, preToolUse, postToolUse, notification, stop, sessionEnd
    case unknown(String)

    init(raw: String) {
        switch raw {
        case "SessionStart": self = .sessionStart
        case "UserPromptSubmit": self = .userPromptSubmit
        case "PreToolUse": self = .preToolUse
        case "PostToolUse": self = .postToolUse
        case "Notification": self = .notification
        case "Stop": self = .stop
        case "SessionEnd": self = .sessionEnd
        default: self = .unknown(raw)
        }
    }
}

public enum NotificationKind: Equatable, Sendable {
    case permission, idle, other
}

public enum HookEventError: Error, Equatable {
    case invalidJSON, missingSessionID
}

/// Claude Code hook'undan gelen tek bir olay (gövde = hook JSON'u, başlıklar = cmux/süreç bilgisi).
public struct HookEvent: Equatable, Sendable {
    public var sessionID: String
    public var name: HookEventName
    public var cwd: String?
    public var toolName: String?
    public var toolTarget: String?
    public var notificationKind: NotificationKind?
    public var workspace: String?
    public var surface: String?
    public var pid: Int32?

    public init(sessionID: String, name: HookEventName, cwd: String? = nil, toolName: String? = nil,
                toolTarget: String? = nil, notificationKind: NotificationKind? = nil,
                workspace: String? = nil, surface: String? = nil, pid: Int32? = nil) {
        self.sessionID = sessionID
        self.name = name
        self.cwd = cwd
        self.toolName = toolName
        self.toolTarget = toolTarget
        self.notificationKind = notificationKind
        self.workspace = workspace
        self.surface = surface
        self.pid = pid
    }

    /// `headers` anahtarları küçük harf olmalıdır.
    public static func parse(body: Data, headers: [String: String]) throws -> HookEvent {
        guard let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            throw HookEventError.invalidJSON
        }
        guard let sid = obj["session_id"] as? String, !sid.isEmpty else {
            throw HookEventError.missingSessionID
        }
        let name = HookEventName(raw: obj["hook_event_name"] as? String ?? "")
        let input = obj["tool_input"] as? [String: Any] ?? [:]

        var event = HookEvent(sessionID: sid, name: name)
        event.cwd = nonEmpty(obj["cwd"] as? String)
        event.toolName = nonEmpty(obj["tool_name"] as? String)
        event.toolTarget = target(from: input)
        if name == .notification {
            event.notificationKind = notificationKind(type: obj["notification_type"] as? String,
                                                      message: obj["message"] as? String)
        }
        event.workspace = nonEmpty(headers["x-cmux-workspace"])
        event.surface = nonEmpty(headers["x-cmux-surface"])
        event.pid = nonEmpty(headers["x-claude-pid"]).flatMap { Int32($0) }
        return event
    }

    /// Tek satıra indirir, `max` karakterden uzunsa keser ve "…" ekler.
    static func shorten(_ s: String, max: Int = 40) -> String {
        let single = s.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return single.count > max ? String(single.prefix(max)) + "…" : single
    }

    private static func target(from input: [String: Any]) -> String? {
        for key in ["file_path", "notebook_path"] {
            if let p = nonEmpty(input[key] as? String) { return (p as NSString).lastPathComponent }
        }
        for key in ["command", "pattern", "url", "description"] {
            if let v = nonEmpty(input[key] as? String) { return shorten(v) }
        }
        return nil
    }

    private static func notificationKind(type: String?, message: String?) -> NotificationKind {
        switch type {
        case "permission_prompt": return .permission
        case "idle_prompt": return .idle
        default: break
        }
        let msg = (message ?? "").lowercased()
        if msg.contains("permission") { return .permission }
        if msg.contains("waiting for your input") { return .idle }
        return .other
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
