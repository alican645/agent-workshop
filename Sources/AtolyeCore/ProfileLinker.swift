import Foundation

/// Profil klasöründeki ortak öğeleri ana `~/.claude`'a sembolik bağlar; böylece bütün profiller aynı
/// skill'leri, ayarları, hafızayı ve geçmişi kullanır. `sessions`, `.claude.json` gibi hesaba özgü olanlar kalır.
public enum ProfileLinker {
    public static let shared: Set<String> = [
        "CLAUDE.md", "agents", "commands", "file-history", "history.jsonl", "hooks", "keybindings.json",
        "output-styles", "plans", "plugins", "projects", "settings.json", "skills", "statusline-command.sh",
    ]
    public static let backupDir = ".atolye-yedek"

    /// Ana klasörde bulunan ortak öğeler (sıralı).
    public static func sharedItems(existingIn names: [String]) -> [String] {
        names.filter(shared.contains).sorted()
    }

    /// Bağlar; profilde gerçek dosya/klasör varsa önce birleştirir (geçmiş satırları, dosya geçmişi
    /// klasörleri), aslını `.atolye-yedek/` altına taşır. Değişen öğelerin adlarını döner.
    @discardableResult
    public static func link(profileDir: String, mainDir: String, fm: FileManager = .default) throws -> [String] {
        guard profileDir != mainDir else { return [] }
        try fm.createDirectory(atPath: profileDir, withIntermediateDirectories: true)
        let names = (try? fm.contentsOfDirectory(atPath: mainDir)) ?? []
        var changed: [String] = []
        for name in sharedItems(existingIn: names) {
            let target = mainDir + "/" + name, here = profileDir + "/" + name
            if let dest = try? fm.destinationOfSymbolicLink(atPath: here) {
                if dest == target { continue }
                try fm.removeItem(atPath: here)
            } else if fm.fileExists(atPath: here) {
                try merge(here, into: target, name: name, fm: fm)
                let backup = profileDir + "/" + backupDir
                try fm.createDirectory(atPath: backup, withIntermediateDirectories: true)
                var dst = backup + "/" + name
                if fm.fileExists(atPath: dst) { dst += "-" + String(Int(Date().timeIntervalSince1970)) }
                try fm.moveItem(atPath: here, toPath: dst)
            }
            try fm.createSymbolicLink(atPath: here, withDestinationPath: target)
            changed.append(name)
        }
        return changed
    }

    private static func merge(_ src: String, into dst: String, name: String, fm: FileManager) throws {
        switch name {
        case "history.jsonl":
            let mine = (try? String(contentsOfFile: dst, encoding: .utf8)) ?? ""
            let theirs = (try? String(contentsOfFile: src, encoding: .utf8)) ?? ""
            let have = Set(mine.split(separator: "\n"))
            let add = theirs.split(separator: "\n").filter { !have.contains($0) }
            guard !add.isEmpty else { return }
            let sep = mine.isEmpty || mine.hasSuffix("\n") ? "" : "\n"
            let h = try FileHandle(forWritingTo: URL(fileURLWithPath: dst))
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: Data((sep + add.joined(separator: "\n") + "\n").utf8))
        case "file-history":
            for child in (try? fm.contentsOfDirectory(atPath: src)) ?? [] where !fm.fileExists(atPath: dst + "/" + child) {
                try fm.moveItem(atPath: src + "/" + child, toPath: dst + "/" + child)
            }
        default:
            break // ana klasördeki kazanır; profildeki yedeğe gider
        }
    }
}
