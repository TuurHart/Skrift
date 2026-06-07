import Foundation

/// Sunrise/sunset + daylight hours from latitude/longitude/date, via the standard
/// sunrise equation (NOAA). Replaces the RN app's SunCalc dependency. Pure math —
/// no sensors — so it's fully testable on the Simulator.
enum SolarCalc {
    /// Daylight info (local `HH:mm` sunrise/sunset + hours of light) for a date at
    /// a location. nil for polar day/night (sun never rises/sets).
    static func daylight(
        latitude: Double,
        longitude: Double,
        date: Date,
        timeZone: TimeZone = .current
    ) -> DaylightInfo? {
        guard let (sunrise, sunset) = sunriseSunset(latitude: latitude, longitude: longitude, date: date) else {
            return nil
        }
        let hours = sunset.timeIntervalSince(sunrise) / 3_600.0
        return DaylightInfo(
            sunrise: hhmm(sunrise, timeZone),
            sunset: hhmm(sunset, timeZone),
            hoursOfLight: (hours * 100).rounded() / 100
        )
    }

    /// UTC sunrise/sunset instants, or nil for polar day/night.
    static func sunriseSunset(latitude: Double, longitude: Double, date: Date) -> (sunrise: Date, sunset: Date)? {
        let rad = Double.pi / 180

        let jd = date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
        let n = (jd - 2_451_545.0 + 0.0008).rounded()           // days since J2000
        let meanSolarTime = n - longitude / 360.0
        let M = (357.5291 + 0.98560028 * meanSolarTime).truncatingRemainder(dividingBy: 360)
        let mRad = M * rad
        let center = 1.9148 * sin(mRad) + 0.0200 * sin(2 * mRad) + 0.0003 * sin(3 * mRad)
        let lambda = (M + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let lambdaRad = lambda * rad
        let transit = 2_451_545.0 + meanSolarTime + 0.0053 * sin(mRad) - 0.0069 * sin(2 * lambdaRad)
        let declination = asin(sin(lambdaRad) * sin(23.44 * rad))

        let cosOmega = (sin(-0.833 * rad) - sin(latitude * rad) * sin(declination))
            / (cos(latitude * rad) * cos(declination))
        guard cosOmega >= -1, cosOmega <= 1 else { return nil }  // polar day/night
        let omega = acos(cosOmega) / rad                         // hour angle, degrees

        let riseJD = transit - omega / 360.0
        let setJD = transit + omega / 360.0
        return (dateFromJulian(riseJD), dateFromJulian(setJD))
    }

    private static func dateFromJulian(_ jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400.0)
    }

    private static func hhmm(_ date: Date, _ tz: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = tz
        return formatter.string(from: date)
    }
}

extension DayPeriod {
    /// morning/afternoon/evening/night from the hour, matching the RN `getDayPeriod`.
    static func from(_ date: Date, calendar: Calendar = .current) -> DayPeriod {
        switch calendar.component(.hour, from: date) {
        case 6..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}
