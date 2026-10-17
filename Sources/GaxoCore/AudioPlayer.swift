import AVFoundation
import Foundation

/// Plays decoded AirPlay audio on the Mac's current output device.
/// Keeps at most `maxQueuedSeconds` queued, dropping buffers beyond that, so
/// latency stays bounded if the stream arrives faster than it plays.
public final class AudioPlayer {
    public var maxQueuedSeconds = 0.5
    /// When false, buffers are discarded (sound off in Settings).
    public var enabled = true

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var queuedFrames: AVAudioFramePosition = 0

    public init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AudioDecoder.outputFormat)
    }

    /// Linear gain 0…1 (see `AirPlayVolume.gain(db:)`).
    public var gain: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    public func start() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        player.play()
    }

    public func stop() {
        player.stop()
        engine.stop()
        lock.withLock { queuedFrames = 0 }
    }

    /// Discards everything queued (the phone flushed its stream).
    public func flush() {
        guard engine.isRunning else { return }
        player.stop()
        lock.withLock { queuedFrames = 0 }
        player.play()
    }

    public func schedule(_ buffer: AVAudioPCMBuffer) {
        guard enabled, engine.isRunning else { return }
        let frames = AVAudioFramePosition(buffer.frameLength)
        let limit = AVAudioFramePosition(maxQueuedSeconds * AudioDecoder.outputFormat.sampleRate)
        let accepted = lock.withLock { () -> Bool in
            guard queuedFrames + frames <= limit else { return false }
            queuedFrames += frames
            return true
        }
        guard accepted else { return }
        player.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            lock.withLock { self.queuedFrames = max(0, self.queuedFrames - frames) }
        }
    }
}
