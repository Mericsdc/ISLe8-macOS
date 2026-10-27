import SwiftUI

// MARK: Ears

struct MediaCompactLeading: View {
    @Environment(NowPlayingService.self) private var media

    var body: some View {
        ArtworkView(image: media.info?.artwork, size: 22, radius: 6)
    }
}

struct MediaCompactTrailing: View {
    @Environment(NowPlayingService.self) private var media
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if settings.showVisualizer {
            AudioBars(isPlaying: media.info?.isPlaying ?? false, color: media.info?.accent ?? .white)
                .frame(width: 20, height: 14)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: media.info?.accent ?? .white))
        }
    }
}

// MARK: Banner

struct MediaAlertView: View {
    @Environment(NowPlayingService.self) private var media

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(image: media.info?.artwork, size: 30, radius: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(media.info?.title ?? "")
                    .font(.system(size: 12, weight: .semibold))
                Text(media.info?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            AudioBars(isPlaying: media.info?.isPlaying ?? false, color: media.info?.accent ?? .white)
                .frame(width: 20, height: 14)
        }
    }
}

// MARK: Player

/// Home's media column. Dashboard: artwork and title, the scrubber, shuffle / previous /
/// play / next / repeat, and the Mac's output volume. Compact: artwork beside the title and
/// the controls. Minimal: one line. The controls stay even when nothing plays, so play can
/// wake the last player.
struct MediaColumn: View {
    @Environment(NowPlayingService.self) private var media
    @Environment(HUDModule.self) private var hud
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        switch settings.homeStyle {
        case .dashboard: full
        case .compact: compact
        case .minimal: minimal
        }
    }

    /// The minimal strip: small artwork, the title, previous / play / next.
    private var minimal: some View {
        let info = media.info
        return HStack(spacing: 6) {
            ArtworkView(image: info?.artwork, size: 38, radius: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(info?.title ?? String(localized: "Şu an bir şey çalmıyor"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let artist = info?.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            TransportButton(systemImage: "backward.fill", help: "Önceki") { media.perform(.previous) }
            TransportButton(
                systemImage: info?.isPlaying == true ? "pause.fill" : "play.fill",
                help: info?.isPlaying == true ? LocalizedStringKey("Duraklat") : LocalizedStringKey("Oynat"),
                isProminent: true
            ) {
                playOrResume()
            }
            TransportButton(systemImage: "forward.fill", help: "Sonraki") { media.perform(.next) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The compact strip: artwork, and beside it the title over the controls; with Spotify
    /// playing, Spotify's own volume underneath.
    private var compact: some View {
        VStack(spacing: 7) {
            compactPlayer
            if media.info?.bundleID == PlayerApp.spotify.rawValue {
                SpotifyVolumeBar()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactPlayer: some View {
        let info = media.info
        return HStack(spacing: 10) {
            ArtworkView(image: info?.artwork, size: 64, radius: 10)
                .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(info?.title ?? String(localized: "Şu an bir şey çalmıyor"))
                    .font(.system(size: 13, weight: .semibold))
                Text(info.map { $0.artist } ?? String(localized: "Spotify, Music ya da tarayıcıda bir şey başlat."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer(minLength: 0)
                controls(playSize: 34, accentRing: true)
            }
            .lineLimit(1)
            .frame(height: 64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dashboard: artwork and title, scrubber, controls, volume, spread over the full height.
    private var full: some View {
        let info = media.info
        let artwork: CGFloat = 104
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ArtworkView(image: info?.artwork, size: artwork, radius: 14)
                    .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Spacer(minLength: 0)
                    Text(info?.title ?? String(localized: "Şu an bir şey çalmıyor"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text(info.map { $0.artist } ?? String(localized: "Spotify, Music ya da tarayıcıda bir şey başlat."))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(height: artwork)
                Spacer(minLength: 0)
                AppIconBadge(bundleID: info?.bundleID)
            }
            Spacer(minLength: 8)

            if let info {
                PlaybackScrubber(info: info) { media.seek(to: $0) }
            } else {
                VStack(spacing: 3) {
                    Capsule().fill(Color.white.opacity(0.15)).frame(height: 4).frame(height: 10)
                    HStack {
                        Text(verbatim: "0:00")
                        Spacer()
                        Text(verbatim: "0:00")
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            Spacer(minLength: 8)
            controls(playSize: 52)
            Spacer(minLength: 8)

            if let volume = hud.outputVolume {
                HStack(spacing: 8) {
                    Image(systemName: Self.speaker(volume))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 18)
                    Slider(value: Binding(get: { volume }, set: { hud.setOutputVolume($0) }), in: 0...1)
                        .controlSize(.small)
                        .accessibilityLabel("Ses")
                    Text(verbatim: "\(Int((volume * 100).rounded()))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .islandTile()
    }

    /// Play/pause; with nothing playing, opens the default player and resumes it.
    private func playOrResume() {
        if media.info == nil {
            media.resume(preferring: PlayerApp(rawValue: settings.defaultPlayer))
        } else {
            media.perform(.togglePlayPause)
        }
    }

    /// Shuffle / previous / play / next / repeat, spread across the width.
    private func controls(playSize: CGFloat, accentRing: Bool = false) -> some View {
        let info = media.info
        return HStack(spacing: 0) {
            ModeButton(systemImage: "shuffle", isOn: info?.isShuffling == true, help: "Karışık çal") {
                media.perform(.advanceShuffle)
            }
            Spacer(minLength: 0)
            TransportButton(systemImage: "backward.fill", help: "Önceki") { media.perform(.previous) }
            Spacer(minLength: 0)
            PlayButton(isPlaying: info?.isPlaying == true, size: playSize, accentRing: accentRing) {
                playOrResume()
            }
            Spacer(minLength: 0)
            TransportButton(systemImage: "forward.fill", help: "Sonraki") { media.perform(.next) }
            Spacer(minLength: 0)
            ModeButton(
                systemImage: info?.repeatMode == .one ? "repeat.1" : "repeat",
                isOn: (info?.repeatMode ?? .off) != .off,
                help: "Tekrarla"
            ) {
                media.perform(.advanceRepeat)
            }
        }
    }

    private static func speaker(_ volume: Double) -> String {
        switch volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// The large play button in a ring, as the centre of the controls. The compact strip rings
/// it in the theme's accent.
private struct PlayButton: View {
    let isPlaying: Bool
    var size: CGFloat = 52
    var accentRing = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.35, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.16 : 0.08)))
                .overlay {
                    if accentRing {
                        Circle().strokeBorder(.tint, lineWidth: 1.5)
                    } else {
                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "Duraklat" : "Oynat")
        .accessibilityLabel(isPlaying ? "Duraklat" : "Oynat")
        .onHover { isHovering = $0 }
    }
}

/// Shuffle and repeat: tinted while on.
private struct ModeButton: View {
    let systemImage: String
    let isOn: Bool
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.6)))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct PlaybackScrubber: View {
    let info: NowPlaying
    let onSeek: (TimeInterval) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        // Ticks twice a second, and only while playing on the open island.
        TimelineView(.animation(minimumInterval: 0.5, paused: !info.isPlaying || dragFraction != nil)) { context in
            let canSeek = info.duration > 0
            let position = dragFraction.map { $0 * info.duration } ?? info.position(at: context.date)
            let fraction = canSeek ? position / info.duration : 0

            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(Color.white.opacity(dragFraction == nil ? 0.85 : 1))
                            .frame(width: proxy.size.width * fraction)
                    }
                    .frame(height: dragFraction == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(canSeek ? seekGesture(width: proxy.size.width) : nil)
                }
                .frame(height: 10)

                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text(canSeek ? "-" + Self.format(info.duration - position) : "")
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragFraction = min(max(value.location.x / max(width, 1), 0), 1)
            }
            .onEnded { value in
                let fraction = min(max(value.location.x / max(width, 1), 0), 1)
                dragFraction = nil
                onSeek(fraction * info.duration)
            }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TransportControls: View {
    @Environment(NowPlayingService.self) private var media
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 22) {
            TransportButton(systemImage: "backward.fill", help: "Önceki") {
                media.perform(.previous)
            }
            TransportButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                help: isPlaying ? LocalizedStringKey("Duraklat") : LocalizedStringKey("Oynat"),
                isProminent: true
            ) {
                media.perform(.togglePlayPause)
            }
            TransportButton(systemImage: "forward.fill", help: "Sonraki") {
                media.perform(.next)
            }
        }
    }
}

struct TransportButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    var isProminent = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let side: CGFloat = isProminent ? 34 : 28
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isProminent ? 16 : 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: side, height: side)
                .background(Circle().fill(Color.white.opacity(background)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
        .onHover { isHovering = $0 }
    }

    private var background: Double {
        switch (isProminent, isHovering) {
        case (true, true): 0.22
        case (true, false): 0.12
        case (false, true): 0.10
        case (false, false): 0
        }
    }
}

// MARK: Shared pieces

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.08)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The playing app's icon. Clicking it brings that app forward.
struct AppIconBadge: View {
    let bundleID: String?

    var body: some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Button {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } label: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Uygulamayı aç")
        }
    }
}

/// Spotify's own volume, like the bar in Spotify: it leaves the Mac's volume alone. Read once
/// when shown; while dragging, Spotify is told at most ten times a second.
private struct SpotifyVolumeBar: View {
    @State private var level: Double?
    @State private var dragging: Double?
    @State private var isHovering = false
    @State private var lastSent = Date.distantPast

    private static let green = Color(red: 0.11, green: 0.73, blue: 0.33)

    var body: some View {
        let value = dragging ?? level ?? 0
        HStack(spacing: 6) {
            Image(systemName: value == 0 ? "speaker.slash.fill" : value < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 14)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(isHovering || dragging != nil ? Self.green : Color.white.opacity(0.85))
                        .frame(width: proxy.size.width * value)
                }
                .frame(height: dragging == nil ? 4 : 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let fraction = min(max(drag.location.x / max(proxy.size.width, 1), 0), 1)
                            dragging = fraction
                            if Date().timeIntervalSince(lastSent) > 0.1 {
                                lastSent = Date()
                                PlayerScript.setVolume(Int((fraction * 100).rounded()), on: .spotify)
                            }
                        }
                        .onEnded { drag in
                            let fraction = min(max(drag.location.x / max(proxy.size.width, 1), 0), 1)
                            dragging = nil
                            level = fraction
                            PlayerScript.setVolume(Int((fraction * 100).rounded()), on: .spotify)
                        }
                )
            }
            .frame(height: 12)
            Text(verbatim: level == nil && dragging == nil ? "—" : String(localized: "%\(Int((value * 100).rounded()))"))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 30, alignment: .trailing)
        }
        .onHover { isHovering = $0 }
        .help("Spotify'ın ses seviyesi")
        .task {
            if let volume = await PlayerScript.volume(of: .spotify) {
                level = Double(volume) / 100
            }
        }
    }
}
