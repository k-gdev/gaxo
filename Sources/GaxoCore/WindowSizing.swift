import CoreGraphics
import Foundation

/// Geometry for the mirror window. All sizes are content sizes in points;
/// `visible` is the screen area the content may use.
public enum WindowSizing {
    /// First open: as large as fits in 70% of the screen, keeping the phone's shape.
    public static func initialContentSize(video: CGSize, visible: CGRect) -> CGSize {
        fit(video, in: CGSize(width: visible.width * 0.7, height: visible.height * 0.7))
    }

    /// The phone rotated: keep the window's centre and its long side, take the
    /// new shape, and stay on screen (shrinking and shifting if needed).
    public static func rotatedFrame(current: CGRect, video: CGSize, visible: CGRect) -> CGRect {
        guard video.width > 0, video.height > 0 else { return current }
        let long = max(current.width, current.height)
        var size = video.width >= video.height
            ? CGSize(width: long, height: long * video.height / video.width)
            : CGSize(width: long * video.width / video.height, height: long)
        if size.width > visible.width || size.height > visible.height {
            size = fit(video, in: visible.size)
        }
        var frame = CGRect(x: current.midX - size.width / 2, y: current.midY - size.height / 2,
                           width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    /// One video pixel per screen pixel, shrunk if that would not fit.
    public static func actualSize(video: CGSize, backingScale: CGFloat, visible: CGRect) -> CGSize {
        let scale = max(backingScale, 1)
        let size = CGSize(width: video.width / scale, height: video.height / scale)
        if size.width <= visible.width, size.height <= visible.height { return size }
        return fit(video, in: visible.size)
    }

    /// The largest size with the phone's shape that fits the screen.
    public static func fitToScreen(video: CGSize, visible: CGRect) -> CGSize {
        fit(video, in: visible.size)
    }

    static func fit(_ video: CGSize, in bounds: CGSize) -> CGSize {
        guard video.width > 0, video.height > 0 else { return bounds }
        let scale = min(bounds.width / video.width, bounds.height / video.height)
        return CGSize(width: (video.width * scale).rounded(), height: (video.height * scale).rounded())
    }
}

/// Screenshot file names, macOS style, never reusing an existing name.
public enum ScreenshotName {
    public static func url(in directory: URL, date: Date = Date(),
                           fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Gaxo Screenshot \(formatter.string(from: date))"
        var url = directory.appendingPathComponent("\(base).png")
        var n = 2
        while fileExists(url) {
            url = directory.appendingPathComponent("\(base) (\(n)).png")
            n += 1
        }
        return url
    }
}
