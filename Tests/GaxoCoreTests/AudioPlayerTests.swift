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

    /// Start and flush (engine threads), stop and Sound on/off (main thread) and device
    /// changes (Core Audio's thread) arrive at once; they must not run into each other.
    @Test func controlsFromSeveralThreadsAtOnce() throws {
        let player = AudioPlayer()
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: AudioDecoder.outputFormat, frameCapacity: 480))
        buffer.frameLength = 480
        DispatchQueue.concurrentPerform(iterations: 4) { lane in
            for i in 0..<25 {
                switch lane {
                case 0:
                    try? player.start()
                    player.flush()
                case 1:
                    player.stop()
                case 2:
                    player.enabled = i.isMultiple(of: 2)
                    player.schedule(buffer)
                default:
                    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: player.engine)
                }
            }
        }
        player.stop()
        #expect(!player.isRunning)
        try player.start()
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
