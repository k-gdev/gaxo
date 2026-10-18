import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import Testing
@testable import Gaxo
@testable import GaxoCore

/// Take Screenshot saves what the mirror window shows. Opens a small window briefly.
@MainActor @Suite(.serialized) struct ScreenshotTests {
    /// During an AirPlay video the window shows the video, not the last mirrored frame.
    @Test func screenshotDuringAVideoIsTheVideo() async throws {
        let movie = FileManager.default.temporaryDirectory.appendingPathComponent("gaxo-blue-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: movie) }
        try await writeMovie(to: movie, colour: (r: 0, g: 0, b: 255))

        let mirror = MirrorWindowController()
        mirror.videoView.display(try solidBuffer(colour: (r: 255, g: 0, b: 0))) // the last mirrored frame: red
        let player = VideoPlayerController(mirror: mirror)
        player.play(url: movie.absoluteString, startPosition: 0)
        defer {
            player.stop()
            mirror.closeForSessionEnd()
        }

        var colour: (r: UInt8, g: UInt8, b: UInt8)?
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            colour = mirror.videoView.screenshotFrame.map(centreColour)
            if let colour, colour.b > 200 { break }
        }
        let shot = try #require(colour, "no picture to save")
        #expect(shot.b > 200 && shot.r < 60, "saved \(shot), the video is blue and the old mirror frame red")
    }

    // MARK: - Helpers

    private func solidBuffer(colour: (r: UInt8, g: UInt8, b: UInt8), size: Int = 128) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, attributes, &made)
        let buffer = try #require(made)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<size {
            for x in 0..<size {
                let pixel = base + y * rowBytes + x * 4
                (pixel[0], pixel[1], pixel[2], pixel[3]) = (colour.b, colour.g, colour.r, 255)
            }
        }
        return buffer
    }

    /// A 3 s H.264 movie of one colour.
    private func writeMovie(to url: URL, colour: (r: UInt8, g: UInt8, b: UInt8)) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 128,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0...6 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(try solidBuffer(colour: colour), withPresentationTime: CMTime(value: Int64(frame), timescale: 2))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed, "\(String(describing: writer.error))")
    }

    private func centreColour(_ buffer: CVPixelBuffer) -> (r: UInt8, g: UInt8, b: UInt8) {
        let image = CIImage(cvPixelBuffer: buffer)
        let centre = CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1)
        var rgba = [UInt8](repeating: 0, count: 4)
        CIContext().render(image, toBitmap: &rgba, rowBytes: 4, bounds: centre, format: .RGBA8, colorSpace: nil)
        return (rgba[0], rgba[1], rgba[2])
    }
}
