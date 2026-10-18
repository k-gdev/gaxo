import AVFoundation
import Foundation

/// Plays decoded AirPlay audio on the Mac's current output device.
/// Keeps at most `maxQueuedSeconds` queued, dropping buffers beyond that, so
/// latency stays bounded if the stream arrives faster than it plays.
///
/// Start and flush come from engine threads, stop from the main thread and the
/// restart after an output change from Core Audio's thread: all of them run on
/// one serial queue.
public final class AudioPlayer {
    public var maxQueuedSeconds = 0.5
    /// When false, buffers are discarded (sound off in Settings). Any thread.
    public var enabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue } }
    }

    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "com.gaxo.audio")
    private let lock = NSLock()
    private var queuedFrames: AVAudioFramePosition = 0
    private var _enabled = true
    private var wantsToRun = false // on `queue` only
    private var configurationObserver: NSObjectProtocol?

    public init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AudioDecoder.outputFormat)
        // Switching the Mac's output device stops the engine; start it again on the new device.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            queue.async { self.restartAfterConfigurationChange() }
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    public var isRunning: Bool {
        queue.sync { engine.isRunning }
    }

    /// Linear gain 0…1 (see `AirPlayVolume.gain(db:)`).
    public var gain: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    public func start() throws {
        try queue.sync {
            wantsToRun = true
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            player.play()
        }
    }

    public func stop() {
        queue.sync {
            wantsToRun = false
            player.stop()
            engine.stop()
            lock.withLock { queuedFrames = 0 }
        }
    }

    /// On `queue`. An output change stops the engine; one that did not has nothing to restart.
    private func restartAfterConfigurationChange() {
        guard wantsToRun, !engine.isRunning else { return }
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
        queue.sync {
            guard engine.isRunning else { return }
            player.stop()
            lock.withLock { queuedFrames = 0 }
            player.play()
        }
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
