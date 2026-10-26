import AppKit
import SwiftUI

enum TimerEvent: Equatable {
    case finished
    case breakStarts(minutes: Int)
    case workStarts(minutes: Int)
}

/// A countdown, a Pomodoro cycle or a stopwatch. Times are worked out from dates, so nothing
/// drifts; the only thing that waits is one sleep until the countdown ends. The ears tick
/// once a second while it runs, and only then.
@Observable
final class TimerModule: IslandModule {
    enum Mode: Equatable {
        case idle
        case countdown
        case pomodoro(isBreak: Bool, round: Int)
        case stopwatch
    }

    let id = "timer"
    private(set) var mode: Mode = .idle
    /// Total length of the current countdown or Pomodoro phase.
    private(set) var duration: TimeInterval = 0
    /// While running: when a countdown ends, or when a stopwatch (re)started.
    private(set) var anchor: Date?
    /// While paused: time left (countdown) or time elapsed (stopwatch).
    private(set) var pausedValue: TimeInterval?

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored var onEvent: ((TimerEvent) -> Void)?
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var endTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isRunning: Bool { mode != .idle && pausedValue == nil }

    var activity: LiveActivity? {
        guard mode != .idle else { return nil }
        return LiveActivity(
            id: id,
            priority: ActivityPriority.timer,
            leading: AnyView(TimerEarIcon()),
            trailing: AnyView(TimerEarTime())
        )
    }

    func start() {}

    func stop() {
        endTask?.cancel()
    }

    // MARK: Controls

    func startCountdown(minutes: Int) {
        begin(.countdown, length: TimeInterval(minutes * 60))
    }

    func startPomodoro() {
        begin(.pomodoro(isBreak: false, round: 1), length: TimeInterval(settings.pomodoroWorkMinutes * 60))
    }

    func startStopwatch() {
        endTask?.cancel()
        mode = .stopwatch
        duration = 0
        anchor = Date()
        pausedValue = nil
        onActivityChange?()
    }

    func pause() {
        guard isRunning, let anchor else { return }
        endTask?.cancel()
        pausedValue = mode == .stopwatch ? Date().timeIntervalSince(anchor) : max(anchor.timeIntervalSinceNow, 0)
    }

    func resume() {
        guard let pausedValue else { return }
        self.pausedValue = nil
        if mode == .stopwatch {
            anchor = Date().addingTimeInterval(-pausedValue)
        } else {
            anchor = Date().addingTimeInterval(pausedValue)
            scheduleEnd()
        }
    }

    func reset() {
        endTask?.cancel()
        mode = .idle
        anchor = nil
        pausedValue = nil
        duration = 0
        onActivityChange?()
    }

    /// Seconds left for a countdown, seconds elapsed for a stopwatch.
    func value(at date: Date) -> TimeInterval {
        if let pausedValue { return pausedValue }
        guard let anchor else { return 0 }
        return mode == .stopwatch ? date.timeIntervalSince(anchor) : max(anchor.timeIntervalSince(date), 0)
    }

    /// 0…1 of the countdown done; 0 for a stopwatch.
    func progress(at date: Date) -> Double {
        guard mode != .stopwatch, duration > 0 else { return 0 }
        return 1 - value(at: date) / duration
    }

    // MARK: Private

    private func begin(_ newMode: Mode, length: TimeInterval) {
        mode = newMode
        duration = length
        anchor = Date().addingTimeInterval(length)
        pausedValue = nil
        scheduleEnd()
        onActivityChange?()
    }

    private func scheduleEnd() {
        endTask?.cancel()
        guard let anchor else { return }
        endTask = Task {
            try? await Task.sleep(for: .seconds(max(anchor.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self.finishPhase()
        }
    }

    private func finishPhase() {
        if settings.timerSound {
            NSSound(named: "Glass")?.play()
        }
        switch mode {
        case .pomodoro(let isBreak, let round):
            if isBreak {
                let minutes = settings.pomodoroWorkMinutes
                onEvent?(.workStarts(minutes: minutes))
                begin(.pomodoro(isBreak: false, round: round + 1), length: TimeInterval(minutes * 60))
            } else {
                let minutes = settings.pomodoroBreakMinutes
                onEvent?(.breakStarts(minutes: minutes))
                begin(.pomodoro(isBreak: true, round: round), length: TimeInterval(minutes * 60))
            }
        default:
            onEvent?(.finished)
            reset()
        }
    }
}

enum TimerText {
    /// "4:05", "24:59", "1:05:00".
    static func format(_ seconds: TimeInterval, roundingUp: Bool = true) -> String {
        let total = Int(roundingUp ? seconds.rounded(.up) : seconds.rounded(.down))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
