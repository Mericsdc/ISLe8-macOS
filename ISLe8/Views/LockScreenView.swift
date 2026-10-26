import AppKit
import SwiftUI

struct LockScreenRootView: View {
    let model: IslandModel

    var body: some View {
        LockScreenView()
            .environment(model)
            .environment(model.settings)
            .environment(\.colorScheme, .dark)
            .modifier(ModuleEnvironment(modules: model.modules))
            .ignoresSafeArea()
    }
}

/// The island on the lock screen. The notch keeps only its ears (a lock, and audio bars
/// while music plays); what is playing and what arrived while locked sit as cards below
/// the system clock, like widgets. Read-only apart from media controls: the shelf,
/// clipboard and everything else stay out of reach until the Mac is unlocked.
struct LockScreenView: View {
    @Environment(IslandModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(NowPlayingService.self) private var media
    @Environment(NotificationModule.self) private var notifications

    static let cardWidth: CGFloat = 380

    /// Distance from the top of the screen to the first card.
    static func cardTop(in screen: CGRect, settings: SettingsStore) -> CGFloat {
        (screen.height * settings.lockScreenCardPosition).rounded()
    }

    var body: some View {
        // Nothing is drawn while unlocked, so the hidden window never animates anything.
        if model.isLocked || model.isPreviewingLockScreen, let geometry = model.geometry {
            let isPreview = !model.isLocked
            let info = settings.lockScreenShowsMedia ? media.info : nil
            let groups = settings.lockScreenShowsNotifications ? Self.groups(notifications.lockedNotifications) : []
            let top = Self.cardTop(in: geometry.screenFrame, settings: settings)

            VStack(spacing: 0) {
                LockEars(info: info, notch: geometry.notchSize)
                Color.clear
                    .frame(height: max(top - geometry.notchSize.height, 0))
                VStack(spacing: 8) {
                    if let info {
                        LockMediaCard(info: info)
                    } else if isPreview {
                        LockPlaceholderCard(systemImage: "music.note", text: "Çalan şarkı burada görünür")
                    }
                    ForEach(groups.prefix(3), id: \.bundleID) { group in
                        LockNotificationCard(group: group)
                    }
                    if isPreview && groups.isEmpty {
                        LockPlaceholderCard(systemImage: "bell.fill", text: "Kilitliyken gelen bildirimler burada görünür")
                    }
                }
                .frame(width: Self.cardWidth)
                .animation(.spring(response: 0.38, dampingFraction: 0.85), value: groups.count)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    struct AppGroup: Equatable {
        let bundleID: String
        let latest: AppNotification
        let count: Int
    }

    /// One card per app, newest app first.
    static func groups(_ notifications: [AppNotification]) -> [AppGroup] {
        var order: [String] = []
        var byApp: [String: [AppNotification]] = [:]
        for notification in notifications {
            if byApp[notification.bundleID] == nil {
                order.append(notification.bundleID)
            }
            byApp[notification.bundleID, default: []].append(notification)
        }
        return order.compactMap { id in
            guard let items = byApp[id], let latest = items.first else { return nil }
            return AppGroup(bundleID: id, latest: latest, count: items.count)
        }
    }
}

/// The collapsed island at the notch: a lock on the left, audio bars on the right.
private struct LockEars: View {
    let info: NowPlaying?
    let notch: CGSize

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: IslandModel.earWidth)
            Spacer(minLength: notch.width)
            ZStack {
                if let info {
                    AudioBars(isPlaying: info.isPlaying, color: info.accent ?? .white)
                        .frame(width: 20, height: 14)
                }
            }
            .frame(width: IslandModel.earWidth)
        }
        .padding(.horizontal, 6)
        .frame(width: notch.width + 2 * IslandModel.earWidth + 12, height: notch.height)
        .background(IslandShape(shoulder: 6, bottomRadius: 12).fill(Color.black))
    }
}

/// A frosted card, like the widgets and notifications macOS shows on the lock screen.
private struct LockCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FrostedBackground()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12))
            )
    }
}

/// Blurs whatever is behind the window: here, the lock screen wallpaper.
private struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct LockMediaCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(NowPlayingService.self) private var media
    let info: NowPlaying

    var body: some View {
        LockCard {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ArtworkView(image: info.artwork, size: 48, radius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(info.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                if settings.lockScreenMediaControls {
                    PlaybackScrubber(info: info) { media.seek(to: $0) }
                    TransportControls(isPlaying: info.isPlaying)
                }
            }
        }
    }
}

private struct LockNotificationCard: View {
    @Environment(SettingsStore.self) private var settings
    let group: LockScreenView.AppGroup

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        let latest = group.latest
        let hidesContent = settings.hideNotificationContentWhenLocked
        LockCard {
            HStack(alignment: .top, spacing: 10) {
                AppIconView(bundleID: group.bundleID, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(AppInfo.name(for: group.bundleID))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Spacer(minLength: 4)
                        Text(Self.relativeFormatter.localizedString(for: latest.date, relativeTo: .now))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    if hidesContent {
                        Text(group.count == 1 ? String(localized: "1 yeni bildirim") : String(localized: "\(group.count) yeni bildirim"))
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        if !latest.title.isEmpty {
                            Text(latest.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        if !latest.detail.isEmpty {
                            Text(latest.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.75))
                                .lineLimit(2)
                        }
                        if group.count > 1 {
                            Text("+\(group.count - 1) bildirim daha")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                }
            }
        }
    }
}

/// Shown only in the preview, so the cards can be placed before anything real is there.
private struct LockPlaceholderCard: View {
    let systemImage: String
    let text: LocalizedStringKey

    var body: some View {
        LockCard {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
    }
}
