import Foundation
import SwiftUI

/// Current weather from Open-Meteo (free, no key). The city defaults to your Mac's time zone (e.g. Africa/Cairo → Cairo)
/// and can be changed in Settings › General.
@MainActor
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    struct Now: Equatable {
        let place: String
        let temperature: Double
        let feelsLike: Double
        let high: Double
        let low: Double
        let code: Int
        let isDay: Bool
        let fetchedAt: Date
    }

    @Published private(set) var now: Now?
    @Published private(set) var error: String?
    @AppStorage("weatherCity") var city = ""

    static var defaultCity: String {
        TimeZone.current.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "London"
    }
    var effectiveCity: String { city.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultCity : city }
    var unit: String { Locale.current.measurementSystem == .us ? "fahrenheit" : "celsius" }

    private var coords: (city: String, lat: Double, lon: Double, name: String)?

    func refreshIfDue() async {
        if let now, Date.now.timeIntervalSince(now.fetchedAt) < 30 * 60, coords?.city == effectiveCity { return }
        await refresh()
    }

    func refresh() async {
        guard !Snapshot.isActive else { return }
        do {
            if coords?.city != effectiveCity {
                var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                comps.queryItems = [.init(name: "name", value: effectiveCity), .init(name: "count", value: "1")]
                let (data, _) = try await URLSession.shared.data(from: comps.url!)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let first = (json?["results"] as? [[String: Any]])?.first,
                      let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else {
                    error = "Couldn't find “\(effectiveCity)”. Set your city in Settings › General."
                    return
                }
                coords = (effectiveCity, lat, lon, first["name"] as? String ?? effectiveCity)
            }
            guard let c = coords else { return }
            var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            comps.queryItems = [
                .init(name: "latitude", value: String(c.lat)), .init(name: "longitude", value: String(c.lon)),
                .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
                .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "1"),
                .init(name: "temperature_unit", value: unit),
            ]
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let cur = json?["current"] as? [String: Any] ?? [:]
            let daily = json?["daily"] as? [String: Any] ?? [:]
            func d(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
            now = Now(place: c.name, temperature: d(cur["temperature_2m"]), feelsLike: d(cur["apparent_temperature"]),
                      high: d((daily["temperature_2m_max"] as? [Any])?.first), low: d((daily["temperature_2m_min"] as? [Any])?.first),
                      code: (cur["weather_code"] as? Int) ?? 0, isDay: (cur["is_day"] as? Int ?? 1) == 1, fetchedAt: .now)
            error = nil
        } catch {
            self.error = "Weather unavailable right now."
        }
    }

    /// SF Symbol and short label for a WMO weather code.
    static func describe(_ code: Int, isDay: Bool) -> (symbol: String, label: String) {
        switch code {
        case 0: (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1, 2: (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly cloudy")
        case 3: ("cloud.fill", "Cloudy")
        case 45, 48: ("cloud.fog.fill", "Foggy")
        case 51...57: ("cloud.drizzle.fill", "Drizzle")
        case 61...67: ("cloud.rain.fill", "Rain")
        case 71...77, 85, 86: ("cloud.snow.fill", "Snow")
        case 80...82: ("cloud.heavyrain.fill", "Showers")
        case 95...99: ("cloud.bolt.rain.fill", "Thunderstorm")
        default: ("cloud.fill", "—")
        }
    }
}

/// Live clock and weather for the Today header.
struct ClockWeather: View {
    @ObservedObject private var weather = WeatherStore.shared

    var body: some View {
        HStack(spacing: 14) {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 0) {
                    Text(ctx.date.formatted(date: .omitted, time: .shortened)).font(Theme.display(26)).monospacedDigit()
                    Text(TimeZone.current.localizedName(for: .shortGeneric, locale: .current) ?? "")
                        .font(Theme.ui(10)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
            }
            Rectangle().fill(Theme.line).frame(width: 1, height: 34)
            if let w = weather.now {
                let d = WeatherStore.describe(w.code, isDay: w.isDay)
                HStack(spacing: 10) {
                    Image(systemName: d.symbol).symbolRenderingMode(.multicolor).font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(w.temperature.rounded()))° \(d.label)").font(Theme.ui(14, weight: .semibold)).lineLimit(1)
                        Text("H \(Int(w.high.rounded()))°  L \(Int(w.low.rounded()))° · \(w.place)")
                            .font(Theme.ui(10)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    }
                }
                .help("Feels like \(Int(w.feelsLike.rounded()))°. Change the city in Settings › General.")
            } else {
                Label(weather.error ?? "Loading weather…", systemImage: "cloud.sun")
                    .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).lineLimit(2).frame(maxWidth: 160)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(Theme.card))
        .task {
            while !Task.isCancelled {
                await weather.refreshIfDue()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }
}
