import XCTest
@testable import SkriftMobile

final class MetadataTests: XCTestCase {

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(hour: Int) -> Date {
        utcCalendar().date(from: DateComponents(year: 2026, month: 6, day: 6, hour: hour))!
    }

    func testDayPeriodFromHour() {
        let calendar = utcCalendar()
        XCTAssertEqual(DayPeriod.from(date(hour: 8), calendar: calendar), .morning)
        XCTAssertEqual(DayPeriod.from(date(hour: 14), calendar: calendar), .afternoon)
        XCTAssertEqual(DayPeriod.from(date(hour: 19), calendar: calendar), .evening)
        XCTAssertEqual(DayPeriod.from(date(hour: 2), calendar: calendar), .night)
    }

    func testSolarDaylightPlausibleForLisbonSummer() {
        let date = utcCalendar().date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let daylight = SolarCalc.daylight(latitude: 38.72, longitude: -9.14, date: date,
                                          timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertNotNil(daylight)
        let hours = daylight?.hoursOfLight ?? 0
        XCTAssertGreaterThan(hours, 14.0)   // Lisbon midsummer ≈ 14.9h
        XCTAssertLessThan(hours, 16.0)
        XCTAssertFalse(daylight?.sunrise.isEmpty ?? true)
        XCTAssertFalse(daylight?.sunset.isEmpty ?? true)
    }

    func testSolarPolarDayReturnsNil() {
        let date = utcCalendar().date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        // 80°N at midsummer → the sun never sets → no sunrise/sunset.
        XCTAssertNil(SolarCalc.daylight(latitude: 80, longitude: 0, date: date))
    }

    func testWeatherParse() {
        let json = #"{"weather":[{"main":"Clouds"}],"main":{"temp":18.6,"pressure":1015}}"#.data(using: .utf8)!
        let reading = WeatherClient.parse(json)
        XCTAssertEqual(reading.weather?.conditions, "Clouds")
        XCTAssertEqual(reading.weather?.temperature, 19)   // rounded from 18.6
        XCTAssertEqual(reading.weather?.temperatureUnit, "C")
        XCTAssertEqual(reading.pressure?.hPa, 1015)
        XCTAssertEqual(reading.pressure?.trend, .steady)
    }
}
