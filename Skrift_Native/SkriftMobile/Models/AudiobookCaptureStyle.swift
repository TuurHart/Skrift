import Foundation

/// How a quote is captured from an audiobook — the A/B seam between the two
/// capture interactions (design: `mocks/text-capture-DESIGN.md`).
///
/// `audio` = the waveform mark-in/out screen (`CaptureMomentView`, shipped).
/// `text`  = the sentence-select screen (`TextCaptureView`, new).
///
/// Persisted under one key both the Settings toggle and the capture-flow router
/// read. **Default = audio** (the proven one); Text is opt-in for the A/B test.
enum AudiobookCaptureStyle: String, CaseIterable {
    case audio
    case text

    static let storageKey = "audiobookCaptureStyle"

    /// The current style from UserDefaults (default `.audio`).
    static var current: AudiobookCaptureStyle {
        AudiobookCaptureStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .audio
    }
}
