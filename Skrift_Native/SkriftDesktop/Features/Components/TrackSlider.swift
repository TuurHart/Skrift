import SwiftUI

/// The one track slider — a filled capsule track + a draggable white thumb — shared
/// by the significance slider, the Settings audio-preprocessing sliders, and the
/// audio scrubber (AUD-P2c: these were three near-identical hand-rolled copies of the
/// same GeometryReader + ZStack + DragGesture). Fraction-based: the caller maps its
/// value (or playback position) to a 0…1 fill and applies scrubs however it likes
/// (snap, round, seek). Track/thumb sizes are parameters for the few px differences.
struct TrackSlider: View {
    /// Current fill, 0…1.
    var fraction: Double
    var trackHeight: CGFloat = 4
    var thumbSize: CGFloat = 13
    /// Called continuously during a drag with the new fill (0…1).
    var onScrub: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let f = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline.opacity(0.12)).frame(height: trackHeight)
                Capsule().fill(Theme.accent).frame(width: max(0, w * f), height: trackHeight)
                Circle().fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: max(0, w * f - thumbSize / 2))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                onScrub(min(1, max(0, g.location.x / w)))
            })
        }
        .frame(height: max(thumbSize + 1, 14))
    }
}
