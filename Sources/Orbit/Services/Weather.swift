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

    /// Sample weather in demo mode (screenshots), which makes no network calls.
    @Published private(set) var now: Now? = Snapshot.isDemo
        ? Now(place: "Cairo", temperature: 27, feelsLike: 28, high: 31, low: 19, code: 1, isDay: true, fetchedAt: .distantFuture) : nil
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

    /// Hour-by-hour forecast for today and tomorrow, as text for the assistant (what to wear, umbrella, sunscreen…).
    func forecastText(latitude: Double, longitude: Double, place: String) async -> String? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(latitude)), .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m"),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,precipitation_probability,weather_code,wind_speed_10m,uv_index"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,sunrise,sunset"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "2"),
            .init(name: "temperature_unit", value: unit),
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: comps.url!),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func nums(_ d: [String: Any]?, _ k: String) -> [Double] { (d?[k] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 } }
        let u = unit == "fahrenheit" ? "°F" : "°C"
        var lines = ["Weather for \(place):"]
        if let c = json["current"] as? [String: Any] {
            func v(_ k: String) -> Double { (c[k] as? NSNumber)?.doubleValue ?? 0 }
            lines.append("Now: \(Int(v("temperature_2m").rounded()))\(u), feels like \(Int(v("apparent_temperature").rounded()))\(u), \(Self.describe(c["weather_code"] as? Int ?? 0, isDay: true).label.lowercased()), wind \(Int(v("wind_speed_10m").rounded())) km/h, humidity \(Int(v("relative_humidity_2m")))%")
        }
        let daily = json["daily"] as? [String: Any]
        let days = (daily?["time"] as? [String]) ?? []
        for (i, day) in days.enumerated() {
            let hi = nums(daily, "temperature_2m_max"), lo = nums(daily, "temperature_2m_min"), rain = nums(daily, "precipitation_probability_max"), uv = nums(daily, "uv_index_max")
            let sunset = ((daily?["sunset"] as? [String]) ?? []).indices.contains(i) ? String(((daily?["sunset"] as? [String]) ?? [])[i].suffix(5)) : ""
            lines.append("\(i == 0 ? "Today" : "Tomorrow") (\(day)): \(Int(lo[safe: i] ?? 0))-\(Int(hi[safe: i] ?? 0))\(u), rain chance up to \(Int(rain[safe: i] ?? 0))%, UV max \(Int(uv[safe: i] ?? 0))\(sunset.isEmpty ? "" : ", sunset \(sunset)")")
        }
        let hourly = json["hourly"] as? [String: Any]
        let times = (hourly?["time"] as? [String]) ?? []
        let t = nums(hourly, "temperature_2m"), feels = nums(hourly, "apparent_temperature"), rain = nums(hourly, "precipitation_probability"),
            wind = nums(hourly, "wind_speed_10m"), uv = nums(hourly, "uv_index")
        let codes = (hourly?["weather_code"] as? [Int]) ?? []
        let nowHour = DateFormatter.localHour.string(from: .now)
        lines.append("Every 3 hours from now:")
        for (i, time) in times.enumerated() where time >= nowHour && i % 3 == 0 {
            lines.append("- \(time.replacingOccurrences(of: "T", with: " ")): \(Int(t[safe: i] ?? 0))\(u) (feels \(Int(feels[safe: i] ?? 0))), \(Self.describe(codes[safe: i] ?? 0, isDay: true).label.lowercased()), rain \(Int(rain[safe: i] ?? 0))%, wind \(Int(wind[safe: i] ?? 0)) km/h, UV \(Int(uv[safe: i] ?? 0))")
        }
        return lines.joined(separator: "\n")
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

/// Compact weather for the iPhone's Today: icon and temperature, with today's high and low. Tap for how it feels.
struct WeatherChip: View {
    @ObservedObject private var weather = WeatherStore.shared
    @State private var detail = false

    var body: some View {
        Group {
            if let w = weather.now {
                let d = WeatherStore.describe(w.code, isDay: w.isDay)
                Button { withAnimation(.snappy) { detail.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: d.symbol).symbolRenderingMode(.multicolor).font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(Int(w.temperature.rounded()))° \(detail ? d.label : "")").font(Theme.ui(15, weight: .semibold)).lineLimit(1)
                            Text(detail ? "Feels \(Int(w.feelsLike.rounded()))° · \(w.place)" : "H \(Int(w.high.rounded()))°  L \(Int(w.low.rounded()))°")
                                .font(Theme.ui(10)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Int(w.temperature.rounded())) degrees, \(d.label), in \(w.place)")
            } else if weather.error != nil {
                Image(systemName: "cloud.sun").font(.system(size: 18)).foregroundStyle(Theme.inkMuted)
                    .onTapGesture { Task { await weather.refresh() } }
            }
        }
        .task {
            while !Task.isCancelled {
                await weather.refreshIfDue()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension DateFormatter {
    /// "2026-10-23T14:00", matching Open-Meteo's local hourly times.
    static let localHour: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH':00'"; return f
    }()
}
