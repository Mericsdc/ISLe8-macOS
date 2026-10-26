import Foundation
import UniformTypeIdentifiers

nonisolated struct ShelfItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var url: URL
    var addedAt: Date
    /// The file is a copy in ISLe8's own folder and is deleted together with the item.
    var isCopy: Bool

    var name: String { url.lastPathComponent }

    var isImage: Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }
}

/// The files on the shelf. Items point at their files through bookmarks, so they survive
/// renames, moves and relaunches.
///
/// Anything that touches the files themselves runs off the main thread: shelf files often
/// sit in Desktop or Downloads, where the first access can wait on a macOS permission
/// prompt, and copies of large files take time.
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []

    @ObservationIgnored private let indexURL: URL
    /// Where copies (and zips or conversions of read-only files) are kept.
    @ObservationIgnored let filesFolder: URL

    init(folder: URL) {
        indexURL = folder.appending(path: "shelf.json")
        filesFolder = folder.appending(path: "Shelf", directoryHint: .isDirectory)
        load()
    }

    /// Adds files to the front of the shelf. A file already on it just moves to the front.
    func add(_ urls: [URL], copy: Bool) {
        guard copy else {
            insert(urls.map { ShelfItem(id: UUID(), url: $0.standardizedFileURL, addedAt: .now, isCopy: false) })
            return
        }
        let folder = filesFolder
        Task {
            let copies = await Task.detached(priority: .userInitiated) {
                urls.compactMap { Self.makeCopy(of: $0, in: folder) }
            }.value
            insert(copies.map { ShelfItem(id: UUID(), url: $0, addedAt: .now, isCopy: true) })
        }
    }

    func remove(_ item: ShelfItem) {
        deleteCopies(of: [item])
        items.removeAll { $0.id == item.id }
        save()
    }

    func removeAll() {
        deleteCopies(of: items)
        items.removeAll()
        save()
    }

    private func insert(_ newItems: [ShelfItem]) {
        for item in newItems {
            if let index = items.firstIndex(where: { $0.url == item.url }) {
                items.insert(items.remove(at: index), at: 0)
            } else {
                items.insert(item, at: 0)
            }
        }
        save()
    }

    // MARK: Files

    nonisolated private static func makeCopy(of url: URL, in filesFolder: URL) -> URL? {
        let folder = filesFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let destination = folder.appending(path: url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            NSLog("ISLe8: could not copy \(url.path) to the shelf: \(error)")
            return nil
        }
    }

    private func deleteCopies(of items: [ShelfItem]) {
        let folders = items.filter(\.isCopy).map { $0.url.deletingLastPathComponent() }
        guard !folders.isEmpty else { return }
        Task.detached(priority: .utility) {
            folders.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    // MARK: Persistence

    nonisolated private struct Entry: Codable, Sendable {
        let id: UUID
        let bookmark: Data
        let addedAt: Date
        let isCopy: Bool
    }

    private func save() {
        let items = items
        let indexURL = indexURL
        Task.detached(priority: .utility) {
            let entries = items.compactMap { item -> Entry? in
                guard let bookmark = try? item.url.bookmarkData() else { return nil }
                return Entry(id: item.id, bookmark: bookmark, addedAt: item.addedAt, isCopy: item.isCopy)
            }
            do {
                try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
            } catch {
                NSLog("ISLe8: could not save the shelf: \(error)")
            }
        }
    }

    private func load() {
        let indexURL = indexURL
        Task {
            let loaded = await Task.detached(priority: .utility) { Self.resolve(indexURL) }.value
            // Anything added while loading stays in front.
            items += loaded.filter { item in !items.contains { $0.id == item.id } }
        }
    }

    nonisolated private static func resolve(_ indexURL: URL) -> [ShelfItem] {
        guard let data = try? Data(contentsOf: indexURL),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.compactMap { entry in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: entry.bookmark,
                options: [.withoutUI, .withoutMounting],
                bookmarkDataIsStale: &isStale
            ), FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ShelfItem(id: entry.id, url: url, addedAt: entry.addedAt, isCopy: entry.isCopy)
        }
    }
}
