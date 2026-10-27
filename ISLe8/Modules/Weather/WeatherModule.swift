import Foundation
import SwiftUI

/// A place weather can be shown for.
struct WeatherPlace: Equatable, Identifiable {
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(latitude),\(longitude)" }
}

struct WeatherReport: Equatable {
    struct Hour: Equatable, Identifiable {
        /// "19:00", as Open-Meteo gives it in the place's own time.
        let label: String
        let temperature: Double
        let code: Int
        let isDay: Bool
        var id: String { label }
    }

    struct Day: Equatable, Identifiable {
        let date: Date
        let code: Int
        let high: Double
        let low: Double
        let rainChance: Int?
        var id: Date { date }
    }

    var temperature: Double
    var code: Int
    var isDay: Bool
    var high: Double
    var low: Double
    /// Today's weather as a whole, for the forecast row; `code` is the sky right now.
    var todayCode: Int
    var todayRainChance: Int?
    var place: String
    var fetchedAt: Date
    var feelsLike: Double
    var humidity: Int
    /// km/h, or mph with Fahrenheit.
    var windSpeed: Double
    /// Where the wind comes from, in degrees.
    var windDirection: Double
    var uvIndex: Double
    /// The next five hours after the current one.
    var hours: [Hour]
    /// The next nine days after today.
    var days: [Day]
}

/// Current weather from Open-Meteo: free, no API key, no account. Without a chosen city the
/// one in the Mac's time zone is used, so no location permission is ever needed. Nothing
/// runs in the background: the report refreshes when Home is shown and is older than 30 min.
@Observable
final class WeatherModule: IslandModule {
    let id = "weather"
    var activity: LiveActivity? { nil }
    private(set) var report: WeatherReport?
    private(set) var isLoading = false
    private(set) var failed = false

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The setting the current report was fetched for; a different one means fetch again.
    @ObservationIgnored private var reportSource = ""

    private static let maxAge: TimeInterval = 30 * 60

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        refreshIfStale()
    }

    func stop() {
        task?.cancel()
    }

    func refreshIfStale() {
        guard !isLoading else { return }
        if let report, Date().timeIntervalSince(report.fetchedAt) < Self.maxAge, reportSource == placeName { return }
        refresh()
    }

    func refresh() {
        task?.cancel()
        isLoading = true
        let source = placeName
        task = Task {
            defer { self.isLoading = false }
            do {
                let place = try await self.resolvePlace()
                let report = try await Self.fetch(place, unit: self.settings.weatherUnit)
                guard !Task.isCancelled else { return }
                self.report = report
                self.reportSource = source
                self.failed = false
            } catch {
                guard !Task.isCancelled else { return }
                self.failed = true
            }
        }
    }

    func choose(_ place: WeatherPlace) {
        settings.weatherCity = place.name
        settings.weatherLatitude = place.latitude
        settings.weatherLongitude = place.longitude
        refresh()
    }

    /// Up to five matching places, named in Turkish where Open-Meteo knows the name.
    func search(_ query: String) async -> [WeatherPlace] {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        return (try? await Self.geocode(query, count: 5)) ?? []
    }

    private var placeName: String {
        settings.weatherCity.isEmpty ? Self.timeZoneCity : settings.weatherCity
    }

    private func resolvePlace() async throws -> WeatherPlace {
        if !settings.weatherCity.isEmpty, settings.weatherLatitude != 0 || settings.weatherLongitude != 0 {
            return WeatherPlace(
                name: settings.weatherCity,
                detail: "",
                latitude: settings.weatherLatitude,
                longitude: settings.weatherLongitude
            )
        }
        guard let place = try await Self.geocode(Self.timeZoneCity, count: 1).first else {
            throw URLError(.cannotFindHost)
        }
        return place
    }

    /// "Europe/Istanbul" → "Istanbul".
    private static var timeZoneCity: String {
        let city = TimeZone.current.identifier.split(separator: "/").last.map(String.init) ?? "Istanbul"
        return city.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: Open-Meteo

    nonisolated private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double?
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double?
            let wind_direction_10m: Double?
            let uv_index: Double?
            let weather_code: Int
            let is_day: Int
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]?
        }
        let current: Current
        let hourly: Hourly?
        let daily: Daily
    }

    nonisolated private struct GeocodingResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Result]?
    }

    private static func fetch(_ place: WeatherPlace, unit: SettingsStore.TemperatureUnit) async throws -> WeatherReport {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            // Two decimals (about a kilometre) is plenty for weather.
            URLQueryItem(name: "latitude", value: String(format: "%.2f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m,uv_index,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "forecast_hours", value: "6"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "10"),
            URLQueryItem(name: "wind_speed_unit", value: unit == .fahrenheit ? "mph" : "kmh"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: unit == .fahrenheit ? "fahrenheit" : "celsius"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let current = response.current
        // The hourly list starts at the current hour; the island shows the five after it.
        var hours: [WeatherReport.Hour] = []
        if let hourly = response.hourly {
            for index in hourly.time.indices.dropFirst() where index < hourly.temperature_2m.count {
                hours.append(WeatherReport.Hour(
                    label: String(hourly.time[index].suffix(5)),
                    temperature: hourly.temperature_2m[index],
                    code: hourly.weather_code[index],
                    isDay: hourly.is_day[index] == 1
                ))
            }
        }
        let dayFormat = DateFormatter()
        dayFormat.dateFormat = "yyyy-MM-dd"
        let daily = response.daily
        let days: [WeatherReport.Day] = daily.time.indices.dropFirst().compactMap { index in
            guard let date = dayFormat.date(from: daily.time[index]), index < daily.temperature_2m_max.count else { return nil }
            return WeatherReport.Day(
                date: date,
                code: daily.weather_code[index],
                high: daily.temperature_2m_max[index],
                low: daily.temperature_2m_min[index],
                rainChance: daily.precipitation_probability_max?[index]
            )
        }
        return WeatherReport(
            temperature: current.temperature_2m,
            code: current.weather_code,
            isDay: current.is_day == 1,
            high: daily.temperature_2m_max.first ?? current.temperature_2m,
            low: daily.temperature_2m_min.first ?? current.temperature_2m,
            todayCode: daily.weather_code.first ?? current.weather_code,
            todayRainChance: daily.precipitation_probability_max?.first ?? nil,
            place: place.name,
            fetchedAt: Date(),
            feelsLike: current.apparent_temperature ?? current.temperature_2m,
            humidity: Int((current.relative_humidity_2m ?? 0).rounded()),
            windSpeed: current.wind_speed_10m ?? 0,
            windDirection: current.wind_direction_10m ?? 0,
            uvIndex: current.uv_index ?? 0,
            hours: hours,
            days: days
        )
    }

    private static func geocode(_ name: String, count: Int) async throws -> [WeatherPlace] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "language", value: "tr"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (response.results ?? []).map { result in
            WeatherPlace(
                name: result.name,
                detail: [result.admin1, result.country].compactMap { $0 }.joined(separator: ", "),
                latitude: result.latitude,
                longitude: result.longitude
            )
        }
    }
}

/// WMO weather codes, as Open-Meteo reports them, to a symbol and a Turkish description.
enum WindDirection {
    /// The eight compass points: "KD" for a north-easterly in Turkish, "NE" in English.
    static func abbreviation(_ degrees: Double) -> String {
        let points = [
            String(localized: "K"), String(localized: "KD"), String(localized: "D"), String(localized: "GD"),
            String(localized: "G"), String(localized: "GB"), String(localized: "B"), String(localized: "KB"),
        ]
        let index = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return points[index]
    }
}

enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: isDay ? "sun.max.fill" : "moon.fill"
        case 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65, 80, 81, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: String(localized: "Açık")
        case 1: String(localized: "Çoğunlukla açık")
        case 2: String(localized: "Parçalı bulutlu")
        case 3: String(localized: "Çok bulutlu")
        case 45, 48: String(localized: "Sisli")
        case 51, 53, 55: String(localized: "Çiseliyor")
        case 56, 57: String(localized: "Donan çisenti")
        case 61, 63: String(localized: "Yağmurlu")
        case 65: String(localized: "Şiddetli yağmur")
        case 66, 67: String(localized: "Donan yağmur")
        case 71, 73, 75, 77: String(localized: "Karlı")
        case 80, 81, 82: String(localized: "Sağanak")
        case 85, 86: String(localized: "Kar sağanağı")
        case 95: String(localized: "Gök gürültülü")
        case 96, 99: String(localized: "Dolulu fırtına")
        default: "—"
        }
    }
}
