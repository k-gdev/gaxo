import AppKit

/// Gaxo's mark from the mockup: a phone in front of a window, drawn in code so
/// the menu bar glyph, the status window and the app icon share one source.
enum GaxoArt {
    static let teal = NSColor(srgbRed: 0x0B / 255.0, green: 0x6E / 255.0, blue: 0x69 / 255.0, alpha: 1)

    /// Draws the glyph (18×18 design units, top-left origin) into `rect`.
    /// `phoneFill` hides the window's lines behind the phone; nil punches them out.
    static func drawGlyph(in rect: CGRect, stroke: NSColor, lineWidth: CGFloat, phoneFill: NSColor?) {
        let s = rect.width / 18
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * s, y: rect.minY + y * s, width: w * s, height: h * s)
        }
        let window = NSBezierPath(roundedRect: box(5.5, 3, 11, 8.5), xRadius: 1.5 * s, yRadius: 1.5 * s)
        let phone = NSBezierPath(roundedRect: box(1.5, 6, 5.5, 9.5), xRadius: 1.2 * s, yRadius: 1.2 * s)
        window.lineWidth = lineWidth * s
        phone.lineWidth = lineWidth * s

        stroke.setStroke()
        window.stroke()
        if let phoneFill {
            phoneFill.setFill()
            phone.fill()
        } else if let context = NSGraphicsContext.current {
            context.compositingOperation = .clear
            phone.fill()
            context.compositingOperation = .sourceOver
        }
        phone.stroke()
    }

    /// Template image for the menu bar (adapts to light/dark).
    static func menuBarGlyph() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            drawGlyph(in: rect, stroke: .black, lineWidth: 1.5, phoneFill: nil)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Gaxo"
        return image
    }

    /// The app icon: teal rounded square with a white glyph, on the macOS icon grid.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let tile = rect.insetBy(dx: size * 0.1, dy: size * 0.1)
            teal.setFill()
            NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225).fill()
            drawGlyph(in: tile.insetBy(dx: tile.width * 0.17, dy: tile.width * 0.17),
                      stroke: .white, lineWidth: 1.25, phoneFill: teal)
            return true
        }
    }
}

/// Writes the app icon as an .iconset folder (used by scripts/build-app.sh via
/// `Gaxo --write-iconset <dir>`), so the bundle icon and the in-app art match.
enum IconExport {
    static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = base * scale
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png(of: GaxoArt.appIcon(size: CGFloat(pixels)), pixels: pixels)
                    .write(to: directory.appendingPathComponent(name))
            }
        }
    }

    private static func png(of image: NSImage, pixels: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
