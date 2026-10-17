import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Decodes the mirrored H.264 stream with VideoToolbox (hardware) into
/// IOSurface-backed pixel buffers. Frames that arrive before the first
/// SPS/PPS are dropped; new SPS/PPS (e.g. the phone rotated) rebuild the
/// decoder.
public final class VideoDecoder {
    public typealias FrameHandler = (CVPixelBuffer, CMTime) -> Void

    private let onFrame: FrameHandler
    private let lock = NSLock()
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var parameterSets: H264ParameterSets?
    private var _dimensions: CGSize?

    /// `onFrame` is called on the decoding thread.
    public init(onFrame: @escaping FrameHandler) {
        self.onFrame = onFrame
    }

    deinit {
        if let session { VTDecompressionSessionInvalidate(session) }
    }

    /// Display size of the current stream (clean aperture), nil before the first SPS/PPS.
    public var dimensions: CGSize? {
        lock.withLock { _dimensions }
    }

    /// Decodes one Annex-B access unit. `ntpNanos` becomes the frame's timestamp.
    public func decode(_ annexB: UnsafeRawBufferPointer, ntpNanos: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        if let sets = AnnexB.parameterSets(in: annexB), sets != parameterSets {
            configure(sets)
        }
        guard let session, let format else { return }

        let avcc = AnnexB.avcc(annexB, excluding: [7, 8, 9]) // SPS, PPS, access unit delimiter
        guard !avcc.isEmpty,
              let sample = Self.makeSample(avcc, format: format,
                                           pts: CMTime(value: CMTimeValue(ntpNanos), timescale: 1_000_000_000))
        else { return }

        let handler = onFrame
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sample, flags: [], infoFlagsOut: nil
        ) { status, _, imageBuffer, pts, _ in
            guard status == noErr, let imageBuffer else { return }
            handler(imageBuffer, pts)
        }
        if status == kVTInvalidSessionErr {
            Log.error("Video decoder session became invalid; rebuilding")
            makeSession()
        } else if status != noErr {
            Log.debug("VTDecompressionSessionDecodeFrame failed: \(status)")
        }
    }

    /// Waits for frames still being decoded.
    public func flush() {
        lock.withLock {
            if let session { VTDecompressionSessionWaitForAsynchronousFrames(session) }
        }
    }

    /// Forgets the stream format (new session from the phone).
    public func reset() {
        lock.withLock {
            if let session { VTDecompressionSessionInvalidate(session) }
            session = nil
            format = nil
            parameterSets = nil
            _dimensions = nil
        }
    }

    // MARK: - Private (lock held)

    private func configure(_ sets: H264ParameterSets) {
        parameterSets = sets
        format = Self.makeFormat(sets)
        if let format {
            _dimensions = CMVideoFormatDescriptionGetPresentationDimensions(
                format, usePixelAspectRatio: false, useCleanAperture: true)
            Log.info("Video format \(Int(_dimensions!.width))×\(Int(_dimensions!.height))")
        } else {
            _dimensions = nil
            Log.error("Could not read the stream's SPS/PPS")
        }
        makeSession()
    }

    private func makeSession() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        guard let format else { return }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: nil, formatDescription: format, decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
            decompressionSessionOut: &newSession)
        if status != noErr { Log.error("VTDecompressionSessionCreate failed: \(status)") }
        session = newSession
    }

    private static func makeFormat(_ sets: H264ParameterSets) -> CMVideoFormatDescription? {
        var format: CMFormatDescription?
        let status = sets.sps.withUnsafeBytes { sps in
            sets.pps.withUnsafeBytes { pps -> OSStatus in
                let pointers = [sps.bindMemory(to: UInt8.self).baseAddress!,
                                pps.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            }
        }
        return status == noErr ? format : nil
    }

    private static func makeSample(_ data: Data, format: CMVideoFormatDescription, pts: CMTime) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: data.count,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
            let block
        else { return nil }
        let copied = data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == noErr else { return nil }

        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var size = data.count
        guard CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
            sampleSizeArray: &size, sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }
}
