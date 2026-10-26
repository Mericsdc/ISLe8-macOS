import SwiftUI

struct PaletteTab: View {
    @Environment(IslandModel.self) private var model
    @Environment(PaletteModule.self) private var palette
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var palette = palette

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                TextField("Komut, uygulama ya da kopyaladığın bir şey yaz", text: $palette.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isFocused)
                    .onSubmit { palette.runSelected() }
                    .onKeyPress(.upArrow) {
                        palette.move(-1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        palette.move(1)
                        return .handled
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))

            if palette.results.isEmpty {
                Text("Sonuç yok")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(palette.results.enumerated()), id: \.element.id) { index, command in
                                PaletteRow(command: command, isSelected: index == palette.selection)
                                    .id(command.id)
                                    .onTapGesture {
                                        palette.selection = index
                                        palette.runSelected()
                                    }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .onChange(of: palette.selection) { _, selection in
                        if palette.results.indices.contains(selection) {
                            proxy.scrollTo(palette.results[selection].id)
                        }
                    }
                }
            }
        }
        .onAppear {
            palette.prepare()
            isFocused = true
        }
        .onExitCommand { model.close() }
    }
}

private struct PaletteRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch command.icon {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 13, weight: .semibold))
                case .image(let image):
                    Image(nsImage: image)
                        .resizable()
                }
            }
            .frame(width: 22, height: 22)
            Text(command.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            if !command.subtitle.isEmpty {
                Text(command.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.14 : 0))
        )
        .contentShape(Rectangle())
    }
}
