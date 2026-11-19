import CryptoKit
import Foundation

/// Yardımcının sürümü: yürütülebilir dosyasının içerik özeti. Her derlemede kendiliğinden değişir.
public enum HostVersion {
    /// Dosyanın SHA-256 özeti (hex); okunamazsa nil.
    public static func of(executable path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Çalışan yardımcı paketteki sürümden farklı mı. Paketteki okunamıyorsa (geliştirme) alarm verilmez;
    /// çalışan sürüm bilinmiyorsa (sürüm bildirmeyen eski yardımcı) eski sayılır.
    public static func outdated(running: String?, bundled: String?) -> Bool {
        guard let bundled else { return false }
        return running != bundled
    }
}

/// Yardımcı yeniden başlarken geri açılacak Claude oturumları.
public enum HostRestart {
    public struct Resume: Equatable, Sendable {
        public var sessionID: String
        public var cwd: String
        public var profileID: String
        /// Eski terminal (masadaki penceresi yenisine geçer).
        public var terminal: String

        public init(sessionID: String, cwd: String, profileID: String, terminal: String) {
            self.sessionID = sessionID; self.cwd = cwd; self.profileID = profileID; self.terminal = terminal
        }
    }

    /// Yardımcıdaki bir terminalde çalışan ve klasörü bilinen oturumlar (cmux gibi dışarıdakiler değil).
    public static func resumable(_ candidates: [ProfileMove.Candidate]) -> [Resume] {
        candidates.compactMap { c in
            guard let t = c.terminal, c.terminalKind != nil, let cwd = c.cwd else { return nil }
            return Resume(sessionID: c.sessionID, cwd: cwd, profileID: c.profileID, terminal: t)
        }
    }
}
