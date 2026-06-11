import Foundation

struct WeatherReading: Sendable {
    let weather: WeatherInfo?
    let pressure: PressureInfo?

    static let empty = WeatherReading(weather: nil, pressure: nil)
}

/// OpenWeatherMap current-weather fetch + parse, ported from the RN
/// `captureWeather`. Pressure comes from the same response (`main.pressure`),
/// matching the shipped RN behavior. The API key lives in UserDefaults under the
/// key Settings' `@AppStorage` writes ("weatherAPIKey"); the RN-era
/// "openweathermap_api_key" slot is read as a legacy fallback. The `parse` step
/// is pure + unit-tested; the network call is device/network-owed.
enum WeatherClient {
    /// Must match SettingsView's `@AppStorage("weatherAPIKey")` — Settings is the
    /// only writer of the key.
    static let apiKeyDefaultsKey = "weatherAPIKey"
    static let legacyAPIKeyDefaultsKey = "openweathermap_api_key"

    static var apiKey: String? {
        let raw = UserDefaults.standard.string(forKey: apiKeyDefaultsKey)
            ?? UserDefaults.standard.string(forKey: legacyAPIKeyDefaultsKey)
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespaces)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: apiKeyDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
            UserDefaults.standard.removeObject(forKey: legacyAPIKeyDefaultsKey)
        }
    }

    static func fetch(latitude: Double, longitude: Double, session: URLSession = .shared) async -> WeatherReading {
        guard let key = apiKey,
              let url = URL(string: "https://api.openweathermap.org/data/2.5/weather?lat=\(latitude)&lon=\(longitude)&units=metric&appid=\(key)") else {
            return .empty
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .empty
            }
            return parse(data)
        } catch {
            return .empty
        }
    }

    /// Parse an OpenWeatherMap `/weather` response into our metadata shapes.
    static func parse(_ data: Data) -> WeatherReading {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty
        }
        let main = obj["main"] as? [String: Any]
        let conditions = (obj["weather"] as? [[String: Any]])?.first?["main"] as? String ?? "Unknown"
        let temperature = (main?["temp"] as? Double).map { Int($0.rounded()) } ?? 0
        let weather = WeatherInfo(conditions: conditions, temperature: temperature, temperatureUnit: "C")

        let hPa = (main?["pressure"] as? Int) ?? (main?["pressure"] as? Double).map(Int.init)
        let pressure = hPa.map { PressureInfo(hPa: $0, trend: .steady) }

        return WeatherReading(weather: weather, pressure: pressure)
    }
}
