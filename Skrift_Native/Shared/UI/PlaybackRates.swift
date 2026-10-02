import Foundation

/// C115/C240: the ONE playback-speed list and its label, shared by the phone/iPad player and
/// the Mac dock. Foundation-only so the Mac unit bundle can compile it.
enum PlaybackRates {
    static let steps: [Float] = [0.75, 1, 1.25, 1.5, 2]

    /// The step after `rate` (wraps). A rate that is not on the list restarts at 1×.
    static func next(after rate: Float) -> Float {
        guard let i = steps.firstIndex(of: rate) else { return 1 }
        return steps[(i + 1) % steps.count]
    }

    /// "1×", "1.5×", "0.75×".
    static func label(_ rate: Float) -> String {
        let n = rate == rate.rounded() ? String(Int(rate)) : String(format: "%g", rate)
        return "\(n)×"
    }
}
