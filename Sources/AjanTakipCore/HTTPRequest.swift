import Foundation

/// Hook script'inden gelen tek HTTP isteğini ayrıştırmaya yetecek minimal ayrıştırıcı.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    /// Anahtarlar küçük harftir.
    public var headers: [String: String]
    public var body: Data

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

        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = sep.upperBound
        guard buffer.endIndex - bodyStart >= length else { return nil }
        return HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers,
                           body: Data(buffer[bodyStart..<(bodyStart + length)]))
    }
}
