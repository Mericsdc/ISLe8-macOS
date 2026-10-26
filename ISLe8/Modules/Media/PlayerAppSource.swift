import AppKit

nonisolated enum PlayerApp: String, CaseIterable, Sendable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var notificationName: String {
        switch self {
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        case .music: "com.apple.Music.playerInfo"
        }
    }

    var scriptingName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }
}

/// Spotify and Music announce every state change with a distributed notification. That
/// needs no permission and keeps working even if MediaRemote is ever closed off entirely.
/// It carries no artwork, so it is only the fallback.
final class PlayerAppSource {
    var onSnapshot: ((MediaSnapshot?) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in PlayerApp.allCases {
            let observer = center.addObserver(
                forName: Notification.Name(player.notificationName),
                object: nil,
                queue: .main
            ) { [weak self] note in
                let snapshot = Self.snapshot(from: note.userInfo, player: player)
                MainActor.assumeIsolated { self?.onSnapshot?(snapshot) }
            }
            observers.append(observer)
        }
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    nonisolated private static func snapshot(from info: [AnyHashable: Any]?, player: PlayerApp) -> MediaSnapshot? {
        guard let info,
              let state = info["Player State"] as? String, state != "Stopped",
              let title = info["Name"] as? String, !title.isEmpty
        else { return nil }
        let isPlaying = state == "Playing"
        // Spotify reports "Duration", Music "Total Time"; both in milliseconds.
        let milliseconds = info["Duration"] as? Double ?? info["Total Time"] as? Double ?? 0
        return MediaSnapshot(
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: milliseconds / 1000,
            elapsed: info["Playback Position"] as? Double ?? 0,
            timestamp: Date(),
            isPlaying: isPlaying,
            rate: isPlaying ? 1 : 0,
            bundleID: player.rawValue,
            artworkData: nil,
            artworkUnchanged: false
        )
    }
}
