import Darwin
import Foundation

/// Yardımcıyı (ve içindeki terminal süreçlerini) bitirir. Claude SIGHUP'ı yok sayar ve kendi süreç grubundadır;
/// yalnız yardımcı öldürülürse terminalsiz yaşamaya devam eder, `--resume` de aynı oturumun ikinci kopyasını açardı.
public enum HostTeardown {
    /// Önce yardımcının bütün torunları toplanır. `graceful`: yardımcıya `shutdown` gönderildi, kendisi kapatıyor;
    /// değilse torunlara SIGHUP+SIGTERM, yardımcıya SIGTERM. `grace` sn içinde bitmeyenlere SIGKILL.
    /// Hepsi bittiyse true.
    public static func terminate(helper pid: pid_t, graceful: Bool, grace: TimeInterval = 3.5) async -> Bool {
        guard pid > 0 else { return true }
        let kids = ProcessTree.descendants(of: pid)
        if !graceful {
            for k in kids { Darwin.kill(k, SIGHUP); Darwin.kill(k, SIGTERM) }
            Darwin.kill(pid, SIGTERM)
        }
        let all = kids + [pid]
        if await waitGone(all, timeout: grace) { return true }
        for k in all where alive(k) { Darwin.kill(k, SIGKILL) }
        return await waitGone(all, timeout: 1.5)
    }

    /// Süreç yaşıyor mu (zombi sayılmaz).
    static func alive(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard n == Int32(MemoryLayout<proc_bsdinfo>.size) else { return false }
        return info.pbi_status != UInt32(SZOMB)
    }

    private static func waitGone(_ pids: [pid_t], timeout: TimeInterval) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if !pids.contains(where: alive) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !pids.contains(where: alive)
    }
}
