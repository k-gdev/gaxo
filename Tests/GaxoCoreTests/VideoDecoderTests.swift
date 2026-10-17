import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import GaxoCore

/// Collects decoded frames from a VideoDecoder.
private final class FrameCollector {
    private let lock = NSLock()
    private var sizes: [CGSize] = []

    func add(_ buffer: CVPixelBuffer) {
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        lock.withLock { sizes.append(size) }
    }

    var all: [CGSize] { lock.withLock { sizes } }
}

@Suite struct VideoDecoderTests {
    private func feed(_ decoder: VideoDecoder, _ units: [Data], startNanos: UInt64 = 0) {
        for (i, unit) in units.enumerated() {
            unit.withUnsafeBytes { decoder.decode($0, ntpNanos: startNanos + UInt64(i) * 16_666_667) }
        }
        decoder.flush()
    }

    @Test func decodesEncodedFrames() throws {
        let collector = FrameCollector()
        let decoder = VideoDecoder { buffer, _ in collector.add(buffer) }
        feed(decoder, try H264TestEncoder.encode(width: 640, height: 480, frames: 10))
        #expect(collector.all.count >= 9)
        #expect(collector.all.allSatisfy { $0 == CGSize(width: 640, height: 480) })
        #expect(decoder.dimensions == CGSize(width: 640, height: 480))
    }

    @Test func decoderRebuildsOnNewParameterSets() throws {
        let collector = FrameCollector()
        let decoder = VideoDecoder { buffer, _ in collector.add(buffer) }
        feed(decoder, try H264TestEncoder.encode(width: 640, height: 480, frames: 5))
        let before = collector.all.count
        feed(decoder, try H264TestEncoder.encode(width: 480, height: 640, frames: 5), startNanos: 1_000_000_000)
        #expect(decoder.dimensions == CGSize(width: 480, height: 640))
        #expect(collector.all.count >= before + 4)
        #expect(collector.all.last == CGSize(width: 480, height: 640))
    }

    @Test func framesBeforeParameterSetsAreDropped() throws {
        let collector = FrameCollector()
        let decoder = VideoDecoder { buffer, _ in collector.add(buffer) }
        let units = try H264TestEncoder.encode(width: 640, height: 480, frames: 6)
        feed(decoder, Array(units.dropFirst())) // the keyframe with SPS/PPS is missing
        #expect(collector.all.isEmpty)
        #expect(decoder.dimensions == nil)
    }

    @Test func resetForgetsTheFormat() throws {
        let decoder = VideoDecoder { _, _ in }
        feed(decoder, try H264TestEncoder.encode(width: 640, height: 480, frames: 2))
        #expect(decoder.dimensions != nil)
        decoder.reset()
        #expect(decoder.dimensions == nil)
    }
}
