import AjanTakipCore
import Foundation
import SwiftTerm

/// Yardımcının tuttuğu tek bir terminal: PTY + süreç + son çıktının tamponu.
/// Tüm geri çağrılar sunucunun seri kuyruğunda gelir.
final class TerminalSession: LocalProcessDelegate {
    static let bufferCapacity = 2_097_152

    var info: TerminalInfo
    var buffer = RingBuffer(capacity: TerminalSession.bufferCapacity)
    var attached = Set<ObjectIdentifier>()
    private var process: LocalProcess!
    private var size: winsize
    private let onOutput: (TerminalSession, Data) -> Void
    private let onExit: (TerminalSession, Int32?) -> Void

    init(info: TerminalInfo, cols: UInt16, rows: UInt16, queue: DispatchQueue,
         onOutput: @escaping (TerminalSession, Data) -> Void, onExit: @escaping (TerminalSession, Int32?) -> Void) {
        self.info = info
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
    }

    func terminate() {
        let pid = process.shellPid
        process.terminate()
        // Kabuğun çocukları (claude) da gitsin: süreç grubuna da sinyal.
        if pid > 0 { Darwin.kill(-pid, SIGHUP) }
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
        info.lastOutputAt = Date()
        onOutput(self, d)
    }

    func getWindowSize() -> winsize { size }
}
