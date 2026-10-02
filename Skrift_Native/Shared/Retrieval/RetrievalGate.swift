import Foundation

/// The consent/loading state machine BOTH apps' semantic-index gates render from —
/// one source for the states AND the user-facing copy (the Journal/Review label
/// lesson: twin strings drift). The Mac's Connections panel and the phone's
/// "Review & search" settings section both derive from here.
enum RetrievalGate: Equatable {
    case gate
    case downloading(fraction: Double)
    /// Bytes done but `prepare()` hasn't returned — the CoreML compile/ANE load.
    /// Without its own label the bar looks frozen (device-found 2026-07-16; the
    /// phone's A15 compile takes ~2 minutes, so it needs this MORE than the Mac).
    case preparing
    case indexing(done: Int, total: Int)
    /// The engine is cold-loading / a first query is in flight — never claim
    /// "no connections" while the answer is still unknown (no-bad-info rule).
    case finding
    case ready

    /// Derive the state from the observable facts. `hasRows` = the current
    /// surface already has results to show (rows win over progress states);
    /// `querying` = a query for the current item is in flight.
    static func derive(enabled: Bool, modelDownloaded: Bool,
                       downloadFraction: Double?,
                       sweeping: Bool, sweepProgress: (done: Int, total: Int)?,
                       hasRows: Bool, querying: Bool) -> RetrievalGate {
        if let f = downloadFraction {
            return f >= 0.999 ? .preparing : .downloading(fraction: f)
        }
        guard enabled, modelDownloaded else { return .gate }
        if !hasRows, sweeping, let p = sweepProgress {
            return .indexing(done: p.done, total: p.total)
        }
        if !hasRows, querying { return .finding }
        return .ready
    }

    /// What flipping the consent switch must DO (Q161): the Mac used to only ever turn it
    /// on, so consent could not be withdrawn. Pure so both Settings surfaces and the
    /// tests share one rule.
    enum ConsentAction: Equatable {
        /// Set the flag, fetch the model if missing, then sweep.
        case enable
        /// Clear the flag: sweeps stop and every semantic surface hides. The model and
        /// the on-disk index stay, so re-enabling is instant.
        case withdraw
        case none
    }

    static func consentAction(wasEnabled: Bool, nowEnabled: Bool) -> ConsentAction {
        switch (wasEnabled, nowEnabled) {
        case (false, true): return .enable
        case (true, false): return .withdraw
        default: return .none
        }
    }

    /// The failure line (C110, R58): a READY surface with no rows whose last
    /// lookup or sweep FAILED says "Connections unavailable" + the error, never
    /// "No connections yet". nil = show the honest state (rows, or empty).
    static func failure(state: RetrievalGate, hasRows: Bool, lastError: String?) -> String? {
        guard state == .ready, !hasRows, let err = lastError, !err.isEmpty else { return nil }
        return err
    }

    /// The user-facing strings, one copy — the device word is the only variable.
    enum Copy {
        static let modelMB = 295

        /// The summon control's label on BOTH note surfaces (iPad chrome band ·
        /// Mac note toolbar): a plain WORD — no ◨ glyph (it hid the meaning) and
        /// no count (capped at 7 it reads "7" forever ⇒ zero signal; Tuur
        /// 2026-07-24). Quiet → accent while the panel is up.
        static let summonLabel = featureName

        /// THE name of the feature everywhere it is named: the Settings switch on
        /// phone, iPad and Mac, the summon word, and the gate's CTA (Q161 — it used
        /// to be "Semantic journal index" in Settings and three other phrasings in
        /// the panel).
        static let featureName = "Connections"
        /// The Settings switch's label (same word as the panel).
        static let settingTitle = featureName

        static func gateBody(device: String) -> String {
            "Related notes, threads, and search by meaning — not just keywords. Runs fully on this \(device); nothing leaves the device. The language model is a one-time \(modelMB) MB download."
        }
        static let gateTitle = "Find connections between your notes"
        static let gateCTA = "Turn on \(featureName)"
        static let gateFootnote = "Downloads EmbeddingGemma · \(modelMB) MB"

        static let downloadingTitle = "Downloading model…"
        static func downloadingSub(fraction: Double) -> String {
            "\(Int(fraction * Double(modelMB))) / \(modelMB) MB · you can keep working"
        }

        static let preparingTitle = "Preparing model…"
        static let preparingSub = "Compiling for the Neural Engine —\na one-time step, then indexing starts"

        static let indexingTitle = "Building the index"
        static func indexingSub(done: Int, total: Int) -> String {
            "\(done) of \(total) notes · runs in the background,\npauses while transcribing"
        }

        static let findingTitle = "Finding connections…"
        static let findingSub = "Warming the on-device model —\nquick once it's loaded."

        /// A failed lookup's title; the error string rides below it.
        static let unavailableTitle = "Connections unavailable"

        static let emptyTitle = "No connections yet"
        static let emptySub = "As more notes touch this idea,\nits arc shows up here."
    }
}
