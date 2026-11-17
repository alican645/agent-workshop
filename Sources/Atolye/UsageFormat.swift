import AtolyeCore
import Foundation

/// Maliyet ve token sayısının kısa yazımı.
enum UsageFormat {
    static func usd(_ v: Double) -> String {
        if v <= 0 { return "$0" }
        if v < 0.01 { return "<$0.01" }
        return v < 100 ? String(format: "$%.2f", v) : String(format: "$%.0f", v)
    }

    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: String(format: "%.0fK", Double(n) / 1_000)
        default: "\(n)"
        }
    }

    static var note: String {
        L("Anthropic API liste fiyatıyla tahmini karşılık. Abonelikle kullanımda ayrıca ödenmez; hangi oturumun ne kadar iş yaptığını karşılaştırmak içindir. Önbellekten okunan token'lar dahil.")
    }
}
