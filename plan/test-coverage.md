# Test-coverage audit — SPEC.md vs. the test suites (2026-09-22)

Method: for every `[auto]` clause (C1–C251, 221 of them; 30 `[tuur]` clauses are out of
scope — no test is expected), the clause's `|| check:` was traced into
`Skrift_Native/SkriftDesktop/SkriftDesktopTests/*.swift` (770 tests, `./gate.sh`) and
`Skrift_Native/SkriftMobile/SkriftMobileTests/*.swift` (~1,000 tests), reading the actual
test body, not just grepping a name match. Corpus = `test-fixtures/corpus/notes/` (109
synthetic notes, each carrying an `expect` field).

Status legend: **TESTED** (a real test asserts the rule) · **PARTIAL** (part of the rule is
tested) · **UNTESTED** (no test) · **UNTESTABLE-AS-WRITTEN** (the check names an artifact
that doesn't exist — a harness, a document, a feature not yet built).

Seven parallel research passes did the clause-by-clause work (batches C1–40, C41–94, C95–139,
C140–164, C165–200, C201–237, C238–251); this file merges their tables.

---

## 0. The one finding that undercuts most `|| check:` corpus references

**Zero of the 109 corpus notes' `expect` field is read by any test, and the field isn't even
decoded.** `Skrift_Native/Shared/Corpus/CorpusSeed.swift:25-63` defines `CorpusSeed.Note` —
`slug` is decoded, `expect` is not a property on the struct at all. Independently confirmed
by grepping all 109 slugs (e.g. `pic-mid-sentence`, `voice-en-untrusted`, `typed-locked`,
`dest-idea`) across both test directories: **zero hits** on any slug string in any test file.
The only corpus-consuming tests are generic bulk passes —
`CorpusSeedTests.swift` (both apps, asserts rate→row + seed-once over all ~109 at once) and
`RoundTripParityTests.swift` (desktop, asset-kind survival over >20 notes) — neither picks a
note by slug and checks its specific `expect` claim. Every clause below whose check names a
corpus slug is downgraded accordingly: the fixture usually **exists**, but nothing asserts
what it exists to prove.

---

## 1. Coverage table, all 221 `[auto]` clauses

### The v2 method (C1–C9)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C1 | UNTESTABLE-AS-WRITTEN | none | a lint asserting no `Shared/Model/*@Model` / `Services/Recording/` file changed |
| C2 | UNTESTABLE-AS-WRITTEN | none | a CI check that a `v1-<subsystem>` tag precedes the deletion commit |
| C3 | UNTESTABLE-AS-WRITTEN | no v2 files exist to measure | `wc -l` check once v2 subsystem files land |
| C4 | PARTIAL | `CorpusSeedTests.swift` (both apps) loads the corpus; `.gitignore:90` confirms `dutch-rambles` ignored | a test asserting the harness picks up `test-fixtures/dutch-rambles` when present |
| C5 | UNTESTABLE-AS-WRITTEN | no v1-vs-v2 diff harness exists | the harness itself |
| C6 | UNTESTABLE-AS-WRITTEN | pieces exist (`RoundTripParityTests.swift:29`) but no unified 54-item invariant suite | the consolidated invariant harness |
| C7 | UNTESTABLE-AS-WRITTEN | none | the recorded-model-output cache keyed `sha256(prompt+input)` |
| C9 | UNTESTABLE-AS-WRITTEN | none | a `-corpus`-driven scenario runner (no v2 subsystem built yet) |

### Body/image model — rewrite target 1 (C10–C27)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C10 | UNTESTED | `pic-*` corpus notes exist, zero test files reference any of them | a test loading each `pic-*` note, asserting no `[[img_` inside a sentence |
| C11 | UNTESTED | `054-pic-mid-sentence` unreferenced | a test asserting the marker lands after "…the glaze." |
| C12 | UNTESTED | `VideoIngestTests`/`VideoImportTests` cover extraction/date/thumbnail, never marker placement; no P3 fixture found | a P3 mixed-share fixture + marker-placement assertion |
| C13 | UNTESTED | `057-pic-two-same-second` unreferenced | a test asserting two consecutive picture paragraphs, order preserved |
| C14 | UNTESTED | `MemoPhotoMaterializerTests.swift:42,59` test write/heal only; **current marker regex is `\d{3}`-only** (`ImageMarkerReinsert.swift:12`), contradicting the `\d+`-reader rule C15 needs | a delete-marker test proving the manifest entry survives un-renumbered |
| C15 | UNTESTED | `ImageMarkerReinsert.swift:12` hardcodes `\#"\[\[img_(\d{3})\]\]"#` — the exact pattern the clause forbids | a test feeding a non-3-digit marker through every reader |
| C16 | UNTESTABLE-AS-WRITTEN | drag-to-reposition doesn't exist | the feature + its test |
| C17 | UNTESTED, **contradicts current tests** | `NoteBodyTests.swift:243` `testSnapMovesWrappedMidSentencePhotoToSentenceEnd`, `:196` `testImageBreaksMakeMidSentencePhotosBlocks` actively assert the PRE-C10 snap system C17 says must be deleted | delete `snapImages`/`SnapResult`/`imageBreaks`, then a single-remap test |
| C18 | TESTED | `NoteBodyTests.swift:141,164,212` | nothing — already gated |
| C19 | UNTESTED | no CRLF/tabs/nbsp/blank-line normalization test anywhere; `024-typed-crlf-tabs-nbsp`/`036-voice-en-triple-blank-lines` unreferenced | a whitespace-normalization unit test wired to those fixtures |
| C20 | UNTESTED, **rule not yet built** | `ParagrapherTests.swift` tests `defaultGap = 0.65` (phone) + `longFormGap = 2.0` as a separate opt-in (`Paragrapher.swift:23,32`) — the "2.0s everywhere" rule (dated same day as this audit) isn't implemented | update `Paragrapher` to a universal 2.0s gap, then test it + the typed-text-never-paragraphed case |
| C21 | PARTIAL | `NoteBodyTests.swift:49` asserts `transcriptUserEdited`, never `editedAt`; `:116` covers the quote-prefix half | assert `editedAt` in the same test |
| C22 | TESTED | `QuoteProtectionTests.swift:48,65,75` (Mac); `NoteBodyTests.swift:116` (mobile) | nothing — already gated |
| C23 | PARTIAL | `DiarizationTests.swift:53` confirms ≥2-header/≥2-name gating; `095-applenote-headings-checklist` unreferenced, no false-positive test | a false-positive test against that exact fixture |
| C24 | PARTIAL | `TagCompleteTests.swift:53,62` cover parsing; "dim-visible" is a render claim, untested | a visual/render check for dim-mark display |
| C25 | PARTIAL | `NoteTitleTests.swift:18` covers the 80-char clip only; no ladder test, no share-capture fallback chain; `020/021/052-*` unreferenced | a ladder test walking every tier + the share-capture fallback |
| C26 | PARTIAL | `KaraokeAlignmentTests.swift:14,29,41` cover exact-match, copy-edit-survives, mismatch→empty | a test for the CALLER's proportional-sweep fallback itself |
| C28 | PARTIAL | `PolishPrompts.swift:14,44` pins repo/revision; no test asserts the constant value or iPad/Mac byte-identical output | a constant-value test + cross-app output-parity test |
| C29 | TESTED | `IPadPolishTests.swift:21,37,49`; `QuoteProtectionTests.swift:119` (Mac) | nothing — already gated |
| C30 | UNTESTED, **contradicts spec** | `ImageMarkerReinsertTests.swift:6` still tests the 6-word `extractAnchors` machinery C30 says must be DELETED; no paragraph-index reinsertion exists; `pic-wall`/`pic-three-spread` unreferenced | delete `extractAnchors`, build paragraph-index reinsertion, test against those fixtures |
| C31 | TESTED | `IPadPolishTests.swift:62`; `QuoteProtectionTests.swift:131` (Mac) | nothing — already gated |
| C32 | TESTED | `IPadPolishTests.swift:90,102` | nothing — already gated |
| C33 | TESTED | `IPadPolishTests.swift:124` | nothing — already gated |
| C34 | PARTIAL | `IPadPolishTests.swift:113` proves deterministic wall-breaking; no paragraph-ledger test; `035-voice-en-asr-wall`/`005-typed-wall-7k` unreferenced by slug | a ledger test (`in N → model N → shipped N`) over both fixtures |
| C35 | UNTESTED | `028/030-*` unreferenced; no filler-removal unit test found (this clause is `[tuur]`-gated for judgment via C8, so an automated assert is a floor, not the whole rule) | a filler-removal unit test |
| C36 | TESTED | `BatchRunnerTests.swift:108,210,219`; `IPadPolishTests.swift:77`; `DiarizationTests.swift:170` | nothing — already gated |
| C37 | TESTED | `MacCloudWriteBackTests.swift:111,146` | nothing — already gated |
| C38 | PARTIAL | `RunReconcilerTests.swift:5` covers "only `!= .done` processed"; no test for "edit re-links never re-polishes" or "edit during a run discards the run" | tests for those two remaining halves |
| C39 | PARTIAL | `PolishPromptsSyncCoreTests.swift:32,43` cover LWW sync; no migration test for a stale `user_settings.json` override | a migration test against a pre-migration settings fixture |
| C40 | UNTESTED | `PolishCenter.swift:163-172` implements the 0.1-floor; no test calls `polishNow` | a test calling `polishNow` on an unrated memo, asserting `significance == 0.1` |

### Copy-edit — rewrite target 2, continued in count above (C40 listed there)

### Reconcile sweep — rewrite target 3 (C41–C52)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C41 | TESTED | `CorpusSeedTests.swift:51`; `MemoCloudReconcilerTests.swift:63,332` | nothing — already gated |
| C42 | PARTIAL | `MemoCloudIngestTests.swift:98,109`; `CorpusSeedTests.swift:70-75` | test for in-flight `.transcribing` untouched + sidecars gated on trust |
| C43 | TESTED | `MemoCloudIngestTests.swift:181,270` (check names a stale `isTextOnly` method — behavior covered via `sourceType` asserts instead) | rename the check to match the real API |
| C44 | PARTIAL | `MemoCloudIngestTests.swift:32` — one-memo field parity | corpus-wide golden diff of every row |
| C45 | PARTIAL | `MemoCloudReconcilerTests.swift:205,254` | blob-fetch-count instrumentation for R29 (0 fetches on unchanged sweep) — none exists |
| C46 | TESTED | `MemoCloudReconcilerTests.swift:350,370` | corpus slug `voice-en-with-mac-polish` still unused by name |
| C47 | TESTED | `MemoCloudUpdateTests.swift:32-386` | nothing — already gated |
| C48 | TESTED | `MemoDuplicatesTests.swift:20,29,36,43`; `MemoCloudReconcilerTests.swift:106` | nothing — already gated |
| C49 | TESTED | `MacMemoAuthorTests.swift:39,62,76` | nothing — already gated |
| C50 | PARTIAL | `NamesTests.swift:26-61` (LWW merge, union) | the named "D1 test" (torn-file/atomic-write → previous roster) doesn't exist |
| C51 | UNTESTABLE-AS-WRITTEN | none | the named "D2 test" doesn't exist |
| C52 | UNTESTED | only `MemoCloudReconciler+Wiring.swift` (impl, no test file) | a test that the sweep fires at launch/activation/import, coalesced, no heartbeat |

### Export compiler — rewrite target 4 (C53–C65)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C53 | TESTED | `VaultLayoutTests.swift:30-80` | nothing — already gated |
| C54 | TESTED | `VaultWriteTests.swift:46,97,109,153` | nothing — already gated |
| C55 | TESTED | `VaultWriteTests.swift:56`; `VaultStampTests.swift:42` | nothing — already gated |
| C56 | PARTIAL | `CompilerTests.swift:10,39` | corpus `voice-en-full-context` never loaded by any test |
| C57 | UNTESTED | corpus `022/023-typed-same-title-a/b` exist, unreferenced | export both through VaultWriter, assert distinct filenames |
| C58 | UNTESTABLE-AS-WRITTEN | none | the named "D3 test" doesn't exist |
| C59 | TESTED | `MemoLinkResolverTests.swift:19,38` | nothing — already gated |
| C60 | TESTED | `CompilerTests.swift:143-211` | nothing — already gated |
| C61 | PARTIAL | `PublishCoordinatorTests.swift:47-147` (gate matrix) | "iPhone never exports" has no counter-test (no export entry point on iOS to assert against) |
| C62 | TESTED | `ArchiveExportTests.swift:68-302` | nothing — already gated |
| C63 | PARTIAL | `VideoIngestTests.swift:88-153` | `video-made-archive` slug / Mac-kept `source.<ext>` archive-copy untested |
| C64 | UNTESTED | `Compiler.compile` takes a precomputed `date` string; the timezone rule producing it is never cross-checked | phone-vs-Mac same-note-at-23:30 agreement test |
| C65 | UNTESTED, **contradicts spec** | `VaultExporterTests.swift:172` `testExportSnapsMidSentencePhotoToSentenceEnd` still pins snap-at-export; `VaultExporter.swift:132` still calls `BodyTransform.snappedImageBody` | once C10 lands, delete that test and assert no `snappedImageBody` call |

### Ingress — share / import (C66–C79)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C66 | TESTED | `AudioShareDrainTests.swift:34-160` | nothing — already gated |
| C67 | PARTIAL | `AudioShareDrainTests.swift:65,90` — drain side only; file's own header says extension-side multi-provider dispatch is device-only | an in-process harness for `SharePayloadLoader`'s multi-item/multi-provider dispatch |
| C68 | PARTIAL | `AudioShareDrainTests.swift:434` (audio+images+text → one memo) | the video-in-mixed-bundle case is untested |
| C69 | UNTESTED | no test for odd-UTI reroute or text-that-is-a-URL → link capture | fixtures per UTI + the text-is-url case |
| C70 | PARTIAL | `IngestServiceTests.swift:104` (Mac-side filename-date parsing only) | phone-side filename parsing — not built (matches the flagged required difference) |
| C71 | PARTIAL | `VideoImportTests.swift:138` (`sourceType == .video` asserted) | R11 glyph-key drift (`sourceType` vs `mediaSource`) has no regression test |
| C72 | PARTIAL | `HTMLMetaTests.swift:51` (title fallback) | retry-at-foreground-with-network (≤3×) untested |
| C73 | TESTED | `AudioShareDrainTests.swift:160,188,225` | nothing — already gated |
| C74 | PARTIAL | `ImageDatesTests.swift:32` (EXIF date) | downsample-≤2048px and GIF-stays-GIF (no re-encode) untested |
| C75 | TESTED | `AudioShareDrainTests.swift:118,475` | nothing — already gated |
| C76 | PARTIAL | `IngestServiceTests.swift:124` (attachment copy+rename) | own-creation-date-vs-date-unknown (vs import time) untested |
| C77 | UNTESTED, **contradicts spec** | `IngestServiceTests.swift:54` `testUnsupportedTypeSkipped` asserts a PDF is silently dropped today (`created.isEmpty`) — the required "honest refusal" (R13) still open | a per-type Mac-import test with a user-visible refusal message |
| C78 | TESTED | `SharedContentParityTests.swift` (both apps) | nothing — already gated |
| C79 | PARTIAL | `BookBundleManifestTests.swift:159`; `AudioShareDrainTests.swift:375` | the ≥1h "offers Books" boundary is untested — `routeToBooks` is always pre-set, never derived from duration |

### Names & sanitise (C80–C86)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C80 | TESTED | `SanitiserTests.swift:37-198`; `NamingGoldenTests.swift:20` | corpus `voice-en-names-all-tiers`/`edge-quote-in-name-roster-word` still unused by name |
| C81 | PARTIAL | `SanitiserParityTests.swift:28-48` (shared Sanitiser byte-identical) | D20: cross-device `namePicks` sync (phone's picks reaching the Mac) untested |
| C82 | PARTIAL | `SanitiserTests.swift:198` (audiobook `>` quote only) | code-block/YAML/memo-link-title exclusion untested; D21 mid-body quotes open |
| C83 | TESTED | `RosterSeedingTests.swift:64,88` | nothing — already gated |
| C84 | TESTED | `SpeakerTurnStyleTests.swift:23-120`; `SpeakerHueTests.swift:8-61` | nothing — already gated |
| C85 | TESTED | `NamesTests.swift:68` | nothing — already gated |
| C86 | UNTESTED | none found | a test that an audiobook-quote import adds no `Person` to the roster |

### Consent, rating, lifecycle (C87–C93)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C87 | TESTED | `NoteConsentTests.swift:12-104`; `UnratedConsentTests.swift:17-76` | nothing — already gated |
| C88 | UNTESTABLE-AS-WRITTEN, **the contradiction is live** | corpus `voice-en-rated-then-unrated` doesn't exist; `WayOutRules.needsProcessing` (`WayOutRules.swift:102-104`) still gates only on `isUnratedLocalRecording`, not `NoteConsent.isRated` — the exact contradiction the clause names is unresolved in code | fix `needsProcessing`, add the corpus note, assert queue-drop + no export |
| C89 | TESTED | `MemoLifecycleTests.swift:20-165` (both apps) | nothing — already gated |
| C90 | TESTED | `DesktopTrashTests.swift:19-60`; `TrashTests.swift:15-208` | nothing — already gated |
| C91 | PARTIAL | `VaultExporterTests.swift:271` | "processing continues on a locked note" and title+🔒-only display both untested |
| C92 | PARTIAL | `MemoCloudUpdateTests.swift:217` (sync only) | per-device alarm derivation untested — spec itself flags "Mac reconciler owed" |
| C93 | TESTED | `MemoModelTests.swift:31-46`; `TagCompleteTests.swift:8-62`; `ArchiveExportTests.swift:127-149` | nothing — already gated |

### Sync contract (C95–C98)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C95 | TESTED | `MemoCloudIngestTests.swift:98`; `MacCloudWriteBackTests.swift:54` | nothing — already gated |
| C96 | PARTIAL | `MetadataTests.swift:42` (only `hPa`-as-Int) | forward-compat decode test + "sent blob has no local-only fields" test |
| C97 | TESTED (rule); UNWIRED (fixture) | `RecoveryOwnershipTests.swift:10` — never through the named corpus fixture `037-voice-en-other-device-transcribing` | wire that fixture into the existing test |
| C98 | UNTESTABLE-AS-WRITTEN | no `Conflict`/`ConflictRecord` type exists anywhere | the conflict mechanism has to be built first (C242 mock is still `[tuur]`) |

### Recording & audio (C99–C103)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C99 | PARTIAL | `LiveRecordingWatchdogTests.swift:11-40` (pure stall/rebuild logic) | segment-persist + launch-sweep-rebuild + force-quit end-to-end is device-owed (sim can't fake a call/kill) |
| C100 | PARTIAL | `LiveRecordingHandoffTests.swift:26` (BT-present→built-in-mic) | "instant record on every entry" and "lands unrated" at creation are untested |
| C101 | TESTED | `ASRPostProcessTests.swift:32,55,77` | nothing — already gated |
| C102 | PARTIAL | `VoiceMatcherTests.swift:34,43` (cosine threshold) | no test that diarization sets `transcriptUserEdited = true` |
| C103 | PARTIAL | `CustomVocabularyTests.swift` (both apps); `VocabularySyncCoreTests`/`VocabularyCloudSyncTests` | "booster pre-warms at launch" — no `preWarm` hit anywhere in source or tests |

### Audiobooks — out of rewrite (C104–C107)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C104 | PARTIAL | `BookCaptureTests.swift:17-131` | corpus `quote-*` (090–094) exist, unused by name; "one memo per capture" unproven against them |
| C105 | TESTED | `ChapterDisplayTests.swift:160`; `ChapterDetectorTests.swift:298` | nothing — already gated |
| C106 | PARTIAL | `BookTranscribePowerPolicyTests.swift:34` (20% pause floor) | sample-accurate-frames-not-AVAssetExportSession is proven only by the manual `-chunksim` CLI, not under `./gate.sh` |
| C107 | TESTED (unit) | `BookBundleManifestTests.swift:36,45,55,159` | spec itself flags the two-device round as owed |

### Search & Connections — out of rewrite (C109–C111)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C109 | PARTIAL | `JournalSearchLogicTests.swift:23,45,50` (floors) | "only rated live notes join" and "no similarity numbers on phone" untested |
| C110 | UNTESTED | none found | a cold-load test asserting an explicit "engine not ready" state, not a silent empty list (BUGS §3 still open) |
| C111 | UNTESTED | corpus `059-pic-ocr-text` exists, zero grep hits for it or "GREY BODY" | a search test loading that note, indexing OCR text, asserting the hit; a Mac jump-to-hit test |

### Editor, note UI, quick capture (C115–C116)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C115 | UNTESTABLE-AS-WRITTEN | none | no structural scan enforcing "no twin of a Shared type" — would need a repo-scan test |
| C116 | UNTESTABLE-AS-WRITTEN | none | the check names a signed mock (`accessory-bar-v2`), an eyeball comparison, not an XCTest assertion |

### Privacy (C120–C122)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C120 | UNTESTABLE-AS-WRITTEN | none | a network-interception harness over a full corpus run |
| C121 | TESTED | `ArchiveExportTests.swift:198` | nothing — already gated |
| C122 | UNTESTABLE-AS-WRITTEN | no `AppPathsTests.swift` at all | that test file, plus the `-corpus` path guard (spec calls this "new, drafter's") |

### Messenger shares (C123–C128)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C123 | UNTESTABLE-AS-WRITTEN | no `sender` field exists on `Memo`/`SharedContent` | the feature isn't built |
| C124 | UNTESTABLE-AS-WRITTEN | no multi-clip-paragraph-boundary code found | the feature isn't built |
| C125 | UNTESTABLE-AS-WRITTEN | known-broken today ("only the first text survives") | the feature isn't built |
| C126 | UNTESTABLE-AS-WRITTEN | known-broken today (extension renames every blob first) | the feature isn't built |
| C127 | UNTESTABLE-AS-WRITTEN | no dedup-on-share code found | the feature isn't built |
| C128 | UNTESTABLE-AS-WRITTEN | no `.zip` refusal path found | the feature isn't built |

### The archive contract (C129–C137)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C129 | TESTED | `ArchiveExportTests.swift:68,91,275` | nothing — already gated |
| C130 | PARTIAL, **a test enforces the bug** | `ArchiveExportTests.swift:91-119` asserts `type`/`source`/`author` absent (matches spec) **but line 104 asserts `summary:` MUST be present** — the exact opposite of this clause, which says Skrift must never write `summary:` in an archive profile | fix `Compiler.swift:128` to drop `summary:`, then flip the test's assertion |
| C131 | UNTESTED | no removals-only diff check found | a corpus-wide test: every word of the cleaned body appears in the raw body |
| C132 | TESTED | `ArchiveExportTests.swift:225,235,245` | nothing — already gated |
| C133 | PARTIAL | `NoteDestinationTests.swift:14,23` | the Idea-vs-Inspiration "intent" line is a judgment call, only indirectly asserted |
| C134 | PARTIAL | `ArchiveExportTests.swift:127,149` (credit-tag gating) | "credit is a photograph, not typed" and "never guesses a maker" untested; named fixtures `dest-inspiration-credit`/`typed-reserved-word-tags` unloaded by name |
| C135 | UNTESTED | none | a test loading `cap-image-no-words` through the archive export, asserting no fabricated sentence |
| C136 | UNTESTED | none | a test with audio + video assets, asserting only audio lands in `dest-made` output |
| C137 | TESTED | `ArchiveExportTests.swift:285` | nothing — already gated |

### From the 50-scenario probe (C140–C164)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C140 | UNTESTED | none | a P9-live-photo fixture + import test asserting the movie is discarded |
| C141 | UNTESTED | known required-difference (code drops other providers' text today) | P9-photo-with-caption fixture + caption-survives test |
| C142 | UNTESTED | none | `.eml` fixture + email-import test |
| C143 | UNTESTED | none | P7-apple-note-share fixture + merge test |
| C144 | UNTESTED | none | P6/P5.2 fixtures + no-fetch assertions |
| C145 | UNTESTED | known required-difference | AirDropped `.aac` + 3-file Files-import tests |
| C146 | PARTIAL | `BookBundleManifestTests.swift:67` (manifest-level only) | a share-sheet-ingress test asserting `.skriftbook` routes to the book importer |
| C147 | UNTESTED | `AudioShareDrainTests.swift` covers many shapes, none mid-delete-failure (known required-difference) | a drainer test that throws/kills after delete, asserting idempotent re-drain |
| C149 | UNTESTED | no `pic-after-interruption` fixture; no test touches `RecordView.swift:453` (known required-difference: wall-clock offsets today) | fixture + a photo-offset test across an interruption |
| C150 | UNTESTED | no `voice-en-forty-minutes` fixture; no per-block copy-edit split test | fixture + a block-split/re-join test |
| C151 | UNTESTED | no `voice-nl-recorded-in-english-mode` fixture; no "Transcribe again" verb test | fixture + language-mode-override test |
| C152 | UNTESTED | no `voice-en-append-after-polish` fixture; no test touches `MemoSaver.swift:657` (known required-difference: append is invisible on polished screens) | fixture + a test asserting appended text shows and triggers a new-block-only pass |
| C153 | PARTIAL | `MemoCloudUpdateTests.swift:71,87` (edit reflected/re-sanitised) | no test that status flips back to pending or that the phone shows the edit pre-repass |
| C154 | UNTESTED | corpus `037-voice-en-other-device-transcribing` exists, unreferenced; no 30-min-takeover logic found | an aged `.transcribing` memo + present-audio + quiet-recorder test |
| C155 | UNTESTED | none | injected CKError (quota/sign-in) test |
| C157 | PARTIAL | `DesktopTrashTests.swift`/`WayOutRulesTests.swift`/`MemoLifecycleTests.swift`/`MemoSpineTests.swift` cover trash/sweep generally, none for orphan-row-on-gone-memo (known required-difference: `NotesRepository.swift:112-126` keeps the enhancement) | purge test + orphan-row sweep test |
| C158 | UNTESTED | no `pic-deleted-after-export` fixture | fixture + export test |
| C159 | UNTESTED | no `voice-en-bruno-before-roster` fixture; no rename-golden test (known required-difference: only the open note re-scans today) | fixture ×3 + rename-golden test |
| C160 | UNTESTED | no "Fix quote"/edited-quote-golden test | an edited-quote golden test |
| C161 | PARTIAL, **possible contradiction** | export-block tested (`VaultExporterTests.swift:271`); never-shown tested (`NoteBodyTests.swift:451`); but `WayOutRulesTests.swift:40` `testUnpipelinedExcludesLockedMemos` treats lock as "skip processing" — appears to contradict "keeps processing" | reconcile the processing-continues claim against that test; no `typed-locked`-driven or ledger-entry test |
| C163 | UNTESTED | no `dest-idea` re-filed-Personal test (corpus `100-dest-idea` exists, unreferenced; known required-difference: `VaultWrite.swift:27-100` leaves old file) | fixture + destination-change test (old file removed when owned/untouched) |
| C164 | PARTIAL | `VaultWriteTests.swift:73` (retitle only) | no two-root/vault-folder-switch test |

### Rules recovered by the coverage audit — method/gate, body/image, copy-edit (C165–C184)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C165 | PARTIAL | `VaultWriteTests.swift:280` (forbidden chars, fallbacks) | a >120-char title test asserting the cap |
| C166 | UNTESTED | `RunFile.swift:668,988` implements the verbs; no test invokes them | an automated script running the harness against the corpus, diffing goldens |
| C167 | UNTESTED | `project.yml` pins verified by eye only | a lint asserting zero `branch:` keys |
| C168 | UNTESTED | `try?` appears dozens of times in Shared/Export, Shared/Naming, Pipeline/Ingest (e.g. `VaultWrite.swift:80-83`, `MemoCloudReconciler.swift:59-180`) — the check would FAIL today if run | a static `try?`-count test + MLX-fault-wrapping test |
| C169 | PARTIAL | `MemoSaverTests.swift:422` (manifest order/injection) | pause-exclusion test for `offsetSeconds`; corpus `089-conv-with-picture` (`expect: needs-verdict`, D3 unresolved) unread by any test |
| C170 | TESTED | `MemoModelTests.swift:141-204` | nothing — already gated |
| C171 | PARTIAL | `FillerFilterTests.swift:12-59` | opt-in default-off gating + voice-memo-only call-site rule untested |
| C172 | PARTIAL | `QuotePresentationTests.swift:20-252` (mobile); `QuoteProtectionTests.swift:15-144` (Mac) — two SEPARATE types, not one shared splitter | a parity test proving both agree |
| C173 | TESTED | `NoteBodyTests.swift:82` | nothing — already gated |
| C174 | TESTED | `DiarizationTests.swift:329` | nothing — already gated |
| C176 | TESTED | `VaultExporterTests.swift:202,239` | nothing — already gated |
| C177 | UNTESTED | no post-condition `Gate` type found; existing tests cover link/marker preservation only, not proper-noun/language-flip/length bounds | tests for each gate + unedited-text fallback |
| C178 | PARTIAL | `TagMatcherTests.swift:6-23`; `BatchRunnerTests.swift:219` | an explicit ordering test: tags → name-link → compile, no `[[ ]]` to the model |
| C179 | UNTESTED | `PolishCenter.swift:55,182` defines `redo(...)`; no test calls it | redo tests (escrow write, LWW stamp, no second row) |
| C180 | PARTIAL | `IPadPolishTests.swift:13` proves gate=false on sim only; device-owed per comment | device-class gate test (currently unverifiable off-device) |
| C182 | PARTIAL | `RunReconcilerTests.swift:5`; `UnratedTakeTests.swift`; `DiarizationTests.swift:62` | 60s idle-unload timer test; re-transcribe-clears-diarization-keeps-title test |
| C184 | PARTIAL | `NoteDestinationTests.swift:73` (one shared constant) | a string-scan test that no "memo" wording remains |

### Reconcile sweep, export, ingress — recovered rules (C185–C200)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C185 | UNTESTED | `MemoCloudReconciler.swift:48` `sweep()` is one function; no order assertion | an order-assertion test (spy/log sequence) over the full wiring |
| C186 | TESTED | `MacCloudWriteBackTests.swift:33-45,86` | nothing — already gated |
| C187 | TESTED | `MemoNoteProjectionTests.swift:43,147,161` | nothing — already gated |
| C188 | PARTIAL | `MemoCloudUpdateTests.swift:197,375`; `MemoCloudReconcilerTests.swift:151` | no test that content date = phone's `recordedAt`, never ingest time |
| C189 | UNTESTED | `VaultWriteTests.swift:56` tests exporter idempotency, not sweep-triggers-re-export wiring | a wiring test |
| C190 | PARTIAL | `MemoPhotoMaterializerTests.swift:42-77`; `DesktopTrashTests.swift:39` | byte-count-refresh test; once-per-launch recovery test; phone-owns-purge split test |
| C191 | UNTESTED | `AppSettings.swift:99,106` defines the flag; no test references it | default-value test + silent-push registration check |
| C192 | PARTIAL | `VaultLayoutTests.swift:30-80`; media subfolders confirmed via `VaultExporterTests.swift:166` | a test that the archive profile returns the pick unchanged |
| C193 | PARTIAL | `VaultStampTests.swift:90,110`; `VaultWriteTests.swift:73` | "never deletes a vault file" + lock-shows-"already in your vault" untested |
| C194 | TESTED | `VaultWriteTests.swift:173,191`; `NoteDestinationTests.swift:64` | nothing — already gated |
| C195 | TESTED | `VaultExporterTests.swift:4,117` | nothing — already gated |
| C196 | PARTIAL | `CompilerTests.swift:10,75` | dangling-marker-drop untested on the DESKTOP export path (only `ObsidianPublisherTests.swift:204`, mobile); asset-write-failure-counted-not-fatal untested |
| C198 | PARTIAL | `AudioShareDrainTests.swift:349` and dispatch-order tests | `maps.app.goo.gl` short-link-stays-plain-card is explicitly called out in spec, not covered |
| C199 | UNTESTED | `AppURLHandlerTests.swift:7-22` — 3 generic tests, none for `.ogg/.oga/.m4b/.pdf` parity | tests asserting open-in matches the share sheet, per format |
| C200 | UNTESTABLE-AS-WRITTEN | no opus/ogg fixture exists anywhere in the corpus | the fixture itself has to be created first |

### Ingress cont'd, names, consent/lifecycle, sync — recovered rules (C201–C219)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C201 | PARTIAL | `AudioShareDrainTests.swift:475-496` (tombstone-and-skip) | cap-200 eviction test; re-entrancy-guard-under-concurrency test; exact feedback-copy test |
| C202 | PARTIAL | `VideoImportTests.swift:104` (mobile only) | Mac-side "identical" failed-note test; location-stamp-recordings-only vs never-import-for-captures test |
| C204 | TESTED | `RosterSeedingTests.swift:26-89` | nothing — already gated |
| C205 | TESTED | `SanitiserTests.swift:40-44` | nothing — already gated |
| C206 | TESTED | `UnlinkTests.swift:36-130` | nothing — already gated |
| C207 | PARTIAL | `RosterAuditTests.swift:19-59`; `SanitiserTests.swift:228-241` | stoplisted-frequent-person no-override test; sentence-initial-noise test |
| C208 | TESTED | `NamesTests.swift:26-259` | nothing — already gated |
| C209 | PARTIAL | `VoiceMatcherTests.swift:13-60`; `SpeakerFusionTests.swift:7-85` (cosine math only) | audio-discard-after-embedding; enrol-on-naming; trust-gated attribution; forced-N-merges; cross-app parity — all untested |
| C210 | TESTED | `SignificanceScaleTests.swift:14-85` | nothing — already gated |
| C211 | TESTED | `MemoSpineTests.swift:106-116` | nothing — already gated |
| C213 | PARTIAL | `NoteBodyTests.swift:451-471`; `VaultExporterTests.swift:271` | no test that the player refuses a locked memo |
| C215 | TESTED | `ProcessPileTests.swift:25-128`; `UnratedConsentTests.swift:66-68` | nothing — already gated |
| C216 | PARTIAL | `MemoAssetTests.swift:21-241` | "newest enhancement row wins on read" and once-only-flags-never-synced both untested explicitly |
| C217 | TESTED | `LanguageSyncCoreTests.swift:32-98` | nothing — already gated |
| C218 | PARTIAL | `AudiobookBookmarkSyncTests.swift:40-118` (bookmarks only) | per-book opt-in, Wi-Fi-only gate, position/rate LWW, transcript re-stamp, applied-marker, unshare-keeps-audio — all untested; no check was even named in SPEC.md for this clause |
| C219 | UNTESTABLE-AS-WRITTEN | no check named, no test found | a schema-history diff tool (additive-only across commits) doesn't exist; not unit-testable as stated |

### Recording, audiobooks, search, editor — recovered rules (C220–C237)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C220 | PARTIAL | `LiveRecordingDraftTests.swift:17-171` | no test pins the 7s Mac / 25s phone rotation constants |
| C221 | TESTED | `LiveRecordingRouteChangeTests.swift:76-234`; `LiveRecordingWatchdogTests.swift:11-39` | a device round for the real `.ended`/foreground observer wiring (spec itself flags this) |
| C222 | UNTESTED | no check was named in SPEC.md; none of the sub-rules (60s auto-stop variants, sticky toggle, <0.4s discard, camera sheet, no-haptic) have a test | tests for each sub-rule |
| C223 | TESTED | `MemoSaverTests.swift:92-229` | nothing — already gated |
| C224 | TESTED (unit); UNTESTABLE (named harness) | `MacRecorderRefusalTests.swift:17-352` | the named `-recordcheck` is live-hardware only, can't be a unit test |
| C225 | PARTIAL | `AudiobookInterruptionTests.swift:17-38` | ducking-only-on-Play and book-chunks-skip-vocab-pass untested |
| C226 | PARTIAL | `QuoteCaptureSaveTests.swift:27-110`; `AudiobookCaptureMathTests.swift` | the literal ~90s-before/8-lines-after/4-un-chunked bounds untested |
| C227 | TESTED (unit); UNTESTABLE (named harness) | `AlignmentCoreTests.swift:104-288`; `AlignedSentenceSourceTests.swift:41-326` | the named `-readalongcheck` is device/real-audio only |
| C228 | PARTIAL | `ChapterDetectorTests.swift` (~25 funcs); `ChapterDisplayTests.swift:148-162` | nil-vs-`[]` rerun semantics, quote-span-crossing, cancelled-chunk-redo, RTF-only speed — all untested |
| C230 | PARTIAL | `EmbeddingIndexTests.swift:19-107` | trashed-excluded, captures-included, book-sidecars-out, vault-never-indexed — untested |
| C231 | TESTED | `JournalSearchLogicTests.swift:12-32`; `WallPrinterTests.swift:45`; `LookbackProviderTests.swift:21-93` | nothing — already gated |
| C233 | PARTIAL | `WallPrinterTests.swift:33` | offline-queue-to-saved-printer untested |
| C236 | PARTIAL | `NoteBodyTests.swift:560-570` (title/transcript/tags/place/OCR) | summary/PDF/article-text fields untested; "OCR hits match in LIST search only" untested |
| C237 | TESTED | `WeatherKeyTests.swift:17-44` | nothing — already gated |

### Shared code, catches, meta-process (C238–C251)

| Cn | status | evidence | what a v2 gate would need |
|---|---|---|---|
| C238 | UNTESTED | no `Shared/` import-dispatch layer exists at all; `plan/parity.md` Table B shows mobile (`CaptureInboxDrainer`) and Mac (`IngestService`) as fully separate stacks — this is the v2 target, not yet built | cross-platform ingress fixture test once `Shared/` dispatch exists |
| C239 | UNTESTED | `plan/twins.md` does not exist; `plan/bug-shapes.md` found one twin drift (`voice:` ladder) independently but not the enumerated 7-area audit the clause requires | write `plan/twins.md` |
| C244 | UNTESTED | `plan/measurements.md` does not exist; no battery numbers anywhere in `plan/`, `SPEC.md`, or `backlog.md` | the two measured numbers, written before any tuning |
| C245 | PARTIAL | `plan/parity.md` Table A + `RoundTripParityTests.swift:30-69` pin the gap via `XCTExpectFailure` citing R34/C245 — this is an EXPECTED failure, not a red gate, and uses the synthetic corpus, not the real `dutch-rambles` fixture | a device- or dutch-rambles-seeded test that goes RED once the writer is added |
| C246 | PARTIAL | `src:` convention used consistently in `plan/extraction/code-core.md`; NOT retrofitted into `plan/extraction/ingress.md` (10 "Expected:" lines uncited) or `plan/extraction/scenarios.md` | a CI grep failing on any expected/by-design/harmless/fine line lacking `src:` |
| C247 | TESTED (as a document) | `plan/parity.md` (142 lines) — Tables A/B/C, every empty cell explained or listed as a bug candidate | a generator script run in CI, failing on a newly unexplained empty cell |
| C248 | TESTED (as a document) | `plan/bug-shapes.md` (360 lines) — all 10 shapes present, grep counts, verdicts, ranked candidates | the sweep re-run automatically per swap (currently manual) |
| C249 | PARTIAL | `RoundTripParityTests.swift` (70 lines, 1 test) — phone→Mac→phone, asset-kind only, no Mac→phone counterpart, no logged device diff | field-by-field both-direction round trip + a logged per-swap device diff |
| C250 | PARTIAL | same grep as C246 — 51 hits project-wide for expected/by-design/harmless/fine, several without the literal `src:` token | the same CI gate as C246, scoped wider |
| C251 | TESTED (as of this pass), borderline | `plan/extraction/scenarios.md` (50 traces) + `plan/scenarios-adverse.md` (40 traces, this very audit's sibling) exist, but neither is named `plan/scenarios-<subsystem>.md` as literally required — both are general, not tied to a subsystem about to swap (none has swapped yet) | name the next probe after its subsystem; independently confirm the no-prior-context constraint |

---

## 2. Counts

- **251** total clauses (C1–C251, no gaps, no duplicates). **221** `[auto]` (audited above). **30** `[tuur]` (out of scope for this audit — no test expected; includes **C241**, missed from the batch-7 table but confirmed `[tuur]` in SPEC.md).
- Of the 221 `[auto]` clauses:
  - **TESTED: 66** (30%)
  - **PARTIAL: 77** (35%)
  - **UNTESTED: 54** (24%)
  - **UNTESTABLE-AS-WRITTEN: 24** (11%) — the check names a harness, document, or feature that does not exist yet
- **Six existing tests actively pin v1 behavior that its own clause says must change** — these will need to be deleted/flipped, not just supplemented: C17 (`NoteBodyTests.swift:196,243`), C30 (`ImageMarkerReinsertTests.swift:6`), C65 (`VaultExporterTests.swift:172`), C77 (`IngestServiceTests.swift:54`), C88 (`WayOutRulesTests.swift` gates on the wrong field), C130 (`ArchiveExportTests.swift:104` asserts the forbidden `summary:` key is present).
- **Corpus**: 109/109 notes carry an `expect` field; **0/109** have that field read or asserted by any test (see §0). `CorpusSeed.Note` doesn't even decode the field.

---

## 3. UNTESTED `[auto]` clauses inside the four rewrite targets — first queue items

**Body/image model (C10–C27) — 9 UNTESTED, 1 UNTESTABLE-AS-WRITTEN:**
C10, C11, C12, C13, C14, C15, C17 (contradicted), C19, C20 (rule not yet built) — plus C16 (feature doesn't exist).

**Copy-edit (C28–C40) — 3 UNTESTED:**
C30 (contradicted), C35, C40.

**Reconcile sweep (C41–C52) — 1 UNTESTED, 1 UNTESTABLE-AS-WRITTEN:**
C52 — plus C51 (named "D2 test" doesn't exist).

**Export compiler (C53–C65) — 3 UNTESTED, 1 UNTESTABLE-AS-WRITTEN:**
C57, C64, C65 (contradicted) — plus C58 (named "D3 test" doesn't exist).

**Total: 16 UNTESTED + 3 UNTESTABLE-AS-WRITTEN = 19 clauses with zero current gate**, across the
four subsystems about to be rewritten. Three of these (C17, C30, C65) are worse than untested —
an existing test actively locks in the v1 behavior the clause says must go.

---

## 4. Corpus notes whose `expect` no test consumes

**All 109.** See §0 — the `expect` field isn't decoded by `CorpusSeed.Note`, and zero test file
references any of the 109 slugs by name. This is not a partial gap to list note-by-note; it's
the whole corpus. The fixtures exist (folder + `note.json` for every slug named in every clause
check above — `pic-mid-sentence`, `voice-en-untrusted`, `typed-locked`, `dest-idea`,
`quote-with-names`, etc.), but nothing loads them individually and checks their `expect` claim.
Six specific slugs named in clause checks don't even exist yet as fixtures:
`pic-after-interruption`, `voice-en-forty-minutes`, `voice-nl-recorded-in-english-mode`,
`voice-en-append-after-polish`, `pic-deleted-after-export`, `voice-en-bruno-before-roster`.
An opus/ogg ingress fixture (for C200) also doesn't exist.

---

## 5. Checks that name a harness, document, or feature that doesn't exist yet

**Process/meta harnesses (blocking the whole v2 method, C1–C9, C247–C251):**
- The v1-vs-v2 diff harness itself (C5, C6, C9) — nothing implements it.
- The consolidated 54-item invariant suite (C6) — pieces exist scattered, nothing unifies them.
- Recorded-model-output cache keyed `sha256(prompt+input)` (C7).
- `-corpus`-driven end-to-end scenario runner, one per swap (C9) — none exist, no v2 subsystem built.
- `plan/twins.md` (C239) and `plan/measurements.md` (C244) — neither file exists.
- A CI-enforced `src:`-citation grep (C246, C250) — the convention exists in one doc, not enforced.
- A per-swap logged device diff (C249's `[tuur]` half) — no artifact found.
- A subsystem-named scenario probe, `plan/scenarios-<subsystem>.md` (C251) — two general probes exist instead.

**Named "D-tests" that don't exist as files:**
- C50/C58 → "D1 test" / "D3 test" — not found.
- C51 → "D2 test" — not found.

**Device/live-hardware only (structurally can't be a unit test):**
- C99 (call/kill mid-take), C100 (device round), C106/C227 (`-chunksim`/`-readalongcheck`), C120
  (network-interception over a real run), C166 (`-ingestfile`/`-processfile -exportafter`
  corpus-golden run), C180 (iPad-class gate), C221 (route/interruption wiring), C224
  (`-recordcheck`), C243 (audiobook backgrounding, `[tuur]`).

**Features not built yet, so their check can't run against anything:**
- The whole messenger-share block, C123–C128 (no `sender` field, no multi-clip merge, no dedup,
  no `.zip` refusal — the code these clauses describe doesn't exist).
- C16 (drag-to-reposition), C98 (conflict type/mechanism), C177 (post-condition `Gate` type),
  C238 (the one `Shared/` import layer — still two separate per-app stacks per `plan/parity.md`).

**Static/structural checks nobody runs (would likely fail today if run):**
- C1/C2/C3 (no lint for the v2-method constraints).
- C115 (no "no twin of a Shared type" scan).
- C167 (no `branch:`-ref lint over `project.yml`).
- C168 (`try?`-count check — dozens of hits exist in the very files it targets).
- C222 (no check was even named in SPEC.md for the live-caption sub-rules).
