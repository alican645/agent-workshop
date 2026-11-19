import AtolyeCore
import AppKit
import AtolyeHostKit
import Foundation

/// Claude hesapları (profiller). Bütün profiller aynı skill'leri, ayarları, hafızayı ve geçmişi kullanır
/// (sembolik bağlar); `.claude.json`'daki MCP ve proje izinleri birkaç saniyede bir eşitlenir. Limitler
/// statusline'ın yazdığı dosyalardan okunur; %90'ı geçen profil için uyarı verilir.
@MainActor
@Observable
final class Profiles {
    private(set) var store: AccountStore
    /// Profil → statusline'dan gelen son limitler.
    private(set) var limits: [String: AccountUsage] = [:]
    /// Profil → `.claude.json`'da girişli hesap.
    private(set) var loggedIn: [String: String] = [:]

    @ObservationIgnored var onWarning: ((AccountProfile, String) -> Void)?
    @ObservationIgnored private var warned: Set<String> = []
    @ObservationIgnored private let queue = DispatchQueue(label: "atolye.profiles", qos: .utility)
    @ObservationIgnored private var busy = false

    nonisolated static let support = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Atolye"
    nonisolated static let storeURL = URL(fileURLWithPath: support + "/accounts.json")
    nonisolated static let limitsDir = support + "/limits"
    nonisolated static let backupDir = support + "/yedek"
    nonisolated static let syncBase = support + "/config-sync.json"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        store = Self.load(home: home)
        save()
    }

    var profiles: [AccountProfile] { store.profiles }
    var active: AccountProfile { profiles.first { $0.id == store.activeID } ?? profiles[0] }
    var main: AccountProfile { profiles.first { $0.id == AccountStore.defaultID } ?? profiles[0] }

    func environment(_ id: String? = nil) -> [String: String] { store.environment(id ?? store.activeID) }

    func setActive(_ id: String) {
        guard store.activeID != id, profiles.contains(where: { $0.id == id }) else { return }
        store.activeID = id
        save()
    }

    @discardableResult
    func add(email: String?) -> AccountProfile {
        let p = store.addProfile(email: email)
        save()
        try? ProfileLinker.link(profileDir: p.configDir, mainDir: main.configDir)
        return p
    }

    func setEmail(_ email: String?, for id: String) {
        guard let i = store.profiles.firstIndex(where: { $0.id == id }) else { return }
        store.profiles[i].email = email.flatMap { $0.isEmpty ? nil : $0 }
        save()
    }

    /// Profilin beklenen hesabı dışında bir hesaba girişliyse açıklaması.
    func mismatch(_ p: AccountProfile) -> String? {
        guard let want = p.email, let have = loggedIn[p.id], want.lowercased() != have.lowercased() else { return nil }
        return L("{0} ile girişli, {1} bekleniyor", have, want)
    }

    func needsWarning(_ p: AccountProfile, now: Date = Date()) -> Bool {
        limits[p.id].map { AccountStore.needsWarning($0, now: now) } ?? false
    }

    // MARK: Tazeleme (arka planda)

    func refresh() {
        guard !busy else { return }
        busy = true
        let store = self.store
        queue.async {
            let mainDir = store.profiles.first { $0.id == AccountStore.defaultID }?.configDir ?? ""
            var reports: [String: AccountUsage] = [:]   // klasör → rapor
            var logins: [String: String] = [:]          // klasör → girişli hesap
            var emails: [String: String] = [:]
            var files: [String] = []
            for p in store.profiles {
                if p.id != AccountStore.defaultID { try? ProfileLinker.link(profileDir: p.configDir, mainDir: mainDir) }
                let lf = Self.limitsDir + "/" + AtolyeIntegration.limitFileName(configDir: p.configDir)
                reports[p.configDir] = AtolyeIntegration.readLimits(path: lf)
                if let g = store.globalConfigPath(p.id), FileManager.default.fileExists(atPath: g) {
                    files.append(g)
                    emails[p.id] = AtolyeIntegration.loggedInEmail(globalConfig: g)
                    logins[p.configDir] = emails[p.id]
                }
            }
            // Limitler hesaba bağlı: aynı hesaba girişli klasörlerin en taze raporu.
            let limits = AccountLimits.byProfile(profiles: store.profiles.map { ($0.id, $0.configDir) },
                                                 reports: reports, logins: logins)
            _ = ConfigSync.run(files: files, baseFile: Self.syncBase, backupDir: Self.backupDir)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self.limits != limits { self.limits = limits }
                    if self.loggedIn != emails { self.loggedIn = emails }
                    self.busy = false
                    self.checkWarnings()
                }
            }
        }
    }

    private func checkWarnings() {
        let now = Date()
        for p in profiles {
            guard let u = limits[p.id] else { continue }
            for (name, v, reset) in [(L("5 saatlik"), u.effectiveFiveHour(now: now), u.fiveHourResetsAt),
                                     (L("haftalık"), u.effectiveSevenDay(now: now), u.sevenDayResetsAt)] {
                guard let v, v >= AccountStore.warningThreshold else { continue }
                let key = "\(p.id)|\(name)|\(reset?.timeIntervalSince1970 ?? 0)"
                guard !warned.contains(key) else { continue }
                warned.insert(key)
                onWarning?(p, L("{0} limit %{1} dolu", name, "\(Int((v * 100).rounded()))"))
            }
        }
    }

    // MARK: Kalıcılık

    private static func load(home: String) -> AccountStore {
        if let d = try? Data(contentsOf: storeURL), let s = try? JSONDecoder().decode(AccountStore.self, from: d) { return s }
        // İlk açılış: adları sıra numarasına çevir.
        var s = AccountStore(home: home)
        for i in s.profiles.indices {
            let id = s.profiles[i].id
            s.profiles[i].name = id == AccountStore.defaultID ? "Profil 1"
                : id.hasPrefix("profil-") ? "Profil " + id.dropFirst(7) : s.profiles[i].name
        }
        return s
    }

    private func save() {
        try? FileManager.default.createDirectory(atPath: Self.support, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(store) { try? d.write(to: Self.storeURL, options: .atomic) }
    }

    // MARK: Kurulum (her açılışta, değişiklik yoksa dokunmaz)

    /// statusline'a limit bloğunu ekler. Değişen dosyanın aslı önce `yedek/` klasörüne kopyalanır.
    nonisolated static func installIntegration(mainDir: String) {
        func rewrite(_ path: String, _ change: (String) -> String?) {
            let real = (path as NSString).resolvingSymlinksInPath
            guard let old = try? String(contentsOfFile: real, encoding: .utf8), let new = change(old), new != old else { return }
            backup(real)
            try? new.write(toFile: real, atomically: true, encoding: .utf8)
        }
        rewrite(mainDir + "/statusline-command.sh") { AtolyeIntegration.installStatusline(into: $0) }
        // Balondan cevap için Claude Code hook'u: önce sabit yola kopyalanır, ayarlar o yolu gösterir.
        if installHookBinary() {
            rewrite(mainDir + "/settings.json") { AtolyeIntegration.installHooks(into: $0, executable: HostPaths.hookBinary) }
        }
    }

    /// Paketteki `atolye-hook`'u Application Support'a kopyalar (aynıysa dokunmaz). Hook kullanılabilir mi.
    nonisolated private static func installHookBinary() -> Bool {
        let fm = FileManager.default
        guard let src = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("atolye-hook").path,
              let data = fm.contents(atPath: src) else { return fm.isExecutableFile(atPath: HostPaths.hookBinary) }
        if fm.contents(atPath: HostPaths.hookBinary) == data { return true }
        let dir = (HostPaths.hookBinary as NSString).deletingLastPathComponent
        let tmp = HostPaths.hookBinary + ".new"
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? fm.removeItem(atPath: tmp)
            try fm.copyItem(atPath: src, toPath: tmp)
            // Çalışan bir hook eski dosyayı açık tutuyor olabilir: yerine taşımak onu bozmaz.
            _ = rename(tmp, HostPaths.hookBinary)
        } catch {
            return fm.isExecutableFile(atPath: HostPaths.hookBinary)
        }
        return fm.isExecutableFile(atPath: HostPaths.hookBinary)
    }

    nonisolated private static func backup(_ path: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
        let dst = backupDir + "/" + path.replacingOccurrences(of: "/", with: "_") + "-" + String(Int(Date().timeIntervalSince1970))
        try? fm.copyItem(atPath: path, toPath: dst)
    }
}
