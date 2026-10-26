import AppKit

/// MediaRemote command numbers; the bridge passes them through unchanged.
enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case next = 4
    case previous = 5
    case advanceShuffle = 6
    case advanceRepeat = 7

    /// Play, pause and skip; only these are checked for having worked.
    var isTransport: Bool { rawValue <= 5 }
}

enum RepeatMode: Equatable {
    case off
    case one
    case all
}

/// What is playing right now, merged from whichever source currently knows.
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    /// Playback position at `timestamp`.
    var elapsed: TimeInterval
    var timestamp: Date
    var isPlaying: Bool
    var rate: Double
    var bundleID: String?
    var artwork: NSImage? = nil
    var accent: NSColor? = nil
    var isShuffling = false
    var repeatMode: RepeatMode = .off

    var trackKey: String { "\(title)\u{1F}\(artist)\u{1F}\(album)" }

    /// The position at `date`, worked out from the last report instead of a running timer.
    func position(at date: Date = .now) -> TimeInterval {
        var position = elapsed
        if isPlaying {
            position += date.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1)
        }
        return duration > 0 ? min(max(position, 0), duration) : max(position, 0)
    }
}

/// Now-playing data as a source reports it, before the artwork is decoded.
nonisolated struct MediaSnapshot: Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var isPlaying: Bool
    var rate: Double
    var bundleID: String?
    var artworkData: Data?
    /// The bridge leaves out artwork it has already sent.
    var artworkUnchanged: Bool
    /// MediaRemote's modes: shuffle 1 off, 2 albums, 3 songs; repeat 1 off, 2 one, 3 all.
    var shuffle: Int? = nil
    var repeatMode: Int? = nil
}
