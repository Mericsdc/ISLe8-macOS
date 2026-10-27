// Builds ISLe8's app icon from the logo artwork into ISLe8/Resources/Assets.xcassets/AppIcon.appiconset.
// The artwork's rounded square (everything that isn't transparent) is fitted to Apple's macOS
// icon grid: an 824 pt body with continuous corners, centred on a 1024 canvas, on the soft
// shadow macOS icons sit on.
// Usage: swift scripts/make-icon.swift <logo image> [Assets.xcassets folder]
import AppKit
import SwiftUI

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

let arguments = CommandLine.arguments
guard arguments.count >= 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("Usage: swift scripts/make-icon.swift <logo image> [Assets.xcassets folder]")
    exit(1)
}

/// The artwork without the transparent margin around its rounded square.
func trimmed(_ image: CGImage) -> CGImage {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    // Rows run top to bottom in memory, as CGImage cropping counts them.
    var minX = width, maxX = -1, minY = height, maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= 128 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { return image }
    return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? image
}

let logo = trimmed(artwork)

func drawIcon(in context: CGContext) {
    let shape = RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: body).cgPath

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(CGColor(srgbRed: 0.01, green: 0.07, blue: 0.19, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // The artwork fills the body; its own corners are a touch tighter, so the system shape
    // trims them.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.draw(logo, in: body)
    context.restoreGState()
}

func render(pixels: Int) -> Data {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: context)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let folder = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "ISLe8/Resources/Assets.xcassets")
let iconSet = folder.appending(path: "AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: folder.appending(path: "Contents.json"))

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: iconSet.appending(path: name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appending(path: "Contents.json"))
print(iconSet.path)
