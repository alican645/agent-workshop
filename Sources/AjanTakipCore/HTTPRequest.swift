import Foundation

/// Hook script'inden gelen tek HTTP isteğini ayrıştırmaya yetecek minimal ayrıştırıcı.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    /// Anahtarlar küçük harftir.
    public var headers: [String: String]
    public var body: Data

    /// Tarayıcıdan (web sayfasından) gelen istek mi? Hook script'i (curl) bu başlıkları göndermez.
    public var isFromBrowser: Bool {
        headers["origin"] != nil || headers["sec-fetch-site"] != nil || headers["sec-fetch-mode"] != nil
    }

    /// Tam bir istek yoksa (başlıklar veya gövde eksikse) `nil` döner.
    public static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let sep = buffer.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buffer[buffer.startIndex..<sep.lowerBound], encoding: .utf8)
        else { return nil }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        guard let length = Int(headers["content-length"] ?? "0"), length >= 0 else { return nil }
        let bodyStart = sep.upperBound
        guard buffer.endIndex - bodyStart >= length else { return nil }
        return HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers,
                           body: Data(buffer[bodyStart..<(bodyStart + length)]))
    }

    /// Başlıklar tamamlanmış ama Content-Length geçersizse (negatif / sayı değil) true.
    /// Eksik istek bozuk sayılmaz.
    public static func isMalformed(_ buffer: Data) -> Bool {
        guard let sep = buffer.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buffer[buffer.startIndex..<sep.lowerBound], encoding: .utf8)
        else { return false }
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":"),
                  line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
            else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard let n = Int(value), n >= 0 else { return true }
        }
        return false
    }
}
