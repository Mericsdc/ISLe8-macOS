import SwiftUI

// MARK: Ears

struct TimerEarIcon: View {
    @Environment(TimerModule.self) private var timer

    var body: some View {
        Image(systemName: TimerSymbols.symbol(for: timer.mode))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(TimerSymbols.tint(for: timer.mode))
    }
}

struct TimerEarTime: View {
    @Environment(TimerModule.self) private var timer

    var body: some View {
        // Ticks once a second while running, not at all while paused.
        TimelineView(.animation(minimumInterval: 1, paused: !timer.isRunning)) { context in
            Text(TimerText.format(timer.value(at: context.date), roundingUp: timer.mode != .stopwatch))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .opacity(timer.isRunning ? 1 : 0.5)
        }
    }
}

enum TimerSymbols {
    static func symbol(for mode: TimerModule.Mode) -> String {
        switch mode {
        case .pomodoro(let isBreak, _): isBreak ? "cup.and.saucer.fill" : "brain.head.profile"
        case .stopwatch: "stopwatch.fill"
        default: "timer"
        }
    }

    static func tint(for mode: TimerModule.Mode) -> Color {
        switch mode {
        case .pomodoro(let isBreak, _): isBreak ? .green : .orange
        default: .orange
        }
    }
}

// MARK: Tile

struct TimerTile: View {
    @Environment(TimerModule.self) private var timer
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            if settings.homeStyle == .minimal {
                minimal
            } else if timer.mode == .idle {
                presets
            } else {
                running
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.homeStyle == .minimal ? .leading : .topLeading)
        .islandTile()
    }

    /// The minimal strip: the time left while running, else two quick starts.
    private var minimal: some View {
        HStack(spacing: 6) {
            Image(systemName: TimerSymbols.symbol(for: timer.mode))
                .foregroundStyle(timer.mode == .idle ? AnyShapeStyle(Color.white.opacity(0.6)) : AnyShapeStyle(TimerSymbols.tint(for: timer.mode)))
            if timer.mode == .idle {
                PresetButton(title: "5 dk") { timer.startCountdown(minutes: 5) }
                PresetButton(title: "15 dk") { timer.startCountdown(minutes: 15) }
            } else {
                TimelineView(.animation(minimumInterval: 1, paused: !timer.isRunning)) { context in
                    Text(TimerText.format(timer.value(at: context.date), roundingUp: timer.mode != .stopwatch))
                        .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                PresetButton(systemImage: "stop.fill", label: "Zamanlayıcıyı durdur") { timer.reset() }
                    .frame(width: 30)
            }
        }
        .font(.system(size: 12, weight: .semibold))
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Zamanlayıcı")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                PresetButton(title: "5 dk") { timer.startCountdown(minutes: 5) }
                PresetButton(title: "15 dk") { timer.startCountdown(minutes: 15) }
            }
            HStack(spacing: 6) {
                PresetButton(systemImage: "brain.head.profile", label: "Pomodoro başlat") { timer.startPomodoro() }
                PresetButton(systemImage: "stopwatch.fill", label: "Kronometre başlat") { timer.startStopwatch() }
            }
        }
    }

    private var running: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !timer.isRunning)) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: TimerSymbols.symbol(for: timer.mode))
                        .foregroundStyle(TimerSymbols.tint(for: timer.mode))
                    Text(label)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))

                Text(TimerText.format(timer.value(at: context.date), roundingUp: timer.mode != .stopwatch))
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if timer.mode != .stopwatch {
                    ProgressView(value: timer.progress(at: context.date))
                        .progressViewStyle(.linear)
                        .tint(TimerSymbols.tint(for: timer.mode))
                        .controlSize(.mini)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if timer.isRunning {
                        PresetButton(systemImage: "pause.fill", label: "Duraklat") { timer.pause() }
                    } else {
                        PresetButton(systemImage: "play.fill", label: "Sürdür") { timer.resume() }
                    }
                    PresetButton(systemImage: "stop.fill", label: "Zamanlayıcıyı durdur") { timer.reset() }
                }
            }
        }
    }

    private var label: String {
        switch timer.mode {
        case .pomodoro(let isBreak, let round): isBreak ? "Mola · \(round). tur" : "Odaklan · \(round). tur"
        case .stopwatch: String(localized: "Kronometre")
        default: String(localized: "Zamanlayıcı")
        }
    }
}

private struct PresetButton: View {
    var title: LocalizedStringKey?
    var systemImage: String?
    /// What VoiceOver and the tooltip say for a button that shows only an icon.
    var label: LocalizedStringKey?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                if let title {
                    Text(title)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(isHovering ? 0.18 : 0.1)))
        }
        .buttonStyle(.plain)
        .help(label.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityLabel(label.map { Text($0) } ?? title.map { Text($0) } ?? Text(verbatim: ""))
        .onHover { isHovering = $0 }
    }
}

// MARK: Banner

struct TimerAlertView: View {
    let event: TimerEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.2)))
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
        case .finished: "timer"
        case .breakStarts: "cup.and.saucer.fill"
        case .workStarts: "brain.head.profile"
        }
    }

    private var tint: Color {
        switch event {
        case .breakStarts: .green
        default: .orange
        }
    }

    private var title: String {
        switch event {
        case .finished: String(localized: "Süre doldu")
        case .breakStarts: String(localized: "Mola zamanı")
        case .workStarts: String(localized: "Odaklanma zamanı")
        }
    }

    private var detail: String {
        switch event {
        case .finished: String(localized: "Zamanlayıcı bitti")
        case .breakStarts(let minutes): String(localized: "\(minutes) dakika dinlen")
        case .workStarts(let minutes): String(localized: "\(minutes) dakikalık yeni tur başladı")
        }
    }
}
