import Foundation

/// C115/C240: the ONE seconds → clock label, on both apps (player times, list duration chip,
/// stats line, header chip). "m:ss", and "h:mm:ss" once the hour is reached, so a 2h05m note
/// reads 2:05:33, never 125:33. Foundation-only so the Mac unit bundle can compile it.
enum DurationFormat {
    static func label(seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
