import AtolyeCore
import Foundation
import SwiftTerm

/// Yardımcının tuttuğu tek bir terminal: PTY + süreç + son çıktının tamponu.
/// Tüm geri çağrılar sunucunun seri kuyruğunda gelir.
final class TerminalSession: LocalProcessDelegate {
    static let bufferCapacity = 2_097_152

    var info: TerminalInfo
    var buffer = RingBuffer(capacity: TerminalSession.bufferCapacity)
    var attached = Set<ObjectIdentifier>()
    /// Görünen ekranın aynası; yalnız Claude terminalinde (seçenek menülerini okumak için).
    let mirror: ScreenMirror?
    private var process: LocalProcess!
    private var size: winsize
    private let onOutput: (TerminalSession, Data) -> Void
    private let onExit: (TerminalSession, Int32?) -> Void

    init(info: TerminalInfo, cols: UInt16, rows: UInt16, queue: DispatchQueue,
         onOutput: @escaping (TerminalSession, Data) -> Void, onExit: @escaping (TerminalSession, Int32?) -> Void) {
        self.info = info
        mirror = info.kind == .claude ? ScreenMirror(cols: Int(cols), rows: Int(rows)) : nil
        size = winsize(ws_row: max(rows, 1), ws_col: max(cols, 1), ws_xpixel: 0, ws_ypixel: 0)
        self.onOutput = onOutput
        self.onExit = onExit
        process = LocalProcess(delegate: self, dispatchQueue: queue)
    }

    func start(command: [String], environment: [String: String]) {
        let env = environment.map { "\($0.key)=\($0.value)" }
        process.startProcess(executable: command[0], args: Array(command.dropFirst()), environment: env,
                             currentDirectory: info.cwd)
        info.pid = process.shellPid
    }

    func send(_ d: Data) {
        guard info.running else { return }
        process.send(data: ArraySlice([UInt8](d)))
    }

    func resize(cols: UInt16, rows: UInt16) {
        size = winsize(ws_row: max(rows, 1), ws_col: max(cols, 1), ws_xpixel: 0, ws_ypixel: 0)
        process.updateWindowSize(&size)
        mirror?.resize(cols: Int(size.ws_col), rows: Int(size.ws_row))
    }

    func terminate() {
        let pid = process.shellPid
        // Kabuk ölmeden önce torunlarını topla: zsh iş denetimiyle claude'u ayrı süreç grubuna koyar ve
        // claude SIGHUP'ı yok sayar; yalnız gruba sinyal gönderilirse terminalsiz asılı kalıyordu.
        let kids = ProcessTree.descendants(of: pid)
        process.terminate()
        if pid > 0 { Darwin.kill(-pid, SIGHUP) }
        for k in kids {
            Darwin.kill(k, SIGHUP)
            Darwin.kill(k, SIGTERM)
        }
        // Kabuk da (ör. tuzak kurmuş zsh) direnirse zorla bitir; oturum süreç bitene kadar tutulur.
        let stubborn = kids + (pid > 0 ? [pid] : [])
        guard !stubborn.isEmpty else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            for k in stubborn where Darwin.kill(k, 0) == 0 { Darwin.kill(k, SIGKILL) }
        }
    }

    // MARK: LocalProcessDelegate

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        info.running = false
        info.exitCode = exitCode
        onExit(self, exitCode)
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        let d = Data(slice)
        buffer.append(d)
        mirror?.feed(d)
        info.lastOutputAt = Date()
        onOutput(self, d)
    }

    func getWindowSize() -> winsize { size }
}
