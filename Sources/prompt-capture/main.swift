import AtolyeHostKit
import Foundation
import SwiftTerm

// Geliştirici aracı: bir komutu 120x40 PTY'de çalıştırır, ekranını ScreenMirror ile izler ve
// belirtilen süre sonunda görünen satırları dosyaya yazar (gerçek Claude ekranlarını test verisi yapmak için).
//
//   prompt-capture [--registry <profilDizini>] <çıktı.txt> <bekleme-sn> -- <komut…>
//
// stdin'den gelen her satır PTY'ye `\r` ile yazılır; `@` ile başlayan satırlar sırayla işlenen yönergedir:
//   @sleep <sn>          bekle
//   @wait <sn> <metin>   ekranda <metin> görünene dek bekle (en çok <sn>)
//   @text <metin>        metni `\r` olmadan yaz
//   @key <ad>            tek tuş: enter space up down left right tab btab esc backspace
//   @snap <dosya>        o anki ekranı (ve --registry varsa kaydı) <dosya>'ya yaz
// --registry verilirse yalnız bu sürecin `<profilDizini>/sessions/<pid>.json` kaydı
// `<çıktı>.registry.json` dosyasına (JSON dizi) kopyalanır — başka oturumların kaydı alınmaz.
// Terminalin sorgu cevapları (imleç konumu vb.) sürece geri iletilir, gerçek bir terminal gibi.

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("prompt-capture: \(msg)\n".utf8))
    exit(2)
}

func note(_ msg: String) { FileHandle.standardError.write(Data("prompt-capture: \(msg)\n".utf8)) }

var args = Array(CommandLine.arguments.dropFirst())
var registryArg: String?
if args.first == "--registry" {
    guard args.count >= 2 else { fail("--registry bir dizin ister") }
    registryArg = args[1]
    args.removeFirst(2)
}
guard let sep = args.firstIndex(of: "--"), sep == 2, args.count > 3, let seconds = Double(args[1]), seconds >= 0 else {
    fail("kullanım: prompt-capture [--registry <profilDizini>] <çıktı.txt> <bekleme-sn> -- <komut…>")
}
let outPath = args[0]
let registryDir = registryArg
let command = Array(args[(sep + 1)...])

let queue = DispatchQueue(label: "prompt-capture")
final class Runner: LocalProcessDelegate, @unchecked Sendable {
    /// Yalnız `queue` üzerinde dokunulur.
    var mirror: ScreenMirror!
    /// PROMPT_CAPTURE_RAW=<dosya> verilirse ham çıktı oraya da yazılır (ayıklama için).
    let raw = ProcessInfo.processInfo.environment["PROMPT_CAPTURE_RAW"].flatMap { path -> FileHandle? in
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {}
    func processFailedToStart(_ source: LocalProcess, error: LocalProcessError) {
        fail("süreç başlamadı: \(error)")
    }
    func dataReceived(slice: ArraySlice<UInt8>) {
        raw?.write(Data(slice))
        mirror.feed(Data(slice))
    }
    func getWindowSize() -> winsize { winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0) }
}

let runner = Runner()
nonisolated(unsafe) let process = LocalProcess(delegate: runner, dispatchQueue: queue)
// Cevaplar `queue` üzerinde (beslemenin içinden) doğar; sürece doğrudan yazılır.
runner.mirror = ScreenMirror(cols: 120, rows: 40, onReply: { process.send(data: $0) })
var env = ProcessInfo.processInfo.environment
env["TERM"] = "xterm-256color"
env["COLORTERM"] = "truecolor"
process.startProcess(executable: command[0], args: Array(command.dropFirst()),
                     environment: env.map { "\($0.key)=\($0.value)" })

func send(_ s: String) { queue.async { process.send(data: ArraySlice(Array(s.utf8))) } }
func screenText() -> String { queue.sync { runner.mirror.lines().joined(separator: "\n") + "\n" } }

let keys: [String: String] = [
    "enter": "\r", "space": " ", "tab": "\t", "btab": "\u{1b}[Z", "esc": "\u{1b}", "backspace": "\u{7f}",
    "up": "\u{1b}[A", "down": "\u{1b}[B", "right": "\u{1b}[C", "left": "\u{1b}[D",
]

/// Ekranı ve (istenmişse) bu sürecin kaydını yazar.
func snapshot(to path: String) {
    do {
        try screenText().write(toFile: path, atomically: true, encoding: .utf8)
        if let registryDir {
            let file = ((registryDir as NSString).appendingPathComponent("sessions") as NSString)
                .appendingPathComponent("\(process.shellPid).json")
            var items: [Any] = []
            if let d = FileManager.default.contents(atPath: file), let j = try? JSONSerialization.jsonObject(with: d) {
                items.append(j)
            } else {
                note("kayıt bulunamadı: \(file)")
            }
            let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path + ".registry.json"))
        }
    } catch {
        fail("yazılamadı: \(error)")
    }
}

// stdin satırlarını sırayla işle (ayrı iş parçacığı; kapanırsa sessizce biter).
Thread.detachNewThread {
    while let line = readLine() {
        guard line.hasPrefix("@") else { send(line + "\r"); continue }
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let rest = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "@sleep":
            Thread.sleep(forTimeInterval: Double(rest) ?? 0)
        case "@wait":
            let p = rest.split(separator: " ", maxSplits: 1).map(String.init)
            let limit = Date().addingTimeInterval(Double(p.first ?? "") ?? 0)
            let needle = p.count > 1 ? p[1] : ""
            while !screenText().contains(needle) {
                if Date() > limit { note("beklenen metin gelmedi: \(needle)"); break }
                Thread.sleep(forTimeInterval: 0.2)
            }
        case "@text":
            send(rest)
        case "@key":
            guard let k = keys[rest] else { note("bilinmeyen tuş: \(rest)"); continue }
            send(k)
        case "@snap":
            snapshot(to: rest)
        default:
            note("bilinmeyen yönerge: \(line)")
        }
    }
}

Thread.sleep(forTimeInterval: seconds)
snapshot(to: outPath)
let pid = process.shellPid
queue.sync { process.terminate() }
// SIGTERM'i yok sayan bir çocuk kalmasın.
Thread.sleep(forTimeInterval: 0.5)
if pid > 0 { kill(pid, SIGKILL) }
exit(0)
