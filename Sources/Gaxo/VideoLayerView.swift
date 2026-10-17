import AppKit
import AVFoundation
import CoreMedia
import CoreVideo

/// Shows decoded frames, letterboxed to the phone's shape, as soon as they arrive.
final class VideoLayerView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let queue = DispatchQueue(label: "com.gaxo.video-display")
    private var format: CMVideoFormatDescription? // used on `queue` only
    private let lock = NSLock()
    private var newestFrame: CVPixelBuffer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(displayLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Mirrored iPhone screen")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The most recent frame (for screenshots).
    var lastFrame: CVPixelBuffer? {
        lock.withLock { newestFrame }
    }

    /// Callable from any thread.
    func display(_ pixelBuffer: CVPixelBuffer) {
        lock.withLock { newestFrame = pixelBuffer }
        queue.async { [self] in
            guard let sample = makeSample(pixelBuffer) else { return }
            let renderer = displayLayer.sampleBufferRenderer
            if renderer.status == .failed { renderer.flush() }
            renderer.enqueue(sample)
        }
    }

    /// Drops the picture (session over).
    func clear() {
        lock.withLock { newestFrame = nil }
        queue.async { [self] in
            displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        }
    }

    private func makeSample(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        if format == nil || !CMVideoFormatDescriptionMatchesImageBuffer(format!, imageBuffer: pixelBuffer) {
            format = nil
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer,
                                                         formatDescriptionOut: &format)
        }
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample
        else { return nil }
        // v1: lowest latency — show each frame immediately instead of scheduling by timestamp.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
