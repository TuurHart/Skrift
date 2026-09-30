import SwiftUI

// The phone's half of the note rating pill (`NoteRatingPill` / `NoteRatingRow`, shared): which
// colours out of `Theme`, and the measurements a touch screen was tuned to. Also drawn on iPad
// (SkriftMobile is universal, TARGETED_DEVICE_FAMILY "1,2"). The 3-stop scale is the SHARED
// `ThreeBallScale`. The old 3-ball card (`SignificanceCircles`, `ThreeBallImportanceView`) was
// deleted in Q89 (D158).

/// Q88: the note header's rating pill (`NoteRatingRow`: pill + orange fading line — one
/// header everywhere, C115) for hosts outside the note page: the quick note, the audiobook
/// capture sheet and the share sheet. Non-optional `Double` binding (the phone stores "never rated" as 0). The step toast is drawn
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

extension NoteRatingPillStyle {
    /// The header pill (Q85): 26pt tall, 44pt touch target, 12pt semibold.
    static var phone: NoteRatingPillStyle {
        NoteRatingPillStyle(
            accent: .skAccent,
            accentText: .skAccentText,
            accentSoft: .skAccentSoft,
            surface: .skSurface,
            border: .skBorder,
            ring: ring,
            textDim: .skTextDim,
            height: 26,
            fontSize: 12,
            hitHeight: 44,
            animation: SkMotion.snappy)
    }

    /// Unlit ball ring — the mock's 20% hairline, adaptive.
    private static let ring = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.22)
                                       : UIColor(white: 0, alpha: 0.18)
    })
}
