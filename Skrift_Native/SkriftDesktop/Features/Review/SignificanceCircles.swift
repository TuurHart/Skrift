import SwiftUI
import AppKit

// The Mac's half of the note rating pill (`NoteRatingPill` / `NoteRatingRow`, shared): which
// colours out of `Theme`, and the measurements a pointer-driven desktop was tuned to. The 3-stop
// scale is the SHARED `ThreeBallScale`. The old 3-ball card (`SignificanceCircles`,
// `ThreeBallImportanceView`) was deleted in Q89 (D158).

/// Q88: the note header's rating pill (`NoteRatingRow`, C115) for `UnpipelinedMemoSheet`,
/// the one Mac host outside `NoteProperties`. The step toast is drawn here, just above the
/// pill, because a sheet has no screen-level toast layer.
struct MacRatingRow: View {
    /// nil = the user hasn't rated this note yet. Set values are exact 0.1 snaps.
    @Binding var value: Double?
    var enabled: Bool = true
    var fadingLine: String? = nil
    @State private var toast: RatingToast?

    var body: some View {
        NoteRatingRow(value: $value, style: .mac, enabled: enabled,
                      fadingLine: fadingLine, lineColor: Theme.amber.opacity(0.9),
                      onToast: { toast = $0 })
            .overlay(alignment: .top) {
                if let toast {
                    RatingToastView(toast: toast)
                        .offset(y: -34)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .task(id: toast.id) {
                            try? await Task.sleep(for: .seconds(1.6))
                            if self.toast?.id == toast.id { withAnimation(.easeOut(duration: 0.12)) { self.toast = nil } }
                        }
                }
            }
    }
}

extension NoteRatingPillStyle {
    /// The header pill (Q85): 22pt tall, pointer-sized.
    static var mac: NoteRatingPillStyle {
        NoteRatingPillStyle(
            accent: Theme.accent,
            accentText: Theme.accentText,
            accentSoft: Theme.accent.opacity(0.13),
            surface: Theme.surface,
            border: Theme.hairline.opacity(0.09),
            ring: Theme.hairline.opacity(0.2),
            textDim: Theme.textSecondary,
            height: 22,
            fontSize: 11.5,
            hitHeight: 22,
            animation: .easeOut(duration: 0.12))
    }
}

extension DestinationRowStyle {
    /// The Mac's destination row. Portfolio family = the amber token, the same hue the
    /// sidebar already uses for "this wants your attention" — which is what a note about
    /// to leave for an AI-readable repo is.
    static var mac: DestinationRowStyle {
        DestinationRowStyle(
            accent: Theme.accent,
            accentSoft: Theme.accent.opacity(0.16),
            accentText: Theme.accentText,
            portfolio: Theme.amber,
            portfolioSoft: Theme.amber.opacity(0.13),
            text: Theme.textPrimary,
            textDim: Theme.textSecondary,
            textFaint: Theme.textMuted,
            border: Theme.hairline.opacity(0.16),
            chipFill: Theme.hairline.opacity(0.07))
    }
}
