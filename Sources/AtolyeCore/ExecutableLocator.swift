import Foundation

public enum ExecutableLocator {
    /// GUI uygulamalarının PATH'i kısa olduğu için Homebrew dizinleri de denenir.
    public static let wellKnownDirs = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Sıra: `preferred` → PATH dizinleri → bilinen dizinler.
    public static func find(_ name: String, preferred: [String], pathEnv: String?,
                            isExecutable: (String) -> Bool) -> String? {
        let pathDirs = (pathEnv ?? "").split(separator: ":").map(String.init)
        let candidates = preferred + (pathDirs + wellKnownDirs).map { "\($0)/\(name)" }
        return candidates.first(where: isExecutable)
    }
}
