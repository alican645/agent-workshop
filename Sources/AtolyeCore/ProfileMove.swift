import Foundation

/// Etkin profil değişince Atölye'de açılmış Claude oturumlarının yeni profille, kaldıkları yerden
/// (`claude --resume <id>`) sürdürülmesi. Çalışan oturum yarıda kesilmez; işi bitince taşınır.
public enum ProfileMove {
    public struct Candidate: Equatable, Sendable {
        public var sessionID: String
        public var profileID: String
        /// Oturum bir Atölye terminalindeyse onun kimliği (cmux gibi dışarıdakilerde nil).
        public var terminal: String?
        public var terminalKind: TerminalKind?
        public var working: Bool
        public var cwd: String?

        public init(sessionID: String, profileID: String, terminal: String?, terminalKind: TerminalKind?,
                    working: Bool, cwd: String?) {
            self.sessionID = sessionID; self.profileID = profileID; self.terminal = terminal
            self.terminalKind = terminalKind; self.working = working; self.cwd = cwd
        }
    }

    public struct Move: Equatable, Sendable {
        public var sessionID: String
        public var terminal: String
        public var cwd: String
    }

    /// `now`: hemen taşınacaklar; `later`: çalıştığı için işi bitince taşınacak oturumlar.
    public static func plan(_ candidates: [Candidate], to profile: String) -> (now: [Move], later: [String]) {
        var now: [Move] = [], later: [String] = []
        for c in candidates where c.profileID != profile && c.terminalKind == .claude {
            guard let t = c.terminal, let cwd = c.cwd, !cwd.isEmpty else { continue }
            if c.working { later.append(c.sessionID) } else { now.append(Move(sessionID: c.sessionID, terminal: t, cwd: cwd)) }
        }
        return (now, later)
    }

    public static func resumeArgs(_ sessionID: String) -> [String] { ["--resume", sessionID] }
}
