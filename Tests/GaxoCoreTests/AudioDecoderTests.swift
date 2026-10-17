import AVFoundation
import Foundation
import Testing
@testable import GaxoCore

@Suite struct AudioDecoderTests {
    /// Decodes every packet; returns total frames and the RMS of the output.
    private func decodeAll(_ decoder: AudioDecoder, _ packets: [Data]) -> (frames: Int, rms: Float) {
        var frames = 0
        var sum: Float = 0
        for packet in packets {
            guard let pcm = packet.withUnsafeBytes({ decoder.decode($0) }) else { continue }
            #expect(pcm.format.sampleRate == 44_100)
            #expect(pcm.format.channelCount == 2)
            #expect(pcm.format.commonFormat == .pcmFormatFloat32)
            let left = pcm.floatChannelData![0]
            for i in 0..<Int(pcm.frameLength) { sum += left[i] * left[i] }
            frames += Int(pcm.frameLength)
        }
        return (frames, frames > 0 ? (sum / Float(frames)).squareRoot() : 0)
    }

    @Test func decodesAacEld() throws {
        let packets = try AudioTestEncoder.encode(formatID: kAudioFormatMPEG4AAC_ELD, framesPerPacket: 480)
        let decoder = try AudioDecoder(codec: 8)
        let (frames, rms) = decodeAll(decoder, packets)
        #expect(abs(frames - 44_100) <= 2 * 480, "decoded \(frames) frames")
        #expect(rms > 0.01)
    }

    @Test func decodesAlac() throws {
        let packets = try AudioTestEncoder.encode(formatID: kAudioFormatAppleLossless, framesPerPacket: 352,
                                                  flags: AudioFormatFlags(kAppleLosslessFormatFlag_16BitSourceData))
        let decoder = try AudioDecoder(codec: 2)
        let (frames, rms) = decodeAll(decoder, packets)
        #expect(abs(frames - 44_100) <= 2 * 352, "decoded \(frames) frames")
        #expect(rms > 0.01)
    }

    /// Same layout as the cookie Apple's AAC-ELD encoder emits, with zeroed buffer/bitrate fields.
    @Test func esdsWrapsAudioSpecificConfig() {
        let esds = AudioDecoder.esds(audioSpecificConfig: [0xF8, 0xE8, 0x50, 0x00])
        let hex = esds.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "038080802400000004808080164014000000000000000000000005808080"
            + "04f8e85000068080800102")
    }

    @Test func unknownCodecThrows() {
        #expect(throws: AudioDecoder.DecoderError.unsupportedCodec(3)) { try AudioDecoder(codec: 3) }
    }

    @Test func garbageDoesNotCrash() throws {
        let decoder = try AudioDecoder(codec: 8)
        let junk = Data((0..<200).map { UInt8($0 & 0xFF) })
        _ = junk.withUnsafeBytes { decoder.decode($0) }
    }
}

@Suite struct AirPlayVolumeTests {
    @Test func volumeMapping() {
        #expect(AirPlayVolume.gain(db: -144) == 0)
        #expect(AirPlayVolume.gain(db: -30) == 0)
        #expect(AirPlayVolume.gain(db: 0) == 1)
        #expect(abs(AirPlayVolume.gain(db: -6) - 0.501) < 0.001)
        #expect(AirPlayVolume.gain(db: 3) == 1)
    }
}
