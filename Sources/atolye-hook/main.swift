import Darwin
import Foundation

// Claude Code hook'u: stdin'deki olayı Agent Workshop'un hook soketine iletir.
// PermissionRequest'te Atölye'nin cevabını bekler ve stdout'a yazar (balondan verilen cevap). Atölye
// çalışmıyorsa, soket yoksa ya da cevap gelmeden bağlantı kapanırsa hiçbir şey yazmadan 0 ile çıkar:
// Claude Code o zaman her zamanki gibi terminalde sorar. Terminalden verilen cevap her zaman geçerlidir.
//
// Protokol: istemci olayın tamamını yazar ve yazma ucunu kapatır; sunucu cevabı (ya da hiçbir şeyi)
// yazıp bağlantıyı kapatır.

// ATOLYE_HOOK_SOCKET yalnız denemeler içindir.
let socketPath = ProcessInfo.processInfo.environment["ATOLYE_HOOK_SOCKET"]
    ?? FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Atolye/hooks.sock"

let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty else { exit(0) }
let waits = (try? JSONSerialization.jsonObject(with: input) as? [String: Any])?["hook_event_name"] as? String
    == "PermissionRequest"

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { exit(0) }
withUnsafeMutableBytes(of: &addr.sun_path) { raw in
    raw.copyBytes(from: pathBytes)
    raw[pathBytes.count] = 0
}
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
var on: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard connected == 0 else { exit(0) }

var off = 0
while off < input.count {
    let n = input.withUnsafeBytes { write(fd, $0.baseAddress! + off, input.count - off) }
    if n > 0 { off += n } else if errno != EINTR { exit(0) }
}
shutdown(fd, SHUT_WR)
guard waits else { exit(0) }

var reply = Data()
var buf = [UInt8](repeating: 0, count: 65536)
while true {
    let n = read(fd, &buf, buf.count)
    if n > 0 { reply.append(buf, count: n) } else if n < 0 && errno == EINTR { continue } else { break }
}
if !reply.isEmpty { FileHandle.standardOutput.write(reply) }
exit(0)
