import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Gaxo
@testable import GaxoCore

/// App-level behaviour found in the final review. These open a small window briefly.
@MainActor @Suite(.serialized) struct AppFixesTests {
    /// Settings say sound changes apply live: turning sound on mid-session must start playback.
    @Test func soundTurnedOnMidSessionStartsPlaying() {
        let audio = AudioPlayer()
        let router = MediaRouter(mirror: MirrorWindowController(), audioPlayer: audio)
        router.playSound = false
        router.audioFormat(codec: 8, samplesPerFrame: 480)
        router.playSound = true
        #expect(audio.isRunning)
        audio.stop()
    }

    /// "Close window when mirroring stops" off: the next session keeps the window where it was.
    @Test func windowLeftOpenStaysWhereTheUserPutIt() throws {
        let mirror = MirrorWindowController()
        mirror.videoSizeChanged(CGSize(width: 498, height: 1080))
        let window = try #require(mirror.window)
        let visible = try #require(window.screen ?? NSScreen.main).visibleFrame
        let placed = NSRect(x: visible.minX + 40, y: visible.minY + 40,
                            width: window.frame.width * 0.8, height: window.frame.height * 0.8)
        window.setFrame(placed, display: false)
        let before = window.frame

        mirror.resetVideo() // the session ended; the window stays open
        mirror.videoSizeChanged(CGSize(width: 498, height: 1080)) // the next session

        #expect(abs(window.frame.midX - before.midX) < 1)
        #expect(abs(window.frame.midY - before.midY) < 1)
        #expect(abs(window.frame.height - before.height) < 2)
        mirror.closeForSessionEnd()
    }

    /// A video AVPlayer cannot load must end (the iPhone otherwise spins forever).
    @Test func failedVideoIsReportedAsFinished() async throws {
        let mirror = MirrorWindowController()
        let player = VideoPlayerController(mirror: mirror)
        player.play(url: "http://localhost:9/master.m3u8", startPosition: 0) // like the engine's playlist failing to load
        for _ in 0..<100 where player.currentPlayback() != .finished {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(player.currentPlayback() == .finished)
        player.stop()
        try await Task.sleep(for: .milliseconds(50))
        mirror.closeForSessionEnd()
    }
}
