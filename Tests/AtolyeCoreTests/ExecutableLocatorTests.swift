import Testing
@testable import AtolyeCore

@Suite struct ExecutableLocatorTests {
    @Test func prefersBundledThenPathThenWellKnownDirs() {
        let exists: Set<String> = ["/opt/homebrew/bin/cmux"]
        let found = ExecutableLocator.find("cmux", preferred: ["/Applications/cmux.app/Contents/Resources/bin/cmux"],
                                           pathEnv: "/usr/bin:/bin", isExecutable: { exists.contains($0) })
        #expect(found == "/opt/homebrew/bin/cmux")
    }

    @Test func bundledWins() {
        let all: Set<String> = ["/b/cmux", "/opt/homebrew/bin/cmux"]
        #expect(ExecutableLocator.find("cmux", preferred: ["/b/cmux"], pathEnv: nil, isExecutable: { all.contains($0) }) == "/b/cmux")
    }

    @Test func pathEnvBeforeWellKnown() {
        let all: Set<String> = ["/x/cmux", "/usr/local/bin/cmux"]
        #expect(ExecutableLocator.find("cmux", preferred: [], pathEnv: "/x", isExecutable: { all.contains($0) }) == "/x/cmux")
    }

    @Test func notFound() {
        #expect(ExecutableLocator.find("cmux", preferred: [], pathEnv: "/x", isExecutable: { _ in false }) == nil)
    }
}
