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
                HStack(spacing: 6) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: proxy.size.width * shownLevel)
                        }
                    }
                    .frame(height: 5)
                    .animation(.easeOut(duration: 0.12), value: shownLevel)
                    Text(shownLevel, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .frame(width: IslandModel.hudEarWidth)
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
        case .unplugged: "battery.75percent"
        case .low: "battery.25percent"
        case .critical: "battery.0percent"
        }
    }

    private var tint: Color {
        switch event {
        case .pluggedIn: .green
        case .unplugged: .white
        case .low: .orange
        case .critical: .red
        }
    }

    private var title: String {
        switch event {
        case .pluggedIn: String(localized: "Şarj oluyor")
        case .unplugged: String(localized: "Pilde")
        case .low: String(localized: "Pil azalıyor")
        case .critical: String(localized: "Pil çok az")
        }
    }

    private var detail: String {
        switch event {
        case .pluggedIn(let percent), .unplugged(let percent): "%\(percent)"
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

/// Charging, or online by cable: the island widens beside the notch with a green symbol on
/// the left and the figure on the right, the way an iPhone shows it is charging.
struct StatusEarsView: View {
    @Environment(IslandModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let symbol: String
    let text: String
    let label: String
    /// Green when something was plugged in, white when it was taken out.
    var tint: Color = .green
    @State private var isOut = false

    var body: some View {
        if let notch = model.geometry?.notchSize {
            // Both sides slide out from under the notch with a little bounce, then the
            // symbol pulses once.
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: isOut)
                    .frame(width: IslandModel.statusEarWidth)
                    .offset(x: isOut ? 0 : IslandModel.statusEarWidth * 0.6)
                    .scaleEffect(isOut ? 1 : 0.4)
                    .opacity(isOut ? 1 : 0)
                Spacer(minLength: notch.width)
                Text(verbatim: text)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(tint)
                    .frame(width: IslandModel.statusEarWidth)
                    .offset(x: isOut ? 0 : -IslandModel.statusEarWidth * 0.6)
                    .scaleEffect(isOut ? 1 : 0.4)
                    .opacity(isOut ? 1 : 0)
            }
            .frame(height: notch.height)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.6).delay(0.05)) {
                    isOut = true
                }
            }
            .onChange(of: model.isRetractingStatus) { _, retracting in
                guard retracting else { return }
                withAnimation(reduceMotion ? .easeIn(duration: 0.12) : .easeIn(duration: 0.22)) {
                    isOut = false
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(label) \(text)"))
        }
    }
}
