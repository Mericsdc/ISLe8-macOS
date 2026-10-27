import SwiftUI

/// The top row of the open island, beside the notch: status chips on the left, pin and
/// settings on the right. The tabs live in the dock at the bottom. Each side keeps to the
/// space beside the notch; when the chips don't fit, the least important ones go first.
struct HeaderBar: View {
    @Environment(IslandModel.self) private var model
    @Environment(SystemModule.self) private var system
    @Environment(SettingsStore.self) private var settings
    @Environment(UsageModule.self) private var usage

    var body: some View {
        let notch = model.geometry?.notchSize ?? CGSize(width: 180, height: 32)
        let side = max((model.size(for: .expanded).width - notch.width) / 2 - 18, 0)
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                chips(devices: true, watts: true, keepAwake: true)
                chips(devices: false, watts: true, keepAwake: true)
                chips(devices: false, watts: false, keepAwake: true)
                chips(devices: false, watts: false, keepAwake: false)
            }
            .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                IconButton(
                    systemImage: model.isPinned ? "pin.fill" : "pin",
                    help: model.isPinned ? LocalizedStringKey("Sabitlemeyi kaldır") : LocalizedStringKey("Açık tut")
                ) {
                    model.togglePin()
                }
                IconButton(systemImage: "gearshape.fill", help: "Ayarlar") {
                    model.openSettings()
                }
            }
            .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: notch.height)
    }

    /// Battery and camera/microphone always stay; the rest drops out in the order given above.
    private func chips(devices: Bool, watts: Bool, keepAwake: Bool) -> some View {
        HStack(spacing: 4) {
            if settings.showBatteryChip, let battery = system.battery {
                BatteryChip(state: battery)
            }
            if settings.showNetworkChip, system.network == .wired {
                HStack(spacing: 4) {
                    Image(systemName: "cable.connector.horizontal")
                        .foregroundStyle(Color.green)
                    Text(verbatim: "LAN")
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .help("İnternete kabloyla (Ethernet) bağlı")
            }
            if watts, settings.showBatteryChip, let watts = usage.adapterWatts {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Color.yellow)
                    Text(verbatim: "\(Int(watts.rounded())) W")
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .help("Adaptörden Mac'e giren güç")
            }
            if settings.showPrivacyChip && (system.isCameraInUse || system.isMicrophoneInUse) {
                PrivacyEar(camera: system.isCameraInUse, microphone: system.isMicrophoneInUse)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .help("Kamera ya da mikrofon kullanımda")
            }
            if devices, settings.showDevicesChip {
                DevicesChip()
            }
            if keepAwake, settings.showKeepAwakeChip {
                IconButton(
                    systemImage: system.isKeepingAwake ? "cup.and.saucer.fill" : "cup.and.saucer",
                    help: system.isKeepingAwake ? LocalizedStringKey("Uyanık tutmayı kapat") : LocalizedStringKey("Mac'i uyanık tut")
                ) {
                    system.setKeepAwake(!system.isKeepingAwake)
                }
            }
        }
        .fixedSize()
    }
}

/// The tabs, as icons in a small capsule at the bottom of the open island.
struct TabDock: View {
    @Environment(IslandModel.self) private var model
    @Environment(AgentsModule.self) private var agents
    @Environment(\.islandTheme) private var theme

    static let height: CGFloat = 36

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.visibleTabs, id: \.self) { tab in
                DockButton(tab: tab, isSelected: model.tab == tab) {
                    model.select(tab)
                }
                .overlay(alignment: .topTrailing) {
                    if tab == .agents && agents.needsAttention && model.tab != .agents {
                        Circle().fill(Color.orange).frame(width: 6, height: 6).offset(x: -6, y: 4)
                    }
                }
            }
        }
        .padding(3)
        .frame(height: Self.height)
        .background(Capsule().fill(theme.surface.color))
        .overlay {
            if !theme.border.isClear {
                Capsule().strokeBorder(theme.border.color, lineWidth: 1)
            }
        }
    }
}

private struct DockButton: View {
    let tab: IslandTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 48, height: TabDock.height - 6)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(isHovering ? 0.9 : 0.55)))
                .background(Capsule().fill(isSelected ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(Color.white.opacity(isHovering ? 0.08 : 0))))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

extension IslandTab {
    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .shelf: String(localized: "Raf")
        case .clipboard: String(localized: "Pano")
        case .notes: String(localized: "Notlar")
        case .agents: String(localized: "AI")
        case .devices: String(localized: "Cihazlar")
        case .system: String(localized: "Sistem")
        case .palette: String(localized: "Komut")
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .notes: "note.text"
        case .agents: "sparkles"
        case .devices: "macbook.and.iphone"
        case .system: "gauge.with.dots.needle.50percent"
        case .palette: "command"
        }
    }
}

struct IconButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 24)
                .background(Capsule().fill(Color.white.opacity(isHovering ? 0.14 : 0.07)))
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
        .onHover { isHovering = $0 }
    }
}
