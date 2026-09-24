import SwiftUI
import AppKit

// The importance control itself is the SHARED `ThreeBallImportanceView`
// (Shared/UI/ThreeBallImportanceView.swift) and the value↔ball mapping is the
// SHARED `ThreeBallScale` — one copy each for both apps, since the scale gates
// phone→Mac sync and the control has already drifted twice (Q8, replacing the
// 10-circle `SignificanceCirclesView`/`SignificanceScale` pairing here). What is
// left here is the Mac's half: which colours out of `Theme`, and the
// measurements a pointer-driven desktop card was tuned to.

/// The Mac's importance card. Keeps the call sites (`NoteProperties`,
/// `UnpipelinedMemoSheet`) unchanged; everything it draws comes from the shared view.
struct SignificanceCircles: View {
    /// nil = the user hasn't rated this note yet. Set values are exact 0.1 snaps.
    @Binding var value: Double?
    /// Disabled until the note is processed (#18 — can't rate an unprocessed note).
    var enabled: Bool = true

    var body: some View {
        ThreeBallImportanceView(value: $value, style: .mac, enabled: enabled)
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

extension DestinationRowStyle {
    /// The Mac's destination row. Archive family = the amber token, the same hue the
    /// sidebar already uses for "this wants your attention" — which is what a note about
    /// to leave for an AI-readable repo is.
    static var mac: DestinationRowStyle {
        DestinationRowStyle(
            accent: Theme.accent,
            accentSoft: Theme.accent.opacity(0.16),
            accentText: Theme.accentText,
            archive: Theme.amber,
            archiveSoft: Theme.amber.opacity(0.13),
            text: Theme.textPrimary,
            textDim: Theme.textSecondary,
            textFaint: Theme.textMuted,
            border: Theme.hairline.opacity(0.16),
            chipFill: Theme.hairline.opacity(0.07))
    }
}
