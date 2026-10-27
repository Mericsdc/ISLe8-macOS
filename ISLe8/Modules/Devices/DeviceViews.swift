import SwiftUI

/// A small ring with what it measures inside ("L", "R", the case) and the percentage beside it.
struct BatteryBadge: View {
    enum Part {
        case main
        case left
        case right
        case chargingCase
    }

    let part: Part
    let level: Int
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: Double(level) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                label
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .frame(width: size, height: size)
            Text(verbatim: percentText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(level <= DevicesModule.lowLevel ? Color.red : Color.white.opacity(0.75))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(partName) \(percentText)"))
    }

    @ViewBuilder
    private var label: some View {
        switch part {
        case .main: EmptyView()
        case .left: Text("L")
        case .right: Text("R")
        case .chargingCase: Image(systemName: "airpods.chargingcase")
        }
    }

    private var partName: String {
        switch part {
        case .main: ""
        case .left: String(localized: "Sol")
        case .right: String(localized: "Sağ")
        case .chargingCase: String(localized: "Kutu")
        }
    }

    private var percentText: String { String(localized: "%\(level)") }

    private var tint: Color {
        switch level {
        case ...DevicesModule.lowLevel: .red
        case ...30: .orange
        default: .green
        }
    }
}

/// Every level a device reports: both buds and the case, or its one battery.
struct DeviceLevels: View {
    let device: WirelessDevice
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: 8) {
            if let main = device.main { BatteryBadge(part: .main, level: main, size: size) }
            if let left = device.left { BatteryBadge(part: .left, level: left, size: size) }
            if let right = device.right { BatteryBadge(part: .right, level: right, size: size) }
            if let caseLevel = device.caseLevel { BatteryBadge(part: .chargingCase, level: caseLevel, size: size) }
        }
    }
}

/// In the header: the connected device whose battery runs out first.
struct DevicesChip: View {
    @Environment(DevicesModule.self) private var devices

    var body: some View {
        if let device = devices.devices.min(by: { ($0.lowest ?? 101) < ($1.lowest ?? 101) }) {
            HStack(spacing: 4) {
                Image(systemName: device.symbol)
                if let level = device.lowest ?? device.caseLevel {
                    Text(verbatim: String(localized: "%\(level)"))
                        .monospacedDigit()
                        .foregroundStyle(level <= DevicesModule.lowLevel ? Color.red : Color.white)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .help(devices.devices.map(Self.summary).joined(separator: "\n"))
        }
    }

    static func summary(_ device: WirelessDevice) -> String {
        var parts: [String] = []
        if let main = device.main { parts.append(String(localized: "%\(main)")) }
        if let left = device.left { parts.append(String(localized: "Sol %\(left)")) }
        if let right = device.right { parts.append(String(localized: "Sağ %\(right)")) }
        if let caseLevel = device.caseLevel { parts.append(String(localized: "Kutu %\(caseLevel)")) }
        return ([device.name] + parts).joined(separator: " · ")
    }
}

// MARK: Devices tab

/// One battery to show: the thing it powers (as an icon) and its level.
private struct BatteryCell: Identifiable {
    let id: String
    let symbol: String
    let level: Int
    var isCharging = false
    let label: String
}

/// A card per device: this Mac first, then what is connected. Every battery is a ring with
/// the device's icon inside and its level below, like the batteries widget on iPhone. Cards
/// share a row by how many rings they hold.
struct DevicesTab: View {
    @Environment(DevicesModule.self) private var devices
    @Environment(SystemModule.self) private var system
    @Environment(UsageModule.self) private var usage

    var body: some View {
        let cards = self.cards
        let rows = Self.rows(cards)
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GeometryReader { proxy in
                    let rings = CGFloat(row.map(\.cells.count).reduce(0, +))
                    let width = proxy.size.width - CGFloat(row.count - 1) * 8
                    HStack(spacing: 8) {
                        ForEach(row) { card in
                            // Shared by ring count, but a lone card doesn't stretch across.
                            let cells = CGFloat(card.cells.count)
                            DeviceCard(card: card, ringSize: rows.count == 1 ? 58 : 46)
                                .frame(width: min(width * cells / rings, cells * 120 + 60))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: rows.count == 1 ? 140 : 112)
            }
            if devices.devices.isEmpty {
                Text("AirPods, Magic Mouse ya da pilini bildiren başka bir Bluetooth cihazı bağlanınca burada görünür.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
    }

    fileprivate struct Card: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let cells: [BatteryCell]
    }

    private var cards: [Card] {
        var cards: [Card] = []
        if let battery = system.battery {
            let status: String = if battery.isCharging, let watts = usage.adapterWatts {
                String(localized: "Şarj oluyor · \(Int(watts.rounded())) W")
            } else if battery.isCharging {
                String(localized: "Şarj oluyor")
            } else if battery.isPluggedIn {
                String(localized: "Prize takılı")
            } else {
                String(localized: "Pilde")
            }
            cards.append(Card(id: "mac", title: String(localized: "Bu Mac"), subtitle: status, cells: [
                BatteryCell(id: "mac", symbol: "laptopcomputer", level: battery.percent, isCharging: battery.isCharging, label: String(localized: "Bu Mac")),
            ]))
        }
        for device in devices.devices {
            let subtitle = device.isCharging ? String(localized: "Şarj oluyor") : nil
            cards.append(Card(id: device.id, title: device.shortName, subtitle: subtitle, cells: Self.cells(device)))
        }
        return cards
    }

    /// Buds and case get their own icons; everything else is one ring.
    private static func cells(_ device: WirelessDevice) -> [BatteryCell] {
        let pro = device.kind == .airPodsPro
        var cells: [BatteryCell] = []
        if let main = device.main {
            cells.append(BatteryCell(id: "main", symbol: device.symbol, level: main, isCharging: device.isCharging, label: device.shortName))
        }
        if let left = device.left {
            cells.append(BatteryCell(id: "left", symbol: pro ? "airpodpro.left" : "airpod.left", level: left, label: String(localized: "Sol")))
        }
        if let right = device.right {
            cells.append(BatteryCell(id: "right", symbol: pro ? "airpodpro.right" : "airpod.right", level: right, label: String(localized: "Sağ")))
        }
        if let caseLevel = device.caseLevel {
            cells.append(BatteryCell(id: "case", symbol: pro ? "airpodspro.chargingcase.wireless" : "airpods.chargingcase", level: caseLevel, label: String(localized: "Kutu")))
        }
        return cells
    }

    /// At most five rings to a row.
    private static func rows(_ cards: [Card]) -> [[Card]] {
        var rows: [[Card]] = []
        var row: [Card] = []
        for card in cards {
            if !row.isEmpty, row.map(\.cells.count).reduce(0, +) + card.cells.count > 5 {
                rows.append(row)
                row = []
            }
            row.append(card)
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

private struct DeviceCard: View {
    let card: DevicesTab.Card
    let ringSize: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: ringSize * 0.32) {
                ForEach(card.cells) { cell in
                    VStack(spacing: 6) {
                        IconRing(symbol: cell.symbol, level: cell.level, size: ringSize)
                        HStack(spacing: 2) {
                            if cell.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.green)
                            }
                            Text(verbatim: String(localized: "%\(cell.level)"))
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(cell.label) \(String(localized: "%\(cell.level)"))"))
                }
            }
            VStack(spacing: 1) {
                Text(card.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandTile()
    }
}

/// The battery ring with the device drawn inside it. Green, orange from 30 %, red from 15 %.
private struct IconRing: View {
    let symbol: String
    let level: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: size * 0.085)
            Circle()
                .trim(from: 0, to: Double(level) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .frame(width: size, height: size)
    }

    private var tint: Color {
        switch level {
        case ...DevicesModule.lowLevel: .red
        case ...30: .orange
        default: .green
        }
    }
}

/// The banner when a device connects, or when its battery runs low.
struct DeviceAlertView: View {
    let device: WirelessDevice
    let isLow: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isLow ? Color.red : Color.white)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(isLow ? String(localized: "Pil azaldı") : String(localized: "Bağlandı"))
                        .font(.system(size: 11))
                        .foregroundStyle(isLow ? Color.red : Color.white.opacity(0.55))
                }
                DeviceLevels(device: device)
            }
            Spacer(minLength: 0)
        }
    }
}
