import SwiftUI
import AppKit

// The importance control itself is the SHARED `ThreeBallImportanceView`
// (Shared/UI/ThreeBallImportanceView.swift) and the value↔ball mapping is the
// SHARED `ThreeBallScale` — one copy each for both apps, since the scale gates
// phone→Mac sync and the control has already drifted twice (Q8, replacing the
// old 10-circle scale/view pairing here, fully retired by Q24). What is
// left here is the Mac's half: which colours out of `Theme`, and the
// measurements a pointer-driven desktop card was tuned to.

/// The Mac's importance control outside the note page. Since Q88 it is the SAME header
/// pill as `NoteProperties` (`NoteRatingRow`, C115), used by `UnpipelinedMemoSheet`.
/// The step toast is drawn here, just above the pill, because a sheet has no
/// screen-level toast layer.
struct SignificanceCircles: View {
    /// nil = the user hasn't rated this note yet. Set values are exact 0.1 snaps.
    @Binding var value: Double?
    /// Disabled until the note is processed (#18 — can't rate an unprocessed note).
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

extension ThreeBallStyle {
    /// Desktop card: 10pt balls at 8pt gaps in a 20pt pointer target (D107 —
    /// one size down from the old 13pt/7pt control), hover + tooltips, an
    /// outlined card.
    static var mac: ThreeBallStyle {
        ThreeBallStyle(
            accent: Theme.accent,
            surface: Theme.surface,
            divider: Theme.hairline.opacity(0.07),
            ring: Theme.hairline.opacity(0.2),
            cardStroke: Theme.hairline.opacity(0.07),
            textMuted: Theme.textMuted,
            textSecondary: Theme.textSecondary,
            green: Theme.green,
            ballSize: 10,
            gap: 8,
            targetSize: 20,
            cardRadius: 12,
            syncDotSize: 5,
            syncFontSize: 11,
            hoverPreview: true,
            tooltips: true,
            scalesToFit: false,
            animation: .easeOut(duration: 0.12))
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
