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

@Suite struct HTTPRequestRobustnessTests {
    @Test func negativeContentLengthRejected() {
        let raw = "POST /event HTTP/1.1\r\nContent-Length: -5\r\n\r\n{}"
        #expect(HTTPRequest.parse(Data(raw.utf8)) == nil)
        #expect(HTTPRequest.isMalformed(Data(raw.utf8)))
    }

    @Test func garbageContentLengthRejected() {
        let raw = "POST /event HTTP/1.1\r\nContent-Length: abc\r\n\r\n{}"
        #expect(HTTPRequest.parse(Data(raw.utf8)) == nil)
        #expect(HTTPRequest.isMalformed(Data(raw.utf8)))
    }

    @Test func incompleteIsNotMalformed() {
        #expect(!HTTPRequest.isMalformed(Data("POST /event HTTP/1.1\r\nContent-Length: 10\r\n\r\nab".utf8)))
    }
}

@Suite struct BrowserOriginTests {
    @Test func requestWithOriginIsFromBrowser() throws {
        let raw = "POST /event HTTP/1.1\r\nOrigin: https://evil.example\r\nContent-Length: 2\r\n\r\n{}"
        #expect(try #require(HTTPRequest.parse(Data(raw.utf8))).isFromBrowser)
    }

    @Test func requestWithSecFetchSiteIsFromBrowser() throws {
        let raw = "POST /event HTTP/1.1\r\nSec-Fetch-Site: cross-site\r\nContent-Length: 2\r\n\r\n{}"
        #expect(try #require(HTTPRequest.parse(Data(raw.utf8))).isFromBrowser)
    }

    @Test func curlRequestIsNotFromBrowser() throws {
        let raw = "POST /event HTTP/1.1\r\nHost: 127.0.0.1\r\nUser-Agent: curl/8\r\nContent-Length: 2\r\n\r\n{}"
        #expect(try !#require(HTTPRequest.parse(Data(raw.utf8))).isFromBrowser)
    }
}
