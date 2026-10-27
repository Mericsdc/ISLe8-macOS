import SwiftUI

/// The Notes tab: a line to write in, and the notes as cards. Clicking a card copies it.
struct NotesTab: View {
    @Environment(NotesModule.self) private var notes
    @Environment(IslandModel.self) private var model
    @State private var draft = ""
    @State private var editing: UUID?
    @State private var copied: UUID?
    @FocusState private var isWriting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            editor
            if notes.notes.isEmpty {
                Text("Henüz not yok. Yukarıya yaz, Enter'la ekle; bir nota tıklayınca kopyalanır.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                        ForEach(notes.notes) { note in
                            NoteCard(
                                note: note,
                                isCopied: copied == note.id,
                                isEditing: editing == note.id,
                                copy: { copy(note) },
                                edit: { startEditing(note) },
                                delete: { notes.delete(note.id) }
                            )
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var editor: some View {
        HStack(spacing: 6) {
            Image(systemName: editing == nil ? "square.and.pencil" : "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tint)
            TextField(editing == nil ? "Not yaz, Enter'la ekle" : "Notu düzenle", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isWriting)
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
                // The island only takes the keyboard when asked, so typing works without
                // bringing ISLe8 to the front.
                .simultaneousGesture(TapGesture().onEnded { beginTyping() })
            if editing != nil || !draft.isEmpty {
                IconButton(systemImage: "xmark", help: "Vazgeç", action: cancel)
            }
            IconButton(systemImage: editing == nil ? "plus" : "checkmark", help: editing == nil ? "Ekle" : "Kaydet", action: commit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func beginTyping() {
        model.requestKeyboard()
        isWriting = true
    }

    private func commit() {
        if let editing {
            notes.update(editing, text: draft)
        } else {
            notes.add(draft)
        }
        draft = ""
        editing = nil
    }

    private func cancel() {
        draft = ""
        editing = nil
        isWriting = false
    }

    private func startEditing(_ note: Note) {
        editing = note.id
        draft = note.text
        beginTyping()
    }

    private func copy(_ note: Note) {
        notes.copy(note)
        copied = note.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copied == note.id { copied = nil }
        }
    }
}

private struct NoteCard: View {
    let note: Note
    let isCopied: Bool
    let isEditing: Bool
    let copy: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.text)
                .font(.system(size: 12))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if isCopied {
                Label("Kopyalandı", systemImage: "checkmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tint)
            } else {
                Text(note.updated, format: .relative(presentation: .named))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .islandTile(radius: 10)
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.tint, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: copy)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                HStack(spacing: 4) {
                    IconButton(systemImage: "pencil", help: "Düzenle", action: edit)
                    IconButton(systemImage: "trash", help: "Sil", action: delete)
                }
                .padding(6)
            }
        }
        .onHover { isHovering = $0 }
        .help("Kopyalamak için tıkla")
        .contextMenu {
            Button("Kopyala", action: copy)
            Button("Düzenle", action: edit)
            Button("Sil", role: .destructive, action: delete)
        }
    }
}
