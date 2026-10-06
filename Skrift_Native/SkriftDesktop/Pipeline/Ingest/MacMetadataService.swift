import Foundation

/// What the Mac can read about the moment a note is created: where it is (the shared
/// one-shot CoreLocation fix, `LocationOneShot`), the daypart and the daylight hours that
/// place implies, and — when an OpenWeatherMap key has reached this Mac (it syncs from the
/// phone, Q326 / D182) — the weather and pressure there. No steps (no pedometer on a Mac).
/// A refused or failed fix leaves the place nil and the weather out (the call needs
/// coordinates), silently, like the phone; with no key the weather is simply absent.
///
/// Every input is injectable so a test can stub the fix, the key and the network call.
@MainActor
struct MacMetadataService: MetadataProviding {
    var location: () async -> LocationInfo? = { await LocationOneShot().current() }
    /// The key from settings (blank/nil = none). Never logged.
    var weatherKey: () -> String? = { SettingsStore.shared.load().weatherKey }
    var fetchWeather: (_ latitude: Double, _ longitude: Double, _ key: String) async -> WeatherReading = { lat, lon, key in
        await WeatherClient.fetch(latitude: lat, longitude: lon, apiKey: key)
    }

    func capture() async -> MemoMetadata {
        let now = Date()
        let place = await location()
        var daylight: DaylightInfo?
        var reading = WeatherReading.empty
        if let place {
            daylight = SolarCalc.daylight(latitude: place.latitude, longitude: place.longitude, date: now)
            if let key = weatherKey()?.trimmingCharacters(in: .whitespaces), !key.isEmpty {
                reading = await fetchWeather(place.latitude, place.longitude, key)
            }
        }
        return MemoMetadata(capturedAt: ISO8601.string(from: now),
                            location: place,
                            weather: reading.weather,
                            pressure: reading.pressure,
                            dayPeriod: DayPeriod.from(now),
                            daylight: daylight,
                            tags: [])
    }
}
