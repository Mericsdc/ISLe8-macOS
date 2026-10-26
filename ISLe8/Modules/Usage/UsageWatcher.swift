import Darwin
import Foundation

// Ported from LimitBar LRX's ActivityMonitor.swift (see UsageModule.swift for the credit).

/// Kernel notifications (kqueue) on Codex's session logs and the folders above them, so a new
/// quota line is read within about two seconds with no repeated scan and no helper running.
/// All work happens on `queue`, never on the main thread, and all state is touched only there.
nonisolated final class UsageFileWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lrxe8.isle8.usage.watch", qos: .utility)
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    /// Watches the recent sessions under `codexRoot`, or nothing when it is nil.
    func watch(codexRoot: String?) {
        queue.async { [self] in
            update(codexRoot.map { UsageSessionFiles.watchPaths(root: $0) } ?? [])
        }
    }

    func stop() {
        queue.async { [self] in
            update([])
        }
    }

    private func update(_ paths: [String]) {
        let wanted = Set(paths)
        for path in Array(sources.keys) where !wanted.contains(path) {
            sources.removeValue(forKey: path)?.cancel()
        }
        for path in wanted where sources[path] == nil {
            let descriptor = open(path, O_EVTONLY | O_CLOEXEC)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete], queue: queue
            )
            source.setEventHandler { [weak self] in
                guard let self, let current = self.sources[path] else { return }
                // A replaced file needs a new descriptor; the next rebuild opens it.
                if !current.data.intersection([.rename, .delete]).isEmpty {
                    self.sources.removeValue(forKey: path)?.cancel()
                }
                self.onChange()
            }
            source.setCancelHandler { close(descriptor) }
            sources[path] = source
            source.resume()
        }
    }
}

/// Codex keeps its logs in ~/.codex/sessions/YYYY/MM/DD/*.jsonl.
nonisolated enum UsageSessionFiles {
    /// Today's and yesterday's folders. Session dates are UTC, including when the Mac has
    /// crossed local midnight.
    static func directories(root: String, now: Date = Date()) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return (0..<2).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: now) else { return nil }
            return String(format: "%@/%04d/%02d/%02d", root, calendar.component(.year, from: day),
                          calendar.component(.month, from: day), calendar.component(.day, from: day))
        }
    }

    static func recent(root: String, now: Date = Date(), limit: Int = 8) -> [String] {
        let manager = FileManager.default
        return directories(root: root, now: now).flatMap { directory -> [(String, Date)] in
            ((try? manager.contentsOfDirectory(atPath: directory)) ?? []).compactMap { file in
                guard file.hasSuffix(".jsonl"), let date = UsageFetch.mtime("\(directory)/\(file)") else { return nil }
                return ("\(directory)/\(file)", date)
            }
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map { $0.0 }
    }

    /// The recent logs, their folders and the folders above, so a new day, month or year
    /// folder is noticed too.
    static func watchPaths(root: String) -> [String] {
        let days = directories(root: root)
        let ancestors = days.flatMap { day -> [String] in
            let month = (day as NSString).deletingLastPathComponent
            return [day, month, (month as NSString).deletingLastPathComponent]
        }
        return [root] + ancestors + recent(root: root)
    }
}
