import SwiftUI

/// The root of the island's view tree; hands the shared objects to everything below.
struct IslandRootView: View {
    let model: IslandModel

    var body: some View {
        let theme = model.settings.theme
        IslandView()
            .environment(model)
            .environment(model.settings)
            .environment(\.islandTheme, theme)
            .environment(\.colorScheme, .dark)
            .tint(theme.accent.color)
            .fontDesign(theme.typeface.design)
            .modifier(ModuleEnvironment(modules: model.modules))
            .ignoresSafeArea()
    }
}

/// Puts each module's observable objects into the environment for its views.
struct ModuleEnvironment: ViewModifier {
    let modules: [any IslandModule]

    func body(content: Content) -> some View {
        content
            .environment(module(MediaModule.self)?.service)
            .environment(module(ShelfModule.self))
            .environment(module(ClipboardModule.self)?.service)
            .environment(module(NotificationModule.self))
            .environment(module(SystemModule.self))
            .environment(module(HUDModule.self))
            .environment(module(CalendarModule.self))
            .environment(module(WeatherModule.self))
            .environment(module(TimerModule.self))
            .environment(module(AgentsModule.self))
            .environment(module(PaletteModule.self))
            .environment(module(UsageModule.self))
            .environment(module(DevicesModule.self))
    }

    private func module<T>(_ type: T.Type) -> T? {
        modules.lazy.compactMap { $0 as? T }.first
    }
}

/// The island's fill. At rest it is always black, so the ears blend with the notch; the
/// theme applies once the island opens or shows a banner.
private struct IslandBackground: View {
    @Environment(IslandModel.self) private var model
    @Environment(NowPlayingService.self) private var media
    @Environment(\.islandTheme) private var theme
    let shape: IslandShape

    var body: some View {
        let isOpen = [.expanded, .alert, .dropTarget].contains(model.state) && model.alert != .unlocked
        switch isOpen ? theme.material : .black {
        case .glass:
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: shape)
            } else {
                shape.fill(Color.black.opacity(0.85))
            }
        case .artwork:
            shape.fill(underNotch(Color(nsColor: media.info?.accent ?? .darkGray).opacity(0.55), .black))
        case .solid:
            shape.fill(underNotch(theme.background.color, theme.background.color))
        case .gradient:
            shape.fill(underNotch(theme.background.color, theme.backgroundBottom.color))
        case .black:
            shape.fill(Color.black)
        }
    }

    /// Black across the notch row, so the notch never shows as a bite out of a coloured
    /// island, then the theme's colours below it. `.artwork` rises from the bottom instead.
    private func underNotch(_ top: Color, _ bottom: Color) -> LinearGradient {
        let height = max(model.size(for: model.state).height, 1)
        let band = min((model.geometry?.notchSize.height ?? 32) / height, 0.5)
        if theme.material == .artwork {
            return LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.5),
                .init(color: top, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: band * 0.7),
            .init(color: top, location: min(band + 0.18, 1)),
            .init(color: bottom, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

struct IslandView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let size = model.size(for: model.state)
        let shape = IslandShape(
            shoulder: model.shoulder(for: model.state),
            bottomRadius: model.bottomRadius(for: model.state)
        )

        ZStack(alignment: .top) {
            IslandBackground(shape: shape)
            content
                .padding(.horizontal, model.shoulder(for: model.state))
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { model.open() }
        .animation(model.animation, value: model.state)
        .animation(model.animation, value: model.tab)
        // External monitors from 1080p to 4K: drawn larger or smaller, growing down from the top.
        .scaleEffect(model.scale, anchor: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .compact, .peek:
            CompactView()
                .transition(.opacity)
        case .alert:
            AlertView()
                .transition(.opacity)
        case .expanded:
            // The content settles in just behind the shell and folds back up into the notch
            // with it, instead of vanishing and leaving an empty box to shrink.
            ExpandedView()
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                        .animation(.easeOut(duration: 0.22).delay(0.06)),
                    removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                        .animation(.easeIn(duration: 0.16))
                ))
        case .dropTarget:
            DropTargetView()
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
        }
    }
}

/// The ears: one activity's leading view left of the notch, its trailing view right of it.
struct CompactView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        if let activity = model.primaryActivity, let notch = model.geometry?.notchSize {
            HStack(spacing: 0) {
                activity.leading
                    .frame(width: IslandModel.earWidth)
                Spacer(minLength: notch.width)
                activity.trailing
                    .frame(width: IslandModel.earWidth)
            }
            .frame(height: notch.height)
        }
    }
}

struct AlertView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        switch model.alert {
        case .unlocked:
            UnlockedAlertView()
        case .hud(let value):
            HUDAlertView(value: value)
        default:
            banner
        }
    }

    private var banner: some View {
        VStack(spacing: 0) {
            // The notch row stays empty; the banner sits just below it.
            Color.clear
                .frame(height: model.geometry?.notchSize.height ?? 0)
            Group {
                switch model.alert {
                case .nowPlaying:
                    MediaAlertView()
                case .airDropReceived(let count):
                    AirDropAlertView(count: count)
                case .notification(let notification):
                    NotificationAlertView(notification: notification)
                case .battery(let event):
                    BatteryAlertView(event: event)
                case .meeting(let item):
                    MeetingAlertView(item: item)
                case .timer(let event):
                    TimerAlertView(event: event)
                case .approval(let approval):
                    ApprovalAlertView(approval: approval)
                case .agentDone(let session):
                    AgentDoneAlertView(session: session)
                case .usageLimit(let snapshot, let window):
                    UsageAlertView(snapshot: snapshot, window: window)
                case .deviceConnected(let device):
                    DeviceAlertView(device: device, isLow: false)
                case .deviceLowBattery(let device):
                    DeviceAlertView(device: device, isLow: true)
                case .unlocked, .hud, nil:
                    EmptyView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
            .frame(maxHeight: .infinity)
        }
    }
}

struct ExpandedView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Group {
                switch model.tab {
                case .home:
                    HomeView()
                case .shelf:
                    ShelfTab()
                case .clipboard:
                    ClipboardTab()
                case .agents:
                    AgentsTab()
                case .devices:
                    DevicesTab()
                case .palette:
                    PaletteTab()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
            // Tabs share one size, so changing tab is a quick crossfade of the content alone.
            .id(model.tab)
            .transition(.opacity.animation(.easeInOut(duration: 0.18)))
            if model.tab != .palette {
                TabDock()
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            } else {
                Color.clear.frame(height: model.bottomSpace(for: .palette))
            }
        }
    }
}
