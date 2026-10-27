import AppKit
import SwiftUI

/// The card in the middle of the screen while the keyboard is locked for cleaning: what is
/// going on, how long is left, and the button that ends it. The keyboard can't close it, the
/// mouse can.
final class KeyboardLockWindow {
    private let system: SystemModule
    private let settings: SettingsStore
    private var panel: NSPanel?

    init(system: SystemModule, settings: SettingsStore) {
        self.system = system
        self.settings = settings
    }

    func show() {
        guard panel == nil, let unlocksAt = system.keyboardUnlocksAt else { return }
        let view = KeyboardLockView(unlocksAt: unlocksAt) { [weak system] in system?.unlockKeyboard() }
            .tint(settings.theme.accent.color)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.setFrameSize(host.fittingSize)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct KeyboardLockView: View {
    let unlocksAt: Date
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.tint)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .padding(5)
                        .background(Circle().fill(Color.black))
                        .offset(x: 10, y: 8)
                }
                .padding(.bottom, 4)
            Text("Klavye kilitli")
                .font(.system(size: 20, weight: .bold))
            Text("Tuşlara basmak bir şey yazmaz; gönül rahatlığıyla silebilirsin.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Kilit \(Self.remaining(until: unlocksAt, now: context.date)) sonra kendiliğinden açılır")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            Button(action: unlock) {
                Text("Kilidi aç")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Capsule().fill(.tint))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(Int(date.timeIntervalSince(now).rounded(.up)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
