import Foundation

/// Profillerin `.claude.json` dosyalarında paylaşılması gereken alanları eşitler (MCP sunucuları, proje
/// izinleri ve güven onayları). Hesabın kimliği (`oauthAccount`) ve önbellekler dokunulmadan kalır.
///
/// Üç yollu birleştirme: taban, son eşitlenen haldir. Bir profilde tabana göre değişen (eklenen, silinen,
/// değiştirilen) öğe hepsine yansır; birden çok profil değiştirdiyse sırada sonraki (en son yazılan) kazanır.
/// Tabanda hiç bulunmamış bir profil yalnız ekleme yapabilir, eksikleri silme sayılmaz.
public enum ConfigSync {
    static let listFields = ["allowedTools", "enabledMcpjsonServers", "disabledMcpjsonServers", "disabledMcpServers"]
    static let scalarFields = ["hasTrustDialogAccepted", "enableAllProjectMcpServers"]
    static let sep = "\u{1F}"

    public struct Base: Codable, Equatable, Sendable {
        public var items: [String: Data] = [:]
        public var members: [String] = []
    }

    public struct Result {
        public var configs: [[String: Any]]
        public var base: Base
        public var changed: [Bool]
    }

    // MARK: Düzleştirme

    static func canonical(_ v: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
    }

    /// Anahtar sırası korunarak düz öğe listesi.
    static func flatten(_ c: [String: Any]) -> [(String, Data)] {
        var out: [(String, Data)] = []
        for (name, v) in ((c["mcpServers"] as? [String: Any]) ?? [:]).sorted(by: { $0.key < $1.key }) {
            out.append((["mcp", name].joined(separator: sep), canonical(v)))
        }
        for (path, raw) in ((c["projects"] as? [String: Any]) ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let p = raw as? [String: Any] else { continue }
            for (name, v) in ((p["mcpServers"] as? [String: Any]) ?? [:]).sorted(by: { $0.key < $1.key }) {
                out.append((["p", path, "mcpServers", name].joined(separator: sep), canonical(v)))
            }
            for f in listFields {
                for el in (p[f] as? [Any]) ?? [] {
                    guard let s = el as? String else { continue }
                    out.append((["p", path, f, s].joined(separator: sep), canonical(true)))
                }
            }
            for f in scalarFields where p[f] != nil {
                out.append((["p", path, f].joined(separator: sep), canonical(p[f]!)))
            }
        }
        return out
    }

    // MARK: Birleştirme

    public static func sync(configs: [[String: Any]], ids: [String]? = nil, base: Base?) -> Result {
        let ids = ids ?? configs.indices.map(String.init)
        let base = base ?? Base()
        let flats = configs.map { Dictionary(flatten($0), uniquingKeysWith: { a, _ in a }) }
        var order: [String] = []
        var seen = Set<String>()
        for k in base.items.keys.sorted() where !seen.contains(k) { seen.insert(k); order.append(k) }
        for c in configs { for (k, _) in flatten(c) where !seen.contains(k) { seen.insert(k); order.append(k) } }

        var merged: [String: Data] = [:]
        for k in order {
            let b = base.items[k]
            var result = b
            for (i, f) in flats.enumerated() {
                let v = f[k]
                let member = base.members.contains(ids[i])
                if v != b, member || v != nil { result = v }
            }
            if let result { merged[k] = result }
        }
        let mergedOrder = order.filter { merged[$0] != nil }
        let out = configs.map { rebuild($0, items: merged, order: mergedOrder, all: configs) }
        let changed = zip(configs, out).map { canonical($0) != canonical($1) }
        return Result(configs: out, base: Base(items: merged, members: ids), changed: changed)
    }

    private static func rebuild(_ c: [String: Any], items: [String: Data], order: [String], all: [[String: Any]]) -> [String: Any] {
        func value(_ d: Data) -> Any { (try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])) ?? NSNull() }
        var out = c
        var top: [String: Any] = [:]
        var projects: [String: [String: Any]] = [:] // yol → eşitlenen alanlar
        var lists: [String: [String: [String]]] = [:]
        for k in order {
            let parts = k.components(separatedBy: sep)
            if parts[0] == "mcp" { top[parts[1]] = value(items[k]!); continue }
            let path = parts[1], field = parts[2]
            if field == "mcpServers" {
                var m = projects[path]?["mcpServers"] as? [String: Any] ?? [:]
                m[parts[3]] = value(items[k]!)
                projects[path, default: [:]]["mcpServers"] = m
            } else if listFields.contains(field) {
                lists[path, default: [:]][field, default: []].append(parts[3])
                projects[path, default: [:]][field] = lists[path]![field]!
            } else {
                projects[path, default: [:]][field] = value(items[k]!)
            }
        }
        if !top.isEmpty || c["mcpServers"] != nil { out["mcpServers"] = top }

        var allProjects = (c["projects"] as? [String: Any]) ?? [:]
        let paths = Set(allProjects.keys).union(projects.keys)
        for path in paths {
            var entry: [String: Any]
            if let e = allProjects[path] as? [String: Any] {
                entry = e
            } else {
                // Diğer profillerden (en son yazılandan) tam kaydı kopyala; Claude'un varsayılan alanları olsun.
                entry = all.reversed().lazy.compactMap { ($0["projects"] as? [String: Any])?[path] as? [String: Any] }.first ?? [:]
            }
            let synced = projects[path] ?? [:]
            for f in ["mcpServers"] + listFields {
                if let v = synced[f] {
                    if let list = v as? [String] {
                        // Profilin kendi sırasını koru, yenileri sona ekle.
                        let mine = (entry[f] as? [String] ?? []).filter(list.contains)
                        entry[f] = mine + list.filter { !mine.contains($0) }
                    } else { entry[f] = v }
                } else if entry[f] != nil {
                    entry[f] = f == "mcpServers" ? [String: Any]() : [String]()
                }
            }
            for f in scalarFields { entry[f] = synced[f] }
            allProjects[path] = entry
        }
        if c["projects"] != nil || !projects.isEmpty { out["projects"] = allProjects }
        return out
    }

    // MARK: Dosyalar

    /// Dosyaları eşitler. Claude kilidi varsa ya da bir dosya okunamıyorsa `nil` (bu tur atlanır);
    /// yoksa yazılan dosyalar. İlk yazımdan önce gün başına bir yedek alınır.
    public static func run(files: [String], baseFile: String, backupDir: String, fm: FileManager = .default) -> [String]? {
        struct Item { var path: String; var json: [String: Any]; var mtime: Date; var perms: Int? }
        var items: [Item] = []
        for f in files {
            if fm.fileExists(atPath: f + ".lock") { return nil }
            let real = (f as NSString).resolvingSymlinksInPath
            guard let attrs = try? fm.attributesOfItem(atPath: real), let mtime = attrs[.modificationDate] as? Date,
                  let data = fm.contents(atPath: real),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            items.append(Item(path: real, json: json, mtime: mtime, perms: (attrs[.posixPermissions] as? NSNumber)?.intValue))
        }
        guard items.count > 1 else { return [] }
        items.sort { $0.mtime < $1.mtime }
        let base = fm.contents(atPath: baseFile).flatMap { try? JSONDecoder().decode(Base.self, from: $0) }
        let r = sync(configs: items.map(\.json), ids: items.map(\.path), base: base)

        // Okuduktan sonra Claude yazdıysa bu turu bırak.
        for it in items where (try? fm.attributesOfItem(atPath: it.path))?[.modificationDate] as? Date != it.mtime { return nil }
        var written: [String] = []
        let stamp = UsageMeter.dayKey(Date())
        for (i, it) in items.enumerated() where r.changed[i] {
            guard let data = try? JSONSerialization.data(withJSONObject: r.configs[i],
                                                         options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            else { continue }
            try? fm.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
            let name = it.path.replacingOccurrences(of: "/", with: "_")
            let backup = backupDir + "/" + name + "-" + stamp
            if !fm.fileExists(atPath: backup) { try? fm.copyItem(atPath: it.path, toPath: backup) }
            do {
                try data.write(to: URL(fileURLWithPath: it.path), options: .atomic)
                if let p = it.perms { try? fm.setAttributes([.posixPermissions: p], ofItemAtPath: it.path) }
                written.append(it.path)
            } catch { continue }
        }
        if let d = try? JSONEncoder().encode(r.base) {
            try? fm.createDirectory(atPath: (baseFile as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? d.write(to: URL(fileURLWithPath: baseFile), options: .atomic)
        }
        return written
    }
}
