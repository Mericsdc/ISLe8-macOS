import SwiftUI
import UniformTypeIdentifiers

// MARK: Drop target

/// What the island shows while files are dragged towards it.
struct DropTargetView: View {
    @Environment(IslandModel.self) private var model
    @Environment(ShelfModule.self) private var shelf
    @State private var isShelfTargeted = false
    @State private var isAirDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: model.geometry?.notchSize.height ?? 0)
            HStack(spacing: 10) {
                DropZone(title: "Rafa bırak", systemImage: "tray.and.arrow.down.fill", tint: .white, isTargeted: isShelfTargeted)
                    .dropDestination(for: URL.self) { urls, _ in
                        shelf.add(urls)
                        model.showShelfAfterDrop()
                        return true
                    } isTargeted: { isShelfTargeted = $0 }
                DropZone(title: "AirDrop", systemImage: "dot.radiowaves.up.forward", tint: .blue, isTargeted: isAirDropTargeted)
                    .dropDestination(for: URL.self) { urls, _ in
                        model.close()
                        ShelfActions.airDrop(urls)
                        return true
                    } isTargeted: { isAirDropTargeted = $0 }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
    }
}

private struct DropZone: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(isTargeted ? tint : Color.white.opacity(0.75))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(isTargeted ? 0.18 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    tint.opacity(isTargeted ? 0.9 : 0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [5, 4])
                )
        )
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isTargeted)
    }
}

// MARK: Shelf tab

struct ShelfTab: View {
    @Environment(ShelfModule.self) private var shelf

    var body: some View {
        let items = shelf.store.items
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Raf")
                    .font(.system(size: 13, weight: .semibold))
                if !items.isEmpty {
                    Text("\(items.count) öğe")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                Spacer()
                if !items.isEmpty {
                    PillButton(title: "AirDrop", systemImage: "dot.radiowaves.up.forward") {
                        ShelfActions.airDrop(items.map(\.url))
                    }
                    PillButton(title: "Temizle", systemImage: "trash") {
                        shelf.store.removeAll()
                    }
                }
            }

            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text("Dosyaları notch'a sürükle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Burada bekler; istediğin yere sürükleyip bırakabilir ya da AirDrop'la gönderebilirsin.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items) { item in
                            ShelfTile(item: item)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Files can also be dropped straight onto the open shelf.
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            return true
        }
    }
}

private struct ShelfTile: View {
    @Environment(ShelfModule.self) private var shelf
    let item: ShelfItem
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            FileThumbnail(url: item.url, size: 48)
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 26, alignment: .top)
        }
        .frame(width: 74)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.10 : 0.04))
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    shelf.store.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Raftan kaldır")
                .accessibilityLabel("Raftan kaldır")
                .offset(x: 4, y: -4)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { ShelfActions.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(item.url.path)
        .contextMenu {
            Button("Aç") { ShelfActions.open(item.url) }
            Button("Finder'da göster") { ShelfActions.reveal([item.url]) }
            Divider()
            Button("AirDrop ile gönder") { ShelfActions.airDrop([item.url]) }
            ShareLink(item: item.url) {
                Text("Paylaş…")
            }
            Button("Zip olarak sıkıştır") { shelf.zip(item) }
            if item.isImage {
                Menu("Dönüştür") {
                    Button("PNG") { shelf.convert(item, to: .png) }
                    Button("JPEG") { shelf.convert(item, to: .jpeg) }
                    Button("HEIC") { shelf.convert(item, to: .heic) }
                }
            }
            Divider()
            Button("Raftan kaldır", role: .destructive) { shelf.store.remove(item) }
        }
    }
}

// MARK: Banner

struct AirDropAlertView: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text("AirDrop")
                    .font(.system(size: 12, weight: .semibold))
                Text(count == 1 ? String(localized: "1 dosya alındı, rafta") : String(localized: "\(count) dosya alındı, rafta"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Shared

/// A small capsule button for actions inside a tab.
struct PillButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(isHovering ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
