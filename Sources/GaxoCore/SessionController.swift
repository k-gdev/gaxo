import CoreGraphics
import Foundation

public struct ClientInfo: Equatable {
    public var deviceID: String
    public var model: String
    public var name: String

    public init(deviceID: String, model: String, name: String) {
        self.deviceID = deviceID
        self.model = model
        self.name = name
    }
}

public enum SessionState: Equatable {
    /// Engine not running (not visible to iPhones).
    case stopped
    /// Advertised and waiting for a device.
    case ready
    case mirroring(ClientInfo)
    /// Code mode: the iPhone is asking for this 4-digit code.
    case awaitingCode(String)
    /// AirPlay video (YouTube) is playing in Gaxo.
    case playingVideo
    case failed(EngineError)
}

/// Receives decoded-stream data. **Called on engine threads.**
public protocol MediaSink: AnyObject {
    func videoFrame(_ annexB: UnsafeRawBufferPointer, ntpNanos: UInt64)
    func videoSize(source: CGSize, size: CGSize)
    func videoFlush()
    func audioFormat(codec: UInt8, samplesPerFrame: UInt16)
    func audioFrame(_ data: UnsafeRawBufferPointer, codec: UInt8, ntpNanos: UInt64)
    func audioFlush()
    func volume(db: Float)
}

/// Owns the engine and the session rules that `uxplay.cpp` implements around
/// UxPlay's library: one device at a time, a client-silence watchdog, dropping
/// clients when the connection is lost, and restarting on settings changes.
///
/// Engine callbacks arrive on engine threads. Anything that calls back into
/// the engine (drop clients, stop, start) runs on `executor`, never inside a
/// callback, because the engine joins its own threads while doing it.
public final class SessionController: EngineDelegate {
    public weak var media: MediaSink?
    public weak var videoPlayer: VideoPlaybackSink?
    /// Delivered on the main queue.
    public var onStateChange: ((SessionState) -> Void)?

    private let makeEngine: (EngineConfig) -> EngineProtocol
    private let clock: () -> TimeInterval
    private let silenceLimit: TimeInterval
    private let executor: (@escaping () -> Void) -> Void
    private var timer: DispatchSourceTimer?
    /// The last state given to `onStateChange` (main queue only).
    private var deliveredState: SessionState?

    private let lock = NSLock()
    private var engine: EngineProtocol?
    private var config: EngineConfig?
    private var accepting = true
    private var _state: SessionState = .stopped
    private var client: ClientInfo?
    private var openConnections = 0
    private var lastHeardFrom: TimeInterval = 0
    private var codeShownAt: TimeInterval?
    private var videoActive = false
    /// Mirror frames are flowing (the session itself can outlive the stream).
    private var mirrorStreamActive = false
    /// How long a pairing code stays up if the iPhone never comes back with it.
    private let codeTimeout: TimeInterval = 60

    public static let controlQueue = DispatchQueue(label: "com.gaxo.session")

    public init(makeEngine: @escaping (EngineConfig) -> EngineProtocol = { Engine(config: $0) },
                clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                silenceLimit: TimeInterval = 15,
                timerInterval: TimeInterval? = 1,
                executor: @escaping (@escaping () -> Void) -> Void = { controlQueue.async(execute: $0) }) {
        self.makeEngine = makeEngine
        self.clock = clock
        self.silenceLimit = silenceLimit
        self.executor = executor
        if let timerInterval {
            let timer = DispatchSource.makeTimerSource(queue: Self.controlQueue)
            timer.schedule(deadline: .now() + timerInterval, repeating: timerInterval)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    deinit {
        timer?.cancel()
    }

    public var state: SessionState {
        lock.withLock { _state }
    }

    // MARK: - Control

    public func start(config: EngineConfig) {
        executor { [self] in startNow(config) }
    }

    public func stop() {
        executor { [self] in stopNow() }
    }

    /// Applies a new config. While not accepting connections the engine stays
    /// stopped and the config is used when connections are accepted again.
    public func restart(config: EngineConfig) {
        executor { [self] in
            let accepting = lock.withLock { () -> Bool in
                self.config = config
                return self.accepting
            }
            stopNow()
            if accepting { startNow(config) }
        }
    }

    /// From "Can’t start": tries to start the receiver again. Does nothing in any other state.
    public func retry() {
        executor { [self] in
            let config = lock.withLock { () -> EngineConfig? in
                guard case .failed = _state, accepting else { return nil }
                return self.config
            }
            if let config { startNow(config) }
        }
    }

    /// Ends the current session; the iPhone leaves Screen Mirroring.
    public func disconnect() {
        executor { [self] in dropNow() }
    }

    /// Off: the engine stops, so iPhones no longer list Gaxo. On: it starts again.
    public func setAcceptingConnections(_ accepting: Bool) {
        executor { [self] in
            let config = lock.withLock { () -> EngineConfig? in
                self.accepting = accepting
                return self.config
            }
            if accepting {
                if let config, state == .stopped { startNow(config) }
            } else {
                stopNow()
            }
        }
    }

    /// Called every second: ends a session whose client went silent, and takes
    /// down a pairing code nobody came back with.
    public func tick() {
        let codeExpired = lock.withLock { () -> Bool in
            guard case .awaitingCode = _state, let shown = codeShownAt, clock() - shown > codeTimeout else {
                return false
            }
            codeShownAt = nil
            return setStateLocked(.ready)
        }
        if codeExpired {
            Log.info("Pairing code expired")
            notifyStateChange()
        }

        let silent = lock.withLock {
            (client != nil || videoActive) && clock() - lastHeardFrom > silenceLimit
        }
        if silent {
            Log.info("No word from the iPhone for \(Int(silenceLimit)) s; ending the session")
            dropNow()
        }
    }

    private func startNow(_ config: EngineConfig) {
        let engine = makeEngine(config)
        engine.delegate = self
        lock.withLock {
            self.config = config
            self.engine = engine
        }
        do {
            try engine.start()
            Log.info("Engine started as \"\(config.name)\" on port \(engine.port)")
            setState(.ready)
        } catch let error as EngineError {
            Log.error("Engine failed to start: \(error)")
            lock.withLock { self.engine = nil }
            setState(.failed(error))
        } catch {
            lock.withLock { self.engine = nil }
            setState(.failed(.raopInit))
        }
    }

    private func stopNow() {
        stopVideoIfActive()
        let engine = lock.withLock { () -> EngineProtocol? in
            let e = self.engine
            self.engine = nil
            endSessionLocked()
            return e
        }
        engine?.stop()
        setState(.stopped)
    }

    private func dropNow() {
        stopVideoIfActive()
        let engine = lock.withLock { self.engine }
        engine?.dropClients()
        endSession()
    }

    // MARK: - Session bookkeeping

    private func endSessionLocked() {
        client = nil
        openConnections = 0
        mirrorStreamActive = false
    }

    /// `keepingCode`: a connection closing does not take a pairing code off screen —
    /// iOS asks for the code on a short connection and closes it before the user types it.
    private func endSession(keepingCode: Bool = false) {
        let changed = lock.withLock { () -> Bool in
            let active = client != nil
            endSessionLocked()
            if keepingCode, case .awaitingCode = _state { return false }
            if videoActive { return false } // the mirror stream may stop while a video plays
            codeShownAt = nil
            guard active || _state != .ready, engine != nil else { return false }
            return setStateLocked(.ready)
        }
        if changed { notifyStateChange() }
    }

    // MARK: - State

    // A state is decided and set in one `lock` section, so a decision made from
    // the bookkeeping can never be applied after that bookkeeping has changed.

    private func setState(_ new: SessionState) {
        if lock.withLock({ setStateLocked(new) }) { notifyStateChange() }
    }

    /// Caller holds `lock`. Returns true when the state changed: then call
    /// `notifyStateChange()` once the lock is released.
    private func setStateLocked(_ new: SessionState) -> Bool {
        guard _state != new else { return false }
        _state = new
        return true
    }

    /// Tells the observer on the main queue. It is given the state as it is when the
    /// main queue gets there, so a change that overtook this one is never undone.
    private func notifyStateChange() {
        guard onStateChange != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let onStateChange else { return }
            let current = state
            guard current != deliveredState else { return }
            deliveredState = current
            onStateChange(current)
        }
    }

    // MARK: - EngineDelegate

    public func engineClientRequest(deviceID: String, model: String, name: String) -> Bool {
        let requester = ClientInfo(deviceID: deviceID, model: model, name: name)
        let admitted = lock.withLock { () -> Bool in
            guard accepting else { return false }
            if let client, client.deviceID != deviceID { return false }
            client = requester
            lastHeardFrom = clock()
            return true
        }
        Log.info("Connection request from \(name) (\(model), \(deviceID)): \(admitted ? "admitted" : "refused")")
        return admitted
    }

    public func engineConnectionOpened() {
        lock.withLock {
            openConnections += 1
            lastHeardFrom = clock()
        }
    }

    public func engineConnectionClosed() {
        let last = lock.withLock { () -> Bool in
            openConnections = max(0, openConnections - 1)
            return openConnections == 0
        }
        if last { endSession(keepingCode: true) }
    }

    public func engineConnectionLost(reason: Int32) {
        Log.info("Lost the connection with the iPhone (reason \(reason))")
        executor { [self] in dropNow() }
    }

    public func engineFeedback() {
        lock.withLock { lastHeardFrom = clock() }
    }

    /// The mirror stream stopped. While the phone's connection stays open the session
    /// continues (iOS may resume mirroring or play an AirPlay video on it); it ends when
    /// the last connection closes, the watchdog fires, or the user disconnects.
    public func engineVideoStopped() {
        Log.info("The iPhone stopped mirroring")
        media?.videoFlush()
        let (sessionContinues, changed) = lock.withLock { () -> (Bool, Bool) in
            mirrorStreamActive = false
            guard client != nil && openConnections > 0 else { return (false, false) }
            return (true, !videoActive && setStateLocked(.ready))
        }
        if !sessionContinues {
            endSession()
        } else if changed {
            notifyStateChange()
        }
    }

    public func engineVideoFrame(_ annexB: UnsafeRawBufferPointer, ntpNanos: UInt64) {
        markMirroring()
        media?.videoFrame(annexB, ntpNanos: ntpNanos)
    }

    public func engineVideoSize(source: CGSize, size: CGSize) {
        Log.info("Video size \(Int(size.width))×\(Int(size.height)) (source \(Int(source.width))×\(Int(source.height)))")
        markMirroring()
        media?.videoSize(source: source, size: size)
    }

    public func engineVideoFlush() {
        media?.videoFlush()
    }

    public func engineAudioFormat(codec: UInt8, samplesPerFrame: UInt16) {
        Log.info("Audio format ct=\(codec) spf=\(samplesPerFrame)")
        media?.audioFormat(codec: codec, samplesPerFrame: samplesPerFrame)
    }

    public func engineAudioFrame(_ data: UnsafeRawBufferPointer, codec: UInt8, ntpNanos: UInt64) {
        media?.audioFrame(data, codec: codec, ntpNanos: ntpNanos)
    }

    public func engineAudioFlush() {
        media?.audioFlush()
    }

    public func engineVolume(db: Float) {
        media?.volume(db: db)
    }

    public func engineShowPIN(_ pin: String) {
        Log.info("Showing pairing code")
        let changed = lock.withLock { () -> Bool in
            codeShownAt = clock()
            return setStateLocked(.awaitingCode(pin))
        }
        if changed { notifyStateChange() }
    }

    public func engineLog(level: Int32, _ message: String) {
        Log.engine(level: level, message)
    }

    private func markMirroring() {
        let changed = lock.withLock { () -> Bool in
            codeShownAt = nil
            guard let client else { return false }
            mirrorStreamActive = true
            return !videoActive && setStateLocked(.mirroring(client))
        }
        if changed { notifyStateChange() }
    }

    // MARK: - AirPlay video (YouTube)

    public func engineVideoPlay(url: String, startPosition: Float) {
        Log.info("AirPlay video: play \(url) from \(startPosition) s")
        let changed = lock.withLock { () -> Bool in
            videoActive = true
            lastHeardFrom = clock()
            return setStateLocked(.playingVideo)
        }
        videoPlayer?.play(url: url, startPosition: startPosition)
        if changed { notifyStateChange() }
    }

    public func engineVideoSeek(to position: Float) {
        videoPlayer?.seek(to: position)
    }

    public func engineVideoRate(_ rate: Float) {
        videoPlayer?.setRate(rate)
    }

    /// The iPhone stopped the video (POST /stop).
    public func engineVideoStop() {
        Log.info("AirPlay video: stopped by the iPhone")
        finishVideo()
    }

    /// The engine ended the AirPlay video session (finished, or torn down).
    public func engineVideoEnded() {
        Log.info("AirPlay video: session ended")
        finishVideo()
    }

    /// The iPhone polls this about once a second during a video: it also counts as
    /// hearing from the phone (the watchdog keeps running during videos).
    public func engineVideoPlaybackInfo() -> PlaybackSnapshot {
        lock.withLock { lastHeardFrom = clock() }
        return videoPlayer?.currentPlayback() ?? .notReady
    }

    public func engineVideoPlaylistRemoved() -> Float {
        videoPlayer?.pauseForPlaylistChange() ?? 0
    }

    private func finishVideo() {
        let (wasActive, changed) = lock.withLock { () -> (Bool, Bool) in
            guard videoActive else { return (false, false) }
            videoActive = false
            let mirroringClient = mirrorStreamActive ? client : nil
            return (true, setStateLocked(mirroringClient.map { .mirroring($0) } ?? .ready))
        }
        guard wasActive else { return }
        videoPlayer?.stop()
        if changed { notifyStateChange() }
    }

    private func stopVideoIfActive() {
        let wasActive = lock.withLock { () -> Bool in
            defer { videoActive = false }
            return videoActive
        }
        if wasActive { videoPlayer?.stop() }
    }
}
