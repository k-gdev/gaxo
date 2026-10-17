import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Encodes real H.264 with VideoToolbox and returns it the way the UxPlay
/// engine delivers it: Annex-B access units, SPS + PPS in front of keyframes.
enum H264TestEncoder {
    static func encode(width: Int, height: Int, frames: Int) throws -> [Data] {
        var session: VTCompressionSession?
        var status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        guard status == noErr, let session else { throw EncoderError.create(status) }
        defer { VTCompressionSessionInvalidate(session) }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 30 as CFNumber)

        var output: [Data] = []
        let lock = NSLock()
        for i in 0..<frames {
            let pixelBuffer = try makePattern(width: width, height: height, seed: i)
            let pts = CMTime(value: CMTimeValue(i), timescale: 30)
            status = VTCompressionSessionEncodeFrame(
                session, imageBuffer: pixelBuffer, presentationTimeStamp: pts, duration: .invalid,
                frameProperties: nil, infoFlagsOut: nil
            ) { status, _, sampleBuffer in
                guard status == noErr, let sampleBuffer, let data = annexB(sampleBuffer) else { return }
                lock.withLock { output.append(data) }
            }
            guard status == noErr else { throw EncoderError.encode(status) }
        }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        return lock.withLock { output }
    }

    enum EncoderError: Error {
        case create(OSStatus), encode(OSStatus), pixelBuffer(CVReturn)
    }

    private static func makePattern(width: Int, height: Int, seed: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                         [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard result == kCVReturnSuccess, let buffer else { throw EncoderError.pixelBuffer(result) }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let p = base + y * stride + x * 4
                p[0] = UInt8((x + seed * 4) & 0xFF)
                p[1] = UInt8((y + seed * 2) & 0xFF)
                p[2] = UInt8((x ^ y) & 0xFF)
                p[3] = 0xFF
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// AVCC sample → Annex-B, with SPS/PPS prepended to keyframes.
    private static func annexB(_ sample: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var out = Data()
        let startCode: [UInt8] = [0, 0, 0, 1]

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        if !notSync, let format = CMSampleBufferGetFormatDescription(sample) {
            for index in 0..<2 {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                if let pointer {
                    out.append(contentsOf: startCode)
                    out.append(pointer, count: size)
                }
            }
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let dataPointer else { return nil }
        let bytes = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: UInt8.self)
        var offset = 0
        while offset + 4 <= length {
            let n = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            offset += 4
            guard offset + n <= length else { break }
            out.append(contentsOf: startCode)
            out.append(bytes + offset, count: n)
            offset += n
        }
        return out
    }
}
