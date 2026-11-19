import Foundation

/// Atölye ile arka plan yardımcısı (`atolye-host`) arasındaki mesajlar.
public enum TerminalKind: String, Codable, Sendable {
    case claude, shell
}

public struct TerminalInfo: Codable, Equatable, Sendable {
    public var id: String
    public var cwd: String
    public var title: String
    public var kind: TerminalKind
    public var pid: Int32
    public var running: Bool
    public var exitCode: Int32?
    public var lastOutputAt: Date?
    /// Claude'a verilen argümanlar (ör. `--resume <id>`). Eski yardımcı bu alanı bilmez, hep nil döner.
    public var args: [String]? = nil

    public init(id: String, cwd: String, title: String, kind: TerminalKind, pid: Int32, running: Bool,
                exitCode: Int32?, lastOutputAt: Date?, args: [String]? = nil) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.kind = kind
        self.pid = pid
        self.running = running
        self.exitCode = exitCode
        self.lastOutputAt = lastOutputAt
        self.args = args
    }
}

public enum HostRequest: Codable, Equatable, Sendable {
    case list
    /// `env`: terminale eklenecek ortam (ör. Claude profili için CLAUDE_CONFIG_DIR).
    /// `args`: Claude terminalinde `claude`'a eklenecek argümanlar.
    case create(kind: TerminalKind, cwd: String, cols: UInt16, rows: UInt16, env: [String: String]? = nil,
                args: [String]? = nil)
    case attach(id: String)
    case detach(id: String)
    case input(id: String, data: Data)
    case resize(id: String, cols: UInt16, rows: UInt16)
    case kill(id: String)
    case killAll
    /// Terminalin görünen ekranını ister (yalnız Claude terminali). Eski yardımcı `.error` döner.
    case screen(id: String)
}

public enum HostEvent: Codable, Equatable, Sendable {
    case terminals([TerminalInfo])
    case created(TerminalInfo)
    case output(id: String, data: Data)
    case exited(id: String, code: Int32?)
    case error(String)
    case screen(id: String, lines: [String], cursorRow: Int)
}

/// Çerçeve: 4 bayt büyük-endian uzunluk + JSON gövde.
public enum Frame {
    public static let maxLength = 16 * 1024 * 1024

    public static func encode<T: Encodable>(_ v: T) -> Data {
        let body = (try? JSONEncoder().encode(v)) ?? Data()
        var len = UInt32(body.count).bigEndian
        return Data(bytes: &len, count: 4) + body
    }

    /// Gelen baytları biriktirir, tamamlanan gövdeleri döner. Saçma uzunlukta `broken` olur ve durur.
    public struct Reader: Sendable {
        private var buf = Data()
        public private(set) var broken = false

        public init() {}

        public mutating func push(_ d: Data) -> [Data] {
            guard !broken else { return [] }
            buf.append(d)
            var out: [Data] = []
            while buf.count >= 4 {
                let s = buf.startIndex
                let len = Int(buf[s]) << 24 | Int(buf[s + 1]) << 16 | Int(buf[s + 2]) << 8 | Int(buf[s + 3])
                guard len <= Frame.maxLength else {
                    broken = true
                    buf = Data()
                    return out
                }
                guard buf.count >= 4 + len else { break }
                out.append(Data(buf[(s + 4)..<(s + 4 + len)]))
                buf = Data(buf[(s + 4 + len)...])
            }
            return out
        }
    }
}
