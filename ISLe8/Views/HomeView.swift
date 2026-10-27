import SwiftUI

/// The Home tab: the columns chosen in Settings > Layout, side by side at full height, in
/// the style picked in Settings > Appearance. On the dashboard each column is a card and
/// calendar, media and weather share the width about evenly. The compact and minimal strips
/// are flat, split by hairlines, with the player in the middle under the notch.
struct HomeView: View {
    @Environment(SettingsStore.self) private var settings

    private static let weights: [String: CGFloat] = ["calendar": 1, "media": 1.1, "weather": 1, "timer": 0.62]

    /// A card gap on the dashboard; a hairline with room on both sides in the strips.
    private var gap: CGFloat { settings.homeStyle == .dashboard ? 10 : HomeStrip.gap }

    var body: some View {
        let columns = settings.homeTiles
        if columns.isEmpty {
            Text("Home boş. Ayarlar > Düzen'den sütun ekleyebilirsin.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                let widths = widths(of: columns, in: proxy.size.width)
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.element) { index, column in
                        if index > 0 {
                            separator
                        }
                        HomeColumn(id: column)
                            .frame(width: widths[index])
                    }
                }
            }
        }
    }

    private func widths(of columns: [String], in width: CGFloat) -> [CGFloat] {
        guard settings.homeStyle == .dashboard else {
            return HomeStrip.widths(columns, style: settings.homeStyle, in: width)
        }
        let total = columns.map { Self.weights[$0] ?? 1 }.reduce(0, +)
        let free = width - CGFloat(columns.count - 1) * gap
        return columns.map { free * (Self.weights[$0] ?? 1) / total }
    }

    @ViewBuilder
    private var separator: some View {
        if settings.homeStyle == .dashboard {
            Color.clear.frame(width: gap)
        } else {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 4)
                .padding(.horizontal, (gap - 1) / 2)
        }
    }
}

/// How the compact and minimal strips share their width. Each column gets what it needs; the
/// player sits in the middle, under the notch, and the columns either side of it get equal
/// halves. When the two sides would be very uneven (the timer on one of them), the columns
/// just go side by side.
enum HomeStrip {
    static let gap: CGFloat = 21

    private static let needs: [SettingsStore.HomeStyle: [String: CGFloat]] = [
        .compact: ["calendar": 270, "media": 240, "weather": 270, "timer": 120],
        .minimal: ["calendar": 170, "media": 250, "weather": 190, "timer": 130],
    ]

    /// The width the columns need, gaps included.
    static func width(_ columns: [String], style: SettingsStore.HomeStyle) -> CGFloat {
        guard !columns.isEmpty else { return 0 }
        if let (left, right) = sides(of: columns, style: style) {
            return need("media", style) + 2 * max(span(left, style), span(right, style))
        }
        return columns.map { need($0, style) }.reduce(0, +) + CGFloat(columns.count - 1) * gap
    }

    /// Each column's width in a strip `total` wide.
    static func widths(_ columns: [String], style: SettingsStore.HomeStyle, in total: CGFloat) -> [CGFloat] {
        if let (left, right) = sides(of: columns, style: style) {
            let media = need("media", style)
            let half = (total - media) / 2
            return share(left, half - CGFloat(left.count) * gap, style)
                + [media]
                + share(right, half - CGFloat(right.count) * gap, style)
        }
        return share(columns[...], total - CGFloat(columns.count - 1) * gap, style)
    }

    /// The columns left and right of the player, when it can sit in the middle.
    private static func sides(
        of columns: [String],
        style: SettingsStore.HomeStyle
    ) -> (ArraySlice<String>, ArraySlice<String>)? {
        guard let index = columns.firstIndex(of: "media"), index > 0, index < columns.count - 1 else { return nil }
        let left = columns[..<index]
        let right = columns[(index + 1)...]
        return abs(span(left, style) - span(right, style)) <= 80 ? (left, right) : nil
    }

    /// One side of the player: its columns, each with the gap that separates it.
    private static func span(_ columns: ArraySlice<String>, _ style: SettingsStore.HomeStyle) -> CGFloat {
        columns.map { need($0, style) + gap }.reduce(0, +)
    }

    /// `room` split in proportion to what each column needs.
    private static func share(_ columns: ArraySlice<String>, _ room: CGFloat, _ style: SettingsStore.HomeStyle) -> [CGFloat] {
        let total = columns.map { need($0, style) }.reduce(0, +)
        return columns.map { need($0, style) / max(total, 1) * room }
    }

    private static func need(_ column: String, _ style: SettingsStore.HomeStyle) -> CGFloat {
        needs[style]?[column] ?? 150
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

extension View {
    /// A Home column's backing: a card on the dashboard, nothing in the flat strips.
    @ViewBuilder
    func homeColumn(_ style: SettingsStore.HomeStyle) -> some View {
        if style == .dashboard {
            islandTile()
        } else {
            self
        }
    }
}
