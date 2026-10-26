import SwiftUI

/// The Home tab: the columns chosen in Settings > Layout, side by side at full height, in
/// the style picked in Settings > Appearance. Calendar, media and weather share the width
/// about evenly; the timer is narrow. In the minimal strip the player gets the most room.
struct HomeView: View {
    @Environment(SettingsStore.self) private var settings

    private static let weights: [SettingsStore.HomeStyle: [String: CGFloat]] = [
        .dashboard: ["calendar": 1, "media": 1.1, "weather": 1, "timer": 0.62],
        .compact: ["calendar": 1, "media": 1.15, "weather": 1, "timer": 0.7],
        .minimal: ["calendar": 1.1, "media": 1.7, "weather": 0.7, "timer": 0.9],
    ]

    private var spacing: CGFloat { settings.homeStyle == .dashboard ? 10 : 8 }

    var body: some View {
        let columns = settings.homeTiles
        if columns.isEmpty {
            Text("Home boş. Ayarlar > Düzen'den sütun ekleyebilirsin.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                let weights = Self.weights[settings.homeStyle] ?? [:]
                let total = columns.map { weights[$0] ?? 1 }.reduce(0, +)
                let free = proxy.size.width - CGFloat(columns.count - 1) * spacing
                HStack(spacing: spacing) {
                    ForEach(columns, id: \.self) { column in
                        HomeColumn(id: column)
                            .frame(width: free * (weights[column] ?? 1) / total)
                    }
                }
            }
        }
    }
}

private struct HomeColumn: View {
    let id: String

    var body: some View {
        switch id {
        case "calendar": CalendarColumn()
        case "media": MediaColumn()
        case "weather": WeatherColumn()
        case "timer": TimerTile()
        default: EmptyView()
        }
    }
}
