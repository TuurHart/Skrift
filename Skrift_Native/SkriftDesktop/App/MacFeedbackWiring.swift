import FeedbackKit
import SwiftUI

/// In-app feedback on the Mac through the shared FeedbackKit (Q342, the Mac half of Q299 / D179):
/// the round button on the app's windows, the sheet, the outbox and Help > Send Feedback….
/// App id `skrift`, key from `Config/Feedback.xcconfig` (resolved from a file outside git).
/// The app is unsandboxed, so the kit needs no extra entitlements.
enum MacFeedbackWiring {
    static let appID = "skrift"
    static let privacyLine = SharedCopy.feedbackPrivacyLine

    /// Called once from `SkriftDesktopApp.init`, after the headless modes have had their turn.
    /// Never in a headless run or an XCTest host: the kit adds a child window to every titled window.
    @MainActor
    static func startIfInteractive() {
        guard !LaunchArgs.isXCTest, !HeadlessIsolation.isRequested() else { return }
        FeedbackKit.start(appearance: MacFeedbackPalette.appearance(privacyLine: privacyLine))
    }
}

/// Skrift's Mac tokens (Features/Theme) for every FeedbackAppearance colour, the twin of the
/// phone's `FeedbackPalette`. `interfaceStyle: .unspecified` makes the kit follow the app's
/// own light / dark / auto setting (`AppTheme.applyToApp`).
enum MacFeedbackPalette {
    static func appearance(privacyLine: String) -> FeedbackAppearance {
        FeedbackAppearance(
            accent: Theme.accent,
            background: Theme.bg,
            surface: Theme.surface,
            soft: Theme.chip,
            track: Theme.chip,
            line: Theme.textPrimary.opacity(0.16),
            ink: Theme.textPrimary,
            inkSecondary: Theme.textSecondary,
            inkMuted: Theme.textSecondary,
            inkFaint: Theme.textMuted,
            placeholder: Theme.textMuted,
            label: Theme.nameSuggest,
            questionID: Theme.nameSuggest,
            dot: Theme.nameSuggestLine,
            recording: Theme.destructive,
            recordingLate: Theme.destructive,
            onAccent: .white,
            interfaceStyle: .unspecified,
            privacyLine: privacyLine)
    }
}

extension View {
    /// Names the Mac's current top-level screen for feedback. The name is part of the view's
    /// identity, so a change pops the old tag and pushes the new one.
    func macFeedbackScreen(_ name: String) -> some View {
        background { Color.clear.frame(width: 0, height: 0).feedbackScreen(name).id(name) }
    }
}
