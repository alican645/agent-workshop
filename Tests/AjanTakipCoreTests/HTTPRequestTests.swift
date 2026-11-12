import Foundation
import Testing
@testable import AjanTakipCore

@Suite struct HTTPRequestTests {
    @Test func completeRequest() throws {
        let raw = "POST /event HTTP/1.1\r\nContent-Length: 2\r\nX-Cmux-Workspace: W\r\n\r\n{}"
        let r = try #require(HTTPRequest.parse(Data(raw.utf8)))
        #expect(r.method == "POST")
        #expect(r.path == "/event")
        #expect(r.headers["x-cmux-workspace"] == "W")
        #expect(r.body == Data("{}".utf8))
    }

    @Test func incompleteHeadersNil() {
        #expect(HTTPRequest.parse(Data("POST /event HTTP/1.1\r\nContent-Length: 2\r\n".utf8)) == nil)
    }

    @Test func incompleteBodyNil() {
        #expect(HTTPRequest.parse(Data("POST /event HTTP/1.1\r\nContent-Length: 10\r\n\r\nabcd".utf8)) == nil)
    }

    @Test func noContentLengthEmptyBody() throws {
        let r = try #require(HTTPRequest.parse(Data("GET /health HTTP/1.1\r\nHost: x\r\n\r\n".utf8)))
        #expect(r.path == "/health")
        #expect(r.body.isEmpty)
    }
}
