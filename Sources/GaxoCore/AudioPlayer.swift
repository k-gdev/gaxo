import AVFoundation
import Foundation

/// Plays decoded AirPlay audio on the Mac's current output device.
/// Keeps at most `maxQueuedSeconds` queued, dropping buffers beyond that, so
/// latency stays bounded if the stream arrives faster than it plays.
public final class AudioPlayer {
    public var maxQueuedSeconds = 0.5
    /// When false, buffers are discarded (sound off in Settings).
    public var enabled = true

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var queuedFrames: AVAudioFramePosition = 0
    private var wantsToRun = false
    private var configurationObserver: NSObjectProtocol?

    public init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AudioDecoder.outputFormat)
        // Switching the Mac's output device stops the engine; start it again on the new device.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    public var isRunning: Bool {
        engine.isRunning
    }

    /// Linear gain 0…1 (see `AirPlayVolume.gain(db:)`).
    public var gain: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    public func start() throws {
        wantsToRun = true
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        player.play()
    }

    public func stop() {
        wantsToRun = false
        player.stop()
        engine.stop()
        lock.withLock { queuedFrames = 0 }
    }

    private func restartAfterConfigurationChange() {
        guard wantsToRun else { return }
        Log.info("Audio output changed; restarting playback")
        lock.withLock { queuedFrames = 0 }
        do {
            engine.connect(player, to: engine.mainMixerNode, format: AudioDecoder.outputFormat)
            engine.prepare()
            try engine.start()
            player.play()
        } catch {
            Log.error("Could not restart audio after an output change: \(error)")
        }
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
