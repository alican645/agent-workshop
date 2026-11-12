import Testing
@testable import AjanTakipCore

@Suite struct DurationFormatTests {
    @Test(arguments: [
        (0.0, "0 sn"), (12, "12 sn"), (59, "59 sn"), (60, "1 dk"), (3599, "59 dk"), (7200, "2 sa"),
    ])
    func short(_ seconds: Double, _ expected: String) {
        #expect(DurationFormat.short(seconds) == expected)
    }
}
