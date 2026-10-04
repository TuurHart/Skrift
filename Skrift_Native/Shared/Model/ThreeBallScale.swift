import Foundation

/// The 3-stop importance scale (Q2, D30, D107, C210): Passing 0.3 / Useful 0.6 /
/// Important 1.0. THE importance scale for both apps — legacy 0.1–1.0 grid
/// values (still the persisted contract on `Memo.significance` /
/// `PipelineFile.significance`) bucket to the nearest of the three stops. There
/// is no refine wall (D52/C183 removed the refine pass): a rating's only job now
/// is "process this or don't" — 0 = left alone, any stop = ready to process. ONE
/// copy for both apps: this gates CloudKit→pipeline pickup, so the grid and the
/// bucket boundaries must never drift between the Mac, phone and iPad.
///
/// The old 10-circle scale (and the concept of a refine pass) is fully retired
/// (Q24) — `NoteConsent`, `ConnectionsPanel` (both apps), `JournalView`,
/// `RunFile` and `LookbackProvider` all read this scale now.
enum ThreeBallScale {
    /// Persisted values a tapped ball writes.
    static let stops: [Double] = [0.3, 0.6, 1.0]
    static let names = ["Passing", "Useful", "Important"]
    static let stepCount = 3

    /// Legacy 0.1–1.0 grid value → its ball (0 = unrated, 1...3). Buckets
    /// 0.1–0.3 → 1 (Passing), 0.4–0.6 → 2 (Useful), 0.7–1.0 → 3 (Important —
    /// 0.7 rounds UP because it already read "Important" on the old scale).
    /// Non-finite or ≤0 → 0; anything above the grid clamps to 3 rather than
    /// trapping, same discipline the old scale used.
    static func step(for value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        // Clamp BEFORE the `Int` conversion — `value * 10` on a huge finite
        // double (e.g. `.greatestFiniteMagnitude`) overflows to `.infinity`,
        // and `Int(.infinity)` traps. Same discipline the old scale used.
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
    /// same convention the old scale used.
    static func step(for value: Double?) -> Int {
        value.map(step(for:)) ?? 0
    }

    /// Ball step (1...3) → the persisted stop value.
    static func value(forStep step: Int) -> Double {
        guard step >= 1, step <= stepCount else { return 0 }
        return stops[step - 1]
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

    // ── The header pill (Q85, signed mock Q75-note-header-final, behaviour A) ──

    /// One tap on the pill: Not rated → Passing → Useful → Important → Not rated.
    /// Stepping off Important un-rates (C88: the row stays, the note leaves the
    /// queue and every export). Returns the persisted value (0 = Not rated).
    static func stepped(_ value: Double?) -> Double {
        let next = (step(for: value) + 1) % (stepCount + 1)
        return self.value(forStep: next)
    }

    /// The toast that names what a pill tap just did. `from`/`to` are steps 0...3.
    static func toastCopy(from: Int, to: Int) -> String {
        if to > 0 { return "\(name(forStep: to)) · ready to process" }
        return from > 0 ? "Not rated · out of the queue, no export" : "Not rated · left alone"
    }

    // ── The Connections row readout (Q119, C210: one rule on Mac, iPad, phone) ──

    /// The importance decimal a Connections row prints: the BUCKETED stop, never
    /// the raw stored value (legacy 0.7 reads "1.0", 0.4 reads "0.6"). nil when
    /// unrated (no fake "0.0").
    static func readout(for value: Double?) -> String? {
        let s = step(for: value)
        return s > 0 ? String(format: "%.1f", self.value(forStep: s)) : nil
    }

    /// The readout's amber tier: the top stop (Important) only.
    static func isTopStop(_ value: Double?) -> Bool {
        step(for: value) == stepCount
    }
}
