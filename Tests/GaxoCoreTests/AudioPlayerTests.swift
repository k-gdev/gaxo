import AVFoundation
import Testing
@testable import GaxoCore

@Suite struct AudioPlayerTests {
    /// Switching the Mac's output (e.g. turning a headset on) stops AVAudioEngine
    /// and posts AVAudioEngineConfigurationChange; playback must resume by itself.
    @Test func restartsAfterOutputDeviceChange() throws {
        let player = AudioPlayer()
        try player.start()
        #expect(player.isRunning)

        player.engine.stop() // what a device switch does to the engine
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: player.engine)
        #expect(player.isRunning)
        player.stop()
    }

    @Test func stoppedPlayerStaysStoppedOnDeviceChange() throws {
        let player = AudioPlayer()
        try player.start()
        player.stop()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: player.engine)
        #expect(!player.isRunning)
    }
}
