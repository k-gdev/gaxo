import AVFoundation
import CoreGraphics
import CoreVideo
import GaxoCore

/// Routes the engine's streams: video → decoder → mirror window,
/// audio → decoder → speakers. Called on engine threads.
final class MediaRouter: MediaSink {
    private let mirror: MirrorWindowController
    private let audioPlayer: AudioPlayer
    private let lock = NSLock()
    private var audioDecoder: AudioDecoder?
    private var lastDimensions: CGSize?
    private lazy var videoDecoder = VideoDecoder { [mirror] pixelBuffer, _ in
        mirror.videoView.display(pixelBuffer)
    }

    init(mirror: MirrorWindowController, audioPlayer: AudioPlayer) {
        self.mirror = mirror
        self.audioPlayer = audioPlayer
    }

    var playSound: Bool {
        get { audioPlayer.enabled }
        set { audioPlayer.enabled = newValue }
    }

    /// Main thread: the session is over; the next one starts from scratch.
    func sessionEnded() {
        videoDecoder.reset()
        lock.withLock {
            lastDimensions = nil
            audioDecoder = nil
        }
        audioPlayer.stop()
    }

    // MARK: - MediaSink

    func videoFrame(_ annexB: UnsafeRawBufferPointer, ntpNanos: UInt64) {
        videoDecoder.decode(annexB, ntpNanos: ntpNanos)
        // The decoder's dimensions (from SPS/PPS) drive the window: first frame and rotation.
        guard let dimensions = videoDecoder.dimensions else { return }
        let changed = lock.withLock { () -> Bool in
            guard dimensions != lastDimensions else { return false }
            lastDimensions = dimensions
            return true
        }
        if changed {
            DispatchQueue.main.async { [mirror] in mirror.videoSizeChanged(dimensions) }
        }
    }

    func videoSize(source: CGSize, size: CGSize) {}

    func videoFlush() {
        videoDecoder.flush()
    }

    func audioFormat(codec: UInt8, samplesPerFrame: UInt16) {
        let decoder = try? AudioDecoder(codec: codec)
        if decoder == nil { Log.error("Unsupported audio format ct=\(codec)") }
        lock.withLock { audioDecoder = decoder }
        if audioPlayer.enabled {
            do { try audioPlayer.start() } catch { Log.error("Could not start audio: \(error)") }
        }
    }

    func audioFrame(_ data: UnsafeRawBufferPointer, codec: UInt8, ntpNanos: UInt64) {
        guard let pcm = lock.withLock({ audioDecoder?.decode(data) }) else { return }
        audioPlayer.schedule(pcm)
    }

    func audioFlush() {
        audioPlayer.flush()
    }

    func volume(db: Float) {
        audioPlayer.gain = AirPlayVolume.gain(db: db)
    }
}
