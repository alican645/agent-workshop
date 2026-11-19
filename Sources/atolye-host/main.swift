import AtolyeCore
import AtolyeHostKit
import Foundation

// Atölye'nin arka plan yardımcısı: terminalleri Atölye'den bağımsız yaşatır.
let path = ProcessInfo.processInfo.environment["ATOLYE_SOCKET"] ?? HostPaths.socket
try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                         withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
signal(SIGPIPE, SIG_IGN)
signal(SIGHUP, SIG_IGN)
// Çalışan kodun sürümü: dosya sonradan üstüne yazılsa da açılıştaki özet kalır.
let version = HostVersion.of(executable: Bundle.main.executablePath ?? CommandLine.arguments[0])
let server = HostServer(socketPath: path, idleExit: 600, onIdle: { exit(0) }, version: version)
do {
    try server.start()
} catch {
    FileHandle.standardError.write(Data("atolye-host: \(error)\n".utf8))
    exit(1)
}
dispatchMain()
