import Foundation

/// `.git/info/exclude` metni: yalnız bu depoda, kimseyle paylaşılmadan yok sayılan dosyalar.
public enum GitExclude {
    public static let todoEntry = "/" + TodoList.fileName

    public static func adding(_ text: String, _ entry: String) -> String {
        let ls = text.components(separatedBy: "\n")
        if ls.contains(where: { $0.trimmingCharacters(in: .whitespaces) == entry }) { return text }
        return text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + entry + "\n"
    }

    public static func removing(_ text: String, _ entry: String) -> String {
        text.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces) != entry }.joined(separator: "\n")
    }
}

/// TODO.local.md git'te paylaşılıyor mu.
public enum TodoGitState: Equatable, Sendable {
    /// Proje bir git deposu değil.
    case notRepo
    /// Dosya git'te takip edilmiyor (bu Mac'te kalır).
    case local
    /// Dosya git'te takip ediliyor: commit'lerle birlikte push edilir.
    case shared
}

public struct TodoGitError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Yapılacaklar dosyasının git ayarı. Git komutları çalıştırır; ana iş parçacığında çağrılmamalı.
public enum TodoGit {
    public static func state(root: String, file: String = TodoList.fileName) -> TodoGitState {
        guard GitRunner.run(["rev-parse", "--git-dir"], in: root) != nil else { return .notRepo }
        return GitRunner.run(["ls-files", "--error-unmatch", "--", file], in: root) != nil ? .shared : .local
    }

    /// Dosya takip edilmiyor ve hiçbir kural onu yok saymıyorsa bu depoda yok sayılanlara ekler.
    /// `file`: proje kökündeki dosya (varsayılan `TODO.local.md`; çalıştırma kartları için `RUN.local.json`).
    public static func keepLocal(root: String, file: String = TodoList.fileName) throws {
        guard state(root: root, file: file) == .local,
              FileManager.default.fileExists(atPath: root + "/" + file),
              GitRunner.run(["check-ignore", "-q", "--", file], in: root) == nil else { return }
        try editExclude(root: root, file: file) { GitExclude.adding($0, $1) }
    }

    /// Dosyayı git'e ekler (hazırlar): bir sonraki commit'le birlikte push edilir.
    public static func share(root: String) throws {
        let path = ProjectRoot.todoPath(root: root)
        if !FileManager.default.fileExists(atPath: path) { try "".write(toFile: path, atomically: true, encoding: .utf8) }
        try editExclude(root: root) { GitExclude.removing($0, $1) }
        try git(["add", "-f", "--", TodoList.fileName], root: root)
    }

    /// Dosyayı git takibinden çıkarır; diskteki dosya kalır ve bu depoda yok sayılır.
    public static func unshare(root: String) throws {
        try git(["rm", "--cached", "--quiet", "--", TodoList.fileName], root: root)
        try editExclude(root: root) { GitExclude.adding($0, $1) }
    }

    // MARK: Yardımcılar

    /// Depo kökü proje klasörünün üstündeyse girdi alt klasörle başlar.
    private static func entry(root: String, file: String) -> String {
        let prefix = GitRunner.run(["rev-parse", "--show-prefix"], in: root)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "/" + prefix + file
    }

    private static func editExclude(root: String, file: String = TodoList.fileName, _ change: (String, String) -> String) throws {
        guard var rel = GitRunner.run(["rev-parse", "--git-path", "info/exclude"], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !rel.isEmpty else {
            throw TodoGitError(message: "git: info/exclude bulunamadı")
        }
        if !rel.hasPrefix("/") { rel = root + "/" + rel }
        let old = (try? String(contentsOfFile: rel, encoding: .utf8)) ?? ""
        let new = change(old, entry(root: root, file: file))
        guard new != old else { return }
        try FileManager.default.createDirectory(atPath: (rel as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try new.write(toFile: rel, atomically: true, encoding: .utf8)
    }

    /// Yazan git komutu; başarısızsa git'in hata mesajıyla atar.
    private static func git(_ args: [String], root: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        p.environment = env
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw TodoGitError(message: msg.isEmpty ? "git \(args.first ?? "") başarısız" : msg)
        }
    }
}
