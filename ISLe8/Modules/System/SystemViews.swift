import SwiftUI

/// Volume or brightness in the ears: the icon on the left, a level bar on the right.
struct HUDAlertView: View {
    @Environment(IslandModel.self) private var model
    let value: HUDValue

    var body: some View {
        if let notch = model.geometry?.notchSize {
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: IslandModel.hudEarWidth)
                Spacer(minLength: notch.width)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * shownLevel)
                    }
                }
                .frame(width: IslandModel.hudEarWidth - 22, height: 5)
                .frame(width: IslandModel.hudEarWidth)
                .animation(.easeOut(duration: 0.12), value: shownLevel)
            }
            .frame(height: notch.height)
        }
    }

    private var shownLevel: Double {
        value.isMuted ? 0 : min(max(value.level, 0), 1)
    }

    private var symbol: String {
        switch value.kind {
        case .brightness:
            return value.level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if value.isMuted || value.level == 0 { return "speaker.slash.fill" }
            if value.level < 0.34 { return "speaker.wave.1.fill" }
            if value.level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

struct BatteryAlertView: View {
    let event: BatteryEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(tint, Color.white.opacity(0.85))
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }

    private var symbol: String {
        switch event {
        case .pluggedIn: "battery.100percent.bolt"
        case .full: "battery.100percent"
        case .low: "battery.25percent"
        case .critical: "battery.0percent"
        }
    }

    private var tint: Color {
        switch event {
        case .pluggedIn, .full: .green
        case .low: .orange
        case .critical: .red
        }
    }

    private var title: String {
        switch event {
        case .pluggedIn: String(localized: "Şarj oluyor")
        case .full: String(localized: "Tam şarj oldu")
        case .low: String(localized: "Pil azalıyor")
        case .critical: String(localized: "Pil çok az")
        }
    }

    private var detail: String {
        switch event {
        case .pluggedIn(let percent): "%\(percent)"
        case .full: String(localized: "Şarj aletini çıkarabilirsin")
        case .low(let percent), .critical(let percent): String(localized: "%\(percent) kaldı · şarja tak")
        }
    }
}

/// Green camera and orange microphone, as macOS colors its own indicators.
struct PrivacyEar: View {
    let camera: Bool
    let microphone: Bool

    var body: some View {
        HStack(spacing: 3) {
            if camera {
                Image(systemName: "video.fill")
                    .foregroundStyle(Color.green)
            }
            if microphone {
                Image(systemName: "mic.fill")
                    .foregroundStyle(Color.orange)
            }
        }
        .font(.system(size: 10, weight: .semibold))
    }
}

// MARK: Header chips

struct BatteryChip: View {
    let state: BatteryState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(tint, Color.white.opacity(0.8))
            Text("%\(state.percent)")
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .help(state.isCharging ? String(localized: "Şarj oluyor") : state.isPluggedIn ? String(localized: "Prize takılı") : String(localized: "Pilde"))
    }

    private var symbol: String {
        if state.isCharging { return "battery.100percent.bolt" }
        switch state.percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var tint: Color {
        if state.isCharging || state.isPluggedIn { return .green }
        if state.percent <= 10 { return .red }
        if state.percent <= 20 { return .orange }
        return .white
    }
}
