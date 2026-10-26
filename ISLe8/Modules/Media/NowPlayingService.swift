import AppKit

/// Merges the MediaRemote bridge (every app) with the Spotify/Music fallback, and sends
/// commands down whichever path actually works.
@Observable
final class NowPlayingService {
    enum BridgeStatus {
        case starting
        case running
        case unavailable
    }

    /// What the island shows. Commands update it right away; the next report corrects it.
    private(set) var info: NowPlaying?
    private(set) var bridgeStatus: BridgeStatus = .starting

    @ObservationIgnored var onChange: ((_ old: NowPlaying?, _ new: NowPlaying?) -> Void)?

    @ObservationIgnored private let bridge = MediaRemoteSource()
    @ObservationIgnored private let players = PlayerAppSource()
    @ObservationIgnored private var bridgeInfo: NowPlaying?
    @ObservationIgnored private var playerInfo: NowPlaying?
    /// The sources' last word, without the optimistic changes in `info`.
    @ObservationIgnored private var reported: NowPlaying?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var bridgeExits: [Date] = []
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var bridgeCommandsWork = true
    @ObservationIgnored private var bridgeCommandMisses = 0
    @ObservationIgnored private var verifyTask: Task<Void, Never>?

    func start() {
        guard !isStarted else { return }
        isStarted = true

        bridge.onEvent = { [weak self] event in self?.handle(event) }
        bridge.onExit = { [weak self] in self?.bridgeExited() }
        bridgeStatus = bridge.start() ? .starting : .unavailable

        players.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            playerInfo = makeInfo(snapshot, previous: playerInfo)
            publish()
        }
        players.start()
    }

    func stop() {
        isStarted = false
        restartTask?.cancel()
        verifyTask?.cancel()
        bridge.stop()
        players.stop()
    }

    // MARK: Commands

    func perform(_ command: MediaCommand) {
        let before = reported
        if bridgeCommandsWork, bridgeStatus == .running {
            bridge.send("cmd \(command.rawValue)")
            verify(command, before: before)
        } else {
            fallback(command)
        }
        showOptimistically(command)
    }

    func seek(to time: TimeInterval) {
        if bridgeCommandsWork, bridgeStatus == .running {
            bridge.send("seek \(time)")
        } else if let id = reported?.bundleID, let player = PlayerApp(rawValue: id) {
            PlayerScript.seek(to: time, on: player)
        }
        if var current = info {
            current.elapsed = time
            current.timestamp = .now
            info = current
        }
    }

    /// Some macOS releases accept MediaRemote commands and then ignore them. If nothing
    /// changes shortly after a command, repeat it another way; after two misses in a row,
    /// stop trying MediaRemote for commands.
    private func verify(_ command: MediaCommand, before: NowPlaying?) {
        verifyTask?.cancel()
        // Not every player reports shuffle and repeat, so those are taken on trust.
        guard before != nil, command.isTransport else { return }
        verifyTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            if Self.tookEffect(command, before: before, after: reported) {
                bridgeCommandMisses = 0
            } else {
                bridgeCommandMisses += 1
                if bridgeCommandMisses >= 2 {
                    bridgeCommandsWork = false
                }
                fallback(command)
            }
        }
    }

    private static func tookEffect(_ command: MediaCommand, before: NowPlaying?, after: NowPlaying?) -> Bool {
        guard let before else { return true }
        guard let after else { return command == .pause }
        switch command {
        case .play: return after.isPlaying
        case .pause: return !after.isPlaying
        case .togglePlayPause: return after.isPlaying != before.isPlaying
        case .next: return after.trackKey != before.trackKey
        case .previous: return after.trackKey != before.trackKey || after.position() < 4
        case .advanceShuffle, .advanceRepeat: return true
        }
    }

    private func fallback(_ command: MediaCommand) {
        if let id = reported?.bundleID, let player = PlayerApp(rawValue: id) {
            PlayerScript.run(command, on: player)
        } else if command.isTransport {
            MediaKeys.press(command)
        }
    }

    private func showOptimistically(_ command: MediaCommand) {
        guard var current = info else { return }
        let shouldPlay: Bool
        switch command {
        case .togglePlayPause: shouldPlay = !current.isPlaying
        case .play: shouldPlay = true
        case .pause: shouldPlay = false
        case .next, .previous: return
        case .advanceShuffle:
            current.isShuffling.toggle()
            info = current
            return
        case .advanceRepeat:
            current.repeatMode = switch current.repeatMode {
            case .off: .all
            case .all: .one
            case .one: .off
            }
            info = current
            return
        }
        let now = Date()
        current.elapsed = current.position(at: now)
        current.timestamp = now
        current.isPlaying = shouldPlay
        current.rate = shouldPlay ? 1 : 0
        info = current
    }

    // MARK: Sources

    private func handle(_ event: BridgeEvent) {
        switch event {
        case .ready:
            bridgeStatus = .running
        case .data(let snapshot):
            bridgeInfo = makeInfo(snapshot, previous: bridgeInfo)
            publish()
        case .ack:
            break
        case .failure(let message):
            NSLog("ISLe8: MediaRemote bridge failed: \(message)")
            bridgeStatus = .unavailable
        }
    }

    /// Restart a crashed bridge, but give up if it keeps dying.
    private func bridgeExited() {
        bridgeInfo = nil
        publish()
        guard isStarted else { return }
        let now = Date()
        bridgeExits = bridgeExits.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard bridgeExits.count < 3 else {
            bridgeStatus = .unavailable
            return
        }
        bridgeStatus = .starting
        restartTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, isStarted else { return }
            if !bridge.start() {
                bridgeStatus = .unavailable
            }
        }
    }

    private func makeInfo(_ snapshot: MediaSnapshot?, previous: NowPlaying?) -> NowPlaying? {
        guard let snapshot else { return nil }
        var info = NowPlaying(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration,
            elapsed: snapshot.elapsed,
            timestamp: snapshot.timestamp,
            isPlaying: snapshot.isPlaying,
            rate: snapshot.rate,
            bundleID: snapshot.bundleID
        )
        info.isShuffling = (snapshot.shuffle ?? (previous?.isShuffling == true ? 2 : 1)) >= 2
        info.repeatMode = switch snapshot.repeatMode {
        case 2: .one
        case 3: .all
        case nil: previous?.repeatMode ?? .off
        default: .off
        }
        if let data = snapshot.artworkData, let artwork = Artwork.decode(data) {
            info.artwork = artwork.image
            info.accent = artwork.accent
        } else if let previous, snapshot.artworkUnchanged || previous.trackKey == info.trackKey {
            info.artwork = previous.artwork
            info.accent = previous.accent
        }
        return info
    }

    private func publish() {
        let merged = bridgeInfo ?? playerInfo
        reported = merged
        guard merged != info else { return }
        let old = info
        info = merged
        onChange?(old, merged)
    }
}
