import Foundation

/// The 10-step importance scale behind both apps' circle controls
/// (`mocks/significance-circles.html` — desktop card + iOS panel). ONE copy for
/// both apps: the scale is contract semantics, not UI — `significance` gates
/// the Mac's pipeline pickup (flag-to-process: CloudKit syncs every memo, but
/// `MemoCloudIngest` skips 0 — the Mac only polishes rated ones) and the same
/// 0.1-grid value round-trips through `Memo.significance` ↔
/// `PipelineFile.significance`, so the grid, tier boundaries (0.4 / 0.7) and
/// the 0.8 refine wall must never drift between the apps. (They did once:
/// the "Importance" relabel renamed the top tier "Important" on the phone
/// while the Mac kept "Significant" — the split copies are why.)
///
/// User-facing label is "Importance"; internal symbols stay `Significance*` /
/// `significance` (the persisted field name is the contract).
enum SignificanceScale {
    static let stepCount = 10

    /// First step past the refine wall: 0.8+ notes get a refine pass (Mac-side)
    /// before export.
    static let refineStep = 8

    /// `significance` (0 / 0.1…1.0) → its circle step (0…10). Tolerates float
    /// noise (0.7000000001 from old slider writes) by rounding, and survives
    /// off-contract values: non-finite → 0, and the clamp happens BEFORE the
    /// `Int` conversion so a huge double can't trap it.
    static func step(for value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(Double(stepCount), max(0, (value * 10).rounded())))
    }

    /// nil-tolerant `step(for:)` — how many circles are lit (0 = unrated). The
    /// desktop stores significance as `Double?` (nil = never rated); the phone
    /// stores a non-optional 0.
    static func litCount(_ value: Double?) -> Int {
        value.map(step(for:)) ?? 0
    }

    /// Circle step → the persisted significance value (0 / 0.1…1.0).
    static func value(forStep step: Int) -> Double {
        Double(min(stepCount, max(0, step))) / 10
    }

    /// Star-rating toggle: tapping the already-set circle clears to 0 (Not
    /// rated); tapping any other circle sets that rating.
    static func toggling(_ value: Double, tappedStep: Int) -> Double {
        step(for: value) == tappedStep ? 0 : self.value(forStep: tappedStep)
    }

    static func isRefine(step: Int) -> Bool { step >= refineStep }

    /// Tier name for a set step (1…10). Boundaries 0.4 / 0.7 per the mock; the
    /// top tier reads "Important" (the Importance relabel) in BOTH apps.
    static func tierName(forStep step: Int) -> String {
        step >= 7 ? "Important" : step >= 4 ? "Useful" : "Passing"
    }

    /// "0.5 · Useful" / "1.0 · Important" — the raw value text (no zero guard;
    /// callers gate on a set rating, e.g. the desktop top-right label + tooltips).
    static func valueText(forStep step: Int) -> String {
        (step == stepCount ? "1.0" : "0.\(step)") + " · " + tierName(forStep: step)
    }

    /// The live value label: "Not rated" / `valueText`.
    static func label(forStep step: Int) -> String {
        guard step > 0 else { return "Not rated" }
        return valueText(forStep: step)
    }
}
