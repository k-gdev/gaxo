import CoreImage
import CoreVideo
import Foundation
import GaxoCore
import ImageIO
import UniformTypeIdentifiers

/// Saves a mirrored frame as a PNG on the Desktop, never replacing an existing file.
enum Screenshot {
    enum SaveError: Error {
        case render, write(URL)
    }

    static func save(_ pixelBuffer: CVPixelBuffer) throws -> URL {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { throw SaveError.render }

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let url = ScreenshotName.url(in: desktop)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw SaveError.write(url) }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw SaveError.write(url) }
        return url
    }
}
