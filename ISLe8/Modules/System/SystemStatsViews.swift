import SwiftUI

/// The System tab: CPU, memory, startup disk and network as gauges, and beside them the
/// processes using the most CPU. Figures are taken only while this tab is on screen, and
/// change without animating, so an update is a single frame.
struct SystemTab: View {
    @Environment(SystemModule.self) private var system
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let sample = system.stats.sample
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                StatCard(
                    symbol: "cpu",
                    fraction: sample?.cpu,
                    value: sample.map { Self.percent($0.cpu) } ?? "—",
                    title: String(localized: "İşlemci"),
                    detail: sample.map { String(localized: "\($0.cores) çekirdek") }
                )
                StatCard(
                    symbol: "memorychip",
                    fraction: sample.map { Double($0.memoryUsed) / Double(max($0.memoryTotal, 1)) },
                    value: sample.map { Self.percent(Double($0.memoryUsed) / Double(max($0.memoryTotal, 1))) } ?? "—",
                    title: String(localized: "Bellek"),
                    detail: sample.map { "\(Self.bytes($0.memoryUsed, style: .memory)) / \(Self.bytes($0.memoryTotal, style: .memory))" }
                )
                StatCard(
                    symbol: "internaldrive",
                    fraction: sample.flatMap { $0.diskTotal > 0 ? 1 - Double($0.diskFree) / Double($0.diskTotal) : nil },
                    value: sample.flatMap { $0.diskTotal > 0 ? Self.percent(1 - Double($0.diskFree) / Double($0.diskTotal)) : nil } ?? "—",
                    title: String(localized: "Disk"),
                    detail: sample.map { String(localized: "\(Self.bytes(UInt64(max($0.diskFree, 0)), style: .file)) boş") }
                )
                NetworkCard(link: system.network, sample: sample)
            }
            ProcessList(processes: sample?.top ?? [])
                .frame(width: settings.homeStyle == .dashboard ? 220 : 230)
        }
        .task { await system.stats.run() }
    }

    static func percent(_ fraction: Double) -> String {
        min(max(fraction, 0), 9.99).formatted(.percent.precision(.fractionLength(0)))
    }

    static func bytes(_ count: UInt64, style: ByteCountFormatStyle.Style) -> String {
        Int64(clamping: count).formatted(.byteCount(style: style))
    }

    /// "1,2 MB/sn".
    static func rate(_ bytesPerSecond: Double) -> String {
        String(localized: "\(Int64(bytesPerSecond.rounded()).formatted(.byteCount(style: .file)))/sn")
    }
}

/// A gauge that fills as use grows: green, orange from 60 %, red from 85 %.
private struct StatCard: View {
    let symbol: String
    let fraction: Double?
    let value: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4.5)
                Circle()
                    .trim(from: 0, to: min(max(fraction ?? 0, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .frame(width: 52, height: 52)
            Text(verbatim: value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandTile()
    }

    private var tint: Color {
        switch fraction ?? 0 {
        case 0.85...: .red
        case 0.6...: .orange
        default: .green
        }
    }
}

/// How the Mac is online, and the traffic over Ethernet and Wi-Fi.
private struct NetworkCard: View {
    let link: NetworkLink
    let sample: SystemStats.Sample?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(tint)
            }
            .frame(width: 52, height: 52)
            Text(name)
                .font(.system(size: 14, weight: .semibold))
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                    Text(verbatim: SystemTab.rate(sample?.download ?? 0))
                }
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Text(verbatim: SystemTab.rate(sample?.upload ?? 0))
                }
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.5))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandTile()
        .help(link == .wired ? String(localized: "İnternete kabloyla (Ethernet) bağlı") : "")
    }

    private var symbol: String {
        switch link {
        case .wired: "cable.connector.horizontal"
        case .wifi: "wifi"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .other: "network"
        case .offline: "wifi.slash"
        }
    }

    private var name: String {
        switch link {
        case .wired: "LAN"
        case .wifi: "Wi-Fi"
        case .cellular: String(localized: "Hücresel")
        case .other: String(localized: "Ağ")
        case .offline: String(localized: "Çevrimdışı")
        }
    }

    private var tint: Color {
        switch link {
        case .wired: .green
        case .offline: .red
        default: .white
        }
    }
}

/// The user's processes using the most CPU, with their memory.
private struct ProcessList: View {
    let processes: [SystemStats.Process]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("En çok işlemci kullananlar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Etkinlik Monitörü'nü aç")
            }
            if processes.isEmpty {
                Text("Ölçülüyor…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            ForEach(processes) { process in
                HStack(spacing: 6) {
                    Text(process.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: String(localized: "%\(Int(process.cpu.rounded()))"))
                        .foregroundStyle(process.cpu >= 50 ? Color.orange : Color.white.opacity(0.85))
                        .frame(width: 38, alignment: .trailing)
                    Text(verbatim: SystemTab.bytes(process.memory, style: .memory))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 58, alignment: .trailing)
                }
                .font(.system(size: 10.5).monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .islandTile()
    }
}
