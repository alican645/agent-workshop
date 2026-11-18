import AtolyeCore
import AppKit
import Foundation
import Security

/// GitHub OAuth uygulamasının kimliği (gizli değil). Boşsa giriş düğmesi kapalı kalır.
enum GitHubConfig {
    static let clientID = "Ov23lidctnCuPi1EKRA8"
}

/// GitHub girişi ve kişisel katkı panosunun verisi. Anahtar Anahtar Zinciri'nde durur.
@MainActor
@Observable
final class GitHubModel {
    enum Phase: Equatable {
        case signedOut
        case waiting(GitHubDeviceCode)
        case signedIn
    }

    private(set) var phase: Phase = .signedOut
    private(set) var profile: GitHubProfile?
    private(set) var repos: [RepoActivity] = []
    private(set) var reposTotal = 0
    private(set) var loading = false
    private(set) var lastUpdated: Date?
    var error: String?

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    static let refreshInterval: TimeInterval = 600
    static let repoDays = 30

    var configured: Bool { !GitHubConfig.clientID.isEmpty }

    init() {
        // Anahtar Zinciri şifre sorabilir: arka planda oku ki açılış (ve arayüz) o soruyu beklemesin.
        Task { [weak self] in
            let saved = await Task.detached { Keychain.load() }.value
            guard let self, self.token == nil, let saved else { return }
            self.token = saved
            self.phase = .signedIn
            self.refreshIfStale()
        }
    }

    var stats: ContributionStats? {
        profile.map { ContributionStats(days: $0.days, today: UsageMeter.dayKey(Date())) }
    }

    // MARK: Giriş

    func signIn() {
        guard configured else { return }
        signInTask?.cancel()
        error = nil
        signInTask = Task { await runDeviceFlow() }
    }

    /// Bu Mac'teki GitHub CLI (`gh`) — varsa girişini kullanmak için.
    let ghPath: String? = ExecutableLocator.find(
        "gh", preferred: [FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/gh"],
        pathEnv: ProcessInfo.processInfo.environment["PATH"], isExecutable: FileManager.default.isExecutableFile(atPath:))

    /// OAuth kaydı gerekmeden: `gh auth token` ile alınan anahtarı kullanır.
    func useGHLogin() {
        guard let gh = ghPath else { return }
        error = nil
        Task {
            let token = await Task.detached { Self.run(gh, ["auth", "token"]) }.value
            guard let token, !token.isEmpty else {
                error = L("GitHub CLI'da giriş bulunamadı. Terminalde `gh auth login` ile giriş yapıp tekrar dene.")
                return
            }
            Keychain.save(token)
            self.token = token
            phase = .signedIn
            await refresh()
        }
    }

    nonisolated private static func run(_ exe: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        phase = .signedOut
    }

    func signOut() {
        Keychain.delete()
        token = nil
        profile = nil
        repos = []
        lastUpdated = nil
        phase = .signedOut
    }

    private func runDeviceFlow() async {
        do {
            let (data, _) = try await URLSession.shared.data(for: GitHubAPI.deviceCodeRequest(clientID: GitHubConfig.clientID))
            guard let code = GitHubDeviceCode.parse(data) else {
                if case let .failed(msg) = GitHubTokenPoll.parse(data) { error = msg } else { error = L("Giriş başlatılamadı.") }
                return
            }
            phase = .waiting(code)
            Self.copy(code.userCode)
            NSWorkspace.shared.open(code.verificationURI)

            var interval = code.interval
            let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
            while Date() < deadline {
                try await Task.sleep(for: .seconds(interval))
                let (d, _) = try await URLSession.shared.data(
                    for: GitHubAPI.tokenRequest(clientID: GitHubConfig.clientID, deviceCode: code.deviceCode))
                switch GitHubTokenPoll.parse(d) {
                case let .token(t):
                    Keychain.save(t)
                    token = t
                    phase = .signedIn
                    NSApp.activate()
                    await refresh()
                    return
                case .pending: continue
                case let .slowDown(i): interval = i
                case let .failed(msg):
                    error = msg
                    phase = .signedOut
                    return
                }
            }
            error = L("Kodun süresi doldu, yeniden dene.")
            phase = .signedOut
        } catch is CancellationError {
        } catch {
            self.error = L("GitHub'a ulaşılamadı: {0}", error.localizedDescription)
            phase = .signedOut
        }
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    // MARK: Veri

    func refreshIfStale() {
        guard phase == .signedIn, !loading else { return }
        if let t = lastUpdated, Date().timeIntervalSince(t) < Self.refreshInterval { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard let token, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let (pd, resp) = try await URLSession.shared.data(for: GitHubAPI.profileRequest(token: token))
            if (resp as? HTTPURLResponse)?.statusCode == 401 {
                signOut()
                error = L("GitHub oturumu geçersiz, yeniden giriş yap.")
                return
            }
            guard let p = GitHubProfile.parse(pd) else { error = L("Katkılar okunamadı."); return }
            profile = p
            error = nil

            let since = UsageMeter.dayKey(Date().addingTimeInterval(-Double(Self.repoDays) * 86_400))
            var pages: [Data] = []
            for page in 1...10 { // arama en çok 1000 sonuç verir
                let (sd, _) = try await URLSession.shared.data(
                    for: GitHubAPI.searchRequest(token: token, login: p.login, since: since, page: page))
                pages.append(sd)
                if page == 1 { reposTotal = RepoActivity.totalCount(sd) }
                if page * 100 >= reposTotal { break }
            }
            repos = RepoActivity.count(searchPages: pages)
            lastUpdated = Date()
        } catch {
            self.error = L("GitHub'a ulaşılamadı: {0}", error.localizedDescription)
        }
    }
}

/// GitHub anahtarı için Anahtar Zinciri kaydı.
enum Keychain {
    private static let service = "com.ajantakip.atolye.github"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "token"]
    }

    static func save(_ token: String) {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}
