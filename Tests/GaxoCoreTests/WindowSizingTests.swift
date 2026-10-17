import CoreGraphics
import Foundation
import Testing
@testable import GaxoCore

@Suite struct WindowSizingTests {
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 945)

    private func aspect(_ s: CGSize) -> CGFloat { s.width / s.height }
    private func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

    @Test func initialPortraitFitsSeventyPercent() {
        let video = CGSize(width: 886, height: 1920)
        let size = WindowSizing.initialContentSize(video: video, visible: visible)
        #expect(size.height <= 945 * 0.7 + 0.5)
        #expect(size.width <= 1512 * 0.7 + 0.5)
        #expect(close(aspect(size), aspect(video)))
        #expect(close(size.height, 945 * 0.7, 1), "portrait fills the height budget")
    }

    @Test func initialLandscapeFitsSeventyPercent() {
        let video = CGSize(width: 1920, height: 886)
        let size = WindowSizing.initialContentSize(video: video, visible: visible)
        #expect(close(size.width, 1512 * 0.7, 1))
        #expect(close(aspect(size), aspect(video)))
    }

    @Test func rotationKeepsCentreAndLongSide() {
        let current = CGRect(x: 600, y: 150, width: 300, height: 650)
        let rotated = WindowSizing.rotatedFrame(current: current, video: CGSize(width: 1080, height: 498), visible: visible)
        #expect(close(rotated.midX, current.midX, 0.5))
        #expect(close(rotated.midY, current.midY, 0.5))
        #expect(close(max(rotated.width, rotated.height), 650, 0.5))
        #expect(close(aspect(rotated.size), 1080 / 498))
        #expect(visible.contains(rotated))
    }

    @Test func rotationClampsToScreen() {
        // A tall window near the right edge turning landscape would overflow: shrink and shift inside.
        let current = CGRect(x: 1300, y: 20, width: 200, height: 900)
        let rotated = WindowSizing.rotatedFrame(current: current, video: CGSize(width: 1920, height: 886), visible: visible)
        #expect(visible.contains(rotated))
        #expect(close(aspect(rotated.size), 1920 / 886))
    }

    @Test func actualSizeUsesBackingScale() {
        let size = WindowSizing.actualSize(video: CGSize(width: 1920, height: 1080), backingScale: 2, visible: visible)
        #expect(size == CGSize(width: 960, height: 540))
        let big = WindowSizing.actualSize(video: CGSize(width: 1920, height: 1080), backingScale: 1, visible: visible)
        #expect(big.width <= visible.width && big.height <= visible.height, "shrunk to fit the screen")
        #expect(close(aspect(big), 1920 / 1080))
    }

    @Test func fitToScreenFills() {
        let size = WindowSizing.fitToScreen(video: CGSize(width: 498, height: 1080), visible: visible)
        #expect(close(size.height, 945, 0.5))
        #expect(close(aspect(size), 498 / 1080))
    }
}

@Suite struct ScreenshotNameTests {
    private let date = DateComponents(calendar: .init(identifier: .gregorian), timeZone: .current,
                                      year: 2026, month: 10, day: 17, hour: 13, minute: 5, second: 9).date!
    private let desktop = URL(fileURLWithPath: "/Users/test/Desktop", isDirectory: true)

    @Test func usesMacStyleName() {
        let url = ScreenshotName.url(in: desktop, date: date) { _ in false }
        #expect(url.lastPathComponent == "Gaxo Screenshot 2026-10-17 at 13.05.09.png")
    }

    @Test func screenshotNeverOverwrites() {
        var existing: Set<String> = ["Gaxo Screenshot 2026-10-17 at 13.05.09.png",
                                     "Gaxo Screenshot 2026-10-17 at 13.05.09 (2).png"]
        let url = ScreenshotName.url(in: desktop, date: date) { existing.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "Gaxo Screenshot 2026-10-17 at 13.05.09 (3).png")
        existing.insert(url.lastPathComponent)
    }
}
