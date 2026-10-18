import Testing
@testable import GaxoCore

@Suite struct VideoStatsTests {
    /// Off unless asked for: shipping Gaxo neither counts nor logs every 2 s.
    @Test func offReportsNothing() {
        var stats = VideoStats(isEnabled: false, now: 0)
        var reports: [VideoStats.Report] = []
        for tenth in 1...50 {
            stats.pictureDecoded(fingerprint: UInt64(tenth))
            if let report = stats.frameReceived(bytes: 1000, now: Double(tenth) / 10) { reports.append(report) }
        }
        #expect(reports.isEmpty)
    }

    @Test func onReportsEveryTwoSeconds() {
        var stats = VideoStats(isEnabled: true, now: 0)
        stats.pictureDecoded(fingerprint: 1)
        #expect(stats.frameReceived(bytes: 1000, now: 0.5) == nil)
        stats.pictureDecoded(fingerprint: 1) // the same picture again
        #expect(stats.frameReceived(bytes: 500, now: 1.5) == nil)
        stats.pictureDecoded(fingerprint: 2)
        #expect(stats.frameReceived(bytes: 100, now: 2.1)
            == VideoStats.Report(received: 3, bytes: 1600, decoded: 3, distinctPictures: 2))
        #expect(stats.frameReceived(bytes: 100, now: 3) == nil, "counting starts again after a report")
        #expect(stats.frameReceived(bytes: 100, now: 4.2)
            == VideoStats.Report(received: 2, bytes: 200, decoded: 0, distinctPictures: 0))
    }
}
