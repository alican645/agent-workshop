import Foundation

/// Oturum kayıtlarının (`<configDir>/projects/*/*.jsonl`) bulunması. Profiller `projects` klasörünü ana
/// profille paylaşır (symlink); yollar çözülüp her gerçek dosya bir kez sayılır.
public enum TranscriptFiles {
    public static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Verilen andan sonra değişen kayıtlar, symlink'ler çözülmüş ve tekilleştirilmiş.
    public static func modified(since start: Date, in configDirs: [String]) -> [String] {
        let fm = FileManager.default
        var seen = Set<String>(), out: [String] = []
        for dir in configDirs {
            let projects = canonical(dir + "/projects")
            for p in (try? fm.contentsOfDirectory(atPath: projects)) ?? [] {
                let pdir = projects + "/" + p
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: pdir, isDirectory: &isDir), isDir.boolValue else { continue }
                for f in (try? fm.contentsOfDirectory(atPath: pdir)) ?? [] where f.hasSuffix(".jsonl") {
                    let path = canonical(pdir + "/" + f)
                    guard !seen.contains(path),
                          let m = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date, m >= start
                    else { continue }
                    seen.insert(path); out.append(path)
                }
            }
        }
        return out
    }
}

/// 5 saatlik ve haftalık limitler hesaba bağlıdır, profil klasörüne değil: aynı hesaba girişli bütün
/// klasörlerin en taze raporu o hesabı kullanan her profilde gösterilir.
public enum AccountLimits {
    /// `reports`: klasör → statusline raporu; `logins`: klasör → girişli hesabın e-postası.
    public static func byProfile(profiles: [(id: String, dir: String)], reports: [String: AccountUsage],
                                 logins: [String: String]) -> [String: AccountUsage] {
        var out: [String: AccountUsage] = [:]
        for p in profiles {
            let me = logins[p.dir]?.lowercased()
            let dirs = me.map { e in profiles.map(\.dir).filter { logins[$0]?.lowercased() == e } } ?? [p.dir]
            out[p.id] = dirs.compactMap { reports[$0] }.max { $0.reportedAt < $1.reportedAt }
        }
        return out
    }
}
