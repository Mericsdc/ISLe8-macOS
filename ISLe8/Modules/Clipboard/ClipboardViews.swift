import SwiftUI

struct ClipboardTab: View {
    @Environment(IslandModel.self) private var model
    @Environment(ClipboardService.self) private var clipboard
    @Environment(SettingsStore.self) private var settings
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var clipboard = clipboard

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                    TextField("Panoda ara", text: $clipboard.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(0.08)))

                if !clipboard.items.isEmpty {
                    IconButton(systemImage: "trash", help: "Geçmişi temizle (sabitlenenler kalır)") {
                        clipboard.clearHistory()
                    }
                }
            }

            if settings.recordClipboard && clipboard.access != .allowed {
                ClipboardPermissionNotice()
            }
            content
        }
        .onAppear { clipboard.refreshAccess() }
        .onChange(of: model.wantsSearchFocus, initial: true) { _, wants in
            if wants { isSearchFocused = true }
        }
        .onExitCommand { model.close() }
    }

    @ViewBuilder
    private var content: some View {
        if !clipboard.isStoreAvailable {
            notice("Pano geçmişi açılamadı", "Veritabanı oluşturulamadı.")
        } else if !settings.recordClipboard && clipboard.items.isEmpty {
            notice("Pano geçmişi kapalı", "Ayarlar > Pano bölümünden açabilirsin.")
        } else if clipboard.items.isEmpty {
            if clipboard.query.isEmpty {
                notice("Henüz bir şey kopyalanmadı", "Kopyaladıkların burada birikir. ⌃⌥V ile her yerden açılır.")
            } else {
                notice("Sonuç yok", "Başka bir kelime dene.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(clipboard.items) { item in
                        ClipboardRow(item: item)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func notice(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Explains why nothing new is being recorded and how to allow it.
private struct ClipboardPermissionNotice: View {
    @Environment(ClipboardService.self) private var clipboard

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(clipboard.access == .denied
                     ? String(localized: "Pano erişimi reddedilmiş.")
                     : String(localized: "Pano geçmişi için izin gerekiyor."))
                    .font(.system(size: 12, weight: .semibold))
                Text("Sistem Ayarları > Gizlilik ve Güvenlik > Yapıştır bölümünde ISLe8 için \"Her zaman izin ver\"i seç. ISLe8 listede yoksa önce \"İzin iste\"ye bas.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if clipboard.access != .denied {
                        PillButton(title: "İzin iste", systemImage: "checkmark.shield") {
                            clipboard.requestAccess()
                        }
                    }
                    PillButton(title: "Sistem Ayarları", systemImage: "gearshape") {
                        clipboard.openPrivacySettings()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }
}

private struct ClipboardRow: View {
    @Environment(IslandModel.self) private var model
    @Environment(ClipboardService.self) private var clipboard
    let item: ClipboardItem
    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                    }
                    Text(Self.relativeFormatter.localizedString(for: item.copiedAt, relativeTo: .now))
                    if let icon = sourceAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 11, height: 11)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))
            }

            Spacer(minLength: 4)

            if clipboard.lastCopiedID == item.id {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.green)
            } else if isHovering {
                HStack(spacing: 2) {
                    IconButton(systemImage: item.isPinned ? "pin.slash" : "pin", help: item.isPinned ? LocalizedStringKey("Sabitlemeyi kaldır") : LocalizedStringKey("Sabitle")) {
                        clipboard.togglePin(item)
                    }
                    IconButton(systemImage: "xmark", help: "Sil") {
                        clipboard.delete(item)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) {
                paste()
            } else {
                clipboard.copy(item)
            }
        }
        .help("Tıkla: kopyala · ⌥ tıkla: yapıştır")
        .contextMenu {
            Button("Kopyala") { clipboard.copy(item) }
            Button("Yapıştır") { paste() }
            Button(item.isPinned ? String(localized: "Sabitlemeyi kaldır") : String(localized: "Sabitle")) { clipboard.togglePin(item) }
            if item.kind == .url, let url = URL(string: item.preview.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Button("Tarayıcıda aç") { NSWorkspace.shared.open(url) }
            }
            if let email = item.emailAddress, let url = URL(string: "mailto:\(email)") {
                Button("E-posta yaz") { NSWorkspace.shared.open(url) }
            }
            if item.kind == .files {
                Button("Finder'da göster") {
                    ShelfActions.reveal(item.preview.split(separator: "\n").map { URL(fileURLWithPath: String($0)) })
                }
            }
            Divider()
            Button("Sil", role: .destructive) { clipboard.delete(item) }
        }
    }

    @ViewBuilder
    private var leading: some View {
        if item.kind == .image, let url = clipboard.imageURL(for: item) {
            FileThumbnail(url: url, size: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if let color = item.color {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: color))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2))
                )
                .padding(3)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
    }

    private var symbol: String {
        switch item.kind {
        case .text: item.emailAddress == nil ? "text.alignleft" : "envelope"
        case .richText: "doc.richtext"
        case .url: "link"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }

    private var sourceAppIcon: NSImage? {
        guard let id = item.sourceApp, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Copies, closes the island so the previous app has the keyboard again, then presses ⌘V.
    private func paste() {
        guard clipboard.prepareToPaste(item) else { return }
        model.close()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            ClipboardService.pressPaste()
        }
    }
}
