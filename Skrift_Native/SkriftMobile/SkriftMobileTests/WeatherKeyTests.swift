import XCTest
@testable import SkriftMobile

/// The weather API key must flow from Settings to the fetch: SettingsView binds
/// `@AppStorage("weatherAPIKey")`, and WeatherClient reads that same slot (with the
/// RN-era "openweathermap_api_key" as a legacy fallback). A mismatch here is the
/// silent kind — Settings looks set, the fetch quietly returns .empty.
final class WeatherKeyTests: XCTestCase {
    private let defaults = UserDefaults.standard

    override func tearDown() {
        defaults.removeObject(forKey: WeatherClient.apiKeyDefaultsKey)
        defaults.removeObject(forKey: WeatherClient.legacyAPIKeyDefaultsKey)
        super.tearDown()
    }

    func testReadsTheKeySettingsWrites() {
        // SettingsView's @AppStorage key is a string literal there; pin the contract.
        XCTAssertEqual(WeatherClient.apiKeyDefaultsKey, "weatherAPIKey")
        defaults.set("abc123", forKey: "weatherAPIKey")
        XCTAssertEqual(WeatherClient.apiKey, "abc123")
    }

    func testTrimsWhitespaceOnRead() {
        // @AppStorage writes the raw text — trimming happens on read.
        defaults.set("  abc123  ", forKey: WeatherClient.apiKeyDefaultsKey)
        XCTAssertEqual(WeatherClient.apiKey, "abc123")
    }

    func testEmptyOrWhitespaceKeyReadsAsNil() {
        defaults.set("   ", forKey: WeatherClient.apiKeyDefaultsKey)
        XCTAssertNil(WeatherClient.apiKey)
    }

    func testLegacyKeyFallback() {
        // A key written to the RN-era slot still works when the Settings slot is unset.
        defaults.set("legacy42", forKey: WeatherClient.legacyAPIKeyDefaultsKey)
        XCTAssertEqual(WeatherClient.apiKey, "legacy42")
        // ...but the Settings slot wins once present.
        defaults.set("fresh7", forKey: WeatherClient.apiKeyDefaultsKey)
        XCTAssertEqual(WeatherClient.apiKey, "fresh7")
    }

    func testSetAPIKeyRoundTrip() {
        WeatherClient.setAPIKey("  zz9  ")
        XCTAssertEqual(WeatherClient.apiKey, "zz9")
        WeatherClient.setAPIKey(nil)
        XCTAssertNil(WeatherClient.apiKey)
    }
}
