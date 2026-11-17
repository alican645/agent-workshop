import Foundation
import Testing
@testable import AjanTakipCore

@Suite struct WebPathTests {
    let web = URL(fileURLWithPath: "/tmp/w/Web")
    let robots = URL(fileURLWithPath: "/tmp/a/robots")

    @Test func emptyPathIsIndex() {
        #expect(WebPath.resolve("", webRoot: web, robotsRoot: robots)?.path == "/tmp/w/Web/index.html")
    }
    @Test func webFile() {
        #expect(WebPath.resolve("models/x.glb", webRoot: web, robotsRoot: robots)?.path == "/tmp/w/Web/models/x.glb")
    }
    @Test func robotFile() {
        #expect(WebPath.resolve("robots/abc.glb", webRoot: web, robotsRoot: robots)?.path == "/tmp/a/robots/abc.glb")
    }
    @Test func robotEscapeRejected() {
        #expect(WebPath.resolve("robots/../../etc/passwd", webRoot: web, robotsRoot: robots) == nil)
    }
    @Test func webEscapeRejected() {
        #expect(WebPath.resolve("../secret", webRoot: web, robotsRoot: robots) == nil)
    }
}
