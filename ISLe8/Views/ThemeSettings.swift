import SwiftUI
import UniformTypeIdentifiers

/// Settings > Appearance: pick a theme from the gallery, then fine-tune it below. Changes are
/// made to the theme itself, built-in ones included; a changed built-in theme can be put back
/// as it came.
struct ThemeSettings: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Section {
            ThemeGallery()
        } header: {
            Text("Tema")
        }

        Section {
            ThemeEditor()
        } header: {
            Text("Özelleştir")
        } footer: {
            Text(settings.theme.isPreset
                 ? String(localized: "Değişiklikler bu temaya kaydedilir; \"Varsayılana döndür\" ilk haline getirir.")
                 : String(localized: "Ada kapalıyken her temada siyah kalır, notch'la kaynaşsın diye."))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ThemeGallery: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
            ForEach(settings.allThemes) { theme in
                Button {
                    settings.themeID = theme.id
                } label: {
                    VStack(spacing: 6) {
                        ThemePreview(theme: theme, isSelected: theme.id == settings.themeID)
                        Text(theme.name)
                            .font(.system(size: 11, weight: theme.id == settings.themeID ? .semibold : .regular))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.name)
                .accessibilityAddTraits(theme.id == settings.themeID ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// A miniature of the open island in this theme: notch row, two cards, the accent.
struct ThemePreview: View {
    let theme: IslandTheme
    var isSelected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(fill)
            VStack(spacing: 5) {
                Capsule().fill(Color.black).frame(width: 34, height: 7)
                HStack(spacing: 5) {
                    card.overlay(alignment: .bottomLeading) {
                        Capsule().fill(theme.accent.color).frame(width: 26, height: 3).padding(6)
                    }
                    card.frame(width: 30)
                }
                .frame(height: 38)
                card.frame(height: 12)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 84)
        .clipShape(shape)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? theme.accent.color : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        }
        .fontDesign(theme.typeface.design)
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: max(theme.cornerRadius * 0.35, 2), style: .continuous)
        return shape.fill(theme.surface.color)
            .overlay { if !theme.border.isClear { shape.strokeBorder(theme.border.color, lineWidth: 0.5) } }
    }

    private var fill: AnyShapeStyle {
        switch theme.material {
        case .black: AnyShapeStyle(Color.black)
        case .solid: AnyShapeStyle(theme.background.color)
        case .gradient: AnyShapeStyle(LinearGradient(colors: [theme.background.color, theme.backgroundBottom.color], startPoint: .top, endPoint: .bottom))
        case .glass: AnyShapeStyle(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .artwork: AnyShapeStyle(LinearGradient(colors: [.black, Color.orange.opacity(0.55)], startPoint: .top, endPoint: .bottom))
        }
    }
}

private struct ThemeEditor: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let theme = settings.theme
        if !theme.isPreset {
            TextField("Ad", text: binding(\.name))
        }
        Picker("Malzeme", selection: binding(\.material)) {
            Text("Siyah").tag(IslandTheme.Material.black)
            Text("Düz renk").tag(IslandTheme.Material.solid)
            Text("Degrade").tag(IslandTheme.Material.gradient)
            Text("Cam").tag(IslandTheme.Material.glass)
            Text("Kapak rengi").tag(IslandTheme.Material.artwork)
        }
        if theme.material == .solid || theme.material == .gradient {
            ColorPicker(theme.material == .gradient ? "Üst renk" : "Arka plan", selection: colorBinding(\.background), supportsOpacity: false)
        }
        if theme.material == .gradient {
            ColorPicker("Alt renk", selection: colorBinding(\.backgroundBottom), supportsOpacity: false)
        }
        ColorPicker("Kartlar", selection: colorBinding(\.surface))
        ColorPicker("Kart kenarlığı", selection: colorBinding(\.border))
        ColorPicker("Vurgu rengi", selection: colorBinding(\.accent), supportsOpacity: false)
        LabeledContent("Köşe yuvarlaklığı") {
            HStack {
                Slider(value: binding(\.cornerRadius), in: 0...26, step: 1)
                    .frame(width: 180)
                Text("\(Int(theme.cornerRadius)) pt")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
        Picker("Yazı tipi", selection: binding(\.typeface)) {
            Text("Sistem").tag(IslandTheme.Typeface.system)
            Text("Yuvarlak").tag(IslandTheme.Typeface.rounded)
            Text("Mono").tag(IslandTheme.Typeface.monospaced)
            Text("Serif").tag(IslandTheme.Typeface.serif)
        }
        LabeledContent("Tema dosyası") {
            HStack {
                Button("Dışa aktar…", action: exportTheme)
                Button("İçe aktar…", action: importTheme)
                if !theme.isPreset {
                    Button("Sil", role: .destructive, action: deleteTheme)
                } else if settings.customThemes.contains(where: { $0.id == theme.id }) {
                    Button("Varsayılana döndür", action: resetTheme)
                }
            }
        }
    }

    // MARK: Editing

    private func binding<Value>(_ keyPath: WritableKeyPath<IslandTheme, Value>) -> Binding<Value> {
        Binding(
            get: { settings.theme[keyPath: keyPath] },
            set: { value in edit { $0[keyPath: keyPath] = value } }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<IslandTheme, ThemeColor>) -> Binding<Color> {
        Binding(
            get: { settings.theme[keyPath: keyPath].color },
            set: { color in edit { $0[keyPath: keyPath] = ThemeColor(color) } }
        )
    }

    /// Changes the selected theme in place. The first change to a preset stores it, under its
    /// own ID, among the user's themes.
    private func edit(_ change: (inout IslandTheme) -> Void) {
        let theme = settings.theme
        if let index = settings.customThemes.firstIndex(where: { $0.id == theme.id }) {
            change(&settings.customThemes[index])
        } else {
            var changed = theme
            change(&changed)
            settings.customThemes.append(changed)
        }
    }

    /// A changed preset as it came.
    private func resetTheme() {
        let id = settings.themeID
        settings.customThemes.removeAll { $0.id == id }
    }

    private func deleteTheme() {
        let id = settings.themeID
        settings.themeID = IslandTheme.notchBlack.id
        settings.customThemes.removeAll { $0.id == id }
    }

    // MARK: Files

    private func exportTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(settings.theme.name).isle8theme.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(settings.theme).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var theme = try JSONDecoder().decode(IslandTheme.self, from: Data(contentsOf: url))
            // An imported theme never replaces a preset or one already here.
            if settings.allThemes.contains(where: { $0.id == theme.id }) {
                theme.id = UUID().uuidString
            }
            settings.customThemes.append(theme)
            settings.themeID = theme.id
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
