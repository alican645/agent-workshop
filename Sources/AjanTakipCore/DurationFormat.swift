import Foundation

public enum DurationFormat {
    /// "12 sn", "3 dk", "2 sa"
    public static func short(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s) sn" }
        if s < 3600 { return "\(s / 60) dk" }
        return "\(s / 3600) sa"
    }
}
