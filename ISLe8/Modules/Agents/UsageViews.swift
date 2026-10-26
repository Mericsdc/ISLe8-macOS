import SwiftUI

/// Claude, Codex and Gemini limits under the AI tab's cards: a ring per vendor for the window
/// that runs out first, with the weekly one beside it.
struct UsageStrip: View {
    @Environment(UsageModule.self) private var usage

    var body: some View {
        if usage.isEnabled, !usage.snapshots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Limitler")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Spacer()
                    if let measured = usage.snapshots.compactMap(\.measuredAt).max() {
                        TimelineView(.everyMinute) { _ in
                            Text(measured, format: .relative(presentation: .named))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                    }
                    if usage.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 18, height: 18)
                    } else {
                        Button {
                            usage.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help("Yenile")
                        .accessibilityLabel("Yenile")
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(usage.snapshots) { snapshot in
                        VendorUsage(snapshot: snapshot)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .islandTile()
        }
    }
}

private struct VendorUsage: View {
    let snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 8) {
            UsageRing(vendor: snapshot.vendor, used: current(snapshot.bar), size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.vendor.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                switch snapshot.state {
                case .ok:
                    ForEach(snapshot.windows.prefix(2)) { window in
                        Text(verbatim: "\(window.label) \(percent(current(window)))")
                            .foregroundStyle(window.isHot ? Color.orange : Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    if let reset = snapshot.bar?.resetsAt, !(snapshot.bar?.resetPassed ?? true) {
                        Text("Sıfırlanma \(UsageFetch.relativeDay(reset))")
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }
                case .signedOut:
                    Text("Giriş yapılmamış")
                        .foregroundStyle(Color.orange)
                        .help(snapshot.vendor.loginHint)
                case .missing, .untrusted, .failed:
                    Text(snapshot.error ?? String(localized: "Okunamadı"))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(2)
                }
            }
            .font(.system(size: 10))
        }
        .help(snapshot.plan.isEmpty ? snapshot.vendor.product : "\(snapshot.vendor.product) · \(snapshot.plan)")
    }

    /// A window whose reset time has passed no longer counts.
    private func current(_ window: UsageWindow?) -> Double? {
        guard let window, !window.resetPassed else { return nil }
        return window.used
    }
}

/// How much of a limit is used, as a ring around the vendor's mark. Orange from 70 %, red from 90 %.
struct UsageRing: View {
    let vendor: UsageVendor
    let used: Double?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 3)
            Circle()
                .trim(from: 0, to: (used ?? 0) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let mark = vendor.markImage {
                Image(nsImage: mark)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.3), value: used)
    }

    private var tint: AnyShapeStyle {
        switch used ?? 0 {
        case 90...: AnyShapeStyle(Color.red)
        case 70..<90: AnyShapeStyle(Color.orange)
        default: AnyShapeStyle(.tint)
        }
    }
}

/// The banner when a limit crosses 90 %.
struct UsageAlertView: View {
    let snapshot: UsageSnapshot
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 10) {
            UsageRing(vendor: snapshot.vendor, used: window.used, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(snapshot.vendor.displayName) · \(window.label) \(percent(window.used))")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Group {
                    if let reset = window.resetsAt {
                        Text("Limit dolmak üzere · sıfırlanma \(UsageFetch.relativeDay(reset))")
                    } else {
                        Text("Limit dolmak üzere")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// "%14" in Turkish, "14%" in English.
private func percent(_ value: Double?) -> String {
    guard value != nil else { return "—" }
    return String(localized: "%\(UsageWindow.percentText(value))")
}
