import AjanTakipCore
import Darwin
import Foundation

/// Unix soketinden gelen istekleri karşılayan, terminalleri tutan sunucu. Tüm durum tek bir seri kuyrukta yaşar.
public final class HostServer: @unchecked Sendable {
    let queue = DispatchQueue(label: "atolye.host")
    private let socketPath: String
    private let idleExit: TimeInterval?
    private let onIdle: @Sendable () -> Void
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var terminals: [String: TerminalSession] = [:]
    private var order: [String] = []
    private var idleWork: DispatchWorkItem?

    /// Yalnız testler için: terminal türüne göre çalıştırılacak komut.
    var commandOverride: (@Sendable (TerminalKind) -> [String])?

    public init(socketPath: String, idleExit: TimeInterval?, onIdle: @escaping @Sendable () -> Void) {
        self.socketPath = socketPath
        self.idleExit = idleExit
        self.onIdle = onIdle
    }

    public func start() throws {
        try queue.sync {
            unlink(socketPath)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            var addr = try Self.address(socketPath)
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard ok == 0, chmod(socketPath, 0o600) == 0, listen(fd, 16) == 0 else {
                let e = errno
                close(fd)
                throw POSIXError(.init(rawValue: e) ?? .EIO)
            }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            listenFD = fd
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.acceptAll() }
            src.resume()
            listenSource = src
            scheduleIdleCheck()
        }
    }

    public func stop() {
        queue.sync {
            listenSource?.cancel()
            listenSource = nil
            if listenFD >= 0 { close(listenFD) }
            listenFD = -1
            unlink(socketPath)
            for c in clients.values { c.close() }
            clients = [:]
            for t in terminals.values { t.terminate() }
            terminals = [:]
            order = []
            idleWork?.cancel()
        }
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    // MARK: Bağlantılar

    private func acceptAll() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                close(fd)
                continue
            }
            let c = Client(fd: fd, queue: queue)
            let key = ObjectIdentifier(c)
            c.onFrame = { [weak self] body in self?.handle(body, from: key) }
            c.onClose = { [weak self] in self?.drop(key) }
            clients[key] = c
            c.start()
            scheduleIdleCheck()
        }
    }

    private func drop(_ key: ObjectIdentifier) {
        clients[key]?.close()
        clients[key] = nil
        for t in terminals.values { t.attached.remove(key) }
        scheduleIdleCheck()
    }

    private func send(_ e: HostEvent, to key: ObjectIdentifier) {
        clients[key]?.write(Frame.encode(e))
    }

    // MARK: İstekler

    private func handle(_ body: Data, from key: ObjectIdentifier) {
        guard let req = try? JSONDecoder().decode(HostRequest.self, from: body) else {
            send(.error("anlaşılmayan istek"), to: key)
            return
        }
        switch req {
        case .list:
            send(.terminals(order.compactMap { terminals[$0]?.info }), to: key)
        case let .create(kind, cwd, cols, rows, extra):
            create(kind: kind, cwd: cwd, cols: cols, rows: rows, extra: extra ?? [:], for: key)
        case let .attach(id):
            guard let t = terminals[id] else { return send(.error("terminal yok: \(id)"), to: key) }
            t.attached.insert(key)
            let old = t.buffer.contents
            if !old.isEmpty { send(.output(id: id, data: old), to: key) }
            if !t.info.running { send(.exited(id: id, code: t.info.exitCode), to: key) }
        case let .detach(id):
            terminals[id]?.attached.remove(key)
        case let .input(id, data):
            terminals[id]?.send(data)
        case let .resize(id, cols, rows):
            terminals[id]?.resize(cols: cols, rows: rows)
        case let .kill(id):
            if let t = terminals.removeValue(forKey: id) {
                order.removeAll { $0 == id }
                if t.info.running { t.terminate() }
            }
            scheduleIdleCheck()
        case .killAll:
            for t in terminals.values where t.info.running { t.terminate() }
            terminals = [:]
            order = []
            scheduleIdleCheck()
        }
    }

    static func command(for kind: TerminalKind) -> [String] {
        switch kind {
        case .claude: ["/bin/zsh", "-il", "-c", "claude; exec zsh -il"]
        case .shell: ["/bin/zsh", "-il"]
        }
    }

    private func create(kind: TerminalKind, cwd: String, cols: UInt16, rows: UInt16, extra: [String: String],
                        for key: ObjectIdentifier) {
        let id = UUID().uuidString
        var env = TerminalEnvironment.clean(ProcessInfo.processInfo.environment)
        env["ATOLYE_TERMINAL_ID"] = id
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["PWD"] = cwd
        env.merge(extra) { $1 }
        let info = TerminalInfo(id: id, cwd: cwd, title: kind == .claude ? "Claude" : "zsh", kind: kind, pid: 0,
                                running: true, exitCode: nil, lastOutputAt: nil)
        let t = TerminalSession(info: info, cols: cols, rows: rows, queue: queue,
                                onOutput: { [weak self] t, d in
                                    guard let self else { return }
                                    let frame = Frame.encode(HostEvent.output(id: t.info.id, data: d))
                                    for k in t.attached { self.clients[k]?.write(frame) }
                                },
                                onExit: { [weak self] t, code in
                                    guard let self else { return }
                                    let frame = Frame.encode(HostEvent.exited(id: t.info.id, code: code))
                                    for k in t.attached { self.clients[k]?.write(frame) }
                                })
        terminals[id] = t
        order.append(id)
        t.start(command: commandOverride?(kind) ?? Self.command(for: kind), environment: env)
        send(.created(t.info), to: key)
        scheduleIdleCheck()
    }

    // MARK: Boşta çıkış

    private func scheduleIdleCheck() {
        idleWork?.cancel()
        guard let idleExit, terminals.isEmpty, clients.isEmpty, listenFD >= 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.terminals.isEmpty, self.clients.isEmpty else { return }
            self.onIdle()
        }
        idleWork = work
        queue.asyncAfter(deadline: .now() + idleExit, execute: work)
    }
}

/// Bir istemci bağlantısı: okunan çerçeveleri iletir, yazılacakları sıraya koyup soket hazır oldukça yollar.
final class Client {
    let fd: Int32
    private let queue: DispatchQueue
    private var reader = Frame.Reader()
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var pending = Data()
    private var writing = false
    private var closed = false
    var onFrame: ((Data) -> Void)?
    var onClose: (() -> Void)?

    /// Okumayan bir istemci yüzünden bellek şişmesin.
    static let maxPending = 64 * 1024 * 1024

    init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    func start() {
        let r = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        r.setEventHandler { [weak self] in self?.readAvailable() }
        r.resume()
        readSource = r
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                for body in reader.push(Data(buf[0..<n])) { onFrame?(body) }
                if reader.broken { return fail() }
            } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
                return fail()
            } else {
                return
            }
        }
    }

    func write(_ d: Data) {
        guard !closed else { return }
        pending.append(d)
        if pending.count > Self.maxPending { return fail() }
        flush()
    }

    private func flush() {
        while !pending.isEmpty {
            let n = pending.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                pending.removeFirst(n)
            } else if n < 0 && (errno == EAGAIN || errno == EINTR) {
                if writeSource == nil {
                    let w = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
                    w.setEventHandler { [weak self] in self?.flush() }
                    w.resume()
                    writeSource = w
                }
                return
            } else {
                return fail()
            }
        }
        writeSource?.cancel()
        writeSource = nil
    }

    private func fail() {
        guard !closed else { return }
        onClose?()
    }

    func close() {
        guard !closed else { return }
        closed = true
        readSource?.cancel()
        writeSource?.cancel()
        readSource = nil
        writeSource = nil
        Darwin.close(fd)
    }
}
