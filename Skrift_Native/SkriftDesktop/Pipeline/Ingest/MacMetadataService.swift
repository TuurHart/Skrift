import Foundation

/// What the Mac can read about the moment a note is created: where it is (the shared
/// one-shot CoreLocation fix, `LocationOneShot`), the daypart and the daylight hours that
/// place implies. No steps (no pedometer on a Mac) and no weather yet — the phone's
/// `WeatherClient` and the key it needs have no Mac counterpart (D151, weather item pending).
/// A refused or failed fix leaves the place nil, silently, like the phone.
@MainActor
struct MacMetadataService: MetadataProviding {
    func capture() async -> MemoMetadata {
        let now = Date()
        let location = await LocationOneShot().current()
        var daylight: DaylightInfo?
        if let location {
            daylight = SolarCalc.daylight(latitude: location.latitude, longitude: location.longitude, date: now)
        }
        return MemoMetadata(capturedAt: ISO8601.string(from: now),
                            location: location,
                            dayPeriod: DayPeriod.from(now),
                            daylight: daylight,
                            tags: [])
    }
}
