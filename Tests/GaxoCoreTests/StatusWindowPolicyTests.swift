import Testing
@testable import GaxoCore

@Suite struct StatusWindowPolicyTests {
    @Test func openWindowHidesWhileMirroringAndReturns() {
        var policy = StatusWindowPolicy()
        #expect(policy.sessionStarted(windowVisible: true) == true, "hide it")
        #expect(policy.sessionEnded() == true, "bring it back")
        #expect(policy.sessionEnded() == false, "only once")
    }

    @Test func closedWindowStaysClosed() {
        var policy = StatusWindowPolicy()
        #expect(policy.sessionStarted(windowVisible: false) == false)
        #expect(policy.sessionEnded() == false, "user runs Gaxo from the menu bar: don't pop it up")
    }

    /// Mirroring can be reported again (e.g. after the code screen); the window is already hidden by then.
    @Test func repeatedStartDoesNotForgetTheWindow() {
        var policy = StatusWindowPolicy()
        let hideFirst = policy.sessionStarted(windowVisible: true)
        let hideAgain = policy.sessionStarted(windowVisible: false)
        let showAtEnd = policy.sessionEnded()
        #expect(hideFirst)
        #expect(!hideAgain)
        #expect(showAtEnd)
    }

    @Test func endWithoutStartDoesNothing() {
        var policy = StatusWindowPolicy()
        #expect(policy.sessionEnded() == false)
    }
}
