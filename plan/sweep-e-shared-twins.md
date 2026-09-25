# Sweep E — Shared/ + twin code (read-only, verified by reading source)

Scope: `Skrift_Native/Shared/` (14,496 lines, 113 files) + twin logic across
`SkriftMobile`/`SkriftDesktop`. Read `plan/parity.md` (sync asymmetries) and
`plan/perf-sweep.md` (perf, incl. Shared items P1–P7 already fixed/open) first —
cited below, not repeated. Every finding below was confirmed by reading the
actual code and grepping call sites; nothing here is a guess.

## Ranked findings

### 1. TWIN — Mac lock-visibility bypasses the shared privacy predicate — HIGH confidence
`Skrift_Native/SkriftMobile/Services/LockGate+Memo.swift:10-12` vs
`Skrift_Native/SkriftDesktop/Features/Shell/LockGate+PipelineFile.swift:6-9`.
The phone's `isLocked(_:)` calls `!NoteVisibility.contentVisible(locked:unlockedThisSession:)`
— the shared predicate in `Shared/Session/NoteVisibility.swift:11`, whose doc comment
says "every surface that can reveal a note's content... routes through this so a new
surface can't reintroduce the leak" (R88/C161/C213/C91). The Mac's `isLocked(_ pf:)`
instead reimplements the same boolean inline: `pf.locked && !isUnlocked(pf.id)` —
never calls `NoteVisibility`. Logically equivalent today, but the doctrine's own
claim ("every surface... routes through this") is already false, and the two copies
will silently diverge the next time the visibility rule gains a condition (e.g. a
grace period) on one side only.
**Fix:** `LockGate+PipelineFile.swift:8` → `!NoteVisibility.contentVisible(locked: pf.locked, unlockedThisSession: isUnlocked(pf.id))`. One-line change, matches the phone exactly.

### 2. TWIN — Mac re-warms the vocab booster on a synced word, phone doesn't — HIGH confidence
`Skrift_Native/SkriftMobile/Services/VocabularyCloudSync.swift:21-24` vs
`Skrift_Native/SkriftDesktop/App/VocabularyCloudSync.swift:63-69`. Both adapters wrap
the same shared `VocabularySyncCore.reconcile`. On `.adoptRemote` (a word synced in
from the other device, e.g. mid-session foreground), the Mac's adapter calls
`Task.detached { await VocabularyBooster.shared.prewarm(words: words) }` so the new
word boosts the next transcription immediately. The phone's adapter only logs
(`DevLog.log("vocab: adopted...")`) — it never calls
`VocabularyBooster.shared.prewarm`. The phone DOES prewarm once, but only from a
separate launch-time `.task` in `SkriftApp.swift:184-190` that reads
`CustomVocabularyStore.words()` once at cold launch. A word added on the Mac and
synced to an already-running phone session (via the same `.task` on
`SkriftApp.swift:209` foreground hook) is adopted into storage but the booster stays
stale until next relaunch — the exact "custom vocab never corrected" failure mode
`memory/project_vocab_booster.md` already fixed once (2026-06-13, "root cause was
booster never WARM").
**Fix:** add the same `Task.detached { await VocabularyBooster.shared.prewarm(words: words) }` to the `.adoptRemote` case in `SkriftMobile/Services/VocabularyCloudSync.swift:22-24`.

### 3. DEAD — `NamesStore.pruneOldTombstones` implemented + tested, never called — HIGH confidence
`Skrift_Native/Shared/Naming/NamesStore.swift:277-291`. Fully implemented (drops
`isDeleted` people past `maxAgeDays`, returns count) and unit-tested
(`SkriftDesktopTests/NamesTests.swift:181`), but grep across both app targets
(`SkriftMobile`, `SkriftDesktop`, all non-test code) finds zero call sites — no
launch/foreground sweep, no Settings action invokes it. Tombstones (deleted people,
kept for LWW merge) accumulate in `names.json` forever. This directly feeds
perf-sweep.md's already-flagged item #10 (`names.json` growing, re-decoded on every
access, "256-dim voice embeddings") — an unpruned tombstone list is pure dead weight
in that same file.
**Fix:** call it from one of the existing sweep chains (`NamesCloudSync.run`, or the phone's launch `.task` list in `SkriftApp.swift:108-203`) — matches the shape of the other nine sweeps already there.

### 4. SLOW — Vault tag scan recompiles a regex per file, up to 5000× per scan — HIGH confidence
`Skrift_Native/Shared/Pipeline/Tags/VaultTagScanner.swift:45` (`frontmatter(_:)`) and
`Shared/Pipeline/Tags/TagMatcher.swift:44` (`spokenHashtags(in:)`, called from
`VaultTagScanner.collectTags:34`). Both build a fresh `NSRegularExpression(pattern:)`
inline on every call; `collectTags` runs once per `.md` file inside `scan(root:maxFiles:)`'s
loop, capped at 5000 files. This is the identical anti-pattern `Sanitiser.swift`
already fixed once with `wordRegexCache` (comment at `Sanitiser.swift:737-739`:
"every process()/nameSpans() call used to build a fresh NSRegularExpression per
alias" — now `NSCache`-backed) — that fix was never applied here.
**Fix:** hoist both patterns to `private static let` (they're fixed strings, no per-call variation) in `VaultTagScanner.swift` and `TagMatcher.swift`.

### 5. SLOW — `SpeakerTurnStyle.turns` recompiles its header regex on every call, feeding the known Mac per-keystroke hot path — HIGH confidence
`Skrift_Native/Shared/Pipeline/SpeakerTurnStyle.swift:86`:
`guard let re = try? NSRegularExpression(pattern: SpeakerTranscript.headerPattern)`
— inline, not cached. `perf-sweep.md` §2 finding #1 (R90) already names
`SkriftDesktop/Features/Review/BodyTextView.swift:613` (`restyle(tv)`, called
**unconditionally on every keystroke, no debounce**) as the single worst perf item in
the app; that exact line calls `SpeakerTurnStyle.turns(in:people:)`. So every
keystroke in a Mac conversation note recompiles this regex from scratch — a concrete,
previously-unnamed contributor to R90 that lives in Shared/, not just the app-level
restyle cost already flagged.
**Fix:** `private static let headerRegex = try! NSRegularExpression(pattern: SpeakerTranscript.headerPattern)` in `SpeakerTurnStyle.swift`. Cheap, and it's the closest thing to a same-session quick win against R90 while the real fix (scope `restyle` to the edited range) is pending.

### 6. DEAD/half-wired — ePub DRM detection is computed, never surfaced to the user — MEDIUM confidence
`Skrift_Native/Shared/Pipeline/EPubParse.swift:308` (`evaluateDRM`) computes an
`EPubDRMVerdict` (`.none` / `.protected(reason:)`) on every ePub parse, stored on
`EPubBook.drm` (:513). Grep for `.drm`/`EPubDRMVerdict` across both app targets
(non-test) finds exactly one reader: `SkriftDesktop/Features/Shell/RunFile.swift:633`,
a debug/headless-harness log line (`log("book: ... drm \(book.drm)")`). Nothing in
either app's real UI checks it — a DRM-protected book is imported and fed to
alignment/parsing like any other, with no warning, on either platform. Given this
project's own locked doctrine ("better no info than bad info",
`memory/feedback_no_bad_information.md`), a DRM book silently producing garbage
alignment is the failure mode that doctrine exists to prevent.
**Fix:** either surface `book.drm` as an import-time warning in the Books-tab importer (both apps), or if this was deliberately deferred, note it in SPEC.md rather than leaving it silently computed-and-discarded.

### 7. INELEGANT — `Sanitiser.swift` bundles 4 distinct jobs in one 781-line enum — MEDIUM confidence
`Skrift_Native/Shared/Naming/Sanitiser.swift` — the largest file in `Shared/Naming/`,
one `enum Sanitiser` (line 27) with four MARK-separated sections that don't share
much beyond the `Person` type: tiered name-span detection over raw transcripts
(`:206`), conversation-aware/speaker-attributed linking (`:328`), review-time
unlinking (`:552`), and cross-cutting helpers incl. its own regex cache (`:681`).
Each section is large enough to be its own file — `BodyV2` already got this split
treatment (6 focused files: `BodyV2`, `BodyV2Legacy`, `BodyV2Marker`, `BodyV2Text`,
`BodyV2Thumbnail`, `BodyNormaliseMigration`) for a comparably-sized concern;
`Naming/` has not.
**Fix:** split along the existing MARK boundaries — `NameLinking.swift`, `ConversationLinking.swift`, `NameUnlinking.swift`, keep `Sanitiser` as a thin facade. No behavior change, lower risk of an edit to one tier accidentally touching another.

### 8. SLOW — `Sanitiser.nonProseRanges` recompiles 2 regexes on every call — LOW-MEDIUM confidence (low value)
`Skrift_Native/Shared/Naming/Sanitiser.swift:719-720`: the code-fence and inline-code
patterns (`` ```[\s\S]*?``` `` and `` `[^`\n]+` ``) are built inline inside a
`for pattern in [...]` loop, on every `nonProseRanges(in:)` call — called from 6 call
sites in the same file (`:173,193,225,460,481,502`), each once per name-link pass
(not per keystroke, so lower impact than #4/#5, but the same easy fix).
**Fix:** two `private static let` regexes instead of the inline loop.

## Not findings — correctly-factored code worth noting so it isn't re-flagged later
- `Names/Vocab/PolishPrompts CloudSync` per-app adapters (`SkriftMobile/Services/*CloudSync.swift` vs `SkriftDesktop/App/*CloudSync.swift`) look like twins by filename but are legitimately different: each wraps a genuinely different local store (UserDefaults-backed `CustomVocabularyStore` vs `AppSettings`/SwiftData) around the SAME shared `*SyncCore.reconcile` — this is the intended shape, not drift (except finding #2's one missing line).
- `SignificanceCircles.swift` (mobile 61 lines / desktop 69 lines) — same filename, but both are thin per-platform style structs (`ThreeBallStyle.phone` / `.mac`) over the one shared `ThreeBallImportanceView` + `ThreeBallScale`. Model for how a twin-by-name should look.
- `MemoLifecycle.backlinkedIDs`/`.partition` (Shared, O(n) single-pass, explicit doc warning "never scan per row") are correctly written — the corpus-rescan-per-row bug perf-sweep.md flags (P1, #2, #5) is a caller misuse in `MemosListView.swift`/`MemoDetailView.swift`, not a Shared defect.
