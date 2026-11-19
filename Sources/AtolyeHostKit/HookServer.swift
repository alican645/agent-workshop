import Darwin
import Foundation

/// Atölye tarafı: `atolye-hook`'ların bağlandığı soket. Her bağlantı tek bir olaydır: istemci olayı yazıp
/// yazma ucunu kapatır; olay `onEvent`'e (sunucunun kuyruğunda) gider. `HookConnection.reply` ile cevap
/// yazılıp bağlantı kapanır; cevaplanmayan bağlantı bekler (hook terminaldeki menüyle yarışır).
public final class HookServer: @unchecked Sendable {
    private let socketPath: String
    private let queue = DispatchQueue(label: "atolye.hooks")
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var readers: [ObjectIdentifier: DispatchSourceRead] = [:]
    private let onEvent: @Sendable (Data, HookConnection) -> Void
    /// Bir olayın en büyük boyutu (büyük plan ya da Write girdisi sığsın).
    static let maxEvent = 16 * 1024 * 1024

    public init(socketPath: String, onEvent: @escaping @Sendable (Data, HookConnection) -> Void) {
        self.socketPath = socketPath
        self.onEvent = onEvent
    }

    public func start() throws {
        try queue.sync {
            try FileManager.default.createDirectory(atPath: (socketPath as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            unlink(socketPath)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            var addr = try HostServer.address(socketPath)
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard ok == 0, chmod(socketPath, 0o600) == 0, listen(fd, 32) == 0 else {
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
        }
    }

    public func stop() {
        queue.sync {
            listenSource?.cancel()
            listenSource = nil
            if listenFD >= 0 { close(listenFD) }
            listenFD = -1
            unlink(socketPath)
        }
    }

    private func acceptAll() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                close(fd)
                continue
            }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            read(fd)
        }
    }

    /// Olayı yazma ucu kapanana dek okur, sonra `onEvent`'e verir.
    private func read(_ fd: Int32) {
        var data = Data()
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let key = ObjectIdentifier(src)
        var buf = [UInt8](repeating: 0, count: 65536)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            while true {
                let n = Darwin.read(fd, &buf, buf.count)
                if n > 0 {
                    data.append(buf, count: n)
                    if data.count > Self.maxEvent { return self.finish(key, fd, nil) }
                } else if n == 0 {
                    return self.finish(key, fd, data)
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN {
                    return
                } else {
                    return self.finish(key, fd, nil)
                }
            }
        }
        readers[key] = src
        src.resume()
    }

    private func finish(_ key: ObjectIdentifier, _ fd: Int32, _ data: Data?) {
        readers.removeValue(forKey: key)?.cancel()
        guard let data, !data.isEmpty else { close(fd); return }
        onEvent(data, HookConnection(fd: fd, queue: queue))
    }
}

/// Bekleyen hook bağlantısı. `reply` bir kez çalışır; sonrakiler yok sayılır.
public final class HookConnection: @unchecked Sendable {
    private let fd: Int32
    private let queue: DispatchQueue
    private var closed = false

    init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
    }

    /// Cevabı yazar (nil: hiçbir şey yazmadan) ve bağlantıyı kapatır.
    public func reply(_ text: String?) {
        queue.async { [self] in
            guard !closed else { return }
            closed = true
            if let text {
                let d = Data(text.utf8)
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
                var off = 0
                while off < d.count {
                    let n = d.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + off, d.count - off) }
                    if n > 0 { off += n } else if errno != EINTR { break }
                }
            }
            close(fd)
        }
    }
}
