import Foundation
import Testing
@testable import AjanTakipCore

private func data(_ s: String) -> Data { Data(s.utf8) }

@Suite struct RegistryEntryTests {
    private let full = data(#"{"pid":42,"sessionId":"s1","cwd":"/x/erp","status":"waiting","waitingFor":"Bash","statusUpdatedAt":1000000000000,"updatedAt":5,"kind":"interactive"}"#)

    @Test func parsesFields() {
        let e = RegistryEntry.parse(full, profileID: "default")!
        #expect(e.pid == 42 && e.sessionID == "s1" && e.cwd == "/x/erp")
        #expect(e.status == .waiting && e.waitingFor == "Bash" && e.profileID == "default")
        #expect(e.statusSince == Date(timeIntervalSince1970: 1_000_000_000))
    }

    @Test func statusMapping() {
        for (raw, want) in [("busy", RegistryStatus.busy), ("idle", .idle), ("shell", .idle)] {
            let d = data(#"{"pid":1,"sessionId":"a","status":"\#(raw)","updatedAt":1}"#)
            #expect(RegistryEntry.parse(d, profileID: "p")?.status == want, "\(raw)")
        }
        let e = RegistryEntry.parse(data(#"{"pid":1,"sessionId":"a","updatedAt":2000}"#), profileID: "p")!
        #expect(e.status == .idle)
        #expect(e.statusSince == Date(timeIntervalSince1970: 2))
    }

    @Test func skipsNonChats() {
        #expect(RegistryEntry.parse(data(#"{"pid":1,"sessionId":"a","kind":"daemon"}"#), profileID: "p") == nil)
        #expect(RegistryEntry.parse(data(#"{"pid":1,"sessionId":"a","spare":true}"#), profileID: "p") == nil)
        #expect(RegistryEntry.parse(data(#"{"pid":1,"sessionId":"a","hostSessionId":"h"}"#), profileID: "p") == nil)
        #expect(RegistryEntry.parse(data(#"{"pid":1,"sessionId":"a","hostSessionId":""}"#), profileID: "p") != nil)
    }

    @Test func rejectsBroken() {
        #expect(RegistryEntry.parse(data(#"{"pid":1,"#), profileID: "p") == nil)
        #expect(RegistryEntry.parse(data(#"{"sessionId":"a"}"#), profileID: "p") == nil)
        #expect(RegistryEntry.parse(data(#"{"pid":1}"#), profileID: "p") == nil)
    }
}
