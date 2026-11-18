import Darwin

/// Bir sürecin bütün torunları (süreç grubundan bağımsız). Terminal kapanırken kabuğun iş denetimiyle
/// ayrı gruba koyduğu programları (ör. `claude`) da bulmak için.
public enum ProcessTree {
    static func allParents() -> [pid_t: pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        let count = size / MemoryLayout<kinfo_proc>.stride + 16
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        size = count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [:] }
        var out: [pid_t: pid_t] = [:]
        for p in procs.prefix(size / MemoryLayout<kinfo_proc>.stride) {
            out[p.kp_proc.p_pid] = p.kp_eproc.e_ppid
        }
        return out
    }

    public static func descendants(of root: pid_t) -> [pid_t] {
        guard root > 0 else { return [] }
        let parents = allParents()
        var children: [pid_t: [pid_t]] = [:]
        for (pid, ppid) in parents { children[ppid, default: []].append(pid) }
        var out: [pid_t] = []
        var stack = children[root] ?? []
        while let p = stack.popLast() {
            out.append(p)
            stack += children[p] ?? []
        }
        return out
    }
}
