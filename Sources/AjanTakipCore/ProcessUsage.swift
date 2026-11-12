import Foundation

/// Tek bir sürecin anlık örneği.
public struct ProcessSample: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    /// Çalıştırılabilir dosyanın tam yolu (okunamazsa nil).
    public var path: String?
    /// Toplam (user + system) CPU süresi, nanosaniye.
    public var cpuTimeNs: UInt64
    /// Activity Monitor "Bellek" (phys_footprint), bayt.
    public var memoryBytes: UInt64

    public init(pid: Int32, name: String, path: String?, cpuTimeNs: UInt64, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.path = path
        self.cpuTimeNs = cpuTimeNs
        self.memoryBytes = memoryBytes
    }
}

/// Çalışan bir uygulamanın paket yolu ve görünen adı.
public struct AppBundle: Equatable, Sendable {
    public var path: String
    public var name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

/// Bir programın (gruplanmış) kullanımı.
public struct AppUsage: Equatable, Sendable {
    public var name: String
    /// Bir çekirdeğe oranla CPU (1.0 = %100).
    public var cpu: Double
    public var memoryBytes: UInt64

    public init(name: String, cpu: Double, memoryBytes: UInt64) {
        self.name = name
        self.cpu = cpu
        self.memoryBytes = memoryBytes
    }
}

public struct UsageBreakdown: Equatable, Sendable {
    public var top: [AppUsage]
    public var otherCount: Int
    public var otherMemoryBytes: UInt64
    /// Tüm bilgisayara oranla (0…1).
    public var otherCPUShare: Double
}

public enum ProcessUsage {
    public enum Metric: Sendable { case cpu, memory }

    /// Sürüm numarasıyla adlandırılmış ikili dosyalar (ör. `…/claude/versions/2.1.322`)
    /// için aracın adını döner; diğerlerinde adı değiştirmez.
    public static func displayName(name: String, path: String?) -> String {
        guard let path, !name.isEmpty, name.allSatisfy({ $0.isNumber || $0 == "." }) else { return name }
        let parts = path.split(separator: "/")
        if let i = parts.lastIndex(of: "versions"), i > 0 { return String(parts[i - 1]) }
        return name
    }

    /// Süreç, bilinen bir uygulama paketinin içindeyse o uygulamanın adı (en içteki paket);
    /// değilse kendi adı.
    public static func groupName(path: String?, fallback: String, apps: [AppBundle]) -> String {
        guard let path else { return fallback }
        let owner = apps
            .filter { path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }
            .max { $0.path.count < $1.path.count }
        return owner?.name ?? fallback
    }

    /// İki örnek arasında programa göre gruplanmış CPU ve bellek kullanımı.
    /// Yeni başlayan veya sayacı geri giden süreç CPU'ya katkı yapmaz.
    public static func aggregate(previous: [ProcessSample], current: [ProcessSample],
                                 interval: TimeInterval, apps: [AppBundle]) -> [AppUsage] {
        let prevByPid = Dictionary(previous.map { ($0.pid, $0.cpuTimeNs) }, uniquingKeysWith: { a, _ in a })
        var cpuNs: [String: UInt64] = [:]
        var memory: [String: UInt64] = [:]
        for s in current {
            let name = groupName(path: s.path, fallback: displayName(name: s.name, path: s.path), apps: apps)
            var delta: UInt64 = 0
            if let prev = prevByPid[s.pid], s.cpuTimeNs >= prev { delta = s.cpuTimeNs - prev }
            cpuNs[name, default: 0] += delta
            memory[name, default: 0] += s.memoryBytes
        }
        let intervalNs = max(interval, 0.001) * 1_000_000_000
        return memory.keys.map { name in
            AppUsage(name: name, cpu: Double(cpuNs[name] ?? 0) / intervalNs, memoryBytes: memory[name] ?? 0)
        }
    }

    /// Programın tüm bilgisayara oranla CPU payı (çekirdek sayısına bölünür).
    public static func machineShare(_ u: AppUsage, cores: Int) -> Double {
        u.cpu / Double(max(cores, 1))
    }

    /// İlk `limit` program + geri kalanların özeti.
    /// CPU'da "diğer", toplam kullanımdan ilk programların payı düşülerek bulunur
    /// (okunamayan sistem süreçleri dahil); negatif olmaz.
    public static func breakdown(_ usage: [AppUsage], by metric: Metric, limit: Int = 10,
                                 cores: Int, totalCPU: Double?) -> UsageBreakdown {
        let sorted = top(usage, by: metric, limit: usage.count)
        let topItems = Array(sorted.prefix(limit))
        let rest = sorted.dropFirst(limit)
        let topShare = topItems.reduce(0) { $0 + machineShare($1, cores: cores) }
        return UsageBreakdown(
            top: topItems,
            otherCount: rest.count,
            otherMemoryBytes: rest.reduce(0) { $0 + $1.memoryBytes },
            otherCPUShare: max(0, (totalCPU ?? topShare) - topShare))
    }

    public static func top(_ usage: [AppUsage], by metric: Metric, limit: Int = 5) -> [AppUsage] {
        let sorted = usage.sorted { a, b in
            switch metric {
            case .cpu: a.cpu != b.cpu ? a.cpu > b.cpu : a.name < b.name
            case .memory: a.memoryBytes != b.memoryBytes ? a.memoryBytes > b.memoryBytes : a.name < b.name
            }
        }
        return Array(sorted.prefix(limit))
    }

    /// "18,2%"
    public static func cpuText(_ fraction: Double) -> String {
        oneDecimal(max(0, fraction) * 100) + "%"
    }

    /// "340 MB" / "1,3 GB"
    public static func memoryText(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return oneDecimal(gb) + " GB" }
        return "\(Int((Double(bytes) / 1_048_576).rounded())) MB"
    }

    static func oneDecimal(_ x: Double) -> String {
        let tenths = Int((x * 10).rounded())
        return "\(tenths / 10),\(tenths % 10)"
    }
}
