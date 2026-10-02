import CoreLocation
import CoreMotion
import Foundation

/// Captures contextual metadata when a recording stops. `@MainActor` so the
/// CoreLocation manager gets a run loop for its delegate callbacks.
/// Real capture: CoreLocation (+reverse-geocode), CMPedometer steps, SolarCalc
/// daylight, day period, and OpenWeatherMap weather+pressure. Mirrors the RN
/// `captureMetadata`. All fields are optional/non-blocking — any failure or
/// denied permission yields nil for that field. Sensors + network are device-owed.
@MainActor
struct MetadataService: MetadataProviding {
    func capture() async -> MemoMetadata {
        let now = Date()
        let location = await LocationOneShot().current()
        let steps = await Self.captureSteps()

        var daylight: DaylightInfo?
        var weather: WeatherInfo?
        var pressure: PressureInfo?
        if let location {
            daylight = SolarCalc.daylight(latitude: location.latitude, longitude: location.longitude, date: now)
            let reading = await WeatherClient.fetch(latitude: location.latitude, longitude: location.longitude)
            weather = reading.weather
            pressure = reading.pressure
        }

        return MemoMetadata(
            capturedAt: ISO8601.string(from: now),
            location: location,
            weather: weather,
            pressure: pressure,
            dayPeriod: DayPeriod.from(now),
            daylight: daylight,
            steps: steps,
            tags: []
        )
    }

    private static func captureSteps() async -> Int? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        let pedometer = CMPedometer()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: startOfDay, to: Date()) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }
}

enum MetadataProviderFactory {
    /// Mock in tests (`-seedTranscript`, which also implies no sensors/network),
    /// real capture otherwise.
    @MainActor static func make() -> any MetadataProviding {
        LaunchFlags.seedTranscript != nil ? MockMetadataService() : MetadataService()
    }
}

/// Deterministic metadata for tests — no sensors, no network.
@MainActor
struct MockMetadataService: MetadataProviding {
    var metadata: MemoMetadata

    init(_ metadata: MemoMetadata? = nil) {
        self.metadata = metadata ?? MemoMetadata(
            capturedAt: ISO8601.string(from: Date()),
            dayPeriod: .afternoon,
            tags: []
        )
    }

    func capture() async -> MemoMetadata { metadata }
}
