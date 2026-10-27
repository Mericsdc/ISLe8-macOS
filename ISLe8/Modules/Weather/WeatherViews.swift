import SwiftUI

/// Home's weather column. Dashboard: now in detail (feels like, humidity, wind, UV), the next
/// five hours and the next five days. Compact: now, beside five days at a time (an arrow
/// shows the next five); a tap on a day puts its details in a line underneath. Minimal: the
/// place, now, and today's high and low.
struct WeatherColumn: View {
    @Environment(WeatherModule.self) private var weather
    @Environment(SettingsStore.self) private var settings
    @State private var forecastPage = 0
    @State private var pickedDay: Date?

    var body: some View {
        Group {
            if let report = weather.report {
                switch settings.homeStyle {
                case .dashboard: content(report)
                case .compact: compact(report)
                case .minimal: minimal(report)
                }
            } else if weather.failed {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Text("Hava durumu alınamadı")
                        .font(.system(size: 12, weight: .semibold))
                    PillButton(title: "Tekrar dene", systemImage: "arrow.clockwise") { weather.refresh() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(settings.homeStyle == .dashboard ? 12 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.homeStyle == .dashboard ? .topLeading : .leading)
        .homeColumn(settings.homeStyle)
        .onAppear { weather.refreshIfStale() }
    }

    /// Minimal: the place over the icon and temperature, the sky and today's range beside.
    private func minimal(_ report: WeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            place(report, size: 12)
            HStack(spacing: 6) {
                Image(systemName: WeatherCode.symbol(report.code, isDay: report.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 20))
                Text(Self.degrees(report.temperature))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .fixedSize()
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(WeatherCode.description(report.code))
                    Text("Y \(Self.degrees(report.high))  D \(Self.degrees(report.low))")
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
            }
        }
    }

    /// Compact: now (temperature, place, sky), five days beside it, the picked day below.
    private func compact(_ report: WeatherReport) -> some View {
        let forecast = Self.forecast(report)
        let pages = max((forecast.count + 4) / 5, 1)
        let page = min(forecastPage, pages - 1)
        let picked = forecast.first { $0.date == pickedDay } ?? forecast.first
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: WeatherCode.symbol(report.code, isDay: report.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 24))
                        Text(Self.degrees(report.temperature))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                    }
                    place(report, size: 12)
                    Text(WeatherCode.description(report.code))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
                .layoutPriority(1)
                HStack(spacing: 0) {
                    ForEach(forecast.dropFirst(page * 5).prefix(5)) { day in
                        VStack(spacing: 4) {
                            Text(day.label)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Image(systemName: WeatherCode.symbol(day.code, isDay: true))
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 15))
                                .frame(height: 18)
                            Text(Self.degrees(day.high))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(day.date == picked?.date ? 0.1 : 0))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { pickedDay = day.date }
                    }
                    if pages > 1 {
                        let hasMore = page + 1 < pages
                        Button {
                            forecastPage = hasMore ? page + 1 : 0
                        } label: {
                            Image(systemName: hasMore ? "chevron.right" : "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .frame(width: 16, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(hasMore ? "Sonraki günler" : "İlk günler")
                    }
                }
            }
            if let picked {
                Text(Self.detail(picked))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    /// "Cmt 31 Eki · Sağanak · Y 18°  D 12° · Yağış %70".
    private static func detail(_ day: ForecastDay) -> String {
        let calendar = Calendar.current
        let name = calendar.isDateInToday(day.date) || calendar.isDateInTomorrow(day.date)
            ? day.label
            : day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        var parts = [name, WeatherCode.description(day.code), String(localized: "Y \(degrees(day.high))  D \(degrees(day.low))")]
        if let rain = day.rainChance {
            parts.append(String(localized: "Yağış %\(rain)"))
        }
        return parts.joined(separator: " · ")
    }

    private func place(_ report: WeatherReport, size: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(report.place)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "location.fill")
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private struct ForecastDay: Identifiable {
        let date: Date
        let label: String
        let code: Int
        let high: Double
        let low: Double
        let rainChance: Int?
        var id: Date { date }
    }

    /// Today, tomorrow, then the days after: ten in all, five to a page.
    private static func forecast(_ report: WeatherReport) -> [ForecastDay] {
        let today = ForecastDay(
            date: Calendar.current.startOfDay(for: .now), label: String(localized: "Bugün"),
            code: report.todayCode, high: report.high, low: report.low, rainChance: report.todayRainChance
        )
        let next = report.days.prefix(9).enumerated().map { index, day in
            ForecastDay(
                date: day.date,
                label: index == 0 ? String(localized: "Yarın") : day.date.formatted(.dateTime.weekday(.abbreviated)),
                code: day.code,
                high: day.high,
                low: day.low,
                rainChance: day.rainChance
            )
        }
        return [today] + next
    }

    private func content(_ report: WeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(report.place)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "location.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                Text(WeatherCode.description(report.code))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: WeatherCode.symbol(report.code, isDay: report.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 28))
                Text(Self.degrees(report.temperature))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Hissedilen \(Self.degrees(report.feelsLike))")
                    Text("Y \(Self.degrees(report.high))  D \(Self.degrees(report.low))")
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.6))
            }

            HStack(spacing: 0) {
                Detail(symbol: "drop", value: String(localized: "%\(report.humidity)"), caption: String(localized: "Nem"))
                Detail(symbol: "wind", value: windText(report.windSpeed), caption: String(localized: "Rüzgar"))
                Detail(symbol: "location.north.line", value: WindDirection.abbreviation(report.windDirection), caption: String(localized: "Yön"))
                Detail(symbol: "sun.max", value: "\(Int(report.uvIndex.rounded()))", caption: String(localized: "UV"))
            }
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.05)))

            HStack(spacing: 0) {
                Hour(label: String(localized: "Şimdi"), code: report.code, isDay: report.isDay, temperature: report.temperature)
                ForEach(report.hours.prefix(5)) { hour in
                    Hour(label: hour.label, code: hour.code, isDay: hour.isDay, temperature: hour.temperature)
                }
            }

            VStack(spacing: 3) {
                ForEach(Array(report.days.prefix(5).enumerated()), id: \.element.id) { index, day in
                    HStack(spacing: 6) {
                        Text(index == 0 ? String(localized: "Yarın") : day.date.formatted(.dateTime.weekday(.wide)))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: WeatherCode.symbol(day.code, isDay: true))
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 18)
                        Text(Self.degrees(day.high))
                            .frame(width: 28, alignment: .trailing)
                        Text(Self.degrees(day.low))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: 28, alignment: .trailing)
                        HStack(spacing: 2) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.cyan)
                            Text(day.rainChance.map { String(localized: "%\($0)") } ?? "—")
                        }
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 38, alignment: .trailing)
                    }
                    .font(.system(size: 10.5).monospacedDigit())
                }
            }
        }
    }

    private func windText(_ speed: Double) -> String {
        let value = Int(speed.rounded())
        return settings.weatherUnit == .fahrenheit ? String(localized: "\(value) mph") : String(localized: "\(value) km/sa")
    }

    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}

private struct Detail: View {
    let symbol: String
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Hour: View {
    let label: String
    let code: Int
    let isDay: Bool
    let temperature: Double

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.55))
            Image(systemName: WeatherCode.symbol(code, isDay: isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 13))
                .frame(height: 15)
            Text(WeatherColumn.degrees(temperature))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}
