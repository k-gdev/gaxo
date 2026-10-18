import Foundation

/// Video diagnostics for the log: every 2 s while video flows, how many frames
/// arrived, were decoded, and how many distinct pictures they held — to see
/// where a stall happens. Off unless turned on with
/// `defaults write com.gaxo.Gaxo verboseVideoLog -bool true`.
public struct VideoStats {
    public static let defaultsKey = "verboseVideoLog"

    public struct Report: Equatable {
        public var received: Int
        public var bytes: Int
        public var decoded: Int
        public var distinctPictures: Int

        public init(received: Int, bytes: Int, decoded: Int, distinctPictures: Int) {
            self.received = received
            self.bytes = bytes
            self.decoded = decoded
            self.distinctPictures = distinctPictures
        }
    }

    /// When false nothing is counted or reported (and pictures need no fingerprint).
    public let isEnabled: Bool
    private var counts = Report(received: 0, bytes: 0, decoded: 0, distinctPictures: 0)
    private var fingerprints = Set<UInt64>()
    private var lastReport: TimeInterval

    public init(isEnabled: Bool, now: TimeInterval) {
        self.isEnabled = isEnabled
        lastReport = now
    }

    public mutating func pictureDecoded(fingerprint: UInt64) {
        guard isEnabled else { return }
        counts.decoded += 1
        fingerprints.insert(fingerprint)
    }

    /// A frame arrived. Returns the counts since the last report once 2 s have passed.
    public mutating func frameReceived(bytes: Int, now: TimeInterval) -> Report? {
        guard isEnabled else { return nil }
        counts.received += 1
        counts.bytes += bytes
        guard now - lastReport >= 2 else { return nil }
        var report = counts
        report.distinctPictures = fingerprints.count
        counts = Report(received: 0, bytes: 0, decoded: 0, distinctPictures: 0)
        fingerprints.removeAll(keepingCapacity: true)
        lastReport = now
        return report
    }
}
