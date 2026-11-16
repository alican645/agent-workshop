import AjanTakipCore
import Darwin
import Foundation

/// Atölye tarafı: yardımcıya bağlanır (gerekirse başlatır), istek yollar, olayları `onEvent` ile iletir.
/// `onEvent` istemcinin kendi kuyruğunda çağrılır.
public final class HostClient: @unchecked Sendable {
    public static let disconnected = "bağlantı koptu"

    private let socketPath: String
    private let hostExecutable: String?
    private let onEvent: @Sendable (HostEvent) -> Void
    private let queue = DispatchQueue(label: "atolye.client")
    private let writeLock = NSLock()
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var reader = Frame.Reader()
    private var closedByUs = false
    /// Bu istemcinin başlattığı yardımcının süreç kimliği (başlatmadıysa nil).
    public private(set) var spawnedPID: pid_t?

    public init(socketPath: String, hostExecutable: String?, onEvent: @escaping @Sendable (HostEvent) -> Void) {
        self.socketPath = socketPath
        self.hostExecutable = hostExecutable
        self.onEvent = onEvent
    }

    public func connect() throws {
        if let s = Self.dial(socketPath) {
            attach(s)
            return
        }
        guard let hostExecutable else { throw POSIXError(.ECONNREFUSED) }
        unlink(socketPath) // bayat soket
        spawnedPID = try Self.spawn(hostExecutable, socketPath: socketPath)
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            if let s = Self.dial(socketPath) {
                attach(s)
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw POSIXError(.ETIMEDOUT)
    }

    public func send(_ r: HostRequest) {
        let d = Frame.encode(r)
        writeLock.withLock {
            guard fd >= 0 else { return }
            var off = 0
            while off < d.count {
                let n = d.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + off, d.count - off) }
                if n > 0 { off += n } else if errno != EINTR { return }
            }
        }
    }

    public func close() {
        queue.sync {
            closedByUs = true
            source?.cancel()
            source = nil
        }
        writeLock.withLock {
            if fd >= 0 { Darwin.close(fd) }
            fd = -1
        }
    }

    private func attach(_ s: Int32) {
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        writeLock.withLock { fd = s }
        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: queue)
        src.setEventHandler { [weak self] in self?.readAvailable(s) }
        src.resume()
        source = src
    }

    private func readAvailable(_ s: Int32) {
        var buf = [UInt8](repeating: 0, count: 262_144)
        let n = read(s, &buf, buf.count)
        if n > 0 {
            for body in reader.push(Data(buf[0..<n])) {
                if let e = try? JSONDecoder().decode(HostEvent.self, from: body) { onEvent(e) }
            }
            if !reader.broken { return }
        } else if n < 0 && (errno == EAGAIN || errno == EINTR) {
            return
        }
        source?.cancel()
        source = nil
        if !closedByUs { onEvent(.error(Self.disconnected)) }
    }

    static func dial(_ path: String) -> Int32? {
        guard var addr = try? HostServer.address(path) else { return nil }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return nil }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok == 0 { return s }
        Darwin.close(s)
        return nil
    }

    /// Yardımcıyı kendi oturum grubunda, Atölye'den bağımsız başlatır.
    static func spawn(_ exe: String, socketPath: String) throws -> pid_t {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd: Int32 in [0, 1, 2] {
            posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0)
        }
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CMUX_") }
        env["ATOLYE_SOCKET"] = socketPath
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let argv = [strdup(exe), nil]
        defer {
            envp.forEach { free($0) }
            argv.forEach { free($0) }
        }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, exe, &actions, &attr, argv, envp)
        guard rc == 0 else { throw POSIXError(.init(rawValue: rc) ?? .EIO) }
        return pid
    }
}
