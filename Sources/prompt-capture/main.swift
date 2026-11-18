import AtolyeHostKit
import Foundation
import SwiftTerm

// Geliştirici aracı: bir komutu 120x40 PTY'de çalıştırır, ekranını ScreenMirror ile izler ve
// belirtilen süre sonunda görünen satırları dosyaya yazar (gerçek Claude ekranlarını test verisi yapmak için).
//
//   prompt-capture [--registry <profilDizini>] <çıktı.txt> <bekleme-sn> -- <komut…>
//
// stdin'den gelen her satır PTY'ye `\r` ile yazılır. --registry verilirse yakalama anındaki
// `<profilDizini>/sessions/*.json` içerikleri `<çıktı>.registry.json` dosyasına kopyalanır.

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("prompt-capture: \(msg)\n".utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
var registryDir: String?
if args.first == "--registry" {
    guard args.count >= 2 else { fail("--registry bir dizin ister") }
    registryDir = args[1]
    args.removeFirst(2)
}
guard let sep = args.firstIndex(of: "--"), sep == 2, args.count > 3, let seconds = Double(args[1]), seconds >= 0 else {
    fail("kullanım: prompt-capture [--registry <profilDizini>] <çıktı.txt> <bekleme-sn> -- <komut…>")
}
let outPath = args[0]
let command = Array(args[(sep + 1)...])

let queue = DispatchQueue(label: "prompt-capture")
final class Runner: LocalProcessDelegate, @unchecked Sendable {
    /// Yalnız `queue` üzerinde dokunulur.
    let mirror = ScreenMirror(cols: 120, rows: 40)
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {}
    func processFailedToStart(_ source: LocalProcess, error: LocalProcessError) {
        fail("süreç başlamadı: \(error)")
    }
    func dataReceived(slice: ArraySlice<UInt8>) { mirror.feed(Data(slice)) }
    func getWindowSize() -> winsize { winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0) }
}

let runner = Runner()
nonisolated(unsafe) let process = LocalProcess(delegate: runner, dispatchQueue: queue)
var env = ProcessInfo.processInfo.environment
env["TERM"] = "xterm-256color"
env["COLORTERM"] = "truecolor"
process.startProcess(executable: command[0], args: Array(command.dropFirst()),
                     environment: env.map { "\($0.key)=\($0.value)" })

// stdin satırlarını PTY'ye ilet (ayrı iş parçacığı; kapanırsa sessizce biter).
Thread.detachNewThread {
    while let line = readLine() {
        queue.async { process.send(data: ArraySlice(Array((line + "\r").utf8))) }
    }
}

Thread.sleep(forTimeInterval: seconds)

let screen = queue.sync { runner.mirror.lines().joined(separator: "\n") + "\n" }
do {
    try screen.write(toFile: outPath, atomically: true, encoding: .utf8)
    if let registryDir {
        let dir = (registryDir as NSString).appendingPathComponent("sessions")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
        var items: [Any] = []
        for f in files {
            if let d = FileManager.default.contents(atPath: (dir as NSString).appendingPathComponent(f)),
               let j = try? JSONSerialization.jsonObject(with: d) { items.append(j) }
        }
        let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: outPath + ".registry.json"))
    }
} catch {
    fail("yazılamadı: \(error)")
}
queue.sync { process.terminate() }
exit(0)
