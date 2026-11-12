import Foundation

/// Tüm çekirdeklerin toplam CPU tick sayaçları (host_statistics HOST_CPU_LOAD_INFO).
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    var busy: UInt64 { user &+ system &+ nice }
    var total: UInt64 { busy &+ idle }
}

/// Activity Monitor'deki "Kullanılan Bellek" hesabı için ham sayfa sayıları.
public struct MemorySample: Equatable, Sendable {
    public var totalBytes: UInt64
    public var pageSize: UInt64
    public var internalPages: UInt64
    public var purgeablePages: UInt64
    public var wiredPages: UInt64
    public var compressedPages: UInt64
    /// Dosya önbelleği sayfaları (kullanılan sayılmaz).
    public var externalPages: UInt64

    public init(totalBytes: UInt64, pageSize: UInt64, internalPages: UInt64, purgeablePages: UInt64,
                wiredPages: UInt64, compressedPages: UInt64, externalPages: UInt64 = 0) {
        self.totalBytes = totalBytes
        self.pageSize = pageSize
        self.internalPages = internalPages
        self.purgeablePages = purgeablePages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
        self.externalPages = externalPages
    }

    /// Uygulama belleği (internal − purgeable).
    public var appBytes: UInt64 { (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * pageSize }
    public var wiredBytes: UInt64 { wiredPages * pageSize }
    public var compressedBytes: UInt64 { compressedPages * pageSize }
    public var usedBytes: UInt64 { appBytes + wiredBytes + compressedBytes }
    /// Önbellek (dosya + temizlenebilir); gerektiğinde boşaltılır.
    public var cacheBytes: UInt64 { (externalPages + purgeablePages) * pageSize }

    /// (uygulama belleği + wired + sıkıştırılmış) / toplam, 0…1
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let used = Double(app + wiredPages + compressedPages) * Double(pageSize)
        return min(1, max(0, used / Double(totalBytes)))
    }
}

public enum LoadLevel: Equatable, Sendable {
    case normal, high, critical

    /// < %60 normal, %60–85 yüksek, > %85 kritik
    public init(fraction: Double) {
        if fraction < 0.60 { self = .normal } else if fraction <= 0.85 { self = .high } else { self = .critical }
    }
}

public enum SystemStats {
    /// İki örnek arasındaki CPU kullanım oranı (0…1). Sayaç geri gittiyse veya fark yoksa 0.
    public static func cpuUsage(previous: CPUTicks, current: CPUTicks) -> Double {
        guard current.total > previous.total, current.busy >= previous.busy else { return 0 }
        return Double(current.busy - previous.busy) / Double(current.total - previous.total)
    }

    /// "9,7 / 16 GB · 61%"
    public static func memoryHeader(_ m: MemorySample) -> String {
        let totalGB = Int((Double(m.totalBytes) / 1_073_741_824).rounded())
        let usedGB = ProcessUsage.oneDecimal(Double(m.usedBytes) / 1_073_741_824)
        return "\(usedGB) / \(totalGB) GB · \(percentText(m.usedFraction))"
    }

    public static func percentText(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }
}
