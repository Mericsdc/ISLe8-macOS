// Draws ISLe8's app icon into ISLe8/Resources/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift
import AppKit
import SwiftUI

let canvas: CGFloat = 1024
// Apple's macOS icon grid: an 824 pt body with continuous corners, centered.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func linear(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func drawIcon(in context: CGContext) {
    let shape = RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: body).cgPath

    // The body, with the soft shadow macOS icons sit on.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x101012))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(
        linear([color(0x2C2E35), color(0x0B0B0D)]),
        start: CGPoint(x: 0, y: body.maxY),
        end: CGPoint(x: 0, y: body.minY),
        options: []
    )
    // A warm glow under the island, as if the song's artwork lit it from below.
    context.drawRadialGradient(
        linear([color(0xFF7A3D, 0.42), color(0xFF375F, 0.0)]),
        startCenter: CGPoint(x: 512, y: 600), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 560), endRadius: 430,
        options: []
    )
    context.restoreGState()

    // A hairline along the top edge.
    context.saveGState()
    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, 0.10))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    // The island.
    let island = CGRect(x: 512 - 300, y: 640 - 84, width: 600, height: 168)
    let capsule = CGPath(roundedRect: island, cornerWidth: 84, cornerHeight: 84, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: color(0x000000, 0.6))
    context.addPath(capsule)
    context.setFillColor(color(0x000000))
    context.fillPath()
    context.restoreGState()
    context.addPath(capsule)
    context.setStrokeColor(color(0xFFFFFF, 0.08))
    context.setLineWidth(2)
    context.strokePath()

    // Artwork on the left.
    let art = CGRect(x: island.minX + 34, y: island.midY - 50, width: 100, height: 100)
    context.saveGState()
    context.addPath(CGPath(roundedRect: art, cornerWidth: 26, cornerHeight: 26, transform: nil))
    context.clip()
    context.drawLinearGradient(
        linear([color(0xFFB340), color(0xFF375F)]),
        start: CGPoint(x: art.minX, y: art.maxY),
        end: CGPoint(x: art.maxX, y: art.minY),
        options: []
    )
    context.restoreGState()

    // Audio bars on the right.
    let heights: [CGFloat] = [52, 92, 70, 40]
    let barWidth: CGFloat = 20
    let gap: CGFloat = 14
    var x = island.maxX - 46 - CGFloat(heights.count) * barWidth - CGFloat(heights.count - 1) * gap
    for height in heights {
        let bar = CGRect(x: x, y: island.midY - height / 2, width: barWidth, height: height)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        x += barWidth + gap
    }
    context.setFillColor(color(0xFFFFFF, 0.92))
    context.fillPath()

    // The wordmark.
    let font = NSFont.systemFont(ofSize: 132, weight: .bold)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 132) } ?? font
    let text = NSAttributedString(string: "ISLe8", attributes: [
        .font: rounded,
        .foregroundColor: NSColor(white: 1, alpha: 0.9),
        .kern: -2,
    ])
    let size = text.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    text.draw(at: CGPoint(x: 512 - size.width / 2, y: 250))
    NSGraphicsContext.restoreGraphicsState()
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

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ISLe8/Resources/Assets.xcassets")
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
