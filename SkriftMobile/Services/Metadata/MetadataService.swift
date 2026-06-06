import CoreLocation
import CoreMotion
import Foundation

/// Captures contextual metadata when a recording stops. `@MainActor` so the
/// CoreLocation manager gets a run loop for its delegate callbacks.
@MainActor
protocol MetadataProviding {
    func capture() async -> MemoMetadata
}

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

/// One-shot CoreLocation fix + reverse-geocode. Returns nil if unauthorized or
/// the fix fails. Created/used on the main actor so delegate callbacks arrive.
@MainActor
final class LocationOneShot: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationInfo?, Never>?

    func current() async -> LocationInfo? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways || status == .notDetermined else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            if status == .notDetermined { manager.requestWhenInUseAuthorization() }
            manager.requestLocation()
        }
    }

    private func finish(_ info: LocationInfo?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: info)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            Task { @MainActor in self.finish(nil) }
            return
        }
        Task { @MainActor in
            let place = await Self.reverseGeocode(location)
            self.finish(LocationInfo(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                placeName: place
            ))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private static func reverseGeocode(_ location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first else { return nil }
        let area = placemark.subLocality ?? placemark.thoroughfare ?? placemark.locality ?? placemark.subAdministrativeArea
        let city = (placemark.locality != nil && area != placemark.locality) ? placemark.locality : nil
        let name = [area, city].compactMap { $0 }.joined(separator: ", ")
        return name.isEmpty ? nil : name
    }
}
