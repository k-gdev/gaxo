import AudioToolbox
import AVFoundation
import Foundation

/// Decodes AirPlay audio packets to 44.1 kHz stereo Float32 PCM.
/// AirPlay sends a codec type (`ct`) instead of a magic cookie; the cookies
/// below are the fixed ones UxPlay uses for each type (renderers/audio_renderer.c).
///
/// Uses AudioToolbox's AudioConverter directly: AVAudioConverter does not hand
/// an `AVAudioFormat.magicCookie` to the decoder, which breaks ALAC.
public final class AudioDecoder {
    public enum DecoderError: Error, Equatable {
        case unsupportedCodec(UInt8)
        case converter
    }

    /// ct=2 ALAC: 'alac' atom wrapping ALACSpecificConfig (352 spf, 16 bit, 2 ch, 44100 Hz).
    static let alacCookie: [UInt8] = [
        0x00, 0x00, 0x00, 0x24, 0x61, 0x6C, 0x61, 0x63, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x60, 0x00, 0x10, 0x28, 0x0A, 0x0E, 0x02, 0x00, 0xFF,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAC, 0x44,
    ]

    public static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!

    /// Returned by the input callback when the single packet has been consumed.
    private static let noDataNow: OSStatus = 0x6E6F_6474 // 'nodt'

    public let codec: UInt8
    private let converter: AudioConverterRef
    private let framesPerPacket: AVAudioFrameCount
    private let feed = PacketFeed()

    public init(codec: UInt8) throws {
        let formatID: AudioFormatID
        let flags: AudioFormatFlags
        var cookie: [UInt8]
        switch codec {
        case 8: // AAC-ELD, used for screen mirroring
            (formatID, framesPerPacket, flags, cookie) = (
                kAudioFormatMPEG4AAC_ELD, 480, 0, Self.esds(audioSpecificConfig: [0xF8, 0xE8, 0x50, 0x00]))
        case 4: // AAC-LC
            (formatID, framesPerPacket, flags, cookie) = (
                kAudioFormatMPEG4AAC, 1024, 0, Self.esds(audioSpecificConfig: [0x12, 0x10]))
        case 2: // ALAC, used for music-only AirPlay
            (formatID, framesPerPacket, flags, cookie) = (
                kAudioFormatAppleLossless, 352, AudioFormatFlags(kAppleLosslessFormatFlag_16BitSourceData),
                Self.alacCookie)
        default:
            throw DecoderError.unsupportedCodec(codec)
        }
        self.codec = codec

        var input = AudioStreamBasicDescription(
            mSampleRate: 44_100, mFormatID: formatID, mFormatFlags: flags, mBytesPerPacket: 0,
            mFramesPerPacket: framesPerPacket, mBytesPerFrame: 0, mChannelsPerFrame: 2,
            mBitsPerChannel: 0, mReserved: 0)
        var output = Self.outputFormat.streamDescription.pointee
        var newConverter: AudioConverterRef?
        guard AudioConverterNew(&input, &output, &newConverter) == noErr, let newConverter else {
            throw DecoderError.converter
        }
        guard AudioConverterSetProperty(newConverter, kAudioConverterDecompressionMagicCookie,
                                        UInt32(cookie.count), &cookie) == noErr
        else {
            AudioConverterDispose(newConverter)
            throw DecoderError.converter
        }
        converter = newConverter
    }

    deinit {
        AudioConverterDispose(converter)
    }

    /// Apple's AAC decoders take their magic cookie as an MPEG-4 `esds`
    /// descriptor (the form Apple's own AAC encoders emit), not the bare
    /// AudioSpecificConfig that AirPlay/UxPlay pass to ffmpeg.
    static func esds(audioSpecificConfig asc: [UInt8]) -> [UInt8] {
        func length(_ n: Int) -> [UInt8] { [0x80, 0x80, 0x80, UInt8(n)] }
        let decoderSpecificInfo = [0x05] + length(asc.count) + asc
        let decoderConfig: [UInt8] = [0x04] + length(13 + decoderSpecificInfo.count)
            + [0x40, 0x14] // MPEG-4 audio, audio stream
            + [0x00, 0x00, 0x00] + [0x00, 0x00, 0x00, 0x00] + [0x00, 0x00, 0x00, 0x00] // buffer size, bitrates
            + decoderSpecificInfo
        let slConfig: [UInt8] = [0x06] + length(1) + [0x02]
        return [0x03] + length(3 + decoderConfig.count + slConfig.count) + [0x00, 0x00, 0x00]
            + decoderConfig + slConfig
    }

    /// Decodes one packet. Returns nil for packets that produce no audio
    /// (decoder start-up delay, corrupt data).
    public func decode(_ packet: UnsafeRawBufferPointer) -> AVAudioPCMBuffer? {
        guard let base = packet.baseAddress, packet.count > 0,
              let output = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: framesPerPacket * 2)
        else { return nil }
        output.frameLength = output.frameCapacity // the buffer list must advertise its capacity

        feed.load(base, count: packet.count)
        var frames = output.frameCapacity
        let status = AudioConverterFillComplexBuffer(
            converter, Self.inputProc, Unmanaged.passUnretained(feed).toOpaque(),
            &frames, output.mutableAudioBufferList, nil)
        guard status == noErr || status == Self.noDataNow else {
            AudioConverterReset(converter)
            output.frameLength = 0
            return nil
        }
        output.frameLength = frames
        return frames > 0 ? output : nil
    }

    private static let inputProc: AudioConverterComplexInputDataProc = { _, ioPackets, ioData, outDescription, user in
        let feed = Unmanaged<PacketFeed>.fromOpaque(user!).takeUnretainedValue()
        guard !feed.consumed, let data = feed.data else {
            ioPackets.pointee = 0
            return AudioDecoder.noDataNow
        }
        feed.consumed = true
        ioPackets.pointee = 1
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: data)
        ioData.pointee.mBuffers.mDataByteSize = UInt32(feed.count)
        ioData.pointee.mBuffers.mNumberChannels = 2
        feed.description.pointee = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(feed.count))
        outDescription?.pointee = feed.description
        return noErr
    }
}

/// The one packet handed to the converter's input callback.
private final class PacketFeed {
    var data: UnsafeRawPointer?
    var count = 0
    var consumed = true
    let description = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)

    deinit {
        description.deallocate()
    }

    func load(_ data: UnsafeRawPointer, count: Int) {
        self.data = data
        self.count = count
        consumed = false
    }
}

/// AirPlay sends volume in dB: 0 is full, -30 the quietest audible step, -144 mute.
public enum AirPlayVolume {
    public static func gain(db: Float) -> Float {
        if db <= -30 { return 0 }
        return min(1, pow(10, db / 20))
    }
}
