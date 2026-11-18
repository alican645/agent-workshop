import Foundation

/// Bir robotun dikkat isteyen durum değişimi (bildirim için).
public struct RobotAlert: Equatable, Sendable {
    public enum Kind: Sendable { case waiting, done }
    public var robotID: String
    public var kind: Kind
    public var zoneName: String
    public var label: String
    /// Beklenen şey (izin istenen araç vb.).
    public var detail: String?
}

extension Workshop {
    /// Önceki görüntüde de olan robotlardan beklemeye ya da bitti durumuna yeni geçenler.
    public static func alerts(from old: WorkshopSnapshot?, to new: WorkshopSnapshot) -> [RobotAlert] {
        guard let old else { return [] }
        let before = Dictionary(old.zones.flatMap { $0.robots.map { ($0.id, $0.state) } }, uniquingKeysWith: { a, _ in a })
        var out: [RobotAlert] = []
        for z in new.zones {
            for r in z.robots {
                guard let prev = before[r.id], prev != r.state else { continue }
                let kind: RobotAlert.Kind? = r.state == "waiting" ? .waiting : r.state == "done" ? .done : nil
                if let kind {
                    out.append(RobotAlert(robotID: r.id, kind: kind, zoneName: z.name, label: r.label, detail: r.waitingFor))
                }
            }
        }
        return out
    }

    /// Seni bekleyen ve bir Atölye terminalinde çalışan oturumların terminalleri.
    public static func waitingTerminals(_ s: WorkshopSnapshot) -> Set<String> {
        Set(s.zones.flatMap { $0.robots.filter { $0.state == "waiting" }.compactMap(\.terminal) })
    }

    public static func waitingCount(_ s: WorkshopSnapshot) -> Int {
        s.zones.reduce(0) { $0 + $1.robots.filter { $0.state == "waiting" }.count }
    }
}
