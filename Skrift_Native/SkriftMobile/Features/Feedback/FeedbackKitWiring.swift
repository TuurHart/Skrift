import FeedbackKit
import SwiftUI
import UIKit

/// In-app feedback through the shared FeedbackKit (Q299 / D179): the floating
/// feedback button, its sheet and the outbox. App id `skrift`, key from
/// `Config/Feedback.xcconfig` (resolved from a file outside git). Phone + iPad only.
enum FeedbackKitWiring {
    static let appID = "skrift"
    static let privacyLine = "Private, only Tuur reads it. Voice notes are deleted 30 days after they are transcribed."

    /// Called once from `SkriftApp.init`.
    @MainActor
    static func start() {
        FeedbackKit.start(appearance: FeedbackPalette.appearance(privacyLine: privacyLine))
    }

    /// What the Settings "Send feedback" row calls (Q301). A seam so a test can see the
    /// row reach the kit without presenting a sheet.
    @MainActor static var presenter: () -> Void = { FeedbackKit.present() }

    @MainActor
    static func openFeedback() { presenter() }
}

/// Skrift's own tokens (Shared/UI/Palette) for every FeedbackAppearance colour (Q300 / D179).
///
/// FeedbackKit presents its sheet with `overrideUserInterfaceStyle = .light`, so a plain
/// `Color.skDynamic` would always resolve to its LIGHT column inside the sheet. These
/// colours therefore ignore the trait they are asked to resolve against and read the
/// app's own theme instead (Settings → Theme, `appTheme`; "auto" = the system style).
/// The sheet is built fresh on every open, so it picks up the current theme each time;
/// the floating button redraws on its next state change.
enum FeedbackPalette {
    /// Pure rule, unit-tested: does the feedback UI draw dark right now?
    static func isDark(themeRaw: String?, systemDark: Bool) -> Bool {
        switch ThemePreference.mode(themeRaw ?? ThemePreference.defaultRaw) {
        case .light: return false
        case .dark: return true
        case .system: return systemDark
        }
    }

    private static func liveIsDark() -> Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let systemDark = (scene?.screen.traitCollection.userInterfaceStyle ?? .light) == .dark
        return isDark(themeRaw: UserDefaults.standard.string(forKey: ThemePreference.key), systemDark: systemDark)
    }

    private static func uiColor(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    /// A light/dark pair that follows the APP theme, not the (forced-light) sheet trait.
    static func color(_ pair: PalettePair, alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { _ in uiColor(liveIsDark() ? pair.dark : pair.light, alpha: alpha) })
    }

    static func color(_ pair: DriftedPair, alpha: CGFloat = 1) -> Color { color(pair.phone, alpha: alpha) }

    /// A stroke: the primary text colour at a low alpha, so it sits right on either background.
    private static func line(alpha: CGFloat) -> Color {
        Color(uiColor: UIColor { _ in
            liveIsDark() ? uiColor(Palette.textPrimary.phone.dark, alpha: alpha)
                         : uiColor(Palette.textPrimary.phone.light, alpha: alpha)
        })
    }

    @MainActor
    static func appearance(privacyLine: String) -> FeedbackAppearance {
        FeedbackAppearance(
            accent: color(Palette.accent),
            background: color(Palette.bg.phone),
            surface: color(Palette.surface),
            soft: color(Palette.chipFill),
            track: color(Palette.chipFill),
            line: line(alpha: 0.16),
            ink: color(Palette.textPrimary),
            inkSecondary: color(Palette.textSecondary),
            inkMuted: color(Palette.textSecondary),
            inkFaint: color(Palette.textTertiary),
            placeholder: color(Palette.textTertiary),
            label: color(Palette.nameSuggest),
            questionID: color(Palette.nameSuggest),
            dot: color(Palette.nameSuggestLine),
            recording: color(Palette.red),
            recordingLate: color(Palette.red),
            privacyLine: privacyLine)
    }
}

/// The voice-pause rule, pure. FeedbackKit's recorder switches the audio session to
/// `.playAndRecord` and deactivates it afterwards, which would cut Skrift's own
/// audio — so voice notes are off while Skrift owns the session.
enum FeedbackVoicePause {
    static let line = "Voice notes are off while Skrift is recording or playing."

    struct AudioStates: Equatable {
        /// A recording session is live (paused included) — covers live caption and
        /// the voice ramble of a quote capture, which both run on `LiveRecordingService`.
        var recording = false
        var playingBook = false
        var playingMemo = false
        /// The audiobook quote-capture flow is open.
        var capturingQuote = false
    }

    static func reason(for s: AudioStates) -> String? {
        (s.recording || s.playingBook || s.playingMemo || s.capturingQuote) ? line : nil
    }
}

/// Collects the audio state from its owners and tells FeedbackKit. Recording and
/// memo playback are read from the owners' own static signals
/// (`LiveRecordingService.isRecordingActive`, `AudioPlayerModel.nowPlaying`), which
/// call `refresh()` when they change. The book and the quote-capture flow push their
/// flag (`AudiobookSession` is never touched from here, so this can't spin it up).
/// FeedbackKit only hears about a change.
@MainActor
enum FeedbackAudioGate {
    static var playingBook = false { didSet { if playingBook != oldValue { refresh() } } }
    static var capturingQuote = false { didSet { if capturingQuote != oldValue { refresh() } } }
    private static var applied: String?? = .none

    static var states: FeedbackVoicePause.AudioStates {
        FeedbackVoicePause.AudioStates(
            recording: LiveRecordingService.isRecordingActive,
            playingBook: playingBook,
            playingMemo: AudioPlayerModel.nowPlaying != nil,
            capturingQuote: capturingQuote)
    }

    static func refresh() {
        let reason = FeedbackVoicePause.reason(for: states)
        if case .some(let last) = applied, last == reason { return }
        applied = .some(reason)
        FeedbackKit.setVoicePaused(reason)
    }
}
