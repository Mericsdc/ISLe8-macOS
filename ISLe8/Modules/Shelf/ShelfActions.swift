import AppKit
import ImageIO
import UniformTypeIdentifiers

/// What you can do with files on the shelf.
enum ShelfActions {
    /// Opens the system AirDrop picker for the files.
    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls)
        else {
            NSSound.beep()
            return
        }
        // The picker belongs to ISLe8, so it has to be in front to be seen.
        NSApp.activate()
        service.perform(withItems: urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Zips a file or folder next to it (or into `fallbackFolder` if that isn't writable).
    static func zip(_ url: URL, fallbackFolder: URL) async -> URL? {
        let folder = writableFolder(next: url, fallback: fallbackFolder)
        let destination = uniqueURL(in: folder, name: url.lastPathComponent, extension: "zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, destination.path]
        let succeeded = await run(process)
        return succeeded ? destination : nil
    }

    /// Writes the image in another format next to the original.
    static func convert(_ url: URL, to type: UTType, fallbackFolder: URL) async -> URL? {
        let folder = writableFolder(next: url, fallback: fallbackFolder)
        let destination = uniqueURL(
            in: folder,
            name: url.deletingPathExtension().lastPathComponent,
            extension: type.preferredFilenameExtension ?? "img"
        )
        let identifier = type.identifier
        return await Task.detached(priority: .userInitiated) {
            convertImage(at: url, to: destination, typeIdentifier: identifier) ? destination : nil
        }.value
    }

    nonisolated private static func convertImage(at source: URL, to destination: URL, typeIdentifier: String) -> Bool {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(input, 0, nil),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, typeIdentifier as CFString, 1, nil)
        else { return false }
        // Carry the metadata over so orientation and color profile survive.
        CGImageDestinationAddImage(output, image, CGImageSourceCopyPropertiesAtIndex(input, 0, nil))
        return CGImageDestinationFinalize(output)
    }

    private static func run(_ process: Process) async -> Bool {
        await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
    }

    private static func writableFolder(next url: URL, fallback: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: folder.path) {
            return folder
        }
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// "name.ext", or "name 2.ext", "name 3.ext"… if that is taken.
    nonisolated static func uniqueURL(in folder: URL, name: String, extension ext: String) -> URL {
        var candidate = folder.appending(path: "\(name).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(name) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
