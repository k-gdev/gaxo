import CoreGraphics
import Foundation
import Testing
@testable import GaxoCore

private final class FakeEngine: EngineProtocol {
    weak var delegate: EngineDelegate?
    var port: UInt16 = 7101
    let config: EngineConfig
    let startError: EngineError?
    var started = 0
    var stopped = 0
    var dropped = 0

    init(config: EngineConfig, startError: EngineError?) {
        self.config = config
        self.startError = startError
    }

    func start() throws {
        started += 1
        if let startError { throw startError }
    }

    func stop() { stopped += 1 }
    func dropClients() { dropped += 1 }
}

private final class RecordingSink: MediaSink {
    var videoFrames = 0
    var audioFrames = 0
    func videoFrame(_ annexB: UnsafeRawBufferPointer, ntpNanos: UInt64) { videoFrames += 1 }
    func videoSize(source: CGSize, size: CGSize) {}
    func videoFlush() {}
    func audioFormat(codec: UInt8, samplesPerFrame: UInt16) {}
    func audioFrame(_ data: UnsafeRawBufferPointer, codec: UInt8, ntpNanos: UInt64) { audioFrames += 1 }
    func audioFlush() {}
    func volume(db: Float) {}
}

/// Drives a SessionController with a fake engine, a fake clock and a
/// synchronous executor, so every test is deterministic.
private final class Harness {
    var now: TimeInterval = 1_000
    var engines: [FakeEngine] = []
    var nextStartError: EngineError?
    lazy var session = SessionController(
        makeEngine: { [unowned self] config in
            let engine = FakeEngine(config: config, startError: nextStartError)
            engines.append(engine)
            return engine
        },
        clock: { [unowned self] in now },
        silenceLimit: 15,
        timerInterval: nil,
        executor: { $0() })

    var engine: FakeEngine { engines.last! }

    static func config(_ name: String = "Gaxo") -> EngineConfig {
        EngineConfig(name: name, deviceID: "02:11:22:33:44:55", keyfile: URL(fileURLWithPath: "/tmp/k.pem"),
                     basePort: 7100, width: 1920, height: 1080, refreshRate: 60, maxFPS: 60,
                     pinOnce: false, advertise: true, logLevel: 6)
    }

    static let phoneA = ClientInfo(deviceID: "AA:AA:AA:AA:AA:AA", model: "iPhone17,1", name: "Phone A")
    static let phoneB = ClientInfo(deviceID: "BB:BB:BB:BB:BB:BB", model: "iPhone16,2", name: "Phone B")

    @discardableResult
    func request(_ client: ClientInfo) -> Bool {
        session.engineClientRequest(deviceID: client.deviceID, model: client.model, name: client.name)
    }

    func startMirroring(_ client: ClientInfo = phoneA) {
        session.start(config: Self.config())
        session.engineConnectionOpened()
        request(client)
        session.engineVideoSize(source: CGSize(width: 886, height: 1920), size: CGSize(width: 886, height: 1920))
    }
}

@Suite struct SessionControllerTests {
    @Test func startGoesReady() {
        let h = Harness()
        h.session.start(config: Harness.config())
        #expect(h.session.state == .ready)
        #expect(h.engine.started == 1)
    }

    @Test func startFailureBecomesFailedState() {
        let h = Harness()
        h.nextStartError = .portInUse(7100)
        h.session.start(config: Harness.config())
        #expect(h.session.state == .failed(.portInUse(7100)))
    }

    @Test func firstDeviceAdmittedAndMirroring() {
        let h = Harness()
        h.session.start(config: Harness.config())
        #expect(h.request(Harness.phoneA))
        h.session.engineVideoSize(source: CGSize(width: 886, height: 1920), size: CGSize(width: 886, height: 1920))
        #expect(h.session.state == .mirroring(Harness.phoneA))
    }

    @Test func secondDeviceIsRefused() {
        let h = Harness()
        h.startMirroring(Harness.phoneA)
        #expect(!h.request(Harness.phoneB))
        #expect(h.session.state == .mirroring(Harness.phoneA))
        #expect(h.request(Harness.phoneA), "the same phone reconnecting is still admitted")
    }

    @Test func watchdogEndsSilentSession() {
        let h = Harness()
        h.startMirroring()
        h.now += 16
        h.session.tick()
        #expect(h.engine.dropped == 1)
        #expect(h.session.state == .ready)
    }

    @Test func feedbackKeepsSessionAlive() {
        let h = Harness()
        h.startMirroring()
        for _ in 0..<30 {
            h.now += 2
            h.session.engineFeedback()
            h.session.tick()
        }
        #expect(h.engine.dropped == 0)
        #expect(h.session.state == .mirroring(Harness.phoneA))
    }

    @Test func videoStoppedReturnsToReady() {
        let h = Harness()
        h.startMirroring(Harness.phoneA)
        h.session.engineVideoStopped()
        #expect(h.session.state == .ready)
        #expect(h.request(Harness.phoneB), "another phone may connect once the session ended")
    }

    @Test func connectionLostReturnsToReady() {
        let h = Harness()
        h.startMirroring()
        h.session.engineConnectionLost(reason: 1)
        #expect(h.engine.dropped == 1)
        #expect(h.session.state == .ready)
    }

    @Test func lastConnectionClosedEndsSession() {
        let h = Harness()
        h.startMirroring()
        h.session.engineConnectionOpened()
        h.session.engineConnectionClosed()
        #expect(h.session.state == .mirroring(Harness.phoneA))
        h.session.engineConnectionClosed()
        #expect(h.session.state == .ready)
    }

    @Test func disconnectDropsClients() {
        let h = Harness()
        h.startMirroring()
        h.session.disconnect()
        #expect(h.engine.dropped == 1)
        #expect(h.session.state == .ready)
    }

    @Test func notAcceptingStopsEngineAndResumes() {
        let h = Harness()
        h.startMirroring()
        h.session.setAcceptingConnections(false)
        #expect(h.engines[0].stopped == 1)
        #expect(h.session.state == .stopped)
        h.session.setAcceptingConnections(true)
        #expect(h.engines.count == 2)
        #expect(h.engines[1].started == 1)
        #expect(h.session.state == .ready)
    }

    @Test func restartEndsSessionAndRestarts() {
        let h = Harness()
        h.startMirroring()
        h.session.restart(config: Harness.config("Living Room"))
        #expect(h.engines[0].stopped == 1)
        #expect(h.engines.count == 2)
        #expect(h.engines[1].config.name == "Living Room")
        #expect(h.session.state == .ready)
    }

    /// Settings changed while "Accept connections" is off: stay invisible, but use the
    /// new settings when connections are accepted again.
    @Test func restartWhilePausedStaysPausedThenUsesNewConfig() {
        let h = Harness()
        h.session.start(config: Harness.config("Gaxo"))
        h.session.setAcceptingConnections(false)
        h.session.restart(config: Harness.config("Living Room"))
        #expect(h.session.state == .stopped)
        #expect(h.engines.count == 1, "no engine started while paused")
        h.session.setAcceptingConnections(true)
        #expect(h.engines.last?.config.name == "Living Room")
        #expect(h.session.state == .ready)
    }

    @Test func pinShownThenMirroring() {
        let h = Harness()
        h.session.start(config: Harness.config())
        h.session.engineShowPIN("1234")
        #expect(h.session.state == .awaitingCode("1234"))
        h.request(Harness.phoneA)
        h.session.engineVideoSize(source: CGSize(width: 886, height: 1920), size: CGSize(width: 886, height: 1920))
        #expect(h.session.state == .mirroring(Harness.phoneA))
    }

    /// iOS requests the code on a short connection and closes it before the user types
    /// the code; the code must stay on screen.
    @Test func codeSurvivesTheRequestingConnectionClosing() {
        let h = Harness()
        h.session.start(config: Harness.config())
        h.session.engineConnectionOpened()
        h.session.engineShowPIN("0846")
        h.session.engineConnectionClosed()
        #expect(h.session.state == .awaitingCode("0846"))
    }

    @Test func codeExpiresAfterAMinute() {
        let h = Harness()
        h.session.start(config: Harness.config())
        h.session.engineShowPIN("0846")
        h.now += 59
        h.session.tick()
        #expect(h.session.state == .awaitingCode("0846"))
        h.now += 2
        h.session.tick()
        #expect(h.session.state == .ready)
    }

    @Test func disconnectClearsCode() {
        let h = Harness()
        h.session.start(config: Harness.config())
        h.session.engineShowPIN("0846")
        h.session.disconnect()
        #expect(h.session.state == .ready)
    }

    @Test func mediaIsForwardedToSink() {
        let h = Harness()
        let sink = RecordingSink()
        h.session.media = sink
        h.startMirroring()
        let bytes: [UInt8] = [0, 0, 0, 1, 0x65]
        bytes.withUnsafeBytes { h.session.engineVideoFrame($0, ntpNanos: 1) }
        bytes.withUnsafeBytes { h.session.engineAudioFrame($0, codec: 8, ntpNanos: 1) }
        #expect(sink.videoFrames == 1)
        #expect(sink.audioFrames == 1)
    }
}
