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
