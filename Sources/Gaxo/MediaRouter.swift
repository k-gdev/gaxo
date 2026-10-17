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
    private var receivedCount = 0
    private var decodedCount = 0
    private var receivedBytes = 0
    private var pictureFingerprints = Set<UInt64>()
    private var lastReport = ProcessInfo.processInfo.systemUptime
    private lazy var videoDecoder = VideoDecoder { [weak self] pixelBuffer, _ in
        guard let self else { return }
        let fingerprint = Self.fingerprint(pixelBuffer)
        lock.withLock {
            self.decodedCount += 1
            self.pictureFingerprints.insert(fingerprint)
        }
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
        lock.withLock { receivedBytes += annexB.count }
        videoDecoder.decode(annexB, ntpNanos: ntpNanos)
        reportVideoStats()
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

    /// Every 2 s while video flows: received → decoded → shown, to see where a stall happens.
    private func reportVideoStats() {
        let now = ProcessInfo.processInfo.systemUptime
        let counts = lock.withLock { () -> (Int, Int, CGSize?, Int, Int)? in
            receivedCount += 1
            guard now - lastReport >= 2 else { return nil }
            defer {
                receivedCount = 0
                decodedCount = 0
                receivedBytes = 0
                pictureFingerprints.removeAll(keepingCapacity: true)
                lastReport = now
            }
            return (receivedCount, decodedCount, lastDimensions, receivedBytes, pictureFingerprints.count)
        }
        guard let (received, decoded, size, bytes, distinct) = counts else { return }
        let dims = size.map { "\(Int($0.width))×\(Int($0.height))" } ?? "-"
        Log.debug("Video 2 s at \(dims): received \(received) (\(bytes / 1024) KB), decoded \(decoded) "
            + "(\(distinct) distinct pictures), \(mirror.videoView.takeReport())")
    }

    /// A cheap fingerprint of a decoded picture (64 luma samples), to tell a moving
    /// picture from the same picture sent again and again.
    private static func fingerprint(_ buffer: CVPixelBuffer) -> UInt64 {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for gy in 1...8 {
            for gx in 1...8 {
                let byte = base.load(fromByteOffset: (height * gy / 9) * rowBytes + width * gx / 9, as: UInt8.self)
                hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
            }
        }
        return hash
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
