import AjanTakipCore
import AppKit
import Darwin

/// Kullanıcının okuyabildiği tüm süreçlerin CPU süresi ve bellek kullanımını okur.
/// (Root/sistem süreçleri macOS tarafından gizlenir ve atlanır.)
enum ProcessSampler {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func sample() -> [ProcessSample] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }

        var result: [ProcessSample] = []
        result.reserveCapacity(Int(count))
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var info = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard rc == 0 else { continue }
            let ticks = info.ri_user_time &+ info.ri_system_time
            let ns = ticks &* UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
            result.append(ProcessSample(pid: pid, name: name(of: pid), path: path(of: pid),
                                        cpuTimeNs: ns, memoryBytes: info.ri_phys_footprint))
        }
        return result
    }

    /// Normal ve accessory uygulamaların paketleri (yardımcı süreçleri gruplamak için).
    @MainActor
    static func runningApps() -> [AppBundle] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy != .prohibited, let url = app.bundleURL else { return nil }
            return AppBundle(path: url.path, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent)
        }
    }

    private static func name(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let n = proc_name(pid, &buf, UInt32(buf.count))
        return n > 0 ? cString(buf) : "pid \(pid)"
    }

    private static func path(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? cString(buf) : nil
    }

    private static func cString(_ buf: [CChar]) -> String {
        let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
