import Foundation

/// Claude Code'un `sessions/<pid>.json` kaydındaki durum.
public enum RegistryStatus: Equatable, Sendable {
    case busy, waiting, idle
}

/// Bir profilin `sessions/<pid>.json` dosyasından okunan canlı sohbet.
public struct RegistryEntry: Equatable, Sendable {
    public var pid: Int32
    public var sessionID: String
    public var cwd: String?
    public var status: RegistryStatus
    public var waitingFor: String?
    public var statusSince: Date
    public var profileID: String

    public init(pid: Int32, sessionID: String, cwd: String?, status: RegistryStatus, waitingFor: String?,
                statusSince: Date, profileID: String) {
        self.pid = pid; self.sessionID = sessionID; self.cwd = cwd; self.status = status
        self.waitingFor = waitingFor; self.statusSince = statusSince; self.profileID = profileID
    }

    /// Yalnız kullanıcının sohbetleri: arka plan işleri (`kind`), yedek süreçler (`spare`) ve başka bir oturumun
    /// içindekiler (`hostSessionId`) atlanır. Bozuk ya da eksik dosyada nil.
    public static func parse(_ data: Data, profileID: String) -> RegistryEntry? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (o["pid"] as? NSNumber)?.int32Value,
              let sid = o["sessionId"] as? String, !sid.isEmpty else { return nil }
        if let kind = o["kind"] as? String, kind != "interactive" { return nil }
        if o["spare"] as? Bool == true { return nil }
        if let host = o["hostSessionId"] as? String, !host.isEmpty { return nil }
        let status: RegistryStatus = switch o["status"] as? String {
        case "busy": .busy
        case "waiting": .waiting
        default: .idle  // durum yok, "idle" ya da "shell" (yalnız arka planda bir kabuk çalışıyor)
        }
        let ms = (o["statusUpdatedAt"] as? NSNumber ?? o["updatedAt"] as? NSNumber)?.doubleValue ?? 0
        let waiting = (o["waitingFor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return RegistryEntry(pid: pid, sessionID: sid, cwd: o["cwd"] as? String, status: status, waitingFor: waiting,
                             statusSince: Date(timeIntervalSince1970: ms / 1000), profileID: profileID)
    }
}
