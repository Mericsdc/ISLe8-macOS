import AppKit
import ImageIO

enum Artwork {
    /// Decodes artwork straight to a small thumbnail (the island never draws it larger than
    /// ~80 pt) and picks an accent color from it. Runs once per track.
    static func decode(_ data: Data, maxPixelSize: Int = 240) -> (image: NSImage, accent: NSColor)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let size = NSSize(width: image.width, height: image.height)
        return (NSImage(cgImage: image, size: size), accent(of: image))
    }

    /// The image's average color, pushed bright enough to read on black.
    private static func accent(of image: CGImage) -> NSColor {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return .white }

        let average = NSColor(
            deviceRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // Near-gray artwork stays neutral instead of turning into a muddy tint.
        let tunedSaturation = saturation < 0.12 ? 0 : min(max(saturation, 0.45), 0.85)
        return NSColor(hue: hue, saturation: tunedSaturation, brightness: max(brightness, 0.85), alpha: 1)
    }
}
