import SwiftUI

/// Now Playing: artwork and audio bars in the ears, a player on the open island, and a
/// short banner when the song changes.
@Observable
final class MediaModule: IslandModule {
    let id = "media"
    let service: NowPlayingService
    private(set) var isActive = false

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored var onTrackChange: (() -> Void)?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var hasSeenFirstUpdate = false

    init(service: NowPlayingService) {
        self.service = service
    }

    var activity: LiveActivity? {
        guard isActive else { return nil }
        return LiveActivity(
            id: id,
            priority: ActivityPriority.media,
            leading: AnyView(MediaCompactLeading()),
            trailing: AnyView(MediaCompactTrailing())
        )
    }

    func start() {
        service.onChange = { [weak self] old, new in self?.update(old: old, new: new) }
        service.start()
    }

    func stop() {
        idleTask?.cancel()
        service.stop()
        setActive(false)
    }

    private func update(old: NowPlaying?, new: NowPlaying?) {
        defer { hasSeenFirstUpdate = true }
        guard let new else {
            idleTask?.cancel()
            setActive(false)
            return
        }
        if new.isPlaying {
            idleTask?.cancel()
            setActive(true)
            // No banner for whatever was already playing when ISLe8 launched.
            if hasSeenFirstUpdate, old?.trackKey != new.trackKey {
                onTrackChange?()
            }
        } else if isActive {
            // Keep the ears a little after pausing so a quick resume doesn't flicker.
            idleTask?.cancel()
            idleTask = Task {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                setActive(false)
            }
        }
    }

    private func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onActivityChange?()
    }
}
