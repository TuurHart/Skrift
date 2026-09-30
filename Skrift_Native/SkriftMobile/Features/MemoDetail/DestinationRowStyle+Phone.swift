import SwiftUI

// The phone/iPad's style table for the SHARED `DestinationRowView` — the same
// per-app-theme seam as `NoteCardStyle.skrift` and `SignificanceStyle.phone`.
//
// It lives in its OWN file on purpose. The obvious home was beside the significance
// style in `SignificanceCircles.swift`, but the SkriftShare extension compiles that
// file BY NAME (its Sources phase is per-file, not per-directory) and does not carry
// `Shared/UI/DestinationRowView.swift` — so putting it there broke the extension
// build while the app target compiled fine. A share sheet has no destination control;
// keeping the table here is what stops it needing one.
extension DestinationRowStyle {
    /// The phone/iPad's destination row. The portfolio family is the AMBER token — the same
    /// hue the notes list already uses for "this needs your attention", which is exactly what
    /// a note about to leave for an AI-readable repo is.
    static var phone: DestinationRowStyle {
        DestinationRowStyle(
            accent: .skAccent, accentSoft: .skAccentSoft, accentText: .skAccentText,
            portfolio: .skAmber, portfolioSoft: .skAmber.opacity(0.13),
            text: .skText, textDim: .skTextDim, textFaint: .skTextFaint,
            border: .skBorder, chipFill: .skElev)
    }
}
