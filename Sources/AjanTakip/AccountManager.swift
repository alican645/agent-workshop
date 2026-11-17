import AjanTakipCore
import AppKit
import Observation
import os

/// Claude hesap profilleri, son bilinen kullanım oranları ve kabuk entegrasyonu.
@MainActor @Observable
final class AccountManager {
    private struct Saved: Codable {
        var store: AccountStore
        var usage: [String: AccountUsage]
    }

    private static let log = Logger(subsystem: "com.ajantakip.app", category: "accounts")
    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    private static var configDir: URL { URL(fileURLWithPath: home + "/.config/ajantakip") }
    private static var savedURL: URL { configDir.appendingPathComponent("accounts.json") }
    private static var activeProfileURL: URL { configDir.appendingPathComponent("active-profile") }
    private static var profilesListURL: URL { configDir.appendingPathComponent("profiles") }
    static var zshrcURL: URL { URL(fileURLWithPath: home + "/.zshrc") }
    static var statuslineURL: URL { URL(fileURLWithPath: home + "/.claude/statusline-command.sh") }

    var store: AccountStore
    var usage: [String: AccountUsage]
    var auth: [String: AuthStatus] = [:]
    var integrationInstalled = false
    /// Aktif hesap için uyarı verildi mi (eşik altına inince sıfırlanır).
    private var warned = false

    init() {
        if let data = try? Data(contentsOf: Self.savedURL),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            store = saved.store
            usage = saved.usage
        } else {
            store = AccountStore(home: Self.home)
            usage = [:]
        }
        refreshIntegration()
        upgradeIntegration()
        save()
    }

    var hasMultiple: Bool { store.profiles.count > 1 }

    func label(_ p: AccountProfile) -> String {
        if let email = auth[p.id]?.email { return "\(p.name) · \(email)" }
        return p.name
    }

    // MARK: Kullanım

    /// Yeni kullanım raporu; aktif hesap eşiği yeni geçtiyse true döner (uyarı için).
    func ingest(_ report: UsageReport) -> Bool {
        guard let id = store.profileID(forConfigDir: report.configDir) else {
            Self.log.error("bilinmeyen config dir: \(report.configDir ?? "-")")
            return false
        }
        usage[id] = report.usage
        save()
        return checkWarning()
    }

    private func checkWarning() -> Bool {
        let over = usage[store.activeID].map { AccountStore.needsWarning($0, now: .now) } ?? false
        defer { warned = over }
        return over && !warned
    }

    func setActive(_ id: String) {
        guard store.profiles.contains(where: { $0.id == id }) else { return }
        store.activeID = id
        warned = false
        save()
    }

    // MARK: Profiller

    func addProfile(name: String) throws -> AccountProfile {
        var s = store
        let p = try s.addProfile(name: name)
        try createProfileDir(p)
        store = s
        save()
        return p
    }

    func removeProfile(_ id: String) {
        store.removeProfile(id: id)
        usage[id] = nil
        auth[id] = nil
        save()
    }

    /// Profil klasörünü oluşturur, ortak öğeleri ~/.claude'dan sembolik bağlar.
    private func createProfileDir(_ p: AccountProfile) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: p.configDir, withIntermediateDirectories: true)
        let base = Self.home + "/.claude"
        let names = (try? fm.contentsOfDirectory(atPath: base)) ?? []
        for name in ProfileLinker.sharedItems(existingIn: names) {
            let dest = p.configDir + "/" + name
            if fm.fileExists(atPath: dest) || (try? fm.destinationOfSymbolicLink(atPath: dest)) != nil { continue }
            try fm.createSymbolicLink(atPath: dest, withDestinationPath: base + "/" + name)
        }
    }

    /// Yeni bir cmux çalışma alanında bu profil için `claude auth login` açar.
    func openLogin(_ p: AccountProfile) {
        guard let cli = CmuxNavigator.cliPath() else {
            HookSetup.showError("cmux bulunamadı. Bir terminalde şunu çalıştır:\nCLAUDE_CONFIG_DIR=\(p.configDir) claude auth login")
            return
        }
        var args = ["new-workspace", "--name", "Claude: \(p.name)", "--command", "claude auth login", "--focus", "true"]
        if p.id != AccountStore.defaultID { args += ["--env", "CLAUDE_CONFIG_DIR=\(p.configDir)"] }
        let finalArgs = args
        DispatchQueue.global(qos: .userInitiated).async { Self.run(cli, finalArgs) }
    }

    /// Her profilin giriş durumunu (e-posta) arka planda okur.
    func refreshAuth() {
        guard let claude = ExecutableLocator.find("claude", preferred: [Self.home + "/.local/bin/claude"],
                                                  pathEnv: ProcessInfo.processInfo.environment["PATH"],
                                                  isExecutable: FileManager.default.isExecutableFile(atPath:))
        else { return }
        for p in store.profiles {
            let dir = p.id == AccountStore.defaultID ? nil : p.configDir
            Task.detached(priority: .utility) { [weak self] in
                let status = Self.authStatus(claude: claude, configDir: dir)
                await MainActor.run { self?.auth[p.id] = status }
            }
        }
    }

    nonisolated private static func authStatus(claude: String, configDir: String?) -> AuthStatus? {
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CONFIG_DIR"] = configDir
        let out = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = ["auth", "status", "--json"]
        p.environment = env
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return AuthStatus.parse(data)
    }

    var duplicateWarning: String? {
        let emails = auth.compactMapValues(\.email)
        for p in store.profiles {
            if let other = AccountIntegration.duplicateOf(p.id, emails: emails),
               let o = store.profiles.first(where: { $0.id == other }), p.id > other {
                return "\(p.name) ve \(o.name) aynı hesaba giriş yapmış."
            }
        }
        return nil
    }

    // MARK: Kabuk entegrasyonu

    func refreshIntegration() {
        let z = (try? String(contentsOf: Self.zshrcURL, encoding: .utf8)) ?? ""
        let s = (try? String(contentsOf: Self.statuslineURL, encoding: .utf8)) ?? ""
        integrationInstalled = ShellSnippet.contains(in: z) && ShellSnippet.contains(in: s)
    }

    /// Kurulu `.zshrc` bloğu eski sürümse yedek alarak günceller (aynıysa dosyaya dokunulmaz).
    private func upgradeIntegration() {
        guard integrationInstalled else { return }
        do {
            try Self.rewrite(Self.zshrcURL) { ShellSnippet.insert(AccountIntegration.zshBlock, into: $0) }
        } catch {
            Self.log.error("zsh bloğu güncellenemedi: \(error.localizedDescription)")
        }
    }

    func toggleIntegration(port: UInt16) throws {
        let install = !integrationInstalled
        try Self.rewrite(Self.zshrcURL) {
            install ? ShellSnippet.insert(AccountIntegration.zshBlock, into: $0) : ShellSnippet.remove(from: $0)
        }
        try Self.rewrite(Self.statuslineURL) {
            install ? ShellSnippet.insert(AccountIntegration.statuslineBlock(port: port), into: $0)
                    : ShellSnippet.remove(from: $0)
        }
        refreshIntegration()
    }

    /// Dosyayı değiştirmeden önce zaman damgalı yedek alır; içerik aynıysa dokunmaz.
    private static func rewrite(_ url: URL, _ transform: (String) -> String) throws {
        let fm = FileManager.default
        let old = fm.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
        let new = transform(old)
        guard new != old else { return }
        if fm.fileExists(atPath: url.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let backup = URL(fileURLWithPath: url.path + ".bak-" + f.string(from: .now))
            try fm.copyItem(at: url, to: backup)
        }
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        try new.write(to: url, atomically: true, encoding: .utf8)
        if let perms = attrs?[.posixPermissions] { try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: url.path) }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(store: store, usage: usage)).write(to: Self.savedURL, options: .atomic)
            try store.activeConfigDirForShell.write(to: Self.activeProfileURL, atomically: true, encoding: .utf8)
            try store.profilesFileContents.write(to: Self.profilesListURL, atomically: true, encoding: .utf8)
        } catch {
            Self.log.error("kaydedilemedi: \(error.localizedDescription)")
        }
    }

    @discardableResult
    nonisolated private static func run(_ cli: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
