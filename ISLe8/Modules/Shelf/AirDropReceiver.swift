import Foundation

/// Notices files arriving by AirDrop. macOS has no API for that, but AirDrop puts received
/// files in Downloads and marks them as coming from `sharingd`. The folder is watched with
/// a kernel event, so nothing runs until something lands in it.
final class AirDropReceiver {
    var onReceive: (([URL]) -> Void)?
    private let watcher = DownloadsWatcher()

    func start() {
        watcher.start { urls in
            Task { @MainActor in self.onReceive?(urls) }
        }
    }

    func stop() {
        watcher.stop()
    }
}

/// Does the actual watching on its own queue. Downloads is a protected folder: the first
/// access waits until the user answers macOS's permission prompt, which must never block
/// the island. All state is touched only on `queue`.
nonisolated private final class DownloadsWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lrxe8.isle8.airdrop", qos: .utility)
    private let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    private var source: DispatchSourceFileSystemObject?
    private var knownNames: Set<String> = []
    private var pendingScan: DispatchWorkItem?

    func start(onReceive: @escaping @Sendable ([URL]) -> Void) {
        queue.async { [self] in
            guard source == nil else { return }
            let descriptor = open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else {
                NSLog("ISLe8: cannot watch Downloads for AirDrop")
                return
            }
            knownNames = currentNames()
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
            source.setEventHandler { [weak self] in
                self?.scheduleScan(onReceive)
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            self.source = source
        }
    }

    func stop() {
        queue.async { [self] in
            pendingScan?.cancel()
            source?.cancel()
            source = nil
        }
    }

    /// AirDrop writes in several steps; look once things have settled.
    private func scheduleScan(_ onReceive: @escaping @Sendable ([URL]) -> Void) {
        pendingScan?.cancel()
        let scan = DispatchWorkItem { [weak self] in
            self?.scan(onReceive)
        }
        pendingScan = scan
        queue.asyncAfter(deadline: .now() + 1.5, execute: scan)
    }

    private func scan(_ onReceive: @Sendable ([URL]) -> Void) {
        let names = currentNames()
        let added = names.subtracting(knownNames)
        knownNames = names
        let received = added
            .map { folder.appending(path: $0) }
            .filter(Self.cameFromAirDrop)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if !received.isEmpty {
            onReceive(received)
        }
    }

    private func currentNames() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    /// The quarantine attribute reads "flags;time;agent;id"; AirDrop's agent is sharingd.
    private static func cameFromAirDrop(_ url: URL) -> Bool {
        let name = "com.apple.quarantine"
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(url.path, name, &buffer, size, 0, 0)
        guard read > 0 else { return false }
        let fields = String(decoding: buffer.prefix(read), as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false)
        return fields.count > 2 && fields[2] == "sharingd"
    }
}
