import SwiftUI

// The importance control itself is the SHARED `ThreeBallImportanceView`
// (Shared/UI/ThreeBallImportanceView.swift) and the 3-stop scale is the SHARED
// `ThreeBallScale` — one copy each for both apps, since the scale gates
// phone→Mac sync and the control has already drifted twice (Q8, replacing the
// 10-circle `SignificanceCirclesView`/`SignificanceScale` pairing here). What is
// left here is the phone's half (also drawn on iPad — SkriftMobile is universal,
// TARGETED_DEVICE_FAMILY "1,2"): which colours out of `Theme`, and the
// measurements a touch screen was tuned to.

/// The phone/iPad importance card. Keeps the call sites (`MemoDetailView`,
/// `MergedCaptureView`, `ShareSheetView`) unchanged, including their non-optional
/// `Double` binding — the shared view speaks `Double?` (nil = never rated), which
/// the phone stores as 0.
struct SignificanceCircles: View {
    @Binding var value: Double
    var onCommit: () -> Void

    var body: some View {
        ThreeBallImportanceView(
            value: Binding(get: { value == 0 ? nil : value },
                           set: { value = $0 ?? 0 }),
            style: .phone,
            onTap: { Haptics.tap(.light) },
            onCommit: onCommit)
    }
}

extension ThreeBallStyle {
    /// Touch panel: 15pt balls at 10pt gaps in a 44pt touch target (D107 — one
    /// size down from the old 18pt/6pt control). No hover, the sync line
    /// shrinks rather than truncates on a narrow phone.
    static var phone: ThreeBallStyle {
        ThreeBallStyle(
            accent: .skAccent,
            surface: .skSurface,
            divider: .skBorder,
            ring: ring,
            cardStroke: nil,            // the phone's card is fill-only
            textMuted: .skTextFaint,
            textSecondary: .skTextDim,
            green: .skGreen,
            ballSize: 15,
            gap: 10,
            targetSize: 44,
            cardRadius: Theme.Radius.card,
            syncDotSize: 6,
            syncFontSize: 10.5,
            hoverPreview: false,
            tooltips: false,
            scalesToFit: true,
            animation: SkMotion.snappy)
    }

    /// Unlit ball ring — the mock's 20% hairline, adaptive.
    private static let ring = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.22)
                                       : UIColor(white: 0, alpha: 0.18)
    })
}
