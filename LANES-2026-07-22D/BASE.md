# 📖 multi-text + "Book text" sheet — lane batch 2026-07-22D

**BASE MARKER.** If this file exists in your worktree your base is correct; if MISSING, STOP
and `git reset --hard main`, re-verify. Never recreate it by hand.

Conductor: Fable. Executors: Sonnet lanes, one worktree each.
**Operating rules = `LANE_PLAYBOOK.md` (repo root) — read FIRST, follow exactly.**
Signed spec: **`Skrift_Native/SkriftDesktop/mocks/book-text-sheet.html` VARIANT B**
(timeline-first sheet; Tuur 2026-07-22: "yess. ur recommendation") — the attach entry points
route straight to the sheet; variant C's options-screen row is NOT in this batch.
Design record + semantics: backlog.md 📖 "NEXT CHUNK — multi-text per audiobook".
Settled semantics (do not re-derive): one omnibus audiobook holds MANY texts; alignment is
per-file/per-span; when two texts claim the same span the higher-confidence sentence wins;
NOTHING is ever deleted (un-narrated text gets no time; unmatched audio keeps ASR).

**Conductor pre-shipped (on your base — build against, never edit):**
`EPubBook.title` (OPF dc:title, nil→filename fallback) ·
`Audiobook.epubFilenames: [String]?` + `attachedTextFilenames` accessor (legacy
`epubFilename` stays written with the FIRST text) · everything from batches B/C.

## Ownership map (lane → files). Writes outside your set are FORBIDDEN.

**LANE_CORE2** (brief: `LANES-2026-07-22D/LANE_CORE2.md`) — schema 3 multi-source:
- EDIT: `Skrift_Native/SkriftMobile/Services/Audiobooks/BookAlignment.swift`
- EDIT: `Skrift_Native/SkriftMobile/Services/Audiobooks/AudiobookCloudSync.swift` (signature part only, see brief)
- EDIT: `Skrift_Native/SkriftMobile/SkriftMobileTests/BookAlignmentTests.swift`

**LANE_UI2** (brief: `LANES-2026-07-22D/LANE_UI2.md`) — the sheet:
- NEW: `Skrift_Native/SkriftMobile/Features/Audiobooks/BookTextSheet.swift`
- EDIT: `Skrift_Native/SkriftMobile/Features/Audiobooks/AudiobookLibraryView.swift`
- NEW: `Skrift_Native/SkriftMobile/SkriftMobileTests/BookTextSummaryDisplayTests.swift`

Everything else READ-ONLY per the playbook (incl. `AlignedSentenceSource.swift`,
`ReadAlongView`, `MergedCaptureView` — the read surfaces are UNTOUCHED this batch;
they already consume merged sidecars transparently).

## Cross-lane seams — the pinned contract (LANE_CORE2 implements, LANE_UI2 consumes)

```swift
// In BookAlignment.swift (LANE_CORE2):

/// One attached text's alignment outcome for ONE audio file (schema 3).
struct AlignmentSource: Codable, Equatable, Sendable {
    var textFilename: String        // the attached file in the book folder
    var title: String?              // EPubBook.title at alignment time (display)
    var verdict: String             // AlignmentCore.Verdict.rawValue
    var coverage: Double            // Result.coverageBook for THIS file (0…1)
}
// FileAlignment (schema 3) gains:  var sources: [AlignmentSource] = []
// AlignedSentence gains:           var textFile: String? = nil   // which attached text it came from

/// The sheet's data — one call, pure assembly from sidecars + the book record.
struct BookTextSummary: Equatable, Sendable {
    struct PerText: Equatable, Sendable {
        var filename: String
        var title: String?                       // nil → caller shows filename
        var coveredSeconds: TimeInterval         // sum of its GLOBAL spans
        var spans: [ClosedRange<TimeInterval>]   // GLOBAL book time, merged/sorted
        var fileNumbers: [Int]                   // 1-based audio files it aligned (verdict aligned)
    }
    var perText: [PerText]                       // attach order (attachedTextFilenames order)
    var totalCoveredSeconds: TimeInterval
    var bookDuration: TimeInterval
}
extension BookAlignmentRunner {
    /// Pure read — no alignment work. Safe from MainActor.
    static func textSummary(bookID: UUID) -> BookTextSummary?
    /// Detach ONE text: remove it from the book record + strip its sentences/marks
    /// from the sidecars + re-derive chapters. Other texts untouched.
    static func removeText(filename: String, bookID: UUID) async
}
// attach(bookFileAt:bookID:) keeps its name/signature and becomes ADDITIVE
// (appends to epubFilenames; re-attaching the SAME filename replaces that text).
```
- Schema 3 gate: v2 sidecars read as missing → full re-align of every attached text on next
  open (`alignIfNeeded` iterates `attachedTextFilenames`).
- Collision rule at sentence level: overlapping-in-time sentences from different texts →
  higher `confidence` wins, tie → earlier attach order. Deterministic.
- The bar's segments in the sheet = `PerText.spans` drawn over `bookDuration` — REAL spans,
  never per-file approximations (the mock's stated behavior).
- Colors: text N uses accent for N=0, tan for N=1, then cycle (`Theme` tokens); grey =
  uncovered. No new color constants — reuse Theme.
- LANE_UI2 builds against this contract verbatim; insufficient → ESCALATE, don't improvise.
