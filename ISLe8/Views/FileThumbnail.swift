import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// A Quick Look thumbnail of a file, with its Finder icon until the thumbnail is ready.
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // The icon for the file's type: unlike icon(forFile:), it never touches the
                // file, which in a protected folder could wait on a permission prompt.
                Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            thumbnail = await ThumbnailCache.shared.thumbnail(for: url, size: size)
        }
    }
}

/// Thumbnails are made once per file and size, and only while they are on screen.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func thumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let key = "\(url.path)#\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        let image: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { @Sendable representation, _ in
                continuation.resume(returning: representation.map { NSImage(cgImage: $0.cgImage, size: .zero) })
            }
        }
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }
}
