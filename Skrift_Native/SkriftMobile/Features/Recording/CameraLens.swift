import CoreGraphics

/// Which camera the capture session runs, and what that means for the zoom chips.
/// Zoom in the UI is in "display" units where 1 = the main (wide) lens, like the system Camera.
/// A virtual back device (triple / dual-wide) starts at the ULTRA-WIDE at `videoZoomFactor` 1,
/// so display 1x is `videoZoomFactor` == the first switch-over factor (2 on current iPhones)
/// and display 0.5x is `videoZoomFactor` 1. A plain wide camera has min zoom 1.0 and cannot
/// reach 0.5x at all, so it never offers that chip.
enum CameraLens: Equatable {
    case tripleBack
    case dualWideBack
    case wideBack
    case front

    /// The virtual device exposes the ultra-wide lens (zoom below the wide's 1x).
    var hasUltraWide: Bool { self == .tripleBack || self == .dualWideBack }

    /// The presets the sheet shows for this camera at its display-unit zoom range.
    /// `.5x` only when the ultra-wide is reachable; `2x` only when the range reaches it;
    /// the front camera shows no row (pinch only).
    static func chips(for lens: CameraLens, displayRange: ClosedRange<CGFloat>) -> [CGFloat] {
        guard lens != .front else { return [] }
        var out: [CGFloat] = []
        if lens.hasUltraWide, displayRange.lowerBound <= 0.5 + 0.001 { out.append(0.5) }
        out.append(1)
        if displayRange.upperBound >= 2 - 0.001 { out.append(2) }
        return out
    }

    /// `videoZoomFactor` that frames display 1x: the first switch-over factor for a virtual
    /// device that starts on the ultra-wide, else 1.
    static func baseFactor(hasUltraWide: Bool, firstSwitchOver: CGFloat?) -> CGFloat {
        guard hasUltraWide, let s = firstSwitchOver, s >= 1 else { return 1 }
        return s
    }
}
