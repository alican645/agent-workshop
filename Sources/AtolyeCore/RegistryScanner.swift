import Foundation

/// Profillerin `sessions/<pid>.json` kayıtlarını okur. Değişmeyen dosyayı yeniden okumaz; yarım yazılmış dosyada
/// önceki geçerli girdiyi kullanır, böylece oturum listeden düşüp geri gelmez.
public struct RegistryScanner: Sendable {
    private var cache: [String: (mtime: Date, entry: RegistryEntry?)] = [:]

    public init() {}

    public mutating func scan(dirs: [(profileID: String, configDir: String)], isAlive: (Int32) -> Bool) -> [RegistryEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [RegistryEntry] = []
        for (profileID, configDir) in dirs {
            let dir = configDir + "/sessions"
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names.sorted() where name.hasSuffix(".json") {
                let stem = name.dropLast(5)
                guard !stem.isEmpty, stem.allSatisfy(\.isNumber) else { continue }
                let path = dir + "/" + name
                guard let mtime = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { continue }
                seen.insert(path)
                var entry: RegistryEntry?
                if let c = cache[path], c.mtime == mtime {
                    entry = c.entry
                } else {
                    let parsed = fm.contents(atPath: path).flatMap { RegistryEntry.parse($0, profileID: profileID) }
                    entry = parsed ?? cache[path]?.entry
                    cache[path] = (mtime, entry)
                }
                if let entry, isAlive(entry.pid) { out.append(entry) }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        return out
    }
}
