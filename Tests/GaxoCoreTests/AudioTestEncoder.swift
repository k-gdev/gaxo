import AVFoundation
import Foundation

/// Encodes a 440 Hz stereo sine with Apple's encoders into raw packets, the
/// way AirPlay sends them (one packet per RTP payload).
enum AudioTestEncoder {
    enum EncoderError: Error { case format, converter, encode(String) }

    static func encode(formatID: AudioFormatID, framesPerPacket: UInt32, flags: AudioFormatFlags = 0,
                       seconds: Double = 1) throws -> [Data] {
        let sampleRate = 44_100.0
        guard let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                            channels: 2, interleaved: false)
        else { throw EncoderError.format }
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: formatID, mFormatFlags: flags, mBytesPerPacket: 0,
            mFramesPerPacket: framesPerPacket, mBytesPerFrame: 0, mChannelsPerFrame: 2,
            mBitsPerChannel: 0, mReserved: 0)
        guard let outFormat = AVAudioFormat(streamDescription: &asbd),
              let converter = AVAudioConverter(from: pcmFormat, to: outFormat)
        else { throw EncoderError.converter }

        let total = AVAudioFrameCount(sampleRate * seconds)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: total) else { throw EncoderError.format }
        pcm.frameLength = total
        for ch in 0..<2 {
            let samples = pcm.floatChannelData![ch]
            for i in 0..<Int(total) {
                samples[i] = 0.5 * sin(2 * .pi * 440 * Float(i) / Float(sampleRate))
            }
        }

        var packets: [Data] = []
        var supplied = false
        var finished = false
        while !finished {
            let out = AVAudioCompressedBuffer(format: outFormat, packetCapacity: 8,
                                              maximumPacketSize: max(converter.maximumOutputPacketSize, 8192))
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return pcm
            }
            if status == .error { throw EncoderError.encode(error?.localizedDescription ?? "?") }
            for i in 0..<Int(out.packetCount) {
                let d = out.packetDescriptions![i]
                packets.append(Data(bytes: out.data.advanced(by: Int(d.mStartOffset)), count: Int(d.mDataByteSize)))
            }
            finished = status == .endOfStream || (out.packetCount == 0 && supplied)
        }
        return packets
    }
}
