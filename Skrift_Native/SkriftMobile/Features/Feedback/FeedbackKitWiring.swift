import FeedbackKit
import SwiftUI

/// In-app feedback through the shared FeedbackKit (Q299 / D179): the floating
/// feedback button, its sheet and the outbox. App id `skrift`, key from
/// `Config/Feedback.xcconfig` (resolved from a file outside git). Phone + iPad only.
enum FeedbackKitWiring {
    static let appID = "skrift"
    static let privacyLine = "Private, only Tuur reads it. Voice notes are deleted 30 days after they are transcribed."

    /// Called once from `SkriftApp.init`. The sheet is drawn light-only, so it takes
    /// the LIGHT column of Skrift's accent token.
    @MainActor
    static func start() {
        let accent = Palette.accent.light
        FeedbackKit.start(appearance: FeedbackAppearance(
            accent: Color(.sRGB,
                          red: Double((accent >> 16) & 0xff) / 255,
                          green: Double((accent >> 8) & 0xff) / 255,
                          blue: Double(accent & 0xff) / 255),
            privacyLine: privacyLine))
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
