import SwiftUI

struct WeatherPanel: View {
    @Environment(AppSettings.self) private var settings
    private var store: WeatherStore { .shared }

    var body: some View {
        let forecast = store.forecast
        Panel(module: .weather, headline: forecast.map { temp($0.temperature) } ?? "—") {
            if let location = settings.weatherLocation {
                if let forecast {
                    current(forecast, location: location)
                    hourly(forecast)
                    daily(forecast)
                } else if let error = store.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                }
                footer
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick a city to see the weather.").font(.callout)
                    Button("Choose City…") { (NSApp.delegate as? AppDelegate)?.showSettings() }
                }
            }
        }
        .onAppear { store.refresh() }
    }

    private func temp(_ value: Double) -> String { String(format: "%.0f°", value) }

    private func current(_ f: WeatherForecast, location: WeatherLocation) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: WeatherCode.symbol(f.code, isDay: f.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name).font(.headline)
                Text(WeatherCode.describe(f.code)).font(.callout)
                Text("Feels like \(temp(f.feelsLike)) · Humidity \(f.humidity)% · Wind \(Int(f.windSpeed.rounded())) \(f.windUnit)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func hourly(_ f: WeatherForecast) -> some View {
        let hourFormat = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: f.timeZone)
        return HStack(spacing: 0) {
            ForEach(Array(f.hours.prefix(12).enumerated()).filter { $0.offset % 2 == 0 }.map(\.element)) { hour in
                VStack(spacing: 4) {
                    Text(hour.time.formatted(hourFormat)).font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: WeatherCode.symbol(hour.code)).symbolRenderingMode(.multicolor)
                    Text(temp(hour.temperature)).font(.caption.monospacedDigit())
                    Text(hour.precipitationChance.map { $0 >= 20 ? "\($0)%" : " " } ?? " ")
                        .font(.caption2).foregroundStyle(.cyan)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }

    private func daily(_ f: WeatherForecast) -> some View {
        let low = f.days.map(\.low).min() ?? 0
        let high = f.days.map(\.high).max() ?? 1
        var dayCalendar = Calendar.current
        dayCalendar.timeZone = f.timeZone
        return VStack(spacing: 5) {
            ForEach(f.days) { day in
                HStack(spacing: 8) {
                    Text(dayCalendar.isDateInToday(day.date) ? "Today"
                         : day.date.formatted(Date.FormatStyle(timeZone: f.timeZone).weekday(.abbreviated)))
                        .frame(width: 44, alignment: .leading)
                    Image(systemName: WeatherCode.symbol(day.code)).symbolRenderingMode(.multicolor).frame(width: 22)
                    Text(day.precipitationChance.map { $0 >= 20 ? "\($0)%" : "" } ?? "")
                        .font(.caption2).foregroundStyle(.cyan).frame(width: 30, alignment: .leading)
                    Text(temp(day.low)).monospacedDigit().foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                    RangeBar(low: day.low, high: day.high, overallLow: low, overallHigh: high)
                    Text(temp(day.high)).monospacedDigit().frame(width: 32, alignment: .trailing)
                }
                .font(.callout)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
            }
            Spacer()
            Link("Weather data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com/")!)
        }
        .font(.caption2).foregroundStyle(.tertiary)
    }
}

/// A day's low-to-high span drawn against the whole week's range.
struct RangeBar: View {
    let low: Double, high: Double, overallLow: Double, overallHigh: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(overallHigh - overallLow, 1)
            let start = (low - overallLow) / span, end = (high - overallLow) / span
            Capsule().fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * CGFloat(end - start)))
                        .offset(x: geo.size.width * CGFloat(start))
                }
        }
        .frame(height: 5)
    }
}
