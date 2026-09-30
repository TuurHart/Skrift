import SwiftUI

// The importance control itself is the SHARED `ThreeBallImportanceView`
// (Shared/UI/ThreeBallImportanceView.swift) and the 3-stop scale is the SHARED
// `ThreeBallScale` — one copy each for both apps, since the scale gates
// phone→Mac sync and the control has already drifted twice (Q8, replacing the
// old 10-circle scale/view pairing here, fully retired by Q24). What is
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

/// Q88: the note header's rating pill (`NoteRatingRow`: pill + orange fading line — one
/// header everywhere, C115) for hosts outside the note page: the quick note, the audiobook
/// capture sheet and the share sheet. Same non-optional `Double` binding as
/// `SignificanceCircles` (the phone stores "never rated" as 0). The step toast is drawn
/// here, just above the pill, because a sheet / share extension has no screen-level layer.
struct PhoneRatingRow: View {
    @Binding var value: Double
    var onCommit: () -> Void = {}
    /// nil = no line (rated, or the note doesn't exist yet).
    var fadingLine: String? = nil
    @State private var toast: RatingToast?

    var body: some View {
        NoteRatingRow(
            value: Binding(get: { value == 0 ? nil : value },
                           set: { value = $0 ?? 0 }),
            style: .phone,
            fadingLine: fadingLine,
            lineColor: Color.skAmber.opacity(0.9),
            onTap: { Haptics.tap(.light) },
            onCommit: onCommit,
            onToast: { toast = $0 })
            .overlay(alignment: .top) {
                if let toast {
                    RatingToastView(toast: toast)
                        .offset(y: -38)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .task(id: toast.id) {
                            try? await Task.sleep(for: .seconds(1.6))
                            if self.toast?.id == toast.id { withAnimation(SkMotion.snappy) { self.toast = nil } }
                        }
                }
            }
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
    fileprivate static let ring = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.22)
                                       : UIColor(white: 0, alpha: 0.18)
    })
}

extension NoteRatingPillStyle {
    /// The header pill (Q85): 26pt tall, 44pt touch target, 12pt semibold.
    static var phone: NoteRatingPillStyle {
        NoteRatingPillStyle(
            accent: .skAccent,
            accentText: .skAccentText,
            accentSoft: .skAccentSoft,
            surface: .skSurface,
            border: .skBorder,
            ring: ThreeBallStyle.ring,
            textDim: .skTextDim,
            height: 26,
            fontSize: 12,
            hitHeight: 44,
            animation: SkMotion.snappy)
    }
}
