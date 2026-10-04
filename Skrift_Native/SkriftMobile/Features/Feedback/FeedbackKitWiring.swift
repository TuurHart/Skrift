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

/// Skrift's own tokens (Shared/UI/Palette) for every FeedbackAppearance colour (Q300 / Q305, D179).
///
/// `interfaceStyle: .unspecified` makes the kit stop forcing its sheet light, so the
/// ordinary `Color.skDynamic` tokens resolve against the trait the sheet inherits.
/// `onAccent` is white: the glyph on Skrift's purple accent and red recording colour
/// (mic, Send) in both themes.
enum FeedbackPalette {
    @MainActor
    static func appearance(privacyLine: String) -> FeedbackAppearance {
        FeedbackAppearance(
            accent: .skAccent,
            background: .skBg,
            surface: .skSurface,
            soft: .skElev,
            track: .skElev,
            line: .skDynamic(Palette.textPrimary.phone, alpha: 0.16),
            ink: .skText,
            inkSecondary: .skTextDim,
            inkMuted: .skTextDim,
            inkFaint: .skTextFaint,
            placeholder: .skTextFaint,
            label: .skDynamic(Palette.nameSuggest.phone),
            questionID: .skDynamic(Palette.nameSuggest.phone),
            dot: .skDynamic(Palette.nameSuggestLine.phone),
            recording: .skDynamic(Palette.red),
            recordingLate: .skDynamic(Palette.red),
            onAccent: .white,
            interfaceStyle: .unspecified,
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
