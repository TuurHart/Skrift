import Foundation

/// The UserDefaults / `@AppStorage` keys both apps share, each with its default beside it
/// (C239). Writers and readers use these, never a string literal, so a key and its default
/// cannot drift between a Settings toggle and the service that reads it.
enum PrefKey {
    /// Live caption while recording (phone). Default ON.
    static let liveTranscription = "liveTranscription"
    static let liveTranscriptionDefault = true

    /// Seconds of silence before the live caption turns itself off (phone).
    static let liveCaptionAutoOffSeconds = "liveCaptionAutoOffSeconds"
    static let liveCaptionAutoOffSecondsDefault = 60

    /// Copy the transcript to the clipboard after a save (phone). Default OFF (user-locked).
    static let autoCopyTranscript = "autoCopyTranscript"
    static let autoCopyTranscriptDefault = false

    /// Tapping a word in the read-along seeks the audio (phone). Default ON.
    static let karaokeTapToSeek = "karaokeTapToSeek"
    static let karaokeTapToSeekDefault = true

    /// When the user last looked at the fading list (seconds since 1970; both apps).
    static let fadingLastSeenAt = "fadingLastSeenAt"
    static let fadingLastSeenAtDefault: Double = 0

    /// The OpenWeather key Settings writes and `WeatherClient` reads (phone).
    static let weatherAPIKey = "weatherAPIKey"
    static let weatherAPIKeyDefault = ""

    /// The theme preference; the ColorScheme mapping lives in `ThemePreference`.
    static let appTheme = ThemePreference.key
    static let appThemeDefault = ThemePreference.defaultRaw

    /// Whether the Mac sidebar is showing.
    static let macSidebarVisible = "macSidebarVisible"
    static let macSidebarVisibleDefault = true

    /// The Mac's left-column width in points. ONE value for both surfaces: the Notes split
    /// writes it as the divider is dragged, the Review rail reads it (`MacSidebarWidth`).
    static let macSidebarWidth = "macSidebarWidth"
}

/// The Mac left column's width rule (Q533). Notes (HSplitView, draggable) and Review
/// (fixed rail) used to differ (292 vs 252), so ⌘1 / ⌘2 made the column jump. Pure
/// arithmetic so a unit test can pin it.
enum MacSidebarWidth {
    static let minimum: Double = 240   // the measured floor of the Notes header row
    static let ideal: Double = 292     // m2 cards breathe at ~290 (signed mock)
    static let maximum: Double = 360

    /// Clamp a stored value into the column's range; zero / garbage falls back to `ideal`.
    static func clamped(_ raw: Double) -> Double {
        guard raw.isFinite, raw > 0 else { return ideal }
        return min(max(raw, minimum), maximum)
    }

    /// Whether a measured width is worth persisting: in range and moved by at least half a point.
    static func shouldRecord(measured: Double, stored: Double) -> Bool {
        guard measured.isFinite, measured >= minimum, measured <= maximum else { return false }
        return abs(measured - clamped(stored)) >= 0.5
    }

    static func current(in defaults: UserDefaults = .standard) -> Double {
        clamped(defaults.double(forKey: PrefKey.macSidebarWidth))
    }

    /// Persist a drag-written width (no-op when it is out of range or unchanged).
    static func record(_ measured: Double, in defaults: UserDefaults = .standard) {
        guard shouldRecord(measured: measured, stored: defaults.double(forKey: PrefKey.macSidebarWidth)) else { return }
        defaults.set(measured, forKey: PrefKey.macSidebarWidth)
    }
}
