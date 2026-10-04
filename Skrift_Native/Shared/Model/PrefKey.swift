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

    /// The day (yyyy-MM-dd) the Continue-listening card was dismissed (phone).
    static let continueCardDismissedDay = "continueCardDismissedDay"
    static let continueCardDismissedDayDefault = ""

    /// The OpenWeather key Settings writes and `WeatherClient` reads (phone).
    static let weatherAPIKey = "weatherAPIKey"
    static let weatherAPIKeyDefault = ""

    /// The theme preference; the ColorScheme mapping lives in `ThemePreference`.
    static let appTheme = ThemePreference.key
    static let appThemeDefault = ThemePreference.defaultRaw

    /// Whether the Mac sidebar is showing.
    static let macSidebarVisible = "macSidebarVisible"
    static let macSidebarVisibleDefault = true

    /// The author name for published notes. The key and its LWW stamp are owned by
    /// `AuthorSettings` (Q158); this only re-exports the key.
    static let publishAuthor = AuthorSettings.key
}
