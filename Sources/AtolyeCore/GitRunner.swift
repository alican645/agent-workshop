import Foundation

/// `git` komutunu çalıştırır. Ajanların işini bozmamak için hiçbir zaman isteğe bağlı kilit almaz
/// (`--no-optional-locks`), yazma yapan komut çalıştırmaz. Ana iş parçacığında çağrılmamalı.
public enum GitRunner {
    public static let diffLimit = 3000

    /// Diff'i istenen öğe.
    public enum Target: Equatable, Sendable, Hashable {
        case staged(String), unstaged(String), untracked(String), commit(String)
    }

    /// Çıkış kodu kabul edilenlerden biriyse çıktı, değilse (ya da zaman aşımında) nil.
    public static func run(_ args: [String], in dir: String, okCodes: Set<Int32> = [0], timeout: TimeInterval = 5) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["--no-optional-locks", "-C", dir] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_PAGER"] = "cat"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationReason == .exit, okCodes.contains(p.terminationStatus) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Depo değilse nil.
    public static func status(_ root: String) -> GitStatus? {
        run(["status", "--porcelain=v2", "--branch", "-z"], in: root).map(GitStatus.parse)
    }

    public static func log(_ root: String, limit: Int) -> [GitCommit] {
        run(["log", "-n", "\(limit)", "--format=\(GitCommit.format)"], in: root).map(GitLog.parse) ?? []
    }

    public static func badge(_ root: String) -> GitBadge? {
        guard let s = status(root) else { return nil }
        let head = log(root, limit: 1).first
        return GitBadge(branch: s.branch ?? "?", changed: s.changedCount, ahead: s.ahead, behind: s.behind,
                        head: head?.short, headSubject: head?.subject)
    }

    public static func diff(_ target: Target, in root: String, limit: Int = diffLimit) -> [DiffLine] {
        let out: String? = switch target {
        case let .unstaged(p): run(["diff", "--no-color", "--", p], in: root)
        case let .staged(p): run(["diff", "--no-color", "--cached", "--", p], in: root)
        case let .untracked(p): run(["diff", "--no-color", "--no-index", "--", "/dev/null", p], in: root, okCodes: [0, 1])
        case let .commit(h):
            run(["show", "--no-color", "--date=format:%d.%m.%Y %H:%M",
                 "--format=commit %H%n\(L("Yazan")): %an%n\(L("Tarih")): %ad%n%n%B", h], in: root)
        }
        return GitDiff.parse(out ?? "", limit: limit)
    }
}
