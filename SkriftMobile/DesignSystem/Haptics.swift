import AudioToolbox
import UIKit

/// Tactile feedback. Plain taps use the native haptic engine; but an **active
/// `.measurement` recording session suppresses the haptic engine**, so taps made
/// while recording (stop / shutter / pause) fall back to a short system sound so
/// the press still registers. (Handoff: native `.sensoryFeedback` shares the
/// audio session and gets muted mid-recording.)
enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// For controls pressed while a recording is active — the haptic engine is
    /// suppressed, so play a brief system tick instead.
    static func recordingTap() {
        AudioServicesPlaySystemSound(1104)
    }
}
