# 📖 spike 6 — productize alignment (lane batch 2026-07-21C)

**BASE MARKER.** If this file exists in your worktree your base is correct; if MISSING, STOP
and `git reset --hard main`, re-verify. Never recreate it by hand.

Conductor: Fable. Executors: Sonnet lanes, one worktree each.
**Operating rules = `LANE_PLAYBOOK.md` (repo root) — read FIRST, follow exactly.**
Spec of record: `backlog.md` "📖 ePub ↔ audiobook alignment" (all decisions LOCKED; spikes 1–5
DONE, real-pair verdict GO — f0 ALIGNED 86.9%/95.5% monotonic, wrong files REJECTED).
ALL WORK IS PHONE-SIDE (`Skrift_Native/SkriftMobile/`). The desktop learns nothing new.

**Conductor pre-shipped (already on your base — build against, never edit):**
`Audiobook.epubFilename` + `Audiobook.epubChapters` (+ `effectiveChapters` precedence
ePub > detected > embedded) · ZIPFoundation 0.9.20 in the iOS APP target only ·
`Shared/Pipeline/EPubParse.swift` + `Shared/Pipeline/AlignmentCore.swift` (spikes 4–5;
compiled into the app module — no import statement needed, they're same-module types).

## Ownership map (lane → files). Writes outside your set are FORBIDDEN.

**LANE_CORE** (brief: `LANES-2026-07-21C/LANE_CORE.md`) — sidecar + runner + triggers + sync:
- NEW: `Skrift_Native/SkriftMobile/Services/Audiobooks/BookAlignment.swift`
- EDIT: `Skrift_Native/SkriftMobile/Services/Audiobooks/BookTranscriptionJob.swift` (trigger line only)
- EDIT: `Skrift_Native/SkriftMobile/Services/Audiobooks/AudiobookSession.swift` (retro-hook line only)
- EDIT: `Skrift_Native/SkriftMobile/Services/Audiobooks/AudiobookCloudSync.swift` (alignment mirror of the transcript block)
- EDIT: `Skrift_Native/SkriftMobile/Models/AudiobookSyncModels.swift` (`alignmentSignature` additive field only)
- NEW: `Skrift_Native/SkriftMobile/SkriftMobileTests/BookAlignmentTests.swift`

**LANE_UI** (brief: `LANES-2026-07-21C/LANE_UI.md`) — true-text surfaces + attach UX:
- NEW: `Skrift_Native/SkriftMobile/Features/Audiobooks/AlignedSentenceSource.swift`
- EDIT: `Skrift_Native/SkriftMobile/Features/Audiobooks/ReadAlongView.swift`
- EDIT: `Skrift_Native/SkriftMobile/Features/Audiobooks/MergedCaptureView.swift`
- EDIT: `Skrift_Native/SkriftMobile/Features/Audiobooks/AudiobookLibraryView.swift`
- NEW: `Skrift_Native/SkriftMobile/SkriftMobileTests/AlignedSentenceSourceTests.swift`

Everything else READ-ONLY per the playbook (incl. `QuoteCaptureProcessor.swift`,
`BookTranscriptStore.swift`, `Audiobook.swift`, the two Shared cores).

## Cross-lane seams — the pinned contract (exact spelling; LANE_CORE implements, LANE_UI consumes)

```swift
// In BookAlignment.swift (LANE_CORE):
struct AlignedSentence: Codable, Equatable, Sendable {
    var text: String            // published book text, display-ready
    var start: TimeInterval     // FILE-LOCAL seconds
    var end: TimeInterval
    var wordStart: Int          // transcript word-index range (ASR fallback splice)
    var wordEnd: Int            // exclusive
    var confidence: Double      // fraction of this sentence's book words directly matched
    var words: [WordTiming]     // book words with per-word times (karaoke)
    var sourceFile: String?     // ePub spine path this sentence came from
}
struct ChapterMark: Codable, Equatable, Sendable { var title: String; var sentenceIndex: Int }
struct FileAlignment: Codable, Equatable, Sendable {
    var schema: Int             // 1
    var fileIndex: Int
    var transcriptSignature: String   // "<Int(coveredUpTo)>:<wordCount>" at alignment time
    var epubSignature: String         // SHA-256 hex of the ePub bytes
    var verdict: String               // AlignmentCore.Verdict.rawValue
    var chapterMarks: [ChapterMark]
    var sentences: [AlignedSentence]
}
final class BookAlignmentStore {
    init(directory: URL)                                        // the audiobook library dir
    func fileAlignment(bookID: UUID, fileIndex: Int) -> FileAlignment?
    func save(_ fa: FileAlignment, bookID: UUID) throws
    /// Fresh = fa.transcriptSignature matches the CURRENT transcript sidecar's
    /// "<Int(coveredUpTo)>:<wordCount>" for that file.
    func isFresh(_ fa: FileAlignment, bookID: UUID, fileIndex: Int, audioURL: URL) -> Bool
}
enum BookAlignmentRunner {
    struct AttachSummary: Equatable { var alignedFiles: Int; var rejectedFiles: Int; var totalFiles: Int }
    /// Copy the picked file into the book folder, set epubFilename, align every
    /// covered transcript file, write sidecars, derive epubChapters, save the book.
    static func attach(bookFileAt url: URL, bookID: UUID) async throws -> AttachSummary
    /// Cheap no-op-guarded re-align (no ePub attached / sidecars fresh ⇒ returns fast).
    static func alignIfNeeded(bookID: UUID) async
}
```
- Sidecar file on disk: `alignment_f<n>.json` beside `transcript_f<n>.json` in the book folder.
- CloudKit record name: `ab_<bookID>_al<n>` (transcripts use `_t<n>`; audio `_a<n>`).
  `AudiobookSyncRecord.alignmentSignature: String = ""` — additive with default (schema-safe).
- `WordTiming` = the existing app type (word/start/end) — reuse, don't redeclare.
- ZIPFoundation is imported ONLY inside `BookAlignment.swift`. Never in tests, never in Features/.
- LANE_UI builds against this contract verbatim; if it feels insufficient — ESCALATE, don't improvise.
- Per-sentence fallback threshold (both lanes quote it): confidence < 0.5 ⇒ that sentence
  renders ASR words (`ft.words[wordStart..<wordEnd]`), not book text.
