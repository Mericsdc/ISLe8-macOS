import AppKit

nonisolated struct Note: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var updated: Date
}

/// Quick notes on the island: type one in, click it to copy it. Kept in notes.json in
/// ISLe8's support folder, readable only by the user. Nothing runs between edits.
@Observable
final class NotesModule: IslandModule {
    let id = "notes"
    var activity: LiveActivity? { nil }
    @ObservationIgnored var onActivityChange: (() -> Void)?

    /// Newest first.
    private(set) var notes: [Note] = []
    @ObservationIgnored private let fileURL: URL

    init(folder: URL) {
        fileURL = folder.appending(path: "notes.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = saved
        }
    }

    func start() {}
    func stop() {}

    func add(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        notes.insert(Note(id: UUID(), text: text, updated: .now), at: 0)
        save()
    }

    /// Emptying a note deletes it.
    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            notes.remove(at: index)
        } else {
            notes[index].text = text
            notes[index].updated = .now
        }
        save()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func copy(_ note: Note) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.text, forType: .string)
    }

    /// A few kilobytes at most, so it is written straight away.
    private func save() {
        do {
            try JSONEncoder().encode(notes).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("ISLe8: could not save the notes: \(error)")
        }
    }
}
