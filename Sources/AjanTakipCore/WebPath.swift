import Foundation

/// `atolye://app/<yol>` isteğinin dosyası: `robots/…` kendi robot klasöründen, gerisi Web klasöründen.
/// Kökün dışına çıkan yollar reddedilir.
public enum WebPath {
    public static func resolve(_ rel: String, webRoot: URL, robotsRoot: URL) -> URL? {
        let prefix = "robots/"
        let (root, sub) = rel.hasPrefix(prefix)
            ? (robotsRoot.standardizedFileURL, String(rel.dropFirst(prefix.count)))
            : (webRoot.standardizedFileURL, rel.isEmpty ? "index.html" : rel)
        let file = root.appendingPathComponent(sub).standardizedFileURL
        return file.path.hasPrefix(root.path + "/") ? file : nil
    }
}
