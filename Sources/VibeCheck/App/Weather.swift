import Foundation
import Observation

struct WeatherLocation: Codable, Equatable, Identifiable {
    var id: String { "\(latitude),\(longitude)" }
    let name: String
    let region: String?
    let country: String?
    let latitude: Double
    let longitude: Double

    var subtitle: String { [region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var title: String { self == .celsius ? String(localized: "Celsius (°C)") : String(localized: "Fahrenheit (°F)") }
}

struct WeatherForecast {
    struct Hour: Identifiable {
        var id: Date { time }
        let time: Date
        let temperature: Double
        let code: Int
        let precipitationChance: Int?
    }

    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let code: Int
        let high: Double
        let low: Double
        let precipitationChance: Int?
    }

    let temperature: Double
    let feelsLike: Double
    let humidity: Int
    let windSpeed: Double
    let windUnit: String
    let code: Int
    let isDay: Bool
    let hours: [Hour]
    let days: [Day]
    let timeZone: TimeZone
}

/// WMO weather interpretation codes, as used by Open-Meteo.
enum WeatherCode {
    static func describe(_ code: Int) -> String {
        switch code {
        case 0: String(localized: "Clear")
        case 1: String(localized: "Mostly clear")
        case 2: String(localized: "Partly cloudy")
        case 3: String(localized: "Overcast")
        case 45, 48: String(localized: "Fog")
        case 51, 53, 55: String(localized: "Drizzle")
        case 56, 57: String(localized: "Freezing drizzle")
        case 61, 63: String(localized: "Rain")
        case 65: String(localized: "Heavy rain")
        case 66, 67: String(localized: "Freezing rain")
        case 71, 73: String(localized: "Snow")
        case 75: String(localized: "Heavy snow")
        case 77: String(localized: "Snow grains")
        case 80, 81: String(localized: "Showers")
        case 82: String(localized: "Heavy showers")
        case 85, 86: String(localized: "Snow showers")
        case 95: String(localized: "Thunderstorm")
        case 96, 99: String(localized: "Thunderstorm with hail")
        default: String(localized: "Unknown")
        }
    }

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66, 67, 80, 81: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

/// Fetches forecasts from Open-Meteo (free, no API key). Only the chosen city's coordinates are sent.
enum OpenMeteo {
    static func search(_ query: String) async throws -> [WeatherLocation] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "8"),
                                 URLQueryItem(name: "format", value: "json")]
        struct Response: Decodable {
            struct Result: Decodable {
                let name: String
                let admin1: String?
                let country: String?
                let latitude: Double
                let longitude: Double
            }
            let results: [Result]?
        }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return (try JSONDecoder().decode(Response.self, from: data).results ?? []).map {
            WeatherLocation(name: $0.name, region: $0.admin1, country: $0.country,
                            latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    static func forecast(for location: WeatherLocation, unit: TemperatureUnit) async throws -> WeatherForecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", location.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
            URLQueryItem(name: "wind_speed_unit", value: unit == .fahrenheit ? "mph" : "kmh"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> WeatherForecast {
        struct Response: Decodable {
            struct Current: Decodable {
                let time: String
                let temperature_2m: Double
                let apparent_temperature: Double
                let relative_humidity_2m: Int
                let weather_code: Int
                let wind_speed_10m: Double
                let is_day: Int
            }
            struct Units: Decodable { let wind_speed_10m: String }
            struct Hourly: Decodable {
                let time: [String]
                let temperature_2m: [Double?]
                let weather_code: [Int?]
                let precipitation_probability: [Int?]?
            }
            struct Daily: Decodable {
                let time: [String]
                let weather_code: [Int?]
                let temperature_2m_max: [Double?]
                let temperature_2m_min: [Double?]
                let precipitation_probability_max: [Int?]?
            }
            let utc_offset_seconds: Int
            let current: Current
            let current_units: Units
            let hourly: Hourly
            let daily: Daily
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let zone = TimeZone(secondsFromGMT: r.utc_offset_seconds) ?? .gmt

        let hourFormat = DateFormatter()
        hourFormat.locale = Locale(identifier: "en_US_POSIX")
        hourFormat.timeZone = zone
        hourFormat.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.timeZone = zone
        dayFormat.dateFormat = "yyyy-MM-dd"

        let now = hourFormat.date(from: r.current.time) ?? Date()
        let hours: [WeatherForecast.Hour] = r.hourly.time.indices.compactMap { i in
            guard let time = hourFormat.date(from: r.hourly.time[i]),
                  time >= now.addingTimeInterval(-3600),
                  let temp = r.hourly.temperature_2m[i], let code = r.hourly.weather_code[i] else { return nil }
            return .init(time: time, temperature: temp, code: code, precipitationChance: r.hourly.precipitation_probability?[i])
        }
        let days: [WeatherForecast.Day] = r.daily.time.indices.compactMap { i in
            guard let date = dayFormat.date(from: r.daily.time[i]), let code = r.daily.weather_code[i],
                  let high = r.daily.temperature_2m_max[i], let low = r.daily.temperature_2m_min[i] else { return nil }
            return .init(date: date, code: code, high: high, low: low,
                         precipitationChance: r.daily.precipitation_probability_max?[i])
        }
        return WeatherForecast(temperature: r.current.temperature_2m, feelsLike: r.current.apparent_temperature,
                               humidity: r.current.relative_humidity_2m, windSpeed: r.current.wind_speed_10m,
                               windUnit: r.current_units.wind_speed_10m, code: r.current.weather_code,
                               isDay: r.current.is_day == 1, hours: Array(hours.prefix(24)), days: days, timeZone: zone)
    }
}

/// Holds the latest forecast; refreshes every 30 minutes while the Weather item is on and a city is set.
@Observable
@MainActor
final class WeatherStore {
    static let shared = WeatherStore()

    private(set) var forecast: WeatherForecast?
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var loadedKey: String?

    private init() {
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { WeatherStore.shared.refresh(force: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Fetches if the item is on and the city/unit changed (or `force`). Cheap to call often.
    func refresh(force: Bool = false) {
        let settings = AppSettings.shared
        guard settings.isEnabled(.weather), let location = settings.weatherLocation else {
            if settings.weatherLocation == nil { forecast = nil; loadedKey = nil }
            return
        }
        let key = "\(location.id)|\(settings.temperatureUnit.rawValue)"
        guard force || key != loadedKey, !isLoading else { return }
        isLoading = true
        Task {
            do {
                let result = try await OpenMeteo.forecast(for: location, unit: settings.temperatureUnit)
                forecast = result
                lastUpdated = Date()
                errorMessage = nil
                loadedKey = key
            } catch {
                errorMessage = String(localized: "Couldn't load weather. Check your connection.")
            }
            isLoading = false
        }
    }
}
