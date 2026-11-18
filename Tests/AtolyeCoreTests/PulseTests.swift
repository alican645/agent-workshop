import Testing
@testable import AtolyeCore

@Suite struct PulseTests {
    @Test func newAlertStartsPulseWhenCollapsed() {
        #expect(Pulse.next(current: nil, alert: .attention, waitingCount: 1, expanded: false) == .attention)
        #expect(Pulse.next(current: nil, alert: .attention, waitingCount: 1, expanded: true) == nil)
    }

    @Test func attentionClearsWhenNothingWaits() {
        #expect(Pulse.next(current: .attention, alert: nil, waitingCount: 0, expanded: false) == nil)
        #expect(Pulse.next(current: .attention, alert: nil, waitingCount: 1, expanded: false) == .attention)
    }

    @Test func finishedPulseStaysUntilExpanded() {
        #expect(Pulse.next(current: .finished, alert: nil, waitingCount: 0, expanded: false) == .finished)
    }
}
