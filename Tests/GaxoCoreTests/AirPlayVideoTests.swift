import CoreGraphics
import Foundation
import Testing
@testable import GaxoCore

/// Records what the session asks the video player to do.
private final class RecordingPlayer: VideoPlaybackSink {
    var played: [(String, Float)] = []
    var seeks: [Float] = []
    var rates: [Float] = []
    var stops = 0
    var snapshot = PlaybackSnapshot.notReady
    func play(url: String, startPosition: Float) { played.append((url, startPosition)) }
    func seek(to position: Float) { seeks.append(position) }
    func setRate(_ rate: Float) { rates.append(rate) }
    func stop() { stops += 1 }
    func currentPlayback() -> PlaybackSnapshot { snapshot }
    func pauseForPlaylistChange() -> Float { 42 }
}

private final class StubEngine: EngineProtocol {
    weak var delegate: EngineDelegate?
    var port: UInt16 = 7101
    var dropped = 0
    func start() throws {}
    func stop() {}
    func dropClients() { dropped += 1 }
}

@Suite struct AirPlayVideoSessionTests {
    private final class Clock { var now: TimeInterval = 1_000 }
    private let clock = Clock()

    private func makeSession() -> (SessionController, RecordingPlayer, StubEngine) {
        let engine = StubEngine()
        let clock = self.clock
        let session = SessionController(makeEngine: { _ in engine }, clock: { clock.now }, timerInterval: nil,
                                        executor: { $0() })
        let player = RecordingPlayer()
        session.videoPlayer = player
        session.start(config: EngineConfig(name: "Gaxo", deviceID: "02:11:22:33:44:55",
                                           keyfile: URL(fileURLWithPath: "/tmp/k.pem"), basePort: 7100,
                                           width: 1920, height: 1080, refreshRate: 60, maxFPS: 60,
                                           pinOnce: false, advertise: true, logLevel: 6))
        return (session, player, engine)
    }

    @Test func playStartsThePlayerAndChangesState() {
        let (session, player, _) = makeSession()
        session.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 12.5)
        #expect(player.played.count == 1)
        #expect(player.played.first?.0 == "http://localhost:7101/master.m3u8")
        #expect(player.played.first?.1 == 12.5)
        #expect(session.state == .playingVideo)
    }

    @Test func mirrorStreamStoppingDoesNotEndTheVideo() {
        let (session, _, _) = makeSession()
        session.engineConnectionOpened()
        _ = session.engineClientRequest(deviceID: "FE", model: "iPhone18,2", name: "Phone")
        session.engineVideoSize(source: CGSize(width: 498, height: 1080), size: CGSize(width: 498, height: 1080))
        session.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 0)
        session.engineVideoStopped() // iOS pauses mirroring while YouTube plays
        #expect(session.state == .playingVideo)
    }

    private let phone = ClientInfo(deviceID: "FE", model: "iPhone18,2", name: "Phone")

    private func startMirroring(_ session: SessionController) {
        session.engineConnectionOpened()
        _ = session.engineClientRequest(deviceID: phone.deviceID, model: phone.model, name: phone.name)
        session.engineVideoSize(source: CGSize(width: 498, height: 1080), size: CGSize(width: 498, height: 1080))
    }

    /// What the engine really sends: the mirror stream stops (RTP teardown), then the video plays.
    @Test func videoEndingAfterTheMirrorStreamStoppedWaitsForMirroringToResume() {
        let (session, player, _) = makeSession()
        startMirroring(session)
        session.engineVideoStopped()
        session.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 0)
        session.engineVideoEnded()
        #expect(player.stops == 1)
        #expect(session.state == .ready)
        session.engineVideoSize(source: CGSize(width: 498, height: 1080), size: CGSize(width: 498, height: 1080))
        #expect(session.state == .mirroring(phone), "the same phone resumes on the same connection")
    }

    @Test func videoEndingWhileStillMirroringReturnsToMirroring() {
        let (session, _, _) = makeSession()
        startMirroring(session)
        session.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 0)
        session.engineVideoEnded()
        #expect(session.state == .mirroring(phone))

        let (alone, _, _) = makeSession()
        alone.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 0)
        alone.engineVideoEnded()
        #expect(alone.state == .ready)
    }

    @Test func secondPhoneIsRefusedDuringAVideo() {
        let (session, _, _) = makeSession()
        startMirroring(session)
        session.engineVideoStopped()
        session.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 0)
        #expect(!session.engineClientRequest(deviceID: "BB", model: "iPhone16,2", name: "Other"))
    }

    @Test func iPhoneControlsReachThePlayer() {
        let (session, player, _) = makeSession()
        session.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 0)
        session.engineVideoSeek(to: 30)
        session.engineVideoRate(0)
        session.engineVideoRate(1)
        #expect(player.seeks == [30])
        #expect(player.rates == [0, 1])
        #expect(session.engineVideoPlaylistRemoved() == 42)
        session.engineVideoStop()
        #expect(player.stops == 1)
        #expect(session.state == .ready)
    }

    @Test func playbackReportComesFromThePlayer() {
        let (session, player, _) = makeSession()
        player.snapshot = PlaybackSnapshot(duration: 200, position: 31, rate: 1, seekStart: 0, seekDuration: 200,
                                           bufferEmpty: false, bufferFull: true, likelyToKeepUp: true,
                                           readyToPlay: true)
        #expect(session.engineVideoPlaybackInfo() == player.snapshot)
    }

    /// The phone drops off Wi-Fi mid-video: after 15 s without a playback poll the session ends.
    @Test func watchdogEndsASilentVideo() {
        let (session, player, engine) = makeSession()
        session.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 0)
        clock.now += 16
        session.tick()
        #expect(engine.dropped == 1)
        #expect(player.stops == 1)
        #expect(session.state == .ready)
    }

    /// During a video the iPhone polls playback info about once a second: that keeps it alive.
    @Test func playbackPollsKeepAVideoAlive() {
        let (session, _, engine) = makeSession()
        session.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 0)
        for _ in 0..<30 {
            clock.now += 1
            _ = session.engineVideoPlaybackInfo()
            session.tick()
        }
        #expect(engine.dropped == 0)
        #expect(session.state == .playingVideo)
    }

    @Test func disconnectStopsTheVideo() {
        let (session, player, engine) = makeSession()
        session.engineVideoPlay(url: "http://localhost:7101/master.m3u8", startPosition: 0)
        session.disconnect()
        #expect(player.stops == 1)
        #expect(engine.dropped == 1)
        #expect(session.state == .ready)
    }
}

@Suite struct PlaybackSnapshotTests {
    /// The engine's conventions: position -1 = not ready yet; duration -1 = finished.
    @Test func notReadyAndFinishedFollowTheEngineConventions() {
        #expect(PlaybackSnapshot.notReady.position == -1)
        #expect(PlaybackSnapshot.notReady.duration != -1)
        #expect(PlaybackSnapshot.finished.duration == -1)
        #expect(PlaybackSnapshot.finished.position == -1)
    }
}

@Suite struct AirPlayVideoEngineTests {
    private func features(hls: Bool) throws -> UInt64 {
        let keyfile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gaxo-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("identity.pem")
        var config = EngineConfig(name: "GaxoHLSTest", deviceID: "02:11:22:33:44:88", keyfile: keyfile,
                                  basePort: 0, width: 1920, height: 1080, refreshRate: 60, maxFPS: 60,
                                  pinOnce: false, advertise: false, logLevel: 0)
        config.airPlayVideo = hls
        let engine = Engine(config: config)
        try engine.start()
        defer { engine.stop() }
        return engine.advertisedFeatures
    }

    /// Bits 0 (video) and 4 (HLS) tell iOS that YouTube may send AirPlay video.
    @Test func airPlayVideoAdvertisesVideoAndHLS() throws {
        #expect(try features(hls: true) & 0x11 == 0x11)
        #expect(try features(hls: false) & 0x11 == 0)
    }
}
