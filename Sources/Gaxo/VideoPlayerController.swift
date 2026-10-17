import AppKit
import AVFoundation
import GaxoCore

/// Plays AirPlay video (YouTube's HLS stream, served by the engine on localhost)
/// in the mirror window, and keeps a snapshot of its state for the iPhone's
/// playback-info polls. Engine calls arrive on engine threads; AVPlayer is only
/// touched on the main thread.
final class VideoPlayerController: VideoPlaybackSink {
    private let mirror: MirrorWindowController
    private let lock = NSLock()
    private var snapshot = PlaybackSnapshot.notReady

    // Main thread only.
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var finished = false

    /// Sound off in Settings.
    var muted = false {
        didSet { DispatchQueue.main.async { [self] in player?.isMuted = muted } }
    }

    init(mirror: MirrorWindowController) {
        self.mirror = mirror
    }

    // MARK: - VideoPlaybackSink

    func play(url: String, startPosition: Float) {
        DispatchQueue.main.async { [self] in start(url, at: startPosition) }
    }

    func seek(to position: Float) {
        DispatchQueue.main.async { [self] in
            player?.seek(to: CMTime(seconds: Double(position), preferredTimescale: 600))
        }
    }

    func setRate(_ rate: Float) {
        DispatchQueue.main.async { [self] in
            if rate == 0 { player?.pause() } else { player?.play() }
        }
    }

    func stop() {
        DispatchQueue.main.async { [self] in tearDown() }
    }

    func currentPlayback() -> PlaybackSnapshot {
        lock.withLock { snapshot }
    }

    func pauseForPlaylistChange() -> Float {
        let position = lock.withLock { Float(max(snapshot.position, 0)) }
        DispatchQueue.main.async { [self] in player?.pause() }
        return position
    }

    // MARK: - Main thread

    private func start(_ urlString: String, at startPosition: Float) {
        tearDown()
        guard let url = URL(string: urlString) else {
            Log.error("AirPlay video: bad URL \(urlString)")
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = muted
        self.player = player
        finished = false

        observations = [
            item.observe(\.status) { item, _ in
                if item.status == .failed {
                    Log.error("AirPlay video failed: \(item.error.map { String(describing: $0) } ?? "unknown error")")
                }
            },
            item.observe(\.presentationSize) { [weak self] item, _ in
                let size = item.presentationSize
                guard size.width > 0, size.height > 0 else { return }
                DispatchQueue.main.async { self?.mirror.videoSizeChanged(size) }
            },
        ]
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] _ in self?.updateSnapshot() }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Log.info("AirPlay video: reached the end")
            self?.finished = true
            self?.lock.withLock { self?.snapshot = .finished } // the engine then ends the session
        }

        mirror.showPlayer(player)
        if startPosition > 0 {
            player.seek(to: CMTime(seconds: Double(startPosition), preferredTimescale: 600))
        }
        player.play()
    }

    private func updateSnapshot() {
        guard !finished, let player, let item = player.currentItem else { return }
        let ready = item.status == .readyToPlay
        let duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
        let seekable = item.seekableTimeRanges.first?.timeRangeValue
        let position = player.currentTime().seconds
        let current = PlaybackSnapshot(
            duration: duration,
            position: ready && position.isFinite ? position : -1,
            rate: player.rate,
            seekStart: seekable?.start.seconds ?? 0,
            seekDuration: seekable?.duration.seconds ?? duration,
            bufferEmpty: item.isPlaybackBufferEmpty,
            bufferFull: item.isPlaybackBufferFull,
            likelyToKeepUp: item.isPlaybackLikelyToKeepUp,
            readyToPlay: ready)
        lock.withLock { snapshot = current }
    }

    private func tearDown() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        observations = []
        player?.pause()
        player = nil
        finished = false
        mirror.hidePlayer()
        lock.withLock { snapshot = .notReady }
    }
}
