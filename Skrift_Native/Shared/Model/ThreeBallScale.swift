import Foundation

/// The 3-stop importance scale (Q2, D30, D107): Passing 0.3 / Useful 0.6 /
/// Important 1.0. Replaces the 10-circle `SignificanceScale`'s role as the
/// importance CONTROL's scale — legacy 0.1–1.0 grid values (still the persisted
/// contract on `Memo.significance` / `PipelineFile.significance`) bucket to the
/// nearest of the three stops. There is no refine wall (D52 removed the refine
/// pass): a rating's only job now is "process this or don't" — 0 = left alone,
/// any stop = ready to process. ONE copy for both apps, same reason the old
/// scale was unified: this gates CloudKit→pipeline pickup, so the grid and the
/// bucket boundaries must never drift between the Mac, phone and iPad.
///
/// `SignificanceScale` (Shared/Model/SignificanceScale.swift) stays as-is
/// alongside this: it is still exercised directly, outside the ball control, by
/// `NoteConsent`, `ConnectionsPanel` (both apps), `JournalView`, `RunFile` and
/// `LookbackProvider` — none of which Q8 touches. Retiring those call sites
/// (and the refine-pass concept they still read) is not this item's scope.
enum ThreeBallScale {
    /// Persisted values a tapped ball writes.
    static let stops: [Double] = [0.3, 0.6, 1.0]
    static let names = ["Passing", "Useful", "Important"]
    static let stepCount = 3

    /// Legacy 0.1–1.0 grid value → its ball (0 = unrated, 1...3). Buckets
    /// 0.1–0.3 → 1 (Passing), 0.4–0.6 → 2 (Useful), 0.7–1.0 → 3 (Important —
    /// 0.7 rounds UP because it already read "Important" on the old scale).
    /// Non-finite or ≤0 → 0; anything above the grid clamps to 3 rather than
    /// trapping, same discipline as `SignificanceScale.step(for:)`.
    static func step(for value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        // Clamp BEFORE the `Int` conversion — `value * 10` on a huge finite
        // double (e.g. `.greatestFiniteMagnitude`) overflows to `.infinity`,
        // and `Int(.infinity)` traps. Same discipline as
        // `SignificanceScale.step(for:)`.
        let tenth = Int(min(10, (value * 10).rounded()))
        switch tenth {
        case ..<1: return 0
        case 1...3: return 1
        case 4...6: return 2
        default: return 3
        }
    }

    /// nil-tolerant `step(for:)` — the desktop stores `Double?` (nil = never
    /// rated); the phone stores a non-optional 0 and adapts at the call site,
    /// same convention as `SignificanceScale.litCount`.
    static func step(for value: Double?) -> Int {
        value.map(step(for:)) ?? 0
    }

    /// Ball step (1...3) → the persisted stop value.
    static func value(forStep step: Int) -> Double {
        guard step >= 1, step <= stepCount else { return 0 }
        return stops[step - 1]
    }

    /// Tap-to-set / tap-to-clear: tapping the already-set ball clears to 0 (Not
    /// rated); tapping any other ball sets that stop.
    static func toggling(_ value: Double?, tappedStep: Int) -> Double {
        step(for: value) == tappedStep ? 0 : self.value(forStep: tappedStep)
    }

    /// Tier word for a set ball (1...3). Out of range reads "Not rated" — callers
    /// that need the raw word for a hovered/previewed ball pass 1...3 only.
    static func name(forStep step: Int) -> String {
        guard step >= 1, step <= stepCount else { return "Not rated" }
        return names[step - 1]
    }

    /// The live readout: the word alone, no number (Q2/D134 — "the word alone as
    /// readout" was the signed pick; the numeric variant lost).
    static func label(forStep step: Int) -> String {
        step > 0 ? name(forStep: step) : "Not rated"
    }

    /// What the rating means for processing. No refine-pass branch — amber and
    /// the refine wall left the control entirely (D52, D107).
    static func syncCopy(forStep step: Int) -> String {
        step == 0 ? "Not rated — left alone" : "Rated — ready to process"
    }
}
