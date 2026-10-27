import SwiftUI

/// The root of the island's view tree; hands the shared objects to everything below.
struct IslandRootView: View {
    let model: IslandModel

    var body: some View {
        let theme = model.settings.islandTheme
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
            .environment(module(NotesModule.self))
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
        // The theme fades in over the black rather than replacing it, so the island never
        // turns see-through halfway. Only glass lets the black go.
        ZStack {
            shape.fill(Color.black)
                .opacity(isOpen && theme.material == .glass ? 0 : 1)
            if isOpen && theme.material != .black {
                themeFill
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var themeFill: some View {
        switch theme.material {
        case .glass:
            // Apple's clear glass: the colours behind bleed through and bend a little at the
            // edges. Darker in the middle, where the text is, so it reads over anything; a
            // thin rim catches the light along the bottom. The notch row stays black.
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.clear.tint(Color.black.opacity(0.1)), in: shape)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.black.opacity(0.34))
                            .padding(14)
                            .blur(radius: 16)
                            .clipShape(shape)
                    }
                    .overlay(shape.stroke(rim, lineWidth: 1.5))
                    .overlay(shape.fill(underNotch(.clear, .clear)))
            } else {
                shape.fill(Color.black.opacity(0.85))
            }
        case .artwork:
            // On black, so the artwork colour tints the island instead of letting the windows
            // behind show through it.
            shape.fill(Color.black)
                .overlay(shape.fill(underNotch(Color(nsColor: media.info?.accent ?? .darkGray).opacity(0.55), .black)))
        case .solid:
            shape.fill(underNotch(theme.background.color, theme.background.color))
        case .gradient:
            shape.fill(underNotch(theme.background.color, theme.backgroundBottom.color))
        case .black:
            shape.fill(Color.black)
        }
    }

    /// Clear along the notch row, brightening towards the bottom edge.
    private var rim: LinearGradient {
        let height = max(model.size(for: model.state).height, 1)
        let band = min((model.geometry?.notchSize.height ?? 32) / height, 0.5)
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: band),
            .init(color: Color.white.opacity(0.16), location: min(band + 0.25, 1)),
            .init(color: Color.white.opacity(0.42), location: 1),
        ], startPoint: .top, endPoint: .bottom)
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
        let shoulder = model.shoulder(for: model.state)
        let radius = model.bottomRadius(for: model.state)
        let outline = CenteredIslandShape(size: size, shoulder: shoulder, bottomRadius: radius)

        // Everything sits in one fixed frame the size of the window, centred under the notch;
        // only the fill and the outline grow and shrink. Inside a frame that grows, the views
        // would be placed from its left edge and slide sideways while the island opens.
        ZStack(alignment: .top) {
            IslandBackground(shape: IslandShape(shoulder: shoulder, bottomRadius: radius))
                .frame(width: size.width, height: size.height)
            if model.state == .expanded, let occasion = model.settings.activeOccasion {
                SeasonalDecor(
                    occasion: occasion, shoulder: shoulder, bottomRadius: radius,
                    headerHeight: model.geometry?.notchSize.height ?? 36
                )
                .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(outline)
        .contentShape(outline)
        .onTapGesture { model.open() }
        // External monitors from 1080p to 4K: drawn larger or smaller, growing down from the top.
        .scaleEffect(model.scale, anchor: .top)
        .animation(model.animation, value: model.state)
        .animation(model.animation, value: model.tab)
    }

    /// Each state's views carry their own frame, so a state that appears is laid out straight
    /// under the notch instead of inside the frame of the state before it.
    @ViewBuilder
    private var content: some View {
        let size = model.size(for: model.state)
        let shoulder = model.shoulder(for: model.state)
        switch model.state {
        case .idle:
            EmptyView()
        case .compact, .peek:
            CompactView()
                .islandFrame(size, shoulder: shoulder)
                .transition(.opacity)
        case .alert:
            AlertView()
                .islandFrame(size, shoulder: shoulder)
                .transition(.opacity)
        case .expanded:
            // The content settles in just behind the shell and folds back up into the notch
            // with it, instead of vanishing and leaving an empty box to shrink.
            ExpandedView()
                .islandFrame(size, shoulder: shoulder)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                        .animation(.easeOut(duration: 0.22).delay(0.06)),
                    removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                        .animation(.easeIn(duration: 0.16))
                ))
        case .dropTarget:
            DropTargetView()
                .islandFrame(size, shoulder: shoulder)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
        }
    }
}

private extension View {
    func islandFrame(_ size: CGSize, shoulder: CGFloat) -> some View {
        padding(.horizontal, shoulder)
            .frame(width: size.width, height: size.height, alignment: .top)
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
        case .battery(.pluggedIn(let percent)):
            StatusEarsView(symbol: "battery.100percent.bolt", text: String(localized: "%\(percent)"), label: String(localized: "Şarj oluyor"))
        case .battery(.unplugged(let percent)):
            StatusEarsView(symbol: "battery.75percent", text: String(localized: "%\(percent)"), label: String(localized: "Pilde"), tint: .white)
        case .wired(true):
            StatusEarsView(symbol: "cable.connector.horizontal", text: "LAN", label: String(localized: "Kabloyla bağlandı"))
        case .wired(false):
            StatusEarsView(symbol: model.modules.lazy.compactMap { $0 as? SystemModule }.first?.network == .offline ? "wifi.slash" : "wifi", text: model.modules.lazy.compactMap { $0 as? SystemModule }.first?.network == .offline ? String(localized: "Çevrimdışı") : "Wi-Fi", label: String(localized: "Kablo çıkarıldı"), tint: .white)
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
                case .unlocked, .hud, .wired, nil:
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
                case .notes:
                    NotesTab()
                case .devices:
                    DevicesTab()
                case .system:
                    SystemTab()
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
