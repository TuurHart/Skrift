# Bug-shape sweep (SPEC.md C248) — 2026-09-22

Scope: `Shared/`, `SkriftDesktop/Pipeline/`, `SkriftDesktop/App/MacCloud*.swift`,
`SkriftDesktop/Engines/EnhancementService.swift`, `SkriftMobile/Services/`,
`SkriftMobile/Features/Recording/MemoSaver.swift`, `SkriftMobile/Features/MemoDetail/NoteBodyView.swift`
(202 files). For shape 1 the narrow patterns (`return []`, `?? []`, `?? ""`) were triaged
across all 202; the wide patterns (`.first`, `try?`, `return nil`, `else { return }`) were
triaged against a 53-file "core" subset (sync/ingest/export/polish/consent — grep `-i
"sync|ingest|export|polish|reconcil|cloud|MemoSaver|NotesRepository|Consent|Trash|Compiler"`
over the file list) and spot-checked elsewhere. Every CANDIDATE below was verified by reading
the code path, not from memory.

---

## 1. THE SILENT EMPTY RESULT

Greps (core 53 files): `return \[\]` → 2 · `?? \[\]` → 34 · `?? ""` → 28.

| Hit | Verdict | Note |
|---|---|---|
| `MemoPhotoMaterializer.swift:57` | SAFE | `have=[]` on bad manifest JSON forces a rewrite (`want != have`), self-healing. |
| `ArrivalPath.swift:64` | SAFE | Trivial `!urls.isEmpty` guard, not a failure path. |
| `NotesRepository.swift` ×11, `IngestService.swift` ×2, `VaultExporter.swift` ×2, `CompilerBridge.swift`, `MemoCloudIngest.swift:115` | SAFE (grouped) | `(try? context.fetch(...)) ?? []` — SwiftData fetch throws only on a bad predicate/schema (a build-time bug caught in dev), not on a data-dependent runtime condition. Directory-listing `try?` pairs are similar. |
| **`MemoCloudReconciler.swift:59`** | **CANDIDATE** | see below |
| **`IngestService.swift:180`** | **CANDIDATE** | see below |
| **`AudiobookBookmarkSyncCore.swift:41`** | **CANDIDATE** | see below |
| `MacMemoAuthor.swift`, `MemoCloudUpdate.swift`, `UploadService.swift`, remaining `?? ""` hits | SAFE | Plain optional→empty-string coalescing for display/comparison of fields that are legitimately nil (no transcript yet); not swallowing a fallible operation. |

### CANDIDATE — `MemoCloudReconciler.sweep`, line 59
```swift
let memos = MemoDuplicates.canonicalRows(
    (try? cloudContext.fetch(FetchDescriptor<Memo>())) ?? [])
```
This is the top of the Mac→CloudKit reconcile loop — the one thing the sweep exists to run.
Every per-memo ingest failure *inside* the loop is caught and logged (`ingestFailures`,
`Logger(...).error(...)`, lines 167–170) and even a rated-but-rowless memo gets a dedicated
`stranded` counter + log line (lines 163–165). But this outer fetch has none of that: if it
throws, `memos = []`, the loop body never runs, and `sweep` returns a plain `SweepOutcome()`
— `created: 0, updatedIDs: [], ingestFailures: 0, stranded: 0` — indistinguishable from "cloud
had nothing new." No log line fires anywhere in this path.
- **What the user does:** nothing wrong — a transient CloudKit-store fetch error (migration in
  flight, container hiccup) on any sweep.
- **What they get:** the Mac silently stops picking up new phone memos, forever-looking like
  "in sync," with zero diagnostic trail — the exact class of bug `stranded` was built to catch
  on 2026-08-19, but one layer higher.
- **What they should get:** the failure logged (`Logger(...).error`) same as the per-memo path.
- **Fix location:** `Skrift_Native/SkriftDesktop/Pipeline/Ingest/MemoCloudReconciler.swift:59`.
- **SPEC clause:** no existing clause covers this outer fetch; C248 itself requires a citation
  or a BUGS.md row — recommend the row.

### CANDIDATE — `IngestService.ingestNote`, line 180
```swift
try FileManager.default.copyItem(at: url, to: dest)
var content = (try? String(contentsOf: dest, encoding: .utf8)) ?? ""
let title = Self.appleNoteTitle(content, fallback: ...)
content = Self.importAttachments(content: content, ...)
try? Data(content.utf8).write(to: dest)
```
The file is copied, then immediately re-read; if that read fails (odd encoding, filesystem
hiccup right after the copy — plausible for a large Apple Notes export with embedded
attachments), `content` becomes `""`. Title falls back to the filename stem (fine), but
`importAttachments` then runs on empty text and the final `try? Data(content.utf8).write`
**overwrites the just-copied `dest` with an empty file** — no error, no retry, no log.
- **What the user does:** imports an Apple Notes `.md` export.
- **What they get:** a note that ingests successfully (no thrown error) but is permanently
  blank — a husk.
- **What they should get:** per C75 ("A share with an empty payload never saves a husk;
  failures are honest"), either the read error propagates or gets logged and the note is
  marked failed, never silently blanked.
- **Fix location:** `Skrift_Native/SkriftDesktop/Pipeline/Ingest/IngestService.swift:180`.
- **SPEC clause:** C75, C76 (Apple Notes import).

### CANDIDATE — `AudiobookBookmarkSyncCore.reconcile`, line 41
```swift
let items = (try? JSONDecoder().decode([AudiobookBookmark].self, from: newest.itemsBlob)) ?? []
return .adoptRemote(items: items, modifiedAt: newest.modifiedAt)
```
The caller (`AudiobookCloudSync.swift:293`) applies this outcome unconditionally:
`bookmarkStore.adoptSynced(items, stamp: ts, bookID: bookID)` — an unconditional overwrite of
the local bookmark list, plus adopting the newer stamp. If `itemsBlob` fails to decode (a
future-format blob, a partial CloudKit sync, corruption), `items = []` and the device's real
bookmarks for that book are silently replaced with nothing; the log line even reads as benign
("adopted 0 bookmarks for X"). Because the stamp is also adopted, the next reconcile treats
the two devices as already agreeing — the wipe never surfaces and never self-heals.
- **What the user does:** nothing wrong — any transient blob corruption/version-skew on sync.
- **What they get:** that book's bookmarks vanish on this device, silently, permanently.
- **What they should get:** a decode failure should skip the adopt (treat as `.noop`) and log
  an error, not overwrite real data with an empty list.
- **Fix location:** `Skrift_Native/SkriftMobile/Services/Audiobooks/AudiobookBookmarkSyncCore.swift:41`
  (caller: `AudiobookCloudSync.swift:293`).
- **SPEC clause:** none (audiobooks are out of the rewrite, CLAUDE.md); recommend a BUGS.md row.
- **Note (ties to shape 7):** `VocabularySyncCore`/`PolishPromptsSyncCore` — the otherwise
  identical sibling sync engines — carry their payload as typed SwiftData properties
  (`[String]`, plain `String`s), not a hand-encoded blob, so they have no equivalent
  decode-failure path. The audiobook-bookmark carrier is the odd one out, and it's the
  fragile one.

---

## 2. TWO LISTS WHOSE GAP NOBODY IS IN

Checked: `WayOutRules.swift` (`unpipelined` / `stranded` / the fading conveyor) and
`NoteConsent.swift`.

- **SAFE.** `NoteConsent.isRated` is the single predicate every caller in scope routes
  through (`grep -rn "significance == 0|significance != nil|..."` over Shared/Desktop-Pipeline/
  Mobile-Services found no bypass — the one hand-rolled `significance == 0` left is in
  `SkriftDesktop/Features/Shell/RunFile.swift:797`, outside this sweep's scope, a headless
  test-harness path).
- `WayOutRules.unpipelined` (quiet rows) and `WayOutRules.stranded` (rated+rowless) are
  explicitly proven disjoint-and-covering in their own doc comments — `stranded`'s docstring
  names the exact 2026-08-19 incident this sweep is checking for and states the invariant
  ("a memo that is rated but rowless renders in neither... every known cause is fixed at the
  ingest end; this is the standing floor"). Fading memos are excluded from `unpipelined` by
  design and documented as living on the conveyor instead (one-home law, 2026-07-21) —
  not independently re-verified that the conveyor's fading list is itself rated/unrated-complete,
  flagged below as unverified.
- **Unverified (time-boxed out):** whether `MemoLifecycle.isFading`'s consumers (the conveyor)
  cover both rated and unrated fading memos with no third gap. Worth a follow-up pass.

---

## 3. THE ECHO GUARD THAT REFUSES THE ONLY COPY

Grep: `enhancedByDeviceID != |enhancedByDeviceID ==` → 2 in-scope guard sites (plus
`recordingDeviceID ==` in `MacMemoAuthor.swift:124`).

| Hit | Verdict | Note |
|---|---|---|
| `MemoCloudUpdate.swift:63` | SAFE | `guard isFreshRow \|\| e.enhancedByDeviceID != thisDeviceID else { return nil }` — the `isFreshRow` carve-out is the exact fix for this exact shape, landed 2026-08-19 per the file's own doc comment ("skipping it as 'my own echo' means the note surfaces RAW forever ... the store held the copy-edit, the open note showed the blob"). |
| `MacCloudWriteBack.swift:102` | SAFE | Genuine LWW compare (`existing.enhancedAt > now`), not a bare device-echo check; `existing == nil` (no local copy) falls through and writes normally. |
| `MacMemoAuthor.swift:124` | SAFE | Device-scoping by design (only reflect a Mac's own recording's transcript); if the memo row doesn't exist yet, `.first` returns nil and this sweep-companion simply retries next sweep — no permanent loss, just delay. |

No candidates in scope for this shape.

---

## 4. ONLY THE FIRST ONE

Grep: `inputItems\.first|providers\.first|attachments\.first|itemProviders\.first|results\.first|urls\.first|images\.first` → 9 hits app-wide (excluding vendored MLX/FluidAudio packages).

| Hit | Verdict | Note |
|---|---|---|
| `SharePayloadLoader.swift:77` `context.inputItems.first` | SAFE | Documented + correct: "The extension handles one item at a time (activation rule: max 1 of each type)" — iOS always hands a share extension one `NSExtensionItem` with N attachments nested inside; all multi-select handling happens on `item.attachments`, which this file iterates fully (`.filter`, not `.first`, for audio/image collection). |
| `SharePayloadLoader.swift` `attachments.first(where:)` ×4 | SAFE | Each finds the (at most one, per the activation rule) provider of a *specific* type — not dropping siblings. |
| `VideoImportPicker.swift:50` `results.first` | SAFE | `config.selectionLimit = 1` (line 30) — the only `PHPickerViewController` in the app; no wider `selectionLimit` anywhere else in scope. |
| `MemoSaver.swift:446,703,708` `.loadTracks(...).first` | SAFE | Single-audio-track assets by construction (recorded/appended clips). |
| `CaptureInboxDrainer.swift:219` `entry.audioRecordedAts?.first` | SAFE | Documented: "Oldest clip's original date (index-aligned array) → the memo's recordedAt seed" — only the *date* uses first; all clips (`temps`) are still copied and imported. |
| `NoteBodyView.swift`, `LinkEnrichment.swift`, `PlaceLink.swift` `.first`/`firstMatch` | SAFE | Single-touch handling, single regex match, single query-item lookup — not multi-input contexts. |

No candidates.

---

## 5. THE WAITING THING TURNED INTO A DIFFERENT THING

Checked `AssetMaterializer.swift` (blob-not-yet-synced vs missing), `WayOutRules.isQuietLocalTake`
(unrated Mac take vs pipelined), `MemoCloudReconciler`'s `stranded` (rated-but-media-not-synced
vs deleted — this is the shape's own textbook case, already fixed with `strandedLine`: "waiting
for its audio" instead of a false "not queued" or a vanish).

- **SAFE.** `AssetMaterializer.materializeMissing`/`captureMissing` re-run on every launch +
  foreground and only act on *current* file-existence state — a still-syncing blob is simply
  skipped this pass, not reinterpreted, and picked up automatically next pass.
- **SAFE.** `WayOutRules.isQuietLocalTake` explicitly carves out the errored case (`pf.error ==
  nil`) so a genuinely-waiting take and a *failed* take are kept visibly distinct (comment:
  "an errored take... KEEPS its queue row + Error chip even while unrated").
- Did not have budget to fully re-walk `DiarizationStore`/`DiarizationService` (mobile) or
  `DiarizationSidecar` (desktop) for a not-yet-diarized-treated-as-no-speakers case — flagged
  unverified, worth a follow-up pass given this shape's history.

---

## 6. ONE-WAY PATHS

Grep: files touching `wordTimings|diarization|Diarization` → 32 in scope.

- **KNOWN, already tracked — not a new finding.** `MacMemoAuthor.swift:92` (a Mac recording's
  `Memo` is authored with audio only; `wordTimings`/diarization never ride along) is
  pre-registered as **R34** in `SPEC.md:1096`, cited in the same commit series this worktree
  starts from (`ca8282ab tests: RoundTripParityTests ... R34 pinned as an expected failure`).
  Confirmed still true by reading `MacMemoAuthor.author()` (lines 59–95): the `Memo` init
  carries no `wordTimings` param and the row-companion `MemoAsset(kind: .audio, ...)` is the
  only asset inserted.
- Did not have budget to independently re-derive the full carrier map (every synced field ×
  every device) that C247's parity table calls for — that's a separate, larger exercise
  (`plan/parity.md`), not attempted here.

---

## 7. TWIN COPIES

Verified pairs (read both sides, not just grepped):

| Pair | Agree? | Note |
|---|---|---|
| `EnhancementService.editProse` (desktop) vs `PolishEscrow.editProse` (mobile) | Yes | Both: link-escrow → image-marker-strip → LLM → reinsert → reattach, same truncation/lostTooMuch guards (desktop inline; mobile's live one level up in `MLXPolishEngine.copyEditGenerate`, which round-trips through the same reinsert/reattach on the unedited stripped text, so the output is byte-equivalent). Desktop additionally logs paragraph counts (`paragraphs` logger) — a diagnostics-only gap, not a behavior drift. |
| `VocabularySyncCore` / `PolishPromptsSyncCore` / `AudiobookBookmarkSyncCore` (whole-list-LWW siblings) | **No — see shape 1** | Vocabulary/PolishPrompts carry typed SwiftData fields (no decode step); AudiobookBookmarks hand-encodes/decodes a JSON blob with a swallowed decode failure. Same algorithm, different robustness. |
| **`CompilerBridge.compilerInput.voice` (desktop) vs `MemoExporter.compilerInput.voice` (mobile)** | **No — CANDIDATE** | see below |
| `DiarizationSidecar` (desktop) vs `DiarizationStore`/`DiarizationService` (mobile) | Not verified | out of budget this pass. |
| title ladders / thumbnail rules / date ladders | Not verified | out of budget this pass — `WayOutRules.displayTitle` (desktop) vs `Memo.displayTitle` (mobile, per `WayOutRules`'s own comment citing `MemoDisplay.swift`) look structurally identical (title → first non-empty transcript line, marker-stripped, 80-char clip → source-kind fallback) on a read of both, but not diffed byte-for-byte. |

### CANDIDATE — the `voice:` frontmatter ladder disagrees between apps
`CompilerInput.voice` (`Shared/Export/CompilerInput.swift:19-27`) is a hard archive contract:
*"cleaned means grammar and punctuation ONLY — his words, his order, diffable against the raw
capture"* (SPEC C131, `.claude/rules/portfolio.md`).

Desktop (`CompilerBridge.swift:73-75`, inside `compilerInput`):
```swift
voice: (sourceType != .audio || path.isEmpty) ? .written
    : ((enhancedCopyedit ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
       ? .raw : .cleaned)
```
— `.cleaned` iff `enhancedCopyedit` (the actual polish text) is non-empty. This matches the
Compiler's own body precedence (`sanitised ?? enhancedCopyedit ?? transcript`).

Mobile (`MemoExporter.swift:63-90`):
```swift
let enh = (enhancement?.hasContent == true) ? enhancement : nil
let baseBody: String = {
    if let c = enh?.copyedit, !c...isEmpty { return c }
    return capture ? (memo.annotationText ?? "") : (memo.transcript ?? "")
}()
...
voice: memo.audioFilename.isEmpty ? .written : (enh != nil ? .cleaned : .raw)
```
`enh != nil` iff `MemoEnhancement.hasContent` — which is `copyedit` **OR** `title` **OR**
`summary` non-empty (`MemoEnhancement.swift:57-61`), deliberately loosened by the 2026-08-26
fix (`isProcessed`/`hasContent` split, memory `project_export_destinations`) so a
processed-but-textually-unchanged note isn't miscounted as unprocessed.

That loosening now leaks into `voice`: a memo whose Mac polish produced only a title/summary
(model judged the transcript needed no rewrite, or hit the same "no content" case the
2026-08-26 fix was about) has `enh.copyedit` empty → `baseBody` falls back to the **raw**
transcript (line 66-69) → but `enh != nil` is still true → `voice` ships as **`.cleaned`**.
- **What the user does:** exports a note whose Mac polish set a title/summary but left the
  transcript's own wording untouched (a real, not-rare case per the note's own doc comments).
- **What they get:** an archive-bound file whose body is byte-identical to the raw transcript,
  labeled `voice: cleaned` — breaking C131's own check ("no word of the cleaned body is absent
  from the raw body" is trivially true here, but the *label* now asserts a copy-edit pass ran
  when the shipped text is unedited, misleading any downstream tooling/reader relying on the
  voice key).
- **What they should get:** `voice: .cleaned` iff `enh?.copyedit` is what's actually in the
  body — i.e. gate on the same condition `baseBody` uses, not on `hasContent`.
- **Fix location:** `Skrift_Native/SkriftMobile/Services/Export/MemoExporter.swift:90`
  (compare desktop's `CompilerBridge.swift:73-75` for the reference logic).
- **SPEC clause:** C131 (voice: vocabulary), C247 (parity tables — an "empty cell" here is the
  desktop/mobile voice-ladder cell disagreeing).

---

## 8. THE FALLBACK THAT RETURNS THE WRONG INPUT

Grep (Engines + Polish): `keeping the unedited body|falling back to the unedited|return text$|return transcript$` → 14 hits.

- **SAFE, both apps.** `EnhancementService.editProse`'s `text` parameter is the pre-strip
  original (link-syntax and image markers intact); every failure branch (`looksTruncated`,
  `lostTooMuch`, lost memo-link title) returns that same `text`, never the locally-stripped
  `input`/`stripped` variable. Verified by reading the full function (lines 85-120): the
  stripped/anchor variables never escape as a fallback value.
- **SAFE, mobile.** `PolishEscrow.editProse` mirrors this (`return text` at line 49, same
  shape). `MLXPolishEngine.copyEditGenerate`'s own truncation/lostTooMuch fallback
  (`return input`, lines 108/112) looks one layer lower — but `input` there is *its own*
  function parameter (the already-stripped text `PolishEscrow.editProse` handed it), and the
  unmodified value flows back up through the same reinsert (`ImageMarkerReinsert.reinsert`)
  + reattach (`MemoLinkSyntax.reattach`) steps as the success path, restoring markers/links
  losslessly since nothing changed underneath them. Functionally equivalent to the desktop's
  single-layer fallback, just factored differently. (This is the shape the task brief flagged
  as "known: the iPad truncation fallback returns marker-stripped text" — read fresh here, not
  from memory — and as currently written it is NOT reproducible: the marker-stripped text never
  ships un-reinserted.)

No candidates.

---

## 9. THE UNPINNED DEPENDENCY

Grep: `revision:|branch: "main"|ModelConfiguration\(` (excluding `build-dev/` vendored
checkouts) → 32 hits.

- Both engines pin via `ModelConfiguration(id: modelRepo, revision:
  PolishPrompts.revision(for: modelRepo))` (`EnhancementService.swift:36`,
  `MLXPolishEngine.swift:171`) — this is the fix from the 2026-08-12 iPad-polish incident
  (memory `project_ipad_polish_fix`: "the MODEL was the one unpinned dependency").

### CANDIDATE — the pin only covers the default model repo
```swift
// PolishPrompts.swift:44-45
static func revision(for repo: String) -> String {
    repo == defaultModelRepo ? defaultModelRevision : "main"
}
```
`repo` is `settings.enhancementModelRepo`, a **free-text field** in Settings
(`SettingsView.swift:160`, `textRow("Model (HuggingFace repo)", \.enhancementModelRepo)`),
defaulting to `PolishPrompts.defaultModelRepo` (`AppSettings.swift:31`) but editable to
anything. The moment it's anything else, `revision(for:)` falls through to the literal string
`"main"` — the exact floating-dependency failure mode already diagnosed once app-wide (each
device freezes whatever HF `main` happens to be on its own download day).
- **What the user does:** types any alternate HuggingFace repo into Settings → "Model
  (HuggingFace repo)" — e.g. to try a different Gemma checkpoint.
- **What they get:** that model is no longer revision-pinned; re-downloading later (a fresh
  install, a cache clear, a second device) can silently fetch a different model under the
  same repo string, reproducing the 2026-06→07 two-model-drift bug this pin was built to kill
  — with no warning anywhere in the UI.
- **What they should get:** either the field is removed/hidden (desktop-only debug affordance?),
  or a custom repo still pins to *some* explicit revision (fetched once, cached, warned if it
  isn't the default).
- **Fix location:** `Skrift_Native/Shared/Pipeline/PolishPrompts.swift:44-45`; UI surface
  `Skrift_Native/SkriftDesktop/Features/Settings/SettingsView.swift:160`.
- **SPEC clause:** C28 ("ONE model everywhere ... revision pinned"), C167 ("Every engine and
  the model are revision-pinned; a pin bump is its own commit").
- **Note:** mobile has no equivalent Settings exposure found (`enhancementModelRepo` greps
  came back desktop-only) — this is a desktop-only hole.

---

## 10. STATE THAT ONLY MOVES ON A PATH THAT DOESN'T ALWAYS RUN

Grep: `processedAt\s*=|keptAt\s*=|editedAt\s*=|transcriptMarkersInjected\s*=|syncStatus` → 28 hits.

| Flag | Writers checked | Verdict |
|---|---|---|
| `MemoEnhancement.processedAt` | `MacCloudWriteBack.swift:111` (`if passRan { ... }`), `PolishCenter.swift:377` (full pass) | SAFE — `PolishCenter.runRedo` (single-part redo, line 200-216) does NOT set it, but redo is only offered when a polish already exists (menu gate, line 201-203 comment), so `processedAt` is already true from the original pass; not a fresh path producing the same "processed" outcome without the flag. |
| `Memo.keptAt` | `WayOutRules.bringBack` (line 179), `MemoLifecycle.swift:41,169`, `Memo.markEdited` (`Memo.swift:252`) | SAFE — every rescue/edit path in scope routes through one of these three, all of which set it. |
| `Memo.transcriptMarkersInjected` | `MemoSaver.swift:822` | Only one writer found in scope; not cross-checked against every transcript-producing path (live caption seed vs final pass) for a sibling that skips it — unverified, follow-up worth a targeted look given this flag gates re-injection on the Mac. |

No candidates confidently established in the time available; the `transcriptMarkersInjected`
single-writer point is flagged for a follow-up pass, not asserted as a bug.

---

## Consolidated candidates, ranked by impact

1. **Custom model repo silently un-pins the LLM revision** — Settings → "Model (HuggingFace
   repo)" reverts to floating `"main"`, reproducing the exact two-model-drift bug from
   2026-06/07. `PolishPrompts.swift:44-45` + `SettingsView.swift:160`. C28, C167.
2. **`MemoCloudReconciler.sweep`'s outer `cloudContext.fetch` swallows failure with zero log** —
   the Mac silently stops picking up new phone memos on any transient fetch error, with none of
   the diagnostics the per-memo path has. `MemoCloudReconciler.swift:59`. New finding, C248.
3. **`voice:` frontmatter ladder disagrees Mac vs phone** — mobile can ship a raw,
   unedited body labeled `voice: cleaned` whenever a Mac polish set only title/summary.
   `MemoExporter.swift:90` vs `CompilerBridge.swift:73-75`. C131, C247.
4. **A corrupt audiobook-bookmark blob silently wipes that device's bookmarks** —
   `JSONDecoder` failure → `[]` → unconditional adopt, stamp updates so it never self-heals.
   `AudiobookBookmarkSyncCore.swift:41`, caller `AudiobookCloudSync.swift:293`. New finding.
5. **Apple Notes import can silently ingest a blank note** — copy-then-read-back swallows the
   read failure into `""`, which then overwrites the copy on disk. `IngestService.swift:180`.
   C75, C76.
6. **Audiobook-bookmark sync is architecturally fragile vs its LWW siblings** — the only one
   of three near-identical whole-list-LWW engines that hand-rolls JSON blob encode/decode
   instead of typed SwiftData fields (root cause of #4). `AudiobookBookmarkSyncCore.swift`
   vs `VocabularySyncCore.swift`/`PolishPromptsSyncCore.swift`.
7. **R34 (Mac recording word timings never reach the phone)** — already known/pinned as an
   expected failure in SPEC.md and the current test suite (`RoundTripParityTests`); confirmed
   still true at `MacMemoAuthor.swift:92` but not a new finding — listed for completeness.
8. Follow-ups not reached this pass (explicitly flagged, not claimed clean): the fading
   conveyor's rated/unrated coverage (shape 2), diarization sidecar vs store parity (shapes 5
   & 7), the full C247 field×device parity table (shape 6), and
   `transcriptMarkersInjected`'s single-writer point (shape 10).
