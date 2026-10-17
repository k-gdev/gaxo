import Foundation

/// What the iPhone is told about AirPlay video playback (GET /playback-info).
/// Engine conventions: `position == -1` means "not ready yet"; `duration == -1`
/// means the video has finished (the engine then ends the AirPlay video session).
public struct PlaybackSnapshot: Equatable {
    public var duration: Double
    public var position: Double
    public var rate: Float
    public var seekStart: Double
    public var seekDuration: Double
    public var bufferEmpty: Bool
    public var bufferFull: Bool
    public var likelyToKeepUp: Bool
    public var readyToPlay: Bool

    public init(duration: Double, position: Double, rate: Float, seekStart: Double, seekDuration: Double,
                bufferEmpty: Bool, bufferFull: Bool, likelyToKeepUp: Bool, readyToPlay: Bool) {
        self.duration = duration
        self.position = position
        self.rate = rate
        self.seekStart = seekStart
        self.seekDuration = seekDuration
        self.bufferEmpty = bufferEmpty
        self.bufferFull = bufferFull
        self.likelyToKeepUp = likelyToKeepUp
        self.readyToPlay = readyToPlay
    }

    public static let notReady = PlaybackSnapshot(
        duration: 0, position: -1, rate: 0, seekStart: 0, seekDuration: 0,
        bufferEmpty: true, bufferFull: false, likelyToKeepUp: false, readyToPlay: false)

    public static let finished = PlaybackSnapshot(
        duration: -1, position: -1, rate: 0, seekStart: 0, seekDuration: 0,
        bufferEmpty: true, bufferFull: false, likelyToKeepUp: false, readyToPlay: false)
}

/// Plays AirPlay video (YouTube's HLS stream, served by the engine on localhost).
/// Called on engine threads; implementations must be thread-safe.
public protocol VideoPlaybackSink: AnyObject {
    func play(url: String, startPosition: Float)
    func seek(to position: Float)
    /// 0 = pause, 1 = play.
    func setRate(_ rate: Float)
    func stop()
    func currentPlayback() -> PlaybackSnapshot
    /// The iPhone is changing playlists (e.g. an ad ends): pause and return the position.
    func pauseForPlaylistChange() -> Float
}
