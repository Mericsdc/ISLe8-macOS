import SwiftUI

/// A notification banner below the notch. Clicking it opens the app that sent it.
struct NotificationAlertView: View {
    @Environment(IslandModel.self) private var model
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(bundleID: notification.bundleID, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(AppInfo.name(for: notification.bundleID))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Spacer(minLength: 4)
                    if model.pendingNotificationCount > 0 {
                        Text("+\(model.pendingNotificationCount)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                }
                if !notification.title.isEmpty {
                    Text(notification.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                if !notification.detail.isEmpty {
                    Text(notification.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            AppInfo.open(notification.bundleID)
            model.dismissAlert()
        }
    }
}

/// The ears right after unlocking: an open lock that fades away.
struct UnlockedAlertView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        if let notch = model.geometry?.notchSize {
            HStack(spacing: 0) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .frame(width: IslandModel.earWidth)
                Spacer(minLength: notch.width)
                Color.clear
                    .frame(width: IslandModel.earWidth)
            }
            .frame(height: notch.height)
        }
    }
}

struct AppIconView: View {
    let bundleID: String
    let size: CGFloat

    var body: some View {
        if let icon = AppInfo.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    Image(systemName: "bell.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Color.white.opacity(0.6))
                )
                .frame(width: size, height: size)
        }
    }
}
