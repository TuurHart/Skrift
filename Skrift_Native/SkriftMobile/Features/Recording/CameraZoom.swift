import CoreGraphics

/// Pinch-zoom math for `CameraSheet`, kept pure so it can be tested without a camera.
/// A pinch's `scale` is relative to the gesture start, so the new zoom is the zoom
/// captured AT gesture start times that scale. Feeding the live zoom back in as the
/// base compounds the scale on every `onChanged` and the zoom races to the limits.
enum CameraZoom {
    /// UI ceiling when the device allows more (digital zoom past this is mush).
    static let uiCeiling: CGFloat = 5

    /// The device's supported zoom range, capped at `uiCeiling`.
    static func range(deviceMin: CGFloat, deviceMax: CGFloat) -> ClosedRange<CGFloat> {
        let lo = max(deviceMin, 0.01)
        return lo...max(lo, min(deviceMax, uiCeiling))
    }

    static func clamp(_ factor: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        max(range.lowerBound, min(factor, range.upperBound))
    }

    /// Zoom for a pinch at `scale`, from the zoom factor when the gesture began.
    static func pinched(start: CGFloat, scale: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        clamp(start * scale, to: range)
    }
}
