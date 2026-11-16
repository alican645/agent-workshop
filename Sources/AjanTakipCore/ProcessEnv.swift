import Darwin
import Foundation

/// Bir oturumun cmux konumu. 2. aşamada (terminal uygulama içine gelince) bu dosya kaldırılacak.
public struct CmuxIDs: Equatable, Sendable {
    public var workspace: String
    public var surface: String?

    public init(workspace: String, surface: String?) {
        self.workspace = workspace
        self.surface = surface
    }
}

/// Aynı kullanıcıya ait bir sürecin ortam değişkenlerini `KERN_PROCARGS2` ile okur.
public enum ProcessEnv {
    public static func environment(pid: Int32) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        return parse(procargs: Array(buf.prefix(size)))
    }

    /// Düzen: Int32 argc, exec yolu, NUL dolgusu, argc adet argüman, ortam değişkenleri, boş dize.
    static func parse(procargs b: [UInt8]) -> [String: String] {
        guard b.count >= 4 else { return [:] }
        let argc = Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16 | Int(b[3]) << 24
        var i = 4
        func skipString() { while i < b.count, b[i] != 0 { i += 1 } }
        func skipNULs() { while i < b.count, b[i] == 0 { i += 1 } }
        skipString()
        skipNULs()
        for _ in 0..<argc {
            skipString()
            i += 1
        }
        var env: [String: String] = [:]
        while i < b.count, b[i] != 0 {
            let start = i
            skipString()
            if let s = String(bytes: b[start..<i], encoding: .utf8), let eq = s.firstIndex(of: "=") {
                env[String(s[..<eq])] = String(s[s.index(after: eq)...])
            }
            i += 1
        }
        return env
    }

    public static func cmuxIDs(pid: Int32) -> CmuxIDs? {
        environment(pid: pid).flatMap(cmuxIDs(env:))
    }

    static func cmuxIDs(env: [String: String]) -> CmuxIDs? {
        guard let ws = env["CMUX_WORKSPACE_ID"], !ws.isEmpty else { return nil }
        return CmuxIDs(workspace: ws, surface: env["CMUX_SURFACE_ID"].flatMap { $0.isEmpty ? nil : $0 })
    }
}
