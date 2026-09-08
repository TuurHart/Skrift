# Skrift — Backlog

Deferred ideas and features, captured during the 2026-06 overhaul planning so they're not lost. Not scheduled — pull from here when ready.

## 🎚️ OPEN IDEA — importance: 3 buttons instead of 10 circles (Tuur, voice on the bike, 2026-09-08; decide next week)

What he asked for: "not important / somewhat important / medium important / very important" —
"three things you can click instead of ten", nothing else about the feature changes.

**What exists today** (`Skrift_Native/Shared/Model/SignificanceScale.swift`): 10 steps, persisted as
a Double 0/0.1…1.0 (`Memo.significance` non-optional, 0 = unrated; `PipelineFile.significance`
optional). It already collapses to THREE tier names — Passing 0.1–0.3 / Useful 0.4–0.6 /
Important 0.7–1.0. Only three behaviour breakpoints read the number at all:
- `0` vs `>0` — gates pipeline pickup (`MemoCloudIngest` skips 0),
- `≥0.8` (`refineStep`) — refine pass before export, and `LookbackProvider.importantLately`,
- ranking sorts by significance, ties broken by date (`LookbackProvider.best`, lines 83/106).

So the ten stops are already fake precision: nothing consumes a 0.4 differently from a 0.6. That
argues FOR the change, not against it.

**Cheapest build.** Keep the persisted Double contract; change `SignificanceScale` + the control
only. Three steps → values `0.3 / 0.6 / 1.0`. Tier names, the 0.4/0.7 boundaries, the 0.8 refine
wall, the `>0` gate and the Connections-panel decimals all keep working untouched, and legacy
values already synced (0.5, 0.7, 0.9) still land in the right bucket. No data migration — do not
rewrite stored values.

**The one real decision (my pushback).** With three levels the top one is ≥0.8, so "very
important" always buys a refine pass. Today 0.7 is the escape hatch: important, don't spend the
refine. Either accept that (top button = refine, arguably the point of the top button) or take the
four labels literally — four buttons, level 3 = 0.7 (important, no refine), level 4 = 1.0 (refine).
He said four names and three clicks in one breath; pick one next week.

**Second-order.** Ties get common when there are 3 buckets instead of 10, so date becomes the
dominant sort in Looking back and Related. Probably fine, eyeball Related after.

**Owed before code.** `mocks/significance-circles.html` is the signed-off spec — a 3-button control
needs a mock pass first (mock-first is locked). The wall tick at
`Shared/UI/SignificanceCirclesView.swift:202` either disappears or becomes the top button's own
treatment. Re-baseline the render gates: Mac `-snapshot-significance` (5 states × 2 schemes) and
`SkriftMobileTests/SignificanceCirclesRenderTests`.

Roadmap idea **i23** points here.

## 🧠 IDEA MENU — getting more out of the notes you already have (2026-08-11 ideation session; NOTHING BUILT)

Design menu, no code. Every "you already have X" was verified against source in that session.
Roadmap ideas **i18–i22** point here. Nothing below is scheduled — pick from it.

### The doctrine for a dumb local model

The Mac runs Gemma 4 E4B via mlx-swift (`SkriftDesktop/Engines/EnhancementService.swift`):
`temperature: 0`, one verb per call (`copyEdit` 1024 tok · `summary` 256 · `title` 64), prompts
editable in `AppSettings.Prompts`. `editProse` already implements the pattern every new LLM verb
must reuse — **escrow → generate → verify → bail**: `MemoLinkSyntax.escrowForEditing` pulls links
out, `ImageMarkerReinsert.extractAnchors` pulls `[photo N]` anchors out, the model sees neither,
and `reattach` returning nil **aborts the enhancement**. Generalised:

1. The model never retrieves, ranks, counts or does dates — code owns all four.
2. **Selection over generation.** "Pick the 2 sentences that matter" is verifiable (output must be
   a substring of the input); "write a summary" is not. Highest-leverage trick on this page.
3. One verb per call. Never merge title+summary to save a call.
4. Small windows, map-reduce. `MemoGist.chunks(body:)` (~175 words) is the feeder.
5. Closed-book only — never a question whose answer isn't in the window.
6. Mechanical post-conditions: length bound · output-is-substring · **no proper noun in the output
   that was absent from the input** (diff `NLTagger.nameType`) · language didn't flip
   (`NLLanguageRecognizer`). That third one kills the worst failure this app can have.
7. On gate failure degrade to the deterministic fallback — never ship the suspect output.

**Never hand a local model:** corpus-wide synthesis ("what did I learn this year"), anything
numeric or temporal, cross-note fact merging without retrieval, translation (the `copyEdit` prompt
already forbids it — EN/NL mid-sentence switching is where small models "helpfully" normalise),
sentiment as a verdict, or any path that writes an unreviewed proper noun into the vault.

⚠️ **Apple Foundation Models gate — this answers roadmap P4a.** Apple Intelligence requires
A17 Pro / M-series, so **the iPhone 13 cannot run it**. FM is Mac + newer-phones only; the 13's
answer is "the Mac does it". Build P4b's picker as genuinely adaptive, not FM-with-a-fallback.

### A. Already own the parts — no new model, no download, no permission

- **A1 · Cluster the embedding index into THEMES.** Today the index only answers pairwise
  questions (`search`, `related` in `Shared/Retrieval/EmbeddingIndex.swift`). Agglomerative
  average-linkage cosine over the **gist** vectors gives global structure: "you've circled the
  pricing decision 14× since April, cooling." Cut height **~0.60–0.65** — justified by the
  on-device calibration already in that file (random pairs p90 ≈ 0.49, p99 ≈ 0.81, which is why
  `relatedFloor` = 0.45). Singletons stay singletons; most notes aren't a theme. Labels: top-lemma
  TF-IDF (lemmatizer already in `Pipeline/Tags/TagMatcher.swift:60`) or one Gemma call (C1).
  Brute-force O(N²) is fine — `scores(against:)` already scans that way. Temperature = notes in
  last 21d ÷ historical rate. **Catch:** persist cluster IDs and re-assign by centroid proximity
  across runs, or the UI flickers and the counts become a lie. ⭐ **Unlocks A4, C7, C8.**
- **A2 · Prosody heat — intra-note attention from word timings already at rest.** Every memo ships
  `[WordTiming] {word,start,end}` as a `word_timings.json` `MemoAsset`, decoded on the Mac by
  `MemoCloudIngest`. Three signals: **rate** (words/sec, rolling ~8s), **pause-before** (gap from
  previous word's `end`), **energy** (RMS). Score each window as a **z-score against that memo's
  own baseline** — per-memo normalisation is the whole trick, absolute WPM thresholds just flag
  whichever notes you recorded while walking fast. Flag spans ≥1.5σ. Rate + pause are pure
  arithmetic on data you already persist; energy needs a windowed variant of
  `Shared/Pipeline/AudioRMS.swift` (today `averageRMS` is whole-file for the phantom guard, but
  `rms(of buffer:)` exists — loop it over sample-accurate `AVAudioFile` frame reads).
  **Catch:** fast+loud is also irritation, or a bus. Ship as **"you leaned in here"**, never as
  significance — the rating stays Tuur's. Start rate+pause only; add energy after an eyeball.
  Feeds "Important lately" + the wall printer with the *sentence* instead of the note.
- **A3 · Speaker-scoped retrieval.** `Shared/Pipeline/SpeakerTranscript.swift` already parses
  `**Name:**` turns and knows `speakers(in:)` / `isAttributed(_:)`; voice identity already resolves
  who's who. Missing piece: index turns **per speaker**, with the speaker as row metadata (never as
  text in the vector — `MemoGist.stripSpeakerHeaders` exists exactly because headers inflate
  similarity). Answers "what has Jack actually said about pricing", which text search structurally
  cannot. **Catch:** a wrong attribution quotes a real person saying something they didn't. Gate on
  the existing trust rule; render unnamed speakers as unnamed.
- **A4 · Open loops.** Rules first, no model. Sentence-split, match a small per-language pattern set
  (EN/NL both, he mixes): interrogatives `should I / what if / moet ik / waarom`, commitments
  `I should / remind me to / ik moet nog / niet vergeten`, unknowns `I don't know if / geen idee of`.
  "Still open" = the loop's cluster (A1) has no *later* note scoring >0.6 that also carries a
  resolution marker (rating / decision phrase / tag). **Catch:** suppress rhetorical questions with
  no noun-phrase object; dismissal is one tap and permanent.

### B. Free Apple frameworks — already linked, barely used

`NLTagger` is in the repo but only for `.lemma` in `TagMatcher.swift:60`. Same object, zero cost:

- **B1 · `.nameType` → unlinked mentions** (people/places/orgs), diffed against the names DB and
  ranked by frequency. This is roadmap **P7b** at near-zero cost, plus free facets. **Catch:** NER
  on Dutch is meaningfully weaker, and mixed-language sentences are its worst case — suggestions
  with counts, never auto-linking, and measure the Dutch hit rate before placing the UI.
- **B2 · `.sentimentScore` as a retrieval FACET, not a verdict.** Per-paragraph −1…1. Use for "that
  note where I was fed up about the export path" and as the contrast detector feeding C6. Never
  render "your mood this week". Dutch again weaker — scope to English-dominant paragraphs.
- **B3 · `SoundAnalysis` ambient labels.** `SNClassifySoundRequest`, ~300 built-in classes, one
  windowed pass at import. Keep only high-confidence AND sustained labels (>0.7 across ≥3
  consecutive windows) so one door slam doesn't tag the memo. Gives journal texture and a real
  search axis ("that thing I said while walking"). **Catch:** genuinely noisy, and "speech" will
  dominate a voice memo — exclude it. Earn this one with a manual check before wiring to search.
- **B4 · `EventKit` calendar join.** Match `recordedAt` against local `EKEvent`s: **during** and
  **just after** (0–30 min post-end — the debrief ramble, probably where the best notes live).
  Cheapest context-per-line on the page: it supplies the one thing a voice memo never records,
  what you had just been doing. **Catch:** permission; and render the neutral fact ("4 min after"),
  never causation.

### C. Local-LLM verbs, safest class first

Format: *call · scaffolding · gate · how it fails.*

- **C1 · Cluster labels** (A1's naming). 12 gist snippets → `"2–4 word label, use only words that
  appear above"` · 16 tok · gate: every content word present in input, else fall back to TF-IDF ·
  fails as generic mush ("various thoughts") — catch with a stopword-ratio check.
- **C2 · Decision extraction → a running decision log.** Per sentence `"Is this the speaker
  committing to a decision? YES/NO"` · 4 tok. Code pre-filters with patterns (`we're going with`,
  `besloten`, `I'm not doing`, `let's just`) so the model judges ~20 sentences, not 400. **The
  stored text is the original sentence, never the model's words.** Fails as over-YES on
  hypotheticals → require first-person + non-interrogative in the pre-filter. *Highest-utility
  extraction for someone who designs by talking to himself: what you lose isn't the idea, it's the
  fact that you already decided.*
- **C3 · Action/todo extraction.** Same shape + one 16-tok rewrite to imperative. Keep the source
  sentence attached so a bad rewrite is recoverable.
- **C4 · Open-loop resolution** (makes A4 trustworthy). `"Question: {Q} / Later note: {chunk} /
  Does the note answer it? YES/NO"` · 4 tok. The index pre-selects — only pairs >0.6 reach the
  model, so ~5 judgments not N². Fails by mistaking topic-similarity for answering → present as
  "possibly answered here?" with a confirm tap.
- **C5 · Tag suggestion from a CLOSED set.** Note + `"pick 0–3 from this list"` + the existing tag
  vocabulary. A closed set means the model can only choose, not invent — reject anything off-list.
  Cap 3, and require the tag to also clear a cosine floor.
- **C6 · Contradiction / evolution.** Two same-cluster chunks with opposed sentiment →
  `"Did the position change? YES/NO. If YES quote the sentence from B."` Gate: the quote must be a
  literal substring of B. **Always presented as a question ("did this change?"), never an
  assertion** — most interesting when right, most embarrassing when wrong.
- **C7 · Ramble modes — roadmap P4c, and nearly free.** Note / Bullets / Email / To-do = four new
  fields on `AppSettings.Prompts` over the existing `run(prompt:text:maxTokens:)`. Reuse the escrow
  guards unchanged — **bullets mode will otherwise eat `[photo 2]` anchors.** ⭐ Highest
  value-per-line on this whole page: a prompt and a picker, and it changes what the app does daily.
- **C8 · Query expansion for search.** `"Rewrite this search as 3 alternative phrasings"` · 48 tok
  → embed all four, union, dedupe by memo, keep max score. **Failure is harmless** (a bad paraphrase
  returns nothing extra), and it fixes the real problem: `searchFloor` 0.25 assumes you phrase the
  query the way you phrased the note.
- **C9 · Per-turn conversation summary.** Map over `SpeakerTranscript.Turn` groups, one line each,
  assembled by code. Never hand the model a 40-minute transcript and ask what it was about.
- **C10 · Auto-title on capture** (roadmap P6d). The `title` verb exists at 64 tok on the Mac; the
  gap is the phone. FM `@Generable` on capable devices, Mac for the iPhone 13.
- **C11 · Person digest** — "what Jack and I keep circling": A3 + C1 machinery, filtered by speaker.
- **C12 · On-this-day card** — one sentence linking today's note to one a year old, written only
  when the pair clears the related floor. Low frequency, tiny call.

### D. Monthly digest — full execution

**The rule: the model never sees the month.** It sees one cluster at a time; code assembles
everything carrying a date, a count or a link.

```
STEP 1  code    cluster the month's memos (A1, cosine ≥0.6 agglomerative)
STEP 2  code    per cluster: rank notes by significance + prosody heat (A2)
STEP 3  model   per cluster EXTRACTIVE — "which 2 of these 8 sentences best capture
                this? reply verbatim"  → GATE: both exact substrings, else top-2 by heat
STEP 4  model   per cluster: ONE sentence ≤25 words, closed-book over those 2
                → GATE: no proper noun absent from input · ≤25 words · language unchanged
STEP 5  code    assemble — every date, count, arrow and [[link]] is String(format:)
STEP 6  code    write one .md into the vault via the shared VaultWriter
```

Output shape: `# July 2026 / 23 notes · 6 themes · 4h12m` → per theme a heading with
`N notes · 8 Jul → 23 Jul · ▲ most active`, the model's one sentence, one verbatim `>` quote with
its date, then `→ [[links]]`; then **Still open** (A4) and **First mentioned this month** (B1).

Cost: ~2 short calls × ~6 clusters = 12 calls, once a month, on a plugged-in Mac with Gemma already
resident. Trigger on first app-open of a new month. The model contributes **six ≤25-word sentences**,
each written from two sentences of Tuur's own text — a job a 4B model does reliably.
**Weekly** is the same code with a different window, but build monthly first: a week often has too
few notes per cluster for the extractive step to have anything to choose between.

### Build order

1. **C7 ramble modes** — four prompt strings over existing plumbing, ships in a session.
2. **A1 clustering** — pure math, prerequisite for A4 / C6 / C7's siblings / D.
3. **B4 EventKit** — smallest effort-to-context ratio here.
4. **D monthly digest** — falls out of A1 nearly free.
5. **FM spike (P4a/P4b)** — deliberately, with the iPhone 13 gate above understood up front.

A1 and A2 share a property worth keeping in mind: both extract new information from bytes already
stored and synced — no model, no download, no permission, no network.


## ⭐ RESUME HERE (branch `claude/book-sharing-devices-rygara`, not merged)

1. ✅ **🔋 DONE 2026-08-11** — sim gate passed on the Mac AND device-confirmed by Tuur on build 136
   (Low Power Mode on, transcribe climbing 0% → 7%). → `## 🔋` section.
2. ✅ **📖 Remove transcript SHIPPED 2026-08-11** (b136) — the Text sheet's Level 1 card got the same
   ⋯ an attached text row has, because Tuur wanted it "in line with what is already there" rather
   than a separate Transcribe-again button. Reader-cache bug found on device and fixed in b137.
3. 🔨 **📦 BOOK SHARING — ALL 5 CHUNKS BUILT 2026-08-11, on the phone as build 138, UNTESTED.**
   Manifest + rules (13 tests) · zip packer/importer + the hoisted re-stamper · per-config UTI and
   document type · the Share sheet · the arrival sheet. 1024 unit tests green. **Nothing has been
   run end-to-end and neither sheet has been looked at** — the sim has no books to open them with.
   **Next: the device round.** Share a real book to yourself, watch it package, AirDrop it to a
   second device, accept it, confirm read-along works on arrival without re-transcribing (that is
   the re-stamp doing its job) and that a second import says "already in your books".
   Two decisions taken against the written design, both recorded in the `## 📦` section: the Dev
   file extension differs from prod's, and the duration reads "28 h 04" in the app's own style.
   One assumption flagged to Tuur and not contradicted: his notes/captures stay behind with the
   bookmarks.

**Nothing else is in flight.** Both retractions from the 📦 design are recorded in that section on
purpose — don't let a later session rebuild what was cut.

**Merging back:** the branch forked at `ba4cbe9` and `main` has moved 7 commits since. None of them
touch the four files this branch changes in app code, so the only merge conflicts will be in the
docs (`backlog.md`, `FEATURES.md`, `roadmap/roadmap.yaml`).


## 🔋 2026-07-30 — Low Power Mode no longer stops a book transcribe (Tuur; FIXED; **sim gate PASSED 2026-08-11, device check owed**)

**✅ GATE RESULT (2026-08-11, Mac, this branch):** it compiles. `xcodebuild test -scheme SkriftMobile
-destination 'platform=iOS Simulator,name=iPhone 17'` → **`SkriftMobileTests` 1004 tests, 2 skipped,
0 failures**, including all 5 `BookTranscribePowerPolicyTests` cases. The `@MainActor` worry was
unfounded: `nonisolated` on the static func and the static let, plus the removed `powerModeObserver`
stored property, all build clean (the project is `SWIFT_VERSION: "5.9"`, so no strict-concurrency
checking). The UI suite failed 17 tests — **all pre-existing**, none from this change: 14 are on the
known iOS-26 list ([[project_xcuitest_ios26_failures]]), and the other 3
(`MemosListUITests.testSwipeToDelete`, both `ShareSheetActivationProbe` cases) were verified by
re-running them in a worktree at `b30021a`, the commit *before* the fix — identical failures, same
assertions. **Worktree gotcha:** a fresh `-derivedDataPath` needs `-skipPackagePluginValidation`
(and `-skipMacroValidation`) or the run dies on *"Plugin 'CudaBuild' from package 'mlx-swift' must be
enabled"* — the main tree has that trust already, a new worktree does not.

**✅ DEVICE-CONFIRMED 2026-08-11 (Tuur, build 136).** Removed the transcript, started it again,
turned Low Power Mode ON with the phone on battery: transcription kept running and climbed 0% → 7%.
Screenshot shows the yellow LPM battery and a live "Transcribing…" card. Old behaviour was an
instant pause plus the in-flight chunk cancelled. **🔋 is done, both gates passed.**

**Fell out of that test — 📖 a removed transcript stayed on the page (FIXED same session, b137).**
Tuur: *"you can see in the background the actual text is still there. So it did not actually delete
it."* The files WERE deleted; `ReadAlongModel` was holding its decode. Its reload guard
(`fileIndex != loadedFileIndex || fileLocal > loadedUpTo || !covered`) is false on all three counts
right after a removal, so it kept the old sentences until playback crossed the stale frontier.
`removeTranscripts` now posts `BookTranscriptStore.transcriptRemovedNotification` with the book id
and the model drops its sentences on it — one announcement, so a future in-memory reader listens
rather than each one learning to distrust its own cache. **Durable: deleting the files is only half
of a delete; anything that already decoded them keeps showing what you removed.**

**Report, verbatim:** "Book transcription should not be stopped On low power mode."

**Cause — one line.** `BookTranscriptionJob.shouldConserve` treated LPM as an explicit
"save battery" signal and auto-paused (`phase = .pausedUnplugged` + `cancelInFlightChunk()`):
```swift
guard !isPluggedIn else { return false }
if ProcessInfo.processInfo.isLowPowerModeEnabled { return true }   // ← gone
```
LPM is something people leave on for days, so this silently killed the one long-running job in the
app — a whole-book transcribe that never progresses, with no visible reason. iOS already throttles
CPU/ANE under LPM, so keeping it alive costs a slower run, not a flat phone.

**Fix.** Policy is now charge-only: pause below 20% ON BATTERY, never when plugged in. Extracted as a
`nonisolated static func shouldConserve(pluggedIn:batteryLevel:)` — a pure rule, so the behaviour is
unit-testable without draining a real phone (new `BookTranscribePowerPolicyTests`, 5 cases incl. the
regression guard, the boundary against the constant, and level `-1` = unknown must NOT read as flat).
The `.NSProcessInfoPowerStateDidChange` observer went with it (it fires only for LPM toggles, so it
was dead). Copy that promised the old behaviour fixed in both places: `TranscribeBookView` guidance
row and `BookTextSheet.transcribingMeta` ("runs on battery, pauses in Low Power Mode" → "pauses below
20%").

**Self-healing for a job stuck paused by the old rule:** battery-level notifications fire on every 1%
change and `powerStateChanged()` recomputes, so an LPM-paused job resumes within a minute or two of
this build landing — no migration needed.

**Known limit, NOT ours to fix:** iOS won't launch a `BGProcessingTask` while Low Power Mode is on, so
the *background* (app-closed) overnight path stays blocked in LPM regardless. Foreground/in-app
transcription — what "it stopped" actually meant — now keeps running. `requiresExternalPower = true`
on the background request is unchanged.



### ✅ ROUND TRIP PROVEN 2026-08-12 — a real bundle off Tuur's phone, imported and played

Tuur packed **In Praise of Shadows** on the device and handed over the file, so the outgoing half is
device-confirmed: **42,305,897 bytes**, extension `.skriftbookdev`, UTI `com.skrift.book.dev`
(rank Owner) — the Dev/prod type split is real, a test bundle can't reach the prod app. Imported it
into the iPhone 17 sim on the Dev build; every claim below was seen, not reasoned.

**The bundle:** `manifest.json` · `audio/book.m4b` (42.1 MB) · `cover.jpg` · `derived/transcript_f0.json`
(795 KB) · `derived/alignment_f0.json`. `textFilenames: []` — this book has no ePub, and the sheet
correctly said "Audio ·" rather than promising text.

**The privacy promise holds, in the DATA and on screen.** `sanitizedForSharing()` writes
`position: 0` + `playbackRate: 1` into the manifest, and the imported book shows **"1:28:20 left"
with an empty progress bar and 1×** — the recipient starts at the beginning of the book, not at
Tuur's place in it.

**What landed:** arrival sheet (cover · title · author · "1 h 28" · "Audio · 42,3 MB" · Add to my
books / Not now) → library row with cover → **plays, with read-along running off the shipped
transcript** → **"Ch 1 / 13"**, matching the manifest's 13 chapters. Re-offering the same file says
**"Already in your books"** instead of duplicating — the dedupe that is the whole reason the book id
survives `sanitizedForSharing()`.

⚠️ **One thing to clean up (noise, NOT a bug).** `derived/alignment_f0.json` is 201 bytes of dead
record: `verdict: "rejected"`, empty `sources`/`sentences`, empty `transcriptSignature` — but a
POPULATED `epubSignature` for an ePub that isn't in the bundle (removed on his device later). It's
harmless because `BookAlignmentStore.isFresh` compares transcript signatures and `""` can never
match, so a recipient who attaches their own text re-aligns from scratch. But it ships a stale
fingerprint of a file the recipient never gets. Cheap fix: `BookBundle.derivedSidecars` packs any
`alignment_f{i}.json` that EXISTS, with no look at its verdict — skip a rejected/empty one.

🐞 **UX nit, not from sharing:** the title reads "In Praise of Shadows - Junichiro Tanizaki" AND the
author line reads "Junichiro Tanizaki", so the author appears twice in both the arrival sheet and the
library. Root is the original import naming the book from its filename.

**AirDrop / Messages between two physical devices — TUUR'S CALL 2026-08-12:** *"ill assume it works
and tell you if it doesnt."* Not tested, deliberately not blocking. **BookShare is `done` on the
roadmap on that basis** — if a real hand-off ever fails, the untested link is document-type routing
in the wild, not the packer, importer or either sheet (all three are proven above).

**Queued, not done:** the rejected-alignment skip in `BookBundle.derivedSidecars` (one guard), and
the duplicated-author title nit.

---

## ⭐ CONTINUE HERE — 2026-08-20 (rate→row fixed + promoted; the picture-collapse found)

**PROD PROMOTED 2026-08-20 ~09:07 and VERIFIED ON HIS REAL DATA.** The log is the proof:
the old binary (pid 20894) logged `reconcile: ingested 0`; the new one (pid 23469) logged
**`reconcile: ingested 2`** on its first sweep — his two missing notes, back with rows.
Connections went 42 → 44 memos. No `STRANDED` lines, `ingest-failures 0`. `/Applications/
Skrift.app` string-grep verified (Aug 20 08:42 binary, "STRANDED: rated memo" ×1). NOTE: he
had prod OPEN when I swapped it — I quit it and relaunched it, so his window is fresh.

**🖼️ THE PICTURE-COLLAPSE — root-caused + fixed the same session.** Tuur: paragraphs
appeared after processing "and then they collapsed again. Probably because there's a picture
in there." He was right about the picture. `ImageMarkerReinsert.extractAnchors` flattened
`\s+ → " "` when stripping `[[img_NNN]]` markers — and that stripped text is what the model
is FED whenever a note has a photo (`input = imgNums.isEmpty ? linkStripped : stripped`). So
a photo was the ONE thing that destroyed the author's paragraphing before copy-edit ever ran,
and Gemma at temperature 0 will not put breaks back (`ensureParagraphs` exists because it
won't) — it re-grouped the text into machine paragraphs of ~4 sentences instead, which is
exactly what "collapsed" looks like. Now only HORIZONTAL runs collapse; blank lines survive,
≥3 breaks normalise to one. Proven both ways: the new tests reproduce the wall verbatim when
reverted. Blast radius is tight — a note with NO picture never used that string.
LEFT ALONE (worth knowing): `ensureParagraphs` only fires below 2 newlines, so a long output
with 2–3 stray breaks still passes as "paragraphed". Not touched — widening it risks
re-paragraphing text somebody structured deliberately.

**PROMOTED AGAIN with the picture fix, 09:31** — `/Applications/Skrift.app` is the Aug 20
09:31 binary, verified by three literals inside it ("copy-edit paragraphs", "STRANDED: rated
memo", "waiting for its audio"). Prod was 0% CPU / no log activity for 24 min, so the swap
cost nothing. Relaunched; sweep clean (`ingested 0`, no STRANDED).

**📏 NEW: the paragraph ledger.** Every copy-edit now logs three numbers — what the note HAD,
what the model gave back, what shipped:
```
log stream --predicate 'subsystem == "com.skrift.desktop" AND category == "paragraphs"'
```
(`log show --last 10m …` reads it retroactively.) It answers "did copy-edit do anything" in
one run, and it exists partly because the picture fix is pure regex: Swift stores short string
literals inline, so nothing in that fix was string-greppable — a promotion of it could not be
verified the CLAUDE.md way until this line existed. **When Tuur runs his redo, read this log:
`in N → model N → shipped N` names the culprit immediately.**

**Bin done:** 1924 test-fixture folders (identical 5-byte `AUDIO` blob) moved to
`~/.Trash/SkriftDevTestLitter-2026-08-20/`; 45 real folders left, 85 MB → 77 MB.

---

## (prev) ⭐ 2026-08-20 morning (the rate→row handoff, fixed)

Branch `main`. **The rate→row fix is committed and gate-green (desktop 744/0, MLX build
green) but NOT on Tuur's Mac yet** — the full write-up is the 🔴→✅ entry below. What it
needs from him:
1. **"prod is idle" → promote.** The Release is already BUILT + string-grep verified at
   `Skrift_Native/SkriftDesktop/build-release/Build/Products/Release/Skrift.app`; the swap is
   one command. Then his two stuck notes should appear with their already-written
   enhancements — and any prod-side stranded notes surface with them.
2. **The slab-note redo outcome** on the new prod (started 2026-08-19, never reported) —
   the deterministic paragrapher should guarantee paragraphs.
3. **Device eyeball owed:** m2 photo-thumb rows + book-quote rows (iPad b155 / Dev Mac).
Still parked: Mac list thumbnails (3b, cached loader), Mac place/tags chips, picture
drag-reposition + mixed-share placement (design first), perf (Instruments, don't guess).

---

## (prev) ⭐ session wrap 2026-08-19 (copy-edit forensics + m2 un-twinning)

Branch `main`, clean, everything pushed (head `64c88aa7`). **Next chat = the RATE→ROW
HANDOFF fix — kickoff board lives in the 🖥️ m2 entry below ("⭐ NEXT-CHAT KICKOFF").**

**Done + VERIFIED today:** copy-edit fix wave (dynamic budget, shrink guard, deterministic
paragraphs, visible errors) — proven by harness on Tuur's exact note + 6-fixture sweep;
prod stale-binary regression found + fixed (string-grep rule now in CLAUDE.md); m2 shared
NoteCardView on BOTH lists (b155 iPad verified via devicectl; Dev Mac checksum-verified;
Tuur's eyeball caught + we fixed the quiet-row double date). iPad verbs wave (b149–155:
header Record/✎, chrome Export three-state, Redo submenu, Settings simplified, export
honesty) — all sim-proven, Tuur-eyeballed through the day.
**Done but UNVERIFIED:** the slab-note redo on the new prod (Tuur started it; outcome
unreported); m2 photo-thumb rows + book-quote rows on device (code ported, not eyeballed).
**Blocked/parked:** Mac thumbnails (3b — cached loader); Mac place/tags chips; picture
drag-reposition + mixed-share placement (design first); perf feel (Instruments, don't
guess); phone still on b148.

---

## (prev) ⭐ session wrap 2026-08-14/18 (the iPad-polish + vault-export marathon)

**2026-08-18 morning session on top of this wrap:**
- **iPad b148 installed** (unlock + attempt 4) → **Tuur confirmed the amber** on the device.
- **Mac prod verified alive**: up since Aug 14 17:07, 3.5 days, zero crash logs.
- **Gates re-run clean**: desktop 734/0 twice; mobile green (one OCR warm-up flake on the
  freshly-erased sim, passed in isolation; suite now 1029 tests with the new factory test).
- **Tuur voice feedback triaged** (2 items → the 🐢 and 📝 entries below): app-feels-slow
  (investigate with Instruments, don't guess) + Apple-Notes-bar note editing.
- **iPad verbs → the Mac's places BUILT** (`5de2b71c`, **b149 installed on the iPad**, verified
  via devicectl): header = Import · Record · ✎ + Process full-width (corner FAB yields at
  regular width); chrome band = three-state primary (Process → Export to Obsidian → Re-export)
  · ⋯ (＋ folded in as `NoteMenuItem.addRecording`) · Connections; typed notes born on the iPad
  via shared `Memo.newTyped`; rows stop calling a typed note a 0:00 "Voice note".
  Sim-proven visually (header, ✎→type→title-derives, Export on a polished note).
- **b149's Export tap came back "nothing happened" (Tuur, same morning) → fixed in b150.**
  Two real bugs behind the silence: (1) `exportNow` was `_ = try?` around a gate that
  returns nil — **five silent refusal paths**, and his iPad has no vault bookmark (they're
  per-device, they don't sync); (2) the per-note export read author from `skrift.author`,
  a key NOTHING writes — Settings writes `skrift.publish.author` — so every per-note export
  compiled with a blank author line and the same note would diff across devices (the edit
  guard would then refuse forever). Now: `PublishCoordinator.exportRefusal` names the first
  failing gate BESIDE `shouldPublish` (tested, wording pinned), every outcome answers
  (refusal → alert, back-off → alert, write → "Exported ✓" flash then Re-export), right
  author key. Sim-proven: the exact no-vault tap now alerts "No vault folder is set on this
  device yet. Pick one in Settings → Obsidian."
  **OWED: Tuur on b151 — Settings → Obsidian → pick the vault folder (+ set Author to match
  the Mac's), then the Export tap again (expect "Exported ✓" → Re-export, file in the vault).**
- **The Settings toggle + "Export now" are GONE (b151).** Tuur, same morning, on seeing them:
  *"iPad can export so it should, Mac can export so it should, phone cannot so it should not"*
  and exporting "can be done in the app itself… not in settings". Doctrine: **the picked folder
  IS the consent** — nothing on iOS auto-publishes (verified: the only publish callers were the
  per-note button and the deleted Settings button), so the toggle was a third consent stacked
  on two. The old `skrift.publish.obsidianEnabled` key is dead and deliberately unread (devices
  that had it false don't stay silently off). Settings → Obsidian is now just Folder + Author.
  `publishAll` stays as the engine for a future in-app bulk verb (the frontmatter bulk
  re-export, if ever) — it has no UI today.
- **🔎 "Does copy-edit even work?" (Tuur, same morning) — ROOT-CAUSED + FIXED (b152 + Mac).**
  The symptom: a massive note polished with no visible change, no paragraphs; Mac redo no
  different. The mechanism: both native engines hardcoded **`maxTokens: 1024`** for copy-edit
  output — a long note generates into the wall, comes back cut mid-text, the memo-link escrow
  (rightly) refuses the loss and silently ships the RAW body; at temperature 0 a redo fails
  byte-identically. Tuur remembered dynamic per-memo sizing — that was the **Python era**
  (`_effective_max_tokens`: input×1.2, floor 256), lost in both native ports. Restored,
  single-sourced in `PolishPrompts`: `copyEditTokenBudget(forInput:)` = est-tokens ×1.5,
  floor 1024, ceiling 8192; plus a truncation guard (`looksTruncated`) so an output that
  fills the cap keeps the unedited body — a raw note is honest, a half note is data loss.
  Both engines wired; budget + guard pinned by `IPadPolishTests`.
  NOTE: a **conversation** (diarized) note skips copy-edit BY DESIGN (the turn structure is
  the only copy of the diarization) — but those render as speaker turns, not a heap.
  **His broken note self-heals via Mac ⋯ → Redo → Copy-edit once the Mac runs this code**
  (the iPad has no re-polish verb on an already-polished note — the Mac's Redo is the tool).
  **OWED: Mac prod promotion (Release staged, waiting for Tuur's go — prod is in use), then
  the redo on the real note.**
- **Mac prod PROMOTED with the budget fix** (Tuur's go "prod is idle", ~11:20): new
  /Applications/Skrift.app running. **Skrift Dev NOT updated** — Redo experiments belong in prod.
- **The iPad gets the Mac's Redo ▸ Title / Copy-edit / Summary (b153).** Tuur: the iPad ⋯
  "should work like mac in that menu… same redo options. shared code again." Shared vocabulary
  (`NoteMenuItem.redo` + `NoteRedoItem`), engine `redo(part:)` reuses the SAME prompts/escrow/
  budget via one `copyEditGenerate` helper (full polish + redo can't drift), PolishCenter
  writes the part into the EXISTING enhancement (LWW stamp). Gates: copy-edit hidden for
  conversations (turn structure is the only diarization copy), offered only where polished +
  engine available + unlocked. Sim-eyeballed: submenu renders in the Mac's position.
- **🖥️ SIGNED OFF: the Mac's notes list gets the iPad's card — m2, and BOTH apps render it
  "to the T"** (mock `mocks/mac-notes-list-rich.html`, Tuur picked m2 2026-08-18 ~11:45:
  "m2 looks best, build that. make sure the ipad also follows that one to the T").
  Build shape = the SignificanceCircles cure: ONE `Shared/UI/NoteCardView` (m2 rules:
  stamp+pill line, title+fading chip, quote idiom, 2-line snippet, chips row, 44pt thumb,
  locked/quiet variants) + `NoteCardStyle` per app + per-app model adapters (mobile: `Memo`
  — the current `MemoCard` derivations move into the adapter; Mac: `SidebarEntry`
  (PipelineFile/Memo) + a MemoAsset thumbnail read + sidebar width step to ~290).
  Ride-alongs: raw `memo_…` titles → shared `emptyTitleFallback`; Mac glyphs → `SourceKind`.
  ✅ CHUNK 1 SHIPPED (c4dbd74b): `Shared/UI/NoteCardView.swift` — model+style+m2 layout,
  compiles in BOTH apps (xcodegen re-run both). NEXT: chunk 2 = iPad adapter (move MemoCard's
  derivations — snippet/hasTitle/chips/photo tile/book quote/glyph — into a Memo→NoteCardModel
  mapper next to MemosListView, render NoteCardView, keep row a11y ids; leading source-glyph
  column stays OUTSIDE the card на iPad? NO — m2 has no leading glyph column: the glyph moves
  into the chips per the mock; verify against mock before render). Chunk 3 = Mac adapter
  (SidebarEntry→model: queueTitle→emptyTitleFallback fix, snippet from transcript, chips from
  cloud Memo metadata, MemoAsset 44pt thumbnail loader, sidebar width →~290, keep StatusPill
  feed from queueStatus). Then renders both sides, gates, b155 + Mac Dev deploy for eyeball.
  ✅ CHUNKS 2+3 SHIPPED (24f0fc40, 637dbd16): iPad/phone AND Mac lists render the ONE card.
  b155 on the iPad (verified); Dev Mac deployed + dylib-verified, running. OWED: Tuur's
  eyeball both sides; chunk 3b = Mac thumbnails (cached loader, not per-row decode); Mac
  place/tags chips (join via cloud Memo) if Tuur wants them.
  ⭐ NEXT-CHAT KICKOFF (Tuur's call): the RATE→ROW HANDOFF fix — board above ("🔴 NEXT UP…
  rate→pipeline handoff"). Read that entry + the 🔴 ESCALATED addendum; repro = paste text
  into a Mac ✎ note, rate 0.1 → no Process button, invisible in list, relaunch reaps the
  row while 3 cloud copies sit safe. Fix = author a PipelineFile when a rated memo has no
  row (mind the self-echo ingest guard) + the sweep ADOPTS orphans, never reaps. Spine
  code — tests first.
  Status-pill POLICY stays per-app data, not layout: the Mac always shows its pipeline state
  (its dashboard); the iPad keeps pills for in-flight/error only (locked doctrine: an
  always-on badge is no signal). Board: (1) shared view ✚ style ✚ xcodegen both, (2) iPad
  adoption + render eyeball, (3) Mac adoption + Dev deploy for the eyeball, (4) b154 +
  prod promotion after sign-off.
- iPhone stays on b148 (no phone-facing change worth a push; rows for synced typed notes
  pick up the ✎/"Note" fix at the next promotion).

### 📸 Tuur feedback 2026-08-18 ~12:15 — the WhatsApp-share picture
- **Copy-edit hunt continues:** engine + budget PROVEN by `-copyeditcheck` (6181-char seeded
  wall → 8 paragraphs, all errors fixed, 70s). His note: NOT Dev, no links, not a conversation,
  HAS a picture — and images never cause the raw fallback (`ImageMarkerReinsert` degrades
  position, still ships). Remaining suspects: the 8192 ceiling guard (logs "token cap") or
  model echo. Live `log stream` monitor armed on com.skrift.desktop; ONE prod redo names it.
- **Share-import placed the picture wrong** (8 WhatsApp voice memos + 1 picture → one note;
  the `[[img_NNN]]` marker landed in the wrong spot). Trace the mixed-share drain's marker
  placement (AudioShareDrain / share-ingest merge).
- **Can't drag a picture to reposition it in the note** — wants direct manipulation. New
  editor interaction ⇒ DESIGN/MOCK FIRST (locked process) before any code.

### 🔬 COPY-EDIT TEST SWEEP — six failure classes, real engine, 2026-08-18 ~12:45 (NO fixes yet, Tuur's order)
Harness `-copyeditcheck` × 6 fixtures (scratchpad fx1–6; stats = chars·words·newlines·¶):
1. **12k wall, seeded errors → ✅** edits + 8¶ (68.8s).
2. **24k ceiling → ⚠️ UNTESTED**: fixture was ×4-repetition, model deduped to 720 words so the
   8192 ceiling never engaged. Needs a NON-repetitive ~24k fixture for a true ceiling test.
3. **Image markers mid+end → ✅** both `[[img_NNN]]` survive reinsert, text edited, 11¶.
4. **HIS WhatsApp shape (8 blocks \n\n + marker) → ✅** at 1.2k chars: 9¶ kept, marker kept,
   errors fixed (one light miss). Real note is longer — length untested at this shape.
5. **🔴 UNBOUNDED SHRINK IS REAL**: Dutch wall of 14 repetitions → 65 words (7% of input!).
   Prompt-compliant on synthetic repetition, but NOTHING guards output/input ratio — a real
   circling ramble can silently lose big chunks. `looksTruncated` only catches cap-filling.
   FIX CANDIDATE (not implemented): shrink guard, e.g. output <50% of input words → keep raw
   + log (tune threshold; dedup of true repeats is desirable, wholesale loss is not).
6. **Clean text, no errors → ✅ still paragraphs (9¶)** — the echo hypothesis is BUST.

**🎯 ROOT-CAUSED 2026-08-19 (store read, lengths only):** his note `5B628903…`: raw 7789
chars/6 newlines → copyedit 4118 chars/**4 newlines** — and 4 = exactly the \n\n pair around
the reinserted `[[img]]` marker: the model's own text came back as ONE UNBROKEN BLOCK. fx5
(Dutch) reproduces it: **Gemma adds NO paragraph breaks on Dutch-dominant text** (English
fixtures all paragraphed fine). Plus a 47% shrink (7789→4118) — possibly real content eaten
(the fx5 class), not just fillers. Display/routing exonerated; earlier hypothesis below kept
for the record. FIX CANDIDATES (NOT built — Tuur picks): (a) language-neutral paragraph
instruction in the prompt, and/or a deterministic `Paragrapher`-style sentence post-split
when the model returns <2 breaks; (b) STOP collapsing the raw's \n\n joins in the
image-marker path (protect them like quotes — appended-memo boundaries are real structure);
(c) the shrink guard (output <~55% of input words → keep raw + say so).

**✅ GREEN-LIT by Tuur 2026-08-19 ("do them") — the copy-edit fix wave, build board:**
1. ❌ PROMPT REWORD REFUTED BY THE A/B (2026-08-19): prompt B on tuurnote → 7797 chars ·
   4 newlines · 3¶ — the SAME near-echo; fx5 unchanged too. The ambiguous line was NOT the
   cause; the model won't paragraph long Dutch/mixed at temp 0 under any wording. Fix 2 is
   therefore THE cure, not a fallback. (Original plan kept for the record:)
   PROMPT REWORD (A/B-prove first on tuurnote.txt via harness `-copyeditprompt <file>` flag):
   replace the ambiguous line "The author may switch between English and Dutch mid-sentence —
   this is intentional, keep it exactly as-is." with "The author may switch between English
   and Dutch mid-sentence. Keep each sentence in the language it was spoken — never translate.
   Everything else (fillers, spelling, punctuation, paragraph breaks) must still be cleaned up,
   whatever the language." → lands in Shared/Pipeline/PolishPrompts.copyEdit (BOTH engines) +
   ⚠️ prod's user_settings.json carries a prompt OVERRIDE (764 chars, old wording) that will
   SHADOW the new default on the Mac — migrate/clear it or the Mac keeps the bug.
2. PARAGRAPH FALLBACK: if model output has <2 newlines and input >~600 chars, deterministic
   sentence-split (~3-5 sentences/para) — pure Shared helper beside the escrow, both engines.
3. SHRINK GUARD: output words <~55% of input words → keep raw + log (beside looksTruncated).
4. SURFACE coordinator.lastError on the Mac (SidebarView:344 says nothing reads it) — small
   banner/flash near the note toolbar; same honesty class as the iPad Export alert.
🔴→✅ **FIXED 2026-08-20 — THE RATE→ROW HANDOFF.** Root cause, found by reading the ingest
path rather than the symptom: a memo with **no audio and no `sharedContent`** — i.e. every
note somebody TYPED — fell through BOTH arms of `UploadService.prepare`, which returned an
EMPTY descriptor array, so `MemoCloudIngest.ingest` handed back `nil` on every sweep,
forever. Rating it then removed it from the quiet rows (those are the UNRATED memos), so it
rendered in NO list section. **Nothing ever reaped anything** — the row simply never
existed (the launch "reap" in the escalation below was a wrong guess; `DesktopTrash
.purgeExpired` only touches rows already trashed ≥14d, and no other code deletes a
`PipelineFile`). The fix, tests first (each one verified to FAIL with the fix reverted —
7 failures):
1. **Text-only memos ingest as `.note` rows** (`UploadService.prepareText`, body →
   `original.md`, transcribe `.done`, typed marker kept → ✎ "Note" glyph not "Apple Note").
   The `textOnly` decision is the CALLER's (`MemoCloudIngest.isTextOnly`), never sniffed
   from the parts: "no audio part" also describes a voice memo whose blob hasn't synced yet
   (CloudKit trails by hours), and turning one of those into a text row would strand its
   audio permanently.
2. **A FRESH row adopts a `MemoEnhancement` this Mac wrote** (`MemoCloudUpdate
   .apply(isFreshRow:)`). The self-echo guard (skip an enhancement from THIS device) is
   right for a row that already holds the polish and wrong for a row created seconds ago —
   that guard is why his copy-edit sat in the store (16 newlines, 8 ¶) while the open note
   showed the raw blob.
3. **Nothing invisible, ever again**: `SweepOutcome.stranded` counts + logs any rated live
   memo the sweep left rowless, and `WayOutRules.stranded` renders those in the list (they
   stay out of the "N not rated" count + Process-all — they ARE rated).
4. Ride-along: the m2 card's filename-leak guard tested the `memo_` PREFIX shape; it now
   tests "no title AND no body", which covers every filename shape (typed rows are
   `<uuid>.md`).
Gates: **desktop 745/0** (734 + 11 new), full MLX build green.

**Proven on the REAL store, not just in memory.** New DEBUG verb `-ratetorow` runs the whole
repro headlessly against the live store (author a typed note → paste → rate 0.1 → real
reconcile → report the row → clean up after itself). On the Dev store: `.note` row, ✎ "Note"
glyph, title from the first line, body on disk, `needsProcessing` true.

**It also found TWO memos already stranded in the Dev store** — audiobook quotes from
2026-06-11, rated 0.5, whose audio assets never synced: invisible on that Mac for two
months. They can't ingest (an audio memo must keep WAITING for its blob, never become a text
row — that would rob it of its audio permanently), so the floor is what they get: they now
render, with the honest line **"waiting for its audio"**. The spine would have said
"processes on next run", untrue for two months. Eyeballed via a new `-snapshot-stranded`
render — the first wording clipped mid-sentence at sidebar width, so the copy is short by
design. Same class may exist in PROD; the promotion will show.

**Ride-along caught on the way:** `MemoCloudReconciler.sweep` reached `UploadService()`
directly, so every sweep test since 8d materialised ingest folders into the LIVE Dev data
folder (`~/Documents/…Audio Output Dev` — **1987** of them, ~9 more per run). The sweep now
takes an injectable `UploadService`; tests use a temp dir they delete. Verified: folder count
identical before and after a full run. Today's 18 fixture folders went to the Trash; **the
~1969 older ones are still there — Tuur's call whether to bin them.**

**Mac Dev DEPLOYED + dylib-verified** (`/Applications/Skrift Dev.app`, running).
**Mac Release STAGED at `Skrift_Native/SkriftDesktop/build-release/Build/Products/Release/
Skrift.app`, built from HEAD, string-grep verified** ("waiting for its audio" ×1,
"STRANDED: rated memo" ×1) — the installed prod (Aug 19 10:16) has NEITHER, so the before/
after is clean. **AWAITING Tuur's "prod is idle" go for the swap.** His two stuck notes
surface after it, not before.

🔴 (superseded — kept for the trail) **NEXT UP (2026-08-19 ~10:40, Tuur live round): the RATE→PIPELINE HANDOFF on the Mac.**
Store proof: the pasted children's story (B32E8FC9) carries 16 newlines (8 ¶) in BOTH
copyedit AND sanitised — the fix wave works end to end. But the OPEN VIEW kept showing the
raw blob and the note VANISHED from the left list the moment he rated it (0.1) — the unrated
pane doesn't hand over to the fresh pipeline row (stale MemoNoteProjection), and the list
shows it in neither section. He saw "paragraphs then recompaction" = the same stale-view
flap. ALSO reported: right-click delete is slow; a new pasted note didn't appear in the list
then "disappeared"; general slowness (feeds the 🐢 perf entry — Instruments, don't guess).
FIX: trace RootView's rating handover (activeID → pipeline row swap) + list refresh on
rate; reproduce with a pasted typed note + 0.1 rating.
🔴 ESCALATED (11:00, after relaunch): the note went fully INVISIBLE on the Mac — but the
DATA IS SAFE: cloud store holds 3 copies of the story (2 alive incl. the 0.1-rated one, 1 in
trash from his slow right-click delete); the launch sweep DELETED the orphan pipeline row
instead of adopting it. So on the Mac a rated-but-rowless memo renders in NO list section =
looks like data loss. The iPad shows it fine (reads the cloud store). THE fix = the rating
handover + the sweep must AUTHOR rows for rated row-less memos, never reap them silently.
⭐ SECOND SCREENSHOT (10:50) PINS IT: "Rated — ready to process" card + NO Process button
= the view is the UNRATED PROJECTION (copyOnly NoteActions hides pipeline verbs) — the
rating never authored/attached a PipelineFile for a MAC-BORN pasted note. Suspect: local
rating writes the cloud Memo but nothing triggers MacMemoAuthor.backfill / the reconcile
sweep (it runs on SYNC events, not local edits) → no row → no verbs, no list section,
raw body. WORKAROUND told to Tuur: relaunch prod (launch sweep backfills). His paragraphs
(16 \n in store, B32E8FC9 = the FIRST vanished paste) surface once a row exists.

🔴→✅ **THE STALE-PROD POST-MORTEM (2026-08-19 ~10:20)** — both of today's Mac swaps shipped
a **June 14** binary: Release builds without `-derivedDataPath` land in DerivedData, but the
staging path `SkriftDesktop/build/Build/Products/Release/` still held the June relic, and the
"verify" was pgrep, not content. Prod REGRESSED all morning — June code loads the UNPINNED
model revision → the re-uploaded repo's k_proj wall (the iPad's 2026-08-12 crash class) →
every Redo failed in ~2s with the error swallowed (June predates the lastError strip). All
of today's Mac symptoms explained. NOW: `/Applications/Skrift.app` = the real Aug 19 build,
**verified by string-grep of the fix literals inside the installed binary** (the Mac sibling
of the iOS UDID trap). ⭐ RULE: Mac promotion = ditto from DERIVEDDATA (or pass
-derivedDataPath) + string-grep a fix literal in /Applications before claiming swapped.
(iPad builds unaffected — devicectl version checks were real.)

✅ WAVE SHIPPED 2026-08-19 (f67b135d): shrink guard + ensureParagraphs (the wall cure —
deterministic, both engines) + lastError strip on the Mac; prompt reword REFUTED and dropped.
All gates green. **b154 on the iPad (verified). Mac Release STAGED at
SkriftDesktop/build/Build/Products/Release/Skrift.app — awaiting Tuur's "prod idle" go**;
his slab note heals via prod ⋯ → Redo → Copy-edit after the swap (paragrapher guarantees
breaks whatever the model does). THEN back to the m2 shared NoteCard build (signed off).

**🎯🎯 FINAL VERDICT 2026-08-19 (his EXACT note through the harness, out of process):**
ran clean in 129.2s — NO throw — and returned a **NEAR-ECHO**: 7790→7780 chars, 1434→1432
words, 7→4 newlines, 3¶. On HIS real Dutch/mixed text the model removes nothing, fixes
nothing, adds no paragraphs — while my synthetic English fixtures all edited fine. THE
"copy-edit does nothing" is model behavior on his real content, not pipeline. CONFIRMED
DEFECT LIST (test phase COMPLETE, nothing built — Tuur picks): (1) near-echo on real
Dutch/mixed text → prompt work on the Mac (the tuning bench), few-shot or stronger
instruction; (2) no Dutch paragraph breaks → language-neutral prompt line + deterministic
sentence post-split when model returns <2 breaks; (3) unbounded shrink (fx5; his STORED
4118-char copyedit = 53% of raw, written by an earlier run) → shrink guard;
(4) **prod's 2s redo = a swallowed error**: out-of-process load works, so prod-specific
(likely model load/memory), and `coordinator.lastError` renders NOWHERE (SidebarView:344
admits it) → surface it (same silent-failure class as the iPad Export, third of the day).

(superseded) **Therefore Tuur's "still the same" is NOT the engine.** His redo logged NO fallback and the
engine provably edits every tested shape. Top remaining hypothesis: **the DISPLAY never shows
the copyedit for his note's class** — the note came from a WhatsApp mixed share (8 audio + 1
picture): if it carries capture/share flags, the iPad's `macPolish` guard (`isShareCapture` →
nil) hides polish outright, and the Mac's capture rendering may bypass sanitised too. NEXT
TEST (still no fixes): trace AudioShareDrain/mixed-share routing — what flags does the merged
memo carry, and does `MemoNoteProjection`/`NoteDisplayView` render copyedit for it? Also ask
which device he's LOOKING at.


Branch `main`, everything committed and pushed (head `9e83d259`). All six installs are current
except the iPad, which was locked at the end.

### ✅ Done AND verified this session
- **The iPad polishes.** Three stacked walls, each hiding the next — model revision pinned
  (`PolishPrompts.defaultModelRevision`), mlx-swift-lm floor raised to `e6e3de75`, and the
  `increased-memory-limit` entitlement. Device-confirmed: `polish: wrote enhancement`.
- **Export works end to end on the Mac**, read on disk, not assumed: notes in `<pick>/Skrift/`,
  audio in `Skrift/Recordings/`, frontmatter in the new grouped order with the stamp trio last.
- **Mac prod promoted** off the 26 June build — and the reason it was stuck is now documented:
  `xcodebuild -configuration Release` CANNOT build without `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`
  as **CLI args** (CoreML-LLM's x86_64 slice fails on `Float16`; the same keys in project.yml
  do nothing, because SwiftPM package targets inherit neither the target's nor the project's
  settings). In CLAUDE.md now.
- Gates run this session: **desktop 734/0, mobile 1028/0.**

### ⚠️ Done but NOT verified on a device
- **The amber refine colour** — ✅ **CLOSED 2026-08-18**: b148 installed on the iPad (attempt 4
  after unlock) and **Tuur confirmed the amber on the device**.
- **Mac prod** — launched: up since Aug 14 17:07 (3.5 days, zero crash logs, window on screen,
  checked 2026-08-18). Tuur's own glance still the last box.
- **Per-note Export on the iPad** — superseded 2026-08-18: the export verb moved INTO the chrome
  band (see the 2026-08-18 session block below); exercising it on device is owed there (b149).

### 🔴 Open, in priority order
1. **`ConnectionsPanel` is twinned** (683 + 593 lines) and drifted — the Mac draws rows as
   cards, the iPad draws them bare. Fix shape proven on `SignificanceCircles`: one shared view
   + a per-app style table + a render diff proving the good side doesn't move. See the 🕸️ entry.
2. **The rating line is stateless** — says "Rated — ready to process" on a note already
   processed. Needs the note's work state handed to the significance control.
3. **Frontmatter migration is per-note.** Old exports keep the old key order until each is
   re-exported; there is no bulk re-export. Tuur was fine re-exporting by hand.
4. **`0.8`-vs-`0.2` counts in Connections (13 vs 4) were two DIFFERENT notes** — not evidence
   the iPad's index is thinner. Re-check on one note before treating it as a bug.
5. ⚠️ **Mac Dev's vault setting was pointing at the real iCloud vault at 16:09 and at the test
   vault later**, and Tuur says he didn't change it. ONE observation, not a pattern — but a
   vault path that moves on its own decides which folder gets written. Watch it.

### Doctrine set this session
- **Processed is processed, whichever device ran it** (`NoteWorkState`) — local step flags are
  not facts about a note; the enhancement is.
- **The picked folder resolves to the folder Skrift owns** (`VaultLayout.home`): pick `0 Inbox`
  or pick `0 Inbox/Skrift`, land in the same place, move nothing. The NAME check is load-bearing
  — the `skriftID` stamp only arrived 2026-07-26, so pre-stamp folders have no stamp to find.
- **The model is a dependency and is pinned like one.** It was the only floating one.

---

## 🐢 OPEN — the app feels slow next to other apps (Tuur, 2026-08-18, voice)

*"the app seems kind of slow compared to other apps. It might just be that it's running a big
transcription model while it's doing other shit."* His idea: for slower phones, record only and
transcribe later instead of live transcription.

**Checked against source before theorising:**
- Post-hoc transcription IS already the pipeline — the raw transcript is produced after Stop;
  the live caption is an extra concurrent decode for feedback only.
- The live caption already auto-stops after 60s (`liveCaptionAutoOffSeconds`, picker in
  `SettingsView.swift:77`). A "no live caption" option would be a cheap experiment, but it only
  helps WHILE recording.
- General slowness (outside recording) can't be the ASR model — it isn't loaded at launch. The
  launch/foreground pile-up is the candidate: every foreground fires MemoDeduper + migration +
  FadingSweep + CaptureInboxDrainer + AssetMaterializer + PhotoTextIndexer + ReminderScheduler +
  2 cloud syncs + JournalIndexService sweep (`SkriftApp.swift:169–192`).

**Next step is measurement, not guessing:** an Instruments profile on the iPhone 13 (hangs +
time-profiler over a normal open-scroll-open-note minute). Nothing built until profiled.

---

## 📝 OPEN — note creation + editing: "Apple Notes is the bar" (Tuur, 2026-08-18, voice)

*"Sometimes I just wanna start a note."* Wants a new-note button on the phone and iPad — the Mac
already has one (`SidebarView.swift:264`, ⌘N); phone and iPad have NO text-first note creation
(verified: no such affordance in `SkriftMobile/Features`). And the editing experience itself
isn't great next to Apple Notes — he suspects bloat.

- **iPad half ✅ BUILT same day** (`5de2b71c`, b149, with the header unification he asked for in
  the same message): ✎ beside Import·Record, shared `Memo.newTyped` author, ⌘N. Sim-proven:
  tap → empty unrated note → type → first line becomes the title, row updates live.
- **Phone still has no create** (compact header untouched — his ask named the iPad and Mac).
- **Editing feel vs Apple Notes stays OPEN.** Overlaps the parked kickoff **capture-as-note +
  note-editing follow-ups** (deferred 2026-07-07) and the PARKED note-detail mock. New UI =
  **mock first** (locked process); editing-feel work should start from a profile of the editor
  view, not a rewrite on suspicion.

---

## ✅ CLOSED 2026-08-18 — the iPad's note button says "Process" for a note already processed

**Both halves built.** The rule went shared 2026-08-14 (`NoteWorkState`); the chrome band got the
full three-state primary 2026-08-18 (`5de2b71c`, b149 on the iPad): Process → Export to Obsidian
→ Re-export, in the Mac's position. Sim-verified visually; the Re-export flip needs a configured
vault, so Tuur's device tap is the last box. Original entry kept below for the reasoning.

## (was) 🔴 OPEN — the iPad's note button says "Process" for a note already processed

Tuur, 2026-08-14, on an iPad note carrying a real title, summary and copy-edit.

**Narrowed with him, by the Done chip — the counts are CORRECT.** Tapping Done shows exactly
that note, so `enhancedMemoIDs` sees its `MemoEnhancement` and `ProcessPile` is behaving:
"1 ready to review · 24 to process" was right, the note IS the 1. Enhancement visibility is
NOT the bug; earlier suspicion of two stores is dead.

**The bug is the per-note primary action.** `PolishCenter.canPolish` deliberately keeps an
already-polished memo eligible ("a re-run overwrites by LWW"), which is right for a ⋯ verb
and wrong for the primary button. The Mac already models this properly —
`NoteActions.primaryLabel`: `!enhanceDone → "Process"`, else `exported ? "Re-export" :
"Export to Obsidian"`. The iPad has one state where the Mac has three.

**Tuur's principle, and it's the right one:** *"if there is a Mac enhancement, I should be
able to export it on the iPad. The enhancement has been done."* Processed is processed,
whichever device did it — which is exactly what `ProcessPile` already encodes by keying on
`MemoEnhancement` rather than on any device's local step state.

**Fix:** hoist the Mac's three-state label into Shared and give the iPad the same primary
action. Note the iPad's export gate is `PolishCenter.isAvailable` (it can process, so it may
export); the phone keeps no export at all.

⚠️ **And fix the blindness first if this recurs:** PROD writes NO DevLog (`DevLog` is
DEBUG-only), so every diagnosis on 2026-08-14 came from the Dev app. An hour went into
guessing at prod state that a two-line trace would have answered.

---

## ⏳ OWED — the two `ConnectionsPanel` VIEWS are twinned, and have drifted

Tuur, 2026-08-14, comparing Mac and iPad side by side: *"ipad vs mac connections tabs look
different. the mac is way bigger. ipad still has space"* and *"closest on ipad also loose not
as good as on the mac"*.

`SkriftDesktop/Features/Review/ConnectionsPanel.swift` (683 lines) and
`SkriftMobile/Features/MemoDetail/ConnectionsPanel.swift` (593) are separate hand-built
implementations of one design (`mocks/related-panel.html`). Same disease as
`SignificanceCircles`, same cure: one shared view + a per-app style table.

**Checked before believing — two of the three complaints are NOT defects:**
- **CLOSEST MATCH is not missing on the iPad.** Identical logic both sides
  (`isFirst ? "FIRST MENTION" : (row.id == closestID ? "CLOSEST MATCH" : nil)`). In his
  screenshot the closest match WAS the first mention, so one badge rendered, correctly.
- **The subtitle difference is correct.** Both emit `best match first · showing N of M` when
  truncated and `· odd matches sink to the bottom` when not. Mac was showing 7 of 13; the
  iPad had 4 and nothing to truncate.
- **The looseness IS real drift.** The Mac draws each row as a card; the iPad draws bare rows
  (9 rounded-rect uses vs 5), so the iPad reads airy and unfinished at the same width.

⚠️ The counts (13 vs 4) are NOT comparable — he was looking at two different notes.

⭐ **AND A REAL SIGNAL LOST, not just chrome (Tuur spotted the colour):** the Mac paints the
importance decimal **amber past the refine wall** —
`isRefine(step:) ? Theme.amber : Theme.accent` (`ConnectionsPanel.swift:425`) — matching the
0.8+ language the circles and the flame tag already speak. The iPad paints every value one
colour (`Color.skAccentText`, line 243); `isRefine` does not appear in that file at all. So on
the iPad a 1.0 connection looks identical to a 0.2 one, and the whole point of showing the
number is gone. The iPad DOES share the number's TEXT via `ConnectionsPanelLogic.importanceText`,
whose own comment says it exists "so the panel, the significance control, and the Mac panel
never drift" — they shared the string and forgot the colour. Fix this with the un-twinning; it
is the strongest argument that these two files should be one.
**✅ FIXED 2026-08-14 (b148), ahead of the un-twinning** — Tuur asked "u fixed it?" and it did not
need the 600-line refactor. Both iPad render paths (Closest list + Date rail) now colour amber
past the wall via a new `ConnectionsPanelLogic.isRefineImportance`, placed BESIDE `importanceText`
so the string and its colour rule live together. Test pins 0.7 plain / 0.8 amber. The rest of the
drift (card chrome vs bare rows) still stands and still wants the shared view.

**Fix shape (proven on SignificanceCircles 2026-08-12):** one `Shared/UI` view carrying the
rules, a per-app style struct for what each platform legitimately owns, and a render-diff
before/after to prove zero pixels move on the side that is already right. Do the Mac's card
chrome as the target, since that is the one he prefers.

---

## 📦 CONTINUE HERE — share a book (Tuur idea 2026-07-30; ✅ SIGNED OFF 2026-08-11, **build it**)

**The idea, verbatim:** "Sharing books from one device to another. To another skrift app or to files app
and then they import to Skrift."

**Mock = `Skrift_Native/SkriftDesktop/mocks/book-sharing.html`** — 5 columns, no options, no callouts.
**Needs Tuur's sign-off before code.** Branch `claude/book-sharing-devices-rygara`.

**✅ SIGNED OFF by Tuur 2026-08-11** ("Love it"), with the rule stated plainly:

**THE SPEC, in one line (Tuur, final):** *"Just 1 option. Share the audio with the epub. If i dont have the
EPUB. Just the audio. No bookmarks. No fluff."* → one file, one button. Sheet = cover + title/author +
`Audio + book text · 797 MB` (or `Audio · 164 MB` with no ePub) + **Share**. Packaging replaces the button
with a bar + Cancel, then the system share sheet.

**THE SIGN-OFF RULE (Tuur 2026-08-11, verbatim):** *"If I have the ePUB also share the EPUB. If I don't,
don't. If I don't have the transcript, don't share the transcript. If I do the transcript, share the
transcript. Easy. Share what I have. No bookmarks. But all the other shit, share it. Also don't share my
location of course, that it's a new book for them."*

Which resolves to one line: **send the BOOK, never your relationship to it.** Present-if-present for every
book-side part (audio, cover, ePub(s), transcript sidecars, alignment sidecars, detected chapters); nothing
optional about it and no picker. Left behind, because it arrives as a new book for them: **playback
position** ("my location"), **bookmarks**, playback rate, and the user's notes/captures about the book.
Notes + captures are read as excluded under the same rule — they are Tuur's memos, not the book.
This does not disturb the two cuts or the retractions below: audio is still unconditional (an audiobook
always has it), so there is still nothing to duration-match and nothing to merge.

**Two cuts got it here (don't re-expand):**
1. **Own devices are out** — "all that is done over cloud sync". Verified: `AudiobookCloudSync` already
   carries audio, cover, position, rate, bookmarks, transcript sidecars, attached ePubs AND alignment
   sidecars between the user's devices. Person-to-person only.
2. **The audio switch is out** — always included. Killed the destination picker, variants A/B, the reading
   layer, and (below) an entire class of engineering.

**❌ RETRACTED, do not resurrect:** (a) the claimed "free win" that bundle transfer gives two devices a shared
book `id` and dissolves the "each device mints its own id" limit on resume-sync — only ever held
device-to-YOUR-device; (b) the duration-match test + the "this won't line up" refusal screen + all merge
logic — **all three fell out when audio became unconditional**: a bundle's transcript now always arrives with
the audio it was measured against, so it can never be attached to a different rip. Nothing to match, nothing
to merge.

**The format — `.skriftbook`, UTI `com.skrift.book` → `public.zip-archive`:**
```
manifest.json      schema · the Audiobook record · file list
audio/…            ordered, original filenames  (always)
cover.jpg
text/…             the attached ePub(s), if any
derived/transcript_f<i>.json · derived/alignment_f<i>.json

never in a bundle: bookmarks, position, playback rate, notes, captures
```
A ZIP. **ZIPFoundation is already dep #2** (pinned 0.9.20, app target) and streams entry-by-entry — no new
dep, no memory ceiling, real byte progress. Audio entries stored `.none` (already compressed), JSON deflated.
The transcript + alignment ride along as invisible plumbing: ~13 MB against 782 MB, and stripping them would
force the receiving phone to re-transcribe the whole book.

**⚠️ THE CUSTOM-TYPE GOTCHA (answer to "any downside to a custom extension?"):**
**Dev and Prod run side by side on the same phone by design.** If both builds *export* the same
`com.skrift.book` UTI, two installed apps claim one type and document routing is undefined — "Open in Skrift"
can hand a **test** bundle to the **prod** app, straight across the data-safety line. Make the type
config-dependent exactly like the bundle ids: `com.skrift.book` (Release) / `com.skrift.book.dev` (Debug),
Dev accepting BOTH. Same shape as the `$(VAR)`-in-entitlements lesson: literal value per config, selected by
build setting. Other downsides, all minor: opaque to anyone without Skrift (**mitigated by conforming to
`public.zip-archive`** — rename to `.zip` and it's readable); no Files thumbnail without a QuickLook thumbnail
extension; some mail/cloud services mangle unknown attachments (AirDrop/Files/Messages fine); we own the
format forever (that's the manifest `schema` int). Declare it **exported** (`UTExportedTypeDeclarations`).
**No new APP extension needed** — `.onOpenURL` + the document type covers AirDrop/Files/Open-in.

**What the engine must get right (all read out of the code, not guessed):**
1. **Re-stamp the transcript on arrival.** `BookTranscriptStore.signature` is `"<size>:<mtime>"` of the LOCAL
   audio; mtime changes when the receiver writes the file, so an un-restamped sidecar reads as stale and the
   book silently looks un-transcribed. `AudiobookCloudSync.restampTranscripts` already solves this for the
   CloudKit path — **hoist it to ONE shared re-stamper**, don't grow a second copy.
2. **Keep the book id** — import keyed on the manifest's `bookID`, already present → "Already in your books",
   nothing happens. That's now its ONLY job: re-importing the same file can't duplicate a book.
3. **Local-only fields stay local.** `epubChapters`/`detectedChapters` derive from local sidecars and are
   already stripped by `Audiobook.sanitizedForSync()`. Import writes the FILES and re-derives.

**Test constraint (project.yml, verbatim): "App target ONLY — extensions and test bundles never touch
archives."** Testable surface = manifest codec + the already-have-it check + the re-stamp. The zip I/O is a
thin shell verified on device. Shape it like `EpubSyncManifestTests`.

**Wiring:** out = a plain `ShareLink` over the packaged temp file; in = `CFBundleDocumentTypes` +
`LSHandlerRank: Owner` → `.onOpenURL` → a book-bundle branch in `AppURLHandler`, plus the book UTI added to
the Books `+` `fileImporter`. Verb sits in the library long-press ABOVE "Sync this book…" + the player ⋯
(same sheet from either — the locked convention); the two read as opposites on purpose (**Share** = give it
away · **Sync** = keep it across your devices).

**Scope:** mobile only (iPhone + iPad, one universal app). The Mac has no book library
(`Audiobook.swift:19`) — a `.skriftbook` there is storage, not an import.

**For the record, not a gate:** every bundle now carries the audio, so sharing one hands over a purchased
audiobook. Tuur's call, made twice; relevant only if App Store framing ever comes up.

**Build order once signed:** (1) `BookBundleManifest` + the pure checks + tests → (2) the zip writer/reader
shell + the shared re-stamper hoist → (3) per-config UTI + document type + `AppURLHandler` branch +
`importTypes` → (4) the share sheet + the import sheet → (5) device round: AirDrop a real 797 MB book to a
second phone, and confirm a Dev-built bundle never opens in prod.

**✅ 1–4 BUILT 2026-08-11** (commits `064114f`, `8af0a03`, `9d8e07e`, `d353567`; phone build 138).
1024 unit tests green. **(5) the device round is entirely owed — nothing has been run end-to-end
and neither sheet has been looked at.**

**Two deliberate departures — don't "fix" them back:**
1. **The Dev file EXTENSION differs from prod's** (`.skriftbookdev` / `.skriftbook`), not just the
   UTI. The design said Dev should accept both types; that needs a shared extension, and extension
   is precisely what document routing falls back to — it would put the two-claimants ambiguity
   straight back, which is the hazard the per-config type existed to kill. Cost, accepted by Tuur:
   a prod bundle can't be opened in Dev. Verified both configs resolve (`Debug` Info.plist =
   `com.skrift.book.dev`/`skriftbookdev`; `-showBuildSettings -configuration Release` =
   `com.skrift.book`/`skriftbook`).
2. **Duration reads "28 h 04", not the mock's "28h 04m"** — `BookTextDisplay.durationText` is the
   app's only duration style and already ships on the Text sheet. A second formatter for one screen
   is a convention that drifts.

**Also landed on the way:** `BookTranscriptStore.restampTranscripts(for:in:)` is now the ONE
re-stamper (hoisted out of `AudiobookCloudSync`, which now calls it) — import needs the identical
rule and two copies would drift.


## ⚖️ 2026-07-28 — ONE rated/unrated rule (the consolidation chat; ROUND 9 items 3+4 = the acceptance tests, both fixed)

The unrated model ("the rating is CONSENT") was enforced by FIVE hand-rolled copies of
"is this note rated?" across two channels, and every new feature re-tripped one. Now ONE
predicate — `Shared/Pipeline/NoteConsent` — answers it for both dialects, and every gate
routes through it. Four commits, each gated (desktop 718/0 · full MLX build · mobile 999/0
· `-snapshot-unrated`/`-snapshot-shell` vision check; Dev deployed).

**The two dialects, resolved once (the durable knowledge):**
- `Memo.significance` — non-optional, 0 = unrated. Simple.
- `PipelineFile.significance` — optional; nil means THREE things, resolved only in
  `NoteConsent+PipelineFile`: a projection (`modelContext == nil`) = unrated · a local
  RECORDING (`isLocalRecording`) = unrated · a local IMPORT/legacy row (0.1-floor
  authored, never heard back) = RATED. Reading nil as 0 anywhere else silently un-rates
  every Mac import (the `MacCloudMetaSync.mirror` scar, now structural).

**What changed behavior (only the leaks):**
- Mac Connections: index membership = `joinsConnectionsIndex` (live + rated; orphan pass
  removes on un-rate — phone parity) and `NoteDisplayView` DERIVES capabilities from the
  note (`.unrated` for an unrated take's real row too; the `capabilities:` parameter is
  gone, callers can't lie). ROUND 9 #4.
- Quiet-row title: the eager reflect + the pane title chooser now ANNOUNCE
  (`.cloudMemosDidChangeFromSync`) so the row repaints without waiting for a sweep. #3.
- Phone summon: `ConnectionsPanelLogic.canSummon` = rated && !locked, one rule for the
  capsule AND the sheet (round-5 "own panel NO" finally enforced phone-side).

**Routed with zero behavior change:** WayOutRules (unpipelined, isUnratedLocalRecording),
ProcessPile ×4, MemoSpine, MemoLifecycle (neverFades + parked migration), LookbackProvider
hot, MemoCloudIngest flag-to-process, JournalIndexService, PublishCoordinator,
MemosListView (dim rows, clock line, Not-rated filter), SidebarView search-fading.
`AppModel.matchesFilter`'s "No PipelineFile is unrated by definition" comment was already
false — the chip logic survives because quiet takes leave the file row channel.

**✅ MAC LIVE RE-RUN CONFIRMED (Tuur, 2026-07-28 eve — "very sexy, very hot"):** recorded a
real take on Dev; rated it → Connections appeared; un-rated it → Connections hid again (the
local-take two-way door behaving live); no title-lag complaint. ROUND 9 #3+#4 closed with
eyes. **Still owed:** the phone half (canSummon) rides the next phone build.

**DELIBERATELY NOT changed (decided, don't "fix"):** the one-way door — un-rating a SYNCED
pipelined note leaves it lit/processing (Tuur 2026-07-26); local takes are two-way by the
2026-07-28 doctrine. Asymmetric on purpose. Also `MacMemoAuthor`'s 0.1 import floor and
`PolishCenter.polishNow`'s floor — those are the DOORS out of unrated, not leaks.


## ⚡ 2026-07-27 — audit round 2: the CloudKit races, one aligner, titles everywhere

Device-confirmed by Tuur the same day, on `integration/ipad-plus-audit` (iPad wave + main + these).

**Fixed**
- **Two memos fighting over one row.** An audiobook quote capture inherits the source memo's
  `audioFilename`; the sweep's filename fallback gave both ONE `PipelineFile`, so they overwrote
  each other every sweep — one note always wrong, re-exported on each flip. Filename dedup may no
  longer claim a row already owned by another memo. `reflected=4` → `0`, verified on the live store.
- **Unrated memos needed an app relaunch.** Nothing told the sidebar: it refreshed on `files.count`,
  and an unrated memo never becomes a `PipelineFile`. Every sweep now posts
  `.cloudMemosDidChangeFromSync`; the fetch also moved off the stale `mainContext`.
- **Late-asset heals** for `wordTimings` (karaoke-dead notes recover) and `diar` (voice enrollment).
- **ONE ALIGNER.** `Karaoke.wordTimes` → `AlignmentCore`. The phone never aligned a polished body at
  all (flat `t/duration` sweep) — now aligned, b133, "perfect alignment on the phone".
- **Titles everywhere.** The chosen title writes `Memo.title` (both directions); the phone LIST now
  falls back to the Mac's generated title instead of the body text.

**Correction worth keeping:** the phone's karaoke breakage was NOT diarization (I asserted that from
Tuur's phrasing without checking — the note is plain prose). It was **copy-edit**, which affects far
more notes. Check the store before repeating a diagnosis back.

**⭐ CONTINUE HERE — the Mac records (option B built); live capture is UNVERIFIED**

Tuur: *"copy the recording ability of the phone and ipad to the mac too… make 4 mockups. pick
the best one and install it."* Mock `mocks/mac-record-button.html` (A/B/C/D + B-recording);
**Tuur picked B**, built same session.

**The port that wasn't.** `LiveRecordingService` is 1508 lines built around `AVAudioSession`,
which **does not exist on macOS** — the route/HFP/interruption half is genuinely unportable, and
faking a shared abstraction over it would have been a lie. So:
- **`Shared/Recording/RecordingCore.swift`** — the parts that would really drift: encoder
  settings (AAC/m4a at the INPUT's own rate), the `memo_<uuid>.m4a` filename, the ×12 level
  scale, the rolling `Meter`, the `m:ss` label. 10 tests.
- **`SkriftDesktop/Engines/MacRecorder.swift`** — the platform half, deliberately small:
  AVAudioEngine tap → AVAudioFile, elapsed + level published. No session, no route war.
- **`AppPaths.recordingsDirectory` gained its macOS half** (appSupport-suffixed, so a Dev take
  can't land in the real library).
- **Stop hands the file to `ingest([url])` — the SAME call the Import button makes.** That was
  the unlock: `IngestService` → `PipelineFile` → the reconcile sweep's `MacMemoAuthor.backfill`
  → synced `Memo`. A Mac recording is not a new kind of thing, so there is no second path to
  keep in step — it transcribes, syncs, rates and processes like any other note.
- **`INFOPLIST_KEY_NSMicrophoneUsageDescription`** added. macOS TCC needs it even though this
  app is NOT sandboxed; without it, requesting access kills the process instead of prompting.
  (`com.apple.security.device.audio-input` is a sandbox key and stays absent — there's no sandbox.)
- **Process greys out while recording** — one mic, one job.

Desktop 615/0, mobile 996/0. Header layout confirmed in the real app via `-snapshot-shell`.

**Round 2 — "the record button does nothing" (Tuur, 2026-07-28). TWO real defects:**

1. **THIS MAC HAS NO MICROPHONE.** `system_profiler SPAudioDataType` — asked of the hardware,
   not of TCC — lists only outputs (Mac mini Speakers, an HDMI monitor, Multi-Output). The
   recorder was *correct* to refuse.
2. **The refusal was invisible.** `start()` failed into `coordinator.lastError`, which NOTHING
   on screen renders (grep: only the headless `RunFile` reads it). A refused mic and a dead
   button looked identical. Failures now render inline under the button.

**Detector gotcha, durable:** `AVCaptureDevice.DiscoverySession` and `inputNode.inputFormat`
both report empty/0 Hz in TWO different situations — no mic, and a mic we haven't been granted
yet. Neither can gate the UI or the feature dies on every Mac that simply hasn't been prompted.
`MacRecorder.hasInputDevice` asks **CoreAudio** (`kAudioHardwarePropertyDefaultInputDevice`),
which privacy doesn't gate, so the hardware question gets an honest answer. Record is now
disabled + dimmed with "No microphone — connect one (or a headset) to record here" when there
is genuinely no input.

Diagnostics kept: **`-miccheck`** (auth status · usage string · devices · input format — never
prompts, so it can't stall) and **`-recordcheck`** (drives the real recorder for 3s).

**Round 3 — popup replaces the dimming. DONE 2026-07-28.** *"dont make it dimmable. just give a
popup when no mic is connected… the dimming and undimming is very slow."* Record is a normal,
always-live button again; a failed start raises an alert instead. The slowness had a real cause:
`hasInputDevice` is a synchronous CoreAudio call and it was being evaluated inside
`recordButton`'s BODY, so it ran on every sidebar re-render. Asking at press-time takes it off
the render path entirely — the popup is both the nicer behaviour and the faster one. The
detector itself is unchanged (it was hard-won). The inline error row went too: an alert can't be
missed and costs no layout. Desktop 615/0.

**🔴 ACTION FOR TUUR — the mic is DENIED, and I did it.** Running `-recordcheck` from the CLI
called `requestAccess` where macOS cannot present a prompt, so TCC recorded a **denial** for
`com.skrift.desktop.dev`. The GUI will now never prompt; it just fails. Fix, either way:

- **System Settings ▸ Privacy & Security ▸ Microphone → enable "Skrift Dev"**, or
- reset it and let the app ask properly:
  `tccutil reset Microphone com.skrift.desktop.dev`

**GUARDED so it can't recur:** `-recordcheck` now REFUSES to run unless the status is already
`authorized`, and says why. `-miccheck` never requested in the first place.

**Round 4 — CAPTURE WORKS (2026-07-28).** Permission granted, prompt fired, transport ran
(0:05, meter moving), two takes landed as notes. The recorder itself is verified. Two defects
Tuur caught on the first real take:

1. **✅ FIXED — a recording arrived pre-rated "passing" (0.1).** `MacMemoAuthor` floors an
   unrated file to 0.1, and the recording went through the reconcile sweep's `backfill` like an
   import. That floor is right for an IMPORT (adding a file asks for it to be processed) and
   wrong for a CAPTURE — under the unrated model (2026-07-26, which postdates the floor) the
   rating IS consent. `author(…, floorSignificance:)` now makes it explicit, and the recording
   path authors its own Memo unrated before the sweep can floor it (`author` is idempotent, so
   backfill then leaves it alone). 3 new tests; desktop 618/0. **NOTE the Mac pane read "Not
   rated" the whole time — it renders the PipelineFile, while the 0.1 was on the synced Memo.
   The two disagreed, which is why this was invisible on the Mac and would have shown up on the
   phone.**

2. **✅ FIXED — a recording produced no TEXT until you pressed Process.** Was: `ZTRANSCRIPT`
   empty, status `pending`, because a recording rode the Import path and Import waits. And once
   fix 1 made recordings correctly UNRATED, `process()` would never pick them up — so a take
   would have stayed wordless forever.

   **THE DOCTRINE, now written into the code:** *transcription is CAPTURE — raw audio becoming
   text, which the phone does the instant you stop. Polish / name-linking / export are
   PROCESSING, and only those are what a rating gates.* So a Mac take transcribes immediately
   and stays unrated, exactly like a phone one. `BatchRunner.run(…, stopAfterTranscribe:)`
   returns after transcribe + diarize (the phone diarizes on capture too); a new
   `ProcessingCoordinator.transcribe(fileIDs:context:)` loads ONLY the ASR model — the
   enhancement model stays cold — and reflects the words onto the synced `Memo`. Called from
   `stopRecording()`. `enhanceStatus` stays `.pending` on purpose, so rating the note later
   picks it up as ordinary work. Desktop 619/0.

**🎙 ROUND 5 — DIAGNOSED. The mic grant is DENIED; Record was refusing correctly all along.**

`-miccheck`, run with the GUI app quit (the reason it printed nothing before — a second
instance races the store):

```
mic authorization: DENIED — System Settings ▸ Privacy & Security ▸ Microphone
input devices: USB PnP Audio Device, Chonky pods      inputNode format: 24000.0 Hz, 1 ch
```

Hardware was never the problem. `start()` refuses at the permission guard before it touches
the engine — no engine, no meter, no file, no row. The denial is the one `070425e` recorded
against `com.skrift.desktop.dev` when `-recordcheck` called `requestAccess` from a CLI launch,
where macOS cannot present a prompt; that commit stopped the diagnostic doing it again but
never healed the existing entry, and **macOS never prompts again once a denial is on file**.

**⚠️ TUUR — the ONE manual step this needs.** Nothing in the app can clear a TCC denial:

```bash
tccutil reset Microphone com.skrift.desktop.dev
```

Then press Record once and Allow. (Or System Settings ▸ Privacy & Security ▸ Microphone.)

**Fixed so this is never a dead end again:** the refusal is a typed `MacRecorder.Refusal`
instead of a bare sentence, and a permission refusal now carries an **Open Settings** button
straight to the Microphone pane. `MacRecorder` joined the fast test target — the mapping
(which refusals are dead ends, which aren't) is pinned by tests without needing a microphone.

**Also owed → DONE:** both 08:4x takes are back to **Not rated** on the Mac AND on their synced
Memos (`-ratefile <ids> none`). Clearing it needed the memo-identity fix below — the first
attempt updated the Mac and silently left the phone's copy at 0.1.

---

**✅ ROUND 6 — the two claims that shipped untested are now VERIFIED on real takes.**

`-recordingest <audio>` drives the exact path Stop takes (`ArrivalPath.run(asRecording: true)`)
on a file that already exists, so a broken mic can never again hide a broken pipeline. Three
consecutive runs on Tuur's two real 08:4x takes:

```
transcribe=done  words=13   transcript: Hello, test, test, test. Does it record? …
enhance=pending  significance=0.0     Memo: significance=0.0
>>> PASS — words on arrival, still unrated (here AND on the synced Memo), nothing processed
```

**It did NOT pass first time. Two real defects, both invisible to the unit tests:**

1. **The reconcile sweep out-raced the capture path and floored the take to 0.1.** The claim
   "author is idempotent, so the sweep leaves it alone" assumed an ordering nothing enforces:
   the sweep fetches local rows on its own clock, sees inserted-but-unsaved rows, and runs
   while ingest is awaiting detached file work. Whoever authors first wins, and the sweep's
   `backfill` takes the default `floorSignificance: true`. Fixed by making it the ROW's fact,
   not the call site's: `PipelineFile.isLocalRecording`, stamped by `IngestService` at
   construction (stamping it after `ingest` returns still lost the race — measured twice).
   `MacMemoAuthor.author` now refuses to floor a recording whoever asks.
2. **Every Mac→cloud write for a Mac take silently no-opped.** `MacCloudWriteBack.memoID(for:)`
   prefers the filename's UUID — right for a phone memo, WRONG for a recording, whose
   `memo_<uuid>.m4a` names the audio file while the Memo is authored under the row `id`. So
   rating, delete-sync, chosen title and the enhancement write-back all looked up a UUID no
   Memo had and returned quietly. New `MacCloudWriteBack.resolve(for:in:)` asks the STORE which
   candidate exists (also rescues takes made before the flag); all four writers use it.
   Proven on live data: re-running the two cleanups that had silently failed both worked.

**Structural change:** the arrival path moved out of `SidebarView` into `Pipeline/Ingest/`
`ArrivalPath` (hooks injected, `Hooks.live` in `App/`). The Record button and the harness now
run ONE path. Desktop **648/0**.

New headless verbs (all: quit the GUI app first) — `-recordingest <audio>`,
`-trashfile <id>[,…]`, `-ratefile <id>[,…] <0.1–1.0|none>`.

**Still owed:** Tuur grants the mic, presses Record, and confirms a live take end to end. The
button's own path (mic → engine → meter → Stop) is the only part no harness can prove.

---

**🎙 ROUND 7 — Tuur's testimony rewrote the diagnosis: the GUI DID prompt and he DID Allow.**
So TCC was never the GUI's wall — ⭐ **a binary run from a shell answers TCC questions with the
SHELL HOST's identity, not the app's** (`-miccheck` read DENIED before *and after* a successful
`tccutil reset` because the denial it was reading belonged to the terminal's responsible
process). The real regression is the backlog's original suspect: **the default input is
"Chonky pods" (Bluetooth), awake for the first two takes, asleep ever since** — engine starts,
transport counts, ZERO buffers arrive, the <1KB stub is deleted at stop, and the failure went
to `coordinator.lastError`, which nothing renders. Two invisible failures stacked into "the
app does nothing."

Shipped (654/0, deployed):
- **b119 ported from the phone:** with Bluetooth around, record on the wired mic. Pure
  `MacRecorder.pickInput` rule (tested) + CoreAudio enumeration; the engine is pointed at the
  picked device directly — the system default is never touched. BT-only Macs still record.
- **A dead take says so, by name:** `stop()` verdicts — no buffers → "“Chonky pods” delivered
  no audio — a Bluetooth mic may be asleep…"; all-zero samples → "recorded only silence".
  Raised in the same alert as start failures. `lastError` is out of the recording path.
- **The record path logs every gate** (`subsystem com.skrift.desktop`, category `record`):
  TCC status, chosen input + device count, format, engine verdict, stop verdict + signal flag.
  Diagnosing this no longer needs the user's eyes.

**OWED NEXT: one Record press from Tuur** (prompt may appear → Allow). The log + store then
tell the whole story.

---

**✅ ROUND 8 — the lane batch: recorder REBUILT + doctrine SHIPPED, hardware-verified. 2026-07-28.**

Tuur: "for the live test we need to be able to use any microphone and have it switched
smartly… call in some agents." Ran as a LANE_PLAYBOOK batch (research agent + 2 Sonnet lanes;
briefs + research memo in `LANES-2026-07-28/`).

- **RESEARCH (memo: `LANES-2026-07-28/RESEARCH_MIC.md`):** `inputNode` and `outputNode` share
  ONE audio unit on macOS — poking `kAudioOutputUnitProperty_CurrentDevice` on it is
  unsupported and yields stale/0Hz formats: both broken takes explained (zero buffers; bytes
  reinterpreted at the wrong rate = `invalidAudioData`). Apple's own forum guidance: use
  `AVCaptureSession` for device-targeted capture. UX: auto-pick + follow system default
  (Discord/Zoom convention); picker = later settings escape hatch.
- **Lane CAPTURE:** `MacRecorder` rebuilt on `AVCaptureSession` + `AVCaptureDeviceInput` +
  `AVCaptureAudioDataOutput` → the EXISTING `AVAudioFile`/`RecordingCore` path (sync `stop()`,
  phone-parity meter, exact-zero `sawSignal` all preserved; public surface frozen). The file
  is born from the FIRST DELIVERED buffer's own format — the stale-format bug is now
  unrepresentable. Fail-fast: no buffer in 1.5s → named-device alert. Mid-take unplug: the
  take survives if it holds signal. One conductor gate-fix: `AVLinearPCMIsNonInterleaved`
  (the one settings constant with no `Key` suffix).
- **Lane DOCTRINE:** unrated takes = quiet dim rows (twin Memo via `WayOutRules.unpipelined`),
  excluded from "Process N"/`canProcess`; `needsProcessing` moved to pure `WayOutRules`
  (test-target split) and refuses unrated local recordings; errors stay LOUD; rating in the
  peek flips the note back to a lit queue row (existing Q2 reflect, verified).
- **Gate:** 676/0 + full build + vision-check (`-snapshot-shell`: both real takes render as
  quiet fading rows; Process counts only rated work). Deployed.
- **⭐ HARDWARE-VERIFIED WITHOUT EYES:** `open -a "Skrift Dev" --stdout <f> --args -recordcheck`
  — LaunchServices launch = the APP's TCC identity (a plain shell exec answers for the SHELL
  HOST's). Real 3s capture off the USB mic WHILE Scribble shared it: live meter 0.24–0.52,
  86KB / 3.0s file. The recorder works on real, shared hardware.
- Housekeeping: legacy 08:4x takes stamped `isLocalRecording` (now quiet rows); the 0:00
  `invalidAudioData` husk → Recently Deleted.

**OWED: the button's own live run** — Tuur presses Record, talks, stops: words should appear
without Process, note lands as a quiet unrated row. Then W7 → done.

---

**🎙 LIVE-TRANSCRIPTION BUILD — W-A SHIPPED 2026-07-28 (4793e2d); lanes LIVE-ENGINE +
LIVE-UI RUNNING.** The phone's caption machinery (snapshot/rotation/pacing — the freeze-spiral
scars) extracted VERBATIM to `Shared/Recording/LiveCaptionEngine` (model + logger injected);
phone service = thin delegators, exact API kept; `finishParts()` added for m2's tail-only
finalize; frozen `LiveRecordingSession` skeleton = the lane contract.

**⚠️ GATE RECORD + OWED:** desktop 676/0 + build green. Phone unit suite **996/1** — the 1 is
`AudioPlayerModelTests.testPlayClaimsTheSessionAndStopResetsState`, a 1050s hang in play()'s
session activation, **PROVEN ENVIRONMENTAL** (identical 1050s failure on UNMODIFIED code via
stash-control; host CoreAudio wedged on the dozing BT pods — `system_profiler SPAudioDataType`
hangs then returns an EMPTY device list; same illness as the morning's zero-buffer takes).
⭐ DURABLE: the sim's audio-session activation proxies to HOST CoreAudio — a wedged host BT
device fails PHONE tests. **OWED before prod promotion: a clean full phone-suite re-run once
the host audio stack recovers** (recovery watch armed; pods leaving BT range or a reboot both
heal it).

---

**🎤 ROUND 11 (Tuur's evening take, 2026-07-28 — reading a chat message aloud; screenshot
evidence). Verdicts + fixes:**

1. ✅ FIXED SAME SESSION — **too many paragraph gaps** (*"there's a lot of gaps in there…
   increase the time before it is committed"*): every sentence-end breath (~0.7–1.5 s) broke a
   paragraph, on BOTH surfaces — the live join decided at settle time (a pause-settle after a
   sentence = break, no length measured) and the file pass re-paragraphed at the phone's 0.65 s.
   Now: `Paragrapher.longFormGap = 2.0s`, ONE constant for the live join AND the Mac file pass
   (draft and resting note agree); the live join RESOLVES when speech resumes (want-at-boundary,
   decide-at-resumption — `wantsParagraph`/`resolvedJoin`; the settle only proves a pause
   STARTED). Phone byte-identical (timer mode never produces `.pause`; 0.65 default untouched —
   his phone feel is confirmed good). Predicted feel: paragraphs only when you actually stop to
   think (~1.5–2 s real silence); sentence breaths stay in the paragraph. Needs his re-feel.
2. 📝 LOGGED (feel, cold start) — **waveform moves but no words for a while** on the first take
   (*"maybe took a while for the engine to warm up"*): the ASR model loads on first use. Candidate:
   pre-warm on Record press (or app launch, memory cost). Not fixed this session.
3. ⏸ AMBIVALENT, LEFT AS-IS — the ~20 s ceiling commit (*"might be a bit distracting… seems like
   it just cut off your sentence. But maybe that's something you get used to"*): the ceiling joins
   with a space (no visual gap), so the "cut" he sees is the whitening itself. Revisit only if it
   keeps bothering him after the paragraph fix changes the rhythm.
4. Paragraph RULE itself (pause mid-sentence vs sentence-end): confirmed good as designed.

---

**🎤 ROUND 10 (Tuur's third live take, ~14:25) — the pause-settle SHIPS but doesn't FEEL
right; HANDED OFF to a dedicated feel chat (kickoff below).**

**FEEL CHAT STATUS (2026-07-28 ~15:00, deployed to Dev — 014c4b5 + df37693):**
- **Instrumented (①/② evidence):** every rotate logs its trigger (`pause`/`ceiling`/`cost`)
  + measured silence at fire + the last 16 buffer levels — one take now tells a real breath
  from soft speech under `voiceFloor`, and says what the settle latency actually is.
- **Ceiling 7s → 20s** (pre-blessed): suspect (b) — the 7 s cap firing mid-sentence — is
  gone; the cap now only catches the never-breathing talker.
- **③ BUILT — paragraphs live + at rest, the phone's rule single-sourced:** `Paragrapher`
  moved to `Shared/Pipeline` (RunFile's drifted DEBUG mirror deleted); the Mac's file pass
  paragraphs exactly like `MemoSaver` (+ new guard: already-structured text — speaker turns
  — passes through untouched, DiarizationTests forced it); the LIVE draft breaks a paragraph
  when a pause-rotate follows a finished sentence (`chunkJoin` — a pause-rotate implies
  ≥0.8 s real silence, past the phone's 0.65 s gap by construction).
- Gates: desktop 708/0 + full MLX build; phone 997 w/ 1 = the documented environmental
  AudioPlayerModelTests host-CoreAudio case (fails fast -66680 now, same illness).
- **TAKE 4 (~14:56, the first instrumented one) READ + FIXED (a1c7c90, redeployed ~15:15):**
  - **① ROOT CAUSE FOUND — the floor, inverted:** in 51 s with SEVEN real ≥0.8 s pauses,
    zero pause-rotates fired (both rotates `[ceiling]`, silence 0.00s). His USB mic never
    meters below ~0.24 (measured off the take's m4a; real silence 0.25–0.30, speech p50
    0.40) — voiceFloor 0.15 can't see a pause on this hardware. **Adaptive floor built:**
    `max(0.15, rollingMin(5–10s)+0.08)` ≈ 0.32 on his mic — a 0.30 sweep of the take finds
    exactly his 7 pauses, nothing mid-speech. Floor logged per rotate.
  - **SEED-CLOBBER FOUND (store-proven, pre-existing):** the resting note held the rough
    live SEED, not the file pass's paragraphed final (stored text ≠ stored timings' words;
    the real Paragrapher on the row's own data = 4 clean paragraphs). Race: sweep-reflect
    shipped the in-flight seed into the empty Memo mid-decode → post-pass reflect skipped
    non-empty → MemoCloudUpdate Path 3 copied the seed back over the final. **Fix:**
    `reflectTranscripts` publishes only `.done` rows. "Words final on stop" holds now.
  - Gates: desktop 712/0 + build; phone 997/1-known-environmental.
- **TAKE 5 (~15:41) KILLED RMS FOR GOOD (7de11d9, redeployed ~15:55):** one rotate in 40 s,
  `[ceiling]`, adaptive floor 0.22 with levels rippling 0.16–0.33 straight through it. With
  take 4 that's failure in BOTH directions on one mic — **its silence and its quiet speech
  share a band; no energy threshold can separate them.** ⭐ DURABLE: don't tune RMS
  thresholds for pause detection on arbitrary mics — use the decode itself.
  **Built (announced first, per Tuur's process ask):** TEXT-STABILITY settle — identical
  non-empty tail decode on 2 consecutive polls (LocalAgreement-2) = the pause, any mic any
  gain; the stable decode is adopted as the committed chunk VERBATIM (zero extra ASR per
  settle; reentrancy-safe — mid-decode buffers survive adoption). Mac poll floor 0.6→0.4 s
  (param, phone untouched) → expected felt settle ~0.7–1.2 s after the last word. Adaptive-
  floor machinery deleted; levels stay in the log as evidence only.
- ✅ **TAKE 6 (~16:05) — TUUR-CONFIRMED: "way better."** Text-stability settle IS the feel
  fix; session closed here on his call, pushed. ⭐ THE SETTLE MECHANISM (durable): pause =
  identical non-empty tail decode on 2 consecutive polls; the stable decode is adopted
  verbatim (zero extra ASR per settle); the RMS/VAD lane is DEAD on this hardware — never
  re-tune it, extend stability instead.
- **STILL OWED in this area (next session):** the mid-take EDIT live check (fix a settled
  word while talking → survives to the resting note + '✎ edited while recording' chip —
  never yet human-verified); a live-eyeball that the resting note's PARAGRAPHS survive
  (seed-clobber fix is store-proven, not yet eyeballed); karaoke-after-edit parked decision;
  i17 in-Skrift cursor-follow = design item, mock first. Dev-only so far — prod promotion
  also still owes the clean full phone-suite re-run (host CoreAudio flake).
- ✅ **Sidebar: selected note isn't visibly highlighted** (Tuur, same session — "no way to
  see what node I have selected in the left sidebar") → FIXED 2026-07-28: the quiet
  (unrated) rows — which is every fresh Mac take — had NO selected treatment at all; both
  row kinds now share one accent-wash + accent-edge chrome (`sidebarRowSelection`,
  SidebarView.swift), stronger than the old 0.13 wash. Vision-gated dark+light via the new
  `-snapshot-sidebar-selection` render (fixture memos — never opens the real cloud store).

Findings verbatim:
1. **Mid-sentence whitening** — *"sometimes it just cuts up the sentence, mid sentence…
   halfway through a sentence and then I think because the seven seconds have passed it turns
   it white. That's a bad bad system."* Suspects RANKED (instrument before tuning): (a)
   `voiceFloor 0.15` too high for his USB mic's quieter stretches — the harness measured
   0.24–0.52 while SPEAKING, so soft speech can dip under the floor and fake a "pause" mid-
   sentence → pause-rotate DURING speech; (b) his own hypothesis, the 7 s ceiling firing
   mid-sentence — now that pauses are primary the ceiling can rise to ~20 s; (c) `pauseHangover
   0.8` too tight for his cadence. The rotation log line must gain WHICH trigger fired +
   the silenceFor value — then one real take answers this.
2. **Settle latency feels long** — *"it seems like I have to take quite a long pause. Or do
   I?"* True latency = hangover (0.8 s) + up-to-a-poll-cycle before `rotateIfNeeded` even
   runs (0.6–2 s). Consider evaluating the pause gate on `feed()` instead of poll-time, or a
   tighter poll floor while `pauseTriggered` — measure first.
3. **No paragraphs** — *"on the phone I have paragraph generation when I talk. Here I
   don't."* Find the phone's paragraphing rule, single-source it in Shared/, apply to the
   draft (long-pause rotation boundaries are natural paragraph candidates).
4. i17 refinement: *"if I took notes on my computer in my app, it is nice that I would be
   able to click somewhere"* — in-SKRIFT-only cursor-follow is feasible (movable append
   anchor) and attractive to him; system-wide stays the far half of i17.

---

**📋 KICKOFF — the live-transcription FEEL chat (paste to start it):**

> Resume Skrift on `main`. Live transcription on the Mac (roadmap W8) WORKS — words stream
> into the note, pause-triggered settling, edits are structurally safe — but it doesn't FEEL
> right yet, and this chat owns the feel. READ FIRST: backlog.md "🎤 ROUND 10" (the ranked
> suspects), `LANES-2026-07-28/RESEARCH_DICTATION.md`, `Shared/Recording/LiveCaptionEngine
> .swift`, `SkriftDesktop/Features/Shell/LiveRecordingSession.swift` + `Pipeline/Recording/
> LiveRecordingDraft.swift`.
>
> HEAVY WORK FIRST — INSTRUMENT, THEN TUNE (feel bugs are hardware-flavored: orchestrator
> work, no lanes): add to the engine's rotate log WHICH trigger fired (pause/ceiling/cost) +
> silenceFor + window length; deploy Dev (build → pkill → ditto → open); have Tuur talk one
> real take; read `log show … category live/liverecord`. THEN fix in evidence order:
> ① mid-sentence whitening (suspects ranked in ROUND 10 — likely voiceFloor vs his mic's
> soft-speech levels; ceiling can rise to ~20 s regardless), ② settle latency (pause gate is
> only checked at poll time — consider feed-time evaluation), ③ paragraph parity with the
> phone (find its rule, single-source in Shared/, long-pause boundaries = paragraph breaks).
> Engine changes: phone stays byte-identical unless deliberately shared with a default-off
> parameter (the pauseTriggered pattern).
>
> ALSO OWED IN THIS AREA: the mid-take EDIT live check (fix a settled word while talking →
> survives to the resting note + '✎ edited while recording' chip); karaoke-after-edit parked
> decision (needs a timings-only file pass; aligner exists — `Karaoke.wordTimes`); i17's
> near half (in-Skrift cursor-follow = movable append anchor) is a DESIGN item — mock first,
> only if Tuur pulls it in.
>
> Rules: verify on real takes + the live logs, never claim from source; commit per chunk
> with explicit paths; backlog + roadmap in the same change; Dev deploy only (never prod);
> a second Dev instance races the store — quit before harness runs.

---

**🎤 SETTLE POLICY — RESEARCHED + REBUILT same session (memo:
`LANES-2026-07-28/RESEARCH_DICTATION.md`).** Tuur: "how do you know seven seconds is the
right amount?" — honest answer: it wasn't. The research verdict: **a phrase PAUSE is the
primary settle signal everywhere that dictation feels good** (Apple's new SpeechAnalyzer
marks text volatile→final "as the model gets more context" + ships a VAD alongside; Deepgram/
Google/whisper.cpp all commit on endpointing with the window as fallback) — our timer-primary
shape had it inverted, and the Shhhcribble ancestor HAD a VAD speech-end trigger that the
phone rewrite dropped. **Built:** `LiveCaptionEngine` pause-triggered rotation (RMS voice
floor 0.15 on the shared ×12 scale, 0.8 s hangover, 2 s min window, cleared on rotate so
silence can't chain empty commits) — Mac ON with the 7 s interval demoted to a ceiling; phone
timer-only, byte-identical. 700/0 + build + phone 996/1-known. Deployed.
- **Apple's edit-while-dictating** (Tuur's observation): confirmed NOT a special recognition
  mode — the keyboard just stays live and recognition appends at the cursor. Our settled/wet
  ownership model independently matches; no change needed.
- **Karaoke after a mid-take edit** (Tuur: "I don't know how that's gonna work"): researched
  answer — post-hoc realign, never live (Descript/Otter both do deliberate realign passes).
  We already own the aligner (`Karaoke.wordTimes`, anchor-based, fails safe to no-highlight).
  OPEN DECISION: edited takes currently store NO word timings (we skip the re-ASR by design)
  — karaoke for them needs a timings-only file pass (background, text untouched) + the
  aligner. Parked; decide when karaoke-on-unrated actually matters.

---

**🎤 ROUND 9 — THE FIRST LIVE TAKE (Tuur, 2026-07-28 ~14:15). The loop WORKS — words
streamed into the pane, the note landed unrated with a derived title — and the take itself is
a spoken review. Findings, triaged:**

1. ✅ FIXED SAME SESSION — **double waveform** (*"waveform on the top of the screen and on the
   side… looks a bit stupid… just the one on the side is fine"*): the pane transport lost its
   meter; the sidebar keeps the only one. (d3a3426)
2. ✅ FIXED SAME SESSION — **settling too slow** (*"it seems to write a whole paragraph until
   it turns white… works way less clear than the Apple one"*): the engine's rotation cadence
   is the felt settle speed; Mac now rotates at 7 s (phone keeps its thermally-tuned 25 s).
   Needs his re-feel. (d3a3426)
3. ✅ FIXED 2026-07-28 (consolidation chat) — **sidebar row title lags the pane**: the data
   half was already eager (transcribe-at-capture reflects immediately, `.done`-gated); the
   remaining lag was DISPLAY — nothing announced the reflect to the sidebar's fetched memo
   array. The reflect and the pane's title chooser now post `.cloudMemosDidChangeFromSync`
   like the sweep does. Eyeball owed with item 4's.
4. ✅ FIXED 2026-07-28 (consolidation chat) — **Connections shown for an unrated note**: both
   halves — the index sweep now consent-gates membership (`NoteConsent.joinsConnectionsIndex`,
   orphan pass removes on un-rate) and the pane DERIVES `NoteCapabilities` from the note
   itself (the caller-chosen parameter is gone). Phone got the sibling fix (`canSummon`).
   See "⚖️ 2026-07-28 — ONE rated/unrated rule" at the top. Tuur's eyeball owed.
5. STILL OWED: the **mid-take edit** live check (he asked how, didn't visibly do one) — edit a
   settled word while talking, confirm it survives + the '✎' chip appears.

**⭐ TUUR'S DIRECTION (verbatim): "we're gonna start a separate chat that is just gonna clear
out how the fuck rated and unrated no[t]es work… I'm guessing that the code is just really
fucking convoluted, it needs to be cleaned up." → kickoff below.**

---

**📋 KICKOFF — the rated/unrated consolidation chat (paste this to start it):**

> Resume Skrift on `main`. READ FIRST: backlog.md "🎤 ROUND 9" + the memory
> `project_ipad_wave1` (the unrated model: "the rating is CONSENT — until judged, Skrift
> spends nothing on a note and shows it nowhere but back to you; differs only: fades · grey ·
> no process · no export · no connections either direction; play/photos/karaoke/copy/search
> all NORMAL").
>
> THE PROBLEM: that model is implemented as scattered per-feature checks across TWO parallel
> channels — synced-Memo notes vs PipelineFile notes — and every new feature re-trips it.
> 2026-07-28 alone: "Process N" counted unrated Mac takes (fixed via `WayOutRules
> .needsProcessing`), Connections indexes them (open), the sidebar row title lags the pane
> because the ROW renders the twin Memo while the PANE renders the PipelineFile (open).
> Earlier: unrated takes rendered as lit queue rows; a pre-rated 0.1 floor raced in.
>
> THE JOB, in order: (1) INVENTORY — find every place the code asks "is this note
> rated/unrated" or should (render dim/lit, process, export, connections, search, purge,
> title source…); map which channel each lives in; list every disagreement. (2) DESIGN — ONE
> shared predicate/state type (Shared/, both apps) that answers "what may Skrift spend on
> this note, and how does it render" for BOTH channels, so a rule exists once. Mock/spec
> the surface if UI changes. (3) MIGRATE feature by feature onto it, tests per rule, no
> behavior changes beyond fixing the known leaks (backlog ROUND 9 items 3+4 are the
> acceptance tests). Lanes per LANE_PLAYBOOK.md if the migration fans out.
>
> Known scar tissue to respect: `WayOutRules.unpipelined`/`isQuietLocalTake`/
> `needsProcessing` (the file-channel gates that exist so far), `SignificanceScale.litCount`
> (THE unrated predicate — nil and 0 both unrated), `MemoSpine` (lifecycle copy),
> `PipelineFile.isLocalRecording` + `transcriptUserEdited`, the Q2 rating write-back loop
> (`MemoCloudUpdate.swift:112`, `MacCloudMetaSync.setRating`, `MacCloudWriteBack.resolve`).

---

**🎙 LIVE TRANSCRIPTION — BUILT 2026-07-28 (lanes LIVE-ENGINE + LIVE-UI merged, 693/0 +
build + vision-gate; deployed to Dev). Roadmap W8 = now.** The pane becomes the draft on
Record (m1/m2), settled text editable mid-take (engine appends, never rewrites — the type
system enforces it: polls reach the draft only via `absorb`, people only via `settledText`'s
setter), stop just stops (m4), lands as an ordinary quiet unrated note with the one
"✎ edited while recording" chip (m5; `PipelineFile.transcriptUserEdited` mirror). Finalize
fork: unedited → today's full pass (live text seeds first); edited → `finishParts().finalTail`
closes only the engine's wet region, Memo lands `transcriptUserEdited=true` (trusted; author()
infers it from a transcript already present on a fresh local recording — the seed-ordering
contract in `LiveRecordingSession.stop()` + `MacMemoAuthor.author()`).

Conductor gate catches worth remembering: covariant `Self` in a stored-property initializer;
a re-`guard let self` after the first unwrap (the phone's per-iteration local borrow is the
idiom); ⭐ vision-gate caught 3 real defects source review missed — fat meter bars (no
intrinsic width + a wide pane), TextEditor clipping its second paragraph in the hosted render
(fixed with the invisible-twin sizing trick), the wet tail orphaned under a 160pt editor floor.

**GATE SETTLED 2026-07-28 ~14:00 (host audio healed via Tuur's `sudo killall coreaudiod` +
pods docked; USB desk mic is now the system default input):** clean phone re-run = **996/1 in
6s** (the 1050s hang is gone). The 1 = `AudioPlayerModelTests.testPlayClaimsTheSessionAndStop
ResetsState`, now a FAST assertion failure — **DOUBLY proven environmental**: a throwaway
WORKTREE control at the pre-extraction commit (c6f95f2) fails identically (0.167s), as did the
hang-mode stash control earlier. (First stash-control attempt after committing was INVALID —
nothing to stash, and the pop dug up a prehistoric photo-capture stash + archive conflicts,
cleaned; ⭐ lesson: once changes are COMMITTED, control-test via a worktree at the parent
commit, never stash.) The test is host-audio-dependent by design (sim `AVAudioPlayer.play()`
against the host output — HDMI-only here). **PARKED for Tuur's call:** give it an
`XCTSkipIf(no usable host audio output)` guard so a headless/HDMI Mac doesn't read as red.

**OWED still:** ① the LIVE eyeball — record, watch words stream, edit a word, stop, see it
survive; ③ `-recordingest` regression re-check at next convenience.

---

**💡 IDEA (Tuur, 2026-07-28) — names should auto-boost Parakeet.** *"perhaps names added
should be added automatically to custom words in parakeet?"* The two systems already exist and
both already sync (names.json/NamesRecord; vocab blob/VocabularyRecord) — they just never
talk. Right shape: DERIVE, don't duplicate — at booster pre-warm, boost list = user vocab ∪
roster-derived terms (each Person contributes name words + their aliases via the existing
`canonical: alias, alias` form, `VocabularyTermParsing`). Nothing writes into the user's vocab
list, so person-deletion self-heals and nothing syncs twice. Cautions from the booster saga
([[project_vocab_booster]]): SHORT words are FP-prone — filter roster terms (e.g. ≥4 chars,
skip `short` forms that collide with common words); both apps in the same change (Shared).
Not scheduled — parked behind the live-transcription build.

---

**💡 IDEA (Tuur, 2026-07-28) — rebuild Mac recording around INLINE LIVE TRANSCRIPTION.**
**→ DESIGN ROUND OPEN (same day): mock = `Skrift_Native/SkriftDesktop/mocks/mac-live-transcription.html`**
(m1 note-pane-as-surface · m2 + dictation-style mid-take editing, Tuur's Apple-recorder idea —
the phone's committed/volatile rotation boundary becomes the OWNERSHIP line, first edit flips
authority so no wholesale final-pass overwrite · m3 floating record card · m4 stop-moment
settling · m5 at rest). **Tuur picked m2 + ordered the build ("m2 for sure. mock first the
stop moment too, then build it").** Phone facts that
ground it: the caption is snapshot+rotation (NOT a streaming decoder), committed chunks never
change, the caption only SEEDS the note — MemoSaver's stop-pass is the truth. The pacing fn
self-tunes by measured cost, so the M4 runs near the 0.6s floor with zero Mac tuning.

**🔨 BUILD BOARD (waves; W-A first, it gates the rest):**
- **W-A — Shared engine extraction (CONDUCTOR, not a lane: the phone's freeze-hardened hot
  path).** Extract the stream accumulator + 25s rotation + committed-chunks + `captionPollDelay`
  pacing from mobile `Services/Transcription/TranscriptionService.swift` into
  `Shared/Recording/LiveCaptionEngine.swift` (ASR injected as a closure/protocol; DevLog +
  thermal stay injectable). The phone service DELEGATES — behavior byte-identical, twin tests.
  Gate: BOTH suites (desktop UnitTests + iPhone 17 sim).
- **W-B — desktop engine + draft model (lane).** Desktop `TranscriptionService` gains a
  streaming entry on the same `asr`; `MacRecorder`'s `SampleSink` feeds the shared engine
  (second consumer beside the file writer); a `RecordingDraft` model = `settled: String`
  (user-editable) + `wet: String` (engine-owned) — the seam is STRUCTURAL (engine appends to
  settled's end at rotation; user edits inside settled; wet is display-only). Finalize:
  unedited → today's full pass replaces all (seeded instantly); edited → final pass re-hears
  ONLY the live-tail audio window (rotation boundaries are time boundaries), settled text
  untouched, `transcriptUserEdited=true` (= trusted). Karaoke for edited notes = deferred to
  the existing aligner.
- **W-C — the m2 UI (lane; mock = the spec).** `RecordingDraftView` in the pane (docked slim
  transport, editable settled text, wet-ink tail, ownership pill after first edit), sidebar
  Record button → live timer state, synthetic "Recording…" row, m4 settling state (purple
  'finishing words…', wet-tail band), m5 = the ordinary quiet note + '✎ edited while
  recording' chip. The DRAFT is not a PipelineFile until stop — ArrivalPath stays untouched;
  stop hands it file + live text + edit flag.
- Gate everything: suites + build + vision + a live take. Then W7's successor node in
  roadmap.
*"i also wanna see if we should do the recording differently with inline live transcription
generation."* Today the Mac records → stops → transcribes, so you stare at a meter and get
text afterwards. The phone already streams a live caption while you talk
(`LiveRecordingService` feeds partial ASR to the record screen). Worth a design pass before
polishing what's there: the words would appear in the note AS you speak, which changes what the
sidebar transport should even be — quite possibly the note pane becomes the recording surface
and the meter stops being the main feedback. **Mock first** (locked process for new UI), and
read the phone's live-caption path before designing, per the standing "copy what the phone
does" rule. Weigh against: a partial-ASR stream on the Mac competes with nothing (no other
app), so it's cheaper here than on the phone.

---

**(closed) book quotes render the same on every app — 2026-07-27**

Tuur, seeing a raw `> ` wall on the Mac next to the phone's styled quote: *"better right? perhaps
even improve upon that and share that across all apps."*

**Root cause was DATA, not taste.** Both apps gated quote styling on the C2 book metadata
(`isBookCapture` / `bookCapture != nil`). That blob is SYNCED, and for the June-2026 Gide
capture it never reached the Mac — `ZMETADATADATA` empty, only an `audio` asset — so the phone
(holding it locally) drew a proper quote while the Mac showed markup. **A quote now rides on the
TEXT**; only the attribution caption still needs the metadata, and it simply doesn't appear
without it. No invented attributions.

- **`Shared/Model/CaptureQuote.swift`** — the split rule, the line ranges, the marker length and
  the attribution formatter, lifted out of the phone. The Mac's `BookCapture.quoteLineRanges` +
  `.attribution` and the phone's `quoteAttributionLabel` are now thin wrappers.
- **Mac now hides the `> ` markers** (hairline font + clear colour — chars stay in the storage, so
  the model, the export and every word index are untouched), **dims the quote to 0.78** and draws
  the phone's exact 3pt accent capsule at 65%. Editor and read-only path both.
- **Behaviour change, deliberate:** an indented `> ` now counts as a quote line. Markdown allows
  it and the phone always did; the Mac's column-0 rule was the twin that disagreed.
  `QuoteProtection.splitLeadingQuote` (enhancement byte-protection) still demands column 0 —
  untouched on purpose.
- Desktop 606/0, mobile 996/0. Rendered against the real note; **Tuur's eyeball owed.**

---

**(closed) the D column — E1 gutter BUILT + Tuur-confirmed on the Mac, 2026-07-27**
*"way better looking and it all works i think"* — on the real 16-Jul conversation in Skrift
Dev. Nothing owed on this node. Next focus is the roadmap's `now` (IPadWave1).

DESIGN IS SIGNED. Tuur picked **D** over dimming the marks, then **E1** (right gutter + a
colour per speaker) with **(b)** for playback (a faint accent wash behind the live turn).
Mocks, at full fidelity inside the real note pane:
`mocks/conversation-turns-D-hifi.html` — E1 · **E1 · playing (a/b)** · E2 · E3 · E4.
`mocks/conversation-turn-headers.html` (A–D) and `…-headers-D.html` (D1–D6) are the
exploration that led there.

**Chunk 1 SHIPPED** — `Palette.speakerHues` + `speakerHue(slot:)`, 6 hues, deliberately
clear of green/amber/red/accent/nameLinked so a speaker never reads as a verdict and never
collides with the playing wash.

**Chunk 2 SHIPPED (2026-07-27).** Desktop 605/0, mobile 995/0, both apps build.

- **`Shared/Pipeline/SpeakerTurnStyle.swift` — the slot rule, shared.** A speaker's slot is
  the first-appearance order of their resolved IDENTITY, never of their header text: the
  naming rule writes a first header as `**[[Tiuri Hartog]]:**` and every later one as
  `**Tiuri:**`, so a name-keyed map hands ONE voice TWO colours. That was a live bug on the
  phone (`SpeakerTurnsView` had its own private 4-colour table). `Sanitiser`'s conversation
  pass now resolves through the same `HeaderResolver`, so the linker and the renderers can
  never disagree about who is speaking.
- **Mac (`BodyTextView`) — the gutter.** Each `**Name:**` becomes ONE `SpeakerGutterAttachment`
  glyph, exactly gutter+gap wide, drawing the name right-aligned in that speaker's hue;
  `headIndent` keeps every wrapped line clear, and the separator space is kerned out to the
  spine's padding so the first line's words start exactly where the wrapped ones do. The
  spine and the E1·b wash are DRAWN (`drawSpeakerSpines` / `drawBackground`) — a bar spanning
  a four-line turn is geometry, not an attribute. The `**` marks are gone from the reading
  view but **verbatim in the model** (`modelString` reconstructs the literal), so export and
  hand edits round-trip.
- **Phone** — `SpeakerTurnsView` keeps its cards but takes its colours from the shared rule.
  (The handoff pointed at `NoteBodyView`; conversations don't route there — `MemoDetailView`
  sends them to `SpeakerTurnsView`.)
- **Not a conversation → nothing changed.** The gutter only appears for the pipeline's own
  definition (≥2 line-anchored headers, ≥2 distinct speakers), so a lone bold `**Note:**`
  lead-in keeps today's inline styling.

**Verified headlessly, on the two REAL notes from the Dev store** (not fixtures):
`-snapshot-turns` / `-snapshot-turns-body <png> -turnsBody <txt>` render it;
**`-turncheck`** proves the two things a screenshot can't — the model round-trips byte-exact,
and every displayed word still maps to the model word with the same text, so **click-to-seek
lands where you clicked**. That check caught a real defect: a gutter glyph stands in for a
literal that can be several model words, which skewed `seekWord` by one word per multi-word
speaker name above it — `modelWordIndex` now translates (and fixes the same older skew from
memo-link chips and task boxes). The real-note render caught a second: a turn split across
paragraphs by an inline photo leaked out of the column.

**CONFIRMED by Tuur 2026-07-27** — Mac Dev, the real 16-Jul conversation, eyes on:
*"way better looking and it all works i think."* The phone side (b134, on the iPhone 13) was
verified by me on the sim — Tiuri Hartog teal / Speaker 2 rose, the same two slots the Mac
draws — but Tuur hasn't looked at it on the device; nothing suggests it needs a round.

**Left alone deliberately:** turn spacing is looser than the mock's 0.9rem, because the model
has a real blank line between turns and tightening it would mean hiding blank lines from the
storage. Raised with Tuur at the eyeball round; he didn't take issue. Revisit only if a long
conversation ever reads too airy.

**Both sub-decisions CLOSED by Tuur, 2026-07-27** — and both ratify what shipped, so no code
moved:
- **A long gutter name TRUNCATES** ("Bartholomew Fi…"). Wrapping was rejected: it makes the
  gutter label taller than the first line of speech, so turns stop aligning and the column
  goes ragged. Shrinking to fit was rejected too — a smaller label reads as a less important
  speaker, the exact thing the hue tokens exist to prevent. "Tiuri Hartog" fits at 7.4rem.
- **The phone KEEPS its turn cards** — it took the shared hues, not the gutter. A 118pt gutter
  on a ~390pt measure would eat a third of the width and leave ~4 words a line; the cards
  already carry the speaker and the spine, and only the colours were wrong. A phone gutter
  would need its own design pass (names above, not beside) and isn't covered by the signed
  mock — not planned.

---

**(closed) conversation turn headers read badly — design call, 2026-07-27**

Rating the 16-Jul conversation CONFIRMED the naming logic on real data: first mention of each
speaker is a full `**[[Tiuri Hartog]]:**` / `**[[Bulldops]]:**`, every later header the plain short
name. That part is correct and closed.

The RENDERING is the problem — *"this looks pretty shit to read"*. Every turn header shows its
literal `**` marks, so a 20-turn conversation is fringed with asterisks down the whole note. Dim
marks are the locked rule for running prose (roadmap i10), but a speaker header is structure, not
emphasis — it arguably shouldn't wear its syntax at all. Decide the rule for turn headers
specifically, then apply it on both apps (the body renderer is shared).

Screenshot in the 2026-07-27 session. No code written yet — design call first.

**Still open**
- **The caret/insertion point lands ~6 lines below the click.** Unexplained; it self-resolved once.
  NOT from the audit work — it ships with the iPad branch's `NoteDisplayView` rework (GeometryReader
  + nested frames + docked player). If it returns: which note, and what had just been done.
- ~~**A literal `"[]"` tag**~~ — GUARDED 2026-07-27. Source never identified; `Memo.parseTagInput`
  now requires at least one letter or digit, so punctuation-only input can't archive as a tag. The
  two existing rows still carry it (a cleanup pass would need a migration — not worth one).
- ~~**Untrack the generated `Info.plist`s**~~ — DONE 2026-07-27, once the two branches still editing
  them were retired (`archive/retired-branches/`). Verified: deleted all three, `xcodegen generate`
  restored them at b133, suite green.
- **Diarization heal — NOT EXERCISABLE on the current store** (checked 2026-07-27). The only two
  conversation memos (`0C621DB6`, `F9DF6DE0`) are UNRATED, so they never ingest and the heal — which
  only runs on already-ingested rows — can't fire. Both diar assets already exist in the cloud, so a
  future ingest would read them directly and never need the heal either. To exercise: rate one of
  those two on the phone; that tests the normal diarized-ingest path (turns + enroll), which is what
  actually matters. The heal stays a unit-tested safety net for the late-arrival race.


## 🧹 CONTINUE HERE — waste audit + the CloudKit asset-race fix (2026-07-27, MERGED to main)

Read-only audit of both apps (444 Swift files, 79k lines) → 5 commits, merged clean, all
device-verified by Tuur in an office round. Report artifact: "Skrift — audit outcome & test list".

**Shipped (main `7cee65b`):**
- **`Pow` + `DSWaveformImage` dropped** — declared in `project.yml` and LINKED, but zero `import`
  in all 444 sources. Every waveform is hand-rolled (`RecordWaveform`, the widget's `Waveform`).
  The `RecordView` comment crediting DSWaveformImage with the playback scrubber was never true.
- **Retired Bonjour plist keys removed** — `NSBonjourServices`, `NSLocalNetworkUsageDescription`,
  `NSAppTransportSecurity/NSAllowsLocalNetworking`. Cost a Local Network permission prompt + an
  ATS exception for a transport dead since 2026-07-06. ✅ device-confirmed: no prompt, sync fine.
- **`cloudKitMacSyncEnabled` defaults ON** — was `?? false` from the Bonjour era; 9 subsystems gate
  on it, so a fresh Mac install silently synced NOTHING. Caught in the same pass: `toggleRow`
  hardcoded `?? false`, so the switch would have read "Off" while sync ran — it now takes
  `defaultOn` that must match the setting's own fallback. ✅ device-confirmed reads On.
- **⭐ Word-timings CloudKit race healed** (`7cee65b`) — THE karaoke bug. CloudKit delivers asset
  rows independently of the Memo record; the Jul-25 memo's `wordTimings` asset trailed its record
  by **10½ hours** (store forensics: ingest 14:44, asset 01:05 next day). Ingest reads assets ONCE,
  so the row was created timings-less and nothing healed it → every click-to-seek fell to 0:00 and
  the highlight degraded to a time proportion, forever, while the phone/iPad played the same note
  fine (they read the asset directly). `MemoCloudIngest.adoptLateWordTimings` now runs in the sweep's
  already-ingested branch, mirroring the photo heal (`MemoPhotoMaterializer.materializeMissing`)
  that already plugged this exact hole for images. ✅ Tuur confirmed karaoke works again.

**Durable lessons:**
- **A late CloudKit asset is a whole bug CLASS, not one bug.** Photos had a heal; timings didn't.
  **`diarization` still doesn't** — same race, same fix shape, not yet written.
- **Verify derived DATA before blaming display code.** The karaoke "regression" was an empty
  `wordTimingsJSON`; the perf cache reverted in `d898771` reproduced the symptoms identically and
  was never the culprit. The store is queryable — read it before theorising.
- **Regex-derived findings need call-site verification.** 3 of 14 audit findings did NOT survive:
  the "8 shipped test doubles" are a live `LaunchFlags` seeding harness (gating them breaks UITests);
  "29 per-call DateFormatters" was 20 static-initialiser false positives + 9 cold paths; the
  `hPa Int/Double` "drift" is deliberate (widening the synced Codable breaks older decoders).

**Owed / next:**
1. **Sync only lands on APP restart** (Tuur, both 2026-07-26 + 27 rounds — app quit+relaunch, not a
   machine reboot). Launch sweep fires; the live CloudKit-import trigger appears not to. Suspect the
   remote-change push/subscription in the Dev build. ⬅ NEXT.
2. **Phone note-list shows the OLD title** (start-of-note) even though the Mac's generated title
   synced and the phone HAS it — display-precedence bug in the list row.
3. **Diarization late-asset heal** — the twin of `adoptLateWordTimings`, same pattern.
4. **Re-land the karaoke perf cache** (`315206b`, reverted): 878.7 ms → 8.0 ms of main-thread work
   per second of playback, measured on 9k words. Re-test against a HEALED note. Note the `@State`
   +`onAppear` cache shape was fragile — prefer memoising off view lifecycle.
5. **Untrack the generated `Info.plist` files** — xcodegen output with no gitignore rule, the root
   cause of cross-branch `CFBundleVersion` conflicts. Deferred because the open iPad branch has
   `App/Info.plist` in its diff; do it the day that branch lands.
6. Not done, each blocked on a real reason: 6 × `DriftedPair` colours (design decisions, iPad branch
   contests), `SignificanceCircles`/`Theme` dedup (iPad branch contests), `CaptureInboxDrainer.process`
   410-line split (device-critical share-ingest, deserves its own round).

## 🔊 (previous CONTINUE HERE) audio-session round (Tuur voice feedback 2026-07-25, remote session)

Two reports, both audio-session shaped. **Code-diagnosed 2026-07-25 remote; instrumentation
committed blind.** Kickoff prompt: `archive/handoffs/HANDOFF-2026-07-25-audio-session.md`
(archived 2026-07-26 per its own Step 3 — ⚠️ read it only as history: it over-fits the
original report, and its fix list A.1–A.5/B.1–B.5 was superseded in flight; THIS section is
the record of what actually shipped).

**2026-07-26 (Mac, branch `claude/audio-session-handoff-93614c`) — Step 0 CLEARED + first two fixes
shipped:**
- The blind instrumentation **compiles** (`d2d6246`). Build clean, unit suite 902/0.
  `AVAudioSessionInterruptionReasonKey` was fine — the handoff's hedge wasn't needed.
  XCUITest suite is red 17 cases **on base too** (measured, not assumed — same failure set with and
  without the commit; one extra was a `new-recording-button` flake that passes on rerun).
- ✅ **A.1 pre-warm + A.5 continuity shipped** (`26899d3`) — see the record section below.
- ✅ **PRESTART shipped** (`164cf53`, b115) — Tuur re-framed the goal: not "feels faster", **"I want
  to start speaking asap after clicking record — nothing said during Starting… is captured.**"
  So capture now starts AT the button: `prestart()` creates + starts the service while the cover
  animates, parks it in `LiveRecordingService.prestarted`, RecordView claims it in onAppear
  (new-memo flow only; append/quote/Siri claim nil → their paths byte-identical). Session settle =
  off-main 50 ms polls against the session's own hw numbers (`settleSession`, absorbs A.1's
  `prewarm()`), replacing 300 ms ladder bites that each redid the full setup. Unclaimed prestarts
  expire in 8 s (`abandon()` — cancel + temp-file delete + a flag every driver checks): no ghost
  recordings. `startInFlight` makes fast-path and ladder mutually exclusive. Unit 906/0 (+4
  prestart tests), mock flow sim-eyeballed record→caption→stop→save.
- ✅→🗑 **A.4 (bring-up off the main actor) SUPERSEDED by prestart.** The engine bring-up stays ON
  main — observers install at the END of `startEngine`, so keeping it on main preserves the
  `.categoryChange` echo ordering exactly and the round-2 P0 window (echo guard reads `tapInputUID`
  + `engine`, both main-actor, assigned at bring-up END) never opens. Latency win came from
  starting EARLIER + settling FINER, not from moving the engine.
- 🔬 **b115 DEVICE TRACE VERDICT (2026-07-26, the round's whole point):**
  `warm=false cat=4ms activate=128ms node=101ms file=28ms tap=3ms engine=969ms TOTAL=1231ms` vs
  `warm=true … engine=1ms TOTAL=10ms` once the route had flipped. **The ~1 s cold-AirPods cost is
  the A2DP→HFP flip INSIDE `engine.start()` — NOT the session calls (132 ms) everyone blamed.**
  History concurs: every cold AirPods start ~0.9–1.1 s, built-in mic ~0.2–0.3 s, the car 1.6 s.
  So pre-warm/settle aimed at the wrong stage; prestart's real value = starting at tap+0 and warm
  repeat starts. The residual cold-AirPods ~1 s is structural to HFP → lands in the
  `.allowBluetooth` decision below. Same trace caught THE RACE (next bullet). Tuur's b115 run
  memo: capture went live at tap+1421 ms via the old path — **his first ~1.3 s of speech is not in
  that file.**
- 🐛→✅ **b115 prestart raced and lost (FIXED b116, `sync park`):** the async park lost to onAppear
  by 15 ms → claim found nil → the view span up the OLD path; the orphaned prestart then became a
  SECOND concurrent recording at +4.1 s, and its 8 s expiry ran `setActive(false)` UNDER the live
  recording (27 ms before Tuur's stop — memo survived by luck). b116: `prestart()` parks
  synchronously in the button action (happens-before the cover), `startFast`/ladder refuse while
  `isRecordingActive` on another instance, and stop/cancel skip session deactivation when another
  instance is live (`releaseSessionUnlessAnotherRecords`). Unit 908/0 (+2 singleton-contract tests).
- 📌 The handoff doc over-fits Tuur's report in two places, for whoever reads it next: it asserts
  "AirPods ON — that's the case that hurts" (he never tied the record latency to AirPods), and it
  predicts quote-capture is "the entire second report" (**his report contains no quote capture** —
  he started a book and listened). The interruption-`.ended` gap is the one that matches his words.
- Compiler corroboration for free: `'allowBluetooth' was deprecated … renamed to
  'allowBluetoothHFP'` at `LiveRecordingService.swift:417` + `:757`. Apple renamed it to say it —
  that flag IS HFP. ⚠️ But swapping to `.allowBluetoothA2DP` costs the AirPods **mic** (falls back
  to the built-in), so it's a capture-quality decision for Tuur, not a free speed win.

### 🐛 P1 · "Starting…" — tapping record doesn't feel instant

> "once I click the record button it says starting, dot dot dot. I feel like when you click the
> record button it's gotta start immediately."

**Where the time goes** (`RecordView.startIfActive` → `LiveRecordingService.startRetrying` → `start()`
→ `startEngine`). `isRecording` only flips true at the very END, so "Starting…" covers ALL of it:

1. The `fullScreenCover` present animation (~350 ms) runs before `startIfActive()` is even called.
2. `startEngine` runs **wholly on the main actor**, and every step is a synchronous IPC to
   `mediaserverd`:
   - `setCategory(.playAndRecord, options: [.allowBluetooth, .defaultToSpeaker])` — **the prime
     suspect.** `.allowBluetooth` is legacy **HFP**, so with AirPods connected this forces an
     A2DP→HFP route flip (~300 ms–1.5 s, and it degrades AirPods playback while held).
   - `setActive(true)` — another IPC; if another app holds the session it must be interrupted first.
   - `AVAudioEngine()` + first `inputNode` touch instantiates the input audio unit.
   - `AVAudioFile(forWriting:)` (AAC encoder), `installTap` + `AVAudioConverter`, `engine.start()`.
3. **Retry amplification — the likely reason it's *noticeably* slow:** a not-yet-ready input format
   (`0 Hz/0 ch`, routine while a BT route settles) throws, and `startRetrying` sleeps **300 ms** then
   redoes the ENTIRE sequence, `setCategory`/`setActive` included. Two or three rounds ≈ 1.5–2.5 s.
4. Being main-actor-bound, even the spinner can't animate while this runs.

**Fix directions (measure first — the numbers land in the devlog now):**
- ✅ **A.1 Pre-warm the session** — DONE 2026-07-26 (`26899d3`). `LiveRecordingService.prewarm()`
  fires from the record button, **off the main actor**, so the mediaserverd round-trips overlap the
  cover's present animation instead of landing after it. `startEngine` skips setCategory/setActive
  when warm, gated on BOTH a 30 s stamp and a live category check (an audiobook or a call
  re-pointing the session falls back to cold); a warm start that still can't vend a format drops the
  stamp so the retry goes cold. `warm=` is in every log line. **Only the main record button is
  wired** — memo-append and the audiobook quote ramble deliberately are not (pre-warming the quote
  path would seize the route from the book earlier, and that's the undiagnosed half of this round).
- ✅ **`.allowBluetooth` DECIDED + BUILT (Tuur picked two-phase handoff, 2026-07-26, b117):**
  phase 1 starts WITHOUT HFP (`recordingCategoryOptions(deferHFP:)` → `.allowBluetoothA2DP`,
  built-in mic ~0.3 s, output stays full-quality A2DP); phase 2 (`scheduleHFPFlip`, ~700 ms in)
  re-allows HFP → the flip lands as a route change (input UID changes, so the own-echo guard
  correctly lets it through) → the rebuild machinery swaps the tap to the headset mic, converting
  into the file's fixed write format. `wantsDeferredHFPFlip` guards: no BT → classic; input
  already HFP → never flip backwards. `isSessionWarm` now also compares OPTIONS (a post-flip
  HFP-full session must not warm-skip the next start back into the 1 s flip). **The swap hole is
  instrumented** (`capture resumed after tap rebuild — hole=Xms`, stamped teardown→first new-tap
  buffer, covers ALL rebuilds incl. AirPods pull-out). Unit 914/0 (6 policy tests; the 25
  route-change tests green). ⚠️ **Device round judges it: if the mid-speech hole is big (~1 s),
  the fallback is A2DP-only as a Settings toggle.** Car HFP (Discovery Sport, 8 kHz) rides the
  same policy — flag for the round.
  **🔬 b117 DEVICE ROUND → ❌ FLIP REJECTED, FALLBACK ENACTED (b119).** Round looked clean in the
  trace (settle 168 ms, engine 398 ms on iPhone mic, tap swap 15 ms, "hole=184 ms") — **then Tuur
  counted to 10 and two numbers were missing.** Word-timings sidecar proved it: `One,` 0.08–0.96
  stitched DIRECTLY onto `four,` at 0.96 — "two"/"three" gone; file 6.87 s vs 9.5 s wall capture.
  ⭐ DURABLE LESSON: **the OS stops the mic at the START of a route transition and posts the
  route-change notification at its END** — any notification-anchored stopwatch under-reports by
  the whole transition (~1.9 s here vs the 184 ms logged). File-duration-vs-wall-clock is the
  honest metric; the log line now says "notification→first-buffer … pre-notification transition
  NOT included". A ~1.9 s hole MID-SPEECH is strictly worse than 1 s of lag before speech → the
  pre-agreed fallback is enacted in b119: **no mid-recording flip — with Bluetooth around the
  WHOLE memo records on the built-in mic** (`avoidsBluetoothMic` policy, renamed from the flip-era
  helpers; output stays full-quality A2DP; a live HFP input at start is never yanked). Unit 914/0.
  Also in b118: startFast detaches BEFORE touching main (b117 showed 278 ms of the "off-main"
  settle queued behind the cover-presentation transaction) → expected button-to-live ≈ ~500–800 ms.
  **🔬 b119 ROUND (18:36): ✅ ALL TEN NUMBERS captured** (transcript len=58 = the exact full
  count; vocab raw shows two/three/five/six/ten). Input never left the iPhone mic across three
  route events — the policy holds. Two catches → b120: (1) button-to-live=1210 ms because the
  AirPods were ASLEEP at tap (out[Speaker]) and engine.start waited ~841 ms for their A2DP
  OUTPUT attach — OS cost, not ours (pods-already-active runs won't pay it); the settle detach
  works (104 ms, ~20 ms after tap) and the warm OPTIONS check earned its keep (settle configured
  before the pods announced; the mismatch correctly forced a cold re-set instead of an HFP leak).
  (2) file ran 0.6 s short of wall (11.50 vs 12.10 s): the output attach fired newDeviceAvailable
  and we tore down + reinstalled a BYTE-IDENTICAL tap — b120 extends the input-unchanged skip
  (uid match + engine running + node format live via canInstallTap) to ALL route-change reasons,
  with the engine-config observer + watchdog as documented backstops for a same-UID renegotiation.
  Unit 914/0, route suite 25/25. No dedicated run owed — the next natural memo's trace confirms.
  Revisit item (roadmap): AirPods-mic recording for the pocket case needs a flip that can't eat
  capture (pre-flip before capture on explicit user intent, or accept the phone mic).
- ✅ **Don't rebuild from scratch per retry** — DONE via `settleSession` (b115): the settle wait now
  happens ONCE, off-main, at 50 ms grain BEFORE the first attempt; warm-skip keeps any residual
  ladder retries down to engine-only cost. The 300 ms ladder survives purely as fallback.
- 🗑 **A.4 Move `startEngine` off the main actor** — SUPERSEDED by prestart (see header): starting
  earlier + settling finer got the win with the engine staying on main, so the P0 window stays shut.
- ✅ **A.5 UI continuity** — DONE 2026-07-26 (`26899d3`). `startingContent` was a centred spinner —
  a *different screen* that swapped out. It now mirrors `recordingContent`'s skeleton: same status
  row, same waveform+timer slot, same control geometry (inert, 45%, non-real ids so a stop button
  that can't stop anything never answers to `record-button`). Going live changes the dot's colour
  and one word. **Eyeballed side-by-side on the iPhone 17 sim** — status row, waveform and all three
  controls on identical y positions.

### 🐛 P1 · The book stops mid-listen and the OTHER app's audio resumes

> "I was listening to a song on Deezer… I went to my app, started playing a book. And twice…
> midway through it stopped and then the song started playing again. So it seems like the book is
> not very persistent."

**Certain from the code:** `AudiobookSession.pause()` does NOT release the session — so a plain
pause cannot make Deezer resume. Only three call sites hand the route back with
`.notifyOthersOnDeactivation` (literally "other app, resume now"):

1. `AudiobookSession.endSession()` — explicit close, library actions, **and the 2-hour idle timer**.
2. `LiveRecordingService.stop()`/`cancel()` — **and the audiobook quote-capture ramble records
   through `RecordView`** (`MergedCaptureView.swift:128`; `AudiobookPlayerView.swift:390` pauses the
   book first). So: capture a quote → record ramble → stop → the route goes to **Deezer**, not back
   to the paused book. Deterministic — reproduce this one first, it may be the whole report.
3. `AudioPlayerModel.deactivateSession()` — memo playback finishing.

**✅ ALL FIVE FIXED 2026-07-26 (b121, `AudiobookSession` + `LiveRecordingService`), unit 921/0:**
- **B.1 interruption `.ended` — THE report's cause.** `pausedByInterruption` latches in `.began`
  (set AFTER pause(), which clears it — order matters); `.ended` resumes only when the latch is
  set AND the system sent `.shouldResume` AND no recording is live. Re-activates the session
  BEFORE playImmediately (post-interruption our session is dead — otherwise "UI says playing,
  phone silent"). No hint ⇒ drop the latch and stay paused (whoever interrupted still owns the
  route). Decision is a pure `shouldResumeAfterInterruption(...)`, 4 tests.
- **B.2 quote-capture handback.** `releaseSessionUnlessAnotherRecords` now ALSO skips
  deactivation when `AudiobookSession.shared.isActive` — the ramble records through
  `LiveRecordingService`, so its `.notifyOthersOnDeactivation` was telling *Deezer* to resume
  instead of the book. `QuoteCaptureFlowView.onFinish` re-activates for the book a moment later,
  so skipping loses nothing.
- **B.3 silent-stop recovery.** The `tick()` detector now REPAIRS (re-activate + playImmediately)
  instead of only logging; latched by `stalled`, so once per stall; stands down while a recording
  owns the session.
- **B.4 false end-of-book.** The `time >= duration - 0.25` pause fires only on the LAST file
  (`isFinalFile`, 3 tests); on an earlier file a metadata shortfall logs once and lets the
  item-end observer drive the advance — that guard could produce this exact report's symptom on
  a book whose stored duration under-reports.
- **B.5 Now Playing ownership** (Tuur's Spotify-vs-Deezer point). `playbackState` is now stated
  explicitly (rate 0 is ambiguous between paused and stopped), unhandled commands
  (next/previous/seek) are DISABLED, and the handled ones enabled explicitly — a half-claimed
  transport is what makes the system treat us as the stale now-playing entry.

⏸ **Device round DEFERRED by Tuur 2026-07-26** ("I've only encountered it once — I'll trust you on
it and mention if it happens again"). Do NOT re-chase it; it is not owed. **The instrumentation is
already armed**, so if it recurs the answer is one `devlog.txt` pull away — read `audiobook
interruption ENDED … pausedByInterruption= shouldResume=`, `record stop — session deactivation
SKIPPED, a book session is active`, `audiobook silent-stop RECOVERY`, `audiobook end-of-book pause`
vs `audiobook metadata SHORTFALL`.

**Confidence, stated honestly** (no trace was ever captured of Tuur's occurrence, so which cause was
HIS is unknown): B.1 and B.2 are certain-from-code — the `.ended` branch provably did nothing, and
the three `.notifyOthersOnDeactivation` callers were traced exhaustively. B.4 is a real latent bug
regardless of this report. Both B.1 and B.4 independently produce his exact symptom, and both are
now closed. ⚠️ **B.1 introduces auto-resume, which is NEW behavior** — if a book ever springs back
to life when it shouldn't, suspect the latch (`pausedByInterruption`) first; it is pinned by
`AudiobookInterruptionTests` but only against the cases we thought of.

**Prime suspect for the "midway, untouched" version — `AudiobookSession.swift` interruption
observer handles `.began` but never `.ended`.** Any transient interruption (call, Siri, system
chime, another app blipping the session) pauses the book **permanently**; Deezer, which honours
`.ended` + `.shouldResume`, comes back. Net effect = exactly what was reported. **Fix = the textbook
Apple handler:** on `.ended` with `.shouldResume`, re-activate and resume if WE were the one paused
by the interruption (latch a `pausedByInterruption` flag in the `.began` branch so a user-initiated
pause is never auto-resumed).

**Other live candidates, all now instrumented:**
- **Silent stop** — nothing compares `player.timeControlStatus` against our `isPlaying`, so if
  AVPlayer stops without an interruption callback the UI keeps claiming playback over silence.
- **False end-of-book** — `tick()`'s `time >= duration - 0.25` guard uses the *stored metadata*
  duration; a book whose metadata under-reports its length pauses mid-listen.
- **Who owns the AirPods play button** (Tuur's Spotify-vs-Deezer observation): we never set
  `MPNowPlayingInfoCenter.default().playbackState`, and unused remote commands
  (`nextTrack`/`previousTrack`) are left enabled. Both feed that behaviour.

### 🔧 Instrumentation SHIPPED this session (unbuilt — verify it compiles first)

DevLog is **DEBUG-only**, so the repro must run on **Skrift Dev**. Added:
- `LiveRecordingService` — `start requested` (with route) / per-stage `engine started` timings
  (`cat=` `activate=` `node=` `file=` `tap=` `engine=` `TOTAL=`) / `start LIVE after N attempt(s) —
  tap-to-live=Xms` / burned-ms on every refused attempt / `logSessionHandback` when stop/cancel
  releases the route while a book session is live.
- `AudiobookSession` — play / pause / endSession / sleep / end-of-book / file-end causes; session
  ACTIVATED + DEACTIVATED; interruption **BEGAN *and* ENDED** with `shouldResume` + reason; every
  route change while a book is active; and a latched **SILENT STOP** detector in `tick()`.

⚠️ Riskiest line if the build breaks: `AVAudioSessionInterruptionReasonKey` in
`installInterruptionObserverIfNeeded` (iOS 14.5+ — drop the field if the compiler disagrees).

## 📖 Phone feedback 2026-07-23 (1 memo, 08:03 — pulled + second-agent verified same day)

All items are the ePub/audiobook-text flow. ⚠️ **The concurrent audiobook session
(`claude/audiobook-ui-harry-collab-e065c7`) is working this area live with Tuur** — the memo
even ADDRESSES its replace-vs-augment fix, and Tuur's screenshots live in that chat. Coordinate
before building any of these here; tick items off when either session lands them.

- **P1 · Partial-ePub ingest is the real bug (corrects that session's diagnosis):** ePub text ==
  spoken text in this case, so replace-vs-augment wasn't the failure — **not all parts of the ePub
  were displayed/ingested**; whole-ePub ingest would have worked. The "weird error" in Tuur's last
  two screenshots (in the other chat) is likely this same bug's visible symptom — check them first.
- **P2 · Big-ePub import UX (13-hour book):** long load, no progress bar, and unclear whether
  listening can continue during the load — show progress + keep playback available (or say so).
- **P2 · Block ePub upload while the book is still transcribing** — currently undefined; Tuur:
  "it should not" be allowed.
- **P2 · Unify the transcribe-book menu with the ePub-upload menu:** one "add text" flow, two
  levels — level 1 get text (transcribe), level 2 upgrade quality (attach the ePub).

## ⏱ One-clock lifecycle: BUILT 2026-07-22 (suites green both apps) — Dev-deploy eyeball owed

**Spec = `Skrift_Native/SkriftDesktop/mocks/lifecycle-triage-peek.html`** (committed d27a047; m6 = the
build panel, m5 = the model; Q-block records the verdicts: m2+m5 adopted, **Lock demoted to a
background verb** — Tuur, 2026-07-22). **DOCTRINE:** supersedes 2026-07-17 "touched never fades" →
*touch restarts the 30-day clock*; only rated/locked/reminder/backlinked sit off the clock. Memory =
`project_lifecycle_one_clock`; roadmap node = `LifeClock` (done).

### ⏱ v3 amendment — "NO NOTE DIES UNSEEN" (Tuur voice note 2026-07-23; BUILT same day, branch `claude/note-deletion-app-open-5r5z56`)

**DOCTRINE (Tuur):** the fade clock keeps running while the apps sit closed (fading stays honest
about time), but **the final doors only move at an app-open** — a note can only be *sent to Recently
Deleted*, and Recently Deleted can only *burn purge days*, while the user has actually opened the
app. Phone in a drawer for three months → the note is still there at the next open (in Recently
Deleted at worst, with its FULL 14-day window to bring back). The bug this kills: the Mac's
unattended 24h sweep stamped `deletedAt` with nobody looking, and the phone's `init` purge (which
also fires on BGTask/silent-push background launches) counted wall-clock from that synced-in stamp —
so a forgotten note could be purged BEFORE the first post-absence render.

**Built:**
- **Purge clock = new synced `Memo.trashSeenAt`** — first open with the note in the trash; a stamp
  older than `deletedAt` is stale by construction (restore → re-trash restarts unseen). Rulebook =
  `MemoLifecycle.trashClockStart/purgeDue/goneAt/stampTrashSightings`; `MemoSpine` + phone
  `trashDaysRemaining` + WayOut labels all derive from it, so an unseen synced-in deletion honestly
  shows the full window from *now* ("shown dates must be true" holds).
- **Phone:** `purgeExpiredTrash` filters on `purgeDue` (the `SkriftApp.init` purge is now SAFE on
  background wakes — it can only remove notes that had 14 SEEN days); `FadingSweep.run` stamps
  sightings then sweeps, and now also runs on every foreground (`scenePhase .active`, behind the
  once-per-device migration guard so ordering stays load-bearing); `softDelete` stamps its own
  clock; `restore`/Bring-back clear it; deduper clones stamp at trash (no unseen grace for clones).
- **Mac:** `LifecycleSweepScheduler` **day-change + 24h heartbeat RETIRED** → sweeps at launch +
  every app activation only; `MacFadingSweep` stamps sightings and stamps what it sweeps; every Mac
  delete gesture + the delete-sync mirror (`MacCloudDeleteSync`) stamps `trashSeenAt` (user
  present). Desktop's LOCAL `PipelineFile` trash purge unchanged (mirror-only — the cloud copy is
  the phone's to purge). Dev hooks: `-poke-daychange`/`-sweepHeartbeatSeconds` → **`-poke-sweep <sec>`**.
- **Tests (NOT RUN — Linux session, no xcodebuild):** TrashTests +3 (synced-in never purges unseen;
  stale-stamp re-trash; softDelete/restore stamp hygiene), MemoLifecycleTests +2 both suites,
  MemoSpineTests unseen-counts-from-now both suites, WayOutView/Trash label fixtures sighted.
- **Prod note:** `trashSeenAt` is additive → lightweight migration + CloudKit schema deploy rides
  the standing promotion checklist. Pre-v3 trash (stamp nil) gets its clock started at the first
  post-update open — a one-time ≤14-day purge deferral, never an early purge.

**VERIFIED 2026-07-23 (Mac session) + merged to `main` (93c5a8a):**
- Suites green: mobile 868 unit / 0 fail (863 + the 5 new v3 tests), desktop 490 / 0 + full MLX
  build. The 18 mobile UI-bundle failures are the known deferred iOS-26 set — re-ran the 4
  not-yet-catalogued ones on the pre-v3 base commit: identical failures, so v3 added ZERO.
- Mac Dev deployed + eyeballed live: exactly one "lifecycle sweep ran over N memos" at launch and
  one per cmd-tab activation, none while idle (log stream, 3 cycles).
- Phone: build 106 (v3) installed + **launch eyeball DONE on device** (11:55, phone reconnected).
  First open under the new build fired `FadingSweep: purge clock started for 53 synced-in trashed
  note(s)` — the pre-v3 migration case. Re-pulled the store: all 53 trashed tombstones now carry
  a valid `trashSeenAt` (== the open moment, 11:55), and their purge countdown reads the **full 14
  days from today** (a note deleted 2026-07-15 that used to read ~6d, and 2026-07-12's ~3d
  "Deleting soon", both now show 14). Purge gate confirmed running off `trashSeenAt` (0 of the 53
  eligible to purge). NOTE the brief's expected cross-device devlog line was a misread of the final
  code: a Mac DELETE GESTURE syncs in WITH its stamp (by design — the user was at the Mac), so it
  shows the countdown from the Mac deletion, NOT a fresh open-window; the `purge clock started`
  line fires only for PRE-v3/unstamped trash (exactly the 53 above). Optional-only remaining: a
  live visual look at the Recently Deleted screen (label code is unit-green, so cosmetic).
- ⚠️ **Concurrent-session hazard found live:** another worktree session (`gracious-easley`,
  audiobook branch at pre-v3 3d3b71e) ran ITS Dev desktop build against the shared Dev store —
  SwiftData migrated the schema DOWN (dropped `trashSeenAt`), my running v3 app's fetches then
  failed silently ("0 memos") until relaunch (relaunch re-migrates up; 103 rows intact, verified
  via sqlite; erased stamps are doctrine-safe = unseen again). Until every desktop-running session
  is on ≥ 93c5a8a, pre-v3 Dev launches will keep flip-flopping the schema — rebase that branch.

**Built (commits cbf87ff → a3fb3ae → c14daf5, desktop 487 + mobile 863 green, full MLX build green):**
- **Shared:** `clockStart = max(recordedAt, keptAt)`; `markEdited()` bumps `keptAt` (all 19 call
  sites audited = genuine investments; 3 speaker-turn paths that skipped it now call it);
  `MemoSpine` lost Parked → `held(locked/reminder/linked)`, gained `chipText` + `peekSentence`;
  once-per-device migration (`oneClockMigrated.v1`) gives old parked notes a fresh clock — phone
  runs it BEFORE FadingSweep in the same launch task (ordering is load-bearing).
- **Mac:** `UnpipelinedMemoSheet` = m6 (clock chip · sentence · photos at `[[img_NNN]]` via
  manifest→`MemoAsset` blob · circles AS the flag — silent-0.1 button GONE · soft Delete + "14 days
  to undo"); quiet rows right-click **Flag for processing / Lock / Open / Delete**; band excludes
  locked; conveyor renamed **Fading** + fading rows get a trash button; **the Mac can delete a
  synced note for the first time**.
- **Phone:** Fading renames (nav title, Journal shelf, empty state, clock copy); WayOut peek renders
  photos + Delete (soft for fading / confirm-purge for deleted); detail hint = "rate it to keep it".

**Eyeball waves (2026-07-22, live round with Tuur):**
- Wave 1 (b103→104): Mac list confirmed working — migration proven on sight (old "kept — edited"
  memos read "starts fading 21 Aug" = fresh clock; untouched one kept 15 Aug). Phone list rows
  briefly got an always-on clock line (68dbcc2) — overshoot, trimmed by wave 2.
- Wave 2 (b105, 6a096bb) — **ASYMMETRY DOCTRINE LOCKED (Tuur):** the Mac list = the deciding room
  (always-on per-row state: chips, hollow circles, clock lines); the phone list = the NOTEBOOK —
  unrated is the default state there, not an alarm, so rows stay clean. Phone clock line =
  urgency-only (amber, fading ≤7d away or already fading); couch-triage = the new **"Not rated"
  toggle** in Sort & Filter (unrated + unlocked, the Mac band's membership). The two lists are
  deliberately NOT twins — surface role, not drift.

**OWED (next session, rides the 🧬 walkthrough tail):**
1. Deploy Dev both apps + eyeball: peek (chip/sentence/photo/circles/Delete) on the bed-photo memo
   B122966B-era case · quiet-row menu verbs · Fading renames everywhere · phone peek photos+Delete ·
   migration actually bumped the old parked notes (check a "kept — edited"-era memo now reads
   "starts fading <date>").
2. 🧬 walkthrough items phrased in the old vocabulary are OBSOLETE: "kept — edited" chips no longer
   exist — expect "starts fading <date>" / held lines instead.
3. Prod promotion: one-clock rides along with the 🧬+📖 promotion (nothing extra beyond the
   standing checklist).

## 🖥️📱 CONTINUE HERE — iPad wave 1 BUILT overnight (2026-07-22 eve, Fable autonomous session; Tuur review = the gate)

**WHAT EXISTS NOW (branch `claude/ipad-app-version-3f9a3a`, worktree `nice-shtern-06faba` — NOT on main):**
SkriftMobile is UNIVERSAL (family "1,2" + all iPad orientations + extensions; build 106). Same four
tabs; at regular width: Notes = list↔note split (m1) · note page = reading measure + standing
CONNECTIONS panel (m3) · Review = river + standing calendar/places pane w/ map mode (m4/m4b,
completes the signed journal-desktop §2) · Books = cover shelf + three-zone player w/ chapters rail
(m6) · record = centered card + ⌘N/⌘F/⌘1-4 (m7) · **Polish on this iPad** = the Mac's exact pinned
MLX/Gemma stack as an ON-DEMAND engine behind `PolishCenter` (m5; prompts single-sourced
`Shared/Pipeline/PolishPrompts.swift`; writes `MemoEnhancement`, LWW; gate = M-series pad ≥6 GB).
Compact width = the phone app byte-for-byte (the wave's law). Docs: `Skrift_Native/IPAD_PLAN.md`
(roles: phone captures, Mac volunteers, iPad is asked) + mock `mocks/ipad-app.html` (m1–m7,
verdicts inline, every variant kept) + briefs `LANES-2026-07-22-ipad/`.

**Verified tonight:** 5-lane batch (3 Opus + 2 Sonnet, LANE_PLAYBOOK) merged conflict-free;
iPad Pro 13-inch (M5) sim build green after EVERY lane; mobile unit suite **885/0** (was 808 —
lanes added tests); desktop untouched-behavior check green (487/0 + full MLX build — it compiles
the moved `ImageMarkerReinsert` + shared prompts); sim screenshots vision-checked (Notes split,
Review pane, shelf, detail+Connections, Settings).

**TUUR'S REVIEW BOARD (in order):**
1. **Walk the mock first** (`mocks/ipad-app.html`) — verdicts are Fable picks, none are locked;
   m2 (icon-rail shell) was drawn + rejected on the one-IA rule; engine B (Apple Intelligence)
   parked in favor of same-Gemma-as-Mac.
2. **Eyeball the sim build** (or install Dev on the real iPad — its Skrift Dev is ANCIENT, the
   standing item): rig = `scratchpad ipadshot.sh` flags, or Xcode. Known cosmetics: the detail
   ⋯/+ toolbar pill floats over the Connections panel corner; sidebar wears the native iPadOS
   floating-card look (system idiom — mock drew flat columns; Fable accepted system).
3. **Polish on iPad device test** (sim can't Metal-JIT): Settings → Polish on this iPad →
   Download (4.6 GB) → Polish now on a real note → confirm the enhancement lands + Mac doesn't
   redo it (LWW). Memory-pressure behavior under a loaded model = watch devlog.
4. **Owed by contract:** wide-player live eyeball (tap-driven, rig can't tap) · landscape pass ·
   Stage Manager/Split View compact fallback · ⌘-shortcut feel · onboarding on pad.
5. **Then:** promote to main when happy (standard promotion checklist; CFBundleVersion already
   106; Release App-Group one-time Xcode visit still pending from capture-items).

## ✅ DONE 2026-07-26 — an unrated note IS a normal note (`1b5072c`) — Tuur's eyeball owed

Failed twice, fixed on the third. Rounds 1–2 both built a PARALLEL renderer (`UnpipelinedMemoSheet`
in `.pane` mode) — first the peek's anatomy, then hand-copying the note anatomy into it. Tuur:
*"make an unrated note identical to other notes… its just a normal note. nothing special."*
Copying the look was never the ask; the ask is **no second renderer**.

**The route, decided with Tuur.** Presented A (new `NoteSubject` view-model) / B (ingest-on-open) /
C, and Tuur cut through it: *"i dont understand. just look at what a normal note looks like. and
make it look like that."* → C, which is A with the projection target that **already exists**:
`PipelineFile` IS the shape the note view reads. `MemoNoteProjection` (`Pipeline/Ingest/`) maps a
`Memo` into one that is **never inserted** into the pipeline store, and the ordinary
`NoteDisplayView` renders it. No new type, no second renderer, and *the rating IS the flag* holds
**by construction** rather than by policing.

**Why not B, from source:** `WayOutRules.unpipelined` defines the quiet sidebar list as *"has no
`PipelineFile` row"* — so ingesting on open would make the quiet row **vanish the moment you opened
a note**, on top of auditing ~35 `FetchDescriptor<PipelineFile>` sites.

**Deliberately faithful, not improved.** The projection maps through `MemoCloudIngest.metadataJSON`
— the exact blob a real ingest writes — so chips, capture blocks and quote styling derive through
the same accessors. **Bugs included on purpose:** matching what a normal note ACTUALLY does is the
point, and quietly doing better would itself read as a difference.

**Differs only in what it genuinely can't do** (`NoteCapabilities`): no Process/Export (no pipeline
row to act on), no Connections (nothing indexed), no include-audio switch (governs an export that
can't happen, and the field is Mac-local + unsynced). Everything that makes a note a note is
unconditional.

**Edits land on the memo** via `MemoNoteProjection.writeBack` (title/transcript/tags/rating) —
deliberately NOT via `MacCloudEditSync`, which writes a `MemoEnhancement`, i.e. *"the Mac polished
this"*: a lie about a note the Mac never processed. That carrier now skips context-less rows.
Rating through the ordinary circles flags the memo → sweep ingests → the pane becomes the real row
by itself, because **`activeID` already held the memo UUID either way**. `AppModel.paneMemoID` and
the `.pane` presentation are **deleted**; selection is one id space again. The Journal river keeps
its `.sheet` peek (a glance from another surface is a different gesture).

**Verified by RENDER:** new hosted `-snapshot-unrated` puts a pipelined note and the same content
projected **side by side**. Pixel-sampled: title `rgb(207,207,208)` on **both** sides, dimmer than
body `rgb(224,224,227)` — the greyed derived title Tuur asked for, identical across both. Gate:
desktop unit **520/0** (was 510; +10). Deployed to `/Applications/Skrift Dev.app`.
**OWED: Tuur's live eyeball** (open an unrated note, rate it, watch the hand-over).

> 🐞 **Found in passing, NOT fixed (own chunk):** `PipelineFile.durationSeconds` parses an **HMS
> string**, but `MemoCloudIngest.metadataJSON` writes `duration` as a **Double** — so **no
> CloudKit-synced note shows a duration chip or docks a player** on the Mac; only the demo seeds
> (which write strings) do. Pre-existing, affects every synced note, not just unrated ones.

### ✅ Tuur's eyeball round on the above (2026-07-26, `3569067`) — 2 fixed, 1 decided-as-is

He opened an unrated note on the live Dev build and confirmed the anatomy, then found two things.

**1. The derived title cut MID-WORD** — "…once I click the record button, it s". `firstBodyLine`
did a bare `prefix(80)`; it reads as a rendering fault, not a truncation, and unrated notes never
have a real title to fall back FROM so it's always on screen. The same slice sat in **seven**
display sites across both apps → now ONE shared rule, `Shared/Model/NoteTitle.clip`: break on the
last word boundary + "…", hard-cut only a single word longer than the limit.
⚠️ **`MemoExporter.exportTitle` deliberately KEEPS the hard slice** — it feeds the vault FILENAME
via `ObsidianPublisher.sanitizeFilename`, so an ellipsis there would rename notes on disk.

**2. Un-rating went nowhere** ("i just took that note and added a low importance score, it lit up.
when i removed it it did not go grey again"). Re-tap sets the binding to nil and BOTH write-back
paths dropped it on an `if let`.
**The trap I nearly shipped:** `nil` is AMBIGUOUS on a `PipelineFile` — "cleared" OR "never rated".
Making `MacCloudMetaSync.mirror` read nil as 0 looked right, but `mirror` is a passive
current-values pass that **also runs on tag edits**, and a Mac-local import legitimately sits at
nil while its authored `Memo` holds the 0.1 floor (`MacMemoAuthor`) — so any tag edit would have
silently un-rated it. So: **clearing is an EVENT, not a state.** `mirror` still declines to guess;
the new `MacCloudMetaSync.setRating(_:for:)` is driven by the circles' own onChange, where nil is
unambiguously a re-tap. `MemoNoteProjection.writeBack` carries a cleared rating directly (a
projection only exists for an unrated memo, so 0 is never a clobber).

**3. ⏸ DECIDED AS-IS by Tuur (2026-07-26) — rating stays a ONE-WAY door. Don't "fix" this later
without asking him.** Once a rating creates a `PipelineFile`, un-rating leaves the row behind:
`WayOutRules.unpipelined` means *"has no row"*, so the note never returns to the quiet grey list,
and `ProcessingCoordinator.needsProcessing` **ignores significance entirely** (`deletedAt == nil &&
enhanceStatus != .done`), so it stays in "N to process" and still gets processed. He was shown the
symmetric option (un-rate → back to grey, keeping any polish already produced) and chose to leave
it. **Known asymmetry, accepted.** Worth knowing if you ever touch it: making the rating govern
processing is NOT a one-liner — `IngestService` never sets `significance`, so gating on it would
stop Mac-imported files from processing at all.

Gates: desktop **525/0** (+5), mobile **970/0**. `-snapshot-unrated` now seeds Tuur's own note as
the regression fixture.

---

## ✅ DONE 2026-08-12 — the two `SignificanceCircles` VIEWS are ONE view

`Shared/UI/SignificanceCirclesView.swift` is the control; each app keeps a ~60-line file that
supplies a `SignificanceStyle` (colours out of its own Theme, plus the measurements it tuned) and
adapts its binding. All five call sites are unchanged. The stated blocker — two colour namespaces
(`Color.sk*` vs `Theme.*`) — is the style struct.

**The live drift it killed:** both files wrote the past-the-wall mix out channel-by-channel
(`(124 * 0.42 + 245 * 0.58) / 255`, twice). `Palette`'s header calls that class of bug "fixed by
construction" — it wasn't, because neither copy sourced `Palette`. It is now
`Shared/UI/SignificanceWarmFill.swift` (channel VALUES only, Foundation-only so the SwiftUI-free
unit bundle can test it), pinned by 3 tests to the exact numbers the two copies produced.

**Verified by RENDER, both apps, byte-identical before → after:**
- Mac: new hosted `-snapshot-significance <png> [-light]` (5 states × 2 schemes). `cmp` says
  BYTE-IDENTICAL in both schemes. Note `NSApplication.shared`, not `NSApp` — the global is still
  nil that early in the snapshot path and reading it traps.
- Phone: new `SkriftMobileTests/SignificanceCirclesRenderTests` (ImageRenderer → PNG; the phone has
  no headless render mode, so its control gets LOOKED at from the test bundle). BYTE-IDENTICAL.
- ⚠️ `SkriftShare` lists Shared files INDIVIDUALLY, not by directory — both new files had to be
  added to its `sources:` by hand or the extension wouldn't compile.

**Six fields are drift parked as style, not decision** — `flameSize` (9/10), tag+tier `tracking`
(0.54+0.63 / 0.5), `syncDotSize` (5/6), `syncFontSize` (11/10.5), `flameOpacity` (0.9/1.0),
`tierWeight` (regular/medium). Each is sub-2pt and nobody chose it; collapsing a pair is an eyeball
round, exactly like a `Palette.DriftedPair`. **One change was made, disclosed:** the phone's
`kerning` became `tracking` (one modifier for both), which adds 0.5pt after the last character of
"REFINE PASS" and each tier label — invisible in the render diff (still byte-identical).

Gates: desktop **726/0** (+3 new `SignificanceWarmFillTests`, proven to run via `-only-testing`),
mobile unit **1027 tests / 2 skipped / 0 failures**. The mobile UI bundle fails 12 — all on the
pre-existing list this file already records (§ Low Power Mode, 2026-08-11: 17 failures re-run at the
prior commit, `ShareSheetActivationProbe` + `MemosListUITests.testSwipeToDelete` among them). Nothing
new. What that probe CAN'T tell us is whether the extension's control still runs, so it was proven
another way: the generated `SkriftShare` Sources phase compiles both new shared files (its list is
per-file, not per-directory) and the .appex built and embedded.

---

## 🎯 CONTINUE HERE — export destinations (spec SIGNED OFF 2026-08-26; gate fix BUILT)

**The ask** (from the portfolio repo's chat, 2026-08-26): Skrift is already the capture instrument
for Tuur's archive. It needs to write to more than one place, chosen per note.

**FOUR destinations, ONE-OF-FOUR — never two.** Personal is the default and means today's Obsidian
path; the other three leave for the archive repo.

| chip | folder | the line | AI reads it |
|---|---|---|---|
| Personal | the Obsidian vault | his own thoughts | never |
| Made | `portfolio/_inbox/` | something he made | yes |
| Idea | `portfolio/_ideas/` | something he wants to make — HIS | yes |
| Inspiration | `portfolio/_inspiration/` | someone else's, that he liked | yes |

**THE DOCTRINE (don't re-derive):**
- **The destination is a PRIVACY BOUNDARY, not a filing shelf.** His reason for the split, in his
  words: his own thoughts must never be read by AI; his ideas and inspirations are things he WANTS
  Claude to work out with him. That single fact decides every open question below.
- **One-of-four, never two.** `idea` + `inspiration` is meaningless (the line is AUTHORSHIP — you
  cannot be both the author and not the author), and `personal` + anything would put a private
  thought in an AI-readable repo. The engine would allow it (`ExportLedger` is keyed per destination
  folder, so N destinations are N ledgers); it is refused on purpose.
- **The photograph that gave him an idea is ONE note, filed `Idea`** (Tuur, 2026-08-26: *"that's
  actually how it always happens"*). The other person's thing rides inside it as the picture;
  authorship still decides. `Inspiration` is therefore the NARROWER bucket — liked it, no idea yet.
- **Reserved words.** Typing one of the four in the free tag field is refused and points at the
  control that actually moves the note.
- **A stored FIELD rendered as a chip, not a literal tag string** — a real tag would collide with a
  free-typed `idea` and re-route the note. Additive CloudKit optional; nothing else in the pipeline
  changes.
- **Behind ONE Settings switch, off by default** (Tuur: *"somebody might not care… this is very
  specific for me"*). Off = today's behaviour, byte for byte.
- **NO Mac dependency.** A destination is a folder bookmark held per device, like today's Obsidian
  picker; whoever can see the folder writes to it. The repo lives in `Documents` on his Mac today,
  so the Mac writes; move it to iCloud Drive or a Working Copy checkout and the iPad writes with no
  code change.
- **The archive keeps the NAMES.** Tuur reversed my privacy call, deliberately: the archive becomes a
  public website, and *"it'd be nice to give proper credit where credit is due"*. So `people:` AND the
  body's `[[Jack]]` links survive to the archive. PLACES do not — `Compiler.peopleLinks` already
  separates the two via `knownPeople`; point that same allow-list at the BODY.
- **Archive frontmatter** = `title` `date` `source` `summary` `tags` `people` `location` `author`
  + the three stamp keys (`skriftID` `skriftHash` `lastTouched` — they are what let a capture be
  filed out of `_inbox/` without Skrift respawning it). DROPPED: `significance` `weather` `pressure`
  `pressureTrend` `dayPeriod` `daylight` `steps`.
- **Audio rides along**, same as today. VIDEO too — and that is real work: `VaultLayout` has NO video
  asset kind (explicitly cut at the 2026-08-14 folder-model signoff), so shared video is transcribed
  today but the file has never been exported anywhere.
- **A filed note is FROZEN.** Once he moves a file out of `_inbox/` into an item folder, a later Skrift
  edit reports `movedAway` and never reaches it. Correct for an inbox — a one-way door, noted.

**DESIGN — `mocks/note-destination-tags.html`, SIGNED OFF 2026-08-26: version B, COLLAPSED.**
The row lives on the note beside the importance circles (the two routing decisions sit together:
importance says whether a note may leave, destination says where). It rests as ONE chip and expands
to all four on tap. **The two resting states are deliberately unequal** — Personal is a quiet purple
chip and nothing more; an archive destination also names its folder and says AI READS THIS. An
always-on warning is no warning. B4 (chip inline with the tag row) REJECTED. Version C (one fuzzy list
mixing tags and destinations) REJECTED — it puts "add the word inspiration" and "move this note into
the AI-readable repo" one keystroke apart.

**The tag sheet is re-done in the same pass** (it ships as drawn in the mock): no auto-keyboard (today
`.onAppear { inputFocused = true }` means the keyboard eats the sheet before you decide anything),
suggestions above the fold, and **vault tags merged into the suggestions** — the Mac has read real
vault tags via `VaultTagScanner` all along, the phone never has, though it holds a bookmark for
exactly that.

### ✅ BUILT 2026-08-26 — the gate fix (a prerequisite, and a standalone bug)

Tuur found it by asking why a photo-only capture stalls. **"Has a pass RUN?" was being answered by
"is there polish worth showing?" (`MemoEnhancement.hasContent`).** A note the model had nothing to say
about — a bare shared photo, a three-word note, a link with no comment — is PROCESSED and has NO
CONTENT. Two devices, two mechanisms, one identical dead end:
- **Mac** — `MacCloudWriteBack.upsert` returned `nil` for an all-empty result, so **no row was written
  at all** and no other device could ever learn the pass had run.
- **iPad** — `PolishCenter.write` always wrote the row, but every gate read `hasContent`, so an empty
  row still counted as unprocessed.

Result: the export button read *"Process this note first"* forever, pressing Process did the identical
nothing, and on the iPad the note never left the to-process pile (`ProcessPile` builds `enhancedIDs`
from `hasContent`). The **Mac never had the bug** — its own button reads a local step flag that
`BatchRunner` already sets `.done` on empty input (`BatchRunner.swift:104`).

**Fix:** `MemoEnhancement.processedAt` + `isProcessed` in Shared — the one predicate all three apps
read. A pass records itself even when empty (`upsert(passRan:)`; a manual-edit re-sync does NOT, or
every empty edit would mint a placeholder). Pre-`processedAt` rows fall back to the **all-three-parts**
rule, never "any part" — a note's polished title is also written from the user's own chosen title, so
any-part would call a merely-retitled note processed. That rule used to be hand-rolled inside the
phone's `MemoDetailView` and now lives in Shared where the export gate and the process pile read it too.

Gates: **desktop 750/0 · mobile 1037 tests, 2 skipped, 0 failures · full MLX desktop build green.**
OWED: a device round — share a photo into Skrift Dev with no words, rate it, process it, export it.

### Build board — 1–5 BUILT 2026-08-27, 6 BLOCKED ON A DECISION
1. ✅ `NoteDestination` + `Memo.destination` + the reserved-word guard [`37ae2c17`]
2. ✅ The collapsed chip row — shared `DestinationRowView`, phone/iPad [`d7702652`] and Mac
   [`2d8f87d1`], where the destination also became a three-way synced field.
3. ✅ Settings → Destinations on both apps [`020e7314`]. **ONE archive root, not three pickers**
   (the three are siblings inside it); the resolved subfolders are shown read-only.
4. ✅ `ExportProfile` — the archive layout [`56e7df94`]. Flat, `_ideas/2026-08/<timestamp>.md`,
   media beside the note, `![](file)` not `![[file]]`, reduced frontmatter, people-links kept and
   everything else plainified. `ArchiveExportTests` proves it on real files.
5. ✅ The tag sheet rework [`—`]: no auto-keyboard, suggestions above the fold, and the phone
   finally reads vault tags (`TagMatcher` + `VaultTagScanner` moved to `Shared/Pipeline/Tags`).
6. ✅ **Video — DECIDED 2026-08-27: don't store them, skip them** (Tuur: *"no dont store videos,
   just skip them"*). Nothing to build. Skrift never keeps the movie — `MemoSaver.importVideo`
   extracts audio into `memo_<uuid>.m4a`, takes a thumbnail, and the temp copy is discarded —
   so a video-sourced note exports its markdown, its EXTRACTED AUDIO and its photos, and no
   movie file. Storing originals would have meant hundreds of MB per clip in SwiftData and
   CloudKit, synced to every device. **Closed, not deferred**: don't re-open it as a task.

### ✅ 2026-08-27/28 — the frontmatter unified against the REAL archive, and four fixes from his rounds

Tuur pointed this session at `~/Hackerman/Tiurihartog.com/` and it settled every open question.
**Read the repo before proposing a key** — 148 `item.md` files, and two of Skrift's keys were
already taken:

- **`type:` PULLED.** It shipped for one day as `type: idea`. That repo owns `type:` as its
  CATEGORY key — `type: furniture` ×31, `type: lamps` ×13, on 146/148 items, verbatim from his
  folder names. An entry sorted out of `_ideas/` into `Lamps/` would have had one key meaning
  two things. The folder says which bucket a capture arrived in; once sorted, that fact is spent.
- **`source:` → `capture:`** on archive exports. Same collision, quieter: the archive uses
  `source:` for an item's provenance path (130/148). The vault keeps `source:` unchanged.
- **`author:` DROPPED** on archive exports — the real item frontmatter has none, and everything
  there is his by that archive's rule, so the key could only hold one value.
- **`voice:` ADDED** (raw | cleaned | written) — the archive's own key, values and rule. Set
  EXPLICITLY by each app: the Mac carries its polished body in `enhancedCopyedit`, the phone
  re-linked into `sanitised`, so a Compiler-side guess read `cleaned` on one device and `raw` on
  the other. The first attempt did exactly that; the test caught it.
- **`needs: - credit` ADDED**, on INSPIRATION only — the folder OR an `#inspiration` tag. Made and
  Idea are his; a credit need there is false, and a punch list of false needs is not one.
- **`credit:` shape**: free-text lines, no URLs. Tuur: *"that's not up to us, we can do the
  looking up later"* — the archive fills it, Skrift only raises the need.

**NO SUGGESTION ENGINE.** Tuur killed it: *"I know what I'm recording, I just click a button…
it's gonna be so wonky."* The four buttons stay. Don't re-propose inferring the destination.

**The name** (two rounds): `_inspiration/testing-the-functionality-of-the-recording-device.md` —
NAMED, not dated, and FLAT. No month folder, no timestamp, no 42-char cap (that cut a real title
and he caught it). His 148 items are named exactly this way and `date:` is frontmatter. The
timestamp survives ONLY as the fallback for a capture with no title. Collision suffix is
slug-shaped (`a-bench-9e24a49f`) and deterministic.

**Two bugs his rounds found:**
1. **The Mac's place never reached its own export.** `MacLocationStamp` wrote only
   `Memo.metadata`, so it synced to the phone and the Mac — which compiles from
   `PipelineFile.audioMetadataJSON` — still wrote an empty `location:`. Writes both models now.
   ⚠️ This is the PipelineFile⇄Memo seam `MirroredNoteFields` was built for the day before, and
   I walked into it anyway. The refactor makes the seam cheap to cross, not hard to forget.
2. **DELETED was treated as FILED.** He deleted his test exports, edited a note, re-exported, and
   got *"filed out of your Skrift folder — left where you put it"* forever, with no control to
   clear it. `VaultStamp.locate(id:under:)` now tells them apart: found elsewhere → still
   `movedAway` (the inbox doctrine, unchanged); found nowhere → the ledger entry drops and the
   note writes fresh. **Both apps' tests had made the same conflation** — each faked "filed away"
   by DELETING the file — which is why neither caught it.

**ONE EXPORT VERB, ONE ANSWER** (2026-08-28, from his round): the two apps said different
things after the same export, and a REFUSAL faded on the Mac — every outcome shared one
3.5-second banner, so "filed out of your Skrift folder" (a permanent blocker) got the same
three seconds as "done", which is how he hit it without seeing why. `ExportOutcomeCopy` in
Shared is the one table now and it carries the STICKINESS rule with the words: a refusal
stays until dismissed on every device, a success may fade, and `unchanged` no longer claims
"Exported". ⚠️ Per-device ledger CONFIRMED AS DESIGNED: an iPad export does not show as
exported on the Mac (each device has its own folder bookmark). Cosmetic only — the Mac's
write finds the iPad's file by stamp and updates in place, never duplicates.

**Also:** the "AI READS THIS" label cut (an always-on badge is no signal); the export button says
*"Export to archive"* when that is where the note is going; the Mac records a place at all now
(`Shared/Metadata/LocationOneShot.swift`, recordings only — never imports, which would be
inventing metadata); `#inspiration` allowed as a tag again, REVERSING his 2026-08-26 instruction
after his 2026-08-28 workflow needed it.

Builds 156 → 164, installed on iPhone 13, iPad Pro and the Mac each round.
Mobile 1065/0 (2 skipped) · desktop 762/0 · full MLX build green.

### Owed
- **Tuur's device round.** Everything above is simulator- and snapshot-verified only. Point it at a
  THROWAWAY folder before the real portfolio repo.
- The gate fix (`00e67299`) is still device-unverified: share a photo in with no words, rate it,
  process it, export it.
- Questions still out to the portfolio chat: is `_inspiration` still right now that it is the
  narrower bucket; does the site render person pages (or do the `[[Jack]]` links dangle); does the
  site have a "type" concept matching the four; does the archive accept video files.

**Questions out to the portfolio chat:** is `_inspiration` still right now that it's the narrower
bucket? does the site render person pages (or do the `[[Jack]]` links dangle)? does the site have a
"type" concept matching the four? does the archive accept video files?

---

## ✅ BUILT 2026-07-26 — ONE export engine, both apps (chunks 1a–1c: `db84dfa`→`635da5f`→`cb09639`) — real-vault round OWED

Tuur's *"make it shared code and then we improve both"*, built overnight after the design
conversation locked the doctrine. **THE DOCTRINE (don't re-derive):**
- **The picked folder IS the destination** — no `Skrift/` prefix, no source subfolders. Tuur already
  keeps `0 Inbox/Skrift`; the old phone layout would have nested `Skrift/Skrift/` inside it.
- **The folder is an INBOX** — notes get filed OUT. Identity lives in the FILE (the stamp), never a
  remembered path; a note gone from where we wrote it reports `movedAway` and is NEVER re-created
  (v1 would have resurrected every note he files into PARA). Following moves = the plugin (i14).
- **THE STAMP is a PUBLIC CONTRACT** (`skriftID` · `skriftHash` · a real `lastTouched` — the key that
  had shipped EMPTY in every export forever): ours? / edited? / which note, wherever it lives? The
  hash spans the FRONTMATTER (a tag added in Obsidian counts as an edit — "edit tags in the app" was
  rejected as unintuitive), and covers every line but its own.
- **Never write over anything not provably ours + untouched.** Foreign file → deterministic
  `<stem> <id8>.md` beside it; PRE-STAMP legacy export → `blockedLegacy` with NO suffixed twin
  (else his whole real vault duplicates on first re-export); vault-edited → back off, report
  ("You've edited X in Obsidian — Skrift left your version alone"). Return path ADOPTS later.
- **iCloud discipline:** atomic + NSFileCoordinator everywhere (the Mac was a bare `Data.write` —
  exactly the writer class behind Obsidian+iCloud's documented `(1)`-duplicate behavior), and an
  unchanged note writes NOTHING (not even a timestamp/asset — `contentEquivalent` ignores the
  volatile lines; churn is what breeds conflict copies).
- **Ledger = convenience, stamp = safety.** Per-picked-folder ledgers (`ExportLedger.default(for:)`);
  a wiped/fresh ledger ADOPTS its own file by stamp instead of twinning — which is ALSO the
  iPad-meets-the-Mac's-export case, so the cross-device duplicate risk closed itself.

**What each side gained:** Mac — the edit guard + atomicity + honest per-outcome toasts (the
reconciler's auto re-export, the riskiest writer, now only records what it wrote). Phone — PHOTOS
export (markers → real `![[…]]` embeds + `Attachments/`), AUDIO into `Voice Memos/`, the Mac's
polish preferred once `MemoEnhancement` syncs back, lazy blobs (unchanged note = zero bytes read,
test-pinned), and **the missing FRONT DOOR**: Settings → Obsidian (folder picker via security-scoped
bookmark, enable, Rated-only/All, an `author:` field — must match the Mac's or each device sees the
other's file as "changed" — and Export now with a per-outcome summary). `ExportStateStore` retired
(never ran → zero migration risk); the lock-notice check collapsed onto `ObsidianVault.hasPublished`
(it sat twinned in two views).

**Gates:** desktop 557/0 (+28 stamp/engine) · mobile 972/0 (publisher/coordinator suites rewritten
to the new doctrine) · `-vaultexport <dir>` three-pass proof (8 creates → 8 unchanged → sabotage:
backedOff + movedAway-not-respawned) · `-vaultpreview` prints the stamped contract · iPhone-sim
eyeball of the Settings section + the system folder picker presenting. Mac Dev deployed.
**OWED:** Tuur's real-device round — pick a THROWAWAY folder first (this is the phone stack's
first-ever live run), then the real `0 Inbox/Skrift`; his Mac's noteFolder already points at a
Skrift-owned folder so nothing moves there; legacy notes will report `blockedLegacy` by design
(adopt pass = plugin/return-path). ⏸ still parked: `includeAudioInExport` sync (own contract chunk);
the Mac-side return path (kept SMALL on purpose — the plugin owns following moves, i14).

---

## 🔌 THE OBSIDIAN PLUGIN MENU (2026-07-26) — 10 wireframes for Tuur to pick from

Mock: `Skrift_Native/SkriftDesktop/mocks/obsidian-plugin-menu.html` (NOT signed off — a PROPOSAL
menu) · Artifact: https://claude.ai/code/artifact/1d301ae1-7fbc-4ef6-b952-911eacc61ab4
Roadmap: i14 (the ladder: phone → +Mac/iPad → +plugin; it's the TOP RUNG of standalone, not a rival).

**Three lanes** (every feature is tagged): 🟢 vault-files (works everywhere incl. Obsidian on
iPhone/iPad — files + `.skrift/` sidecars travel with the vault) · 🟠 Mac-app (localhost to the live
engines — the Local REST API plugin proves the loopback+auth pattern is community-accepted) ·
🟣 hand-off (`obsidian://` ↔ `skrift://`, one app wakes the other).

**The menu, with the thinking done in advance:**
1. **Listen to any note** 🟢 M — audio is ALREADY in the vault (`Voice Memos/`); ship word timings
   as `.skrift/timings/<id>.json` sidecars and the plugin renders inline player + karaoke. Works on
   Obsidian MOBILE with no Skrift app nearby. Nothing else in that ecosystem can (nobody has the
   timings). *Needs: timings sidecar export (small addition to the engine's asset lane).*
2. **The real inbox** 🟢 M — sidebar list of unfiled Skrift notes, one-click file into PARA;
   `rename` events feed the ledger → the RETURN PATH solved by events, no crawler. *This is the
   card that deletes chunk 2.*
3. **Connections, whole-vault** 🟠 L — the panel over EVERYTHING ever written; also exactly what
   i13's tightness lens waits on. *Needs: Mac app serving embeddings on loopback.*
4. **Sync doctor** 🟢 S–M — standing per note (current / edited-kept / conflict-copy / filed /
   legacy-adopt?) read from stamps alone; the safety model made visible, incl. iCloud `(1)` copies.
   *Cheapest trust-builder; pairs with 2.*
5. **Names everywhere** 🟠 M — Sanitiser over hand-written notes → `[[link]]` suggestions.
6. **Record into this note** 🟣🟠 M — ribbon mic → memo lands linked at cursor.
7. **Book pages** 🟢 S — per-book literature note aggregating quote captures (frontmatter only).
8. **Search your voice** 🟠 M — ⌘P semantic search over memos; play the moment.
9. **Today, spoken** 🟢 S — the day's captures as a daily-note block (place · weather · links).
10. **How the thinking evolved** 🟠🟢 L — the NORTH STAR view: an idea's arc, first mention → now.

**Free win found in research:** the stamp keys are ordinary Obsidian **Properties**, so core
**Bases** can already table/filter every Skrift note TODAY (`skriftID exists`) — zero plugin.
**My recommended v1 bundle:** 2 + 4 + 1 (inbox + doctor + listen) — all 🟢 vault-files, no server,
mobile-capable, and together they retire the return-path chunk while shipping the one feature
nobody else can copy. **Costs, standing:** TypeScript third codebase (the surface the repo
deliberately killed), community review, desktop-first for anything 🟠.

## 🟢 RESUME HERE (2026-07-26 end of session — pushed, parked between chats)

**Branch `claude/ipad-app-version-3f9a3a`, worktree `gracious-easley-e3fc96`. PUSHED to origin
(41 commits, `329aa98`). NOT on main** — promotion stays deliberate. `collab/` is another session's;
never stage it. Mac Dev is deployed + running; the phone is on an OLD build.

### What landed this session (all gated: desktop 578/0 · mobile 975/0)
1. **The shared vault EXPORT engine** — `VaultStamp` (the note contract) + `VaultWriter`
   (assess→commit) + the Mac on it + the phone rebuilt on it (photos/audio) + **the iOS folder
   picker, the front door the publish stack never had** (`setVault` had zero callers ⇒ it had never
   run on any device).
2. **The unrated-note model** — *the rating is CONSENT.* Unrated notes now play, show photos,
   karaoke, copy, flash on search; they don't process, export, or join connections (either
   direction). `polishNow` rates the note; "All notes" export removed and pinned rated-only.
3. **ONE shared ASR tail** (`ASRPostProcess`) — the twin was the ORDER, not the engine.
4. **The Mac's transcription Language setting + cross-device sync** (`ASRLanguageMode`,
   `LanguageSyncCore`) — it had been permanently English-tuned.
5. Fixes: derived titles cut on a word boundary, un-rating actually un-rates, synced notes show
   their duration again.
6. **The 🔌 plugin menu** — 10 wireframes + per-feature thinking, `mocks/obsidian-plugin-menu.html`
   (PROPOSAL) + Artifact; Tuur's verdicts + the v1 rec are in the 🔌 block below.

### ✅ CLOSED 2026-08-11 (device session, phone builds 133 → 134)
- **Language sync: CONFIRMED WORKING BOTH WAYS on device** (Tuur: "it works from Mac to phone and
  from phone to Mac"). The gate is closed. It needed build 133 first — the old phone predated the
  stamping code and `LanguageSyncCore` correctly refuses to push an unstamped default.
- **⭐ THE PHONE DOESN'T EXPORT — DECIDED + BUILT (`a8daa59`, build 134).** Tuur on seeing the
  toggle: *"the phone can't even export anything to Obsidian so it shouldn't even be there. Only
  the iPad and the Mac can do that after they processed the note… we just want the phone to be
  able to READ the vault so its good to pick a folder but that is about it."* So:
  (1) the **folder picker stays on every device** — the security-scoped bookmark is the
  prerequisite for the phone READING the vault (the pull-for-search direction), and the footer now
  states what THIS device does with the folder; (2) the **export controls only render where the
  device can PROCESS** (`PolishCenter.isAvailable`, the same gate the "Polish on this iPad" section
  uses — export appears where a polished note can be produced); (3) **`shouldPublish` now requires
  a PROCESSED note**, not merely a rated one — the deeper half of his point, since otherwise the
  iPad would publish raw rambles. This finally makes both apps agree: the Mac's primary button has
  always read "Process" until an enhancement exists and only then "Export to Obsidian".
  Gate: mobile 976/0 (+1 pinning "unprocessed never publishes").
  ⚠️ **Still true and worth knowing:** nothing on iOS auto-publishes — the only trigger is the
  Settings "Export now" button. Wiring automatic publish (on save / on launch) is an open chunk;
  manual was kept deliberately while the engine is unproven against a real vault.

### 🔴 OPEN BUG (Tuur, 2026-08-12) — the iPad CANNOT process a note; it errors

Reported at the end of the session, error text not captured yet. **This blocks the current `now`
node.** As of `a8daa59` (merged to main today) `PublishCoordinator.shouldPublish` requires a
PROCESSED note, and the export controls only render where `PolishCenter.isAvailable` — so if the
iPad can't polish, **the iPad can't export, and iOS export is dead end-to-end**. SharedExport's
"first real device round" can't even start until this is answered.

**What the surface can be saying** — the string comes from one of exactly two places, and they mean
different things:
- `PolishCenter.modelPhase = .failed(...)` (`PolishCenter.swift:267`) — the **4.6 GB Gemma download**
  failed. Settings model card.
- `PolishCenter.phases[id] = .failed(...)` (`PolishCenter.swift:185`) — the **polish run** failed.
  `PolishEngineError.notLoaded` prints "Polish model not loaded."; anything else is MLX's own text.

**Hypothesis worth checking, NOT a claim:** the Mac segfaulted the same day inside
`mlx::core::Compiled::eval_gpu` → `setComputePipelineState` (`Skrift Dev-2026-08-12-112805.ips`,
EXC_BAD_ACCESS). `MLXPolishEngine` is documented as a 1:1 port of the desktop stack — same
mlx-swift-lm pin, same Gemma repo — so a shared MLX/Metal fault is plausible. Two devices, one
suspect. Don't assume it; the error string discriminates.

**Also in frame:** `MLXPolishEngine` frees the ~4.6 GB container on any memory warning
(`init`'s observer) and reloads on the next polish — worth knowing if the failure is intermittent
or size-dependent rather than immediate.

### ✅ DIAGNOSED 2026-08-12 from the iPad's own trace — and my first two theories were BOTH wrong

Pulled `Documents/devlog.txt` off the iPad (build 132, `com.skrift.mobile.dev`). The error, three
times (07-23, 07-24, 07-25):

```
polish failed for <id>: Key language_model.model.layers.24.self_attn.k_proj.weight
not found in Gemma4Model.Gemma4TextModel.Gemma4TextModelInner.Gemma4DecoderLayer.Gemma4Attention.Linear
```

**Polish has NEVER once succeeded on that iPad** — `wrote enhancement` appears **0 times** in the
whole log.

**WRONG THEORY 1 — "the download timed out and left a partial model."** There IS a
`polish model download failed: The request timed out.` at 15:36 on 07-23, which made this look
obvious. But the on-disk cache is **complete and byte-exact**: `model-00001-of-00002.safetensors` =
4,906,172,928 B and `model-00002-of-00002.safetensors` = 3,974,804,036 B, matching the HF API
exactly. (`devicectl` prints those as "4,57 GB"/"3,7 GB" because it reports **GiB** — that near-miss
against the 8.88 GB `total_size` is what made a complete download look 0.6 GB short. Convert before
concluding.)

**WRONG THEORY 2 — "`isModelOnDisk`'s 500 MB floor false-positives a partial download, and the
Settings card has no way out of `.downloaded`."** Both observations are TRUE
(`MLXPolishEngine.swift:60`, `PolishSettingsView.swift:108`) and both are worth fixing on their own
merits — but neither is this bug, and fixing them would have changed nothing. Do not let them get
recorded as the fix.

**THE ACTUAL FINDING.** The key it dies on **does not exist in the model**. From the repo's own
`model.safetensors.index.json`: `language_model` has **42 layers (0–41)**; exactly **24 of them have
`k_proj`** and **18 do not — layers 24–41**. That is Gemma 3n/4's **KV-shared** tail: the later
layers reuse K/V from earlier ones instead of carrying their own projections. It fails at **layer
24 — the first shared layer** — i.e. it loads the whole normal stack and dies the instant it meets
KV-sharing.

**So it is library-side, not ours.** We have **zero** `k_proj`/KV code (`grep` across
`Skrift_Native/` = no hits); the load is entirely mlx-swift-lm's. Both apps resolve the SAME
versions — `mlx-swift-lm a47894a1e7e9`, `mlx-swift dc43e62d 0.31.4` — and BOTH default to
`mlx-community/gemma-4-e4b-it-8bit` (`Skrift Dev` + `Skrift` `user_settings.json` confirm it).

**THE OPEN QUESTION, and the next step:** the Mac is on the same library, same pin, same model — so
either the Mac's polish is silently broken on this model too, or the library's Gemma4 path diverges
by platform. **Cheapest possible test: one Mac `-runfile` run and read whether the enhancement
lands.** That splits it in a single command and costs nothing. If the Mac fails the same way, this
is a straight dependency bump (mlx-swift-lm past a47894a1) plus a device re-test; if the Mac
succeeds, it's platform-specific and belongs upstream.

⚠️ Rebuilding the phone/iPad app alone will NOT fix this: build 132 is from 2026-07-24, contemporary
with the failures, and nothing in our polish path has changed since.

### ✅ ANSWERED 2026-08-12 — the Mac works, the iPad doesn't, on IDENTICAL everything

Both halves of the deciding test ran.

**Mac (`-runfile` on `test-fixtures/Hotel Du Vin.m4a`): full pipeline SUCCEEDED.** Real Gemma
output — title, summary, name-linked sanitise, compiled note. **Zero** `k_proj`/not-found hits.

**iPad (fresh b139, built from current main, Tuur tapped Polish 13:27:01): FAILED IDENTICALLY.**
`Key language_model.model.layers.24.self_attn.v_proj.weight not found` — same layer 24, the same
KV-shared boundary, just the other projection of the pair.

b139 was built as a CONTROL and its resolved graph was checked, not assumed:
`mlx-swift 0.31.4` + `mlx-swift-lm a47894a1e7e9` — **byte-identical to what the Mac runs.** Same
model repo (`mlx-community/gemma-4-e4b-it-8bit`, confirmed in both `user_settings.json`). Same
first-party code (we own no `k_proj`/KV source at all).

**⇒ FIRST VERDICT — "platform-specific inside mlx-swift-lm" — WAS WRONG.** It held for about ten
minutes and is recorded here only so nobody re-derives it. The real cause is one line lower.

### ⭐ ROOT CAUSE — THE MODEL IS THE ONE UNPINNED DEPENDENCY IN THIS REPO

The two devices are running **structurally different revisions of the same model repo**:

| revision | cached on | downloaded | layers carrying `k_proj` | loads at pin `a47894a1` |
|---|---|---|---|---|
| `d8a1725bb38924b597ed9a3b9f29b4e582187e81` | **Mac** | 2026-06-07 | **42 of 42** | ✅ works |
| `4255b21bd9a9d3fc807ef7abd80373f5e3a52a73` | **iPad** (= HF `main` today) | 2026-07-23 | **24 of 42** (18 KV-shared) | ❌ fails |

`mlx-community` **re-uploaded `gemma-4-e4b-it-8bit` with a KV-shared architecture** between those two
dates. Both apps ask for the repo with **no revision** — `ModelConfiguration(id: modelRepo)`, and
`MLXLMCommon.ModelConfiguration` defaults `revision:` to **`"main"`** — so each device permanently
inherited whatever `main` happened to be on its download day. The Mac isn't "working"; it is running
a June cache.

🔴 **THE MAC IS ONE CACHE-CLEAR FROM THE SAME BUG.** Delete its HF cache, or run Skrift on a fresh
Mac, and it re-fetches `main` = `4255b21b` and dies exactly like the iPad. The only working polisher
in the product is protected by nothing but a stale directory.

**THE FIX (recommended, small): pin the model revision**, the same way every SPM dep here is pinned.
`ModelConfiguration(id:revision:)` already takes it; `PolishPrompts.defaultModelRepo` becomes a
repo + revision pair used by both `EnhancementService` (Mac) and `MLXPolishEngine` (iPad). Pin to
`d8a1725b` — the revision the Mac PROVES loads with our library pin. Cost: the iPad re-downloads
~8 GB once. Doctrine match: `project.yml` pins FluidAudio, ZIPFoundation, mlx-swift-lm,
swift-transformers and swift-jinja by exact revision — *"upgrade deliberately, with a device round —
never float a branch."* The model was the one thing floating.

### ✅ FIXED + MAC-VERIFIED 2026-08-12 (`b8f8540`) — pinned model, raised mlx floor

Both halves shipped, and the Mac proves it: the same `-runfile` that could not load the new upload
now polishes it cleanly (real title/summary/sanitise, zero `k_proj`).

1. **`PolishPrompts.defaultModelRevision`** pins the repo to `4255b21b`, via
   `PolishPrompts.revision(for:)` so the pin applies ONLY to `defaultModelRepo` — the Mac's model is
   a user-editable Settings field and asking another repo for this sha would request a commit that
   doesn't exist there. Anything else tracks `main`.
2. **mlx-swift-lm `a47894a1` → `e6e3de75`** (2026-07-21, +2 days) — where `Gemma4Text` made
   `kProj`/`vProj` OPTIONAL for KV-shared layers. **A FLOOR, not a preference.** It also
   `sanitize`s the redundant tensors out of the OLD upload, so it reads either revision.
   ⚠️ Needs **mlx-swift 0.31.6**: 0.31.4 lacks `DType.greatestFiniteMagnitudeArray` and the library
   won't compile. `Package.resolved` lives in the gitignored `.xcodeproj`, so delete
   `build/SourcePackages` to force a re-resolve or you keep building the stale 0.31.4.

**Cache cleaned: 30 GB → 10 GB.** Dropped the bake-off models and the now-dead `d8a1725b` revision
(unshared blobs only, resolving symlinks so shared config/tokenizer blobs survived). Polish
re-verified AFTER the delete — which also proves the pin end to end, since the June revision the Mac
used to depend on is gone.

### ✅ CLOSED 2026-08-12 — THE iPAD POLISHES. Three walls, each hiding the next

`16:34:36  polish: wrote enhancement for E3E0CF97-… (copyedit 2956 chars)` — on b142, with the
SAME 8.88 GB model the Mac runs, so the "a note reads identically whichever device polished it"
contract survives intact. That was Tuur's own objection to the cheap fix and it decided the route:
raising the ceiling keeps one model, dropping the iPad to 4-bit would have split the outputs.

| wall | what it actually was | fix |
|---|---|---|
| `k_proj not found` at layer 24 | the model repo is UNPINNED; upstream re-uploaded it KV-shared and each device kept whatever `main` was on its download day | pin `defaultModelRevision` + raise the mlx-swift-lm floor to `e6e3de75` (needs mlx-swift 0.31.6) |
| hard crash, no message at all | mlx-swift's default error handler calls `fatalError`, bypassing `PolishCenter`'s catch | scope `MLX.withErrorHandler`, throw `PolishEngineError.mlx(String)` |
| `[malloc] Unable to allocate 2818572288 bytes` | iOS per-app memory ceiling vs an 8.88 GB model | `com.apple.developer.kernel.increased-memory-limit` (needs ONE Xcode Signing & Capabilities visit — `xcodebuild` cannot add a capability) |

**The middle fix paid for itself immediately.** Wall 3 was invisible until MLX errors stopped being
fatal — the crash carried no message, and the `.ips` doesn't record one either. Two rounds were
spent on wall 1's corpse because of it.

⚠️ **Prod promotion owes the same Xcode visit** for `com.skrift.mobile` (Release), exactly like the
App Groups precedent. The Debug id is done.

**Also corrected:** the model card said "4.6 GB" and the footnote "~5 GB free" for a model that is
8.88 GB — stale text from when it was half the size. Both now read 8.9 GB / ~9 GB.

**Dead theories, recorded so nobody re-derives them:** it was never platform-specific (the Mac was
just running a June cache), never a partial download (byte-exact against the HF API — `devicectl`
prints GiB, which made a complete download look 0.6 GB short), and never corrupt local weights (the
clean re-download failed the same way). The unpinned model was the whole story.

### 🔴 (superseded) STILL OPEN on the iPad after b140 — it now CRASHES instead of erroring

Tuur tapped Polish on b140 (the fix build). Hard crash. `SkriftMobile-2026-08-12-153159.ips`:

```
EXC_BREAKPOINT / SIGTRAP
LLMModelFactory._load → loadWeights(…perLayerQuantization:) → eval → mlx_eval
  → _mlx_error → ErrorHandler.dispatch → _assertionFailure
```

**Read that carefully — it is NOT the old bug and NOT out-of-memory.** MLX's C++ layer raised an
error during weight load and **mlx-swift's default error handler calls `fatalError`**, so it traps
instead of throwing. That is why this reads as a crash where the old `k_proj` failure read as a
tidy "polish failed" line: that one was caught Swift, this one bypasses `PolishCenter`'s catch
entirely. The devlog has NO `polish failed` entry — it just stops, which is the signature.

**Nothing re-downloaded.** The iPad's cache is untouched, still dated 23/07 — the pinned revision
is what it already had, so this is purely a load failure.

⭐ **PRIME SUSPECT: the iPad's cached weights are CORRUPT.** Its blobs carry mixed timestamps —
the 3.7 GB shard at **15:15**, the 4.57 GB shard at **17:11** — and the devlog for that same day
reads `15:36 polish model download failed: The request timed out.` then the first `k_proj` failure
at **17:11:31**, the same minute the big shard was last written. So that shard came from an
interrupted-then-resumed fetch. Sizes match the HF API exactly, **but a resumed download can be
right-length and wrong-bytes.** The Mac's FRESHLY downloaded copy of the very same revision
(`4255b21b`) loads and polishes fine — same library, same sha, different outcome, which is what
you would expect from a bad local copy rather than a code bug.

**THE TEST: make the iPad re-download the model clean.** There is no way to do that today — which
is the gap flagged earlier in this entry: `PolishSettingsView` offers a button only in
`.notDownloaded` and `.failed`; `.downloaded` renders a dead "Downloaded ✓" label. A bad cache is
terminal from the UI. Options:
- **(A) Add "Remove model" to the Settings card (recommended).** Small, permanently useful, makes
  this self-serviceable, and closes the dead-end that has now cost two rounds. Pair it with the
  completeness check (also still unbuilt) so a partial fetch can't report Downloaded ✓ again.
- **(B) Uninstall/reinstall the app.** Wipes the container: notes are safe (CloudKit) but the
  LOCAL audiobooks go with it — `Documents/audiobooks` holds The Odyssey at 738 MB plus its
  transcript and alignment. Faster, but it destroys data to run a test.

⚠️ **Worth fixing regardless of this bug: an MLX error should not kill the app.** `MLX.withErrorHandler`
(and `withError`, which converts them to Swift `throws`) exist precisely for this. Wrapping the load
would turn every future MLX fault into the "polish failed: …" line `PolishCenter` already knows how
to show — and would have handed us this error message instead of a stack.

### 🔬 MODEL BAKE-OFF 2026-08-12 — measured, and the answer is DON'T SWITCH

Same transcript through each, on the Mac, via `-runfile … -transcript` (fixed text ⇒ no ASR
variance). Two samples: a deliberately messy EN/NL think-aloud, and the `Hotel Du Vin` fixture.

| model | size | verdict |
|---|---|---|
| `gemma-4-e4b-it-8bit` (current) | 8.88 GB | baseline |
| `gemma-4-12B-it-OptiQ-4bit` | 8.96 GB | **a trade, not a win** |
| `gemma-4-E4B-it-qat-mobile` | 3.46 GB | ❌ **CANNOT LOAD** |

**The 3.46 GB mobile QAT build does not work with our stack** — `unhandledKeys(... per_layer_projection,
keys: [input_activation_scale, output_activation_scale, weight_scale])`. It ships activation-scale
quantization mlx-swift-lm doesn't read. That kills the obvious "shrink the iPad download" idea; note
it before anyone re-proposes it.

**12B-4bit vs our 8-bit, at the SAME footprint:** 12B repaired a broken construction the 8-bit
fumbled ("But should it?" vs *"But does it should?"*) and wrote a title in Tuur's own words rather
than a report heading. But it LOST the orthography the 8-bit got right — left "uberhaupt"
un-umlauted where 8-bit wrote "überhaupt", and lowercased "the mac". On the short clean sample they
were indistinguishable (comma placement, title casing). **One sample each — thin evidence, mixed
direction, so switching isn't justified**, and it would break the "a note reads identically whichever
device polished it" contract for an unproven gain. Revisit with a bigger, messier corpus if it ever
matters.

**THE ALTERNATIVE CONSIDERED AT THE TIME: bump `mlx-swift-lm` past `a47894a1`** so it can load the NEW KV-shared weights.
Avoids the iPad re-download and keeps us current, but risks the one working polisher, needs upstream
archaeology, and needs a device round on both. Candidates seen after our pin: `b207f60d` (Gemma 3n
Boolean attention masks, 07-29), `83f3ef6d` (Gemma4 chunk-invariance, 07-31) — neither obviously
about KV-shared loading.

⚠️ **Consequence while unfixed:** the iPad cannot polish ⇒ cannot export (`shouldPublish` requires a
processed note since `a8daa59`). The Mac is the only device that can put a note in the vault.

⏸ **PARKED behind fleet-ledger (Tuur, 2026-08-12): "fleet ledger takes priority."** Not only a
scheduling call — a `~/Hackerman/fleet-ledger` session is batch-running `Skrift Dev -runfile` over an
audio corpus, and `-runfile` IS a second Skrift instance, which races the shared SwiftData store
(the standing rule in CLAUDE.md). So the deciding Mac test cannot be run until that batch is done
anyway. **Check for a running `-runfile` before starting it.**

### ⚠️ OWED — Tuur's device gates (none of these are known bugs; they're unverified)
- **Mac sync only runs at launch + `didBecomeActive`** (the v3 "no note dies unseen" design —
  background heartbeats were retired). If a phone note hasn't appeared, CLICK the Mac window. This
  confused a live test today; worth remembering before diagnosing.
- **First real export round:** point the iOS picker at a THROWAWAY folder first (its maiden run),
  then `0 Inbox/Skrift`. Legacy pre-stamp notes will report `blockedLegacy` BY DESIGN.
- The unrated-note eyeball (play/photos/karaoke) — Tuur confirmed it works; the export + language
  rounds are what's left.

### ▶️ NEXT, in the order I'd take them
1. **Bump CFBundleVersion + build/install the phone** — unblocks the language round-trip AND the
   iOS export front door. Cheapest unblock of two owed gates at once.
2. **🌙 The monthly-digest spike** — fully planned (section 🌙): `-digest <YYYY-MM>` harness, run on
   his real July, gate = he reads it. The bare scaffold must already be a decent digest.
3. **Plugin v1 bundle** (his picks + my rec): inbox + sync doctor + listen — all vault-files-only,
   mobile-capable, and the inbox card retires the return-path chunk.
4. Parked, needs design chats: book pages in-app (roadmap i16, mock-first), timeline-in-Review
   (open question). *(The twinned `SignificanceCircles` views came off this list — un-twinned
   2026-08-12, see the ✅ section above.)*

---

## ✅ BUILT 2026-07-26 (`a262f02`) — THE UNRATED-NOTE MODEL. Tuur's device eyeball owed.

**THE MODEL (locked over 5 rounds, now implemented): the rating is CONSENT — until you've judged a
note, Skrift spends nothing on it and shows it nowhere but back to you.** What differs is only what
SPENDS (process, export) or CLAIMS (the idea graph); everything that is just reading your own note
back is unconditional. Tuur's own test for the boundary: *"this is not one of those differences."*
Any user act implying judgment BECOMES the rating (polish floors to 0.1; a backlink already held a
note from fading). ALL BUILT — desktop 561/0, mobile 975/0, render re-proved, Dev deployed.

**DECIDED — unrated notes DON'T get:** Process (the rating IS the flag) · Connections (stays
capability-off; the Mac-indexes-PipelineFiles-only asymmetry stays as-is) · Export (+ the
include-audio toggle stays hidden).
**DECIDED — unrated notes DO get:** the player, **playing from the synced copy** — materialise the
audio blob on open to a cache path (`Application Support/UnratedAudio/<memoID>.<ext>`, cleaned when
the note pipelines/trashes), hand it to the projection, delete `NoteCapabilities.transport`.
Verify: `-snapshot-unrated` docks the player on both sides.
**CONFIRMED NOT FORGOTTEN (checked from source):** Mac sidebar search DOES reach quiet memos
(`SidebarView` filters the band via `WayOutRules.matchesSearch`); title/body/tags editing, chips,
importance card all already normal.

**THE FORGOTTEN LIST — ALL SIX DECIDED by Tuur (round 4, 2026-07-26 midday):**
- **A · Photos: "photos should show."** Materialise-on-open via `MemoPhotoMaterializer`, with the
  player chunk. (Was my regression from the projection rebuild.)
- **B · Karaoke: "should work."** Timings blob → projection `wordTimingsJSON`; rides the player.
- **C · Copy verbs: "should for sure work"** — his words for the principle: *"this is one of those
  examples where an unrated note should just be treated the same as normal notes except some
  differences. this is not one of those differences."* Slim ⋯ = Copy transcript · Copy as Markdown;
  Reveal/Open-in-Obsidian stay absent (no file, no export).
- **D · "fix 1":** `PolishCenter.polishNow` FLOORS the rating to 0.1 (MacMemoAuthor precedent) —
  pressing Polish IS a judgment; "polished ⇒ rated" true everywhere. `canPolish` gains no rating
  gate (the button stays offered; using it rates).
- **E · "fix 2":** the "All notes" publish policy option is REMOVED from the phone Settings picker
  — export is rated-only on every device, one rule. (`.all` may stay in code for tests; no UI.)
- **F · Search flash: "should flash."** Pass `searchQuery` through `UnratedNotePane`.

**✅ EDGE CLOSED (round 5): "unrated notes should not join in other notes' connections."** BOTH
directions are NO — no own panel, no appearing as candidates in anyone else's Related. The consent
model covers it fully: Skrift doesn't even mention an unjudged note to your future self.
**Phone chunk this creates:** `JournalIndexService` embeds ALL memos today, so unrated ones DO
appear in Related on phone/iPad — exclude at INDEX time (`significance > 0` joins the corpus;
saves the embedding compute too), drop on the next sweep when a rating returns to 0. The Mac is
already correct (never indexed them). Goes in the unrated build chunk.
**Digest ripple (plan updated):** "top-K by Connections degree" is formally dead for unrated notes
on both apps — unrated notes can enter the digest ONLY via backlinks, and their mentions render as
plain text, never `[[links]]` (no dangling vault links).

---

### Tuur's menu verdicts (voice note, 2026-07-26 morning)

- **1 Listen: "perfect, I like it."** · **4 Doctor: "super cool."** · **6 Record: liked** (answered:
  the MAC APP's own FluidAudio/Parakeet does the transcribing — the plugin is just the button and
  the landing; nothing new lives inside Obsidian). · **8 Search: "very nice."** · **9 Daily: not
  mentioned** (unreviewed).
- **2 Inbox: "smart!"** (round 2, after the plain pitch — verdict upgraded from "don't understand").
- **3 Connections: "perfect for Mac" — ⛔ THE STATIC TIER IS REJECTED** (round 2: "not sure about
  stale data. dont like that"). So: LIVE over localhost to the Mac app's engine+index, Mac-Obsidian
  only; iPad/phone Obsidian simply doesn't get Connections (sandboxes can't reach the app, and
  stale snapshots are declined). No second model inside the plugin, ever.
- **5 Names: liked.** Answered: ONE names DB everywhere already (names.json ↔ NamesRecord over
  CloudKit, LWW union) — the plugin talks to the Mac app, so a person added from Obsidian lands in
  the same DB and syncs to phone/iPad automatically.
- **10 Timeline: concept unclear, visual "super cool"** — re-pitch: pick an idea → every note that
  touches it, laid left→right in time (first mention → now), scrub + play. "How did my thinking
  evolve", as a view.
- **🆕 IDEA (his, #7 spun bigger): BOOK PAGES IN THE APP TOO** — "an overview of all your books…
  that might actually be in Review… that's good everywhere." A per-book page aggregating its quote
  captures (data already on every capture: bookTitle/author/chapter), in the APP (Review/Books) and
  exported as the vault literature note. Candidate roadmap idea; design chat first (mock-first).
- **6 Record → ✅ BUILT 2026-07-26 (`fca5c4f`): ONE transcription tail in `Shared/`** — and the
  premise was PARTLY WRONG, which matters more than the code. **Already shared before this:** the
  engine (FluidAudio/Parakeet v3) and every rule — BPEMerge, AudioRMS, ImageMarkers,
  TranscribingContract, the result/token types. The apps were never running twin engines. **What
  WAS twinned:** the ORCHESTRATION (~35 lines, same order, both services) — the dangerous kind,
  because the order is load-bearing and invisible in a diff (rescore BEFORE markers; phantom guard
  before everything; re-align after the rescore or timings detach). Now `ASRPostProcess.finish`,
  kept FluidAudio-free (neutral RawToken + closures) so it host-tests. Per-app remainder is only
  what genuinely differs: Mac preprocesses (high-pass) + Settings word list; phone tracks
  `TranscriptionActivity` + reads the synced `CustomVocabularyStore`. The phone's PCM book-chunk
  path uses the same tail. Checked, NOT drift: `VocabularyTuning` cbw/minSim exist only on the Mac
  but are `#if DEBUG` env knobs — Release is identical. 8 tests pin the ORDER. Gates: desktop
  569/0, mobile 975/0. **GOTCHA for future fixtures:** `mergeBPETokens` starts a word on a LEADING
  SPACE (not `▁`) — space-less test tokens merge into ONE word (my first draft crashed on it).

- **⚠️ 🔴 FOUND WHILE HOISTING — A REAL TRANSCRIPTION DIVERGENCE, needs Tuur's call.** Confirmed
  from FluidAudio's own source (`AsrTypes.swift`: *"Default `true` preserves PR #264's
  blank-prediction fix on English. Set to `false` for v3 multilingual long-form"*):
  - **Mac:** `AsrManager(config: .default)` ⇒ `melChunkContext = true`, ALWAYS. No setting exists.
  - **Phone/iPad:** `ASRConfig(melChunkContext: !multilingual)` — Settings → Language
    (English/Multilingual, key `transcriptionMultilingual`, default English).
  So with the phone set to **Multilingual**, the SAME audio transcribes down a different path on
  the two devices, and the Mac is permanently English-tuned. This bites whenever the Mac
  transcribes: local +Upload/drag-drop imports, ⋯ Re-transcribe, `-runfile`. For an English/Dutch
  speaker that's a real quality difference, not a cosmetic one. The setting is ALSO per-device
  UserDefaults (unlike custom vocab, which syncs via `VocabularyCloudSync`).
  **✅ FIXED 2026-07-26 (`2c6a958`) — Tuur: "make it sync and add the setting to mac."** Shared
  `ASRLanguageMode` owns the key + the `melChunkContext` derivation + the UI copy (never inline it
  again — that IS how they drifted), plus `ASRLanguageStore` for the phone's Bool + stamp. Syncs on
  the existing `VocabularyRecord` carrier with its **own** stamp (`languageModifiedAt`) so
  word-list and language edits can't clobber each other; the `@Model` type name is unchanged on
  purpose (renaming renames the CloudKit record type). `LanguageSyncCore` = LWW that will NOT push
  a default nobody chose — a fresh Mac would otherwise broadcast "English" and undo the phone's
  Multilingual (that's the test that matters most). Both Settings stamp-on-pick and push; adopting
  a remote value drops the loaded ASR manager so the next transcription rebuilds (the Mac now
  tracks `loadedMultilingual` like the phone always did).
  ⚠️ **An existing test earned its keep:** the Mac's new field as a non-optional `Bool` broke
  `AppSettings` legacy decode — every real install would have failed to load settings. It's `Bool?`
  + effective accessor, the pattern the neighbouring fields document.
  **New harness:** `-snapshot-settings-hosted` (real AppKit, uncapped) — the plain
  `-snapshot-settings` draws Pickers as YELLOW PLACEHOLDERS, the same blindness that hid a
  non-drawing ⋯ chip on 2026-07-25. Verified the control drawn for real. Gates: desktop 578/0,
  mobile 975/0, Dev deployed. **OWED: two-device round-trip** (flip on the phone → Mac adopts) —
  sync-contract change, so that gate is Tuur's.
- **10 Timeline: open design question from Tuur** — "should perhaps exist on mac app too in
  review? not sure." Park for the timeline's design chat: one build, two surfaces (Review + the
  plugin render the same arc)?
- **🆕 IDEA (his): MONTHLY DIGEST — planned below (he liked the model-never-chooses framing);
  plan = "🌙 THE MONTHLY DIGEST" section.**

---

## 🌙 THE MONTHLY DIGEST — the plan (2026-07-26, Tuur: "lets plan it. i like ur way of writing it")

**The bet:** a note that reads like "what July was actually about", written into the vault (and
maybe Review) — where every load-bearing element is REAL and machine-placed, and the local model
only supplies connective prose. His insight is the architecture: *models don't know what's
important — Skrift does.*

**THE ONE RULE (the trust boundary, same class as QuoteProtection):** the model NEVER chooses,
NEVER links, NEVER quotes. Code selects, code builds the skeleton with real `[[links]]` and
byte-verbatim quotes, the model writes ONLY into marked prose slots BETWEEN scaffold blocks.
Slot output that mentions a title/name/quote not present in its slot's inputs is REJECTED
(deterministic re-check, drop to a plain list on failure). Failure mode = boring, never lying.

**1 · SELECTION (pure code, all signals already exist):**
- window: the calendar month, `recordedAt`-based;
- in: every rated note (significance > 0), PLUS unrated notes ONLY via backlinks
  (`MemoLifecycle.backlinkedIDs`) — Connections degree is dead for unrated notes by the round-5
  decision (they're not in any index), and their digest mentions render as PLAIN TEXT, never
  `[[links]]` (an unrated note is never exported ⇒ a link would dangle in the vault);
- flag: first-mentions (a note whose arc has no earlier member — `EmbeddingIndex` date rail);
- rank inside sections by significance, then connection degree; hard cap (~12 notes, "Show all"
  beneath) — a digest that lists everything is a list, not a digest.

**2 · SCAFFOLD (pure code):** frontmatter (stamped — it's an exported note like any other; `type:
digest` + `month:`) → headline stats line (N notes · M rated · places · books touched) → clusters
by Connections adjacency (fallback: by week) → per cluster: the notes as `[[real links]]` + their
existing `MemoGist`/summary one-liners + at most one VERBATIM quote block per book capture
(byte-copied, attribution from C2 fields) → `<!--prose:cluster-N-->` slots.

**3 · WRITING (local Gemma, MLX — the Mac's existing enhancement stack):** per-slot prompt =
ONLY that cluster's gists/links/dates + house style; 2–3 sentences per slot + one intro slot;
temperature low. Per-slot generation keeps context small and makes the reject-check local.

**4 · SPIKE (the "is it shit?" test, an afternoon):** DEBUG harness `-digest <YYYY-MM>` (RunFile
idiom): runs selection+scaffold+writing headless on the REAL store, prints the markdown; run on
Tuur's actual July. GATE = he reads it. Judge: does the prose ADD anything over the bare scaffold?
(The scaffold alone must already be a decent digest — that's the floor, and it ships even if the
model verdict is "kind of shit".)

**5 · IF GO:** where it runs = the Mac (idle, monthly, first open after month-end — same
launch-gated pattern as the lifecycle sweep); output = `Digests/2026-07.md` in the picked folder
via the ENGINE (stamped ⇒ editable/movable like any note, the doctor sees it); Review surface +
iPad/on-demand = later chats.

**OPEN (Tuur, when picking it up):** cadence (monthly only? weekly too?); should the digest note
also land IN the app's Review as a pinned month card, or vault-only at first; does an
all-quiet month (nothing rated) produce a digest or silence (my rec: silence — no-bad-information
doctrine).

---

---

## 🖥️ NEXT CHUNK — `includeAudioInExport` needs to SYNC before the iPad can show it

Tuur, 2026-07-25: *"the include audio should also be part of the ipad."* Agreed, but it is a
**sync-contract change, not a UI addition**, and the reason is the whole chunk:
- `includeAudioInExport` is **Mac-only** — on `PipelineFile`, read only by `VaultExporter`, absent
  from `Memo`, never synced.
- The phone's `ObsidianPublisher` **copies no audio at all** (markdown only), so the toggle cannot
  govern the iPad's own publish — there's nothing there to govern.
- Therefore on the iPad it means *"when the Mac exports this, bring the audio"* → it needs a `Memo`
  property + CloudKit ingest/update/write-back + the Mac's copy driven by the synced value under LWW.

**Build order:** `Memo.includeAudioInExport` (default true, matching `PipelineFile`) → ingest +
update + Mac→phone mirror → the Mac's value follows the synced one (LWW by the existing stamp) →
THEN the iPad's switch appears in its note header, in the same place the Mac's now sits (after
importance). **The iPad's switch stays HIDDEN until the field it writes actually reaches the Mac** —
a visible toggle that doesn't change what happens at export would be a lying control.
Per CLAUDE.md the sync contract is the spine, so this gets its own verification round (both suites +
a real two-device round-trip), not a ride-along.

---

## ✅ DONE 2026-07-25 — unrated notes open as NORMAL notes + the importance drift (`1bfed5a`)

Round 1 of the pane change moved the modal's CONTENT into the pane but kept the **peek's anatomy**
("Not processed" header, amber chip, sentence-in-a-box, bare body). Tuur: *"this note should just be
shown as a normal note same way the ipad does. not this weird way."* The pane now renders the same
anatomy and order as `NoteProperties` — title · ONE chips row · importance card · amber lifecycle line
· body — so an unrated note differs from a pipelined one ONLY in what it genuinely can't offer
(no Process/Export/Connections; it isn't in the pipeline). The Journal river keeps the peek via
`presentation: .sheet`.

**THE IMPORTANCE DRIFT (Tuur: "explain the importance thing?").** The two apps carry SEPARATE
`SignificanceCircles` views, and they had diverged:
| | iPad | Mac (before) |
|---|---|---|
| container | a **card** (`skSurface`, card radius) | none |
| label | "Importance" | "importance" |
| after the tiers | divider + a **status line**: *"Not rated — the Mac will leave it alone"* / *"Rated — the Mac will process this"* / *"Rated for a refine pass"* | **nothing** |
The Mac never said what a rating DOES — the whole point of the control. **And my own mock made it
worse**: it asserted the iPad's block was bare and dropped the Mac's card on that basis. That is the
`feedback_mock_as_is_from_source` rule broken in exactly the way it warns about — I drew one element
from assumption instead of source. The Mac now has the card, the capital label and the line;
`syncCopy` moved phone → `Shared/Model/SignificanceScale.swift` so the sentence exists once.
Gates: desktop 510/0 · mobile 970/0.

---

## ✅ DONE 2026-07-25 — two iPad-parity fixes from Tuur's side-by-side screenshots

**🎨 Panel colours, in SHARED code (`55bded8`).** *"match the colors of the panels on mac to what the
ipad has… ipad is better. also match those in shared code."* Root cause was exactly the drift class
`Palette` exists to prevent: the Mac painted panels with a **Mac-only** `Theme.sidebar` (#15171f dark)
while the iPad's list column + Connections sheet use `skSurface` → the SHARED `Palette.surface`
(#181a23). Two tokens, one semantic, tuned apart. **`Theme.sidebar` is DELETED** — notes list,
Connections inspector and docked player all resolve `Palette.surface` now, so they can't diverge again
by construction. Verified through ONE pipeline: panel #15171c → #17191f, note paper unchanged at
#111216. **DURABLE: the HOSTED render is NOT colour-exact** (lifts ~2 points); `-snapshot`'s
ImageRenderer path is the exact one, so prefer token identity as the guarantee.

**🖱️ An unrated note OPENS instead of popping a modal (`876e72d`).** *"it should copy the ipad where it
just opens it."* The constraint that made it a modal: the pane renders a `PipelineFile` and an unrated
memo has none — **the rating is what pipelines a memo**. NOT closed by ingesting on click (that would
quietly pipeline anything you glanced at and break "rating IS the flag"); instead `AppModel.paneMemoID`
+ a `.pane` presentation on `UnpipelinedMemoSheet` render it read-only in place. Rating from the pane
hands over to the real row. Dead `bandPeek` sheet deleted. The Journal river keeps its modal (a glance
from another surface). **Honesty fix found while wiring:** the amber chip and the peek sentence are
CLAIMS about fading and both read a `backlinked` set the pane couldn't pass — a linked note would have
read as fading; `load()` now derives it when absent.

---

## ✅ DONE 2026-07-25 — the lighter Mac note header (`0d22317`, signed mock v2)

Mock → Tuur's sign-off ("sickk. i like it!") → built, in one session. `mocks/mac-note-header.html`
(Artifact `c4ed5d95`). The four-row properties table and its card are gone: **title = one editable
line** with the suggested-vs-recording choice as two quiet words that replace it on click · **ONE
chips row** flowing into the tags (date · place · weather · daypart · source · duration + the
conditional url/reminder/lock chips) via a new `TagEditor(leadingChips:)` · importance keeps its
circles, loses the card · include-audio stays a **real switch, small** (Tuur's one correction to v1,
which had moved it into the ⋯ — right call: it's a decision you flip while looking at the note).
`author` DELETED not moved (it was always the Settings author ⇒ the same name on every note; the
export writes it to frontmatter anyway). **Breadcrumb removed** — it said "<source> · <date>", both
now chips, and the iPad never had one; it survives ONLY on the locked path, where the header doesn't
render and nothing else names the note. The source chip draws `file.sourceSymbol` — the same
descriptor as the sidebar row, so glyph and label can't disagree.
Gates: desktop unit 510/0 · rendered dark AND light and read with vision · all five ImageRenderer
snapshot modes still produce. **✅ TUUR-CONFIRMED IN DEV 2026-08-12** — "i had already checked that,
it all looked good": the new header, the docked player and the shared panel colours are all signed
off by eye. Nothing owed on this trio.

---

## ⏸ DEFERRED (Tuur, 2026-07-25) — Connections TIGHTNESS lens · waits on the Obsidian vault

Tuur: *"allow me to change the related floor. perhaps i wanna look for super related ones. but the
ux needs to be good to do that"* → then **"do this once we connect my Obsidian vault."** Right call:
the vault changes the very score distribution the steps calibrate from, so tuning now gets thrown away.

**DESIGN AGREED — don't re-litigate when this resumes.** NOT a numeric slider in Settings, because
(a) a cosine value is meaningless to a human, (b) a global threshold is a hidden mode — set it tight
once and months later the panel looks broken, which is the "incomplete must not look complete" rule
violated through a settings UI, and (c) the right number drifts as the corpus grows
(`EmbeddingIndex.swift:19` already says to re-run the histogram).

Instead: a **named 3-step lens in the panel header**, beside the Date⇄Closest pill and never merged
into it (Date/Closest = *ordering*; tightness = *membership*). Steps derived from the measured
random-pair noise distribution, not invented:

| step | floor | promise |
|---|---|---|
| **Related** | 0.45 (≈p90 of noise) | today's behaviour — shares an idea |
| **Close** | ~0.60 | strong overlap |
| **Tight** | ~0.80 (≈p99) | nearly the same note |

Four properties that make it good rather than fiddly:
1. **Live counts on the control** (`Close · 5`) — the trade is visible before you commit, and a
   tightened panel can never masquerade as an empty library.
2. **Its own empty state:** "Nothing this close — 12 at Related" + one tap back. NEVER "No
   connections yet" — that lies about the library.
3. **No looser step than 0.45** — below it sits the *median of random pairs*; it would fill the panel
   with noise and make the feature look stupid.
4. **FIRST MENTION becomes scoped** — raising the floor changes which note is oldest-qualifying, and
   that flag is a claim, so at tighter steps it must read as "first mention at this tightness".

**Build order when the vault lands:** (1) vault connected → (2) run Settings → `Log score histogram
(dev)` on the REAL corpus, pull `devlog.txt`, set the two new floors from those percentiles (the app
does the scanning; only the percentile summary leaves the device — the vault-privacy boundary holds)
→ (3) mock the header control (new UI = mock-first) → (4) build. Roadmap idea **i13**, hangs off P8.

---

## 🧵 DONE — View thread retired from the iPad (2026-07-25, `8708675`)

Tuur: *"isn't it the same as connections looking at date?"* — **it is.** Same query, same 0.45 floor,
same oldest-first order, same first mention; the rail additionally marks THIS NOTE and flags CLOSEST
MATCH, and shows 7 until "Show all". The sheet predated the panel; the iPad inherited both when it
copied the Mac's anatomy. Removed all three regular-width surfaces: the panel's `threadCTA`, the ⋯
item, and **a second, older copy in the `showActions` dialog that had drifted to its own
capitalisation** ("View Thread" / "Print Card" — now reading from `NoteMenuItem`).
**KEPT on purpose:** the COMPACT Related footer card's CTA + `ThreadView` itself — that card lists ≤4
rows with NO Date rail, so on the phone the sheet is the only way to see an arc at all; deleting it
there removes a capability, not a duplicate. Net: ONE arc surface per platform (Mac + iPad = the rail,
phone = the sheet), zero duplication. Gate: mobile build + unit 971/0.

---

## 🖥️ ROUND 2 — Connections became a floating INSPECTOR on the Mac (2026-07-25, `3f34bed` + `6185055`)

Tuur after living with both: **"it does seem better on the ipad, the way the connections pop up."**
Question round → 4 verdicts, built exactly, **no re-litigating**:
1. **Slides in OVER the note's trailing edge** (an `.overlay`, no longer an HStack sibling) with a
   `.move(edge:.trailing)` transition + shadow. It also had **NO animation at all** before — that was
   half of why the iPad's felt better. Now on the house spring.
2. **STAYS open across notes** and re-queries (keeps `@AppStorage`) — a Mac inspector you leave up,
   NOT the iPad's per-note sheet.
3. **Starts BELOW the toolbar** so the bar + its hairline stay unbroken and transport is never covered.
4. **The notes list keeps its real HSplitView column** — a sidebar is structure, an inspector is a
   visitor (asymmetric on purpose).

**⚠️ THE CATCH, and the lesson:** floating over an 820pt column in a 952pt area hid **214pt — a
quarter of every line, cut mid-word**. "Never moves" + "never hides text" are incompatible once
`column + 2×panel > width`. Tuur's call: **ADAPTIVE** → new `NoteMeasure` (pure, unit-tested):
identical-to-closed when the window can afford it (note area ≥1380 ⇒ truly never moves), else the
column narrows into the free region. A 1pt sweep test 400→2400 asserts the column NEVER crosses the
panel edge — and it caught a second bug before it shipped: the scene has no `minWidth`, so a
dragged-narrow window put text back under glass; there the 320pt floor yields.

**TWO DURABLE VERIFICATION LESSONS (this round cost nothing because the harness caught both):**
- **`glassEffect` and `Menu` are SNAPSHOT-BLIND under `ImageRenderer`.** The old floating toolbar
  rendered as an EMPTY capsule; a `Menu` renders as a yellow placeholder. New
  **`-snapshot-inspector`** is HOSTED (real `NSHostingView`) — it draws Menus for real AND can lay out
  the `scrollable: true` live panel. It immediately caught that **the ⋯ chip wasn't drawing at all**
  (on macOS a `Menu` label's background never draws — the chip must wrap the MENU, not its label).
- **A layout consequence you can't see is a layout consequence you'll ship.** The occlusion was
  invisible to reasoning and to the plain-ImageRenderer path; one hosted render made it obvious.

Gates: desktop build green · **desktop unit 510/0** · `-snapshot-inspector` re-rendered, full note
intact. Wide-window "never moves" is proven **by unit test** (layout identical to closed), not by eye.
**OWED:** Tuur's live eyeball — specifically (a) the spring on open/close, (b) whether the column
re-wrapping as it narrows looks janky mid-animation at normal widths, (c) the ⋯ chip.

---

## 🖥️ ROUND 1 — the "chrome that belongs" mirrored to the MAC note view (2026-07-25, `d86072b`)

**✅ BOTH EDITS LANDED. Gates green: desktop build + unit suite 500/0 · mobile build green (the
Palette re-source compiles) · `-snapshot` renders pixel-checked in dark AND light × Connections
open AND closed.** Measured, not eyeballed-by-vibe: chip fill `#1e2130` quiet / `#1d1d34`
accent-soft, label `#b9acff` accent / `#8b8b97` quiet, bottom hairline `#27292e` (= white@10% over
`#0f1117`) spanning the full note column edge-to-edge; light twins `#ebebf0` / `#e5e3f7` / `#dedee1`.
Surfaces confirmed as predicted — zero work needed (sidebar `#15171f` vs note `#0f1117`).

**⚠️ OWED — TUUR'S EYEBALL** (Dev is deployed + was launched from `/Applications/Skrift Dev.app`):
1. The whole bar in the real window (I cannot screencapture — Screen Recording isn't granted to the
   shell, hence the `-snapshot` path).
2. **The ⋯ chip specifically is UNVERIFIED**: a `Menu` can't render in `ImageRenderer`
   (`SidebarView.swift:279`), so it draws as a yellow/red placeholder in every snapshot. Its
   `barGlass()` chip is unproven — check it isn't clipped or mis-shaped.
3. Judgement call to confirm: quiet→accent on the summon is *subtle* on the Mac's dark bg (it's the
   iPad treatment byte-for-byte, and that was signed — but the Mac bar is wider, so say if it's too
   quiet here).

**🔎 SIDE FINDING (durable):** the OLD floating bar rendered **EMPTY** under `ImageRenderer` —
`glassEffect` can't draw headlessly, so that toolbar was never actually eyeball-verifiable in a
snapshot. De-floating it made it renderable. Any future `glassEffect` surface is snapshot-blind.

**Shared-code-first done in the same change:** the two tokens the Mac just twinned moved into
`Palette` (`chipFill` ← phone `skElev`, `accentText` ← phone `skAccentText`, identical hexes ⇒ zero
phone pixels changed), and the summon's word is now `RetrievalGate.Copy.summonLabel`, read by BOTH
note surfaces. Palette's header rule updated: a Mac-only token moves to Shared the moment it grows a twin.

---

**What was decided (2026-07-24 question round) and built to — DON'T re-litigate:**
1. **Connections = CHROME ONLY.** Keep it a STANDING collapsible column (the Mac has room — Tuur's own
   2026-07-16 doctrine; NOT the iPad's pop-over sheet). But mirror the chrome: **kill the ◨ twin + the
   count badge, summon it with the WORD "Connections"** (quiet → accent, no count — same meaningless-7
   insight as iPad).
2. **Chrome polish = surfaces + de-float toolbar.**

**Source findings (already read — build straight from these, no re-investigation):**
- Shell = `SkriftDesktop/Features/Shell/RootView.swift`: `HSplitView { SidebarView | NoteDisplayView }`;
  ◧ `sidebarToggle` ALREADY exists (`macSidebarVisible`, ported from iPad).
- **Surfaces are ALREADY present** (likely little/no work): note = `Theme.bg` `#0f1117` (paper), sidebar =
  `Theme.sidebar` `#15171f` (grayer), Connections column ALSO on `Theme.sidebar`, 280 wide, leading
  hairline (`ConnectionsPanel.swift:189-191`). So "surfaces" ≈ done; just confirm the regions read.
- **The two edits, both in `NoteDisplayView.swift` — DONE:**
  a. `connectionsToggle`: `sidebar.right` glyph + count badge → the word capsule, still toggling
     `connectionsVisible` (the standing column) + ⌥⌘C.
  b. `toolbarBar`: floating glass capsule (radius 14, inset 20, shadow) → hairline-edged bar across the
     note column; ◧ + ⋯ in `barGlass` chips (new `View.barGlass` in the desktop `Theme.swift`); Process
     keeps its tinted capsule; transport stays INLINE.
- Connections PANEL header keeps its own count + ✕ collapse (`ConnectionsPanel.swift:194+`) — the count
  critique was about the SUMMON control only, same as what shipped on iPad.
- Reproduce the render gate any time: `"…/Skrift Dev.app/Contents/MacOS/Skrift Dev" -snapshot <png>`
  (add `-snapshot-light` for light; append `-connectionsPanelVisible NO -macSidebarVisible NO` — argv
  defaults DO reach `@AppStorage` — to see the quiet state).

---

## 🎛️ (done) iPad note view: signed "chrome that belongs" BUILT + installed (build 132, 2026-07-24; branch `claude/ipad-app-version-3f9a3a`, NOT on main)

**✅ BUILT + GATED (`3c871ed`, build 132, installed on the iPad — Opus session).** All 8 board steps
landed in one wave; sim BUILD green; **mobile unit suite 971/0 GREEN** (on iPhone 17 Pro); iPad Pro 13"
sim LIVE taps ALL verified (◧ collapse + re-open — pinned, deterministic, focus-mode 900 centre;
Connections summon = sheet over the note, no reflow, player still reachable; ✕ close). Device build
freshness string-checked (connections-summon/close IN, transportDensity GONE, CFBundleVersion 132).
**✅ TUUR DEVICE EYEBALL 2026-07-24: "this looks soo good!!" — the signed design is CONFIRMED on the
iPad.** ✅ Phone (iPhone 13) install of 132 done 2026-07-24 (compact = layout unchanged; parity + a
compact regression check). ✅ **Bookmark + ePub sync CONFIRMED WORKING on device 2026-07-24** (Tuur —
the round-trip both devices awake, the owed witness). Remaining before this whole iPad wave promotes
to main: only the undiagnosed "could not process" (devlog instrumented), then promote AFTER the
book-import chat lands + prod is idle.
**SIM-ERASE GOTCHA (2026-07-24, cost ~1h):** `AudioPlayerModelTests.testPlayClaimsTheSessionAndStop-
ResetsState` claims a real `AVAudioSession` — after `xcrun simctl erase "iPhone 17"` the erased sim
loses its audio config, so `play()`→`isPlaying` is false and the test fails (or hangs on a starved
sim). PROVEN env-not-code: the identical build-130 commit (Fable-verified 971/0) also fails on the
erased sim, and build 132 passes 971/0 on an UNtouched sim. Don't erase the audio-test sim; run the
unit suite on a fresh/untouched iPhone sim (`-only-testing:SkriftMobileTests`).

---

**⭐ SIGNED SPEC (Tuur: "perfect", 2026-07-24 design session): `mocks/ipad-note-chrome-belongs.html` v2**
(Artifact 13c0cbce, "v2-visitor-sheet") **+ `mocks/ipad-note-surfaces.html` for the tones.** Design
verdicts, locked via a question round: Connections = **on demand, PER NOTE** (never remembered; 13"
can't afford a standing 300pt column) · arrives as a sheet **OVER the note** (nothing reflows) ·
summon = a **plain word** "Connections" in a quiet capsule (NO ◨ glyph — he caught it hiding in the
v1 chip; NO count — capped at 7 ⇒ reads "7" forever ⇒ zero signal; an honest number e.g.
backlinks-only = separate future decision) · resting state = **list + note** · ONE pinned ◧
(screen-fixed, hosted by whichever surface is under it — iPadOS-26's own sidebar pattern) · glass
containment on every bar control · sidebars on `skSurface`, note on `skBg`, hairline toolbar ·
player DOCKS at regular (hairline-top bar; phone keeps its floating glass capsule).

**BUILD BOARD (one wave → build 132, ONE install):**
1. Already committed, in the parked 131: black-band fix (bg outside the slide clip), open-on-newest
   (`selectedMemoID == nil → memos.first`), Notes title 22pt, the anchoring rule (leading against the
   list while it's open / centered when closed). 131 was compiled + freshness-checked, NEVER installed.
2. Surfaces: at regular, list column content bg → `skSurface`; note stays `skBg`.
3. Toolbar: hairline under `workbenchChrome`, spanning the workbench.
4. Glass containment: `PanelToggle` + ＋/⋯ get quiet circular containers (elev-ish bg + inset
   hairline); Process keeps its tinted capsule; the Connections control = text capsule (quiet →
   accent while the sheet is up).
5. ONE pinned ◧: overlay at the topLeading of MemosListView's regular HStack (z above both columns);
   the list header's identity row gains a ~40pt leading gutter; `workbenchChrome` drops its own ◧.
   Align the list header row and the chrome bar to the same top line so the button never appears to
   move.
6. Connections → visitor sheet: DELETE the sliding column + the `aguard` spacer + the
   `ipadConnectionsVisible` AppStorage (regular; phone untouched). New transient `@State` in
   MemoDetailView, auto-close on `selection` change. Sheet = overlay(.trailing) over the PAGER ONLY
   (stops above the docked player — transport stays reachable; Tuur ok'd), width ~300, `skSurface`
   + leading hairline + shadow, `.move(edge: .trailing)` spring. Header: CONNECTIONS · Closest⇄Date
   pill · ✕.
7. Docked player at regular: replace the floating glass capsule with a full-note-width bar
   (hairline top, `skSurface`); compact keeps the glass capsule byte-for-byte.
8. Measure rule follow-up: `bothPanelsClosed` collapses to `!listVisible` (Connections is no longer
   a column) — focus = list closed = centered 900.
**Gates:** mobile unit suite green · iPad-sim live taps (◧ both directions incl. the pinned-overlay
hosting, Connections summon/✕/auto-close-on-note-switch) · bump CFBundleVersion → 132 (project.yml,
3 spots; plists are generated + tracked) · device build UDID `00008142-000239E2146B801C`, install
devicectl `1E182D43-5A0A-5110-8355-89CD78810E13`, string-grep the `.debug.dylib` for freshness.

---

## 🎛️ (prev) iPad note view = direction A (2026-07-24; superseded by the signed spec above)

**⬛ NOTE-VIEW REDESIGN, direction A (`ccaed9b`, build 127, installed on the iPad).** Tuur wanted the
audio player moved to the bottom (phone-parity) + a calmer top. Mock-first: three variants in
`mocks/ipad-player-position.html` (also published as an Artifact) → **Tuur picked A** ("make the right
toggle match the native one on the left").
- **Player → bottom** at every width (the phone's own glass `PlayerBar`); the custom all-in-one top
  note bar is RETIRED. **Nav bar** carries the chrome: matched pair ◧ list / ◨ Connections on the
  edges, **Process · ＋ · ⋯** trailing. No nav title (the body's editable title leads — no dup).
- **THE TOGGLE FINDING:** iPadOS won't surface its own split-view sidebar toggle in this nested
  list/note/Connections layout (tried removing `.toolbar(removing:.sidebarToggle)` on the detail — it
  didn't appear). So **both toggles are custom**, styled as the plain system `sidebar.left/right` glyph
  (nav tint, no accent box) → they match + read as system chrome (Tuur's ask). The native hover-peek is
  pointer-only + not reachable here — noted, not delivered.
- Gate: mobile unit 971/0, iPad-sim + device builds green. **Sim-verified the OPEN state** (matched
  toggles, bottom player spanning the note column, no dup title).
- **CORRECTED build 128 (`b4b8adf`):** 127 shipped the chrome in the SPANNING nav bar → the
  actions/toggles flew to the far right, ABOVE Connections (they act on the note). **My miss: I
  screenshotted it and didn't check WHERE the items sat vs the columns.** Fix: the chrome is a bar
  CONTAINED to the note column now (`noteChromeBar` in the note VStack, nav bar hidden again) —
  `◧ · Process · ＋ · ⋯ · ◨` over the note, verified by cropping + measuring it's LEFT of the
  note/Connections divider. Per-note Process is TINTED (not filled) so it stops competing with the
  list's "Process N". **DURABLE: when a control's column-alignment matters, MEASURE its x vs the
  column boundary — "it rendered" ≠ "it's in the right column".**
- **DEVICE ROUND (build 129, `86da9ed`):** Tuur drove 128 in the sim — the list side + resize "looks
  kinda good"; two bugs fixed: (1) **closing both panels now WIDENS the note** (readingMeasure 640→900
  in focus mode — he "should win real estate"; sim-verified wider); (2) **the Connections ◨ no longer
  floats** behind the sliding panel (dropped `withAnimation` on that toggle — the panel is a sibling
  that resizes the note; the list toggle, which animated nicely, is untouched). A polished panel slide
  is a next-week item.
- **✅ THE REDO — STACKING REBUILT (`1f81136`, build 130, installed on the iPad 2026-07-24; mock
  `mocks/ipad-note-stacking.html`, published as an Artifact).** The Fable redo session ran: NOT a patch —
  the regular-width hierarchy was rebuilt from the ground up, keeping signed direction A pixel-for-pixel
  except ONE visible delta (below). Root cause confirmed as diagnosed: three systems animated out of
  sync — `columnVisibility` ⇄ ◧ shadow state, the Connections panel as an inserted/removed sibling
  resizing the note, and the chrome riding that resizing column.
  - **The new stacking:** `NavigationSplitView` is GONE. MemosListView owns a flat
    `HStack{ sliding 375 list | workbench }`; the workbench (MemoDetailView) = a chrome band SPANNING
    note+Connections, above `HStack{ note pager+player | sliding Connections }`. Panels are fixed-width
    content in width-animated clipped windows (`slidingColumn`, Adaptive.swift) — they SLIDE, never
    unmount (state + presentations survive), and ONE `withAnimation` drives every move.
    `listVisible`/`connectionsVisible` are the only layout state. The `paneMemoID` hoist died (the
    "sibling outside the NavigationStack" constraint was obsolete once the nav bar hid); the panel reads
    the pager's `currentMemo` directly. Dead code cleaned: `transportDensity`/`processControlVisible`/
    `barWidth`/`nativeToggle`/`columnToggle`/`showPaneThread`. Net −15 lines.
  - **The one visible delta (mocked first): ◨ pins to the screen's trailing corner** and the panel
    slides in BENEATH it (Mac inspector idiom) — the tapped toggle can't move, so the float is
    structurally impossible; the slide animates again. Actions (Process ＋ ⋯) hold LEFT of the divider
    via a width-animated spacer (127 lesson intact). List column is a FIXED 375 (drag-resize gone, and
    with it the squeezed narrow-list rows — symptom #2 closed by construction).
  - **Gate:** mobile unit 971/0; iPad Pro 13" sim LIVE taps — all four toggle directions verified
    (◨ close/open with the button pinned at the corner, ◧ close/open, focus mode = 900 measure,
    player spanning each width). Freshness string-checked (`workbenchChrome` in, `transportDensity`
    gone, CFBundleVersion 130).
  - **OWED (Tuur):** the live-feel eyeball of 130 — the float + ◧ tap are the things to retest; the ◨
    corner-pin is the one design delta to veto if it reads wrong (mock shows it interactively); and the
    open gut-check from 129: does the bottom player sit too far from the text at 13"? (Direction A keeps
    it at the bottom; the new stacking makes moving it cheap if the answer is yes.)

---

## 🖥️ (prev) iPad chrome build (session end 2026-07-23 ~19:25)

**⬛ HEADER POLISH PASS (`ded3d41`, build 122, installed on the iPad) — Tuur's device round on the
Mac-header rebuild.** LANDSCAPE RECLAIM CONFIRMED (his 19:06 device shot + my sim: left header y235
≈ Connections y225 — the band is gone in landscape). His asks, all done:
- **Import on BOTH apps** (`SharedCopy.importVerb`) — the Mac's button was "Upload"; one word now
  (behavior unchanged, Mac still opens its file panel).
- **"Search memos" everywhere** (`SharedCopy.searchPlaceholder`) — iPad/phone said "Search transcripts".
- **iPad chips = the Mac's, opacity-for-opacity** (accent text on accent@0.14; the heavier skAccentSoft
  pill is gone) and **no count on the Unrated chip** — the number moved to the triage line ("N not
  rated" under the Unrated chip, the Mac's own branch).
- **Import IS the picker** (menu: Files · Video from Photos · Scan) — so **⋯ stopped doubling as an
  import menu**; it's now a single **filter/sort icon** opening the advanced sheet (place/date/photos/
  unsynced — the axes the chips don't cover). Answers his "is [⋯] not the same as import?".
- **Identity row: kept Notes + Select** (he "like[s] that the iPad has select"); NOT Skrift+gear.
- **ONE sort control (`ef6d772`, build 123):** [superseded by the ONE FILTER BUTTON below] — the
  inline sort became a direct-pick Menu and the sheet dropped Sort at regular.
- **ONE FILTER BUTTON, both apps (`bf039dc`, build 124):** Tuur — the inline "Newest" + the ⋯ + the
  chips had overlapping jobs; collapse to a single Filter control; the one true dup (sheet "Not rated"
  ↔ Unrated chip) is gone.
  - **iPad:** ONE **"Filter"** button (funnel) in the triage line opens the Sort & Filter sheet, which
    now carries **Sort AND the metadata filters**. Removed the inline "Newest" menu + the identity-row
    ⋯ (identity row = Notes + Select). Sheet drops "Not rated" at regular (`showNotRated: !isRegular`,
    the Unrated chip owns it); phone keeps it. Button tints accent when a filter is active.
  - **Mac (same affordance):** the inline sort CYCLE → a **"Filter" button (funnel) → popover of sort
    options** (direct pick, checked). Button+popover NOT a Menu (Menu breaks the ImageRenderer snapshot
    harness). Sidebar UITests updated (`sidebar.sort`→`sidebar.filter`; cycle test → popover-opens-sort).
  - **⚠️ SCOPE / OWED:** the **Mac popover holds Sort ONLY** — the iPad's place/photo filters ride on
    Memo metadata the Mac's `PipelineFile` row doesn't carry; **porting them to the Mac is a follow-up**
    (a memo-metadata join). Also owed: the iPad Filter SHEET contents on device (a tap — sim is stuck
    landscape, rotated tap space), and a **Mac Dev redeploy** to eyeball its Filter popover.
  Gate: mobile 971/0, desktop 496/0, all builds green; header sim-verified (single Filter button, clean
  identity row).
- **FILTER SHEET bigger + trimmed (`ce41f77`, build 125):** Tuur on device — the iPad Filter sheet is
  a **`.large` detent** now (was the cramped medium box); **Place + Has-photos removed** at regular
  ("place I'd go to the Review screen; photos I don't need") — gated phone-only via `showPhoneFilters`
  (phone keeps them + Not-rated). iPad Filter = **Sort + Unsynced + Date**. Mac Filter popover enlarged
  (260pt, "Sort & Filter" title). Big sheet sim-verified. Rig: `-showFilterSheet` presents it on launch.
  **[RESOLVED below]** phone → just the Filter button; Mac → add Date.
- **PHONE Filter + Mac Date + place/photos gone (`6f31463`, build 126):** Tuur's calls —
  - **Phone:** its filter funnel now opens the SAME trimmed big sheet as the iPad (no chips — he chose
    "just the Filter button"). **Place + Has-photos removed from BOTH apps**; phone keeps "Not rated"
    (no chips), iPad hides it (Unrated chip). Phone Filter = Sort + Not-rated + Unsynced + Date; iPad =
    Sort + Unsynced + Date. Both sim-verified (full-height, trimmed). Removed `places`/`availablePlaces`.
  - **Mac:** the enlarged Filter popover gained a **Date (uploaded) section** (From/To inclusive + Clear;
    button tints accent when active) — `AppModel.dateFrom/dateTo` → `matchesDate` → `visible`.
  - **Shared:** the date-range rule is ONE thing now — `Shared/Pipeline/DateRangeFilter` (both apps call
    it; 4 tests in the desktop bundle). Rig: `-showFilterSheet` moved to notesRoot (fires phone + iPad).
  Gate: mobile 971/0, desktop **500/0** (+4), all builds green. **OWED:** Mac Dev redeploy to eyeball the
  Date popover; phone install of 126 (device round — the build already covers it).
Gate: mobile 971/0, desktop 496/0, all builds green. Sim-verified upright (rotated the landscape
capture; chips/Import/Search-memos/no-count all render). Sort-MENU interaction owed on device (the sim
is stuck landscape from Tuur's flip → rotated tap space; the Menu+Picker pattern is proven in-file).

**⬛ HEADER = THE MAC SIDEBAR (`fc0b83a`, build 121, installed on the iPad).** Tuur on the
device (landscape): "the empty space in top left is shit" + "make that look the same" as the Mac
(he showed the Mac sidebar: All/Needs Work/Done/Unrated · N ready to review · N to process · Newest).
Built to the Mac sidebar as the spec:
- **Shared `QueueFilter`** (All/Needs Work/Done/Unrated) moved to `Shared/Model` — ONE word set,
  Mac matches a `PipelineFile`, iPad a `Memo` via `ProcessPile.matches`. No export step on iPad →
  **Done = processed**: Needs Work = rated + not-enhanced, Done = rated + enhanced, Unrated = sig 0
  (chips partition the rated set, test-proven).
- **Triage line** "N ready to review · N to process" + a **Newest** sort cycle (`MemoSort.short/.next`);
  "to process" IS the Process button's count (`ProcessPile.waiting`), pinned equal by a test.
- **Reclaimed the top band**: the Notes column is the split-view SIDEBAR, hosted RAW → its hidden
  nav bar's strip stayed reserved (the dead band). Wrapped it in a `NavigationStack` like the detail's
  `noteStack` (which collapses a hidden bar — why the phone always looked right). **Portrait verified
  (PIL-measured: Notes y215 ≈ note-bar y204 ≈ Connections y225, was y235 pre-fix).**
- ⚠️ **LANDSCAPE RECLAIM UNVERIFIED ON SIM** — the headless sim can't rotate here (Apple events
  blocked, no cliclick). The fix is the SAME wrapper the detail column has, and the detail sits high
  in Tuur's landscape shot, so it should carry — **but Tuur's device-landscape confirm is owed** (he's
  holding it in landscape; 121 is installed).
- **Sim gotcha (durable): `sips --cropOffset` gave FALSE "empty" crops here — cost a wrong "band still
  there" read. Measure pixels with PIL (first non-dark row per column), never trust a sips crop.**
- **Open naming calls (flag, didn't guess):** the Mac says **Upload** / iPad says **Import**; the Mac's
  top row is **Skrift + gear** / iPad kept **Notes + Select + ⋯** (Select/⋯ are needed for touch
  multi-select + the import menu, and Settings is already a tab). Left both as-is pending Tuur.

---

## 🖥️ (previous) iPad chrome build (session end 2026-07-23 ~18:25)

**SIGNED SPEC = `mocks/ipad-chrome.html` direction A** (Tuur picked it and refined the bar).
Chrome built `044f1c6` (119); **eyeball-fix wave `13269c1`, CFBundleVersion 120, INSTALLED on the
iPad** (devicectl `1E182D43-…`; binary freshness confirmed by string-grep, not just a green build).
**Suites green THIS session: mobile unit 968/0, desktop unit 496/0; iPad-sim + iPad-DEVICE builds
green.** Sim-eyeballed the bar across FIVE rounds (bar-v3/v4 → fix-v1 clip regression → fix-v2 →
fix-process → fix-v3 tight + fix-wide full).

**⬛ THE 2026-07-23-EVE FIX WAVE (`13269c1`) — what the sim shots caught + fixed:**
- **Note bar survives portrait.** The scrubber is the flexible element for real now (explicit
  `maxWidth` on the GeometryReader — a `layoutPriority` did the OPPOSITE and clipped the note title
  AND the Connections panel, shot fix-v1). Speed button was an EMPTY capsule when squeezed →
  `fixedSize`. **Graceful density** (`PlayerBar.Density .full/.tight/.minimal`): when the column
  can't hold everything, controls stand down in the order the scrubber can replace them — ±10 skips
  first (drag), then the time labels (the knob says it). Full bar returns when the column widens
  (proven by closing Connections — fix-wide).
- **Process = the Mac's button, ported whole.** It wore the verb but not the meaning: "Process N"
  counted the UNRATED pile — the set every polisher SKIPS. New shared rule **`ProcessPile`**
  (Shared/Pipeline): waiting = RATED + not-yet-enhanced; unrated is a DIFFERENT pile (waits on Tuur,
  not a model), and they provably never overlap. The button now RUNS that pile
  (`PolishCenter.processPile`, sequential — one MLX context or a pad jetsams) showing "Processing 2
  of 5" (`SharedCopy.processingCount`, adopted by the Mac's run bar too) with a stop; appears only
  where the device can process; disabled at 0. One `enhancements` @Query drives the count (never a
  per-memo fetch in a body — the frozen-library trap).
- **Flag verb retired everywhere** (rating IS the flag): "Flagged — the Mac will process this" →
  "Rated — …"; Mac triage help "until you flag one" → "rate one". A test fails on any flag language.
- **List rows:** "Transcribing" broke mid-word in its capsule + the date stamp wrapped to two lines
  once the status pill shared the row → both `fixedSize`.
- **Rig:** `FakePolishEngine` (DEBUG, `-fakePolishEngine`) — the sim gate is false by design, which
  left every Process state un-eyeballable; now they render on the sim. Never true in Release.

**What landed in the chrome build (`044f1c6`, all committed):**

**What landed (all committed):**
- **The note bar** — one pinned row owned by the note; system nav toolbar hidden at regular
  width so nothing floats over a column: `◧ | ⟲10 ▶ ⟳10 | elapsed | scrubber FLEXES |
  remaining | 1× | ＋ | Process | ⋯ | ◨`. Split speakers moved into ⋯.
- **The bottom floating player stands down at regular width** — it was rendering a SECOND
  player and ghosting behind the tab strip (the artifact from the 118 round). Compact untouched.
- **List header = the Mac's construction** — the low 30pt wordmark is gone; identity line +
  Import + **Process N** buttons + search + count line.
- **Process everywhere** via `SharedCopy.processVerb` (the anti-drift constant).
- **Real progress**: engine reports `PolishStep` as DATA (not a guessed fraction) → the bar
  shows "Copy-edit · 2 of 3" + determinate bar, and "Getting the model — 41%" first run.
- **Mac gained ◧** (notes-list toggle mirroring Connections, collapses the column via
  `macSidebarVisible`); Mac deliberately has no ＋.

**NEXT CHAT — heavy work first:**
0. **TUUR'S OWN EYEBALL of 120 on the iPad** (installed, not yet human-seen — the sim eyeball was
   MINE). Hand him the note bar in BOTH orientations: portrait (tight → play·scrubber·1×·＋·Process·⋯
   with skips/times dropped) and landscape (full bar). Also the header's "Process N" and, once the
   model's down, its "Processing 2 of 5" running state + stop.
1. **Install 120 on the PHONE too** and confirm the compact layout is untouched (this wave only
   changed regular-width geometry + shared copy, but the copy + row-wrap fixes ride along) — phone
   UDID `00008110-001208C902EA201E`. Mac Dev also owes a redeploy for its new ◧ (build → pkill →
   ditto → open).
2. **The processing FAILURE Tuur hit is still undiagnosed** ("could not process") — the path
   now logs; pull `Documents/devlog.txt` and read it rather than guessing. Prime suspect: the
   4.6 GB model was never downloaded (Settings → Process on this iPad → Download). NOTE: with 120,
   the header **Process N** now actually runs the pile, so this is the natural way to reproduce it.
3. **Bookmark + ePub sync round-trips are still unwitnessed** (both need the phone AND iPad
   awake with the app foreground; a locked device suspends the app and can't even write the log).

**Open with Tuur:** the ＋ placement (parked in the bar, he wondered about a better home) ·
whether the Mac's "Mark all as Passing" bulk wording is right · promotion to main is sequenced
AFTER the other chat's book-import fixes land.

**🪟 COLUMN TOGGLES (build 118, on the iPad; Tuur's ask + my process miss).** He said the right
side "looks stupid"; I removed the collapse control instead of asking — wrong call twice over
(the real defect was the note's toolbar spanning the panel's column, since fixed by making them
siblings). What he actually wants: close EITHER column — "sometimes I just want to focus on
writing and I don't want any distractions". Built: a toggle per side in the note's toolbar
(icon on the side it controls, accent=open / dim=closed, both persisted via AppStorage); the
list rides `NavigationSplitView(columnVisibility:)` kept two-way in sync; iPadOS's duplicate
sidebar toggle removed via `.toolbar(removing: .sidebarToggle)`.
**VERIFIED (sim):** both-open and focus (both closed) render correctly.
**OPEN — needs a LIVE tap-through (launch-arg permutations proved the wrong instrument):**
(a) re-opening the list from the icon didn't restore the column in a scripted run — suspect
scene-restoration of the collapsed sidebar state beating the `.onAppear` assignment, or the
two-way sync latching closed; (b) a ghost player-bar row draws behind the tab strip while the
list is hidden (the bar is a bottom `safeAreaInset` with GlassEffectContainer — suspect the
iOS-26 tab-bar scroll-edge effect sampling it once the pane spans full width).

**🔬 THE CHAPTER BUG — ROOT-CAUSED FROM THE DEVICE (2026-07-23 eve, build 115 fixes + self-heals).**
Tuur: "the chapters look very different from what the phone has… I think the ePub didn't come over."
Diagnosed by pulling the iPad's own container instead of guessing: `alignment_f0.json` WAS there
(9.5 MB, `verdict=aligned`, **29 chapterMarks with the real TOC titles**, `transcriptSignature
48751:120138` == the transcript's own content signature → freshness passes). The sync was fine.
**Root cause: build 106's `Audiobook` encoder didn't persist `epubChapters`** (main's round-5 fix
`885bc15` only reached this branch in today's merge) — the receiver derived the 29 chapters, wrote
them, the encoder dropped them, and `receiveAlignments` latched its applied-marker UNCONDITIONALLY
→ never retried. Fixes: marker carries the OUTCOME (`<sig>#<count>`) and is written only after the
chapters READ BACK (verdict-gate the derivation); a legacy bare-signature marker re-derives ONCE
from the on-disk sidecar (self-heal, no re-download); mark-less alignments still latch (`#0`);
derivation now reads the LOCAL record (the sanitized remote blob has `detectedChapters` stripped
by contract, which was silently dropping partial-merge chapters on receivers). 7 tests.
**DOCTRINE (new, general):** a sync applied-marker must record what the apply PRODUCED, never just
that it ran. **Also removed:** the iPad Connections collapse toggle (at regular width the note is
already at its reading measure — hiding the panel only re-centred the same text; the Mac keeps its
collapse, where a narrow window earns it).
**✅ ePub FILE SYNC BUILT (2026-07-23 eve, Tuur green-lit "perhaps syncing epub is the way",
build 117, suite 957/0):** `AudiobookSyncRecord.epubSignature` = manifest AND change-signature
(`<i>:<size>:<name>` joined "|", filename LAST so a ":" in it survives); `sendEpubs`/`receiveEpubs`
mirror the transcript pair on the same raw-CloudKit transport (~1 MB vs the 738 MB audio); the
receiver sets its OWN local attach fields after the bytes land, so filenames still never ride the
whole-blob record (local-only doctrine keeps its teeth against old writers); verdict-gated marker.
7 tests. **DEVICE ROUND OWED:** phone uploads on its next foreground reconcile → iPad should show
the ePub attached in the Text sheet, and must NOT kick off a re-align (its alignment sidecars are
already fresh — watch `BookTextActivity`).

**(superseded, kept for the reasoning) — the ePub FILE itself:** local-by-design (v1 doctrine); the alignment carries chapters
+ true-text read-along, so the Text sheet honestly reads "No book text attached" on a receiver even
though its effects are present. Tuur asked for it to come over — DECISION OWED: sync the ePub blob
(cheap: ~2 MB vs the 738 MB audio; enables re-align + captures against published text on any
device) via a new `epubSignature` on the sync record + local attach-field restore on the receiver
(keeps the blob out of the LWW record, so old writers still can't erase it).

**📚 iPad LIVE ROUND (2026-07-23 eve, build 114 on 'Tiuri's iPad big'):** sidebar mode retired
(`.tabBarOnly` — "weird and unnecessary"); origin/main MERGED IN (📖 rounds 5–8 + unified Text
sheet + lifecycle v3; suite now 944/0; conflicts: menu-extraction kept w/ main's unified verbs,
versions → 114). **Book-sync answer (verified in source):** audio ✓ position/speed ✓ transcript
sidecars ✓ alignment sidecars ✓ (chapters re-derive on receiver — the iPad's stale chapters were
build-106-predates-spike-6, fixed by the merge) · ePub FILE local-by-design (alignment travels) ·
**bookmarks were the gap → BUILT: `AudiobookBookmarksRecord` whole-list LWW per synced book (own
record type = old-writer-erasure-proof), BookmarkStore LWW stamp, push-on-edit pokes, 11 tests.**
Prod CloudKit schema deploy at promotion now covers PolishPromptsRecord + AudiobookBookmarksRecord.
OWED: Tuur's 114 round (chapters now current? bookmark round-trip once a second device has the
book playing).

**🗺️ NEW (Tuur review, 2026-07-23) — Mac Places map: deep dive zooms OUT.** Repro on the Mac
Journal map: zoomed in on a 7-note cluster → double-click splits it 3+4 → double-click the
4-cluster ZOOMS OUT instead of in. That's the class of bug the phone's b90 round fixed ("pin tap
never zooms out") — the Mac's map-behind-Places likely never got the b90 camera contract.
Check whether the iPad pane is immune (it reuses the PHONE's `JournalMapCanvas`, so it should
carry the fix — verify), then port the b90 rules to the Mac's `JournalView` map mode.

**✅ m1b AMENDED (2026-07-23 evening): the unrated FADE runs on the PHONE too** (Tuur killed the
washout worry: "when I take a note that I know is important I give it a score straight away" —
unrated = untriaged, every width). Phone rows: dim + hollow ○; the always-on spine line stays
iPad/Mac-only (phone keeps the urgency amber line); count line stays iPad-only. Same pass:
Mac bulk renamed **"Mark all as Passing"** (0.1's own tier word — flag language fully retired).
**PROMOTION SEQUENCING (Tuur): wait for the other chat's book-import fixes to land on main,
THEN merge main in + promote; iPad Dev install + polish live test when he collects the iPad.**

**✅ m1b RESOLVED (2026-07-23, later same day): Tuur picked B + the correction that closed the
verb loop — "flag for processing should just be done when you give it a rating."** Built: at
regular width an unrated live note renders QUIET (dimmed, hollow ○, its MemoSpine one-liner in
the date slot — status pill outranks it when present), count line "N notes · K not rated" taps
into the EXISTING Not-rated filter, tap opens the note whose Importance circles ARE the
rating-and-flag surface. **No Flag verb anywhere — the Mac's quiet-row "Flag for processing"
context-menu item was REMOVED the same day** (same reasoning as the m6 peek's dead silent-0.1
button; `flagQuiet` deleted; "Flag all K" bulk + count-line wording on the Mac left as-is —
flag for Tuur: rename that too?). Compact = phone notebook untouched (asymmetry doctrine
updated in-source).

**✅ V2 BUILT same-day (2026-07-23 pm, conductor-direct — no lanes):** items 1–6+8 below all landed (Connections=Mac-verbatim panel w/ why-chips
+ toolbar badge · polish=visible ✨ button, automation deleted · Mac-parity prompt editors +
**synced prompts** (PolishPromptsRecord carrier, vocab-LWW pattern, both apps, BOTH CloudKit
schemas — prod deploy at promotion) · player=phone-at-every-width (three-zone deleted; expert
canvas clean) · then-vs-now SHARED (ThenVsNow) + the Mac Journal card w/ exclusion · Mac map
dive clamp (b90 port). Gate + numbers in the roadmap shipped log. **OWED: Tuur picks m1b A or B
(rows), eyeball rounds, real-iPad install, polish live test, promote.**

**Original decision list (for the record):**
1. Shell: **system top tab strip accepted** ("that's how it is") — no custom bottom bar.
2. Connections: **copy the Mac panel verbatim** — toolbar count-badge open/close (the Mac's
   affordance, verified in desktop `ConnectionsPanel.swift`), Mac row anatomy, **drop the inline
   closeness %** (Mac keeps it behind hover; touch shows none for now).
3. Polish: **the Mac's verb** — visible Polish/Process button on an unpolished note; KILL the
   polish-on-open toggle. Settings grows **Mac-parity polish settings incl. the three prompt
   editors** (shared defaults). **Prompt overrides SYNC (Tuur 2026-07-23: "do llm prompt
   syncing aswell")** — vocab-pattern LWW carrier (`PolishPromptsRecord`), both apps
   read+write: iPad editors ↔ Mac settings.json, newest wins whole-blob.
   Double-polish race: SAFE by design — `enhancedAt` LWW + `MacCloudWriteBack`'s newer-write
   guard (verified); both burn compute, one wins everywhere. Touch-up: that file's doc still
   says "written ONLY by the Mac" (stale since the wave).
4. **Then-vs-now → all three devices** (Tuur: "we should have that on all three"): phone ✓,
   iPad ✓ (inherits), Mac ✗ (verified zero refs) — move `bestThenNow` + the 14d/6mo window
   rule to `Shared/Retrieval`, card into the Mac Journal column.
5. Map: one behavior on all three — port the phone b90 camera contract to the Mac (bullet
   above); verify iPad's phone-canvas carries it on device.
6. Books: shelf stays; **regular width presents the PHONE player** (width-capped) instead of
   the three-zone layout — a clean canvas for the external book-expert chat that gets a
   self-contained player to redesign (that handoff is that chat's job, not this board's).
7. Notes list rows on iPad: **OPEN — Tuur unconvinced by phone-dialect ("the iPad is
   in-between; easier to cleanup notes; closer to Mac can be argued"). Decide from the mock:
   m1b draws variant A (phone rows verbatim) vs variant B (phone rows + the Mac's triage
   layer: unrated = quiet hollow-○ dimmed rows, context-menu Flag/Delete verbs, count line).
   No row code changes until the pick (current build = variant A already).
8. Record card: unchanged. Mock upkeep: patch m3/m5 (+ m6 note) to v2 before building
   (mock-first), add as-built screenshots; m1/m4 stand (the build is truer than the drawing —
   real SF Symbols/components; mock glyphs were approximations).

**Parked/flagged en route:** SHELL: last-note-delete in the detail pane leaves a stale pane until
a tap (MemoDetailView dismiss is a no-op at pane root — 1-line fix candidate in DETAIL's file) ·
DETAIL: related derivation double-computes at regular (footer hidden + panel; gate on hSize if it
ever matters) · BOOKS: added a bookmark-toggle chip beyond the mock (flag if unwanted) ·
lane wrap-blocks with per-decision flip instructions live in the agents' PLAN files + this
session's transcript.

## ⭐ CONTINUE HERE (session end 2026-07-22 ~15:00 — the 📖 marathon session)

**THE 📖 LANE IS DONE** (roadmap EPubAlign = done 2026-07-22): spikes 1–6 + batch D + FOUR live
device rounds in one session — attach ePub, true-text read-along (device: "way more fucking
aligned"), real-TOC chapters w/ honest partial-merge, multi-text sheet w/ time-true bar, all
on phone b102; Mac Dev current (v0.15.5 + all harnesses). Sections below = the full record.

**NEXT CHAT'S WORK (in order):**
0. ✅ **📖 ROUNDS 5–8 VERIFIED + MERGED 2026-07-23** (the verify session; full record = 📖
   ROUND 8 block below): sim suite 894/0 + Mac 492/0 + MLX build green; R5 device-proven
   live (re-adopt devlog line, real ePub TOC in library.json, 29 chapters); the repro spots
   turned out to be ROUND 8's same-text merge eater — fixed, schema 5, and the healed
   device sidecar machine-verified (7,506 sentences, both repro sentences present as book
   text at conf 1.00, "Book 1: The Boy and the Goddess" chapters). ✅ TUUR EYEBALL SAME
   SESSION: "the parts that were gone before are now there. The chapters look good." ✅
   Attach-UX also live-confirmed (Tuur re-attached the Odyssey text himself, saw "Matching
   the text against the transcript…"). ✅ **MOCK SIGNED OFF same session** (Tuur walked all
   4 phones: liked the flow + time estimate + step ②, A0-vs-A1 explained, "Perfect, yeah.
   I like it." → yes): **`mocks/book-text-unified.html` = the next build board** — ONE
   "Text…" verb/sheet (Level 1 Transcript / Level 2 Book text) replaces the two menu
   entries, + the A0 once-only post-import do-both prompt. Roadmap idea i12. Lane CLOSED.
   → **BUILT same session (b110):** `BookTextSheet` grew the Level-1 inline transcribe card
   (fresh/partial/live-progress+pause/complete; estimate only from measured throughput),
   Level-2 empty card + tan waiting rows; `BookTextPromptSheet` = A0 (once per book,
   UserDefaults seen-set, sheet-swap-race-safe presentation via onDismiss parking);
   ONE "Text…" verb in both menus (TranscribeBookView survives as the read-along nudge's
   sheet); `-showTextSheet`/`-showTextPrompt` render hooks. Suite green (new
   TranscriptCardState/waiting/subtitle/footer/A0 tests); sim A0+A1 vision-checked against
   the mock. **OWED: Tuur's b110 device eyeball** (A3 on the Odyssey, A0 on the next real
   import, the one-verb menus).
   NEW P2 filed same session: silent re-align freezes the library UI.
0b. ✅ **⏱ v3 verify FULLY DONE 2026-07-23** (record in the v3 block above): suites + MLX green,
   merged to `main`, Mac Dev sweep-per-activation eyeballed, AND the phone-open eyeball landed —
   first open under build 106 stamped 53 pre-v3 trashed notes at the open moment, all now showing
   the full 14-day window. Nothing owed. (Optional only: a visual glance at Recently Deleted.)
1. **Pull phone feedback if Tuur recorded any** (/pull-phone-feedback) — 4 live rounds today
   means fresh findings likely.
2. **🧬 walkthrough tail (eyes, guided — b92-era items still unconfirmed):** untouched-note
   detail fade line · WayOut row peek + Bring back · b90 map trio · "0.1 · Passing" on the
   flagged B122966B memo · Mac unified Notes list (quiet rows / Flag verbs / Unrated chip).
   Fading-search WAS confirmed 2026-07-21. Then LifeIA (roadmap now) = done.
3. **Prod promotion decision** (still Dev-only: 🧬 overhaul + everything 📖): deliberate step —
   Release builds both apps while prod idle, CloudKit prod schema deploy (Reminders note in
   NFeat), the Release bundle-ID App-Groups one-time Xcode visit (capture-items lesson).
   Profile the phone list/search paths first (Tuur: Dev "not very well optimized"; Debug build
   caveat noted).
4. **iPad: update its old Skrift Dev build** (it erased additive sync fields once — the
   local-only doctrine now protects those, but old writers + new fields stay a standing risk).
   iPad UDID via `xcrun devicectl list devices` when it's reachable.
5. **Next build lane candidates** (Tuur picks): reading-mode redesign (signed mock 2026-06-19,
   never built; now also the home for ePub images-in-reader + coverage visibility) · Journal
   desktop build board · Connections owed items.
**Standing:** ~~another session owns `mocks/lifecycle-triage-peek.html`~~ → RESOLVED: that
session committed the mock (d27a047) AND built the whole ⏱ one-clock lifecycle same day —
see the ⏱ section at the top of this file. LANE_PLAYBOOK.md = the standing lane contract
(3 batches ran under it today; pinned-contract seams compiled first-try twice).

## 🧬 (previous CONTINUE HERE) lifecycle IA overhaul: BUILT + MACHINE-VERIFIED LIVE (2026-07-21 eve); Tuur walkthroughs = the only gate left

**✅ Owed verifications CLOSED 2026-07-21 pm (machine-verified over USB — phone store pulled +
diffed against the Mac's; new DEBUG dev hooks below):**
1. **MacMemoAuthor live round-trip ✅** — fresh `Mac roundtrip 21 Jul.m4a` ingested headlessly
   (real IngestService) → launch reconcile authored the Memo (sig 0.1 floor, transcript
   `pending`, 300,654-byte audio asset) → arrived on the iPhone byte-identical → Mac
   `-processfile` transcribed it → next sweep logged `reflected-transcripts 1` → phone got the
   474-char transcript (`done`, confidence 1.0). Blob re-extracted from the PHONE store =
   valid m4af (afinfo). **Backfill ✅**: 12 old Mac-only rows (incl. Hotel Du Vin, New
   Recording, an .mp4, a pathless capture → correctly text-only) all authored + on the phone;
   real ratings preserved (0.5/0.6/0.2), unrated floored to exactly 0.1.
2. **Q2 write-back ✅ (data leg)** — `-flagmemo` ran the real sheet verb on unrated
   `memo_B122966B…` (0.0→0.1) → phone store shows 0.1. The "0.1 · Passing" RENDER = Tuur's eyes.
3. **Timer sweep ✅** — `lifecycle sweep ran` on launch, on an in-process NSCalendarDayChanged
   poke, and on a 25s-shrunk heartbeat tick (loop machinery sound; real midnight/24h = OS
   contract, unpokeable without moving the system clock).
4a. **✅ Tuur 2026-07-21 pm: b92 fading-search CONFIRMED on device** ("I can look up the
   notes that are about to fade away by searching for them"). ⚠️ Same round: **phone Dev
   feels SLOW** ("not very well optimized… better than the non-dev version") — NOTE the Dev
   build is Debug (-Onone), so part of this is build config, but don't hide behind that:
   profile the list/search paths on device before prod promotion; ⚡ audit follow-up candidate.
4. **REMAINING — Tuur walkthroughs (eyes only):** phone b92 (amber 'fading' search hits ·
   untouched note's detail "starts fading <date>" line · WayOut row peek + Bring back · b90 map
   trio: card scrolls all in-view notes, pin tap never zooms out, gestures clear selection ·
   NEW: play "Mac roundtrip 21 Jul" + see "0.1 · Passing" on the flagged B122966B memo) + Mac
   (unified Notes list quiet rows / Flag verbs / Unrated chip / peeks). Then LifeIA = done.
**New DEBUG dev hooks (desktop, RunFile family):** `-ingestfile <path>` (real import verb,
headless), `-flagmemo <uuid>` (real Q2 flag verb + export hold), `-poke-sweep <sec>`
(LifecycleSweepScheduler verification; replaced `-poke-daychange`/`-sweepHeartbeatSeconds` when v3
retired the unattended triggers, 2026-07-23). Quit the GUI first, as ever.
**Branch note:** `claude/skrift-roundtrip-verify-wvnpbn` merged to main 2026-07-21 (fast-forward,
contains q3kv2n). The 5 📖 open decisions remain with Tuur — 📖 section bottom.
Everything below = the build record of how we got here.

## 🧬 (build record) lifecycle IA overhaul (locked 2026-07-21; spine BUILT)

**THE SPEC = `mocks/lifecycle-ia-explorations.html`** (Fable-agent exploration, Tuur-approved):
Direction 2 (Two Rooms, One Spine) + Direction 3's exit conveyor. Root diagnosis: significance was
BOTH the process gate (MemoCloudIngest:39) and one of nine touch signals (MemoLifecycle:23) → the
zombie quadrant (touched-unrated: never processed, never fades, RootView:34 dead-end) + two
same-named trashes over different stores. Superseded on arrival: `mocks/unrated-shelf.html` (same
problem, worse room — keep as the artifact that exposed it).

**Tuur's Q-picks (all locked 2026-07-21):**
- Q1 band YES — the Queue grows a collapsed "○ Not in the pipeline · N" band (gate drawn as a boundary).
- Q2 band "Process" writes significance **0.1** — NEW Mac→cloud write direction for that field (same
  lane as Keep/Restore); phone will show Mac-set "0.1 · Passing". Accepted.
- Q3 zombie = **"Parked"**, per-row copy only ("kept — tagged"), NO counting surface.
- Q4 merge Fading + Recently Deleted into ONE "On its way out" conveyor, verb **"Bring back"**;
  sweep moves off Review-refresh onto a DAILY TIMER (shown dates must be true). Phone ⋯ = one item.
- Q5 answered by DISSOLVING the premise: Mac-only files exist only because the Bonjour-era upload
  path predates CloudKit and nobody taught it to author a Memo (verified: zero `Memo(` constructions
  in the desktop app). Direction: **Mac captures author a Memo (+ audio MemoAsset) and sync like any
  note** — both devices are collectors; new build step ⑤ + one-time backfill for existing UUID-id
  local rows. Until ⑤ lands, deleted Mac-local files ride the Review trash as a tiny transitional tail.
- Q6 retire the `processAllSyncedMemos` Settings toggle once the band's "Process all N" exists.
- Q7 copy trio SIGNED: "starts fading <date>" (30d) · "moves to Recently Deleted in Nd" (60d) ·
  "gone for good in ~Nd" (74d) — every surface both apps, verbatim from the spine.

**Build order — ✅ ALL BUILT 2026-07-21 via a 3-lane Sonnet batch (SURF ②③④ / AUTHOR ⑤ /
PHONE parity; briefs = `LANES-2026-07-21/`), Fable conducting. Integrated gate green: desktop
full unit suite + MLX build, phone full unit suite; conveyor snapshot vision-checked.**
- [x] ① the spine — `Shared/Pipeline/MemoSpine.swift` + twin `MemoSpineTests` (11 green each app).
- [x] ② Queue band "○ Not in the pipeline · N" (collapsed, hidden at 0) + per-row/all Process
      (=0.1 + `reconcileSoon()`) + `UnpipelinedMemoSheet` replaces the RootView:34 dead-end flash;
      Q6 toggle UI removed. Testable logic in `Pipeline/WayOutRules.swift` (27 tests).
- [x] ③ ONE trash: queue sheet + footer retired (footer row now jumps to the Review shelf via
      `AppModel.reviewShelf`); `RecentlyDeletedView` (Mac) deleted; MacCloudDeleteSync kept.
- [x] ④ conveyor: `WayOutColumn` = "On its way out" (fading + deleted + Mac-only tail, soonest
      first, ONE verb Bring back = keptAt+undelete); `LifecycleSweepScheduler` daily-timer sweep
      (launch + day-change + 24h) replaces sweep-on-Review-refresh; spine one-liners throughout.
- [x] ⑤ Mac authors Memos: `MacMemoAuthor` (author/backfill/reflectTranscripts, 0.1 floor,
      idempotent, demo-row guard) hooked into the reconcile sweep + instant on upload; 13 tests.
      NOTE: the in-UploadService instant hook was REVERTED by the lane (Pipeline/→App/ breaks the
      host-less test compile) — instant authoring is via reconcileSoon() post-ingest instead.
- [x] Phone parity: ⋯ menu → ONE "On its way out (N)" (`WayOutView` absorbs FadingShelfView +
      phone RecentlyDeletedView; unread-dot semantics untouched; hard-delete kept phone-side).
- **Conductor catches at the gate:** #Predicate can't capture a model property (hoist first);
  `-snapshot-trash` had to move writePNG→hostPNG (ImageRenderer blanks ScrollView rows — the
  header said 5 over an empty body until vision caught it).
- **✅ Tuur's live eyeball round (2026-07-21, same day) — 7 findings, all fixed:** (1) band
  double-homed FADING notes (one-home violation — now New+Parked only, fading-exclusion test
  added); (2) band expanded list unbounded/unscrollable → bounded ScrollView; (3) rows now
  open a read-only PEEK (band → Process, conveyor → Bring back; same UnpipelinedMemoSheet,
  action-parameterized); (4) "✕ Back" text → clear "‹ Back" accent capsule (conveyor + map);
  (5) Review-card importance dots uneven → whole-pixel pitch (5+3); (6) Mac "Queue" renamed
  **"Notes"** to match the phone (SharedCopy.notesTitle, single-sourced both apps); (7) the
  Queue-side "Recently Deleted · in Review" footer row CUT (one home = the conveyor row) +
  dead plumbing removed (wayOutFooterCount, trashedFiles pass-through).
- **✅ Round 3 (2026-07-21): the band is DEAD — one list, like the phone.** Tuur: "flag = it just
  moves into the notes, right?" = correct, and proof the two-container model failed. Unrated memos
  now render as QUIET ROWS interleaved by date in the Notes list itself (dimmed, hollow ○, no
  badge; tap → peek with "Flag for processing"); chips gain **Not rated** (sort control moved up
  to the count line for width); count line reads "N ready · M to process · K not rated"; "Flag
  all K" appears only in Not-rated mode. Conveyor centered like the river. Verbs locked: **Flag
  adds to the pile, Process runs the pile.**
- **LOCKED (Tuur, 2026-07-21): search does NOT include Recently Deleted.** Considered after a
  live "searched a deleted note, no matches" moment and rejected — the trash-excluded idiom
  stands (fading ≠ trash: fading IS searchable per b92). Don't reintroduce.
- **✅ b92 (same eve) — discoverability without a tour:** search finds FADING notes again
  (no-bad-info: "no results" about a recoverable note was the worst answer to "where did my
  note go" — phone hits wear an amber 'fading' capsule, Mac quiet rows self-mark via the
  one-liner; browse mode untouched, conveyor stays the one home) + an untouched note's
  DETAIL narrates its own lifecycle ("starts fading 19 Aug — rating or editing keeps it",
  live-hidden on any touch). PARKED → standalone onboarding phase: first-launch framing +
  a once-ever first-fade explainer card (STANDALONE_PLAN / standalone-onboarding.html).
- **✅ Q-PLACEMENT locked 2026-07-21 (b91): pick B** (mock `wayout-phone-placement.html`,
  Tuur: "B for sure — mac and phone are similar; fading is 3 days old, no habit to protect").
  The phone conveyor's one home = a quiet row at the BOTTOM of the Review feed (Mac-rail
  idiom, non-empty only, amber unread dot moved onto the row — a custom tab-icon dot isn't
  drawable in SwiftUI tabItems); the Notes ⋯ shelf entry + its dot RETIRED. Same session:
  b89 map port (owned camera, dive, in-frame card) + b90 fixes (card scrolls all notes,
  dive never zooms out, gestures clear selection, WayOut rows peek w/ Bring back — Mac parity).
- **✅ Build 88 ON DEVICE 2026-07-21** (iPhone 13, install verified via dylib string-grep):
  merged "On its way out" shelf, flag-to-process microcopy, shared taxonomy glyphs, spine
  one-liners. Device eyeball = Tuur's next phone session. Round 4/5 same-day extras: shared
  SourceTaxonomy (4 hardcoded copies → 1 Shared file + twin tests incl. SF-Symbol-validity),
  count-line tooltip fixed (whole-line hover) + 3-state explainer, quiet-row icons taxonomy-true,
  count line unwrappable. **OWED:** Tuur's live eyeball of the unified Notes list (Mac) + the
  phone b88 walkthrough; prod promotion later as usual.

## ⭐ CONTINUE HERE (2026-07-18 remote session; merged + sim-verified LOCALLY 2026-07-19)

Branch `claude/note-thumbnail-update-bug-tuhrp3` ✅ MERGED to main 2026-07-19 (conflict in this file
resolved: 07-18 sections stacked above the ⚡ perf audit). Thumbnail fix ✅ SIM-VERIFIED: all 8 new
MemoModelTests green, unit suite 742 green (19 UI-suite fails = the known iOS-26 cluster + a
testmanagerd runner crash mass-kill — unrelated areas incl. Safari-ext/vocab; not this change).
1. **Device eyeball owed — build 87 INSTALLED on the phone 2026-07-20** (supersedes 86; includes the
   audit fix waves — one build serves BOTH rounds: this repro + AUDIT_FIX_TESTLIST's top-4 smoke).
   Thumbnail repro: 3-photo memo → delete photos 1–2 in the editor → row thumb becomes photo 3; delete
   all → tile disappears; share-capture + still-transcribing rows keep thumbs. (Audit waves verified
   composed with this fix 2026-07-20: wave 2 rebuilt the row thumb ON `thumbnailPhotoFilename`;
   718/718 unit green re-run independently at audit HEAD, all thumbnail tests in.)
2. Then pick a lane from the two 2026-07-18 sections below: 📤 exportability (attachments = phone-parity
   chunk, brainstorm owed on phone mechanics; lat/lon frontmatter = small buildable chunk), 📍 place notes
   (design session).
3. NEW LANE (2026-07-19 remote session): 📖 ePub↔audiobook alignment — researched + spike-boarded
   (section below). Spikes 1–2 first: Tuur supplies 2–3 real book+ePub pairs; `-asrsweep` ground
   truth on the Mac (punctuation? glued words?). 5 open decisions at the section bottom.

## 📍 Place notes with feeling — "the pin you actually act on" (Tuur direction 2026-07-18; NEEDS DESIGN SESSION before code)

The thesis (verbatim intent): a Maps pin ("to eat") is a dead TODO — it never gets acted on. A voice note
recorded AT the moment ("we walked past a restaurant, Brooks said we should eat there") carries the feeling,
so browsing your notes re-evokes why you cared and you actually engage. Skrift already half-does this;
make it explicit and close the loop.

What EXISTS today (so the design session starts from truth, not memory):
- Recording auto-attaches location + placeName (`MetadataService`); rows carry place chips; place filter + search.
- Share an Apple/Google Maps pin INTO Skrift (D6, `PlaceLink.swift`) → capture item with the same location
  metadata + chip; voice-annotatable. Gap: short `maps.app.goo.gl` links stay plain link cards (opaque
  without a fetch, E4) — and the Google Maps iOS app shares exactly those short links.
- Places map on the phone (`JournalMapView`, Journal tab v1 2026-07-07): pins clustered by place → that
  place's notes. Mac/iPad map-behind-Places is in the signed-off journal-desktop v2 mock (not yet built).
- Reminders are TIME-only (`remindAt` + ReminderScheduler, synced). NOTHING resurfaces a note by PLACE.

Candidate directions for the design session (none decided):
1. **Place-triggered resurfacing** — the literal fix for "and then it doesn't really happen": near the
   restaurant → the note (with your voice from the moment) knocks. iOS geofencing / UNLocationNotificationTrigger;
   fits the existing reminder model as a WHERE alongside remindAt's WHEN. Region limits (~20 monitored) need
   a nearest-N strategy. Privacy: all on-device.
2. **Explicit intent facet** — "I was here" (journal) vs "I want to go back" (to eat / to visit / to try).
   Makes "places I still owe a visit" browsable on the map + filterable; folds into the unified source
   taxonomy work. Could be as small as a tag idiom the UI understands.
3. **Capture friction** — resolve short goo.gl links (needs one fetch — revisits E4); surface the
   share-a-pin flow in onboarding/empty states so the D6 path is discoverable at all.
Related ledger: journal-desktop board (backlog "CONTINUE HERE — desktop-parity"), unified source taxonomy
(CLAUDE.md open cross-app work). Mock-first applies — no code before a signed-off design.

## 📤 Full exportability — markdown as the durable home (Tuur principle 2026-07-18)

The principle (verbatim intent): as features get more complicated, ALL data stays fully exportable — as
much as possible lives in markdown, the app is a smart VIEWER over it. Honest boundary: CloudKit stays the
sync spine (locked 2026-06-15, STANDALONE_PLAN — file-based sync explicitly rejected), so the realistic
form is **the vault is a complete, continuously-published MIRROR**: if Skrift vanished tomorrow, the
markdown + files beside it carry everything human-meaningful. App-internal by nature (document, don't
pretend): word-timing JSON (karaoke), voice embeddings, sync/provenance state; locked notes stay out of
the plaintext vault BY DESIGN.

Already true today: one-way create-only publish into `<vault>/Skrift/` (`ObsidianPublisher`, sticky paths +
hash idempotency + user-edit backoff); body syntax is portable markdown (tasks `- [ ]`, `[[Name]]` links,
photo embeds); Mac polish auto-upgrades the export; speaker turns survive as `**Name:**` text.

Export-completeness GAPS (2026-07-18 code check — the audit's starting list):
1. **Attachments never reach the vault FROM THE PHONE** — phone publish writes ONLY the `.md`. The MAC
   already does this right (`VaultExporter`): `.md` at vault root, audio → audio subfolder, images →
   attachments subfolder (Settings: vault + "Audio subfolder"/"Voice Memos" + "Attachments subfolder"/
   "Attachments"), `[[img_NNN]]` → `![[<title>_NNN.ext]]` embeds. So this is a PHONE-PARITY chunk, and the
   Mac's settings model + embed-naming scheme is the prior art — phone must converge on the SAME filenames
   so both devices publishing one memo don't fork. Tuur 2026-07-18: ✅ wanted; **brainstorm session owed on
   the phone mechanics** (subfolder scheme, audio-by-default or not, security-scoped copy costs, idempotency
   for binaries).
2. **Location coordinates dropped** — frontmatter carries placeName only (`MemoExporter.compilerMetadata`
   AND desktop path); a place note loses its pin outside the app. Direct dependency of the 📍 place-notes
   direction above.
3. **YAML carries ALL metadata — Tuur decision 2026-07-18** ("even steps if we want to" — steps ALREADY
   exports, Compiler.swift:104 😄). In today: title/date/author/source/people/book·bookAuthor·chapter/url/
   location(name)/weather/pressure+trend/dayPeriod/daylight/steps/tags/significance/summary. To ADD:
   lat/lon, duration, createdAt/editedAt, remindAt. Stays internal: sync/provenance state, confidence,
   OCR text (derived; revisit if search-outside-app matters).
4. **Audiobooks — export the USER'S layer, not the book** (answer to "what of the book do we need?"):
   quote captures already export as memos with book frontmatter ✓; **bookmarks don't** (per-book
   `bookmarks.json` — position markers by design, `Bookmark.swift`) — export them into a **per-book index
   note** ("Book — Author.md": book frontmatter, bookmark list ch·timestamp, links to that book's capture
   notes) = the vault face of the roadmap **Commonplace Book** node. NOT exported by default: the audio
   (user's imported property, huge), the whole-book transcript (derived, bulk — on-demand at most),
   positions/detected chapters (ephemeral/app data).
5. No completeness surface — nothing answers "is my vault a full mirror?" (published/skipped/backed-off counts).

First chunk when picked up: field-by-field audit table (→ lands in frontmatter / body / file beside /
app-internal-documented), then phone attachments-parity + lat/lon frontmatter. New frontmatter keys =
contract change → mirror phone `MemoExporter` + Mac `Compiler` in the same pass (no drift).

## 📖 ePub ↔ audiobook alignment — the book text becomes the source of truth (Tuur idea 2026-07-19; RESEARCHED same session, 4-agent fan-out; spike board ready, NOT built)

The idea (verbatim intent): attach the book's ePub alongside the audio; after transcribing, match
transcript ↔ ePub and use the ePub as the source of truth. Read-along/reading mode then shows the
REAL book text (names, punctuation, paragraphs), quote captures export the VERBATIM published
sentence, chapters come from the real TOC; the transcript degrades to a timing layer. Cheap because
the hard half exists: `BookTranscript` sidecars already carry word timings — this is pure
text-to-text alignment, no ML. Prior art ships exactly this pipeline (Storyteller = Whisper + fuzzy
match, sentence-level; we'd be word-level). Amazon/Apple dodge mismatch entirely (matching editions
required / self-generated audio only) — graceful partial alignment would EXCEED the commercial products.

DESIGN (locked by the research):
1. **Aligner**: unique n-gram anchors → LIS monotonicity filter (patience-diff trick) → banded DP in
   the gaps → timestamps onto ePub words, interpolate small holes. Phonetic second signal
   (Metaphone-ish) beside edit distance — ASR mishearings are REAL words ("shore"/"sure",
   Storyteller's lesson). Optional timestamps BOTH directions: transcript-only spans (narrator
   credits) keep ASR text; ePub-only spans (front matter, footnotes) render unhighlighted.
   Per-sentence confidence → per-sentence fallback. Coverage verdicts aligned/partial/rejected; a
   wrong ePub self-detects at attach (near-zero unique anchors). Chapters located INDEPENDENTLY
   (narrators reorder/skip front matter); short generic text (ToC pages) = false-positive bait.
   ePub = ONE continuous text across audio-file cuts (file splits are arbitrary vs book structure)
   even though storage stays per-file.
2. **In-repo ancestor + consolidation**: `Karaoke.wordTimes` (Shared/Pipeline/Karaoke.swift:34)
   already solves the miniature; word-list matching exists in TRIPLICATE (+ `RunFile.anchorDrift`:20,
   inline block RunFile.swift:140) — AlignmentCore is the consolidation point, NOT a 4th copy.
   Adaptations: indexed next-occurrence lookup (kill the linear scan), per-file windowing.
3. **Integration surface is TINY**: `BufferSentence` (QuoteCaptureProcessor.swift:6) is the
   boundary — read-along (ReadAlongView.swift:42) + capture (MergedCaptureView.swift:362) both
   consume `[BufferSentence]` and don't care where `.text` came from. Alignment-backed sentence
   builder at those TWO call sites; seek/bookmark/capture audio-export math untouched
   (`.start/.end/.words` stay from `FileTranscript`). Chapters: ePub TOC just populates
   `detectedChapters` → every consumer follows (`Audiobook.effectiveChapters`:236). DECIDE
   precedence: ePub TOC > transcript-detected > embedded (ChapterDetector doc currently claims
   "THE standard", ChapterDetector.swift:5).
4. **Storage/sync** (mirrors transcripts exactly): `alignment_f<n>.json` beside `transcript_f<n>.json`;
   `FileAlignment{schema, fileIndex, transcriptSignature, epubSignature, alignedUpTo, sentences:
   [AlignedSentence{text, start, end, wordStart, wordEnd, confidence, epubAnchor}]}`. Sync =
   `AudiobookAudioTransport` verbatim: `ab_<bookID>_a<n>` records + additive
   `AudiobookSyncRecord.alignmentSignature`; send/receive/RESTAMP mirroring
   AudiobookCloudSync.swift:356-409. Triggers: BookTranscriptionJob.swift:250 (beside
   `detectChaptersIfNeeded`) + the `AudiobookSession.open` retro-hook (:120) + on ePub attach.
   ePub file: new additive `Audiobook` field; attach UX reuses the `PendingAudiobookImport`
   confirm-sheet pattern.
5. **ePub parsing (HARD PREREQUISITE — zero zip capability exists in the project today)**:
   ZIPFoundation (MIT, zero transitive deps — SPM dep #2 after FluidAudio) + strict `XMLParser`
   for container/OPF/NCX/nav; LENIENT fallback for spine XHTML bodies (real files: `&nbsp;`-style
   entities + malformed markup hard-fail XMLParser) — libxml2's own HTMLparser is on-device
   (bridging header, no new dep) or SwiftSoup. Readium REJECTED (iOS-only, 8-package graph,
   rendering-shaped); EPUBKit doesn't solve the hard part. Footnote exclusion: `epub:type="noteref"`
   + class/id heuristics (semantic markup inconsistently used in the wild). Also accept .txt/plain
   HTML as book text (Gutenberg; dodges DRM). DRM: `encryption.xml` alone ≠ DRM (allowlist the two
   font-obfuscation algorithm URIs); ADEPT = `rights.xml` present; unknown algorithm → treat as
   protected, honest message, never bypass. FairPlay ePubs don't exist as loose files — no detector.
6. **ASR reality check (the load-bearing surprises)**:
   - PUNCTUATION CONTRADICTION: FluidAudio's own Benchmarks.md says Parakeet TDT v3 = "no
     punctuation"; NVIDIA's card + OUR device history say otherwise (lost-period truncation bug
     ChunkFusion.swift:66, the "Dr."-split report backlog:3768 — both only make sense if periods
     are normally present). Settle empirically via `-asrsweep` BEFORE designing sentence segmentation.
   - WORD-GLUING upstream bug (FluidAudio #683), confirmed on our pinned v0.15.2: long-form chunk
     merge splices ignoring SentencePiece `▁` word starts → "wordonewordtwo" possible at every ~15s
     INTERNAL seam. FIXED upstream v0.15.3 + v0.15.5 — our 2026-07-11 pin (7f963cdc) predates both.
     Aligner must tolerate glued tokens regardless; consider a pin-bump chunk (device-verify,
     TrEngine precedent).
   - NUMBERS are confidence-dependent, not guaranteed digits: "ITN usually emits digits"
     (ChapterDetector.swift:590) BUT the spelled-out EN+NL parser exists because both occur; the
     Dutch `-asrsweep` A/B showed the SAME years as correct digits when decoding well, Dutch
     number-words when drifting. Canonicalizer = port/reuse `ChapterDetector.parseNumber`
     (EN+NL cardinals/ordinals + glued Dutch compounds).
   - FluidAudio ships an UNWIRED `TextNormalizer`/ITN (deferred, backlog:2244) — decide: wire it
     pre-aligner vs normalize inside the aligner.
   - Timings run slightly LATE (the ReadAlongView 0.1–0.2s `lead`, :8) — display tuning only,
     alignment math unaffected.
   Normalization ruleset: case-fold; strip punctuation to MATCH KEYS (display keeps original);
   number canonicalization EN+NL; tolerate glued/duplicated/mis-substituted seam words. NOT needed:
   filler stripping, contraction expansion, hyphen-specific rules.

SPIKE BOARD (in order; 1–5 are the research, 6 is the feature):
1. 🟡 Pair #1 DELIVERED (Tuur, 2026-07-21): Steal Like an Artist ePub (in ~/Downloads,
   libgen filename with a LEADING SPACE; keep OUT of git — copyrighted). DRM-free (bare
   container.xml), EPUB2 (OPF+NCX), 10 real chapter titles in the NCX, 9,767 words + 108
   images. 1–2 more pairs still wanted — ideally one matching-edition pair and one messy one.
   **⭐ PYTHON PROBE (2026-07-21, scratchpad — pre-spike-5 de-risk, vs the REAL phone
   sidecars):** the audiobook is the TRILOGY (4 files, ~39,400 words); the ePub is book 1 only —
   and per-file verdicts resolve it perfectly: f0 matched 6,515 unique 4-gram anchors, 96%
   monotonic, spanning words 121–9102 of 9106 (≈98% coverage; ~1 anchor per 1.4 words); f1–f3
   matched ~40 non-monotonic anchors each = noise floor. RIGHT-vs-WRONG book separation ≈
   150:1 — the attach-time self-detect is empirical fact, thresholding is trivial. Only TWO
   >30-word unmatched spans in the whole hour: the 121-word narrator/publisher intro (the
   predicted transcript-only span) + one 35-word epigraph quirk at 3.6min. Kleon's
   hand-lettered image pages = NON-issue here (narrator doesn't read them / text also in
   body). Image alt texts are all FILENAMES → alt is never book text. Spike 5 (Swift
   AlignmentCore + -aligncheck + thresholds) proceeds on a de-risked bet.
2. ✅ ASR ground truth (2026-07-21, real device sidecars + Mac `-asrsweep` on a real audiobook
   chunk — findings):
   - **PUNCTUATION: PRESENT, both apps.** Phone sidecars (Steal Like an Artist ×4, on the
     7f963cdc pin): ~650 periods/hour + commas + question marks + capitalization. Mac
     `-asrsweep` on Man's-Search preface mp3: same. Benchmarks.md's "no punctuation" claim is
     REFUTED for our path — sentence segmentation MAY use ASR punctuation as a signal.
   - **#683 gluing on our pin: REAL but RARE.** 4.5 h of current-pin transcripts → ONE true
     seam artifact: `works.eep` ("works. Keep" with the K eaten). Old-pin June transcript adds
     `Co.oper` ("Cooper" split by an inserted period). So the damage class = glue + eaten
     leading letter + seam-local punctuation corruption, ~1 per 4.5 h — the aligner's
     tolerate-glued-tokens requirement stands, and per-sentence confidence absorbs the rest.
     Pin-bump (spike 3) is thus justified-but-not-urgent, data in hand.
   - Sweep variants: mel-off (B/C) diverges 14% of words from the old default; dual-decode
     alone (D) = 0% — knob effects confirmed on audiobook audio. (Sweep's one-shot API covered
     the opening ~2 min of the chunk; enough for the punctuation verdict.)
3. ✅ Pin BUMPED v0.15.2 → v0.15.5 (2026-07-21, Tuur-approved "fix the bug"): both project.ymls
   → 19600a48 (the v0.15.5 tag). Gate: desktop full build + suite green, mobile 743 unit tests
   green (the 2 UI fails = the known iOS-26 cluster), `-asrsweep` C-variant output
   WORD-IDENTICAL old-vs-new on the preface chunk (seam fixes only touch long-form merges),
   phone b93 built + installed (device lists 93), Mac Dev redeployed on v0.15.5. OWED: next
   real whole-book transcribe should show works.eep-class artifacts gone (falsifiable on the
   next book Tuur transcribes; don't re-transcribe 4.5h just for this).
4. ✅ **EPubParse SHIPPED 2026-07-21 eve** (LANE_EPUB, first LANE_PLAYBOOK batch =
   `LANES-2026-07-21B/`): `Shared/Pipeline/EPubParse.swift` — PURE Foundation (unzip stays
   app-side; ZIPFoundation 0.9.20 revision-pinned, desktop target only for now), spine-ordered
   blocks, NCX+EPUB3-nav TOC, lenient entity/malformed-markup fallback, DRM verdict w/
   font-obfuscation allowlist, footnote/img exclusion. 12 twin tests green both apps.
   REAL-BOOK smoke (Steal ePub): DRM none, 314 blocks / 9,670 words, all 18 TOC titles clean.
5. ✅ **AlignmentCore + `-aligncheck` SHIPPED same eve** (LANE_ALIGN + conductor harness):
   `Shared/Pipeline/AlignmentCore.swift` — unique-n-gram anchors → LIS → banded per-gap DP
   (match/sub/ins/del + glue ops incl. eaten-letter), EN+NL number keys, interpolation,
   Config-tunable thresholds, 10-largest-spans reporting. 12 twin tests green both apps
   (1 gate catch: an LIS test must MOVE a block, not COPY it — duplicated shingles lose
   uniqueness before LIS ever runs). **REAL-PAIR VERDICT (the board's GO/NO-GO): GO.**
   `-aligncheck` on the Steal ePub × all 4 trilogy sidecars: f0 ALIGNED (coverageBook 86.9%,
   7,639 anchors, 95.5% monotonic, 123 ms for 9k×9.7k words); f1/f2/f3 REJECTED (2–7%
   coverage, ~25% monotonic). DEFAULT THRESHOLDS HELD — note: wrong-book coverage can reach
   ~7% (trilogy-sibling phrase bleed), the MONOTONIC gate is the real discriminator. The
   narrated-but-image-only pages (logbook / What Now? lists) surface exactly as honest
   unmatched transcript spans.
6. ✅ **PRODUCTIZED 2026-07-21 night (batch C = `LANES-2026-07-21C/`, 2 Sonnet lanes +
   conductor pre-ship; THE SEAM COMPILED FIRST TRY — 805/0 mobile unit tests):**
   - Pre-ship: `Audiobook.epubFilename`/`epubChapters` + `effectiveChapters` precedence
     (ePub TOC > detected > embedded, Q1), ChapterDetector doc amended, ZIPFoundation into
     the iOS app target.
   - CORE: `BookAlignment.swift` — `FileAlignment`/`AlignedSentence` (published text +
     per-word times + transcript word-range + confidence + chapter marks) + store +
     `BookAlignmentRunner` (attach / alignIfNeeded, security-scoped, .txt freebie) +
     triggers (transcribe-finish + book-open retro) + CK sync `ab_<id>_al<n>` mirroring
     transcripts (receiver holds application until its transcript matches, then derives
     epubChapters). Lane call worth keeping: adjacent same-file EPubBlocks MERGED before
     aligning (AlignmentCore resets word indices per block — unmerged would corrupt
     sentence ranges; `-aligncheck`'s 1:1 bridge is fine for its coverage-only use).
   - UI: `AlignedSentenceSource` (nil unless fresh + verdict aligned; sentence < 0.5
     confidence splices its ASR words via the existing builder) + ReadAlongView/
     MergedCaptureView swaps (trim/audio-export math untouched) + library context-menu
     "Attach book text…" (fileImporter .epub/.txt, verdict toast, wrong-book alert
     Keep-anyway/Remove, "Replace book text…" when attached).
   **✅ DEVICE ROUND 1 (Tuur, 2026-07-22 am) → fix wave SHIPPED same hour (b95 INSTALLED):**
   three findings, all fixed + verified: (1) **highlight trailed the narrator** — the
   sentence assembly linearly re-distributed each matched range's time span across its
   words, drifting seconds over natural pauses (measured on the phone's own f0 sidecar:
   85.4% of words >0.3s off, sentence-END lag median +1s / p90 +5.6s). AlignmentCore now
   surfaces the DP's per-word times verbatim (`MatchedRange.wordTimes` + `direct` flag),
   assembly consumes them, confidence = direct fraction; re-measured offline on the same
   real pair: **median drift 0.0000s, 2.07% >0.3s**. `FileAlignment` schema 1→2 →
   attached books silently re-align on next open. (2) **phantom chapters** — REJECTED
   trilogy-sibling files claimed the 6 front-matter TOC entries f0 couldn't
   (`assignChapterMarks`/`epubChapters` had no verdict gate; f1 carried 6 junk-timed
   marks). Both derivation points now aligned-only + a cheap self-heal re-derives
   `epubChapters` on book open. (3) **"no indication anything changed"** — the outcome
   was a 1.6s toast fired after seconds of silent processing; now a persistent
   "Checking the text…" busy toast + explicit user-dismissed ALERTS, incl. honest
   multi-book copy ("matches N of M — likely one book of a multi-book audiobook").
   Mobile 808/0 + desktop suite green. Sync note (accepted, iPad-scale): a receiver
   holding v1 sidecars whose source signature didn't change won't re-pull until the
   next signature change — irrelevant while the phone is the only aligner.
   **✅ b95 DEVICE-CONFIRMED (Tuur, same hour): "way more fucking aligned… chapters are
   better" — sync fix + phantom-chapter fix both pass ears/eyes.** Follow-up caught by his
   trilogy question: "ePub TOC wins" was WHOLE-BOOK, silently deleting books 2–3's
   transcript-detected chapters (no-bad-info violation) → partial-match MERGE shipped
   (ePub chapters inside aligned files' spans + detected chapters/separators outside;
   boundary entries belong to the next file). 809/0. **b96 BUILT + signed — phone went
   offline again mid-install; one `devicectl install` when it's back**, then the chapters
   sheet shows book 1's real TOC AND books 2–3's detected chapters with their Book-N
   separators. REMAINING (eyes, b96):** AirDrop the Steal ePub to the phone (Files) →
   Books → long-press Steal Like an Artist → Attach book text… → expect "Aligned 1 of 4
   files" (the trilogy: file 1 = book 1, rest honestly rejected) → read-along shows
   Kleon's REAL sentences in file 1 (ASR elsewhere) → capture a quote there = verbatim
   published text → Chapters sheet shows the ePub's real 18-entry TOC.

**📖 ROUND 8 (2026-07-23, the VERIFY session's real-data catch — the actual root cause of
round 6's sighting): `mergeSentences` ate same-text sentences.** Verifying rounds 5–7 on
device surfaced it: the schema-4 re-align healed chapters (R5 ✅ live: devlog "re-adopted
orphaned attached texts" + "toc [40] → 29 marks → 29 epub chapters"; library.json now
persists all three attach fields; real TOC titles) — but BOTH repro spots stayed empty and
`bridged=0`. Offline reproduction (new env-gated `OdysseyRealDataDiagnostics` harness: the
pulled phone ePub + transcript through parse → align → assemble → merge) showed the aligner
had matched both sentences at conf 1.00 ALL ALONG — the align result is bit-deterministic
(coverage identical to 16 digits, device vs sim) and produces 7,506 sentences; the device
sidecar held a strict 7,310-subset. The eater: `mergeSentences` contested collisions WITHIN
one text's own fresh batch — adjacent sentences legitimately overlap by seam fuzz (exact
per-word times straddle sentence boundaries: "(andra)." ends 165.8, "He is not 'the' man…"
starts 165.6), same text = same rank, and the strict-win tie rule silently dropped the later
one — 196 of 7,506 (~2.6%), including both user-reported holes. Rounds 6+7's fills were
built to paper over what was actually this merge bug downstream (the bridge/gap-fill layers
stay — they cover TRUE aligner misses). Fix: collisions contest BETWEEN texts only
(`result[$0].textFile != ns.textFile`); schema 4→5 so every persisted subset sidecar
re-aligns once on next open. Suite: 894/0 incl. the real-data harness asserting
merged=7506 of 7506 + the Trojan-War sentence surviving the merge, and two new
`MultiTextMergeTests` regressions (seam-overlap survives / between-text contest intact).
Device: b109 installed, re-heal launch owed (phone re-locked). DURABLE LESSONS: (1) verify
derived DATA end-to-end on real inputs, not just the layer you changed — assemble alone
looked perfect, the sidecar was wrong; (2) a "collision rule" needs an explicit answer for
SELF-collisions. Also for the record: -resumeBook DEBUG launch hook added (headless device
verify via devicectl); untriaged b105-era crash 09:49 pulled (SIGKILL during a CoreData
fetch — watchdog-flavored, pre-branch; feeds the pre-promotion profiling item).
**P2 re-align freeze — ✅ ADDRESSED b113 (2026-07-23, same session; device verify OWED).**
Report (Tuur, ~14:15 on b109): tap a book, then no book responds ("frozen… maybe stuff's
happening in the background — annoying"). What the code review found + fixed:
- **PROVEN main-thread defect:** `BookAlignmentRunner.textSummary` is `@MainActor` and fully
  decodes EVERY attached file's alignment sidecar (9.1 MB / 7,506 sentences with per-word
  timings on the real Odyssey) — and `BookTextSheet.summary` called it on **every `body`
  evaluation**. Now a `nonisolated` overload (record + directory in) loaded ONCE off-main
  into `@State` via `.task(id:)`, keyed to the things that can actually change it; the
  sheet's detent decision uses a record-only check instead of a decode.
- **Starvation mitigation (not a proven root cause — needs the device to confirm):** the
  re-align's detached task dropped `.utility` → `.background` + `Task.yield()` between
  files, so the ~12-min heal yields to the UI.
- **Visibility (the honest UX fix regardless of cause):** new `BookTextActivity` observable
  (set by the runner, one active book) → the library row shows a spinner + live stage
  ("Reading the text…" / "Matching the text…" / "Placing chapters…") in place of its
  time-left line, and the Text sheet shows the same stage + "You can keep listening while
  this runs." A heal can never again look like a hung app.
**OWED:** b113 is built + suite-green but NOT installed — the iPhone dropped off USB at
15:20. Install and confirm on the next device round (trigger a re-align via Re-check).
Also: an app-killed-mid-align restart currently restarts the whole file from scratch —
fine at 1 file, worth per-file resume if multi-file books grow. And the align dies with
the app on lock when nothing is playing — the "keep listening" advice is real; consider
a BGProcessingTask ride-along for the heal case (parked, standalone-phase candidate).

**📖 ROUND 7 (Tuur 2026-07-23, going over rounds 5+6): four items, all handled (same
branch `claude/epub-chapter-discrepancy-wlgvhd`).**
(1) **"If it had actually put in the whole ePub that was working"** — right: round 6's ASR
gap fill is the fallback, not the fix, when narration == book text. NEW (schema 4): a hole
run SANDWICHED between two timed sentences re-emits the BOOK sentences with times
interpolated across the gap (`AlignedSentence.bridged`), gated on corroboration — the
window's spoken-word count must be 0.5–2.0× the book words (a silent window = narrator
truly skipped it → still dropped, ASR fill owns leftovers). Confidence stays 0 (honest);
the flag drives book-text rendering; collision rule unaffected (bridge loses to any real
match). Schema 3→4 forces every attached book to re-align on next open, so the Trojan-War
sentence should come back as REAL book text, not ASR. Layering now: exact book text >
bridged book text > ASR splice > ASR gap fill.
(2) **13 h attach: no progress, "can I keep listening?"** — the busy line now follows the
runner's live stages ("Copying the file in…" / "Reading the text…" / "Matching the text…
(file k of n)" / "Placing chapters…") + a standing sub-line "You can keep listening while
this runs." (true — playback never contends). Real % inside ONE file's matching would need
an AlignmentCore progress callback (single DP pass) — parked as a candidate.
(3) **ePub while still transcribing** — now DELIBERATE: attach mid-transcribe copies +
records the text but defers alignment (alert: "still transcribing — it will match up on
its own the moment transcription finishes"); `alignIfNeeded` no-ops while the job runs
(the job's own finish call does the real pass) — no more bogus verdicts off a partial
transcript, no churn from player opens.
(4) **Unify transcribe + book-text menus** ("both are about adding text — two levels") —
DESIGN, so mock-first: `mocks/book-text-unified.html` proposes ONE "Text…" verb/sheet:
Level 1 Transcript (status/progress/Transcribe), Level 2 Book text (today's signed-off
sheet unchanged), incl. the mid-transcribe deferred state. Follow-up (Tuur 2026-07-23,
from the phone): + an **A0 import-moment state** — a once-only post-import prompt offering
BOTH actions together ("start both and walk away; the ePub matches up on its own when
transcription finishes") — the import→transcribe→auto-match chain already works in code
(rounds 5–7); A0 makes it visible. **✅ SIGNED OFF 2026-07-23 (verify session, all 4
phones walked) — build board = the ⭐ item-0 note above; roadmap idea i12. Not built.**

**📖 ROUND 6 (Tuur 2026-07-22 ~23:11–23:16, Odyssey): read-along DROPS spoken text —
FIXED (same branch `claude/epub-chapter-discrepancy-wlgvhd`).** Two sightings, one bug:
(a) red-line at ~3:00 — narration between "(andra)." and "The poem tells us…" never
displayed; (b) Apple-Books-vs-Skrift at ~5:35 — "It is not the start of the Trojan War,
which began with the Judgment of Paris…" is in the ePub AND the audio, absent in Skrift.
Cause: the aligned view REPLACED the transcript wholesale — `assembleSentences` drops
zero-timed sentences (aligner holes), and `AlignedSentenceSource` had per-sentence ASR
fallback only for LOW-CONFIDENCE sentences, never for spans with no sentence at all →
silent jumps while the audio plays (Tuur's exact insight: "the transcript is better in
some ways… it has replaced the transcript"). Fix: the display is now a UNION —
`uncoveredWordRanges` finds transcript-word runs no aligned sentence's splice range
covers; runs ≥ 3 words render as ASR sentences via the same builder (1–2-word runs =
boundary fuzz, stay silent). Also fills leading/trailing narration (Audible credits, end
matter) and a partially-matched sentence's untimed tail; capture (`MergedCaptureView`)
inherits it via the shared source. Tests: hole-between-sentences, fuzz threshold,
leading/trailing, no-duplication-with-low-confidence-splices, union/clamp math. Eyes owed
(Tuur, tomorrow): Odyssey ~3:00 and ~5:35 — the missing lines should read along in ASR
text. NOTE the shown ASR fills are the transcript's words (no book punctuation/casing) —
if a fill looks garbled there, that's the aligner MISSING a matchable sentence: next lever
is aligner recall, not display.

**📖 ROUND 5 (Tuur 2026-07-22 ~23:00, Odyssey screenshots): chapters ≠ ePub TOC after
relaunch — ROOT CAUSE FOUND + FIXED (branch `claude/epub-chapter-discrepancy-wlgvhd`).**
Symptom: Odyssey ePub attached + read-along shows the REAL book text (intro), but the
chapters sheet still shows the detected list ("Opening / Part 6 / Part 11 / Part 19 /
Part 20 / Part 24", Ch 1/6 — the detector's structural vote caught only 5 of the 24 spoken
"Book N" announcements; "book" keyword maps to the Part kind, hence "Part N" labels). Root
cause: **`Audiobook`'s hand-written Codable never carried
`epubFilename`/`epubFilenames`/`epubChapters`** — every library.json persist dropped them, so
ANY relaunch forgot the attachment while the sidecars (and read-along) kept working. This is
the SECOND cause of round 2's "fields VANISHED" (the iPad-LWW theory was real but partial —
"re-attach once and it sticks" could never stick; a lone device reproduces it). Fix (5
chunks): (1) the three keys now encode/decode (sync blob still stripped via
`sanitizedForSync` — regression-tested); (2) `alignIfNeeded` RE-ADOPTS orphaned attached
texts from the book folder (disk = durable truth: attach copies in, removeText deletes), so
every already-bitten book self-heals on open — no manual re-attach; (3) title accessors keyed
off `usesDetected` alone → now `titlesAreDisplayReady` (ePub OR detected): with ePub chapters
+ nil detection the sheet rendered EMBEDDED titles against ePub rows (mismatch + index-crash
when the ePub list is longer); (4) `mergeAndFinish` DevLogs toc-counts → marks → derived
chapters (round 5 was undiagnosable from the devlog); (5) TOC parse got the lenient retry the
spine bodies always had — a nav/NCX doc with `&nbsp;`-class entities hard-failed strict XML
and silently yielded an EMPTY TOC (zero marks, broken "real table of contents" promise) — the
OTHER way this same symptom arises with no relaunch at all (both EPubParseTests copies
extended). Tests added (Codable round-trip, store reload, sanitize-strip, ePub-title
accessors, orphan scan, entity-laden nav/NCX). ⚠️ Fixed from a Linux session —
**xcodebuild suite NOT run; next chat verifies** + device-checks the Odyssey book heals.

**📖 ROUND 4 (b101+b102): sheet DEVICE-CONFIRMED end-to-end.** b100 bar verified (one block +
sliver, 22%); "partial"→"full match" tolerance 0.97→0.95 (real f1 = 96.7%, credits absorb);
the 44s calendar-art gap (narrator reads Kleon's hand-lettered calendar page — image-only in
the ePub: "…Don't break the chain." → gap → "Just as you need a chart of past…") was rendering
~5× too wide — the mock-copied 2pt inter-segment spacing is GONE, bar = grey background +
colored overlays at exact fractions, strictly time-true (Tuur: "I do like the truth in this
player"). Interleaved-trilogy theory REFUTED with data (95.5% monotonic = sequential).
Reaffirmed parked: ePub images in the reader (the calendar gap = the demo case).

**📖 ROUND 3 (same session, b100 INSTALLED):** re-attach WORKED on b99 (alert + sheet live on
device) but the bar sprinkled confetti + "37% / 1 h 41" — `textSummary` counted the text's
sentences from files whose per-text verdict was REJECTED; now aligned-files-only (regression
test in). Also dc:title read `.text` on the element but element text lives in `#text` child
nodes → `flattenText`; NOTE the Steal libgen ePub's own metadata has title/creator SWAPPED
("Austin Kleon" as dc:title) — garbage in, honestly displayed, filename fallback covers absent
titles. EXPECTED LOOK on b100: reopen the sheet → ONE contiguous span over the first ~hour,
"~21%", row "~58 min · full match" (row title stays the filename-ish string — the file's own
bad metadata).

**📖 DEVICE ROUND 2 (Tuur live, 2026-07-22 ~14:00) → b98+b99 same hour:** (1) "Book text…"
was library-long-press only; the player ⋯ (where you actually are) now has it — flow extracted
to ONE shared `BookTextFlow` modifier (shared-code-first, both surfaces). (2) **Add button
dead + "No book text attached" LIE** — root causes: a fileImporter attached to the covered
presenting view silently refuses to present on iOS 26 (picker + the 3 outcome alerts now hang
off the SHEET's own content), and the record's attach fields had been ERASED by whole-blob
LWW sync (a device on an older build — iPad suspected — re-encodes the record without
additive fields; on-device sidecar still schema-1 + `epubFilename: None` proved it).
**Doctrine fix: epubFilename/epubFilenames/epubChapters/detectedChapters are LOCAL-ONLY** —
`sanitizedForSync` strips them from every sent blob, `keepingLocalTextFields` preserves them
at all four adopt sites (reconcile receive, session open, adoptSyncedPosition, first-add
strips legacy blobs). Tuur must RE-ATTACH the Steal ePub once on b99 (the erased record can't
self-heal); after that it sticks. ⚠️ If the iPad has an old Skrift Dev, UPDATE it eventually —
it can no longer erase these fields, but other additive fields ride the same risk.

**📖 ✅ MULTI-TEXT + "Book text" SHEET SHIPPED 2026-07-22 pm (batch D = `LANES-2026-07-22D/`;
mock B signed "yess. ur reccomendation"; the pinned-contract seam compiled FIRST TRY again —
858/0):** schema-3 sidecars (per-text sources w/ verdict+coverage, sentences tagged by text,
collision = higher confidence wins/tie = attach order), additive attach (append, re-attach
same file replaces itself), per-text TOC marks unioned, `textSummary` (real global spans,
30s gap-bridge) + `removeText` (surgical detach), 4-field cloud signature. UI: long-press →
"Book text…" opens the timeline-first sheet (bar = real aligned spans colored per text, grey
= transcript; rows w/ dc:title + Remove/Re-check; ＋ Add; busy toast threads into the sheet).
Gate catches: reject-alert Remove now detaches exactly the failed text (lane-flagged), doc
drift fixed. Conductor pre-ship: EPubBook.title (dc:title) + Audiobook.epubFilenames+accessor.
**b97 INSTALLED (device lists 97; includes the b96 chapter merge Tuur never got).
EYES OWED (b97):** open Steal → the schema-3 gate re-aligns silently → long-press → Book
text… → the bar shows book 1's span colored + 3-hour grey tail; chapters sheet = real TOC
then detected Book-2/3 chapters; then someday attach Show Your Work! and watch the bar fill.
CORE2 tabled (fine to leave): 30s gap-bridge untuned; epubChapters' detected-merge span
suppression stays whole-file (revisit only if a partially-covered file miscounts chapters).
(design record, superseded:) mock = `mocks/book-text-sheet.html` — Tuur keeps listening to the
trilogy and will want book 2's/3's ePubs → one-text-per-book graduates to a LIST. Semantics
settled in the chat: alignment is already per-file/per-span, so each new text aligns the spans
it matches and leaves the rest; if two texts claim the same span, the higher-confidence match
wins; NOTHING is ever deleted (un-narrated intros simply get no time; narrated-but-unmatched
spans keep ASR — same as today). Coverage visibility gets a HOME instead of a fleeting alert:
variant A = list-first sheet (rows per text + dimmed "not attached" remainder), B =
timeline-first (one bar = whole audiobook, colored per source, grey = transcript), C = a
"Book text · 2 texts · covers 45% ›" row inside a per-book options screen (placement, opens
A/B as detail). Persist per-file coverage % in the sidecar at the next schema touch (free,
feeds the sheet). Build after the mock pick — likely one lane batch (schema 3: sources array
per sidecar + sheet UI).

Open decisions — **ALL 5 LOCKED (Tuur, 2026-07-21 pm)**:
1. ✅ **Chapter precedence: ePub TOC wins when attached** ("if an EPUB is attached, we're
   gonna use its chapters"); transcript-detected > embedded remains the fallback order;
   ChapterDetector.swift:5's "THE standard" doc gets amended in spike 6.
2. ✅ **Aligner-internal normalization** (raw transcript stays untouched; the matcher treats
   "2026"≡"twenty twenty-six"). FluidAudio's TextNormalizer stays unwired.
3. ✅ **Pin bump: DONE** ("fix the bug, we will do it again" = re-verify round accepted) —
   executed same day, see spike 3 above.
4. ✅ **ZIPFoundation approved as SPM dep #2.**
5. ✅ **Formats: .epub primary** (Tuur: books come as epub, maybe mobi). .mobi = dead format,
   skip in v1 (Calibre converts in one step); keep .txt as a freebie (trivial, Gutenberg).
   Images inside ePubs: invisible to ALIGNMENT; **showing pictures in the reader = PARKED
   for later (Tuur: "we may consider putting pictures in the reader, but we'll push that
   for later")** — a display question for after spike 6, never an alignment risk (probe
   confirmed; alt-texts are filenames, never book text).

## 🐛 List thumbnail stale after deleting photos (reported 2026-07-18, ✅ FIXED same day — branch `claude/note-thumbnail-update-bug-tuhrp3`)

Repro: record with several photos → row thumb = first photo; delete the first photo(s) in the editor →
thumb stays the DELETED photo. Cause: deleting a photo removes its `[[img_NNN]]` marker from the body but
never its manifest entry (markers are 1-based indexes into the manifest — pruning would renumber every later
marker on both apps), and the row blindly showed `imageManifest.first`. Fix: new `Memo.thumbnailPhotoFilename`
(MemoDisplay.swift) = first marker in BODY order that resolves; all markers deleted → no thumb; marker-less
bodies keep manifest-first (share captures render off-manifest, pending/failed transcriptions have no body
yet). Row tile + `hasPhoto` + the "Has photos" filter all ride it (MemosListView). 8 unit tests added
(MemoModelTests). ✅ SIM-VERIFIED 2026-07-19 (all 8 green, unit suite 742 green). **OWED: device eyeball
(build 86)** — delete photos 1–2 of 3, row should show photo 3; delete all → no tile.

## ⚡ Perf + reliability audit — 2026-07-16, VERIFIED 2026-07-19 (5 Sonnet lanes → 5 Opus falsifiers → Fable adjudication; UNBUILT unless ticked)

Wide-net audit of both apps by area; every item confirmed at the cited line. Verification tally: 33/41 confirmed as filed (several understated), 6 downgraded, 1 dropped, 2 corrected, 1 widened — all folded in below. Line numbers drift with ongoing work; items are mechanism-anchored. NEW unaudited surface since the sweep: Connections/retrieval stack (`Shared/Retrieval/` 6 files + `ConnectionsIndexService`) — auditor dispatched 2026-07-19 — findings in the subsection at the end. **FIX WAVE MERGED TO MAIN 2026-07-19** (built on branch `audit-fixes`; Tuur-approved merge; phone/Mac smoke of the testlist top-4 owed). Ticked = fixed on that branch; review artifact = `AUDIT_FIX_TESTLIST.md` on the branch.

**Cross-cutting theme — failures are invisible (`try?` everywhere on the write surface):**
- [x] **P0 `NotesRepository.save()` = `try? context.save()`** (`SkriftMobile/Services/NotesRepository.swift:244`) — the ONE save path for every mobile write incl. the editor's debounced text commit; a throw = user edit silently lost. Log + surface on the editor path. S
- [x] **P1 `MemoSaver.persist()` swallows the temp→dest audio move** (`Features/Recording/MemoSaver.swift:741-742`) — on failure it still inserts a Memo pointing at a file that was never written (phantom memo, orphaned audio). `saveQuoteCapture` ~:511 already does it right (do/catch + abort). S
- [x] **P1 Mac reconciler `try?`-swallows ingest + all saves** (`SkriftDesktop/Pipeline/Ingest/MemoCloudReconciler.swift:70-73`, `+Wiring.swift:77,99`, desktop `NamesCloudSync.swift:46`, `VocabularyCloudSync.swift:58`) — a memo that always fails ingest = silent black hole retried forever, zero trace. Count+log failures. S
- [x] **P2 `VaultExporter` `try?`-swallows image copies (`:152,176,202`) and the phone-edit re-export swallows entirely** (`+Wiring.swift:94`) — vault silently stale/incomplete, `![[embed]]` refs written with no file behind them. Verify bonus: the `:84-85` comment claiming "an export failure is logged by the caller path" is FALSE — nothing logs it; fix the comment with the code. S
- [x] **P2 audiobook raw-CK transport has no CKError-code handling** (`Services/Audiobooks/CloudKitAudiobookTransport.swift`, `AudiobookCloudSync.swift:236-252`) — permanent failures (quota, auth) retry forever, no retryAfterSeconds honored, no terminal UI state. M
- [x] **P3 `runTranscription` catch has no DevLog** (`MemoSaver.swift:817-822`) — `.failed` memos undiagnosable from a device pull. S

**Recording (lane verdict: unusually hardened — session-recovery ladder, ANE time-share, @Observable isolation all excellent):**
- [x] **P1 `save()`'s transcription lacks `BackgroundTask.run` wrap** (`MemoSaver.swift:39-55`) — every import path has it (`:101,141,297`); ordinary record→stop→background-the-app = stuck "Transcribing…" until next launch. S
- [ ] P2 per-buffer `Task { feedStream(out) }` has no ordering guarantee into the caption accumulator (`LiveRecordingService.swift:479-499`) — display-only garble risk; verify on device before hardening. M
- [ ] P2 live-caption rebuilds full AttributedString per poll (`RecordView.swift:644-676`) — only bites when auto-off is disabled (long lectures). M
- [x] P3 `SpeakerVoiceStore.swift` dead code — DONE for free: deleted by SharedKit wave 2e (28efb35).

**Notes UI (mobile):**
- [x] **P1 `MemosListView.filtered`/`flatIndex` recompute the full filter+sort PER ROW** via `.accessibilityIdentifier` (`MemosListView.swift:253,633-639`) — O(N²) per list render; verify found it WORSE: `matches(query:)` JSON-decodes metadata inside the filter, and `groups`/`relatedDisplay` re-access `filtered` in the same body pass. Compute once per body eval. S
- [x] **P1 list photo thumbs decode full-res on main, uncached** (`MemosListView.swift` photoThumb — now keyed off `thumbnailPhotoFilename` since the 2026-07-18 stale-thumb fix) — `MemoImageLoader.thumbnail` exists for exactly this (the "600× with a picture" fix); one-line swap. S
- [x] P2 (was P1 — `[[img_` fast-path covers image-less notes) `NoteBodyView.load()` runs `snappedImageBody` BEFORE the `t == loaded` no-op check (`NoteBodyView.swift:301-314`) — reorder two lines. S
- [x] P2 `Memo.metadata` re-decodes JSON per access (`Shared/Model/Memo.swift:248-251`) — 4-5 decodes per list row per render; cache keyed on data identity. S/M
- [x] P2 `applyTierStyling` re-runs `BodyTransform.pieces(of:)` once PER name span (`NoteBodyView.swift:483-492`) — compute once per pass. M
- [x] P3 (was P2 — early-break scan, tiny constant; repaint already minimal-diff) `Karaoke.activeWordIndex` scans from 0 at 20Hz (`Shared/Pipeline/Karaoke.swift:17-24`) — resume from last index. S
- [ ] P3 (was P2 — fetch is trash-only, usually empty) `purgeExpiredTrash()` runs sync in `SkriftApp.init()` before first frame (`App/SkriftApp.swift:45`) — move to `.task` like every other sweep. S
- [x] P3 Release builds compute `photoHits` corpus scan per search keystroke to feed a DEBUG-only log (`MemosListView.swift:158-167`) — wrap in `#if DEBUG`. S
- [ ] P3 detail pager `@Query` = whole non-trashed corpus (`MemoDetailView.swift:20-21`) — fine now, window it when corpus grows. M/L

**Audiobooks (mobile) — root cause shared by top two: `BookTranscriptStore` has no lightweight read, every consumer decodes the full word array:**
- [x] **P1 `ReadAlongModel.reloadIfNeeded` full-sidecar decode at ~2Hz on main whenever playhead is ahead of the transcribe frontier** (`ReadAlongView.swift:31-49,142-146`) — a designed-for common state. Store-layer fix (cheap `coveredUpTo` read or frontier-advanced signal). M
- [x] **P1 `BookTranscriptionJob.publishValue` re-decodes EVERY file's full sidecar after EVERY chunk, on main** (`BookTranscriptionJob.swift:381-399`) — track covered-seconds in memory. S
- [ ] P2 `QuoteCaptureProcessor.exportSpan` drift — CORRECTED by verify: production passes `PreferPreciseDurationAndTiming` (`:373`), which the measured-bad `-chunksim` export lane did NOT, and live capture paths are self-consistent (audio + word-times shift together). Only `buildOutputFromSidecar` (sidecar times paired with exported audio) is exposed. STEP 0 before any code change: add a chunksim third lane — export WITH the flag — and measure. M
- [x] **P2 failed chunk = permanent silent gap marked covered-with-zero-words, no retry** (`BookTranscriptionJob.swift:226-233`) — retry once or flag for next `start()`. M
- [ ] P3 (was P2 — NSCache hit after first miss; pixel decode deferred to draw) `BookCoverCache.image(for:)` on-main file read in body (`BookCoverView.swift:66-73`) — decode off-main into the existing NSCache. S
- [x] P2 `MergedCaptureView.load()` sentence-parses the ENTIRE covered transcript for a ~90s window (`MergedCaptureView.swift:360-370`) — `ft.words(inWindow:)` exists, unused here. S
- [ ] P3 read-along `setCurrent` linear-scans sentences from 0 at 10Hz (`ReadAlongView.swift:56-60`); P3 `AudiobookCloudSync.localTranscriptSignature` full decode for two scalars (`:325-336`, and it runs on the MAIN actor). Both S. (Dropped by verify: AVAudioFile-reopen-per-chunk — negligible vs the transcribe itself.)

**Sync spine (cross-app):**
- [x] **P1 sync sweeps fault FULL audio/photo blobs into memory — BOTH apps** (WIDENED by verify): Mac `MemoCloudReconciler.swift:42-49` fetches every memo's assets even for already-ingested rows, BEFORE the ingest check, plus N+1 (2-3 fetches per memo); mobile `AssetMaterializer.swift:42` touches `.filename` before its exists-guard and faulting is ROW-level, so its protective doc comment is WRONG (fix the comment too). `MemoAsset.blob` can't be externalStorage (CloudKit). Fix: metadata-only reads (`propertiesToFetch`) + skip unchanged rows. M
- [x] **P1 CloudKit import bursts re-run full-library sweeps un-debounced on BOTH apps** (`SkriftMobile/Services/CloudSyncMonitor.swift:101-136`, `SkriftDesktop/App/MemoCloudReconciler+Wiring.swift:30-81`) — the `isSyncing` UI flag is debounced 1s, the actual work isn't; initial device sync = dozens of back-to-back O(n) main-actor passes. Coalesce the sweep dispatch. S/M
- [ ] P3 (was P2) `ExportStateStore.persist()` whole-ledger rewrite per record (`Services/Export/ExportStateStore.swift:56-69`) — verify found `publishAll()` has NO production caller (unwired standalone publish path; and it's O(k·n), skip-unchanged short-circuits). Dirty-batch it WHEN wiring the publish phase. S
- [ ] P3 `NamesMerge` millisecond-tie always favors remote (`Shared/Naming/NamesData.swift:172-178`); P3 `MacCloudWriteBack` wall-clock LWW has no skew tolerance (single-Mac fine, `:60-65`); P3 `MemoCloudIngest.swift:83-89` Bonjour double-ingest comment likely dead — verify + prune.
- Clean bills: SharePayloadLoader (extension memory ceiling handled textbook), CaptureInbox/Drainer (crash-safe ordering + poison pill), MemoDeduper, VaultExporter locked-note gate, MemoCloudUpdate content-based echo guard.

**Desktop:**
- [x] **P1 drag-drop/open-panel ingest runs on main incl. a semaphore-blocked video export** (`Features/Sidebar/SidebarView.swift:76-101` → `Pipeline/Ingest/IngestService.swift:205-207`) — comment at `:186` only proves no-deadlock, not no-freeze; multi-minute beachball on video drop. `UploadService`'s prepare/commit split is the right pattern next door. M
- [x] **P1 no guard against editing a note the pipeline is actively processing** (`ProcessingCoordinator.swift:158-180`, `BatchRunner.swift:150-156` unconditional overwrite vs `NoteBody.swift:183-194` live editor) — user edits during the multi-second LLM window get clobbered; none of the sync paths' LWW care applies here. Disable editor for the in-flight file or skip final write if hand-edited mid-run. M
- [x] P2 (was P1 — dev/prod stores isolated, needs two SAME-config instances) no second-instance store guard (only the `RunFile.swift:514` comment + discipline) — `NSRunningApplication` check at launch. S
- [x] P3 (was P2 — bounded by library size, active-typing only; and it's 2 full fetches per keystroke via `matches`+`exactExists`) tag typeahead re-tallies the whole library per keystroke (`Features/Review/NoteProperties.swift:252-325`) — compute once when the field opens. S
- [ ] P2 LINKED-FROM backlinks full-corpus body scan per note switch (`NoteDisplayView.swift:501-511`) — maintain a backlink index on save. M
- [ ] P3 `BodyTextView.restyle` full-doc regex per keystroke (`BodyTextView.swift:417-496`) — fine now (fast paths), scope-limit for long pasted transcripts. M
- [x] P3 `Sanitiser.wordRegex` recompiles per alias per call, uncached (`Shared/Naming/Sanitiser.swift:759-763`) — not hot-path; memoize. S
- Clean bills: engine lifecycle (load-once + 60s idle unload of the ~9GB weights), all Mac↔phone write-back LWW/echo guards, serial batch model, `RunReconciler` crash recovery.

**⚡ Found during final verification (2026-07-19):**
- [x] **P1 `mlx-swift-lm` pinned to floating `branch: main`** — PINNED a47894a1 on main 2026-07-19; (desktop `project.yml`) — a fresh checkout/worktree resolves today's upstream, which currently fails to compile against the resolved mlx-swift; the working Mac only builds off its cached resolution. Pin an exact revision (like FluidAudio's `7f963cdc`) — needs Tuur's pick of revision. S

**⚡ Connections/retrieval surface (Sonnet audit 2026-07-19, built same day unless noted):**
- [x] P1 empty-snapshot sweep wipes the whole embedding index on a failed fetch (`EmbeddingIndex.sweep` guard added)
- [x] P1 query failure rendered identically to "no matches" — Mac: `lastError` observable + gate line + "Connections unavailable" empty-state; PHONE PARITY still owed (Related in search)
- [x] P1 `modelRev` never checked on the read path — filtered in scores/related/gistPairScores (mixed-generation vectors excluded, no-bad-info)
- [x] P2 every query re-fetched + re-decoded the whole store — actor-state vector cache, invalidated per sweep
- [x] P2 `EmbeddingStore` silent in-memory fallback — now logged (was: full cold-start tax every launch, invisibly)
- [ ] P2 actor-reentrancy window: a query during a sweep's await can see a mid-swap memo (self-corrects; snapshot-swap deferred — structural M)
- [ ] P3 `ConnectionsModel` backlink full-corpus scan per note switch (needs a backlink index design; on-main rule blocks a trivial hop)
- [ ] P3 ANE-compile hang has no timeout/retry affordance (speculative; needs UX)

**Suggested attack order:** (1) the `try?` hardening pass — P0 + all silent-failure items, one small sweep, mostly S; (2) the three mobile one-liners (list O(N²), list thumbs, `load()` reorder); (3) `BookTranscriptStore` lightweight-read fix (kills both audiobook P1s); (4) Mac sweep blob/N+1 + burst debounce; (5) desktop ingest off main + pipeline-vs-editor guard + instance guard; (6) the P2 tail.

## 🎛 Transcription-engine wave — ✅ BUILT 2026-07-11 (worktree `transcription-engine-wave`; roadmap `TrEngine`)

Research session → user picked the lot; all mobile unless said. **Device round owed on everything below.**
- ✅ **Transcript chapter detection = THE chapter standard** (user call: even multi-file splits aren't reliably
  chapters). `ChapterDetector` (pure, 15 tests): long pause (≥2s) or file start + heading grammar — "Chapter/Hoofdstuk
  N" (digits, spelled EN/NL, ordinals, glued Dutch "drieëntwintig"), "Part/Book/Deel N", standalone Prologue/Epilogue/…;
  the number must TERMINATE (punct or ≥0.35s beat) so prose starting "Chapter seven ended…" can't match; spoken-title
  pickup only when the next short sentence HANGS (≥0.4s); same-heading echo drop (<45s); needs ≥2 detections, ≤30%
  number inversions (reset-to-1 after a part is fine) else nil; "Opening" prepended when the first heading starts >30s.
  Stored as `Audiobook.detectedChapters` (LOCAL-only, not in any sync carrier; `[]` = ran-found-nothing → never
  re-scans; nil = not yet run). `effectiveChapters` routes the WHOLE chapter UI (sheet, pill, sleep end-of-chapter,
  chapter line, capture attribution): detected > embedded/file-synth. Triggers: `BookTranscriptionJob` finish + player
  `open()` retro path (`detectChaptersIfNeeded`, detached, coverage-gated); session `refreshFromStore()` after store.
  Attribution `chapterNumberString` uses the ANNOUNCED number for detected books; a prologue quote carries NO number.
- ✅ **Detection v2 — style vote (same day, after web research + real-library probe).** ACX has narrators read
  headings EXACTLY as the manuscript writes them (so style varies by book but is consistent WITHIN one); m4b-tool's
  silence-chaptering proves gaps need duration priors. v2 harvests every style after silences and the book votes:
  keyword ("Chapter N", now incl. LibriVox "Chapter N of <book>") › bare numbers ("Seven. Don't turn into human
  spam.") › title-only (short HANGING utterances, accepted only when the book's biggest silences are dominated by
  title-shaped sites — sting-heavy productions fail the vote). All winners pass duration priors (median ≥4min,
  spacing ≥2min — kills counting scenes). Probing the REAL phone sidecars found two data truths: pre-2026-06-27
  sidecars carry chunk-seam ECHOES ("ten Ten." → was mis-parsed as 20; now deduped) and multi-file imports can be
  several WORKS (trilogy) → ascending-sanity resets at file boundaries. Result on the real library: Steal-trilogy
  0 → 5 real chapters (+44min Opening; sparse because the old-seam sidecars ate headings — a RE-TRANSCRIBE with the
  fixed seams + 180s chunks should lift recall a lot); Digital Minimalism → Opening + Part 1 + Part 2 (its narrator
  never says "chapter"; its per-chapter titles are title-only style — sidecar only 41.7% covered, finish the
  transcribe and re-judge). 21 detector unit tests; suite 659/659.
- ✅ **Round-2 device feedback (build 71, same evening): "Book N" separators** — the trilogy's restarting numbers
  read as shuffled ("??") → a separator entry lands at every numbered reset (suppressed when a real Part heading
  marks it), and a finished transcribe now FORCE-re-derives chapters (fresh sidecar supersedes old detection — no
  more USB cache-clears). Device-proven same night: trilogy redo = 4.5h in 6.5min (~33× cumulative, ~1.8 min/hr vs
  the June engine's ~3.2; per-chunk ~50× vs 21×), detection auto-fired → 8 real chapters (recall capped by this
  narrator running numbers into titles without a beat — the number+title-as-one-unit loosening is the parked tuning
  experiment, fresh sidecar pulled for offline iteration).
- ✅ **Round-3 (same night): separator restyled as a real SECTION HEADER** (user: the peer-row "Book 2" read as a
  ninth chapter). `AudiobookChapter.isSeparator` (display-only), sheet renders small-caps headers (no bullet/time/tap),
  and ALL index semantics (Ch N/M pill, sleep, attribution, current-highlight, prev/next) run on `playableChapters`
  (separators excluded). Sim-verified WITH VISION via the new `-seedDetectedChapters`/`-showTOCSheet` launch flags
  (self-serve sheet screenshots — no more shipping chapter UI unseen).
- ✅ **Round-4 (same night): SENTENCE-anchored bare numbers — the recall breakthrough.** Fresh-sidecar probing showed
  the missing headings have ZERO silence before them (this production never pauses; silence marks decorative stings
  instead). The discriminator is the SENTENCE BOUNDARY: every true heading follows a finished sentence ("…their
  example. | Two. Think process not product."), every prose number flows mid-sentence ("a nine to five job", "when he
  saw one", "Ecclesiastes chapter one") — all die on the prev-word-ends-sentence test. New anchor: prev-punct + number
  terminates + MANDATORY title sentence (hang waived at zero-gap); vote gates carry the rest. Trilogy probe: 8 → **21
  chapters with real spoken titles** + Book 2/Book 3 separators at the RIGHT places, zero FPs. Suite 677/677.
- ✅ **Round-5 (same night): completeness gate — "better no information than bad information" (user principle, now
  law in the detector).** Ordinals with holes make listeners feel chapters went missing. Numbered headings split into
  per-work SEGMENTS at resets; a segment shows its chapters ONLY when numbers run 1..k hole-free; any hole → the
  segment collapses to one tappable "Book N" jump point; a lone hole-y segment (normal novel with gaps) suppresses
  entirely (book keeps existing chapters). Real Part headings suppress synthesized markers. Trilogy now renders
  Opening · Book 1 · Book 2 · Book 3 (probe-verified) — complete jump points, zero false implications; the full
  21-chapter data stays in the sidecar for the day recall reaches 100% per book. Suite 677/677.
  **Follow-ups parked:** manual "Re-transcribe book" affordance for pre-fix sidecars (no created-at in the sidecar to
  auto-detect age); consider a review-sheet UI for gap-only books that fail the vote (the reading-mode chat owns
  player IA).
- ✅ **Book-transcribe efficiency trio:** (1) chunks feed the engine as in-memory PCM buffers — the temp-WAV round-trip
  is GONE (was ~15–30GB flash I/O per long book) and book chunks skip the custom-vocab CTC second pass (FP-prone on
  prose, pure cost); (2) `chunkSeconds` 60→180 (per-seam 3s lead + redo-tail overhead ~13%→~4%); (3) captures, user
  pause, AND battery-conserve now CANCEL the in-flight chunk (FluidAudio aborts between its ~15s windows) — cancel ≠
  failure: failure skips past the chunk, cancellation redoes the SAME frontier (never a gap).
- ✅ **Lazy RMS (both apps)** — the phantom-guard RMS decoded the ENTIRE file before every transcription; now computed
  after, only when the transcript came back ≤3 words. Free win on every memo/import/chunk.
- ✅ **Filler filter, opt-in (default OFF)** — Settings→Capture "Remove filler words": standalone um/uh/hmm/ehm… (tiny
  EN/NL list; "er"/"so"/"like" deliberately excluded — real words) stripped from text + karaoke timings in lockstep at
  memo save (`FillerFilter`, 6 tests); a dropped filler's sentence terminator transfers to the previous word; `[[img]]`
  markers pass through; an all-filler memo stays unchanged. NEVER audiobook quotes; live caption untouched. Capture
  DICTATION path deliberately not wired (separate path — add on demand).
- ✅ **FluidAudio pinned** to `7f963cdc` in BOTH project.yml (was floating `branch: main` — the drift risk flagged at
  the 2026-06-16 asrsweep entry). Upgrade = deliberate, both apps together, with a device round.
- ✅ **Trunk fix (drive-by, other lane's file):** `NoteBody.imageURL` had a shadowed `let url` from 7b597ad — full
  desktop scheme was RED on main (the UnitTests gate doesn't compile that file). One-line unshadow; ShareW2 chat heads-up.
- **Device-owed:** chapter detection on the real library (titles esp.), capture-cancel latency feel, 180s-chunk memory
  on the iPhone 13, RTF re-measure (buffer path + no-booster should raise the ~min/hr number), filler toggle on a real
  ramble.
- **Parked (from the same research):** per-book language override for the book job (a Dutch book under the global
  English toggle garbles — needs a small Transcribe-sheet picker); Paragrapher grouping for reading-mode when that
  builds; FluidAudio streaming managers for the live caption at the NEXT engine upgrade.

## 🎙 Recording robustness + heat diet (2026-07-07, worktree nice-shtern — roadmap `RecHard`)

User report (iPhone 13, warm): tap record → UI froze, stop unresponsive, memo captured only HALF the
message. Full-code audit found two separate causes, both fixed same day (5 commits, 588 unit tests
green; **device round owed** — the sim can't fire interruptions or measure ANE duty):
- **Data loss:** NO `interruptionNotification` handling — a call/Siri/alarm stops the engine with no
  route/config event, so the recovery lattice never fired and the wall-clock timer kept counting over
  dead capture. Fixed: interruption observer + foreground re-arm (iOS can skip `.ended`) + a
  display-timer capture WATCHDOG (engine dead >2 s, no rebuild in flight → rebuild) + resume()
  rebuilds when a plain start fails. The route-rebuild ladder itself is untouched (device-proven).
- **Heat/freeze:** live captions re-ran FULL ASR over the whole ≤25 s live window every 0.6 s (ANE
  ~100% duty, cost grows with the window) + the camera session ran the entire recording + the screen
  re-rendered ~30×/s (20 Hz timer on a whole-object ObservableObject) + Live Activity got the whole
  transcript every poll. Fixed: self-pacing polls (≥1.5× last snapshot cost, thermal floors
  2.5 s/.serious 6 s/.critical) + early rotation (>10 s window once snapshots >1.2 s) + camera runs
  only while the sheet is open + @Observable per-property observation with child-view splits (4 Hz
  timer) + Live Activity pushes a word-aligned ~220-char tail at ≥1.5 s. DevLog now traces
  window-size/snapshot-ms/rotations — pull `devlog.txt` on the next device round for the real numbers.

**Owed / follow-ups:**
- ⬜ Device round (13 + AirPods): freeze gone? snapshot-ms trace, mid-record call/alarm survives,
  camera-sheet first-open latency (~½ s expected), auto-off still fires, Live Activity tail reads OK.
- ⬜ Phase 3 (own session, riskiest): move session activate/deactivate + engine start/stop OFF the
  main thread — `setActive` blocks 100–300 ms in `start()`/`stop()`; touches the hardened lattice.
- ⬜ Spike: FluidAudio ships true streaming ASR we hand-rolled around — `SlidingWindowAsrManager`
  **accepts the already-loaded `AsrModels`** (`loadModels(_:)`, same weights in RAM) with push
  `streamAudio`/`finish`; would replace the snapshot loop with bounded incremental windows. Also
  `StreamingEouAsrManager` (separate EOU weights). Quality/latency device eval needed.
- ⬜ Extraction pass once device rounds lock behavior: TapWriter / RouteRecovery / CaptionFeed out of
  the 1000-line `LiveRecordingService`; protocol-seam the `if mock` branches.
- Deferred judgment calls: captions keep running while backgrounded (Lock-Screen Live Activity shows
  them — thermal floors now bound the cost); memory-warning `unload()` still no-ops mid-recording.

## ⭐ CONTINUE HERE (2026-07-07 night, audiobook-UX chat wrap) — worktree `sweet-goldstine`

Branch `claude/sweet-goldstine-13dfca` (pushed, NOT yet PR'd) holds **builds 46→51** on top of merged PR #6:
bottom-chrome saga (Option A split row → V2a pill → card-at-rest/pill-when-live → compact header + unified
30pt titles → card as scrolling list row → List-row tap-hijack fix w/ 2 green ContinueCardUITests). Contains
PR #8's content (sprint branch merged in) — **when this branch's PR merges, close PR #8 as contained.**
NEXT: (1) user+Hendri eyeball of build 51 (× must not autoplay; card/pill lifecycle; title sizes), then
(2) OPEN THE PR → merge → close #8. Ghost dismissal-write in the sim container never got attributed —
both write-sites DevLog themselves now; if the card vanishes without ×, pull the devlog.

## 🔬 Audiobook deep-review findings (2026-07-07 chat; UNBUILT unless ticked) — the perf/correctness list

**Perf (one root cause: monolithic sidecar JSON + main-actor I/O):**
- ⬜ P1 read-along uncovered-spot hot loop: `ReadAlongModel.reloadIfNeeded`'s `|| !covered` guard re-decodes the
  ENTIRE partial sidecar ~2×/s on main while playing past the frontier (worst exactly during "keep listening
  while it transcribes"). Cache by (sig, coveredUpTo) or check mtime/tiny header before decoding words.
- ⬜ P1 `BookTranscriptionJob` is @MainActor incl. statics: per 60s chunk — `extractPCM` (~20MB decode+WAV write)
  synchronous on main; `store.save` re-encodes the WHOLE accumulated sidecar (O(n²) bytes over a long file);
  `publishValue` re-DECODES every sidecar per chunk though the loop already holds `coveredUpTo` (trivial fix).
- ⬜ P2 `AudiobookCloudSync.localTranscriptSignature` full-decodes every sidecar per reconcile (launch/foreground/
  pull) just for coveredUpTo+wordCount.
- ⬜ P2 over-observation: 2Hz `currentTime` re-renders Books list (+ per-row SwiftData `isSynced` fetch + N×
  fileExists) via whole-session @ObservedObject; split a PlaybackClock sub-observable; make sync state a real
  observable (kills the `syncToggleTick`/`tick` hacks in AudiobookLibraryView + SyncedAudiobooksView).
- ⬜ P3 `setCurrent` linear-scans sentences 10×/s; per-body `Timer.publish` churn in ReadAlongView; CIContext
  per loadCoverTint.
**Correctness:**
- ⬜ P1 "Edit book details" never syncs: `store.update()` doesn't bump `modifiedAt` → reconcile's send guard
  never fires; replaced cover also never re-uploads (audioUploadedAt upload-once gate).
- ⬜ P2 TranscribeBookView shows the ACTIVE book's progress/ETA on any book's sheet while a job runs, and Start
  silently cancels the other book's job.
- ⬜ P2 seek-while-paused never persists (`seek()` lacks persistProgress; force-quit loses a paused scrub).
- ⬜ P3 BookCoverView placeholder gradient uses `uuidString.hashValue` (per-process seed) — not stable across
  launches despite the comment; use UUID bytes.
- ⬜ VERIFY quote audio extraction: `exportSpan` (AVAssetExportSession + precise-timing key) vs the durable
  PCM-extraction gotcha — if deep-chapter captures drift vs sidecar karaoke, switch to `extractPCM`+m4a.
**Dead code (~800 lines + tests):** wave-1 capture arm — `CaptureMath` (all of it), `CaptureScrub` shim,
`QuoteCaptureProcessor.process()`, `applyTrim`/`TrimResult`, `SentenceSnap.snap`/`inIndex`,
`CaptureSpan.proposal`/`replayWindow`; `AudiobookSession.sleepLabel`; `QuoteCaptureOutput`'s vestigial
buffer fields (shrink the struct). Zero non-test callers verified by grep 2026-07-07.
**UX (decided elsewhere or open):** per-book "N notes" surface + note→book jump-back (metadata `bookID`/
`bookPosition` now accrues since PR #6); multi-select import of N DISTINCT books silently merges into one
(warn when album tags disagree); Books empty-state deserves a real CTA button.

## 🎧 Books tab + one-tap resume — ✅ BUILT 2026-07-07 (mock-first, signed off; worktree `sweet-goldstine`)

From the 2026-07-06/07 audiobook deep-review chat (roadmap detour node **D4**). Mock = `mocks/books-tab-and-resume.html`
(v2, rebuilt 1:1 against Theme.swift + real components after v1 "looks different from the app" feedback). Decisions:
- **Highlights tab CUT** (user: "well kill it") — captures live in Notes; P6 becomes a book-context surface later.
- **Library → Books** (tab + header). **Screen title Memos → Notes**; "memo"→"note" across all user-facing copy
  (list/detail/trash/settings/onboarding/widgets/intents/Live Activity — Siri phrases had no "memo", unchanged).
- **One verb: "Add note"** (capsule pill + capture-screen header renamed from "Capture"; player already said it).
- **Cold-launch resume:** last PLAYED book restores as a **paused** capsule (`restoreOnLaunch`) → resume = 1 tap,
  record = 1 tap, same screen (the "two first things" tension dissolved). Never auto-plays; skips w/o local audio.
- **Global capsule:** mounted per-tab via `safeAreaInset` in AppTabView; persists over pushed screens; covers hide it.
  Memos list stopped observing the session (kills the 2 Hz whole-list re-render during playback).
- **Tap a book row → autoplays** (+ full player opens running); PLAYING/PAUSED row badge dropped (tint stays).
- **Books sort/filter chip** (was a dead-looking static label): Recently played (default, persisted) / Title / Author /
  Recently added + In progress / Not started / Finished. Unit-tested.
- **Capture memos now carry `bookID` + `bookPosition`** (stable join key for the future per-book-notes surface;
  additive metadata, Mac ignores).
Also fixed in passing: stale "Tap Mark" bookmarks empty-state copy; stale "last 30 seconds" capsule a11y label.
**Gate:** build green; unit suite 327 run — only the 8 PRE-EXISTING CloudKit-epic failures (verified identical at
branch HEAD baseline); new sort/filter tests green; 4 UI-test files' "Memos" assertions updated to "Notes".
**Device round 1 (build 40, 2026-07-07): FAIL — record button buried under the capsule.** The tab-level
`safeAreaInset` mount never propagated into the tabs' NavigationStacks on iOS 26; uncatchable in sim (no book
seedable). **FIXED build 46 — Option A** (signed `mocks/notes-bottom-chrome.html`): Notes = ONE 60pt row, compact
`AudiobookMiniPill` (cover · play/pause · ❝ Add note) left + record right (no session → record alone, right corner);
Books keeps the full bar (mounted INSIDE the view); Journal/Settings carry nothing (user call); ˄ chevron cut
everywhere (duplicate of cover-tap); list gets bottom content margin. New hooks `-seedAudiobook` + `-openTab` make
the capsule sim-visible per tab — vision-verified all four before install. **Round 2 (build 46): pill interior "weird — empty space / I'd tap it to open the book" + Henry "crowded".** Iterated V1/V2/V3 then V2a/b/c (mocks notes-pill-variants + notes-pill-v2-iterations); discovered the 390pt truth (title + labeled chip + play don't fit). **PICKED V2a → build 47:** cover · time-left · ❝ Add note · filled accent play; pill BODY opens the player; 16pt pill↔record gap. **Round 3 (build 47) + the Hendri debate:** designer pushback — media chrome on a notes list is weird; dashboard floated. Resolved via mocks (notes-book-presence-debate + notes-compact-header, both signed): **cards for starting, chrome for controlling** — build 48: at rest = ZERO chrome, "Continue listening" CARD above search (▶ 1-tap resume · body → player · × dismiss-for-today); live = V2a pill; launch-restore REMOVED (no phantom paused session — card reads the library). Plus **compact header**: Select/scan/filter inline with the "Notes" title (~44pt back; dodges the iOS-26 trailing-toolbar-item bug). New sim hook `-seedAudiobookIdle`. Both states sim-verified with vision; 582/582 unit green; MemoDetailUITests 5/7 fails PRE-EXISTING (identical at baseline — the known iOS-26 cluster). **Round 4 (build 48) → build 49:** (a) ×-dismissing the card then starting a book left the card gone — playing now VOIDS the dismissal (re-engagement rule; card returns when the session ends). (b) Title parade fixed: all four tabs share ONE 30pt `ScreenTitle` (was 30/26/34/34); Books folded its + into the title line; Journal + Settings got custom headers w/ root-only nav-bar hide (pushes keep bars). Four-tab sim vision check + 582/582 green. **Round 5 (build 49) → build 50:** the pinned card read as "stuck to the top" while scrolling — moved UNDER the search bar as the FIRST LIST ROW (scrolls away with the notes, honoring the original "content, not chrome" pitch). Player cover + the plays-again-voids-dismissal rule hoisted out of the card (a cover on a List row dies when the row unmounts). **Round 6 (build 50) → build 51:** × on the card AUTO-PLAYED the book — the SwiftUI List-row tap hijack (buttons in a List row need `.buttonStyle(.borderless)` or the row fires siblings; broke exactly when the card became a List row). Fixed + **2 new ContinueCardUITests** (tap × → no session; tap ▶ → pill) — green. Seeded launches now reset card-dismissal state (hermetic); ×/void writes DevLog-instrumented (a ghost dismissal write was found in the sim container — logs will name any recurrence). **OWED:** user eyeball of build 51.
Build numbering: 43–45 were consumed by the sprint branch in parallel → renumbered 46; rule = bump to
max(installed-on-phone, main) + 1 before any device build.

## 🔭 Next unclaimed lane + code-verified quick hits (2026-07-06 Fable survey, worktree youthful-wozniak)

Surveyed while three lanes were claimed elsewhere: note-editing (`claude/gracious-easley-e3fc96`),
audiobooks, and the Bonjour-removal/live-sync handoff (`claude/xenodochial-mclaren-9361b9`).
**Recommended next big lane = P8 Journal & retrieval** — full Opus-ready plan in
**`JOURNAL_RETRIEVAL_PLAN.md`** (repo root): locked decisions, chunk list with gates, collision map.

**⭐ P8 ENGINE BUILT 2026-07-07 (this branch — user green-lit parallel build, PR merge flow):**
mock signed off · engine bake-off RUN on the Mac (EmbeddingGemma-300M d512 wins 10/10 vs Apple NL
5/10, `Skrift_Native/spikes/EmbeddingBakeoff/`) · chunks 1–3 built + tested (Shared/Retrieval
gist/chunker/protocol; MemoEmbedding in its OWN local container; hash-diff sweep + orphan cleanup;
search/related max-cosine queries; 14 new unit tests green; full suite's 8 failures PROVEN
pre-existing on base — they're the Bonjour-era SyncCoordinator/MemoModel pill tests the removal
lane owns). Wiring is INERT (`journalIndexEnabled` default-false + model-on-disk guard — no
surprise 295 MB download). **Still owed:** UI chunks 4–8 after the other lanes merge (tab bar /
memos list / detail), floors calibration histogram, device perf run, Settings consent toggle.

**Quick hits (unclaimed; each verified against today's code, not memory):**
1. ⬜ **Stz020 #3 STILL LIVE — phone-added person is unlinkable.** `NamesListView.swift:202` still
   saves `aliases: []`; `PersonEditorView.swift:222` already seeds `[name]`. Fix: same seed in
   AddPersonView + a one-time backfill `aliases = [canonical]` for alias-less people (safe: only
   AddPersonView ever produced them — the editor auto-seeds on save). Backfill also fixes IJsbrand.
2. ⬜ **i4 ROOT-CAUSED — WhatsApp voice message imports as a LINK.** `SkriftShare/SharePayloadLoader.swift:48-70`
   classifies url → movie → image → text → file and has **no `UTType.audio` branch**; WhatsApp audio
   also exposes a URL representation, so the url branch wins. Fix: an audio branch BEFORE url,
   mirroring the movie fast-path (copy into the App-Group inbox, `type: "audio"`, host imports as a
   voice memo + transcribes). Feature half (multi-select messages → append-as-one vs split): the
   loader only reads `attachments.first` per type — iterate all providers + a small share-sheet
   choice. Verify on device with a real WhatsApp share.
   → **2026-07-07 share-ingest deep review:** i4 is row A7 of **`SHARE_INGEST_SURVEY.md`** — the
   full row-by-row table (existing share bugs A1–A16 + multi-item B + link-enrichment C + new
   input types D + cross-cutting UX/IngestKit E). User reviews it row-by-row (memo per row, say
   the ID); triage verdicts back into this ledger, then build.
   → **2026-07-10 VERDICTS RECORDED** (voice pass, in the survey's last column). Headlines:
   big GO wave (all of A incl. A7/A15, B1–B3 w/ B2 = photos ALWAYS one note, C3 podcasts ⭐,
   C5 pdf-urls, D1 quote-detect [NO Highlights tab — quotes are plain notes], D4, D7, D8,
   E1–E5 w/ E2 threshold = 1 h); **SKIP** D2 vCards; **D3 already live** (drainer manifests +
   PhotoTextIndexer — verified); **pending Tuur's call** after plain-words re-explain: C1
   (captions rejected outright), C2, C4, D5, D6, B4. Scribbel reference checked for A7:
   no extension there (doc-types + onOpenURL + ImportTranscriber w/ bg-task claim + toast).
   **r2 same day:** C4 GO · D5 SKIP · D6 GO-w2 · D1 PARKED (Books/Journal chat) — still
   pending only C1/C2/B4.
   → **2026-07-10 WAVE-1 MOCK SIGNED OFF:** `mocks/share-ingest-wave1.html` — 4 states
   (single audio · 8-memos 1-or-N chooser [default = one note, Save relabels live] ·
   photos-always-combine · Saved✓/Error/Unsupported), vision-verified, all questions
   resolved. LOCKED: every share jumps to its note on next app-open; audio shares have
   NO ramble UI (append in-app later — user rule); combine = audiobook-capture model
   (append in timestamp order, one karaoke transcript); "N photos → one note" title.
   → **2026-07-10 WAVE 1 BUILT — chunks 1–3 same day** (`827965f` A7 audio fast-path +
   jump-on-open-for-every-share; `394a916` A11 multi-select 10×, B1 1-or-N chooser
   [combine = clips MERGED in order via `MemoSaver.importAudioClips` → ONE transcription
   pass, no import/append race], B2 photos→one-manifest-note, ImageIO downsample ≤2048px;
   `3371fb1` A12/E3 Saved✓/error/unsupported states + A16 husk guard + A15 "Skrift Dev"
   label). Unit suite 610/610 green; roadmap node `ShareW1` inprogress. i4 = FIXED IN CODE.
   **✅ DEVICE ROUNDS 1–4 RUN 2026-07-10 (builds 60→63).** PASSED: singles+dates (Sunday ✓),
   multi order (chat order ✓), m4a transcribe, video, PDF (after the round-2 file-url fix
   — `public.file-url` CONFORMS to public.url and ate every Files share since June), photos
   inline-in-text (round-3 rebuild: markers in annotation + editorPage routing — user: "the
   only way we should have"), Saved✓, dev label, multi-select visibility. FIXED ALONG THE
   WAY: phantom silent tail on the 4-clip merge (composition+export fabricated duration
   287.5s — rewritten as sample-accurate AVAudioFile frame reads, EOF guard); clip-list
   scrolls all rows. **RETIRED: sheet dictation** — iOS blocks extension recording at the
   entitlement level (mediaserverd refusal; perm 'grnt' yet record()=false, both session
   categories; Apple forums 742601/108435). Old test image-captures stay broken by user
   decree (no migration — "they can go"). **REMAINING/PARKED:** slow first transcribe =
   cold engine + app-suspension (existing launch-sweep recovers; Scribbel-style bg-task
   claim = Wave-2 candidate); voice-annotate captures IN-APP (Wave-2); drag inline photos
   like Apple Notes (note-editor lane); PDF "text, PDF, text" inline (Wave-2 design).
   → **⭐ CONTINUE HERE — SHARE WAVE 2 (kickoff 2026-07-10, Wave 1 MERGED via PR #11).**
   Start from MAIN, fresh worktree. Read `SHARE_INGEST_SURVEY.md` (top status block +
   Verdict column) first. Two tracks: (A) **code-first, no mock needed** — A9 open-in video
   nav + prune avi/mpg, A14 off-main drain copies + pending indicator, C5 pdf-url →
   download→file-capture, D4 .md/.txt → note body, D6 Maps place-note, D8 in-app Files
   importer (audio+video), E2 1-hour Books routing, A4 EXIF date on image captures,
   A6 PDF text-extract (unpin — searchable PDFs), bg-task claim on share imports
   (Scribbel `ImportTranscriber` pattern, ~/Hackerman/ShhcribbleiOS). (B) **mock-first**
   (locked process): E1 unified sheet (video+PDF get the slim sheet — significance at
   share time), PDF text-inline in the body, in-app voice-annotate a capture. C3 podcasts ⭐
   = own lane when user says go. Still awaiting user calls: C1 YouTube rich-card-only?,
   C2 Insta/TikTok, B4 chat-export. Device builds number from **64** (63 = on-phone).
   → **2026-07-11 WAVE-2 TRACK A BUILT — all 10 items, one session, suite 632/632**
   (commits `7b597ad`..`f9386cf`): Mac capture-marker fix FIRST (the Wave-1 unproven
   edge was REAL — literal `[[img_NNN]]` in the Mac Review UI AND the vault export,
   plus a stale-name pinned embed; fixed in VaultExporter/Compiler/NoteBody, desktop
   345/345) · A9 open-in nav + honest "format not supported" for avi/mpg (extensions
   KEPT — public.movie delivers them anyway; pruning would silently eat the share) ·
   A14 drain copies off-main + reentrancy guard + "Importing N shares…" pill · C5
   pdf-url → download (magic-byte sniff, link-card fallback) · D4 .md/.txt → note body
   (loader also FIXED: a text FILE decoded to nil → empty sheet) · D6 Maps → place
   chip (PlaceLink parser; goo.gl short links stay cards — opaque without a fetch) ·
   D8 header import menu (Files audio+video via AppURLHandler; wires the ORPHANED
   VideoImportPicker — it had zero call sites) · E2 ≥1h → Books chooser in the sheet
   (default Books, fallback-to-memo when unreadable) · A4 EXIF dates (read in the
   extension BEFORE the downsample strips them; earliest across a multi-share) · A6
   PDFKit text-extract → sharedContent.text (searchable; 120k cap) · bg-task claims
   on drain + all three import transcriptions (Scribbel pattern). **Track B mock
   `mocks/share-ingest-wave2.html` AWAITS SIGN-OFF** (4 states: E1 video · E1 PDF ·
   PDF text-in-note collapsed/expanded · voice-annotate idle/recording/after; open
   questions printed on the panels). **BUILD 64 INSTALLED on the phone 2026-07-11**
   (freshness strings-verified: Wave-2 symbols in the dylib, app+extension plists = 64).
   → **✅ DRAIN HALF DEVICE-VERIFIED 2026-07-11 (USB, no hands needed):** staged 6
   crafted inbox entries into the app-group container over devicectl, launched the
   app, verified via devlog + pulled SwiftData store + library.json — C5 ✅ REAL
   network download ON the phone (w3.org dummy.pdf → file capture) · A6 ✅ its text
   extracted on-device (sc.text='Dummy PDF file') · D6 ✅ place parsed
   (location{38.7223,-9.1393,'Hotel Du Vin'} + urlTitle fallback) · D4 ✅ .md → body
   (ramble + file text in order, sc.type=text, provenance fileName kept) · A4 ✅
   recordedAt=2026-07-02 = EARLIEST photo date, not share time (2-photo manifest +
   markers) · A9 ✅ garbage .avi → title 'Video format not supported' · E2 ✅ audio
   routed to the Books library (book in library.json) · A14 ✅ drain visibly
   interleaves off-main (pdf download logged mid-video-import). Test junk on the
   phone: 6 notes + 1 'shared import 402AD…' book — delete at will.
   **REMAINS FOR TUUR (extension/UI half, ~3 min):** share-sheet entries from real
   apps (Safari pdf-link · Maps · Files .md · Photos w/ EXIF · 1h+ audio → Books
   CHOOSER visible) · header import menu eyeball · import pill on a big movie ·
   open-in jump lands on the note. KNOWN GAP (pre-existing, logged): the phone's
   OWN Obsidian publish never copies images for ANY photo memo — Mac stays the
   attachment exporter.
   → **ROUND 2 (Tuur's hands, 2026-07-11 evening) — 2 bugs found, both FIXED, build
   66 installed:** (1) **Safari-PDF: Skrift absent from the share sheet** — the
   DICTIONARY activation rule only matches homogeneous items; Safari shares a PDF
   page as ONE item [web-URL + PDF]. Swapped to an explicit predicate string
   (per-attachment OR over url/text/image/movie/audio/pdf/file-url/data, ≤10);
   **sim-verified both ways** via the new `ShareSheetActivationProbe` UITest that
   drives sim-Safari's share sheet (iOS-26 'Share under ···' path): arxiv PDF now
   offers Skrift, plain pages still do. Run it explicitly after any rule change —
   a bad predicate silently removes Skrift from EVERY sheet. (2) **'Video format
   not supported' memo spam** — an inbox entry whose dir survives delete re-imports
   on EVERY open (video/audio mint fresh memo UUIDs; hit via devicectl-staged test
   entries whose dirs the app can't remove — NB devicectl-planted files are
   app-undeletable; the wipe antidote is `devicectl ... copy to --remove-existing-
   content true`). Fix: failed deletes TOMBSTONE the entry id (persisted, cap 200),
   pendingEntries skips them; poisoned inbox wiped; Tuur already purged the junk
   memos. (3) Bonus find: **arxiv links are extensionless** (`/pdf/2406.19741`) —
   C5's .pdf check missed them → now a 10s HEAD content-type sniff catches any
   `application/pdf` link (magic-byte gate unchanged; suite 661/661). Google-Maps
   APP shares = opaque goo.gl short links → stay link cards BY DESIGN (needs a
   fetch; parked with A1/C4 enrichment). Tuur's arxiv paper staged for drain on
   next app-open (build-66 sniff e2e = watch for `drain: pdf-url ... downloaded`).
   E2's Books CHOOSER UI still unverified (no ≥1h file handy) — routing itself is
   device-proven.
   → **⭐ WAVE 3 BUILT 2026-07-12 early-AM ("do everything that's left" — Tuur
   green-lit Track B as drawn via the option pick).** Commits `51a483f`..`c0e8e99`:
   **A3** selected-text beats url, link rides along (loader) · **D7** odd-UTI voice
   notes (Signal/Telegram) reroute off the file branch by audio extension ·
   **A1+C4** link enrichment ON DRAIN — one GET: og/title/description + og:image
   downloaded LOCAL (`linkthumb_<id>.jpg`, offline rule) → url card grows thumb +
   description; Readability-lite article text → `sharedContent.text` (searchable,
   never rendered; 3-para/400-char floor, 60k cap; Maps + pdf-routed links skip);
   pure parser = `HTMLMeta` (6 tests) · **B3** mixed bundles → ONE note: loader
   collects photos+text alongside clips, sheet stacks the signed idioms + forces
   combine, drainer manifests photos under the memo id (markers via the
   transcription pass) + chat text → annotation · **E1 (Track B m1/m2)** video +
   documents get the SLIM SHEET (preview cards w/ duration/filmed-at · pages/size,
   honesty lines, typed thought + significance; silent imports + completeVideo/
   completeFile RETIRED; thought lands as an annotation-lead above the transcript
   — new non-capture annotation display) · **PDF text-in-note (m3)**
   `PDFTextDisclosure` collapsed row under the inline PDF → expanded dimmed
   preview w/ fade → full selectable reader sheet · **voice-annotate (m4)**
   `CaptureVoiceAnnotate`: mic pill on audio-less captures → inline strip with
   LIVE CAPTION (LiveRecordingService reused) → on-device transcribe → appends
   below the ramble → 'Add another'. **v1 = dictation model (audio consumed):
   attaching playable audio flips the Mac capture-ingest discriminator (capture =
   memo WITHOUT audio) — Mac-counterpart chunk owed before that half.**
   **VERIFICATION STATE (resolved 2026-07-12 morning):** the overnight "build-stack
   wedge" was a PENDING macOS DEVELOPER-TOOLS AUTHORIZATION DIALOG — xcodebuild
   sat silently alive at clang-stat-cache/codesign waiting for a GUI prompt no
   terminal can see (Tuur accepted it → suite ran green in 6s). Durable lesson:
   silent multi-minute stalls at stat-cache/codesign ⇒ check the Mac's screen for
   an auth dialog BEFORE diagnosing a wedge. Voice-annotate's UNVERIFIED flag
   LIFTED: suite 669/669 compiles + passes with it; **BUILD 67 INSTALLED**
   (freshness: version 67 + Wave-3 strings in the dylib) and the 61-min chooser
   test file is ON THE PHONE (Files → On My iPhone → Skrift Dev →
   long_test_recording.m4a). **REMAINS: Tuur's Wave-3 retest** — Safari
   selected-text → quote note w/ url · article link → rich card + searchable text ·
   WhatsApp voice+photo multi-select → one note · video/PDF share → sheet w/
   thought+circles · PDF note → text disclosure + reader · capture → mic-pill
   voice ramble · share the 61-min file from Files → Books CHOOSER (E2 eyeball).
   → **⭐ NEXT SESSION KICKOFF — B3 round 2: multi-ITEM WhatsApp bundles (found by
   Tuur 2026-07-12 19:12, devlog-proven).** He multi-selected voice notes + a photo
   + a link + a VIDEO in WhatsApp → only a video note appeared. Root cause: WhatsApp
   ships a multi-select as MULTIPLE NSExtensionItems and `SharePayloadLoader.load`
   reads `inputItems.FIRST` only — his first item was the video, so the voice
   notes/photo/link never entered the loader. B3 merges multi-ATTACHMENT items only.
   Build: (1) flatten attachments across ALL extensionItems before the type
   dispatch; (2) decide video+link roles inside a mixed bundle (suggestion: video →
   its own memo alongside the bundle note, link → rides the note like B3 text; OR
   everything-in-one via markers — design call, mock if UI changes); (3) the sheet
   must SAY what it's keeping (honesty line), never silently drop; (4) device round
   with the same WhatsApp selection. Suite baseline 672/672; builds from 71.
   → **✅ CHAPTER CLOSED 2026-07-12 evening (last Fable-5 day; roadmap ShareW2 →
   done, now → NFeat).** Builds 64→70 shipped; crash loop fixed (dup CloudKit ids
   → tolerant dicts + MemoDeduper trash-sweep); no-bubble rule LOCKED + applied
   (audiobook-quote idiom for shared text, borderless annotation); voice-annotate
   cold-start now says "Warming up the transcriber…" (build 70). **PARKED, ZERO
   URGENCY — user retest of the wave-3 share paths** (list stands below; every
   path fails honestly now — error states + extLog + tombstones — so regressions
   surface in normal use, no test session required). Parallel-board note: Lane P
   builds ON these MemoDetail changes; Lane B (podcasts) reuses C5/enrichment
   plumbing.
   → **2026-07-12 17:00 — Tuur's first retest hit 'Couldn't save this' on EVERY
   share: MY wipe's collateral.** A devicectl-created CaptureInbox dir is
   IMMUTABLE to the app+extension → every extension write died at
   createDirectory (and only print()'d — invisible). **FIXED in build 68
   (installed):** write failures now extLog into the devlog; inboxURL SELF-HEALS
   a file squatting on the inbox name (recovery = devicectl turns the poisoned
   dir into a file; app OR extension unlinks + recreates it app-owned on next
   use). The heal completes on Tuur's next app-open or share attempt. HARD RULE
   FOR SESSIONS: never devicectl-write into app-group paths the extension must
   own (staging test entries planted this twice); pull-only is safe.
3. ⬜ **Stz020 #5 remainder — "every note is a conversation".** `dda494d` (C2) only fixed tag
   over-suggestion on turn bodies. Still open: WHY stored transcripts carry stale `**Name:**` turn
   markers, + a bulk un-diarize/re-transcribe path. (Workaround: sidebar right-click →
   Re-transcribe, `SidebarView.swift:527`.)
4. ⬜ **Prod gate runbook (no code — dashboard + user GUI), before ANY Release promote:**
   (a) CloudKit Dashboard `iCloud.com.skrift.mobile` → deploy Development→Production schema, must
   now include `MemoEnhancement` + `NamesRecord` + `VocabularyRecord`; (b) prod Mac Settings →
   cloudKitMacSync ON; (c) Release bundle-IDs' App Groups capability — one-time Xcode Signing &
   Capabilities visit (CLAUDE.md signing lesson); (d) one real prod round-trip test.
5. ⬜ **Sequencing:** Mac in-place name-linking parity (§ CloudKit epic above) touches
   `Features/Review/NoteBody.swift` — the same file live-sync Part B will edit. Do it AFTER
   live-sync lands, then run `/code-review` over the whole CloudKit sync spine (newest,
   least-battle-tested code in the repo).

Also noted: `AppTabView`'s dimmed "Highlights (soon)" tab — the P8 mock
(`Skrift_Native/SkriftDesktop/mocks/journal-retrieval.html`, drafted 2026-07-06) proposes **Journal
takes that slot** (Notes · Library · Journal · Settings); P6's Highlights feed + Daily Review later
land as sections *inside* Journal, and P6's quote cards remain a user-led design session.

## ⭐ CONTINUE HERE — stabilization DONE, next board (handoff 2026-07-10)

**Stabilization round CLOSED 2026-07-10** (all four triage items below ✅, device-verified;
builds 58/59/60 shipped same-day; phone runs **60**; sim suite 601/601; main pushed through
`30edbc6`). One session-spanning lesson is in memory `project_p0_enhancement_clobber`: the
"truncated transcript", the empty single-word searches, AND the build-53 crashes were ONE
system — the embedder cold path (OOM → relaunch → lazy-pager opens rendering raw).

**The board now (pick by Tuur's call):**
1. ⬜ **Soak-watch builds ≥59** (passive): after a day of normal use, pull devlog + crashes —
   confirm zero tokenizer-OOMs (single-flight fix) and no 0xDEAD10CC recurrence; cold-load
   lines now report duration. If OOM returns: tokenizer-load memory diet (CoreML-LLM side).
2. ⬜ **Design question (1 mock)**: "warming up…" row in the Related section — first search of
   a session shows nothing for ~40s (measured 42.5s cold load). Mock-first if picked up.
3. ⬜ **Prod CloudKit schema deploy** (§ Stz020) — deliberate prod action, Tuur-gated: deploy
   the dev schema to prod + Release app-ID registration, then one real phone↔Mac round-trip.
4. ⬜ **Desktop Review mock sign-off** (user design session) + desktop-parity device
   round-trips owed (lock-gate, OCR search, link export, vocab LWW — see DParityA/SharedKit).
5. ⬜ **Vault lens** — waits on Tuur's iCloud vault move (JOURNAL_RETRIEVAL_PLAN.md Phase 2,
   incl. title-linking design).
6. ⬜ **Parked kickoff: capture-as-note + note-editing follow-ups** — verbatim brief in memory
   `project_capture_as_note_kickoff` (user deferred 2026-07-07).
Wall printer reminder stands: after the office test print, RE-PICK the home printer.

## ✅ Post-convergence stabilization (handoff 2026-07-08 → closed 2026-07-10)

Five chats merged into main in ~24h (P8/Review+Wall · note-editing · Books/recording · SharedKit ·
desktop parity). Feature velocity was huge; convergence bugs surfaced. **NEXT CHAT = a
STABILIZATION round, not a feature lane.** Phone = iPhone 13, Dev build **57** installed (wifi
installs work: devicectl + CoreDevice, no cable). Sim suite 599/599 green.

**Triage, in order:**
1. ✅ **P0 CLOSED 2026-07-10 — NO DATA WAS EVER LOST; two real bugs found + fixed (build 58).**
   Forensics: the memo is a 6.3s recording — its RAW transcript was ALWAYS 108 chars; the "lost"
   body is Tuur's 369-char edited note, which the PHONE STORE STILL HELD INTACT (pulled over
   devicectl — NB the live SwiftData store is in the APP-GROUP container
   `group.com.skrift.mobile.dev`, not the app container, since the 06-12 App-Groups work). All
   memos scan clean. **Restore ABORTED** — the phone's copy was newer than the Mac's frozen
   mirror; running it would have rolled the note back. Mac Skrift Dev safe to launch again.
   - **Real bug A (what Tuur saw), FIXED `6724a41`:** memos opened FROM SEARCH RESULTS rendered
     the raw body and never healed — the pager's LazyHStack realizes pages during the programmatic
     scroll WITHOUT delivering appear events, so the `.task` that fetched the enhancement never ran
     (devlog-proven: zero task side-effects on sick opens; list-flow opens healed in ~200ms).
     Fix: the polish is a live per-memo `@Query` — correct on the first body eval, no appear-event
     dependency, live CloudKit updates (retired the onChange(sync.isSyncing) refetch).
     PolishedDisplayUITests + 601/601 green. ✅ DEVICE-VERIFIED build 59 (2026-07-10 13:58): Tuur
     opened the memo from active search MID-cold-load — first render `len=369`, zero raw frames.
   - **Real bug B (found en route), FIXED `56f360e`:** commitDraft wrote the dirty draft to
     whatever `polishedBinding` held at COMMIT time; the binding arrives async / drops on churn, so
     a raw-born draft COULD flush into the arriving binding (copyedit ← raw). Never fired for this
     memo but the mechanism was real — commit target now PINNED at first dirty edit
     (`markDraftDirty`), both directions regression-tested. The DEBUG `-restoreEnhancementMemo/-Body`
     launch hook stays available (unused).
2. ✅ **Semantic search CLOSED 2026-07-10 (`0778575`, build 58) — it was a COLD-LOAD STALL, not
   weak scores.** Devlog (build 57): first query of the session took 122s — cold `prepare()` (ANE
   load of the 294MB encoder + parsing the 31.8MB tokenizer.json) serialized SIX queries behind
   the index actor; they drained ~15ms each once warm and ALL scored above floor (1-word 'Try'
   0.43, 'Trying' 0.45, 'Attempt' 0.41 vs floor 0.25 — results arrived minutes late into a dead
   view). The 60s idle unload then re-paid the load on nearly every search. Fix: model held 10 min
   (unload immediately on backgrounding), warmup fires at the FIRST keystroke, cold-load duration
   now DevLogged. searchFloor untouched — the bake-off calibration stands. ✅ DEVICE-MEASURED
   builds 58/59: cold load = 42.5–43.9s from the ANE cache (the 122s on 07-08 was the uncached
   worst case). The instrumented run ALSO caught prepare() double-loading on actor reentrancy
   (warmup racing the query path → two concurrent 295MB loads) — fixed with a shared in-flight
   load task, single-load verified on 59 (`70c3714`). DESIGN QUESTION for Tuur: 42s is long
   enough that the first search of a session shows an empty Related section for ~a minute — a
   quiet "warming up…" row would make it honest (mock-first when picked up).
3. ✅ **Crashes CLOSED 2026-07-10 — logs pulled over USB (153 reports, kept on device). Four
   classes, all explained:**
   - **3× Jul-8 10:12–10:15 (build 53) — the ones Tuur reported**: `swift_abortAllocationFailure`
     OOM aborts inside the embedder's tokenizer parse (`BPETokenizer.init` / YYJSONParser over the
     31.8MB tokenizer.json), on the cooperative pool while typing searches. Same root system as
     triage item 2 — crash pid 26017 IS the devlog's sick session (crash → relaunch → lazy-pager
     opens = how the "truncation" kept being seen). The 58/59 fixes attack it directly:
     single-flight load (the reentrancy DOUBLE-load meant two concurrent parses), 10-min hold
     (fewer cold parses), first-keystroke warmup. If OOM recurs on ≥59: next step is a
     tokenizer-load memory diet (serialize parse, release intermediates) — CoreML-LLM side.
   - **1× Jul-7 18:00 (build 39) — reminder-tap assert, FIXED build 60 (`2593da3`)**: async
     UNUserNotificationCenter delegate on a nonisolated class resumed UIKit's completion on the
     cooperative pool → state-restoration snapshot ran off-main → main-thread assert. Delegate now
     @MainActor. Fix by construction; repro (lock-screen reminder tap while snapshotting) is
     impractical — watch.
   - **2× Jul-7 22:07/22:08 (build 48) — RUNNINGBOARD 0xDEAD10CC** (held DB/file lock across
     suspension), books/recording-lane era PRE-hardening; zero recurrence in builds 52–57 (Jul 8)
     after PR #10's recording hardening. WATCH: if it returns, suspect the app-group SwiftData
     store being written at suspension.
   - **1× Jul-7 14:26 (build 35)** — iOS-26 CoreAutoLayout exception inside the system
     keyboard-cursor-accessory (`_UICursorAccessoryHostView`), during the accessory-bar round;
     accessory work landed builds 36+; no recurrence. Watch-only.
   - Jetsam Jul-9: Skrift appears only as `idle-exit` (benign). Older `.diskwrites_resource`
     (Jun 14/26) + `.cpu_resource` (Jun 21) reports predate the current architecture — noted, not
     chased.
4. ⬜ Wall: Tuur's office print test → REMIND: re-pick the HOME printer after (saved printer IS
   the wall). First physical card = design round on paper.
5. ⬜ Then: vault lens (after Tuur's iCloud vault move; incl. title-linking design above),
   desktop Review mock sign-off, prod CloudKit schema deploy (still pending, § Stz020).

**KICKOFF PROMPT for the next chat:**
> Stabilization round on main (all lanes merged). Read backlog.md "⭐ CONTINUE HERE —
> post-convergence stabilization" and work the numbered triage top-down, instrument-first
> (DevLog + devicectl pulls; wifi installs OK, crash logs need USB). Start with the P0
> transcript-truncation data bug. Build numbers continue from 57; bump per device install.
> Commit per finding with explicit paths; update this backlog section as items close.

Noticed in passing (P0 forensics, 2026-07-10; NOT acted on): list-row previews render raw
`memo.transcript` (`MemosListView` transcriptSnippet) while the note detail shows the polish —
after the restore the row's first line ("Yo yo, my name is tiuri…") won't match the note body.
Pre-existing choice, cosmetic; fold into a display-consistency pass if it bothers in use.

**Bug reports (Tuur, on build 53; INSTRUMENT-FIRST — phone off-cable, diagnose from devlog next USB session):**
1. ⬜ **Semantic search intermittently finds nothing** ("I'm trying" no longer surfaces the
   testing notes; worked on earlier builds). Suspects: swallowed engine-load error (was `try?` —
   NOW LOUD: `SemanticSearch …` devlog lines log count/top-score/floor per query, FAILED on
   throw); or scores genuinely below `searchFloor` 0.25 for short queries. Repro then pull devlog.
2. ⬜ **Skrift Dev crashed a few times at random spots** (build 53, mixed usage). Pull crash logs
   next cable session (`idevicecrashreport` per pull-phone-feedback skill); suspects unknown —
   could be any lane's (builds 45–53 span recording + books + P8 work).

**Design adds (locked in conversation):**
- **Vault lens gains title-linking** (the old Backlink-Weaver idea): reading the vault yields a
  title index → transcripts can suggest/insert `[[wikilinks]]` to VAULT notes (not just
  memo↔memo). Belongs to the vault-lens chunk (JOURNAL_RETRIEVAL_PLAN.md Phase 2).
- **Then-vs-Now pair-picking (mechanics)**: for each memo of the last ~2 weeks, `related()` →
  keep hits ≥6 months older → highest-scoring pair above `relatedFloor` renders as the card
  (old + new juxtaposed). No pair clears floor+gap → no card. Cosine picks the topic, the
  time-gap guarantees the "then."
- **Office-printer guard (behavioral rule for now)**: the saved printer IS the wall — test prints
  at the office are fine, but re-pick the home printer after (or toggle auto-print off). Later
  nicety: bind auto-print to the HOME printer identity only.

## 🖨️ Print-to-wall + significance in the Journal (Tuur design session 2026-07-07 evening)

**✅ BOTH BUILT same evening (build 43 on device; 581/581 tests; sim-screenshot verified).**
`Features/Journal/WallPrinter.swift` (service + WallCardView + settings section), Important-lately
in `LookbackProvider`/`JournalHomeView`, queue row on Journal home (the in-app surface — Tuur:
notifications get dismissed), SignificanceCircles commit hook, ⋯ "Print Card". OWED on device:
pick the real printer (Settings → Wall printer), rate a note orange, watch it print; test-card
polish round on the physical print. Original design (still the spec):
1. **"Important lately" card on Journal home** — the orange-tier (≥0.8) notes of the last ~30 days,
   above the Looking-back cards. This is P6's Highlights feed taking its first slot inside Journal.
   Resurfaced UNRATED notes stay in Looking back by design: they're prune-candidates (idea i2)
   making their case — the journal is where a note earns its life (rate it → it survives).
2. **Auto-print Important notes ("the Wall")** — when a note crosses INTO the orange tier, silently
   print a designed card to the home printer. Mechanics: one-time `UIPrinterPickerController` pick
   in Settings ("Wall printer" section: printer + auto-print toggle + threshold, default 0.8) →
   `UIPrintInteractionController.printToPrinter` (NO dialog). Card = the P6 quote-card renderer on
   paper (title + polished text + date/place footer + thread first-mention line; mono-first
   typography; ImageRenderer → PDF). `printedAt` stamp = idempotent (re-rating never reprints);
   manual "Print card" in the note ⋯ menu; offline → queue + retry on foreground + "🖨 sent to the
   wall" toast. Printed notes get a 🖨 mark; later a Journal "Wall" section mirrors the physical
   wall in print order. (Mac-as-print-daemon = robustness fallback later; phone-first is
   standalone-true.) Quote-card renderer is shared with P6's shareable image cards.

## ⭐ CONTINUE HERE — desktop-parity board (written 2026-07-11 for the NEXT chat; Fable→Opus handoff)

**Read this first.** The A-list shipped 2026-07-07 (section below). What remains is three boards, all
**GATE (1) CLEARED — mock v2 ✅ SIGNED OFF 2026-07-11 (Tuur): `mocks/journal-desktop.html` IS the
spec for Boards A+B.** Gate (2) ALSO CLEARED 2026-07-13 — Tuur confirmed all lanes done; verified: no
live lane branches, board-cited files all present on main, desktop trunk build fixed (744cc0f),
FluidAudio pinned 7f963cdc. BUILD FROM CURRENT origin/main (base-proof: MemoDeduper.swift exists).
Stale-gate check for any future session: (2) check no other chat is mid-flight
before touching app code (`git worktree list` + `git branch -a --sort=-committerdate`, merge
origin/main first, work in YOUR OWN worktree branch, `git add` explicit paths only).

**Board A — B-list body parity (desktop), mock panels 3/4 are the spec:**
1. ✅ **DONE 2026-07-13 — memo-link chips + LINKED FROM.** Atomic `MemoLinkChipAttachment`
   (rides the img-marker attachment machinery — `modelString` reconstructs the literal, offset
   math generalized to variable-length attachments); click → `onOpenMemo` → AppModel selection;
   `MemoBacklinks` strip under the body (contains-scan, newest first). Demo seed grew a fixed-UUID
   link pair; NEW verification tool: `-snapshot-memolinks` renders the LIVE NSTextView editor via
   an offscreen NSHostingView + in-memory store (ImageRenderer can't) — chip + strip both
   eyeballed. GOTCHA fixed en route: `.task` on empty conditional content never fires (the strip
   kept itself empty) — keep a zero-height clear view rendered. `[[` creation picker still owed.
2. ✅ **DONE 2026-07-13 — live checklists on the Mac.** `BodyTransform` (the ONE raw⇄display token
   scan: tasks + img markers + memo-links) MOVED to `Shared/Pipeline/` first (phone re-green, 677);
   desktop `TaskBoxAttachment` renders `- [ ]`/`- [x]` as toggleable checkboxes (checked = strike +
   muted line), a click flips the box and writes the flipped syntax back through `modelString` →
   `bodyBinding` → persists + `MacCloudEditSync` push (the phone sees the toggle). Hosted-snapshot
   verified. Return-continuation stays phone-only for now.
3. ✅ **DONE 2026-07-13 — PDF/file capture card (honest variant).** The document BLOB never syncs
   (no `MemoAsset.Kind.document`), so no fake first-page render: the card shows 📄 filename +
   "PDF · on your iPhone — its text is captured in the note" (the phone's A6 extraction already put
   the text in the body the Mac shows/searches/exports). Hosted-snapshot verified. NEW follow-up
   below. BONUS: `-snapshot-capture` switched to the hosted renderer — the sidebar's yellow-🚫
   ImageRenderer placeholder is GONE (sidebar snapshots work now); `pdf:<path>` arg renders the
   file-capture fixture.
3b. ✅ **DONE 2026-07-15 (sync + Open) — `.file` capture documents sync as `MemoAsset.Kind.document`**
   (additive kind, no migration). Phone `AssetMaterializer` captures the `.file` document; Mac
   `MemoCloudIngest.buildParts` adds a `document` part; `UploadService.prepareCapture` writes it into
   `capture_<id>/files/`; the Mac capture card (`CaptureSharedContentBlock`) gains an **Open** button
   (`NSWorkspace`) when the file is present. Golden test `testFileCaptureDocumentMaterializes`; desktop
   365 + mobile 678 green. **STILL OWED (follow-ups):** (a) the mock's true first-page inline render on
   the Mac; (b) C3's Mac-wire — run `PDFTextExtract.text(of:)` on the materialized PDF as a fallback when
   `sharedContent.text` is empty; (c) vault copy of the document on export. LIVE device round-trip owed.
4. Verify: UnitTests scheme + full `-skipMacroValidation` build + `-snapshot` PNGs (see
   [[native-ui-verification]] memory: sidebar can't snapshot; live-drive via UITests if needed).

**Board B — ✅ BUILT 2026-07-13 (chunks 1–5 in one pass; device/live eyeball owed):** shared
`LookbackProvider` + `PlaceCluster` moved to `Shared/Pipeline/` FIRST (phone re-tested green — 677),
then `JournalView.swift` to the mock: switch/rail/column/map-mode, cloud-store read-only w/
`MemoDuplicates.canonicalRows`, in-flight slim row, locked = 🔒 title-only, `-snapshot-journal`
hosted verification (lookback + map states eyeballed; annotation count-bubbles want a live-deploy
look). Original spec follows:
- Chunk order: (1) `Queue | Journal` mode switch (AppModel surface enum; RootView swaps the
  content pane; sidebar per mock). (2) SHARE FIRST, then build: move the phone's pure logic to
  `Shared/Pipeline/` — `LookbackProvider` (pure date math over [Memo]; Memo is shared) and the
  `PlaceCluster` grouping inside `SkriftMobile/Features/Journal/JournalMapView.swift` — so the Mac
  compiles the SAME rules (that's the whole point; don't re-implement). (3) Rail = mini month grid
  (dot density via `LookbackProvider.dayCounts`) + Places list. (4) Column = Looking-back cards +
  selected-day list; in-flight notes = slim row, NEVER a card (review-1). (5) Map mode = SwiftUI
  `Map` (fine on macOS 14) with PlaceCluster pins; a place click swaps the COLUMN (the rail never
  changes); ⨯ returns to Looking back.
- **Data source: the Mac's journal reads the CLOUD Memo store** (`MemoCloudStore.container`), NOT
  PipelineFile — the cloud DB has the full corpus (ingest is significance-gated; sync is not).
  Locked memos: list row shows title + 🔒 only; content stays behind the existing `LockGate`.
- Respect the flag: journal is read-only — never mutate Memos from the Mac journal (the Mac's
  write path stays MemoEnhancement/edit-sync only).

**Board C — SharedKit round 2 (UNBLOCKED 2026-07-13: all lanes done, no live branches; ONE chunk
per commit, both suites green each time — the round-1 recipe):**
0. ✅ **DONE 2026-07-13 — Mac sweep duplicate-tolerant.** Shared `MemoDuplicates` keeper rule
   (alive > most content > latest edit > first; `Shared/Pipeline/MemoDuplicates.swift`);
   `MemoDeduper` refactored onto it (677 mobile tests green); the Mac sweep iterates
   `canonicalRows` (351 desktop tests green incl. the churn regression + trashed-clone-never-
   shadows-keeper). CORRECTION to the original claim: there IS no Mac delete path keyed on
   `memo.deletedAt` (MemoCloudUpdate's comment is aspirational) — so no delete-flap existed; the
   real defect was divergent same-id rows flip-flopping ONE PipelineFile every sweep. Observed
   gap left on record: a memo trashed on the phone is never trashed on the Mac (no delete sync —
   pre-existing, deliberate for now). BONUS: full-scheme desktop build was red on ANY fresh
   regenerate — swift-transformers floated to 1.3.3 (breaks vs Swift 5.9) and transitive Jinja
   floated to 2.4.0 (ObjectKey API) → BOTH exact-pinned in project.yml (1.3.0 / 2.3.6).
0b. ✅ **DONE 2026-07-15 — shared lazy-RMS helper.** `averageRMS` (+ the buffer-path `rms(of:)`)
   extracted to `Shared/Pipeline/AudioRMS.swift`; the lazy `trimmed`/`wordCount` gate folded into a
   pure `BPEMerge.shouldDropAsPhantom(text:rms:)` overload (a lazy closure keeps BPEMerge
   Foundation-only). All 3 call sites (desktop file, phone file, phone buffer) now hit the ONE copy;
   both local copies deleted. New host-less test proves the RMS provider stays lazy for real
   transcripts + fires once for tiny ones. Desktop 352 + full MLX build + mobile 677 green.
1. ✅ **DONE 2026-07-13 — SpeakerTranscript → Shared** (`Shared/Pipeline/SpeakerTranscript.swift`,
   both twins deleted): the shared Sanitiser now parses conversations through ONE type. Turn =
   Identifiable + content-only `==` (id ignored — desktop's equality tests pass, mobile's ForEach
   works). Helper union, and the drift got FIXED in the merge rule: empty-safe join (Mac's rule) +
   preamble preservation (phone's rule — the Mac's twin used to DROP a leading [[img]] preamble on
   mergeAdjacentTurns). Both suites green (351/677) + full MLX build.
2. ✅ **DONE 2026-07-15 — LockGate → Shared.** The two byte-identical twins collapsed to
   `Shared/Session/LockGate.swift` (new `Shared/Session` folder, added to both app targets);
   one `#if canImport(UIKit)` picks `UIApplication`/`NSApplication.willResignActiveNotification`;
   the id key is unified on the memo-UUID **String** (`unlockedIDs: Set<String>`, was `Set<UUID>`
   on the phone). Model-typed `isLocked` + the phone's `unlock(UUID)` live as thin per-app adapters
   (`LockGate+PipelineFile.swift` / `LockGate+Memo.swift`). Desktop 352 + MLX build + mobile 677 green.
3. ✅ **DONE 2026-07-15 (share + rewire) — PDF text-extract → Shared.** The phone's inline
   PDFKit extraction is now `Shared/Pipeline/PDFTextExtract.swift` — a pure `normalize` core
   (trim/drop-empty/120k-cap, host-tested ×3) + `text(of:)` that runs `PDFDocument`; the phone
   drainer calls it (its now-unused `import PDFKit` dropped). Desktop 355 + MLX build + mobile 677 green.
   **Mac-wire FOLDED INTO 3b (below):** the Mac has NO PDF blob today (no `MemoAsset.Kind.document`),
   so there is nothing to extract at ingest — it already receives the phone-extracted `sharedContent.text`
   via sync (A3). Once 3b materializes the document blob on the Mac, wire `PDFTextExtract.text(of:)` at
   ingest as the fallback for memos missing the phone text.
4. ✅ **DONE 2026-07-15 — VocabularyBooster trust→apply core → Shared.** The identical tail of
   both `boost()` bodies (filter shouldReplace → resolve each canonical's aliases → keep the boost
   ONLY when ≥1 applied and EVERY replacement trusted) is now `Shared/Pipeline/VocabularyBoostCore.swift`
   (neutral `VocabularyReplacement` struct; an `aliasesFor` closure keeps FluidAudio's `vocab.terms`
   app-side). The phone's `allReplacementsTrusted` deleted; both boosters map their rescore output →
   the shared core. CTC spot + rescore ENGINES and the DEBUG tuning knobs stay app-side (per the board).
   Trust test repointed to the shared core + a new `appliedReplacements` test. Desktop 355 + MLX build
   + mobile 678 green.
5. ✅ **DONE 2026-07-15 — NamesCloudSync reconcile core → Shared.** The byte-identical phone + Mac
   `run` bodies now delegate to `Shared/Naming/NamesSyncCore.reconcile` (fold carriers → `NamesMerge`
   per-canonical LWW + voiceEmbeddings union → sorted-keys byte-compare → collapse to ONE carrier row
   via injected insert/delete; returns merged + localChanged). One shared encoder so the two can't
   churn-loop. Each adapter keeps its own differences: the phone's DevLog, the Mac's
   `cloudKitMacSyncEnabled` gate + `.namesDidChangeFromSync` post. The 5 `NamesCloudSyncTests` (through
   the phone adapter) cover the shared flow — first-sync, remote merge, embedding union, idempotent,
   collapse-dupes. Desktop 355 + MLX build + mobile 678 green.
6. ⚠️ **ANALYZED 2026-07-15 — do NOT collapse yet; the leniency is load-bearing.** Concrete finding
   from comparing `PhoneMetadata`/`SharedContent` (CompilerBridge) to the shared `MemoMetadata`:
   PhoneMetadata is DELIBERATELY looser — `Weather.temperature`/`Pressure.hPa` are `Double?` (shared:
   non-optional **`Int`**), `dayPeriod`/`pressure.trend` are `String?` (shared: non-optional **enums**
   `DayPeriod`/`PressureTrend`), and `Location` reads only `placeName` (shared requires lat/long). A
   naive collapse would make the STRICT shared decoder THROW on legacy RN/Python working-folder
   payloads (float temps, unknown enum values, lat/long-less locations) → silently drop ALL export
   frontmatter for old notes. `SharedContent` likewise keeps a snake_case (`shared_content`) fallback
   for demo seeds and stays desktop-side (mobile has its own; there is no shared `SharedContent`).
   **To actually do C6:** first give the shared `MemoMetadata` a lenient `init(from:)` (float→Int
   coercion, unknown-enum→nil, optional lat/long) — a CROSS-APP contract change the phone also decodes
   through — backed by GOLDEN ingest tests over real old working-folder payloads on BOTH sides; only
   then retire PhoneMetadata. That's its own deliberate chunk, not a mechanical dedup. Left as-is for now.
7. Cheap/optional — **DONE 2026-07-15 (Tuur asked for both merged):**
   - ✅ **FlowLayout → `Shared/UI/FlowLayout.swift`** — new `Shared/UI` folder added to both app
     targets; the `SkriftShare` extension's `DesignSystem/FlowLayout.swift` path repointed to it (the
     extension listed but never used it). Both app-local copies deleted. Desktop + mobile app + Share
     extension all build; desktop 355 + mobile 678 green; chip-wrap vision-checked on the fresh desktop
     `-snapshot` (tags row `#work ×`/`#ideas ×`/`+ #rewrite`/… flows cleanly, no clip/overlap).
   - ✅ **Karaoke → ONE `Shared/Pipeline/Karaoke.swift`** — the two apps use DIFFERENT functions
     (phone `activeWordIndex` lookup; desktop `wordTimes`/`activeCount`/`normalize` alignment), so this
     is single-home consolidation, NOT a behavior change: both functions now live in one shared `Karaoke`
     enum, each app keeps calling the one it used. (see the Karaoke commit for the details.)

**🐛→✅ DEVICE-FOUND FIX 2026-07-15 — Mac photos added-on-edit now materialize.** Tuur deployed the Dev
Mac and saw a note's `[[img_001/002/003]]` rendered as LITERAL text (photos never showed, would've
missed the vault). Root cause: the Mac writes a memo's photo files only on FIRST ingest
(`MemoCloudIngest`); the phone→Mac update path (`MemoCloudUpdate`) reflected the markers/manifest but
never wrote the image files, so any photo inserted while EDITING an already-synced note was orphaned.
Fix: `Pipeline/Ingest/MemoPhotoMaterializer.swift` writes any missing photo blobs + refreshes
`image_manifest.json` each sweep for already-ingested memos (idempotent; heals already-broken notes on
next launch), wired into `MemoCloudReconciler.sweep`'s update branch (nudges `lastActivityAt` when it
heals a row `apply` didn't touch). Also extracted `PipelineFile.workingFolder` — ONE derivation now
used by the resolver (`NoteBody.imageURL`), the exporter (`VaultExporter`), and the materializer. 3 new
host tests; desktop 358 + full MLX build green. **VERIFIED on real synced data:** the launch sweep
materialized all 3 photos of the reported note (manifest + `images/photo_..._00{1,2,3}.jpg` written
12:49:49, post-launch).
- ⬜ **Minor follow-up (noted, not fixed):** export image collision when two notes share the EXACT same
  title — `convertImageMarkers` names images `<safe-title>_NNN.ext`, so same-titled notes' images
  overwrite in the vault attachments folder. Uniquify by the note stem (which the .md already uniquifies)
  rather than the raw title. Low priority.

## ⭐ Phone↔Mac intertwining — "a thing done in one happens in the other" (2026-07-15, Tuur direction)

Audit of the two sync channels (2026-07-15): **phone→Mac is rich** (transcript, metadata blob, lock,
reminder, photos, OCR); **Mac→phone is narrow** — `MemoEnhancement` carries only body/title/summary.
That asymmetry is the root of the gaps. Order chosen by Tuur: **delete sync FIRST, then widen the
Mac→phone metadata channel.**

- ✅ **DONE 2026-07-15 — Delete sync (trash + restore mirror BOTH ways).** `Memo.deletedAt` is the
  synced carrier. Phone→Mac: `MemoCloudUpdate` mirrors trash/restore onto the row, watermarked by
  `PipelineFile.syncedSourceDeletedAt` (reflects only a real change → never un-trashes a pre-existing
  Mac-local trash; heals a note the phone binned that the Mac still showed). Mac→phone:
  `MacCloudDeleteSync` writes `memo.deletedAt` on a Mac trash/restore (wired at `SidebarView` softDelete
  + `RecentlyDeletedView` restore). Re-export skips trashed rows. Permanent delete stays device-local
  (both purge from the same 14-day stamp). Also folded the 4th working-folder derivation (`DesktopTrash`)
  onto `pf.workingFolder`. Desktop 362 + MLX build + mobile 678 green; core logic unit-tested (5 tests).
  **LIVE round-trip owed** (needs both Dev apps): trash on Mac → gone on phone; trash on phone → gone on
  Mac; restore either way mirrors.
- ✅ **DONE 2026-07-15 — widen the Mac→phone channel: tags + importance.** Both are plain `Memo`
  fields that already sync, so — like delete-sync — the Mac just writes them onto the `Memo`. (a)
  phone→Mac: `MemoCloudUpdate` now reflects `memo.tags`/`memo.significance` onto `pf.tags`/
  `pf.significance` (content-based, like the rest); `MemoCloudIngest` also backfills `pf.tags = memo.tags`
  at first ingest (the Mac's derivation only fills `tagSuggestions`, so the phone's applied tags never
  appeared before). (b) Mac→phone: `App/MacCloudMetaSync.mirror` writes `memo.tags`/`memo.significance`
  from the row, wired via `.onChange(of: file.tags/significance)` on `NoteProperties` (echo-guarded —
  no-op when the memo already matches). Desktop 364 + MLX build green (2 new reflect tests). **LIVE
  round-trip owed** (needs both Dev apps): tag/importance edit on Mac → phone, and phone → Mac.
- ✅ **DONE 2026-07-15 — Mac `[[` link picker** (create memo-links on the Mac, phone parity). Typing
  `[[` in the review body (`BodyTextView` coordinator detects the two-char trigger at the caret) opens
  `MemoLinkPopover` — a search field over every other live memo (title + date subtitle, most-recent
  first; `NoteDisplayView.linkCandidates` lazily fetches, memo-UUID rows only, trashed excluded).
  Picking inserts `[[memo:UUID|Title]]` → `spliceMemoLinkChips` renders the chip → `parent.text` write
  rides the Part-B edit sync to the phone. Popover snapshot-verified (`-snapshot-linkpicker`); desktop
  364 + MLX build green. **LIVE eyeball owed**: does `[[` open it + does pick insert the chip (NSTextView
  typing isn't headless-drivable). Follow-up idea: also link to EXISTING vault notes (the Backlink-Weaver
  title index — backlog line ~539), not just Skrift memos.
- ⬜ Later gaps from the audit:
  reminder alarm on the Mac; (by-design, NOT gaps: Mac shows `[[links]]`+polish, phone shows raw; Mac
  has the LLM; Mac writes Obsidian). Open Q for a future chat: should trashing also DELETE the note's
  Obsidian `.md`? (destructive to the vault — needs Tuur's call before building.)

### (resolved) device-test findings 2026-07-15 (Tuur, iPhone build 76 + latest Mac Dev)

**✅ FIXED + DEVICE-CONFIRMED 2026-07-16 — the sweep read STALE memos.** Tuur re-tested: a phone edit
(importance 0.1 + tags #testy/#more tags + text + photo + a link) synced to the Mac — *"took a while to
sync but it worked."* phone→Mac is live now. Root cause found:
`reconcile()` read the cloud store via `cloud.mainContext`, and a CloudKit import writes the STORE but
does NOT refresh `mainContext`'s already-registered `Memo` objects — so the sweep saw a stale memo and
never noticed the phone's later delete/tag/edit (a first-seen memo is fresh → ingest worked; Mac writes
mutate the same context → Mac→phone worked). Fix: the sweep now reads through a fresh `ModelContext(cloud)`
(empty row cache → every fetch hits the store). Same fix applied to `NamesCloudSync`/`VocabularyCloudSync`
(same trap). Added an os.Logger line (`reconcile: ingested N, reflected M`) to confirm on the next device
pull. Desktop 365 + MLX build green. **RE-TEST on device:** phone delete/tag/importance edit → the Mac
reflects on the next sweep (refocus the Mac app to force one).

**THE HEADLINE BUG — phone→Mac sync is one-directional right now.** Tuur's words: *"whatever I do on
the Mac syncs to the phone, but what I do on the phone does NOT sync to the Mac."* Mac→phone works
(the Mac writes the shared `Memo`/`MemoEnhancement` → phone auto-mirrors via NSPersistentCloudKitContainer).
Phone→Mac does NOT reflect. The phone's changes DO reach the Mac's `memo_cloud.store` (78 memos confirmed
via sqlite), so the data arrives — but the Mac's PipelineFile never updates. **Leading hypotheses for
next session (diagnose FIRST, everything below hangs off it):** (1) the reconciler SWEEP isn't triggered
on a CloudKit import while the Mac app is already foregrounded (triggers = launch / active / CK-import —
check the CK-import trigger actually fires + `cloudKitMacSync` gate is on); (2) CloudKit Mac↔iCloud
propagation latency (the change hadn't landed in `memo_cloud.store` when checked — but Tuur tested over
several minutes); (3) a bug in `MemoCloudUpdate.apply` reflect despite green unit tests. Instrument the
sweep (does it run? does it find the memo with the new deletedAt/tags? does apply return true?).

Per-feature verdicts:
1. **Delete sync — phone→Mac ✗ / Mac→phone ✓.** Restore on Mac → back on phone ✓. Delete on phone →
   still on the Mac (not reflected) ✗.
2. **Tags — phone→Mac ✗ / Mac→phone ✓.** Mac tag add → phone gets ALL the Mac's tags ✓. Phone tag add
   AND phone tag delete → NOT reflected on the Mac ✗. Worse: a Mac tag write pushes the Mac's whole set
   down and OVERWRITES a tag the user had just deleted on the phone (the phone's deletion is lost).
3. ✅ **FIXED 2026-07-15 — Importance now editable on the Mac.** Cause confirmed:
   `SignificanceCircles(value:, enabled: file.steps.enhance == .done)` in `NoteProperties` disabled the
   control (0.5 opacity + hit-testing off) until the note was enhanced. Dropped the gate → always
   editable (phone parity + it now syncs back via MacCloudMetaSync). Device re-verify owed.
4. **Memo links `[[ ]]`:** Mac→phone ✓ (link appears on phone; clicking on either opens the SAME target).
   - (a) ✅ **FIXED — chip "Untitled" on the phone.** My live-title fix over-reached: `liveLinkTitle`
     returned `title ?? firstTranscriptLine ?? "Untitled"`, so a title-less capture/Maps note resolved
     to "Untitled" and CLOBBERED the good snapshot. Now returns nil when there's no REAL title → the chip
     keeps the snapshot (the name the link was made with). Mac `liveTitle` made symmetric.
   - (b) ✅ **FIXED — backlinks missing on the phone.** `recomputeBacklinks` scanned only `memo.transcript`,
     but a Mac-made link lives in the enhancement COPYEDIT (not the transcript). Now scans transcript +
     copyedit (new `NotesRepository.allEnhancements()`). Device re-verify owed.
   - (c) ⬜ transient "lost the link" on the Mac once (couldn't repro; 2nd try kept it). Watch for
     link-persistence flakiness — NOT fixed (unreproduced).
   - (d) ✅ **FIXED 2026-07-16 — Mac chip showed `memo_<UUID>`.** A phone-made link to a title-less
     note rendered the raw filename on the Mac: `liveTitle` used `queueTitle`, which falls back to
     `cleanFilename(filename)` (= `memo_<UUID>`). Switched to `enhancedTitle` only (the real title) →
     no enhanced title → nil → the chip keeps the snapshot (the phone's title). Device re-verify owed.

**🐛→✅ TRANSCRIPTION SLOWNESS 2026-07-16 — NOT the engine; the embedder starved the ANE.** Tuur saw
a 13s clip take ~1 min. Device log showed `embedder: cold load DONE in 117.7s` — the P8 "Related notes"
embedder (EmbeddingGemma-300M) cold-loading on the SAME Neural Engine as ASR, blocking the transcription
until it finished (transcription completed right after the embedder). Fix: `TranscriptionActivity` flag
(the transcriber raises it; `GemmaEmbedder.prepare` YIELDS its cold load while active, capped 30s so a
long book transcribe can't defer Related notes forever). The transcription engine itself is fine.
Desktop 365 + mobile 678 green. Device re-verify owed (record a clip while the embedder is cold).
5. **Photos — ✅ WORKS on device.** Materialization fix confirmed: photos render on the Mac.
6. **PDFs (3b) — ✗ not synced to the Mac.** A shared PDF shows on the phone (first-page render + text);
   the Mac doesn't get it. LIKELY because the tested PDF is an OLD capture (pre-build-76) — 3b only
   materializes a `.document` asset for captures made on the updated phone. RE-TEST with a FRESH PDF share
   before treating it as a bug.
7. **Filter/sort — parity gap (SCOPED 2026-07-15; mock-first before building).** They're different
   models: Mac (`QueueFilter` All/NeedsWork/Done + sort Newest/Oldest/Title) is review-workflow;
   phone (`MemoFilter`: place · has-photos · unsynced · date-range; `MemoSort`: added/edited/recorded/
   oldest/longest, via `SortFilterSheet`) is content-browsing. The gap on the Mac = the phone's CONTENT
   filters (place, has-photos, date-range) + the extra sorts (edited/recorded/longest). "Unsynced only"
   doesn't map to the Mac (everything there is synced). NOT a blind port — the Mac sidebar is compact, so
   where a richer filter set lives is a layout call → do a mock-first pass (which phone filters belong on
   the Mac's review context) before building.

Next-session order: A/B/C all ✅ FIXED + DEPLOYED (see above). (D) re-test 3b with a fresh PDF capture
[device — Tuur]; (E) Mac filter/sort parity [mock-first]. Then re-run the whole checklist.

### 🖼️ image-at-sentence-end reflow — ✅ BUILT + hostPNG-verified 2026-07-16 (DEVICE ROUND OWED)

**Status:** BUILT + tested + Mac-hostPNG-eyeballed. Device round on both apps is the only thing owed.
- **Shared rule:** `Shared/Pipeline/BodyTransform.swift` `snapImages(_:) -> SnapResult` (snapped display/export
  string + a raw→snapped offset map). Moves each MID-SENTENCE `[[img_NNN]]` to its sentence end as a `\n\n`
  block; boundary photos normalize in place; **idempotent**. Handles: `\n\n`-wrapped (injector) AND inline
  (Gemma-reflowed) markers, two-in-a-sentence (both blocks in order), photo-before-any-sentence (block at top),
  newline-as-terminator, and a word-merge seam guard. 10 host-less tests in `BodyTransformTests`.
- **Both renderers:** mobile `NoteBodyView.load` builds from `snappedImageBody(...)` + `applyTierStyling` maps
  name spans raw→snapped→display; desktop `BodyTextView.render` builds storage from the snapped model, the
  `updateNSView` no-op check compares `modelString` vs `snappedImageBody(text)` (idempotent, no re-render loop),
  and `suggestedRanges` maps `ambiguousNames` offsets raw→snapped. Killed the giant inline caret on the Mac.
- **Export:** `VaultExporter` snaps the compiled markdown before `convertImageMarkers`, so the `![[…]]` embed
  drops beneath the whole sentence, matching the screen. (Phone `ObsidianPublisher` doesn't embed inline photos
  yet — separate pre-existing gap, no snap needed there until it does.)
- **Design decision (honored):** display + export snap; the stored RAW keeps the marker at its recorded
  moment — UNTIL a user EDIT, when `reconstruct`/`modelString` writes the snapped form. That's safe: edited
  notes are `userEdited`-trusted and never re-injected/re-snapped, and the true moment lives in
  `imageManifest.offsetSeconds`. So "raw keeps the marker" holds for the display path (the common case).
- **Verify done:** 366 desktop UnitTests + 687 mobile SkriftMobileTests green; full MLX desktop build green;
  Mac hostPNG `-snapshot-photoblock` eyeballed (sentence whole, photo block beneath, rounded corners) — see
  `Features/Shell/Snapshot.swift` `renderPhotoBlock`. **DEVICE ROUND OWED** (both apps, build-number bump per push).

_(original brief kept below for reference)_

Tuur's #1 next build. He approved the layout via an inline before/after mock. **Ship the shared rule +
render a REAL hostPNG of the red-cup note before it goes to device.**

- **The problem:** a photo's `[[img_NNN]]` marker is pinned to the exact moment it was taken, which
  lands MID-SENTENCE. Both apps render it there — the Mac INLINE (text wraps around it + a giant
  image-height caret), the phone as a block-at-marker (still splits the sentence). Both weird.
- **APPROVED layout:** when a marker falls inside a sentence, render the sentence WHOLE, then drop the
  photo to its own **full-width block** right after it (snap to the next `.`/`!`/`?`/newline). Rounded
  corners already ship. This also kills the giant caret (photo no longer shares a line with text).
- **Contract:** ONE shared rule (extend `Shared/Pipeline/BodyTransform.swift` — it already has
  `imageBreaks`/`Piece` parsing), used by BOTH renderers AND the Obsidian export, so nothing drifts.
  The RAW text keeps the marker at its exact spot (moment fidelity); only the DISPLAY + EXPORT snap.
- **Edge cases (handle the obvious way):** photo before any sentence → block at top; two photos in one
  sentence → both blocks in order after it; always snap to the sentence end, never mid-word.
- **The hard part (why it's a real reflow, not a tweak):** the current architecture ties an image's
  DISPLAY position to its raw marker position (the Mac's `splice` inserts the attachment AT the marker;
  `modelString`/`reconstruct` maps it back by scanning). Snapping to the sentence end DECOUPLES display
  position from raw position — the reconstruct + caret/edit handling must survive that. Mac render =
  `BodyTextView` (`splice`, `spliceMemoLinkChips`, `modelString`); phone = `NoteBodyView`
  (`attributed(from:)`, `reconstruct`, `BodyTransform.pieces`).
- **Verify:** hostPNG the real note on the Mac (`-snapshot-memolinks` is the NSTextView-hosted mode; add
  an image to its seed or a new `-snapshot-photoblock` mode), eyeball, THEN device round on both apps.
  Mock-first is satisfied (design approved) — build to it.

**Device-verify checklist owed (fold into the next device session):** Mac-added vocab word →
phone (and deletion → Mac) [LWW fix 6f78ac1]; lock on phone → Mac refuses export + gates body,
unlock → auto re-export; search a photo's OCR text ON THE MAC; Mac-exported memo-link opens the
target note in Obsidian; 🔔 reminder row shows.

**Cautions for the next agent:** commit per chunk with explicit paths; regenerate xcodegen after
every pull; mobile tests = `-only-testing:SkriftMobileTests` (UI suite has known iOS-26 failures);
sim "preflight/Busy" flake → `xcrun simctl shutdown all && xcrun simctl erase "iPhone 17"`;
desktop full build REQUIRES `-skipMacroValidation`; never run two Skrift Dev instances; promote
prod deliberately (idle) only; roadmap.yaml updated in the SAME change as shipped work (exactly
one `now`); mock-first for any NEW UI beyond these signed specs.

- 🅿️ **Review note-detail mock PARKED** (Tuur, 2026-07-18): `mocks/review-note-detail.html` — the
  read-only detail + "Process on this Mac" fix for the purple "Not in the queue" dead-end. Parked
  because the Fading lifecycle ATE most of its audience (untouched old notes — the alert's main
  source — now drain themselves out of Review). REVIVE TRIGGER: the alert annoys again in practice
  (clicking a <30d untouched note, or a touched-but-unflagged note — those still dead-end). Mock is
  sign-off-shaped; build as drawn when revived. Its 2 open Qs ride the revival.

### ⭐ CONTINUE HERE — session end 2026-07-18 ~2am (the wave-2 + lifecycle marathon chat)
**Everything committed + PUSHED; both Dev apps at HEAD (Mac redeployed · phone b85).**
- ✅ THIS CHAT: SharedKit wave 2 complete (6 extractions, 3 drift bugs fixed, 2 dead-code deletes) ·
  Review label single-sourced · phone note-swipe off · map camera/dive/in-frame round · rail
  mini-map (mock→picked→shipped) · **FADING LIFECYCLE end-to-end** (design→mock v3→shipped
  cross-app→3 device fix rounds: auto timers, un-squared ⋯ dot, unread-dot semantics).
- 🅿️ PARKED: review-note-detail mock (below, revive trigger inside) · vault-read direction (🔭
  below, Huginn-shaped) · 6 Palette DriftedPair reconciles (one eyeball round → one-liners).
- ⬜ TUUR'S EYES (casual, no chat needed): fading round (dot→shelf→dark, Keep, sweep-all, phone↔Mac
  convergence) · the b81-era carried items (Journal gate arc %/PREPARING/N-of-M, ~2s search
  highlight, ⌥⌘C/badge/hover-✕/tooltip, light-mode fills) · map dive re-wiggle.

### 🍂 NOTE LIFECYCLE — "Fading" auto-cleanup · DESIGN LOCKED 2026-07-17 (Tuur + chat session), mock round next
**The rule: a note you never invested in fades out by itself; anything you touched stays until you say otherwise.**
- **Touch-list (LOCKED — any of these = never fades):** significance > 0 · transcriptUserEdited ·
  title set · manual tags · locked · remindAt · typed capture annotation · linked-to by another note
  ([[memo:]] backlink, scanned at sweep time) · keptAt (rescued). Explicitly NOT touches (Tuur):
  photos attached, bare share-captures. Guards: in-flight + already-trashed excluded.
- **Timers (LOCKED "for now"): 30 → 30 → 14.** Untouched 30d → Fading shelf (leaves river/day/map/
  search defaults); 30d more → auto-move to Recently Deleted (existing deletedAt); existing 14d purge
  ends it. Every stage visible + one-tap rescue; rescue sets keptAt (permanent).
- **Sync shape:** fading is DERIVED (no stored state, no migration, retroactive for free); ONE new
  additive synced field `keptAt: Date?`; the 60d sweep just sets `deletedAt` (already syncs/restores/
  purges; idempotent per device). Shared rule module (`MemoLifecycle.isFading(...)` in Shared/) —
  phone + Mac filter through ONE copy, tests both suites.
- **First-run guard (P0-trauma rule):** the inaugural sweep NEVER auto-trashes — everything eligible
  lands visible on the shelf with an explicit "sweep now?" prompt; timers only run after that.
- **Placement input (Tuur):** phone Recently Deleted's scroll-to-bottom spot is BAD ("stupid
  position"); Mac's bottom placement is fine. The Fading shelf must not inherit the bad spot — fix
  Recently Deleted's phone placement in the same mock round.
- 🎨 MOCK ROUND OPEN: `mocks/fading-shelf.html` — Mac shelf (column swap; rail row paired with
  Recently Deleted at the rail bottom, count-badged, hidden when empty), first-run sweep prompt,
  Keep-only actions, countdown colors; phone v3 PICKED (v1 chips + v2
  Review-stack row both rejected — vertical space): behind a ⋯ in the Notes header actions
  cluster, amber dot when something's fading, both shelves as menu items; Notes loses its old
  bottom Recently Deleted row. Remaining open Q: search "include fading" toggle (recommend SKIP).
  ✅ SIGNED OFF ("good!") + BUILT SAME SESSION 2026-07-18 — see FEATURES.md "Fading lifecycle" row:
  Shared MemoLifecycle (+keptAt) · phone ⋯/shelf/sweep (b83) · Mac shelves + sweep. Search toggle
  SKIPPED per recommendation. 📱 b83 round findings, FIXED same hour (b84 + Mac redeployed):
  (1) the ⋯ amber dot rendered SQUARE sometimes — an out-of-bounds overlay offset gets mangled by
  the menu-source preview snapshot; dot now lives INSIDE the label frame (+compositingGroup). Menu
  open latency = system Menu behavior, not tunable — revisit as Button+sheet only if it keeps
  annoying. (2) "Start the timers" arming gate CUT on Tuur's call ("why is it not automatic?") —
  sweeps are fully automatic from install; the 14d reversible trash + shelf counts + the dot are
  the safety; "Sweep all now" stays as a plain shelf action both apps. Mock's first-run section is
  now historical. (b84 round) Tuur: "is the dot always there?" — it was (steady 30-60d trickle = permanently lit =
  no signal). b85: UNREAD semantics — the ⋯ dot lights only for notes that ENTERED fading since the
  shelf was last opened (shared `fadeEntersAt` + per-device lastSeen stamp; opening the shelf clears
  it). ⬜ re-eyeball: dot lights fresh → opens shelf → goes dark; Keep; sweep-all; cross-device
  convergence.

### 🔭 PARKED DIRECTION — read the Obsidian vault INTO the app (Tuur, 2026-07-17)
Use vault content (hand-written notes) for linking/Connections/Related, maybe Review. Constraints +
sketch from the chat think-pass: app's-own-code scans only, on-device models only (the privacy rule
allows exactly this — no cloud AI ever); NEW separate consent ("index my vault" ≠ journal consent);
Mac-first (the phone has no vault; embeddings never sync by design); the indexer MUST dedupe/exclude
Skrift's own published exports or every note matches its own export (frontmatter/stem identifies
them); vault-note identity across renames + FSEvents change-watching are the hard bits; start with
Connections/Related + search rows (surface exists), Review-resurfacing of vault notes = later/maybe.
Aligns with the standing "push / pull-for-search" model. Roadmap node = a Huginn conversation.

### 📱 Live round findings — 2026-07-16 night (Tuur, Mac Dev @ HEAD + phone build 82) — ALL FIXED SAME SESSION
- ✅ **Mac still said "Journal"** (sidebar pill + column header) while the phone says "Review" —
  the label had forked AGAIN (the 2026-07-07 rename only landed on the phone). Fixed by
  single-sourcing: `Shared/UI/SharedCopy.reviewTitle` now feeds the phone tab + screen title AND
  the Mac pill + header (5 sites, zero literals left). Snapshot-verified on the Mac fixture.
- ✅ **Swipe-between-notes OFF** (phone) — horizontal page-swipes fought text editing (Tuur).
  `.scrollDisabled(true)` on the detail pager; structure kept — memo-link hops + initial jump
  still work programmatically. Deployed in build 82.
- ✅ **Map glitchiness (Tuur report) — 3 bugs found by code-read, all fixed**: (1) `Map` had NO
  camera binding → automatic framing re-fit ALL pins on every span-driven re-cluster, snapping the
  view back mid-gesture (THE glitch; mechanism-certain, feel-verify on next wiggle); (2) clicking a
  place row while in map mode never moved the camera → now `focus()` flies to the place (0.3°
  span); (3) selection highlight vanished when zoom-out merged pins (compound "a+b" ids vs exact
  match) → id-component matching. Suites + MLX green, Dev redeployed.
- ✅ **Rail mini-map SHIPPED** (mock `review-minimap.html` #m1 — Tuur picked A 2026-07-17): ambient
  `MKMapSnapshotter` shot in the rail under PLACES (static — no live Map idling), fitted to ALL pins
  via new shared `PlaceCluster.fitRegion` (3 tests), same merged clusters drawn on top (+N badges),
  POIs excluded, "click → full map" → map mode fitted to every pin, no place pre-selected; hidden
  when nothing located; river untouched. Fixture vision-checked (real Lisbon tiles + pins); Dev
  redeployed. ✅ click-through eyeballed by Tuur 2026-07-17 → 2 findings, FIXED same hour:
  (1) fit-all entry showed NOTHING below the map (selectedPlace nil) → now lists ALL located notes
  newest-first, narrowing on pin/place pick; (2) rapid zoom in/out stuttered → clusters cached per
  refresh (build() was in every body eval) + span commits only on >20% zoom change (each commit
  tears down every annotation). Round 3 (same night): "All places" → **IN-FRAME list** (map = the filter, Tuur's intuited model:
  pan/zoom refines the notes below; fit-all entry starts with everything); **pin tap = DIVE** (flies
  down to split a merged pin — the fast path for deep zoom, scroll speed isn't tunable; tap the
  selected pin again = back to frame mode); rail place click dives city-level too (was regional 0.3°).
  ⬜ re-wiggle owed.
- ℹ️ **Map on the Mac: already BUILT** (journal-desktop mock v2 shipped with the Journal lane) —
  click a place row under PLACES to swap the reading column for the map; clicking a calendar day
  swaps back. Not a gap, just undiscovered.

### 🕸️ CONTINUE HERE — Connections SHIPPED (2026-07-16); 🧭 SharedKit wave 2 SHIPPED same evening (all 6 ranked items ✅ below + 2 clone-mode items; i10/MemoSaver items fold into their own lanes); STILL OWED: Tuur's Dev eyeball round (Dev at /Applications is ~10 commits behind — redeploy first: build → pkill → ditto → open), the phone device round (blocked on iPhone attached), and the 6 Palette DriftedPair reconciles (one eyeball round, then each collapse is a one-liner)

**2026-07-20 (panel polish chat):** Tuur's eyeball caught the panel's hot borders — root cause:
`Theme.hairline` (pure white) used at 0.25–0.6 where house/mock = 0.02–0.08; fixed (606dd35,
before/after snapshot-verified). Same session: **top-K cap** — Mac showed EVERY ≥0.45 match
(phone caps at 4; unbounded at corpus scale) → new `RetrievalTuning.cappedRelated` (shared,
unit-tested): closest `relatedKMac`=7 shown, the genuinely EARLIEST match always swapped in so
the Date rail's FIRST MENTION can't lie, "Show all N" expander (per-note reset), Closest
subtitle → "showing 7 of N" when capped. Dev at /Applications redeployed this session.

**SESSION-END STATE (2026-07-16 eve — all committed, main @ 522cae5, 31 local/unpushed):**
- ✅ VERIFIED this session: shared index+embedder+gate (both unit suites green per chunk: 372 desktop /
  687 phone); full MLX desktop builds green; panel hostPNG fixture vision-checked; Tuur's LIVE Dev round:
  download→PREPARING→indexing→panel all work on the real 19-note Dev corpus; amber warm-text eyeballed.
- 🌓 BUILT, NOT YET EYEBALLED: the ~2s lingering search-highlight (582cdfd — flash-too-fast fix,
  deployed, one look owed); ⌥⌘C/badge/hover-✕/tooltip on real corpus; light-mode amber fill on Mac.
- ⛔ BLOCKED on iPhone attached: the phone device round — upgraded Journal gate (real % + PREPARING +
  N-of-M, sim-compiled only), phone light-mode warm fill, panel↔phone cross-checks.
- Next chat's HEAVY work = **🧭 SharedKit wave 2** (list below, ranked; SharedContent first) — the
  scanning/triage is DONE, only the fixing remains; tree is clean, tool = `python3 tools/twin-scan.py`
  (+ `--clones`).

### (history) Mac Connections panel: ✅ MOCK SIGNED OFF 2026-07-16 ("oke im down!") → BUILT same day

**THE SPEC = `mocks/related-panel.html` v3** (3 review rounds, all picks in the mock's decisions block):
one panel + Date⇄Closest pill · P1 importance decimals (warm ≥0.8, unrated = nothing) · closeness =
hover tooltip "58% match · shares: …" (raw cosine ×100, %-format, NEVER ambient) · hover ✕ "not related"
per-note hide · in-panel consent gate (295 MB EmbeddingGemma, one consent also unlocks Mac Journal
search) · collapsible w/ count badge ⌥⌘C · REPLACES the bottom LINKED FROM strip · #m6 polish parked.
**Build phases:** (1) ✅ DONE 2026-07-16 (chunks A/B/C, suites green each): index core →
`Shared/Retrieval` (be75213); GemmaEmbedder + TranscriptionActivity shared, Mac binds the SAME
CoreML-LLM EmbeddingGemma — deployment 15.0, model cache `~/Library/Application Support/Skrift/
EmbeddingModels` shared dev+prod (5f5df0d); `ConnectionsIndexService` (consent key = phone's
`journalIndexEnabled`, REAL download progress via the package's onProgress, sweep N-of-M progress,
PipelineFile→MemoSnapshot with metadata `recordedAt` as the thread axis, sweeps ride reconcile+runs,
Mac raises the shared ANE-yield flag around engine work).
(2) ✅ BUILT 2026-07-16 — `ConnectionsPanel.swift` (pure `ConnectionsPanelBody` + live wrapper +
`ConnectionsModel`): Date⇄Closest pill, rail w/ this-note card + FIRST MENTION/CLOSEST MATCH flags,
flat closest rows w/ hover-✕ hide (per-note defaults list), P1 importance decimals (warm ≥0.8, unrated
= nothing), why-chips (people ∩ via [[wikilinks]], tags ∩, shared ≥5-char terms), closeness = `.help`
tooltip "N% match · shares: …", in-panel gate → REAL download % → indexing N-of-M → empty, LINKED FROM
moved in (bottom strip DELETED from NoteDisplayView), collapse ⌥⌘C + count badge (app-wide AppStorage).
hostPNG fixture mode `-snapshot-connections` (4 states) — vision-checked, 2 rounds (count-chip contrast,
CTA/progress offscreen-render fixes). DEVIATION from mock, deliberate: backlinks render below the gate
even pre-consent — consent must not cost the old LINKED FROM strip.
(3) 🌓 LIVE ROUND STARTED 2026-07-16 (Tuur, Dev app): download→index→panel flow WORKS end-to-end
(19-note Dev corpus). FIRST FINDING fixed same hour: after 295/295 MB the CoreML compile/ANE load ran
with the bar looking FROZEN → new `.preparing` state ("Compiling for the Neural Engine…"), plus
`.finding` ("Finding connections…") so a cold engine on a first query never shows a false "No
connections yet". Mock synced (#m4 preparing close-up). SECOND FINDING fixed: warm circle FILL in
LIGHT mode = dirty brown (the accent+amber mix on white) → light shows plain amber, dark keeps the
mix — BOTH apps. ⬜ rest of the eyeball: rows on real notes, pill, hover-✕, tooltip, ⌥⌘C/badge.
⬜ then the phone round. ⬜ FEATURES.md row + roadmap tick owed — BLOCKED on the other session's
uncommitted edits; fold in when they land.

**NEXT CHUNK (Tuur's live-round Qs, 2026-07-16):**
- ⬜ **Shared `RetrievalGate` core** (Shared/Retrieval): the state machine gate/downloading/preparing/
  indexing/finding/ready + the user-facing copy strings, ONE source; Mac panel re-renders from it and
  the **phone's Journal gate adopts it** — real download % (the `GemmaEmbedder.downloadProgress` hook
  exists, phone shows an indeterminate spinner today), PREPARING during the ~2-min A15 ANE compile
  (today the spinner sits frozen across download AND compile — worse than the Mac's bug), sweep N-of-M
  (shared `sweep(onProgress:)` exists).
- ⬜ **Mac search-jump parity (VERIFIED GAP)**: Mac search filters the sidebar (incl. photo-OCR text ✓)
  but opening a result lands at the TOP of the note — no scroll-to-match + flash like the phone. Needs
  an NSTextView ranged scroll + temporary highlight in BodyTextView; device-eyeball verify (hostPNG
  can't capture the flash).
- ✅ **DECIDED (2026-07-16, v1)**: the hover-✕ hide list stays **per-device** — consistent with the
  per-device index (the pairing it hides only exists in THIS device's ranking), and syncing it would
  grow the CloudKit contract (the spine) for marginal value. Revisit only if device use shows it
  annoying in practice.
- ⬜ (small, from Tuur's Q) **photo-OCR search edges on the Mac**: search MATCHES OCR text of synced
  memos (`imageOCRText` mirror ✓, phone runs the OCR), but (a) Mac-local ingests never get OCR'd (no
  Mac-side indexer), and (b) an OCR-only match can't flash in the body (the text isn't there) — could
  scroll to the matching `[[img_N]]` attachment instead.
Suites green per chunk, ledgers same commit.

## 🧭 SharedKit wave 2 — twin-scan triage (2026-07-16, tool: `python3 tools/twin-scan.py`)

First run: 13 file twins · 21 type twins · 40 string twins. Deliberate twins (no action): parity
test files both suites; NamesCloudSync/VocabularyCloudSync thin adapters (cores shared 2026-07);
RootView/SettingsView/RecentlyDeletedView/NoteBody = per-platform surfaces (rules already shared).
**Extraction candidates, ranked:**
- ✅ **SharedContent** — DONE 2026-07-16: ONE typed struct `Shared/Model/SharedContent.swift` (enum
  `ShareContentType` both sides; desktop consumers flipped string→enum; SkriftShare target repointed).
  Goldens FIRST (`SharedContentParityTests`, both suites) — which caught that the desktop's snake_case
  `shared_content` fallback was DEAD code (wrapper decode always succeeds → fallback unreachable, no
  producer since the RN era): deleted, camelCase pinned as the contract; unknown `type` → nil (no
  junk-typed records). Desktop 376 + mobile 691 + full MLX build green.
- ✅ **AppPaths** — DONE 2026-07-16: the name was declared per-app with DIFFERENT members (the
  worst twin class — a shared file referencing it would silently bind either). Now ONE
  `Shared/Model/AppPaths.swift` with `#if os(iOS)`/`#if os(macOS)` sections (LockGate pattern);
  `names.json` literal hoisted to one `namesFileName` constant. Suites + MLX build green.
- ✅ **Theme palette values** — DONE 2026-07-16: `Shared/UI/Palette.swift` = ONE hex table; both
  Themes keep their dyn wrappers but source cross-app tokens from it (agreed: surface/accent/green/
  amber/red/nameLinked). **FOUND 6 already-drifted tokens** (light columns tuned twice): bg,
  textPrimary/Secondary/Tertiary, nameSuggest, nameSuggestLine — kept per-app as explicit
  `DriftedPair`s so ZERO pixels changed (desktop PROVEN: 6 snapshot fixtures byte-identical
  pre/post; deterministic renderer control). ⬜ RECONCILE the 6 DriftedPairs after an eyeball
  round (each collapse = a one-line change now). Suites + MLX build green.
- ✅ **TranscriptionService/TranscriptionResult + DiarizationService/DiarizationOutput/Diarizing** —
  DONE 2026-07-16: contracts + pure passes → `Shared/Pipeline/{TranscribingContract,DiarizingContract}.swift`
  (TranscriptionResult, ONE `Transcribing` protocol — mobile's `Transcriber` renamed, buffer path a
  requirement w/ spill-to-WAV default; DiarizationOutput + unified `Diarizing` w/ `targetSpeakers`;
  SpeakerAudio clip+window constants; SpeakerIdentification identify/clusterToTarget behind an embed
  closure; SpeakerClustering moved to Shared). FluidAudio bindings stay per-app in the engine layer.
  BONUS: the Mac engine now honors `targetSpeakers` (force-to-N was phone-only) — substrate for the
  "per-note Split speakers on Mac" fast-follow (FEATURES row 29), UI still owed.
- ✅ **NamesStore** — DONE 2026-07-16: ONE `Shared/Naming/NamesStore.swift` (the twins' load/save/
  livePeople/addVoiceEmbedding were already line-identical; desktop's writeWithSmartBumps/
  upsert(replacing:)/seedRoster/prune are now the one superset + the phone's convenience upsert kept).
  Phone editor now saves through `upsert(_:replacing:)` — same path as the Mac (rename keeps
  enrollment via replace, no tombstone+re-attach dance). Semantics note: delete now tombstones
  WITHOUT voiceprints on both apps (was: phone kept them on the tombstone) — deleted people don't
  carry voices, matching what LWW sync already made effective. Phone additionally GAINS (inert,
  unwired): seedRoster + pruneOldTombstones (the phone never pruned tombstones).
- ⬜ VocabularyBooster.boost() cores + SpeakerTranscript — already tracked above (SharedKit wave 1
  follow-ups), confirmed by the scan.

**`--clones` mode (added same day — normalized-token shingles, catches RENAMED/adapted copies):**
- ✅ **PersonEditorView ↔ PersonEditor** — DONE 2026-07-16: editing SEMANTICS → one
  `Shared/Naming/PersonEditCore.swift` (materialise/displayShort/aliasDemo/isEnrolled; 9 tests both
  suites); chrome stays per-platform. THREE behavior drifts fixed by the unification: (1) phone
  RENAME dropped the voice enrollment (tombstone + fresh upsert) — now carries + re-attaches
  voiceprints (the Mac's rule); (2) Mac allowed saving a person with NO alias (who never links) —
  now defaults alias to the name (the phone's rule) + case-insensitive de-dupe; (3) the alias demo
  line bolded different things (Mac: full canonical, phone: short display) — unified on short
  display, which now agrees with the [[Full|Short]] help line under it (Mac fixture vision-checked).
- ⬜ **NoteBodyView ↔ BodyTextView** (14) — the body renderers' shared logic; = the i10 premise,
  fold into i10 rather than a separate job.
- ✅ **SpeakerVoiceStore ↔ DiarizationService** — RESOLVED 2026-07-16 by DELETION: SpeakerVoiceStore
  (per-person PCM samples for Sortformer enrollment) had ZERO callers — dead since the identity pivot
  to embedding-cosine (`Person.voiceEmbeddings` + VoiceMatcher). Removed; git history keeps it. Any
  old `recordings/voices/` dirs on devices are orphaned bytes, harmless. The clip-math overlap it was
  flagged for is now the one shared `SpeakerAudio.clip`.
- ⬜ **MemoSaver ↔ IngestService** (10) — the two ingest paths share adapted logic.
- (Scores ≤9 vs SidebarView etc. = generic SwiftUI patterns — noise, no action.)

**MOCK ROUND 2 history (Tuur's round-1 feedback folded in):**
- **A/B variants are DEAD → ONE panel + a Date ⇄ Closest sort pill** (Tuur's call: single click, exactly
  two orders, no click-then-select; same pill idiom as Queue|Review so it self-teaches). #m1 = Date mode
  (the arc: rail + line, first-mention sub-line); #m2 = Closest mode (flat best-first rows; hover swaps a
  row's date for **✕ "not related"** = per-note hide — the weird-embedder-match remedy, v1 hide-only,
  on top of the 0.45 floor).
- **⚠️ ROUND-3 CORRECTION — the O1 "3-circle" pick is VOID.** The mock had drawn importance as 3 circles
  (fiction cribbed from an old journal mock); Tuur flagged the mismatch repeatedly and finally
  screenshotted the app. REAL control = shared `SignificanceScale` (10 steps, 0–1 on a 0.1 grid, tiers
  Passing/Useful/Important, **0.8 refine wall** + flame tag, nil = Not rated; gates phone→Mac sync).
  Mock v3: reading column redrawn FROM SOURCE (NoteProperties + SignificanceCircles); row echo options
  rebuilt honestly — **P1 PICKED (Tuur, same session)**: the control's own decimal readout, warm past the
  0.8 wall; unrated rows show nothing (no fake 0.0). Lesson memorized: `feedback_mock_as_is_from_source`.
  SEMANTICS: rows echo USER-set importance; embedder closeness = Closest-mode ordering + CLOSEST MATCH
  flag + **hover tooltip "58% match · shares: …" (Tuur-approved: tooltip only, never ambient; % format
  vs importance's 0.x so the two numbers can't be confused).**
- **#m4** consent gate in-panel (phone Journal-gate copy, 295 MB EmbeddingGemma, same consent unlocks Mac
  Journal search) + downloading/indexing/no-connections; **#m5** collapsed w/ count badge (⌥⌘C) — both
  states Tuur-liked in round 1.
- Panel REPLACES the bottom LINKED FROM strip; local per-device index; sidebar label Journal→"Review"
  (phone-tab parity — memory `feedback_shared_code_first`).
AFTER sign-off → build phases below (embedder binding → shared index port → panel UI).

**Main-column polish proposal (2026-07-16 — NOT this feature's scope; now an explicit boxed proposal =
mock #m6, no longer drawn as if real):** ⬜ ① tags move UP under the context chips (today: bottom of the
properties card) — Tuur liked; ⬜ ② importance control one size down (10px circles, drop the tier caption
row; today's full-size row IS the signed-off significance-circles spec — this is a feel question, "might
be a little too big", not a bug); ⬜ ③ icons on the context chips (code already passes a symbol per chip —
`MacContextChip(systemImage:)` — but Tuur's chips render without; check why + turn on) — Tuur liked.

Tuur picked the direction (AskUserQuestion, this session): **connections side-panel + thread-as-timeline +
why-related chips** — unlinked mentions = later idea. MOCK-FIRST (locked process): no code until an HTML
mock in `Skrift_Native/SkriftDesktop/mocks/` is signed off; the approved mock IS the spec. Vision-check
mocks via the WKWebView snapshot script (no Chrome on this Mac — memory `reference_mock_vision_check`).

**Investigation facts (verified this session — reuse, don't re-derive):**
- Phone P8 (shipped): `JournalIndexService` sweeps memos → `EmbeddingIndex` (vectors from `GemmaEmbedder`,
  gated on Journal-index consent + model download). Related card = top-K neighbours over
  `RetrievalTuning.relatedFloor`/`relatedK`; thread = `threadOrder` (same scores, OLDEST-first, "the arc
  of this idea") + first-mention date. UI in `MemoDetailView.relatedSection` (~L917) + thread sheet.
- ALREADY SHARED: `Shared/Retrieval/` — `EmbeddingEngine` protocol, `RetrievalMath` (cosine), `MemoGist`
  (gist compose/chunk/textHash). NOT shared: the embedder binding + the index store (phone-local).
- Mac: NO embedder/index/UI today — but the Mac already runs MLX natively (Gemma enhancement), so the same
  embedding model runs there. Each device builds its OWN LOCAL index (embeddings never sync — private by
  construction, zero CloudKit contract change).

**Design brief for the mock (the three locked powers):**
1. **Connections side-panel** — persistent right-hand pane on the review surface: Related + backlinks
   (LINKED FROM) + thread entry in ONE place (Obsidian panel idiom; the phone stacks them under the body).
2. **Thread as a real timeline** — the arc rendered as a dated rail (importance dots, current note
   highlighted, click to hop) — not a sheet list.
3. **Why-related chips** — each related row shows WHAT connects it (shared people / tags / gist terms).
   Needs a cheap explanation heuristic (overlap of MemoGist terms + people + tags) — design the UI first,
   the heuristic can be dumb v1.
Design questions the mock must answer: does the panel collapse? does it replace the bottom LINKED FROM
strip (yes, presumably)? what does an EMPTY state look like (index not built / model not downloaded — the
Mac needs its own consent/download flow mirroring the phone's Journal gate)?

**Build phases AFTER sign-off:** (1) Mac embedder binding (mlx-swift, same model, download+consent) +
`EmbeddingIndex` port over `PipelineFile`s (much of the phone index should move to `Shared/Retrieval` —
same anti-drift move as BodyMarkdown); (2) panel UI + timeline + chips; (3) device/hostPNG verify rounds.
Rules: suites green per chunk, commit explicit paths, ledgers same commit, hostPNG any NSTextView surface.

## ⭐ Desktop parity A-list — the Mac catches up to the phone waves (2026-07-07, roadmap `DParityA`)

**2026-07-16 parity batch (from a phone/Mac screenshot compare — built + verified, device round owed):**
- ✅ **Context chips on the Mac**: place · weather · daypart chips now render under the title
  (`NoteProperties.contextChipRow` + `MacContextChip`; `PipelineFile.contextChips` decodes the synced TYPED
  metadata via `PhoneMetadata`). ROOT CAUSE fixed: the old properties row read demo-only `phone_location`
  keys, so REAL synced memos showed no location/weather and never showed daypart at all. `DayPeriod.symbol`/
  `.label` moved to the SHARED model. hostPNG-verified (Amsterdam · 14° · Morning).
- ✅ **Mac tag-adding — redesigned to a TYPEAHEAD (design #1, user-picked)**: first cut showed the library
  as a chip WALL (Tuur: doesn't scale past a handful; "tag, tag" placeholder weird) → now "+ add tag" opens
  an AUTO-FOCUSED field (device finding: it needed a 2nd click; Esc closes) and typing shows a dropdown of
  prefix-matching tags (most-used first, capped) + a "Create #x" row. Deterministic `tagSuggestions` rank
  first + show as ≤4 quick chips only while the field is open + empty. Return commits, comma-splits via the
  shared `Memo.parseTagInput`. hostPNG'd (`-snapshot-tags`).
- ✅ **Editing-next-to-a-snapped-photo re-render bug (device-found)**: typing after a photo re-rendered the
  whole body EVERY keystroke (photo flashed, typed text jumped before the image) — the reflow's snapped-only
  no-op check misfired because a mid-edit reconstruct isn't snap-stable. `BodyTextView.updateNSView` now
  re-renders only when `modelString` differs from BOTH the raw binding AND its snapped form. Device-confirmed
  fixed (flashing gone).
- ✅ **Inline `#tags` in the Mac body (Obsidian idiom — user-picked after the typeahead), ROUND 2**:
  typing `#word` opens a caret-anchored menu of matching tags. **Round 1 was buggy on device (Tuur: slow,
  typed text vanished, backspace dead, popup churn)** — root cause: it drove NSTextView's BUILT-IN
  completion session with its preview-inserts suppressed; the session's internal bookkeeping desynced and
  consumed keystrokes, plus a full-library fetch ran per keystroke. **Rebuilt the way Obsidian/Xcode do
  it**: a PASSIVE non-activating child panel (`TagSuggestPanel`) that never takes key and never touches the
  text path — typing/backspace/clicks stay fully native; only ↑ ↓ Return Esc are intercepted (`doCommandBy`)
  while it's up; candidates cached once per `#`-run. Accepting inserts the tag inline AND files it → tags
  row → frontmatter ("inline tags copy to the YAML"). Inline `#tag` runs render accent. Pure core =
  `Pipeline/Tags/TagComplete.swift` (Obsidian rules; `TagCompleteTests`), one `TagLibrary` source with the
  field. Device re-eyeball owed.
  **ROUND 3 (Obsidian-parity, Tuur's screenshot ask "just the way Obsidian works"):** a BARE `#` now opens
  the FULL library list immediately (browse; scrolls past 11 rows; keyboard selection stays in view; cap 50
  most-used); typing narrows; the space of a `# ` heading breaks the run so the menu steps aside. PLUS
  **markdown headings render as titles** in the Mac body: `# ` H1 / `## ` H2 / `### +` H3 tier, marks dim
  (turn-header treatment), characters verbatim → the export stays plain markdown. Device re-eyeball owed.
  **Shared-core extraction done same day (Tuur: "make sure the last edit is shared")**: the RULES now live
  in `Shared/Pipeline/BodyMarkdown.swift` (headings + inline-tag detection, host-tested) and
  `Shared/Pipeline/TagComplete.swift` (moved from desktop Pipeline/Tags) — the Mac consumes them; the phone
  compiles them (renderer wiring = i10).
  ⬜ **PINNED (roadmap idea i10, Tuur 2026-07-16 — "not critical to our path")**: Obsidian-grade markdown
  body — bold/italic/==highlight==/strike on BOTH apps by extending `BodyMarkdown` (font-trait merge for
  nesting), dim-visible marks (NEVER Obsidian's vanish-off-caret-line — offset-math trap, phone-hostile),
  phone heading/#tag rendering + inline-# popup, ⌘B/⌘I Mac + accessory B/i/🖍 phone. ~2-3 sessions.
  ⬜ follow-up: move `TagMatcher` → `Shared/` and run the deterministic tag step on the PHONE against its
  synced tag list (Tuur 2026-07-16).
- ⬜ **NEXT — Mac Related notes + thread (DEFERRED to a design pass):** the phone shows a RELATED section
  (✨ embedding-suggested notes) + "View thread"; the Mac shows only LINKED FROM. Tuur wants this on the Mac
  but it "can be MORE POWERFUL on the Mac" → needs a features + UI thinking/mock session FIRST (mock-first),
  not a straight port. Check whether the P8 related-notes embedder data is already available Mac-side.
- Note: phone→Obsidian publish still doesn't embed inline photos (comment left in `ObsidianPublisher.swift`);
  by design we export to Obsidian from the MAC only for now — revisit under the standalone push.

The contract-level "musts" from the parity analysis (memory `project_desktop_parity_plan`), built same-day:
- ✅ **Locked notes**: `PipelineFile.locked` mirror (ingest + update sweep), `VaultExporter` REFUSES export
  (typed error surfaces in the toast; auto re-export sweep skips locked and re-exports on unlock), note
  body + sidebar Copy gated behind Touch ID/password per session (desktop `LockGate`, deactivate
  re-locks), 🔒 properties row. The plaintext-vault promise now holds with the Mac on.
- ✅ **Memo-link precise resolver**: `Compiler.compile(file:)` supplies the whole queue's stems
  (`MemoLinkStems` over `VaultExporter.noteStem` — ONE derivation with the exported filename);
  zero-cost for notes without links. Body chip rendering + backlinks UI = mock round.
- ✅ **Photo-OCR search**: `imageOCRText` flat mirror (kept fresh when the phone's indexer lands late —
  the update sweep now refreshes the metadata blob + recompiles on change, fixing stale book fields too);
  `matchesSearch` matches it.
- 🌓 **remindAt**: mirrors + shows in properties (🔔); Mac-side alarm reconciler still owed.
- Device round-trip owed for the batch (lock on phone → Mac gate; OCR search on Mac; link export).

## ⭐ Shared-code dedup — anti-drift consolidation (2026-07-07, roadmap `SharedKit`)

Every phone↔Mac parity algorithm + wire struct that existed as annotated copies now compiles from
ONE file in `Shared/` (commits `0192947`…`6e4ab09`; both suites green; full MLX desktop build green).
Moved: SignificanceScale (fixed the Mac's residual "Significant" value label — 5207ec3 had only
caught 1 of the Mac's 2 copies), MemoMetadata(+nested), WordTiming, DiarizedSegment, ISO8601, the
0.7 trust rule (`Memo.isTrustedTranscript`), VocabularyTermParsing+Trust+Tuning, VoiceMatcher,
SpeakerFusion, BPEMerge (phone's inline mergeBPETokens/phantom-guard/alignWords deleted), ImageMarkers.

**Follow-ups found in the research (not built — each needs its own care):**
- ⬜ **SpeakerTranscript twins** — the SHARED `Sanitiser` (line ~351) parses conversations through
  `SpeakerTranscript`, which exists per-app (desktop `Diarizing.swift` / mobile `SpeakerTurnsView.swift`,
  same anchored regex today, different helper sets + `Turn` types). A change to one app's parser silently
  forks the shared Sanitiser's behavior. Unify into Shared (reconcile Turn Identifiable-vs-Equatable,
  desktop flattened/isAttributed + mobile setText/reassign helpers).
- ⬜ **MemoCloudIngest de-multipart** — the Mac's ONLY ingest path still re-encodes the typed shared
  `Memo` into fake multipart parts for the retired Bonjour parser (`UploadService` then string-parses
  `[String: Any]`); its comments cite the DELETED phone `UploadPayload`. Map Memo+assets → PipelineFile
  directly/typed (decode `MemoMetadata` where UploadService reads dict keys). Golden parity test first
  (same memo through old + new path, byte-equal PipelineFile).
- ✅ **DONE (2026-07-07, `6f78ac1`) — Mac custom vocab is consume-only** — fixed: shared
  `VocabularySyncCore` (whole-list LWW) + Mac `customVocabularyModifiedAt` + push-on-edit + one-time
  union migration; both adapters are thin wrappers now. 8 new host-less core tests. Live phone↔Mac
  round-trip unverified — fold into the next device session.
- ✅ **DONE 2026-07-15 (Board C5) — NamesCloudSync reconcile core** — one shared
  `Shared/Naming/NamesSyncCore.reconcile` (fold-carriers → NamesMerge → sorted-keys byte-compare →
  collapse-duplicates, injected insert/delete); one encoder so the halves can't churn-loop; thin
  app adapters keep the store/gate/notify differences.
- ⬜ **VocabularyBooster.boost() cores** — same spot→rescore→trust→apply flow both sides but drifted
  (VocabLog vs DevLog, tuning knobs, store injection). Unify around a small store/log seam.
- ⚠️ **Desktop legacy readers — ANALYZED 2026-07-15, kept by design** (see Board C6 above): `PhoneMetadata`'s
  `Double?`/`String?` leniency vs the shared `MemoMetadata`'s `Int`/enum strictness is LOAD-BEARING for
  legacy RN/Python payloads — a collapse needs a lenient shared `init(from:)` (cross-app contract change) +
  golden tests FIRST, or old notes lose their export frontmatter. Not a mechanical dedup.
- ⬜ (nice-to-have) shared `DevLog` for the desktop (it has only VocabLog; the devlog.txt discipline is
  mobile-only today).

## ⭐ CloudKit-only sync epic — retiring Bonjour (2026-07-06, on `main`)

Building CloudKit as the sole phone↔Mac transport, then deleting Bonjour. Plan in
`~/.claude/plans/do-all-the-work-lively-sedgewick.md`. Phases 1–3 built + committed; verify-first.

**Device test session (2026-07-06, Dev, CloudKit-only both ends):**
- ✅ **B — memo round-trip**: phone → Mac (via CloudKit, Bonjour off) → enhance → `MemoEnhancement`
  write-back → phone shows "✦ Polished on your Mac". Title + polish confirmed. PASS.
- ✅ **C — Bonjour retired UX**: phone Settings has no Pair-a-Mac (just "iCloud sync"); no stale
  "Waiting" pill. PASS.
- 🔧 **A/D — names + vocab looked broken, were mostly UI/timing**: the name DID sync (landed in the
  Mac's `names.json`) but the **Mac Names settings list didn't live-refresh**, and edits only pushed
  the carrier on app foreground, not on edit. FIXED (`23a2eb1`/`79975a7`): phone pushes
  NamesCloudSync/VocabularyCloudSync on edit; Mac Names list reloads on `.namesDidChangeFromSync`.
  Re-test owed.

**Feature requests / parity gaps from the session:**
- ✅ **DONE — "significance" → "Importance" on the Mac**: the review label + a11y label + Settings help
  now read "importance" (internal `Significance*` symbols unchanged), matching the phone. (`SignificanceCircles`, `SettingsView`).
- ✅ **DONE — rename discoverability**: the phone person editor's Full-name help now says "Change it to
  rename this person" when editing an existing person (`PersonEditorView`).
- ⬜ **Mac Names screen should match the phone's** person UI (look + interaction parity) — BIG, mock-first.
- ⬜ **Mac in-place name-linking should match the phone**: on the phone a linkable word ("Will") shows
  dotted/tappable immediately on the raw transcript; on the Mac the dotted suggestions only appear
  **after enhance** (the sanitise pass), and aren't as interactive. Want parity (immediate, tappable). BIG.

**Still owed in the epic:** Phase 2a (off-main CloudKit reconciler I/O), Phase 4 (deploy prod CloudKit
schema + device round-trip), Phase 5 (delete the Bonjour code — held until CloudKit-only is signed off).

**Test session 2 (2026-07-06 later — after push-on-edit + Mac Names redesign):**
- ✅ **A/D re-verified**: a deleted person + custom words both synced phone→Mac (CloudKit LATENCY, not
  instant); ✅ B re-confirmed (memo round-trip + polish back). CloudKit-only sync is effectively verified.
- 🐛→✅ **FIXED — rename was genuinely blocked**: the phone Names list opens `PersonDetailView` (voice +
  delete ONLY, no name/alias editing; the full `PersonEditorView` was reachable only from the review flow).
  Added an **Edit** button on `PersonDetailView` → opens the editor (build 28).
- 🐛→✅ **FIXED — stray vertical line down the phone Names list**: `PersonRow` used `.overlay(Divider()…)`,
  which renders a full-height VERTICAL divider (iOS-26 SwiftUI quirk) → replaced with a 0.5pt `Rectangle` rule.
- ⬜ **NEW — live bidirectional editing (Apple-Notes-style)**: a MANUAL edit on the Mac (note body / title)
  does NOT sync back to the phone — only the enhance-time `MemoEnhancement` write-back does. User wants
  "edit anywhere, syncs everywhere". Needs a debounced write-back on Mac-side edits. BIG-ish.
- ℹ️ **Latency expectation**: CloudKit is seconds (with silent push), not Apple-Notes-instant; push-on-edit
  helps but CloudKit propagation + the Mac's import-triggered reconcile add delay. Partly inherent.

## 🐛 Post-0.2.0 prod findings (2026-06-26, after promoting prod to build 22) — TRIAGE

User hit these on the freshly-promoted PROD apps. Diagnoses below; fixes owed (do on Dev, verify,
re-promote — don't hot-patch prod).

1. **Phone memo won't sync to Mac; phone stuck "syncing…".** Most likely root: the **prod CloudKit
   PRODUCTION schema was never deployed** (all on-device testing was on Dev, per the data-safety rule,
   so only the Development schema exists). The phone's `NSPersistentCloudKitContainer` can't push to a
   container whose Production schema lacks the record types → `isSyncing` hangs. **Action (no code):**
   CloudKit Dashboard → `iCloud.com.skrift.mobile` → compare Development vs **Production** record types
   → **Deploy Schema Changes** (now includes `MemoEnhancement`). THEN, for the Mac to *receive* phone
   memos, the prod Mac needs **Settings → cloudKitMacSync ON** (opt-in, OFF by default). I under-sold
   this as "polish-only" earlier — it's the whole prod CloudKit path. ⚠️ Confirm by dashboard check.
2. **"Waiting" sync pill is stale.** `Memo.statusKind` returns `.waiting` for `significance>0 &&
   syncStatus != .synced` — but `syncStatus` is the **Bonjour/HTTP upload** state, not CloudKit. With
   CloudKit the spine, the pill is misleading. **Fix:** drive the pill off CloudKit sync state (or drop
   Waiting/Synced for non-Bonjour users). `MemoDisplay.statusKind`.
3. **Name added on the phone isn't recognised in a note (e.g. "IJsbrand").** ROOT: `AddPersonView`
   (`NamesListView.swift`) saves `upsert(canonical:, aliases: [], short:)` — **empty aliases** — and the
   shared `Sanitiser` matches ONLY by `p.aliases` (no implicit canonical alias). So a phone-added person
   is unlinkable. NOT a capitalization issue (matching is `.caseInsensitive`). **Fix:** seed the alias
   from the name on add (the new `PersonEditorView` already does `if aliases.isEmpty { [name] }`; apply
   the same in `AddPersonView`), and/or make the `Sanitiser` treat the canonical's key as an implicit
   alias (broader; affects desktop). Existing IJsbrand needs an alias added after the fix.
4. **Can't select a word in the transcript and "add as name".** Task-1 added tap-a-RECOGNISED-name →
   resolve, but NOT select-arbitrary-text → add-person/alias (the desktop has it via `onAddName`/
   `onAddAlias`). **Fix:** a UITextView selection → "Add as new person / alias of…" action in
   `TranscriptEditor`. Compounds #3 (no way to fix IJsbrand inline today).
5. **Desktop shows EVERY note as a conversation; no re-transcribe button.** A note is a "conversation"
   when its transcript has **≥2 `**Name:**` headers** (`SpeakerTranscript.parse`), and the note-detail
   **Re-transcribe is hidden for conversations** (`NoteActions.canRetranscribe = … && !isConversation`)
   → can't undo it from the detail. **Workaround NOW:** right-click the note in the **sidebar** →
   **Re-transcribe** (that menu item is NOT conversation-gated, `SidebarView.swift:527`). **Investigate:**
   why do the notes carry turn markers — stale diarized output baked into the stored transcript? (cf.
   `project_conversation_namelinking` "brackets on every mention"). May need a bulk un-diarize/re-transcribe.

## ✅ Phone polished-text display — STANDALONE Phase 4 (2026-06-26, BUILT + sim-verified)

The Mac→CloudKit polish (`MemoEnhancement`) is now VISIBLE on the phone — the thing the user was
waiting on to "see results" of the round-trip. Built to `mocks/phone-polished-display.html`.

- **One editable body, starts from the polish — no toggle** (user decision, mirrors the Mac). When a
  `MemoEnhancement.hasContent` exists for an ordinary monologue memo, the detail body shows the Mac's
  copy-edit; name tiers + tap-resolve (task 1) apply to it. Edits write `MemoEnhancement.copyedit` +
  stamp provenance (this phone, now) → sync as the source of truth.
  - **No clobber** — verified in code: the Mac only processes `enhanceStatus != .done`
    (`ProcessingCoordinator.needsProcessing`); a done memo is never auto-re-polished. **No drift** —
    raw transcript = the contract input, polished(+edits) = the output; nothing re-derives polished
    from raw once it exists.
- **Title chooser** = a compact bottom sheet (Suggested / From-the-recording / your own) — solves the
  PARKED phone title-UI problem (the desktop's two-card chooser is cramped on a phone). The detail
  title defaults to the Mac's suggestion when no user title is set.
- **Summary card** + **"✦ Polished on your Mac" provenance caption**.
- **PROPORTIONAL karaoke** on the polished body (word timings pin to the RAW words; the polish rewrites
  them, so v1 tracks progress, like the Mac). **⭐ FAST-FOLLOW owed:** re-align polished words → raw
  timestamps (token diff: unchanged words inherit exact time, new ones interpolate; mostly-deletions →
  mostly-exact) for word-exact karaoke + "scrub to a word in the polished text and fix it by ear."
- Files: `MemoDetailView` (macPolish/polishedBinding/summaryCard/title chooser/provenance),
  `TranscriptBodyView`+`TranscriptEditor` (polished binding + proportional karaoke),
  `NotesRepository.enhancement(forMemo:)`. Verified on the iPhone 17 sim (`-seedPolished` +
  `PolishedDisplayUITests`). Mobile 498 unit tests green. **Owed:** device eyeball; the list row
  could also prefer the enhancement title (detail does); proportional-karaoke device eyeball.
- **Drive-by fix:** `MemoDate.label`/`group` used `Calendar.isDateInToday/isYesterday` (wall-clock,
  ignored the injected `now`) → the date tests were non-deterministic across midnight. Switched to a
  day-delta against `now` (identical in prod, deterministic in tests).

## ✅ Phone in-place name-linking (2026-06-25, BUILT + sim-verified)

Built the Mac review's name-linking as an iPhone touch surface, to the signed-off interactive
prototype `Skrift_Native/SkriftDesktop/mocks/phone-name-linking.html` (its "Build notes — locked
decisions" are the spec). The phone keeps the transcript **RAW** and re-derives tiers on demand —
the mobile↔Mac contract (phone sends RAW, Mac links names) is **untouched**.

- **Shared engine:** `Sanitiser.nameSpans(inRaw:)` (+ `NameSpan` in `Shared/Naming/NameMatch.swift`)
  — a sibling to `process()` that records linked/suggested/ambiguous/plain spans over the RAW text
  (no `[[brackets]]` written), reusing the SAME `Overrides`/first-mention/`suggestedOccurrences`
  machinery → tiers can't drift from what `process()`/the export links. 9 parity tests.
- **Persistence:** additive `Memo.nameResolutionsData` JSON blob (CloudKit-safe) →
  `NameResolutions{unlinkedNames, namePicks}`; `linkName`/`keepNamePlain`/`clearNameResolution`.
  Uniform model: link = `namePicks[alias]=canonical`, keep-plain/unlink = silence (`""`), undo = clear.
- **UI (always-editable transcript):** 4 tiers styled in place (linked solid #9d8ff7 / suggested tan
  dotted / ambiguous accent-wash+purple-dotted / plain-kept faint dotted); tap a name → native
  confirmationDialog (candidates / New person… / Keep as plain text; linked → Switch person when
  shared / Unlink+Undo-toast / Open card). "People in this note" chip bar. Editable `PersonEditorView`
  (Full name/Aliases+demo/Short/Voice). Tap detects the name (layoutManager rect) then resigns first
  responder so the keyboard yields — robust on UITextInteraction; editor stays always-editable.
- **Verified** on the iPhone 17 sim (`-seedNameLinking` route + `NameLinkingUITests`): detail tiers,
  resolve sheet, chip sheet, person editor all screenshot-checked. Mobile 498 unit tests green.
- **Owed:** device eyeball; conversation (`SpeakerTurnsView`) tap-to-resolve is monologue-only for now
  (conversations already render alias-display links via the conversation linker).

## 🐛 Audiobook import — MP3 rejected as "not a playable audiobook" (2026-06-24, FIXED)

User imported a valid MP3 audiobook part ("Made to Stick-Part02.mp3", 36.6 MB, 76:14 per
Files) via the normal in-app audiobook add → got **"That file doesn't look like a playable
audiobook."** Root cause: every `AVURLAsset(url:)` in the audiobook path was built **without**
`AVURLAssetPreferPreciseDurationAndTimingKey`. For MP3s (VBR rips, large ID3 tags) AVFoundation
estimates duration lazily and returns **0 / indefinite**, so `AudiobookImporter.importSingleFile`'s
`guard tags.duration > 0` threw `.unreadable`. m4b/m4a imported fine (the two existing library books),
which is why only the MP3 failed. **Fix:** `AudiobookImporter.makeAsset(url:)` helper sets the precise
key; used in `readTags`, the multi-file duration loop, and both `AudiobookSession` AVPlayerItem builds
(precise timing also tightens MP3 seek + read-along word alignment). **⚠️ Device verify owed** — fixed on
Linux, no sim gate here; build+install Skrift Dev and re-import the same MP3.

**Ultracode sweep (2026-06-24) — same anti-pattern, 3 more sites fixed, 1 refuted.** Fanned out
agents over every `AVURLAsset`/duration site repo-wide, classified each for MP3-reachability +
whether precise timing changes correctness, then adversarially verified. Confirmed + fixed:
- `QuoteCaptureProcessor.exportSpan:369` (**HIGH**) — quote-span export off an MP3 book drifts late
  (no duration guard → silent mis-alignment of the core audiobook-capture feature).
- `MemoSaver.appendAudio:486` (**MED**) — appending a recording to a memo imported from an MP3
  misplaces the splice offset + writes a wrong merged duration (the `base` asset).
- `RunFile.swift:58` (**MED, DEBUG `-chunksim`**) — bare sync `.duration` on an MP3 returns
  0/indefinite → chunk loop never runs; switched to precise async `load(.duration)`.
Refuted / left alone: `RunFile.swift:81` (the `-chunksim` A/B harness deliberately shows real
AVAssetExportSession behavior); all `IngestService` + `AudioMetadata` + video-import + test sites
(video/AAC-only or metadata-only — not MP3-reachable; not blanket-edited). **⚠️ Device verify owed.**

## 🐛 Audiobook import — recurrence, DIFFERENT root cause (2026-07-05, FIXED + device-verified)

Same "doesn't look like a playable audiobook" symptom on the Frankl multi-part rip — but NOT the
precise-timing bug above. Devlog diagnostics (`copiedBytes=10227234 duration=0.0`) + Mac forensics
proved parts 08+09 are **100% null bytes** (hollow files from a failed 2022 bulk copy — no audio
exists in them; unrecoverable, re-rip to fill). One bad part rejected the WHOLE book, while Bound
silently imported broken zero-length chapters. Fixes (`AudiobookImporter`, build 25, device-verified):
- **Resilient multi-part import** — skip unreadable parts, import the rest, alert "Imported with
  skipped parts" naming each file (never a silent gap, never a whole-book reject).
- **`robustDuration`** — AVAudioFile frame-count fallback when `load(.duration)` returns 0.
- **`materializingCopy`** — coordinated read + `startDownloadingUbiquitousItem` so an un-downloaded
  iCloud/File-Provider pick can't copy a placeholder (the other latent cause of this symptom).
Devlog lines `SKIPPED (unreadable)` + `copiedBytes=` now say WHICH failure it was, ending the
guess-loop. User owes: re-rip parts 08/09; optional hollow-file scan of the Books folder.

## Device-testing feedback — 2026-06-21 (6 live notes, pulled + verified)

Pulled from the dev phone via the **App Group container** (`group.com.skrift.mobile.dev` →
`Library/Application Support/default.store`, live, 83 MB, modified during the pull). ⚠️ **The
`pull-phone-feedback` skill's documented path (`com.skrift.mobile.dev` per-app container) is STILL the
06-12 stale orphan** — confirmed again this round; the live store is in the App Group container and is only
reachable with `devicectl --domain-type appGroupDataContainer` when the CoreDevice service tunnel is up
(it was, this time). 6 non-deleted notes (matched what the user saw in-app); 65 soft-deleted tombstones
ignored. Second-agent verify done. Raw dump at `.claude/memos_dump.txt`.

### P0 — 🐛 DATA-LOSS BUG: append after clearing a pasted note deletes the WHOLE note
**The bug the user "ran into."** Lost a ~3-minute note. **Exact repro (load-bearing details):** (1) start a
**new note**; (2) **paste** text into the body; (3) decide you don't want it and **delete/clear** that
pasted text; (4) **append** to the note with the **+ button**. → the append commits, and *then the whole
note gets deleted* ("your whole note gets deleted after it's added"). Destruction is in the **append-commit
path on a note whose body was paste-then-emptied**, not in the paste or delete step. User: "something we
couldn't have caught… this is strange behavior." → **P0, reproduce + fix first.** (memo 06-21 11:12)

**🔎 INVESTIGATION 2026-06-21 (static read + unit probe) — MemoSaver EXONERATED; suspect = CloudKit.**
Traced every delete path: all three (`softDelete`/`delete`/`permanentlyDelete`,
`NotesRepository.swift`) are DevLog-logged and fire ONLY from explicit user actions (detail ⋯ Delete,
list swipe) or the trash-retention purge — there is **no auto-delete-of-empty-notes** anywhere, and
`recoverStuckTranscriptions` only re-transcribes. The append path
(`MemoSaver.appendRecordingAsync`) re-fetches the memo, handles an empty existing transcript
(`existing.isEmpty ? newText : …`), and never deletes. New regression test
`testAppendAfterClearingBodyKeepsMemoAndLandsText` (clear body → append) **passes** (451/451 unit) →
the append path is safe. The store moved to a **CloudKit-backed** `NSPersistentCloudKitContainer`
(iPhone↔iPad private-DB sync) since this feature era — the prime suspect is a CloudKit remote-change
import deleting/merging the record, which a CloudKit-OFF unit store can't reproduce.
**Instrumentation added** (`5c…`): caller-frames breadcrumb on `softDelete` + a "editor cleared body
→ transcript=nil" timeline marker, so a device repro is conclusive — **if the note vanishes with NO
delete line in `devlog.txt`, it's CloudKit, not our code.** **OWED (needs user): device repro** of
new note → paste → clear → append → pull `devlog.txt`; also confirm whether the lost note is in
**Recently Deleted** (recoverable) and whether the iPad was syncing at the time.

### P1 — 🐛 Diarization / speaker-ID does not survive backgrounding (hypothesis) + ✨ wants a progress bar
Same session, "conversation" mode, 2 speakers. **(a) ✨ FEATURE (loved — "I love this"): a progress bar
while identifying speakers.** Diarization runs long enough that the user backgrounded the app waiting — the
duration itself is a data point. **(b) 🐛 BUG (unconfirmed — user *thinks*):** "it was identifying speakers
for a long time, then I switched out of the app and then I **think** it stopped. Just didn't anymore."
Hypothesis: the speaker-ID `Task` dies on app suspension — **same class as the 06-17 stuck-transcription
bug** (fire-and-forget `Task` can't survive suspend), but on the diarization path. Keep the "user thinks"
hedge — not a verified repro. The progress bar (a) would also surface whether (b) is a true stall vs. just
slow. (memo 06-17 20:20)

**✅ BUILT 2026-06-21 (awaiting device-eyeball).** (b) **Keep-alive + relaunch recovery** mirroring the
06-17 stuck-transcription fix: new additive `Memo.pendingDiarizationTarget: Int?` (0=Auto, N=forced) set
before `MemoSaver.diarizeExisting` and cleared on completion; a kill mid-identify leaves it set →
`recoverStuckDiarizations()` (new, scoped like `recoverStuckTranscriptions`: own-device, audio +
word-timings present) re-runs it once per launch from `SkriftApp`. "Split speakers" now also runs under a
`BackgroundTask.run` UIKit assertion so brief diarizations survive backgrounding without a relaunch.
(a) **Honest progress** (no fake % — FluidAudio's `processComplete` is opaque): the `.identifying` banner
now shows a ticking `· m:ss` elapsed (`DiarizationStatus.labelWithElapsed`, driven by a `TimelineView`) +
a "this can take a while — it keeps going if you leave" subtitle. **15/15 MemoSaverTests green** (2 new
recovery tests: re-runs a stuck memo + skips non-in-flight). OWED: device-eyeball the elapsed readout +
a real background-mid-diarize → return/relaunch cycle.

### P1 — 🔎 CONFIRM: transcription engine now "always warm", much faster, NOT eating battery — what changed?
User noticed (in **prod AND dev**) the engine is now always warm, "way faster," and "not really taking
batteries." Tone is pleased-but-suspicious — "something changed… what happened?" **Action: confirm what
changed (likely the pre-warm booster / always-warm path), confirm it's intentional, and verify it isn't
silently draining battery in some state.** File-and-document, not just log as praise. (memo 06-20 12:33)

### ✨ Auto-stop live captions on a timer — ✅ BUILT 2026-06-22 (build 19)
Feature idea (2026-06-22): for a long recording you don't need live captions the whole time — after N
seconds, auto-drop live captioning (record + waveform + `.m4a` keep going; transcript comes from the
one-shot pass at stop). Saves battery on long messages. **Decided:** a **Setting**, default **1 minute**
(user: "default one minute, that's great"). **Built:** Settings → "Stop live captions after: Never / 30s /
1 min / 2 min" (`@AppStorage("liveCaptionAutoOffSeconds")`, shown only when Live transcription is on);
`RecordView` watches `service.elapsed` and calls the existing `setLiveTranscription(false)` once past the
limit (`autoOffFired` guards re-fire if you tap captions back on). **Transient** — it never flips the sticky
`liveTranscription` preference; `LiveRecordingService.start()` re-seeds from the pref each recording so a
long recording's auto-off can't silence the next. The toggle button + caption now reflect the EFFECTIVE
state (`liveTranscription` made `@Published`; RT tap reads `tapLive`, so race-free). 455/455 unit green.
**Device-eyeball owed** (sim has no real recording). May drop the setting later if it doesn't earn its keep.

### P2 — ✨ Share a PDF into Skrift and have it persist as a source
User tried to share a PDF to Skrift via the share sheet and "have it live in there" — couldn't. Wants a PDF
to **persist as an imported source** (parallels the existing share-to-import audio/video path), not a
one-shot read. Extends the planned **"Unified source taxonomy"** (PDF is already a listed source type — see
below) → make PDF a first-class shareable/importable source. (memo 06-20 10:52)

**✅ BUILT 2026-06-21 — MVP (persist + open), awaiting device-eyeball.** Shares a PDF (or any document)
into Skrift via the share extension and persists it as a `.file` capture: the share-extension activation
rule gains `NSExtensionActivationSupportsFileWithMaxCount`; `SharePayloadLoader.loadFile` copies the doc
out of the provider (no in-memory load); `ShareViewController.completeFile` bypasses the annotation sheet
(mirrors the video path) → writes a `"file"` inbox entry (`CaptureInboxEntry.fileName`/`fileDisplayName`);
`CaptureInboxDrainer` copies the doc into the recordings dir (`file_<memoUUID>.<ext>`, reinstall-safe
relative path in `SharedContent.filePath`) → a `.file` capture memo; `Memo.sharedFileURL` resolves it; the
detail shows a doc card with **Open** → `quickLookPreview`. `permanentlyDelete` now also drops the doc
blob. 455/455 unit green (new drain test). **PINNED for later (user):** PDF as a full text-extracted /
readable source (PDFKit → transcript → name-link/enhance/Obsidian; read-along surface). **OWED:** device
test — share a PDF from Files/Books → confirm the capture + Open. (Share sheet can't be exercised on the sim.)

> **⚠️ P0 REFRAMED 2026-06-21 (user correction) — NOT a deletion, the APPENDED TEXT didn't land.**
> The note was **never deleted** (hence not in Recently Deleted): it stayed, but was **empty after the append
> recording stopped** — the appended text never landed. So this is the **append-transcription path**, the
> same family as the 2026-06-10 "append silently adds NO text" fix, NOT CloudKit/deletion. The
> `testAppendAfterClearingBodyKeepsMemoAndLandsText` test passes because its seeded transcriber returns text
> → the logic is correct **when transcription returns something**; on device the append clip is coming back
> **empty**. The note ends up blank only via: the `audioURL` guard bailing, the engine returning no text
> (silent-restore branch, no Error pill), or the landed text being clobbered by the editor's stale empty
> buffer. `appendRecordingAsync` now logs each branch (start/transcribe-outcome/no-text/failed/landed) +
> the existing "editor cleared body → nil" marker catches a post-append clobber. DEV build **(15)** pushed
> 2026-06-21. **OWED (user):** repro append → I pull `devlog.txt` to see which branch fires.

### P2 — 🎨 Audiobook reading-mode: bookmark icon placement follow-up (post build-14)
Refinement on the just-built reading-mode bookmark UX. Currently the bookmark icon "is still at the bottom"
with awkward negative-space margin. Want it **inline with the "selected text" button, far left** — bookmark
becomes part of the selected-text affordance: tap it to **visualize the bookmarked text and toggle it
on/off** (save/unsave per selection). i.e. bookmark state is per-selection + visualized, not a global bottom
button. (memo 06-19 21:38)

**✅ MOCK (`mocks/audiobook-bookmark-fold.html`) → BUILT 2026-06-21 (build 16).** Clarified on a device call:
the real pain was that the purple margin glyph **wasn't tappable to remove** (the bottom "Mark" button only
toggled at the playhead). Shipped the **page-corner-fold** model: in `ReadAlongView` each line now has a
full-height **tappable left gutter** — tap to fold (bookmark this sentence's global position), tap again to
unfold (remove); the liked `bookmark.fill` marker stays as the indicator + the faint line tint. The bottom
**Mark button is removed** from `AudiobookPlayerView.utilityRow` (`markButton`/`toggleMark`/`isCurrentSpotMarked`
deleted; new `toggleBookmark(atGlobal:)` wired via `onToggleBookmarkAt`). Tap the TEXT still seeks; the TOC
sheet's Chapters/Bookmarks tabs still jump (unchanged). 455/455 unit green. **Trade-off:** bookmarking an
**un-transcribed** (audio-only, no read-along text) book now has no affordance — flag if a fallback is wanted.

**🔧 build 17 fix (device feedback on 16):** tapping never REMOVED a bookmark — the remove matched within
±2 s of the sentence START, but a bookmark sitting elsewhere in a long passage (e.g. dropped at the
playhead) never matched. Fixed: the reader passes the tapped line's whole GLOBAL span and the parent lifts
any bookmark **inside that span** (`toggleBookmark(inSpan:)`), so it removes the exact one the line shows.
Also switched the gutter from a nested `Button` to a single **`SpatialTapGesture`** on the line (left of
text = fold/unfold, text = seek) so the tap is reliable in the scroll view. Mock
(`mocks/audiobook-bookmark-fold.html`) re-aligned to the app's marker and redeployed.

**🎨 build 18 (user: "i want the dog ear, it's a good idea"):** swapped the marker from the bookmark glyph
to an actual **folded page corner** — a `DogEar` Shape (right-angle at the line's top-leading, hypotenuse
TR→BL) filled accent with a soft shadow, scale-in transition on fold; the faint tint stays. Mock restored
to the matching dog-ear (clip-path triangle). Toggle logic unchanged (span-aware + spatial-tap). Build 18.
Device-eyeball owed.

**✅ BUILT 2026-06-22 (build 20) — active-line bookmark affordance.** Bookmark *creation* is now gated to the
**active (white, now-playing) line**, which shows a **hollow dog-ear OUTLINE** in its gutter as the affordance
("you can fold THIS spot" — fixes the invisible-gutter discoverability gap; matches "mark where you are as you
listen"). Tap the outline → fills. **Removal stays tap-the-filled-marker** (confirmed: "retapping it removes
it" — any filled dog-ear taps off). Non-active, unbookmarked lines have no gutter marker and a gutter tap
just seeks. Consequence (user-confirmed): you can only CREATE at the playback spot; to mark a line read ahead,
tap it to seek there first. `ReadAlongView.line` — `isCurrent` drives the outline (`DogEar().stroke`) + gates
the spatial tap to `marked || isCurrent`. 486/486 unit green. Device-eyeball owed.

### P2 — 🧱 EPIC: note-editing experience needs its own focused sprint
> 📌 **PINNED FOR A FRESH CHAT (2026-06-22).** The user wants to start this as its own session. Resume here:
> read the design thinking + the A/B/C fork + the B1-vs-B2 title question below, then go MOCK-FIRST.
> Recommendation on record: **option B** (re-found the body on a natively-scrolling text view), likely
> **B2** (pinned title only; tags/significance scroll with the body). First step in the fresh chat = mock
> **B1 (Notes-style, title scrolls away) vs B2 (pinned title)** side by side for the user to pick.

"The editing of the notes in the app is… not a very good experience." User wants a **focused, holistic
study of note-editing** (Apple Notes as the bar, maybe better apps too) as its **own separate sprint** —
not piecemeal. **Concrete first item — ⚠️ the 06-21 memo's "tags" was an ASR mishear of "TEXT"
(clarified 2026-06-22):** **text SELECTION doesn't auto-scroll.** Double-tap to select → drag the end
handle DOWN → the note doesn't scroll with the drag, so you can't extend the selection past what's on
screen. That's the real annoyance. Plus the wider pass: body editor, significance, photos, speaker turns.
(memo 06-21 11:22 + 06-22 clarification)

**↩︎ CORRECTION 2026-06-22.** The earlier "comma-separated tags" quick win was built off the MIS-HEARD word
("tags" should've been "text") — the user never asked for it. **KEPT anyway** (user: "the comma is actually
nice… we can keep that"); `Memo.parseTagInput` stays, easily reverted on request. The `FlowLayout` does NOT
have a scroll bug. The real text-selection-autoscroll issue above is the actual ask and belongs to THIS
sprint, not a one-off.

**🧠 DESIGN THINKING 2026-06-22 (pre-mock).** Framing: a Skrift note = a **transcript** (editable text +
inline `[[img]]` + speaker turns + title/tags/significance + capture quote), NOT a freeform doc → bar =
"native text-editing *mechanics* (Apple Notes) + keep the transcript richness." **Root-cause diagnosis:** the
editable body `TranscriptEditor` is a `NonScrollingTextView` (UITextView, scrolling OFF, offset pinned 0)
inside the page's one outer ScrollView — a deliberate unified-scroll trade (text + images + metadata in one
flow) that is ALSO why native editing breaks: a non-scrolling textview can't autoscroll a selection drag
(the reported bug), can't run the magnifier/edge handles, can't keep the caret in view while typing (the old
"paste jumps to top" hack = same wound). **Central fork:** A) bridge — manually drive the outer ScrollView
to follow selection/caret (cheap stopgap, hand-reimplements UIKit one behavior at a time); **B) re-found the
body on a natively-scrolling UITextView** with title/tags/significance as a scrolling header + TextKit image
attachments → selection/magnifier/edit-menu/undo/caret-follow all free (**recommended**); C) full TextKit 2
rich editor (overkill, transcripts don't need formatting). **Experience layer (fork-independent):** a
keyboard accessory toolbar (none today — biggest "native" jump), undo/redo, a real tag CHIP editor with
autocomplete from existing tags (the actual "select a lot" need = pick not retype), smart paste.
**Must-not-break:** inline images · edit/play/read mode swap (`TranscriptBodyView`) · karaoke · capture-quote
protection · speaker-turn editing · `transcriptUserEdited` trust flag · save-now. **Path:** (optional) ship
A as a stopgap; then the real sprint MOCK-FIRST on B + toolbar + tag editor. Awaiting user direction.

**🔬 STUDY 2026-07-06 (fresh-eyes code audit — sprint kicked off; roadmap node `NEdit`).** Confirms fork B
and adds the PERF story (code-derived; device magnitudes unprofiled):
1. **Per KEYSTROKE:** the page re-evals and runs the full `Sanitiser.nameSpans` regex scan 2–3×
   (`MemoDetailView.transcriptNameSpans` is an uncached computed property read in several places) +
   `context.save()` (disk + CloudKit churn) + a full-document TextKit relayout (self-sizing
   `sizeThatFits`) → typing cost O(note length × roster size), on-main.
2. **During PLAYBACK:** `AudioPlayerModel`'s 0.05 s timer republishes `currentTime` at 20 Hz through the
   whole page tree; tap-to-seek karaoke (default ON) is one SwiftUI `Text` PER WORD re-diffed per tick.
3. **Mode swaps** (edit↔karaoke) rebuild the body and even change inline image sizes (editor attachment
   cap 320 pt vs `ImageEmbed` fixed 160 pt — a visible jump when Play starts on a photo note).
Scar tissue of the non-scrolling choice: `NonScrollingTextView` offset pin, selection carry-over,
`sizeThatFits` clamps, THREE karaoke renderers (single-Text attr + FlowLayout word grid +
SpeakerTurns' own pair) + `KaraokeWordLayout`. Missing table stakes (grep-verified): keyboard accessory
bar, undo/redo UI, find-in-note, photo tap→viewer, Dynamic Type (all fonts fixed-size).
**KEY MOVE (sharpens B):** ONE scrolling UITextView renders edit AND karaoke — the highlight is
attribute painting on the same textStorage (changes at word rate, not 20 Hz), tap-to-seek = character
hit-test, find = `isFindInteractionEnabled`, undo = native; deletes the mode swap + both monologue
karaoke renderers. Metadata (tags/significance/summary/quote block) = header content inside the scroll
(B1: title in-flow too / B2: title pinned). Free wins during the rebuild: UITextView find, native undo
(+ accessory buttons), Writing Tools on AI-capable devices (NOT the iPhone 13), Dynamic Type, photo
tap→QuickLook (reuse the capture path), selection→"Save highlight" hook (feeds P6 quote cards). Also:
tapping a tag chip DELETES it silently (`removeTag`) — the chip editor must fix that. Perf hygiene
regardless of fork: debounce transcript saves (~1 s idle + end-edit + disappear), memoize nameSpans by
(text, people, resolutions), keep player ticks out of the page body. Conversations (`SpeakerTurnsView`)
keep their surface for now — phase 2.

**✅ REVIEW 1 DECIDED 2026-07-06 (mock v2 = the spec → `Skrift_Native/SkriftDesktop/mocks/note-editor-redesign.html`).**
LOCKED: **B2 — pinned title** (slim title row + ✦ chooser under the nav; rationale = swipe-between-memos context).
Accessory bar = **undo · redo · find · photo-at-caret · Done** (no play-from-caret, no append). **"Save highlight"
DROPPED** (user: never seen it, not necessary — plain system edit menu). Find-in-note: yes. **Summary card joins the
scrolling header** (chips → importance → summary → body) — the app already shows it for Mac-polished memos
(`MemoDetailView.summaryCard`); ⚠️ if a polished memo is NOT showing its summary on the phone today, that's a BUG —
check in the bugs chat. NEW asks from review: (1) **accessory bar restyled** to the app's language (floating glass
pill matching the player — user: system strip "doesn't fit the style, not as clean"); (2) **compact player pill** —
the old ~112 pt bar "takes up way too much space, blocks out the note" → one 44 pt row (play · ±10 s · scrubber+times
· rate), whole-pill scrub target, page dots → transient "3 / 7" while swiping. Mock fidelity note: chips/importance
render schematic — build matches the real app. ~~STILL TO SIGN OFF: the accessory restyle + the compact player direction~~
**✅ REVIEW 2 2026-07-06 — BOTH SIGNED OFF ("that's about it"); icon nit fixed (crisp SVG stand-ins in the mock,
SF Symbols on device: arrow.uturn.backward/.forward · magnifyingglass · camera). THE SPEC IS COMPLETE →
`mocks/note-editor-redesign.html`. Build green-lit as soon as the user's bug-fixing chat wraps.**

**🔍 FEATURE-GAP SURVEY 2026-07-06 (other note apps vs Skrift; knowledge-based).** Already have or already
planned: pins/folders/nested-tags/smart-folders (P5), highlights-feed/quote-cards/daily-review (P6), person
pages/backlinks (P7), journal/on-this-day/map/calendar/semantic-search (P8), ramble→to-do/bullets polish modes
(P4c), share-IN captures (C3), find-in-note + undo + photo-viewer + Dynamic Type (NEdit spec). **Real gaps
proposed (awaiting user pick):** (1) **share a note OUT** — md/text (+audio) share sheet; phone today only
copies the transcript — fold into the NEdit build (S); (2) **word count / duration stats** in ⋯ (S, fold in);
(3) **photo OCR** — on-device Vision text-in-photos → searchable + copyable (M, feeds P8d later);
(4) **note reminders** — "note to self" → local notification at a time (M); (5) **FaceID-locked notes** (M,
fits the privacy brand); (6) **live checklists** — render/toggle `- [ ]` lines, pairs with P4c + Obsidian tasks
(M); (7) **note↔note [[links]] + backlinks** — people-links exist; extend to memos, enriches the vault (M-L,
P7-adjacent); (8) **in-app document scan** — VisionKit → PDF capture (S-M); (9) **audio trim/delete-section
with transcript sync** — beyond Voice Memos; differentiator-grade (L, later). **Rejected as off-north:**
collaboration/shared notes, templates, publish-to-web, handwriting, note colors, typewriter modes.
Strategic note: iOS 18+ Apple Notes/Voice Memos transcribe natively now — don't chase generic parity; win on
context + names + audiobooks + karaoke + Obsidian + privacy. **USER 2026-07-06: their native transcription
quality is far below Parakeet's — transcription QUALITY is the moat; keep it front of positioning.**

**✅ SURVEY DECIDED 2026-07-06 — ALL shortlist items APPROVED** (share-out, word count, photo OCR, reminders,
FaceID lock, checklists, memo↔memo links, doc scan; audio-trim PARKED after explanation; rejected list confirmed
rejected). **HARD RULE (user): every feature ships on BOTH apps — model/logic in `Skrift_Native/Shared/`, thin
per-platform UI; phone and Mac run the same code wherever possible.**

**🏗 BUILD PLAN — frozen 2026-07-06; EXECUTION STARTED 2026-07-07 (bug chat wrapped, user green-lit).** Spec =
`mocks/note-editor-redesign.html`. Commit + verify per chunk (sim tests both apps; device eyeball for editor
feel); update FEATURES.md + roadmap in the same commits.
**Progress: chunk 1 ✅ 2026-07-07** — `NoteBodyView` re-foundation built (scrolling text view + hosted
header/footer, karaoke = attribute painting, `PlayerClock` split ends the 20 Hz whole-page re-render, debounced
saves, memoized name-scan; `NonScrollingTextView` + `TranscriptBodyView`/`TranscriptEditor` + `KaraokeWordLayout`
DELETED; marker write-back normalizes to the writer's `%03d` — the OLD editor drifted `[[img_001]]`→`[[img_1]]`
on every edit, a latent bug caught by the new round-trip test). Unit suite green (489).
**Chunk 2 ✅ 2026-07-07 (chrome):** floating Skrift accessory pill (`NoteAccessoryBar` — undo·redo·find·
photo-at-caret·Done, SF Symbols, live undo-stack state), system **find-in-note** (`isFindInteractionEnabled`),
**compact one-row player pill** (~40 pt: play·±10s·scrubber-with-times·speed; whole scrub zone draggable; page
dots → transient "n / total" flash on swipe), **photo tap → QuickLook viewer** (caret-adjacent attachment),
**photo-at-caret insert** (PhotosPicker → manifest `photo_<id>_NNN.jpg` convention + `AssetMaterializer.capture`
for CloudKit), **share note OUT** (⋯ → markdown + audio file via share sheet; `MemoShare` unit-tested),
**word count · duration** as the ⋯ sheet title, **Dynamic Type** (editor body + attributed text scale via
UIFontMetrics). Unit 493 green; editor-cluster UI tests green.
**Chunk 3 ✅ 2026-07-07 (tags):** `TagEditorSheet` — chips with explicit ✕ (tap-a-chip no longer silently
deletes), comma input KEPT, autocomplete chips from every library tag (`NotesRepository.allTags`, most-used
first, prefix-filtered) — "pick, not retype".
**Chunk 4 ✅ 2026-07-07 (live checklists):** `BodyTransform` = the ONE raw⇄display transform (img markers +
`- [ ]`/`- [x]` line-start task prefixes → single attachment glyphs; indent stays text; byte-exact round-trip)
consumed by BOTH the attributed builder and the name-span offset mapper (they were drifting duplicates);
tap a checkbox → toggles in place (no keyboard) + commits immediately; typed task syntax materializes into
live checkboxes on end-editing; exports verbatim as Obsidian tasks. ⚠️ Desktop parity owed (hard rule) —
`BodyTextView` doesn't render tasks yet; tracked on NFeat.
**Chunk 5 ✅ 2026-07-07 (memo↔memo links):** raw syntax `[[memo:UUID|Title]]` (SHARED `MemoLinkSyntax` in
Shared/Model — both apps compile it); typing `[[` in the editor → searchable note picker → atomic link CHIP
(one attachment glyph — typing can't extend it); tap chip → pager jumps to that memo; **"LINKED FROM"
backlinks** section under the body (off-main scan, capped 6). EXPORT: the shared `Compiler` now rewrites the
syntax at its body choke point — phone publish resolves PRECISE stems (`[[<frozen-or-derived stem>|Title]]`
via ExportStateStore, rename-safe) so vault links actually land; any unresolved path falls back to readable
`[[Title]]` (Mac compiles get the fallback until its resolver is wired — owed). Mobile 505 + desktop 325
unit green.
**Chunk 5b ✅ 2026-07-07 (enhancement-safety — user question caught it):** two seams could corrupt memo-links:
(1) the Mac's Gemma copy-edit ran RAW over the syntax → now `MemoLinkSyntax.escrowForEditing` strips links to
plain titles before the LLM (the img-marker escrow's sibling) and `reattach` re-wraps them after (case-
tolerant); a title edited away ⇒ WHOLE body falls back to unedited (QuoteProtection pattern) — wired in
`EnhancementService.editProse` (+ title/summary prompts read escrowed text); (2) the SHARED Sanitiser could
name-link an alias INSIDE a link title (nested brackets) → memo-link ranges are now `nonProseRanges` — fixes
the Mac sanitise step AND the phone's export relink in one shared change. Mobile 508 + desktop 325 unit green
+ full desktop app builds.
**Chunk 6 ✅ 2026-07-07 (photo OCR):** `PhotoTextIndexer` — on-device Vision over every memo photo; text lands
on `ImageManifestEntry.text` INSIDE the synced metadata blob (additive → every device carries it, zero new sync
machinery). Idempotent sweep (nil = pending, "" = no text) on launch/foreground/sync-settle/photo-insert.
Search extracted to `Memo.matches(query:)` + now matches photo text AND the memo TITLE (pre-existing gap).
Verified with a REAL Vision pass over a rendered fixture (512 unit); Mac search-UI wiring owed. [1d4da6e]
**Chunk 7 ✅ 2026-07-07 (reminders — signed-off design):** `Memo.remindAt: Date?` on the SHARED model (additive
→ lightweight migration; ⚠️ prod CloudKit schema deploy needed at promotion). Reminder = DATA (syncs); alarm =
per-device — `ReminderScheduler` reconciles `UNUserNotificationCenter` from the field (pure `ReminderPlan`:
future+live only → past dates inert; moved dates re-add; unrelated notifications untouched) on
launch/foreground/sync-settle/set/clear. Notification tap → `MemoOpenBridge` opens the memo; foreground
banners. UI: bell CHIP in the header when set (tap = change/remove), ⋯ → "Remind me…", list long-press →
"Remind me…"; presets (This evening/Tomorrow/Next week) + graphical picker; auth on FIRST set, denial explained.
Mac reconciler owed (same UserNotifications API; data lands already). 516 unit + desktop 325 + desktop app
build green.
**Chunk 8 ✅ 2026-07-07 (locked notes — semantics as pinned):** `Memo.locked: Bool` on the SHARED model
(additive; syncs — lock once, locked everywhere; prod schema deploy needed). `LockGate` = per-device SESSION
unlock (device-owner auth: FaceID/TouchID/passcode; injectable for tests); backgrounding re-locks all (Apple
Notes behaviour). UI: list rows show title + 🔒 only (no preview/thumb); the DETAIL PAGE renders a locked
placeholder (title + 🔒 + Unlock) — the pager can't swipe past it, MemoOpenBridge lands on it, and the player
NEVER loads a locked memo's audio (gate-aware load + re-derive on unlock/relock). Lock = instant (needs a
passcode-capable device); REMOVING the lock needs auth. **Publish: locked ⇒ excluded** (`shouldPublish` guard,
tested); locking an already-published memo → honest "already in your vault" notice (Skrift never deletes vault
files). Honesty copy on the placeholder: "hidden, not encrypted". Mac gate owed (LocalAuthentication is the
same API). 520 unit + desktop 325 + desktop app build + UI cluster green.
**📱 DEVICE TEST ROUNDS 1–5 — builds 31→39, all 2026-07-07. ⭐ CONTINUE HERE next chat.**
**ROUND-5 VERDICTS (build 39, session close):** long-press list menu ✓ works · search-hit flash ✓
works · viewer zoom ✓ works · PDF inline ✓ "very nice" — BUT the capture PAGE still reads as a
special layout (pinned block + boxed "Add a note about this capture…"), not a note. NEW DESIGN
CHUNK (next session, MOCK-FIRST): **capture reads as a NOTE** — fold annotationText into the note
body, the file/PDF becomes a body BLOCK (the [[img]]-style machinery from today generalizes: marker
kind + attachment + rect hit + zoom viewer all exist). Touches the C3 contract + exporter + Mac —
design it, don't patch it. ⚠️ STILL OPEN: selection-handles repro NOT retested since build 35 —
build 39 carries the armed probes (`sel-during-scroll` FR-inclusive + frame-write guards); pull
devlog after the next repro. Also owed: Mac parity halves (below), prod CloudKit schema at
promotion, and the **merge decision — this branch is 41 commits ahead of main** (user's call).
**Session ledger 2026-07-07 (builds 31→39):** 6 P1 fixes · camera dialog · checklist
Return-continuation · markup save-back + erase-crash fix · bar v2→v2.1 · photo display-block ·
search-hit flash · viewer zoom · PDF inline · 2 signed-off mocks · 552/552 unit (was 523).
---
**Historical: rounds 1–3 detail below.**
**ROUND-3 VERDICTS (build 35) + same-day fixes (build 36):**
- ❌→🔁 **P1#1 selection handles STILL WEIRD** ("weirder than before": handle refuses to move at the
  screen bottom while dragging; selection follows the viewport after keyboard-dismiss scroll; then
  snaps back). Devlog: ZERO churn events during the repro → round-2's churn fix held; remaining
  suspect = our per-frame hosted-subview frame writes fighting iOS 26's selection overlay
  (_UICursorAccessoryHostView). Build 36: frames assigned ONLY on change + a NEW probe
  `sel-during-scroll` (FR-inclusive — the round-2 probe was FR-gated and his repro keeps FR). If
  round 4 still jumps WITHOUT probe lines → pure overlay artifact → next step is restructuring
  (host header/footer outside the text view).
- ❌→🔁 **P1#3 doc-scan invisible AGAIN** — devlog `isSupported=true` proves capability; iOS 26 eats a
  2nd trailing item in ANY shape (separate items AND one group). Build 36: RELOCATED to the LEADING
  side next to Select. Sort-filter stays lone trailing. (Both toolbar UI tests green.)
- ✅✅ **P1#4 photo search — SOLVED round 5: never broken.** User had been using the in-note 🔍
  (find-in-note) the whole time; photo text matches in the LIST "Search transcripts" bar. Sim e2e
  test stays as the permanent regression gate. SPAWNED the round-5 ask → search-hit flash (below).
- ✅ **NEW (round 5, BUILT build 37): search-hit flash** — tapping a search RESULT opens the note,
  scrolls to the first match and flashes it (~1.4 s): text hit = accent-tinted range; OCR hit = an
  accent ring over the photo (a background hides behind an image). One-shot SearchHitBridge; cleanup
  via the idempotent tier restyle so name-tier colors (incl. ambiguous backgrounds) repaint exactly.
  3 unit tests; device eyeball owed.
- 🔬 **(superseded) P1#4 round-4 evidence trail:** device devlog shows
  Vision READ his photo (`chars=21 head='TENHO…'` at 14:55) yet ZERO `search '…'` probe lines — the
  query never reached the memos-list search field. Sim end-to-end repro (user-directed) is GREEN:
  `-seedPhotoTextMemo` (real rendered-text JPEG, un-OCR'd) → launch sweep → REAL Vision → typed in
  the REAL search field → memo surfaces (`testPhotoTextSearchEndToEnd`, `ccb7ce4`). ROUND 5 = type
  **"tenho"** in the Memos-list "Search transcripts" bar (not the in-note 🔍); the probe logs the
  query either way → distinguishes typed-elsewhere vs a dead device binding.
- ✅✅ **markup ERASE crash — FIXED, device-confirmed round 4** ("works perfect").
- ✅✅ **doc-scan — FOUND + WORKS round 4** (leading slot; "super cool", adjust works). Two spawns:
  (a) NEW ASK: scanned PDF should render INLINE in the note ("text, PDF, text — like Apple Notes"),
  not behind an Open button → design/mock next session (capture-card PDF preview block);
  (b) minor: VisionKit's adjust handles sit under the finger — system UI, note only.
- ✅ **long-press misunderstanding resolved round 4** — he'd been pressing in the NOTE BODY all
  along; the menu lives on the LIST cards. Proper verdict owed but unblocked.
- 💥→✅ **markup ERASE crash (round-3 finding, fixed build 36)** (draw → close → reopen → erase → app dies; crash
  `SkriftMobile-2026-07-07-142621.ips`): CoreAutoLayout main-thread assert — a PencilKit worker
  thread's dying CATransaction committed keyboard/selection-host layout off-main; our
  didUpdateContents chain was rebuilding the editor UNDER the live markup session. Build 36: the
  whole edit chain (re-mirror + OCR reset + thumbnail rebuild) DEFERRED to cover dismissal.
- ✅ **P2#7 camera dialog works** ("Take photo or choose from library — very good"); ✅ markup
  save-back persists ("it stays, very good"); ✅ P1#2 photo-tap fix confirmed (round 2).
- ❓ **P1#5 long-press** — user didn't know what it meant; explain: press-and-HOLD a note card in
  the memos LIST ~1 s → context menu (Remind me / Lock / Copy / Delete). Verdict owed.
**Original round-1 triage (builds 31→33) below for the record:**
LIKED ✓: compact player ("looks good"), player auto-hides for no-audio notes, tag editor ("way better, good
job"), undo buttons, paste-no-teleport, caret-above-keyboard, name resolve sheet + edit-mode semantics
("very good"), lock ("works, very cool"), reminders ("quite cool"), pinned-title ellipsis.
**P1 BUGS (all FIXED 2026-07-07, device verify owed in round 2):**
1. ✅ **Selection handles misbehave on scroll** (`600d9ef`) — diagnosed as styling/selection CHURN: SwiftUI
   re-evals storm during interactive keyboard dismiss and every updateUIView re-ran the FULL name-tier
   rewrite (unchanged spans) + a redundant selectedRange write = whole-doc reflow + iOS-26 selection-UI
   rebuild under live handles. Fixed: updateSpans skips unchanged spans; selectedRange written only when
   different; never restyle over a live selection. DevLog probes left in (inset writes, tier-restore moves,
   load rebuilds, sel-noFR changes) — if round 2 still shows jumps, the devlog names the event.
2. ✅✅ **Tap right of a photo opened the viewer** (`da3cfee`) — touch-point vs drawn rect;
   **DEVICE-CONFIRMED round 2** ("clicking next to the picture doesn't open it anymore — really nice").
3. ✅ **Doc-scan button invisible** (`81a7208`) — the button was a ToolbarItem nested TWO conditionals deep
   in ToolbarContentBuilder (the shape iOS 26 drops); both trailing buttons now live in ONE ToolbarItemGroup.
   Devlog probe "docScan: isSupported=…" proves capability vs toolbar in round 2.
4. ✅ **Photo-OCR search dead** (`461c55d`) — confirmed the sweep WORKS on device (devlog: "photoText:
   indexed 7" at 12:19); the gap was no trigger after a save, so in-session searches found nothing. The
   save paths (recording / awaitable / video import) now run PhotoTextIndexer after the metadata merge;
   integration test = save with rendered-text photo → searchable, real Vision. Handwriting quality = Vision's
   call, still watch.
5. ✅ **List long-press scrolled instead of context menu** (`5376a2f`) — the row's .onTapGesture fought the
   lift; the row is a plain Button now. New UI test long-presses row 0 and asserts the menu (green).
6. ✅ **Checkbox tap sometimes entered editing** (`da3cfee`) — same rect-based fix as #2: task glyph hit by
   drawn rect ±12 pt slop, caret snap irrelevant; geometry test.
**P2 FEATURES/POLISH (user-requested this round; code items BUILT 2026-07-07, device verify owed):**
7. ✅ 📷 offers TAKE PHOTO + library (`f5a16a3`) — confirmation dialog → system camera; both funnel into
   one caret-insert + CloudKit mirror + OCR path; sim stays library-only.
8. ✅ Checklist Return-continuation (`54fe2d4`) — Return in a task line = fresh unchecked item (mid-line
   splits); Return on an EMPTY item dissolves the box (Notes flow). 4 delegate-driven tests.
9. ✅ **Accessory bar v2 — SIGNED OFF (variant B) + BUILT + round-2 AMENDED 2026-07-07:**
   undo · redo | ☑ checklist-toggle (lights in a task line; un-tasks it) · 📷 · → memo-link
   (same picker as typing "[[") · 🔍 · Done. Round-2 verdict: checklist "super cool", link
   found + understood (Obsidian-style [[ ]]). ⋯ overflow REMOVED same day (user: not needed
   while there's space — it held only Find); revisit overflow-vs-SCROLL (user leans scroll,
   à la Notes) when scan/markup verbs arrive. Open (deferred): scan-into-this-note verb.
10. ✅ Draw on photos in-app (`fb7f5f4`) — QuickLook `.updateContents` wrapper (MarkupPreviewView):
    markup saves INTO the photo file → AssetMaterializer size-change re-mirror + OCR reset→rescan +
    mtime-keyed thumbnail rebuild. Shared-file captures get markup too (PDFs).
11. ✅ **Photo display-block — SIGNED OFF + BUILT 2026-07-07:** mid-sentence photos render as their
    own paragraph via TAGGED display-only newlines; raw keeps `[[img]]` mid-sentence (sync/export/Mac
    unchanged). Rule lives in `BodyTransform.imageBreaks` (one source for builder + displayRange).
    Hardening: reconstruct emits syntax only for real U+FFFC runs + typingAttributes scrubbed —
    inherited keys can't duplicate markers or eat a Return.
12. ✅ **Photo-viewer ZOOM — BUILT 2026-07-07 (build 38):** the viewer is UIKit-presented
    (`MarkupQuickLook`) so QuickLook's native zoom runs, anchored on the tapped photo's drawn rect
    (transient UIImageView over the attachment; file-card opens keep the standard animation). The
    markup + dismissal-deferred edit chain moved into the presenter unchanged (tested: edit reports
    on dismiss ONLY — the erase-crash contract). Old cover wrapper deleted. Device eyeball owed.
13. ✅ **PDF INLINE in the note — SIGNED OFF (A) + BUILT 2026-07-07 (build 39):** a readable PDF
    capture (doc scan / shared) renders its FIRST PAGE as a full-width block + "N pages" chip
    (CapturePDFInlineBlock + PDFThumbnailLoader, mtime-cached); tap → the viewer (all pages,
    markup). Non-PDF files + unreadable PDFs keep the card. Snapshot-checked against the mock;
    3 loader tests; device eyeball owed. Search unchanged (sharedContent.text).
**BY DESIGN (confirmed to user):** a SECOND typed mention of a linked name stays plain — one link per person,
first mention only (the locked naming model); re-scan happens on commit (~1 s) + restyles on end-editing.
**ANSWERED:** reminders are LOCAL notifications (not the Reminders app / EventKit), alarms fully offline;
only cross-device sync of the reminder needs iCloud.

**Chunk 9 ✅ 2026-07-07 (doc scan — THE WAVE IS BUILT):** `DocScanner` + `DocScanView` (VisionKit document
camera) — scan pages → ONE PDF via the existing C3 file-capture path (mirrors the share-drainer construction
byte-for-byte: `file_<uuid>.pdf`, SharedContent .file, empty audioFilename discriminator) → the scan is a
normal capture memo (file card + QuickLook + annotation) that syncs like any shared file; pages are OCR'd
on-device into `sharedContent.text` (capped 4 KB) so scans are FINDABLE from the memos search. Entry: a
`doc.viewfinder` toolbar button in the list — hidden on the simulator (the camera doesn't exist there; honest).
Scan → opens the new memo (MemoOpenBridge). 523 unit green (PDF page-count, real-Vision page read, capture
contract). Device eyeball owed
(selection drag / caret-follow / magnifier feel). **Name-tap mechanics changed (UI-test-driven find):** the
scrolling view's system text interactions swallow tap gestures (DevLog-proven), so names resolve via the
FOCUS-GAINING tap's caret (selection delegate, ±1 edge tolerance); while ALREADY editing, taps are plain caret
placement — resolve via the people row. Feels right in principle; confirm on device. Off-screen pager pages
can't a11y-hide hosted UIKit content on iOS 26 → they suffix identifiers ("-offscreen") instead. Chunks in order:
1. **Re-foundation (the editor):** scrolling UITextView page per spec (B2 pinned title; chips→importance→
   summary as in-scroll header), TextKit 2, `[[img]]` attachments, name-tier attributes, quote-protected
   captures. DELETE `NonScrollingTextView` + the 3-mode swap. **Karaoke = attribute painting** on the same
   textStorage (word-rate) + char-hit tap-to-seek. Perf: debounced saves (~1 s idle + Done/close), memoized
   nameSpans, player ticks out of the page body. Verify on a LONG memo: selection-drag autoscroll, caret-follow,
   paste, undo, magnifier.
2. **Chrome:** floating accessory pill (undo · redo · find · photo-at-caret · Done; SF Symbols),
   `isFindInteractionEnabled`, compact 44-pt player pill (whole-pill scrub; dots → transient "3/7"), photo
   tap→QuickLook (Live Text ⇒ copyable for free), Dynamic Type, **share note OUT** (md/text + audio),
   **word count/duration** in ⋯.
3. **Tag chip editor** + autocomplete from existing tags (fixes tap-a-chip-silently-deletes).
4. **Live checklists:** `- [ ]` / `- [x]` lines render as tappable checkboxes in the editor; toggle rewrites the
   line; round-trips verbatim to Obsidian tasks. (Pairs with P4c ramble→to-do later.)
5. **Memo↔memo links:** `[[` in the editor → memo-title autocomplete; store `[[memo:UUID|Title]]` in the raw
   text; exporter emits `[[Title]]` (resolving the CURRENT title) so it works in Obsidian; tap → open that memo;
   "Linked from…" backlinks section on detail. Shared linker in Shared/.
6. **Photo OCR:** Vision `VNRecognizeTextRequest` at photo save/import (background) → per-image text sidecar;
   folds into list search on phone AND Mac; copyable via the QuickLook viewer.
7. **Note reminders:** `Memo.remindAt: Date?` on the SHARED model (syncs via CloudKit like any field); the alarm
   is LOCAL per device — each device reconciles `UNUserNotificationCenter` pending requests from the synced field
   on sync-settle (CloudSyncMonitor hook); same framework on macOS. Set/clear from ⋯ + list long-press; tap the
   notification → open the memo.
8. **Locked notes:** synced `locked` flag; list long-press / detail ⋯ → Lock (Apple Notes idiom); open gated via
   `LocalAuthentication` (FaceID phone / TouchID-password Mac — shared gate); list shows title + 🔒, hides
   preview. **Semantics (user-clarified 2026-07-06): locked memos still SYNC via CloudKit** (appear on the Mac,
   locked there too) — **they're excluded from Obsidian PUBLISH only** (vault = plaintext .md on disk).
   Lock-after-export edge: Skrift never deletes vault files — it surfaces "already in your vault; remove it
   there if you want it gone." Unlock ⇒ publishes again next export. v1 = auth-gated UI, NOT per-note crypto
   (search + pipeline keep working) — stated honestly in Settings copy.
9. **Doc scan (phone):** VisionKit document camera → PDF → the existing C3 file-capture path (Mac views it like
   any shared file).
**DROPPED 2026-07-06:** audio trim / delete-a-section (was parked) — user: "the text is the main source; we
just edit the text. I don't think we need to edit the voice note itself." Off the plan entirely.

## ⭐ Standalone App Store push (2026-06-15) — see `STANDALONE_PLAN.md`

NEW DIRECTION: ship **SkriftMobile to the App Store as a standalone audiobook + notetaking app** that
works fully **without a Mac**. Full plan (phases 0–11, portability map, device/LLM matrix + Polish
spike, CloudKit/Obsidian sync architecture, competitor steal-list) lives in `STANDALONE_PLAN.md`.
Branch **`standalone`**. **Plan awaiting user sign-off before building.**

**LOCKED decisions:** $0.69 one-time, **NO IAP** (→ no cloud LLM cost, all on-device); **full-vision
v1**; internal sync = **CloudKit** (SwiftData CloudKit mode, NOT iCloud-Drive file sync → no
`filename 2.md` conflicts); Obsidian export = **one-way create-only publish** into a user-picked
vault folder (security-scoped bookmark, `Skrift/` subfolder, per-memo file ownership); on-device
**Polish = a gated spike** (lean Gemma, test on the real iPhone 13, ship only if it clears a hard
memory+quality bar, else no-polish); **three coexisting modes** (standalone / standalone+Obsidian /
paired-with-Mac) over one source of truth — Mac stays byte-compatible + opt-in.

**Build order:** Phase 0 `SkriftPipelineKit` (shared pure stages) → 1 CloudKit sync → 2 Export/Obsidian
publish → 3 de-Mac the UX  *(= standalone-capable core / earliest-shippable gate)*  → 4 Polish (spike
first) → 5 Organization (pins/folders/nested tags/smart folders) → 6 Commonplace Book + Daily Review
+ quote cards (the differentiator) → 7 People & backlinks → 8 Journal/map/On-This-Day + semantic
search → 9 audiobook player polish → 10 Apple Watch capture → 11 App Store readiness.

**⭐ PROGRESS (2026-06-18) — all on `main`, local/unpushed (branch `standalone` fast-forwarded in + removed):**
- ✅ **Phase 0** — shared naming engine in `Skrift_Native/Shared/Naming/` (shared SOURCE FOLDER, not SPM). Both apps green.
- ✅ **Phase 1a/1b** — Memo-row CloudKit sync; **device-verified** (iPhone→iPad, no Mac). iCloud capability + per-config container added in Xcode.
- ✅ **Phase 1c** — Memo audio/photos → CKAsset (`c5824eb`+`ec10bf5`). `MemoAsset` blob model (plain `Data`, no `.externalStorage` — CloudKit auto-CKAsset) + idempotent `AssetMaterializer`. **DEVICE-VERIFIED 2026-06-18** (image+audio iPhone→iPad).
- ✅ **Phase 1d** — word-timings + diarization sidecars sync (`026d4ca`) — new `MemoAsset` kinds → karaoke/speaker labels cross devices.
- ✅ **Phase 1e** — names + enrolled voices sync (`5ca7c1e`) — `NamesRecord` carrier + `NamesMerge` (LWW + voiceEmbedding union); `names.json`/Mac contract untouched.
- ✅ **Phase 1f** — custom vocabulary sync (`fddf690`) — `VocabularyRecord` carrier, LWW-by-modifiedAt (delete propagates).
- ✅ **Sync visibility** (`d49333b`) — `CloudSyncMonitor` → "Syncing with iCloud…" strip + "Downloading from iCloud…" image state; materialize-on-import (no foreground needed). ✅ **Vocab clobber fix** (`70a1058`) — fresh device won't wipe another's words.
- ✅ **Audiobook sync ENGINE** (`b0c7e41`, 1g/1h-i) — `AudiobookSyncRecord`/`AudiobookAsset` @Models + `AudiobookCloudSync` (enable/disable/reconcile; capture audio→CKAssets, materialize on receiver, position LWW, unshare keeps local audio). Reconciles against the untouched `library.json`. **Callable-only / NOT auto-wired** (inert until UI+policy). Mock **APPROVED + LOCKED**.
- **Test gate: 430/430 `SkriftMobileTests` green.** ⚠️ 1c–1f + sync-visibility device-verify rides along with any DEV reinstall. ⚠️ 10/40 UI tests pre-existing-broken on the iOS-26 sim — background task; **unit suite is the gate**.
- ✅ **CloudKit push + pull-to-refresh** (`63bf236`) — DEVICE-VERIFIED fast sync (seconds). Push capability added in Xcode; `aps-environment` committed to entitlements (`53451a6`, survives regen; prod=production). Pull-to-refresh on the Memos list runs the sweeps.
- ✅ **Version in About** (`c97a89d`) — reads real `CFBundleShortVersionString (CFBundleVersion)` (was hardcoded); bump per install to tell devices apart. Now build **(7)**.
- ✅ **Floating + debounced sync indicator** (`d1df31c`) — the "Syncing…" pill is an overlay (no layout shift) + debounced (no flicker during CloudKit bursts).
- ✅ **Sprint 2026-06-18:** double-transcription guard (`aab9e3f` — `Memo.recordingDeviceID`/`DeviceID`; receiver won't re-transcribe another device's `.transcribing` memo); Settings "iCloud sync — Up to date/Syncing…" line (`eb69fd3`); de-Mac toolbar gate (`b2460e2` — hide the ⟳ Mac sync button unless a Mac is paired); **audiobook sync toggle UI slice 1** (`e557de2` — library long-press "Sync this book" + `checkmark.icloud` glyph). **Test gate: 432/432.**
- ✅ **Per-book audiobook sync FUNCTIONALLY COMPLETE** (1g engine `b0c7e41` + 1h-ii UI slices `e557de2`/`33eefff`/`34a1fd6`/`19b8508`): toggle (library long-press + player ⋯), row states (synced ✓ / downloading spinner / download-available), "Syncing…" pill in the library, hands-off receive (reconcile on import-complete + pull-to-refresh), per-device **Remove download** (Apple Books model) + **Settings → Synced audiobooks** (size + Remove/Download/Stop-syncing), position LWW. **435/435 unit tests.** Build **(9)**.
- **Installable build (12)** on `main` (unpushed) — raw-CloudKit audiobook % + size sheet landed (build number now lives in `project.yml`, so `xcodegen generate` stops resetting it).
- 📌 **OPEN QUESTION (pinned 2026-06-18): offline conflict resolution.** Scenario: a week offline, notes taken + old notes edited on BOTH iPad + phone, then reconnect. Current behavior: **new notes = no conflict** (distinct per-device UUIDs, both kept — why we dropped `@Attribute(.unique)`). **Same note edited on both = last-writer-wins** per record (NSPersistentCloudKitContainer default; no crash, no "note 2" files, but one side's edit to that note can be silently lost). **Names/voices CONVERGE** (our `NamesMerge` re-merge: per-canonical LWW + voiceEmbedding union). Vocab = whole-list LWW; audiobook position = newest-play wins. **TO VERIFY:** exact NSPersistentCloudKitContainer merge granularity (per-record LWW vs per-property) — don't guess. **DECIDE later:** accept LWW (rare for a solo app) vs a "conflicted copy" safety net vs field-level merge w/ per-field timestamps.
- ✅ **DONE 2026-06-19 — raw-CloudKit audiobook AUDIO transfer (REAL %) + the "Turn it on" size sheet** (build **(12)**, 435/435 unit; commits `974abfd` transport · `08adbf5` rewire · `a353a49` determinate bar · `d012353` sheet · `e16531c` sweeps/build-12). Audio left the SwiftData `AudiobookAsset` blob (no % available) for a raw-CloudKit transfer: `AudiobookAudioTransport`/`CloudKitAudiobookTransport` write `AudiobookAudio` `CKRecord`+`CKAsset(fileURL:)` to the private-DB **default zone**; `CKModifyRecordsOperation`/`CKFetchRecordsOperation` `perRecordProgressBlock` → byte-weighted **DETERMINATE** per-book bar ("Uploading audio · 38%" / "Downloading · 61%"). Fetched by exact recordID (`ab_<bookID>_<index>`/`_cover`) → no queryable index. **No `CKQuerySubscription`** (the default zone wouldn't push one): the source stamps `audioUploadedAt` on the carrier → that @Model push (Core Data's zone) nudges the receiver's `reconcile` to fetch. **"Turn it on" sheet** `AudiobookSyncSheet` (mock screen 1, both menus): cover/title/**on-device size**/switch/live-% card/iCloud note. **BONUS done:** `CKAsset(fileURL:)` streams off-disk → no `Data(contentsOf:)` on main for large books (task #18). Wi-Fi default (`allowsCellularAccess=false`). `AudiobookAsset` @Model retained-but-dead (dropping a synced @Model risks a load fatalError; remove at prod promotion w/ a CloudKit dev-env reset). **Design verified vs current Apple docs** (coexistence-with-NSPersistentCloudKitContainer, fetch-by-id/no-index, perRecordProgressBlock, re-push trigger). **DEFERRED:** the cellular "Ready to sync · N MB" tap-to-pull affordance (`NWPathMonitor`). **⚠️ DEVICE-VERIFY OWED:** real iCloud — opt a book in on iPhone (watch the % climb), see it download on iPad with %; `AudiobookAudio` type auto-creates in DEV (no Dashboard step), needs a Deploy at prod promotion.
  - **Hardened after an adversarial code-review (9 confirmed → 5 fixed `b…`):** epoch-token guard so a late off-main progress callback can't leave a row stuck mid-bar; single-flight `reconcile` (re-run-coalesced) so overlapping triggers can't double-upload; re-fetch the live carrier after the upload `await` (don't write a `disableSync`-deleted @Model); atomic temp→rename asset copy (off-main copy vs main-actor folder ops); `unknownItem`-tolerant download (a missing part no longer discards the copies + retries forever).
  - **Known follow-ups (deferred, logged):** (#8) **playback-RATE-only changes don't sync** — LWW keys on `lastPlayedAt`, which `updateRate` doesn't bump; position (the headline) does sync. Fix later via a per-book `modifiedAt`-on-`Audiobook` (every mutator bumps it) rather than overloading `lastPlayedAt` (would reorder "recently played"). (#9) the Settings "Stop syncing"/"Download" rows wait on the CloudKit round-trip before updating — add an optimistic state/spinner. (#10) **unshare leaves a "phantom" entry on a device that received the entry but never downloaded the audio** — `disableSync` deletes the carrier + cloud audio but never removes a device's local `library.json` entry (correct for a device that HAS the audio → reverts to local-only; wrong for one that doesn't → empty unplayable book). Can't safely auto-GC in `reconcile` (can't tell a once-synced entry from a locally-imported one). Fix in sync-polish: track sync-provenance on the entry (or GC an entry with no carrier AND no local audio files). Narrow edge — both devices having the audio (the common case) is clean.
  - ✅ **"I want EVERYTHING to sync" (device-feedback 2026-06-19) — DONE, build (13):**
    (#11 ✅ `a6126e0`) cover refresh — `BookCoverCache.invalidate` after a download + `endBookTransfer`'s publish re-renders the row once `cover.jpg` lands; surfaced per-record upload/download failures so a dropped cover is visible.
    (#12 ✅ `b4b7214`) `BookTranscript` read-along text now syncs — `transcriptSignature` on the carrier (propagates even if transcribed AFTER syncing), sidecars ride the transport as `ab_<bookID>_t<i>`, receiver **re-stamps** the `signature` to its own audio so it's not stale; unshare deletes them, restore re-stamps. (+test)
    (#13/#8 ✅ `a6126e0`) position + rate — added `Audiobook.modifiedAt` (bumped by `updateProgress`+`updateRate`), reconcile LWW on `modifiedAt` not `lastPlayedAt`, so a **speed-only change syncs** without bumping the recents sort. (+test)
    **⚠️ DEVICE-VERIFY OWED (build 13):** opt a 2nd book in on the iPhone → cover, read-along transcript, position AND speed all appear on the iPad. Bookmarks-sync is still the next gap (separate from this batch).
- ⏳ **Then:** (a) rest of Phase 3 de-Mac — significance→**Importance** reframe (**needs a label nod**) + onboarding/Settings demote; (b) Phase 2 export/Obsidian + unify Compiler/TagMatcher/DTOs; (c) Mac→CloudKit (option A); (d) 10 pre-existing iOS-26 UI-test fixes (background chip). **Device-verify the audiobook sync** (real iCloud uploads, iPhone book → iPad).

**Decisions (resolved 2026-06-15):** (1) on-device name-linking = **YES** (phone still sends RAW; Mac
re-links identically via shared code → no double-link; alias-edit UI on phone mirrors Mac); (2) audio
sync = **CKAsset** (real audio on all devices); (3) Tier-C model = **opt-in** picker in Models tab,
default set by the spike; (4) min iOS = **26**; (6) Apple Watch = **deferred** (fast-follow). **STILL
OPEN: (5) folders model** — app-native vs Obsidian-subfolder — user thinking; don't build Phase 5 yet
(doesn't block 0–4). **Cross-app no-drift principle locked:** shared `SkriftPipelineKit` code + the
contract fixtures are the single source; deterministic re-derivation, never a one-sided "done" flag.
**Next after sign-off:** Phase 0 (`SkriftPipelineKit`) + schedule the Phase-4a model spike on the real
iPhone 13 (independent, longest-pole).

**Mock batch 1 (2026-06-15)** — 4 HTML mocks in `SkriftDesktop/mocks/standalone-*.html`. Status:
`models-polish` ⏸ **PARKED** (Polish behavior locked = title+summary+copy-edit mirroring Mac; held on
the mobile title-presentation UI — desktop's Suggested/From-recording chooser is wrong for a phone;
VERIFIED the Mac never syncs polished text back to the phone, so non-AI devices = raw). `export-obsidian`,
`onboarding`, `commonplace-book` await the user's reaction to their flagged design decisions.

## 🗺️ Roadmap history backfill (idea 2026-06-19; SEPARATE SESSION)

`roadmap/ROADMAP.html` is forward-looking (phases → ship). User wants to also fold in the **full past** —
"insane amounts" of history from the very start of Skrift — as a backward-looking timeline. Doable + its
own session. **Raw material (no vault — privacy):** `git log` back to the start (the spine), `archive/`
(old Electron/Python/RN apps preserved intact) + `archive/CLAUDE-electron-python.md` (pre-convergence
project doc), the memory files, the handoff docs (`*_HANDOFF.md`), `FEATURES.md`. **Shape:** mine into a
structured `HISTORY` array (date · era · what shipped · pointer to commit/doc) → render as a "past" view —
either a history lane flowing left into the future tree (one page) or a sibling timeline. Same data-driven
principle so it can't drift. **Usefulness for the agent:** additive — a curated structured index = fast
orientation ("why does X exist / what was tried before"); git + the ledgers stay the primary source. Leave
this breadcrumb so the dedicated session starts fast.

**UPDATE 2026-06-19:** the roadmap was rebuilt into an interactive metro-tree and now seeds this with a
**light history nod** — a `HISTORY` array (currently `mobile-native` + `desktop-native` converging into the
spine at P0) renders on the far left, flowing into the forward tree on one page. The full backfill = expand
that same `HISTORY` array (mine git/`archive/`/ledgers into dated eras) — the data-driven hook already exists,
so the dedicated session just fills it in. (User, when choosing the rebuild: "a dream, not structurally
directed yet" — so kept light for now, designed to grow.)

**UPDATE 2026-06-21 — staged material compiled:** read-only pass over the 3 external milestone snapshots
the user flagged (`~/Hackerman/archive/Skrift {…before frontend with hendri | …whisper AND parakeet | …before
starting the mobile app}`) → **`roadmap/HISTORY_BACKFILL.md`**. It has the sources, a verified
3-snapshot table, a draft 7-era timeline (Genesis→Whisper→v2-frontend-w/Hendri→Parakeet+significance→RN
mobile→native convergence→standalone), and how to extend the `HISTORY` array. **Not built** — user wants to
hold the backfill until the viz mechanics are locked (avoid rework). Key finding: the **live repo's own
779-commit `git log` (2025-10-18 → now) already holds the full narrative** — the snapshots just add human
milestone labels + the "Hendri" collaborator marker + preserved era artifacts. Start that session from the doc.

## 🎧 Audiobook player — reading-experience redesign (feedback 2026-06-18; ✅ MOCK SIGNED OFF + ✅ BUILT 2026-06-19)

### Device feedback — build 14 run (2026-06-19, triaged same session)
- ✅ **Play button "looked like a sphere"** → flat accent circle + soft glow (`2cc0412`).
- ✅ **Per-word karaoke underline disliked + made the now-line "jump over"** → dropped the per-word weight/underline;
  current sentence is just bright white (3-step ramp stays at the sentence level). Also kills the semibold reflow (`2cc0412`).
- ✅ **Transcription accuracy → SHIPPED `ASRConfig(melChunkContext: false)` (dual OFF)** after a two-language A/B sweep
  (desktop `-asrsweep`, pinned to the phone's FluidAudio commit `7f963cd` / v0.15.2 / parakeet-tdt-0.6b-v3):
  - **English-only clip** ("Do the Work" Intro): mel=off introduced one chunk-seam dup ("emotional emotional"); mel=on
    (default) cleaner. (First pass wrongly concluded "revert" from THIS clip alone.)
  - **Dutch clip** (3-min CC-BY-SA spoken-Wikipedia "Wijngaarden"): mel=on **drifts to its English prior** and garbles
    non-English — wrong years (1666/"twaalftig"/"veertien" vs correct 1986/1283/1451), mangled place-names ("Morenaars
    Graaf"/"Out-Alblas" → Molenaarsgraaf/Oud-Alblas), "Corneus Johan" → "Cornelius Johann". **mel=off fixes all of these.**
  - Verdict for NL/EN-mixed use: mel=off is the clear win on non-English (big accuracy gain, faster) but has a minor
    English seam cost — and the user is MOSTLY English. **Resolution: a Settings toggle** ("Language: English ↔
    Multilingual", `transcriptionMultilingual` @AppStorage, default **English** = mel-on = the v3 default).
    `TranscriptionService.ensureLoaded` reads it + REBUILDS the model when it flips. Multilingual = mel-off, which is
    **language-agnostic** — helps any non-English language v3 supports (German/French/Spanish/…), not just Dutch.
    **dualDecodeArbitration left OFF** — byte-identical to mel=off alone but ~2.7× slower in both tests.
  - Tooling kept: `-asrsweep <audio> [-truth]` (+ `-paragraph <audio>`). Both apps still pin FluidAudio to branch `main`
    → should pin a fixed version (drift risk). The garbled proper-nouns the v3 model just doesn't know (e.g. "Gods schok
    oem") are model limits, not config — out of scope.
- ✅ **iPad cold-launch didn't restore the phone's chapter-2 position** (live sync worked, fresh launch didn't) → real
  two-part race: `open()` read the local library.json position + raced the CloudKit import, and the iPad's first tick
  then LWW-poisoned the phone's update. Fixed: `open()` adopts a strictly-newer carrier position (writes it back), and
  `CloudSyncMonitor` re-seeks an open+paused session when a late import lands (`adoptSyncedPosition`). **DEVICE-VERIFY owed.**
- ✅ **Speed menu "froze first tap, fast second" — expected?** YES, benign: one-time process-wide cost of the FIRST
  SwiftUI `Menu` presentation (the `setRate` path is constant-cost). No fix. (Latent: `AudiobookLibraryStore.persist()`
  does a synchronous main-thread JSON write on every rate/progress change — move off-main someday; not the cause.)
- 👍 **Liked:** auto-recede chrome (read uninterrupted, pause appears when idle) · letter sizing.
- 🔧 **Paragraphing — BUILT + demoed (not yet wired into the UI).** `Models/Paragrapher.swift` (pure, 10 unit tests):
  hybrid — break a paragraph on a long pause AFTER a finished sentence, OR after `maxSentences` (default 4). Demoed on a
  real chapter via desktop `-paragraph`: **pause-only UNDER-segments steady audiobook narration** (the narrator barely
  pauses → one giant block at any 0.5–1.0s threshold); the **sentence cap is what gives audiobooks regular paragraphs**.
  So the hybrid is the right default (pauses catch real structure like bumper/credits; the cap handles dense narration).
  **DECISION OWED:** where to apply — read-along grouping / memo-detail display / stored+exported — and the
  threshold+cap. Not yet wired pending the user's pick. Unused FluidAudio `TextNormalizer`/ITN + `.dutch` hint still deferred.
- 🔧 **Chunk-seam robustness — BUILT (device-verify owed).** Root cause of `UndetectedED`/`WILLIM RAULF` garble: each 60s
  audiobook chunk transcribes from a COLD decoder with no preceding audio → its OPENING words mis-decode/mis-capitalise.
  Fix (`BookTranscriptionJob.transcribeChunk`): prepend ~2s of audio before each chunk as decode CONTEXT, then drop those
  lead-in words (word-time alignment preserved; chunkEnd behaviour unchanged so ChunkFusion's redo-tail still owns the
  trailing seam). First chunk has no lead. Verify on-device on the book where the garble appeared.
- 🔧 **Chunk-seam DROPPED-WORD / merged-sentence — FIXED (device-verify owed).** Device bug 2026-06-27
  ("Made to Stick", ch1 ~40:15): a long run-on sentence ("The creative genius… launch into a four-hour
  brainstorming **session.**") fills a 60s chunk, so `ChunkFusion`'s last sentence-start is > minProgress
  back → it took the **fallback** = keep ALL words + advance to the arbitrary `chunkEnd`. That cut lands
  MID-WORD: chunk A transcribes the boundary word from TRUNCATED audio (mis-decoded "session"→"summer",
  terminating period lost) yet KEEPS it, while chunk B drops it (starts before chunkEnd). The period-less
  word merges the two sentences → the giant un-split highlight block in the screenshot. **Fix:** the
  fallback now mirrors the sentence redo-tail at WORD granularity — drop the final word, rewind the
  frontier to its start so the next chunk re-transcribes it WHOLE (`ChunkFusion.fuse`); guard the tiny-step
  loop (accept the cut only when even the last-word rewind can't make minProgress). Also widened the
  lead-in drop tolerance 0.01→0.2s (`BookTranscriptionJob.transcribeChunk`) so the re-decoded frontier word
  survives cross-decode timing jitter instead of being dropped again. +2 regression tests in
  `ChunkFusionTests`. ⚠️ **xcodebuild test gate NOT run (fixed on Linux/web)** — run the SkriftMobile suite
  on the Mac, then device-verify on "Made to Stick".

✅ **BUILT 2026-06-19 (build 14, 439/439 SkriftMobileTests green; 8 commit-per-chunk steps `7d31b60`→`4bcca6e`).**
All 8 chunks landed to the mock: **(1)** tab-bar shell (`AppTabView`; Library/Settings out of the pull-to-refresh-eating
`.sheet`s) · **(2)** "significance"→**"Importance"** (control unchanged; internal symbols/`Memo.significance`/test-IDs/
contract key untouched) · **(3)** one-bar header + cover-tint ambiance + gradient play sphere + skip back-15/forward-30 ·
**(4)** reading mode (auto-recede never-while-paused, 3-step past/now/ahead ramp, current-WORD weight+underline, now-line
pinned upper-third, free-scroll + "Back to playing", column cap) · **(5)** "Aa" size+spacing persisted (themes dimmed,
fast-follow) · **(6)** bookmark "Mark" toggle + browse-only sheet + margin glyph · **(7)** "Add note" accent chip +
utility reflow (speed/sleep in) + read-along states (nudge / live transcribing-% / empty) · **(8)** sync-aware library
delete-confirm. **Tab bar verified on the iPhone 17 sim; player screens 3–7 owe a device eyeball (USER step — needs a
real book + transcript). Owed: light/sepia themes; ~~a global cross-tab mini-player~~ ✅ BUILT 2026-07-07 (see "🎧 Books tab + one-tap resume"). NEXT → Phase 2 Export.**

✅ **Mock SIGNED OFF 2026-06-19** = `mocks/audiobook-player-reading-mode.html` (v4 — mock-first, refined via two
design-critique workflows + a rendered-pixel agent review; commits `92aee15`→`1700d4e`). **It IS the spec — build to
it.** **LOCKED:** tab-bar IA (Notes·Library·Highlights(soon)·Settings) · "significance"→**"Importance"** (graded,
renamed) · **Add-note** = centered accent chip in the utility row · **reading mode** = auto-recede after ~3–4s idle +
on scroll, tap to show, never while paused, ~250ms crossfade · now-line pinned upper-third + margin **bookmark glyph**
(add = action, sheet = browse-only) · "Aa" text settings (size + spacing v1, themes fast-follow) · floating play ·
cover-tint ambiance + monogram cover fallback · device-frame kept (vs siblings' bezel-less cards — flagged, user OK).
**Defaults on the 2 leftovers:** (a) delete keeps BOTH "Remove from all devices" (=disableSync) + "Remove from this
iPhone only" (=removeDownload, neutral) for a synced book; local-only = plain "Remove". (b) reading column capped
~60–68ch (no full-bleed on iPad). **SCOPE:** the mock is the FULL Phase-9a redesign; the near-term *slice* = tab-bar IA
+ cheap wins (delete-confirm, header compress, Importance, font size) → then Phase 2 Export; deeper reading-mode /
bookmark-model = Phase 9a proper.

The player is becoming a **read-AND-listen** surface (e-reader-like), not just a capture tool, so it
needs a reading-experience pass. **Process: NO building yet — talk it through → render HTML mocks
(`mocks/audiobook-player-*.html`) → user points/critiques → then build.** Research how good e-readers /
audiobook apps do this (Mobbin: Kindle, Apple Books, Audible, Libby, Spotify audiobooks, Snipd/Airr,
Readwise Reader, Speechify/Voice Dream; our north star = Bound). Mock against the existing redesign
(`mocks/audiobook-player-redesign.html`) — keep what works, evolve it.

1. **Compress the header (Henry).** Kill the "NOW PLAYING" label — it's wasted space. Pull the cover +
   title + author + current-chapter UP into ONE compact top bar (where NOW PLAYING is now), keeping the
   collapse chevron + ⋯ menu. Frees vertical room for the text. *(Quick, high-value; probably the first
   mock.)*
2. **More real estate for the text + a readable "rest."** Today the read-along lights the current line
   ("rotating bit") and the rest is faint. Keep the current-line/word highlight, but make the
   surrounding text more legible + give the text region more of the screen so you can **read ahead/behind
   like a page** (not a teleprompter). Idea: gentler dimming/higher contrast on non-current text +
   free-scroll with a "snap back to the playing position" affordance + auto-scroll that keeps the current
   line in view. Pairs with #1 + #6 (both free up space).
3. **Font-size control.** A font button — big-A/small-A (Aa) toggle or a stepper/slider, in a small
   text-settings sheet (e-reader pattern: Aa → font size, later line-spacing + light/sepia/dark reading
   theme). Put the Aa in the utility row (by speed/sleep) or ⋯. Persist per-app (`@AppStorage`). Start
   minimal = font size only; line-spacing/theme are easy follow-ons.
4. **Bookmark UX — make it book-like + fix the model.** In a real book a bookmark sits ON a page. Plan:
   a bookmark icon adds a **margin marker to the LEFT of the text** that scrolls/moves WITH the text, so
   you can scroll and see "this bit is bookmarked"; the bookmark list jumps to it. **Fix the current
   confusion:** the TOC sheet has Chapters + Bookmarks tabs where the *Bookmarks* tab ADDS a bookmark but
   *Chapters* NAVIGATES — inconsistent. Decouple **add bookmark** (an action/toggle at the current
   position) from **browse** (the sheet = navigation only; tap a chapter OR a bookmark → jump). Verify
   our `Bookmark` store positions map cleanly to text lines/offsets for the margin marker.
5. **Floating play button (consistency).** The memo-detail screen has a floating play button; the
   audiobook player should match it instead of the current inline transport. Care needed: the player has
   more controls (scrubber/skip/speed) than a memo — decide what floats (play/pause) vs stays.
6. **"Capture this" → smaller "Add note."** It's a big prominent pill (made sense when capture was THE
   point); now that it's also reading, it eats real estate. Rename **"Capture this" → "Add note"** (or
   "Take note"), shrink it, maybe relocate (freedom — e.g. a compact icon+label in the utility row).
   Keep it reachable; just not dominant. Research how note/highlight-capture apps place this (Snipd/Airr
   highlight button, Readwise).

7. **Library is finnicky — presentation + access (device-tested 2026-06-19).** The library is a
   `.sheet` (`MemosListView:130`), so **pull-to-refresh inside it just dismisses the sheet** (the swipe-
   down-to-close gesture wins) — you can't resync the way you can in Notes. And "how to access it / what
   to do there" feels unclear. Rethink: present it as a full-screen cover or a nav push (so pull-to-
   refresh works), or give it an explicit refresh affordance; reconsider the entry point. Folds into the
   player/library redesign (mock-first).
8. **Too easy to delete a book (device-tested 2026-06-19).** One swipe = gone, no confirm. Add a
   confirmation (and make clear whether it deletes local-only vs also stops syncing). Especially risky
   now that a delete + kept-sync leaves you needing to re-trigger a download.

**e-reader "what makes it good" (to fold into the mocks):** generous margins + line spacing, adjustable
font/size/theme, chrome that fades while reading, tap-zones, clear progress + chapter context,
distraction-free; for read-along specifically: highlight that doesn't fight readability + auto-scroll
with manual override + an easy "back to playing position." Owner action tomorrow: pull specific Mobbin
refs while building the mocks.

## ✅ MOSTLY DONE — Video-from-Photos import bugs (reported 2026-06-15; fixed 2026-06-15)

All three symptoms addressed + sim-verified (394 unit tests green; `VideoMemoUITests` green; row + detail
screenshots in `/tmp/skrift-video-shots`). Commits `d98b6fe` (playback) + `e2108dd` (glyph + snippet).
**Owed:** DEVICE-EYEBALL — the Dev build ("Skrift Dev", `com.skrift.mobile.dev`) is installed on the iPhone 13;
share a real video from Photos → confirm it PLAYS, shows the video glyph, and the thumbnail looks right. After
testing, pull `Documents/devlog.txt` from `com.skrift.mobile.dev` (DEBUG → DevLog works there) for the
`importVideo`/`processVideo` trace. ALSO STILL OWED (separate): re-test capture/share-into-Skrift on the
Release/TestFlight build now that App Groups (Release) is registered — a Release-build/device step.

Sharing a video from Photos → Skrift creates a memo, but THREE issues (device-reported, screenshots in chat):
1. ✅ **No audio playback — FIXED 2026-06-15.** Root cause was load TIMING, not format: a shared-video import
   inserts the memo and OPENS Memo detail immediately (`MemoOpenBridge`) while `processVideo`/`extractAudio`
   still runs async, so the detail player's first `load()` hit a not-yet-existent `memo_<id>.m4a` (`hasAudio=false`)
   and never re-fired (a normal recording/audio-import writes its file synchronously before insert, so they were
   unaffected). Fix: `MemoDetailView` reloads the player on `currentMemo.duration` / `transcriptStatus` change,
   guarded `!hasAudio` so an append never interrupts active playback (`reloadIfAudioMissing`). Format ruled out by
   a test: the extracted m4a loads in `AVAudioPlayer` with a real duration. (NOTE: `DevLog` is `#if DEBUG`-only,
   so the TestFlight/Release container has no `devlog.txt` — the pull can't work; diagnosed from code + sim.)
2. ✅ **Thumbnail/inline-image aspect — FIXED 2026-06-15 (device-confirmed the real cause was PORTRAIT).**
   UPDATE after device-eyeball: the distortion IS real for **portrait** video frames (the user's clip was a
   1080×1920 portrait). Root cause: `TranscriptEditor.imageAttachment` set the inline image's `NSTextAttachment`
   bounds to FULL width × a height capped at 320 — and `NSTextAttachment` scales the image to FILL bounds
   (no aspect preservation), so a tall portrait frame (aspect-height 613 > 320 cap) got crammed into a
   full-width × 320 box → **stretched wide** ("wider than it needs to be"). Fixed: when the height cap engages,
   shrink the WIDTH to keep the image's aspect. Pulled the actual device JPEG (1080×1920, PAR 1:1, person
   correctly proportioned) → confirmed extraction is fine; it was purely the editor's display sizing. The
   `-seedVideoMemo` frame is now PORTRAIT (circle stays round with the fix; was a wide ellipse before).
   (Original landscape-only investigation below was incomplete — landscape frames never hit the 320 cap, so
   they never distorted; that's why the synthetic landscape seed looked fine.)
   The 48×48 row thumb (`scaledToFill`+clip) and playing-mode `ImageEmbed` were already aspect-correct.
   ORIGINAL (landscape) finding — the row thumbnail does NOT squish:
   every display path already aspect-fills + clips (`photoThumb` 48×48 + the detail `ImageEmbed`), and the
   saved frame preserves aspect. PROVEN with `-seedVideoMemo` (a landscape 16:9 frame with a centered CIRCLE —
   it stays a perfect circle, not an ellipse, in BOTH the row thumb and the detail embed; screenshots
   `/tmp/skrift-video-shots`). The square thumb is a conventional center-crop, not a distortion. **What WAS
   broken (and is the likely culprit of the "looks wrong" screenshot): the untitled-row SNIPPET leaked the raw
   `[[img_001]]` marker** — a video transcript always opens with the frame marker, so it filled the whole snippet
   line. Fixed `MemoCard.snippet` to strip `[[img_NNN]]` markers (titled rows already used the marker-stripped
   `firstTranscriptLine`). (If the user's device frame genuinely distorts, suspect an anamorphic/non-square-PAR
   source — `representativeFrame` doesn't PAR-correct; unconfirmed, no repro.)
3b. ✅ **Source glyph BRIDGED TO DESKTOP + date fix — 2026-06-15 (device-reported follow-up).** The Mac still
   showed a synced video as mic + "Voice memo" (the marker was mobile-only) AND showed today's date instead of the
   video's filming date. Fixes: (a) phone uploads `sourceType` (additive `UploadMetadata` field); the Mac reads it
   → `PipelineFile.mediaSource` → a **unified `sourceDescriptor`** in `QueueDerivations` that drives BOTH the
   sidebar glyph AND the detail "source" label (so glyph+label always correspond) across the whole taxonomy
   (Voice memo/Video/Audiobook quote/Link/Image/Text/File/Apple Note); `IngestService.ingestVideo` sets the same
   marker for Mac-side video imports; `NoteProperties`/`NoteDisplayView` source labels now use it. (b) `UploadService`
   uses the phone's `recordedAt` for `pf.uploadedAt` (was upload-time → a Photos video showed "today"). Unit-tested
   (`UploadServiceTests.testIngestVideoUsesRecordedDateAndMarksSource`); 265 desktop UnitTests + full build green.
   NOTE: an ALREADY-synced video won't retroactively fix (ingested pre-fix) — re-sync to see it; the sidebar glyph
   can't be `-snapshot`'d (ImageRenderer/drop-catcher) so eyeball on the Mac.
3. ✅ **Video/source glyph (mobile) — ADDED 2026-06-15.** A video import is neither a share-capture (it HAS audio) nor a
   book-capture, so it had no source marker. Added `MemoMetadata.sourceType` (free-form String, additive/optional,
   value `"video"` via `MemoMetadata.Source.video`; set in `MemoSaver.processVideo` incl. the no-audio-track
   path) → `Memo.isVideoImport` → a `video.fill` leading glyph + a "Video" chip in the list row AND the detail
   header chips. **Mobile-only: NOT added to `UploadMetadata`** (the Mac contract is unchanged — the glyph is a
   phone concern; the full taxonomy on the Mac is still the deferred cross-app item). First entry of the deferred
   "Unified source taxonomy" (voice memo / URL / PDF / video / audiobook quote / Apple Note).

Foundation: read `MemoSaver.swift` (importVideo/processVideo/extractAudio/representativeFrame), the Memos list
row, the Memo-detail player. Gate: iPhone 17 sim build + device-eyeball (it's a device/share-extension flow).
NOTE: also re-test capture/share-into-Skrift generally now that App Groups (Release) is registered (it was
likely broken in prod before — same fix that revived custom-words persistence).

## Device-testing feedback — 2026-06-17 (1 bug-report memo recovered + a data-integrity finding)

Pulled from the dev phone (`com.skrift.mobile.dev`). **Two USB caveats this round** (see "Data-integrity
finding" below): devicectl's CoreDevice **service tunnel was down** (error 1011 — only cached `info details`
worked; every file/app/group call failed), and the per-app store reachable over AFC house-arrest turned out
to be a **stale orphan** frozen at 06-12. The bug report was recovered NOT from the store but by reading the
`wt_<uuid>.json` word-timing sidecars in the private container's `Documents/recordings` (AFC-readable) and
reconstructing the transcript. Raw audio also pulled to `/tmp/skrift-pull/memo_FE3DD029*.m4a`.

### P0/P1 — 🐛 BUG: a recording can get STUCK and never transcribe (no retry) — ✅ FIXED 2026-06-17 (auto-recovery; awaiting device re-test)
**Root cause (confirmed from independent evidence):** `runTranscription` runs in a fire-and-forget `Task`
that can't survive app suspension. The **06-16 23:30 recording (13.48s)** was a **cold-launch auto-record**
(devlog: launch + `record start` at the same instant, 23:30:23 — widget/Siri/deep-link), so the ASR model
wasn't loaded; after `record stop — duration=13.48s` the transcribe `await`s the model load, the app was
backgrounded (late night), the `Task` died → memo stranded at `.transcribing` forever (perpetual spinner =
*"not transcribing at all"*). Proof it never completed: **no `vocab: words=…` line and no `wt_<uuid>.json`
sidecar** for it (every transcribed memo has both). The user asked for *"a reset button or automatic reset."*

**Fix (user chose auto-recovery only — no new UI):** `MemoSaver.recoverStuckTranscriptions()`, called once
per launch from `SkriftApp` (`.task`, skipped on the seeded sim path). No transcription `Task` survives a
relaunch, so any memo still `.transcribing` at launch is orphaned by definition → re-run `runTranscription`.
Scoped to plain recordings/imports: `transcriptStatus == .transcribing && !audioFilename.isEmpty &&
!isBookCapture && <audio file exists>` — capture dictations stay owned by `CaptureDictation.resumePending`,
audiobook captures by `BookTranscriptionJob`. 2 unit tests added; **12/12 MemoSaverTests green on the iPhone 17
sim.** **OWED:** promote to TestFlight → the existing stuck prod memo recovers on next launch (user will
confirm); device-eyeball a fresh cold-launch-auto-record → kill → relaunch cycle.

### Feature — ✨ toggle to disable live transcription for long / battery-saving recordings — ✅ BUILT 2026-06-17 (awaiting device-eyeball)
From the same 56s memo: *"it should be possible to have a button (maybe top-right) that **turns off live
transcription** in case you want to go for a **long recording that needs to use less battery** — where you
just record it once and transcribe it afterwards."* The engine already supported `liveTranscription`
(off = record + waveform only, one-shot transcribe after stop) but it was only a buried Settings toggle.
**Built:** a top-right `captions.bubble`/`.slash` toggle on the record screen (`RecordView.topBar`,
`live-transcription-toggle`), bound to the same persisted `@AppStorage("liveTranscription")` as Settings
(sticky), applying mid-recording via `LiveRecordingService.setLiveTranscription` (tears the live stream
down / brings it up; keeps recording + waveform + `.m4a` write). Off-state shows a "Live transcription off
— transcribed when you stop" placeholder. 2 service unit tests; full app compiles; **37/37 tests green on
the iPhone 17 sim.** OWED: device-eyeball the toggle + off-placeholder + a real long-recording battery run.

### ⚠️ Data-integrity finding — live SwiftData store is NOT in the per-app container anymore
The store AFC house-arrest reaches (`com.skrift.mobile.dev` → `Library/Application Support/default.store`) is
a **stale orphan**: frozen at 2026-06-12 (mtime + max `ZRECORDEDAT`), 16 memos still marked not-deleted even
though the devlog shows a bulk soft-delete of ~18 of them on **06-15** and recordings on 06-16/17 — none of
which are in that file. The **prod** per-app store has no `ZMEMO` table at all. **Strong hypothesis:** when
App Groups landed (~06-12, capture items/widgets) the live store moved into the **App Group container**
(`group.com.skrift.mobile.dev`), orphaning the per-app store. AFC house-arrest **cannot** read App Group
containers — only `devicectl --domain-type appGroupDataContainer` can (and that needs the service tunnel up).
**TODO:** (1) confirm the live store path once the devicectl tunnel is back; (2) if confirmed, **update the
`pull-phone-feedback` skill** — it currently points at the now-orphaned `Library/Application Support/default.store`;
(3) the word-timing sidecar recovery trick (`wt_<uuid>.json` → join `word`s) is a reliable AFC-only fallback
worth baking into the skill.
**✅ RESOLVED 2026-06-21:** all three done. Live store confirmed in the **app group** container
(`group.com.skrift.mobile.dev` → `Library/Application Support/default.store`; tunnel was up, mtime fresh, 6
non-deleted notes matched in-app). Skill updated — pulls from `appGroupDataContainer`, sanity-checks
mtime/`ZDELETEDAT IS NULL`, and bakes in the `wt_<uuid>.json` sidecar AFC-fallback. The per-app store
remains the orphan; don't triage from it.

## ⭐ CONTINUE HERE — Conversation pipeline bug-hunt (2026-06-14)

WILD trace of the whole conversation/diarization → name-linking → Obsidian-export pipeline
(prompt `CONVERSATION_BUGHUNT_PROMPT.md`). 11 bugs confirmed (adversarially verified). **User
decisions LOCKED** (don't re-ask):
1. **Inline name mentions → `[[Canonical|spoken]]`** alias-display, EVERY mention (spoken word preserved).
2. **Turn headers →** FIRST mention full `[[Canonical]]`, every later turn by that speaker plain short `**Tuur:**` (no link).
3. **Merge consecutive same-speaker turns** = YES.
4. **Re-transcribe a diarized memo** = DISABLE (hidden for attributed transcripts).

**DONE (desktop, gated: 255 UnitTests + full `-skipMacroValidation` build green):**
- `Sanitiser.processConversation` — turn-aware linker (merge → first-canonical/rest-short headers → inline alias-display). `process` (monologue) unchanged.
- Pipe-aware link identity everywhere: `Sanitiser.linkTarget`/`hasCanonicalLink`/`linkDisplay`; `BodyTextView.person(matchingCore:)`; resolver first-mention checks (`applyResolvedNames`/`applyResolvedOccurrences`/`applyPartialOccurrences`); unlink/relink restore the SPOKEN word. (The forward-looking "pipe breaks the resolver" trap is closed.)
- `SpeakerTranscript.parse`/`mergeAdjacentTurns` ported to desktop; `isAttributed` line-anchored + ≥2-distinct-speakers (kills the `**Pros:**`/`**Cons:**` false-positive that skipped copy-edit on plain notes).
- `BatchRunner`: conversations → `processConversation`; Mac-diarize path emits PLAIN headers (linking unified at sanitise).
- Re-transcribe + Redo-copy-edit hidden for diarized memos (`NoteActions`, `SidebarView`); `ProcessingCoordinator.redo(.copyEdit)` keeps conversations verbatim.

**DONE (mobile):** `MemoSaver.diarizeIntoTurns` marks `transcriptUserEdited = true` (a low-ASR-confidence
conversation is no longer silently re-ASR'd → turns destroyed at Mac ingest); SpeakerFusion hardened
(stronger smoothing, nearest-BOUNDARY gap metric, post-fusion same-speaker merge).

**Owed / watch:** #4 mid-sentence mis-attribution is *improved* (boundary metric + stronger smoothing +
merge) but bounded by Sortformer quality — manual reassign stays the backstop; device-eyeball a real
Tiuri+Roksana take.

**Follow-ups found by the adjacent-surface hunt (2026-06-14) + the 2026-06-15 batch:**
- ✅ HIGH — Apple Note with ≥2 line-start bold headings misclassified as a conversation → preamble DELETED
  on export. Gated conversation routing on `sourceType == .audio` + preamble preserved (`8c5d9b6`).
- ✅ **Phone same-named-speaker collapse + wrong-voice enroll** — slot-aware rename/enroll via a per-turn
  `turnSlots` map (read fresh from the sidecar at tap), name-based fallback (`580acdc`, `083f223`).
- ✅ **Desktop review bold turn headers** — `**Name:**` renders bold (name) + dimmed `**`, kept in the
  model for export (`cbdb893`). NOTE: still styles ANY line-start `**word:**` (incl. a plain note's
  `**Pros:**`) — defensible markdown-bold, left as-is. Fully HIDING the `**` (vs dimming) is owed
  (NSTextView can't be snapshot-verified → mock-first); the read-only `BodyText.styled` path is unstyled.
- ✅ **Upload phone diarization segments + word-timings** (additive optional `wordTimings`/`diar` parts) →
  Mac karaoke + voice-enroll-from-phone unlocked; byte-compatible (`50bce3a`).
- ✅ **Transcribe a book off-charger** (`3920214`); **audiobook read-along sentence split → NLTokenizer**
  (`0a80da0`).
- ✅ **Custom-vocab over-correction** (device garble "Tuur Skrift Tiuri Tuur…") — trust guard tightened from
  "keep if ANY replacement trusted" to "keep ONLY if EVERY applied replacement trusted" (both apps,
  `VocabularyBooster`; `1170369`). One distant spotter-rescue now drops the whole boost → clean unboosted.
  Precise minSim/cbw tuning still FluidAudio-internal + device-only (DevLog + env knobs to sweep).
- ✅ **Book transcribe in the background** (overnight/charging) — `BookBackgroundScheduler` BGProcessingTask
  (`ade5dde`); benign failure (resumes from saved chunk). **DEVICE-TEST OWED** (no overnight run on the sim).
- **[feature, owed — THE remaining build] Desktop "name a speaker" review affordance.** Mock SIGNED OFF
  (`mocks/name-a-speaker.html`, 3 states: diarized turn cards → click "Speaker 2" → people-picker popover →
  relinked `[[Roksana]]` + "voice learned"). Backend (`embedSpeaker`/`addVoiceEmbedding`) built + proven; the
  phone now uploads the `diar` segments the Mac needs. Scope = Phase-7-size: a SwiftUI speaker-turns card view
  for conversation memos in `NoteBody`/`NoteDisplayView` (today the body is the flat `BodyTextView` NSTextView),
  the picker popover, and tap→relabel-all-that-speaker's-turns + `embedSpeaker`→`addVoiceEmbedding` wiring;
  snapshot-verify via `-snapshot`. Best built ON a device-verified conversation pipeline (rebuild + test the Mac
  Dev build first). When wired, re-validate the uploaded `turnSlots.count` vs the transcript before trusting it.
- **[low/latent] Phone `SpeakerTranscript.parse` not pipe-aware** (a Mac `[[Canonical|spoken]]` header
  doesn't round-trip to the phone today); speaker name containing `*` breaks the Mac header regex (~never);
  monologue `process()` skips demotion when short is empty (whitespace canonical). Fix opportunistically.

## ✅ RESOLVED — Custom words didn't persist on TestFlight (App Groups (Release) not registered)

User reported (2026-06-15, TestFlight build 1): add words in Settings → Capture → Custom words, leave +
return → list empty. **Worked in Dev, failed in TestFlight, same Swift code** → a Release signing/entitlement
issue, NOT the store (`CustomVocabularyStore`, `Services/Transcription/VocabularyBooster.swift`, plain
`UserDefaults.standard`, correct). **ROOT CAUSE:** the Release entitlements (`App/SkriftMobile.entitlements`)
DECLARE `group.com.skrift.mobile`, but the App Groups capability was only registered on the `.dev` app ids
(2026-06-12) — the Release id never got it (the "App Groups at prod promotion" step CLAUDE.md anticipated).
A declared-but-unprovisioned app-group entitlement leaves the Release build in an invalid-entitlement state
that silently breaks `UserDefaults` persistence. **FIX (device-confirmed working):** user checked
`group.com.skrift.mobile` under **App Groups (Release)** in Xcode Signing & Capabilities for the SkriftMobile
(+ SkriftShare + SkriftWidget) targets, re-archived → TestFlight. Custom words now persist. → also unblocks
capture/share-into-Skrift in prod (same App Group). Kept the defensive `.onAppear` reload (`a8d8ab7`).
LESSON → [[project_testflight]]. **Do NOT** move the store to an app-group suite — fix the provisioning.

## Name-link display = SHORT name (revised 2026-06-15)
User clarified: misheard names ("tyr"/"cherry"/"thierry" for "Tuur") must be NORMALISED, not preserved
verbatim. Inline conversation links now render `[[Canonical|short]]` (the person's short, e.g. "Tuur") for
every matched alias (`7a7bf8c`). A mishear only normalises if it's a registered alias of the person — add
via the desktop right-click **"Add '<word>' as → an alias of <person>"** (`BodyTextView` context menu →
`NoteDisplayView.addAlias` → `NamesStore.writeWithSmartBumps`), or fix at the source with custom vocab.
Open question if the user wants it: preserve GENUINE alternate nicknames (vs normalise everything) — would
need marking which aliases are "display" vs "mishear".

## North star — "see how my thinking evolved over time"
The eventual reason the app exists. When I add a note about a realization, surface related notes from across the years and lay them on a timeline ("you had a similar thought in 2019, it shifted in 2021, here's where you are now").
- **Backbone (reachable now, offline):** semantic search across the whole vault using local embedding models; retrieve + rank related notes; timeline UI. Mostly engineering, not model-limited.
- **Harder part (deferred):** having a local LLM *narrate* the evolution well — same quality ceiling as the stale-summary problem. Defer until local models are good enough.

## ⭐ Brain-dump 2026-06-15 (naming model + desktop diarization + summary gate) — triaged, brainstorm pending

From a desktop review session (screenshots in chat). Mix of bugs, features, and 2 design topics:

**BUGS**
- ✅ **Desktop wrongly diarized MONOLOGUES — FIXED 2026-06-15 (off-by-default + Flatten).** Root cause: the
  GLOBAL `settings.conversationModeEnabled` defaulted ON, so EVERY Mac transcription was diarized + Sortformer
  over-split single-speaker notes. Fixes: (a) `conversationMode ?? false` (default OFF — no more auto-split);
  (b) **"Flatten to monologue"** review-menu action (`ProcessingCoordinator.flattenToMonologue` +
  `SpeakerTranscript.flattened`) — strips `**Speaker N:**` headers → prose, clears diarization, re-enhances as
  a monologue (no re-ASR). 268 UnitTests + build green. ⏳ REMAINING (fast-follow): **per-note "Split speakers"**
  (on-demand opt-in diarize on desktop) — needs the diarizer wired into a per-note `ProcessingCoordinator`
  action (mirror the BatchRunner diarize block); deferred to keep this change low-risk. Capability isn't lost
  (phone diarizes conversations; the global flag still works if turned on).
- **Adding a new person doesn't relink existing note text.** Added "Bruno Aragorn" (alias "Bruno") in Names;
  the note's "Bruno" stayed plain (not `[[Bruno Aragorn]]`). Name-linking (Sanitiser) ran before the person
  existed; nothing re-links on add. Fix is entangled with the naming-model decision below (#design).

**FEATURES**
- ✅ **Summary only when the body is long enough — DONE 2026-06-15.** `BatchRunner` skips the Gemma summary when
  the body has < `AppSettings.summaryMinWords` words (default 75; a real setting, tunable). A manual "Redo
  summary" still forces it. Unit-tested (`testShortNoteSkipsSummary`).
- **Right-click → "Add new person" should open the Names settings tab** so you can fill in the rest (aliases,
  short, voice) instead of creating a bare name. Ties into the Names-UX redesign + the relink question.

**DESIGN — LOCKED 2026-06-15 (mock `mocks/opt-in-naming.html`, awaiting final sign-off → then build)**
Opt-in naming model. Detected names render PLAIN; a "People in this note" chip bar lets you tap the people
the note is ABOUT → those link + go in a `people:` frontmatter list. LOCKED rules:
- **One note, one link** — FIRST mention → `[[Canonical|short]]`, every later mention stays PLAIN alias
  (no link littering). The `people:` list carries the graph. (Changes today's conversation linker, which links
  EVERY inline mention → first-only.)
- **No pre-linking** — always start unlinked; user taps the chip. No auto-suggest.
- **Conversations: auto-link the matched speaker** (clearly a subject) — SAME one-link rule (first
  turn-header/mention canonical, rest plain).
- **Mac-only picking for now** — phone "pick people" parked (user working that side separately). Fits the
  phone-sends-RAW / Mac-links contract.
- **Open note only** — adding a person re-scans the OPEN note so they appear as a chip; NO global re-scan.
  (This is how the "added Bruno, text didn't relink" #4 + right-click #3 get resolved — deliberate tap, not auto.)
- **Names settings redesign** — replace the 3 cramped inline columns with a clean LIST (avatar · full name ·
  "aka" alias summary · voice) → tap a row → a labeled detail editor (Full name / Aliases / Short / Voice);
  the SAME editor opens from right-click "Add as a person" in a note. One editor, two doors.

  **BUILD STEPS (mock SIGNED OFF 2026-06-15 — verified what's NEW vs EXISTING against the code):**
  EXISTING, do NOT touch: monologue `Sanitiser.process` is ALREADY first-only (first→`[[Canonical]]`, rest→plain
  short); conversation turn HEADERS already first-only. NEW work only:
  1. ✅ **Opt-in gating (the core) — DONE 2026-06-15 (chunk 1).** `PipelineFile.aboutPeople: [String]` (additive).
     `Sanitiser.process`/`processConversation` take `aboutPeople: Set<String>?` (`gated` helper) — link ONLY those
     people; everyone else plain. EMPTY → links nobody; `nil` = ungated (engine tests). `BatchRunner` (both audio +
     capture paths) + `ProcessingCoordinator` (redo copy-edit) pass `Set(pf.aboutPeople)`. `unlinkedNames` still works.
  2. ✅ **Conversation inline → first-only — DONE 2026-06-15 (chunk 1).** `linkInline` now first-only per person with a
     SHARED `seen` across headers + bodies (two-pass: headers claim speakers, then bodies in document order). A
     speaker's single link is their turn header; later inline mentions demote to the short. Matched speakers auto-link
     regardless of `aboutPeople`. Gate: UnitTests 277 green (9 new: opt-in monologue/conversation, first-only inline,
     two-Jacks tap-one/tap-both) + full `-skipMacroValidation` build green. Conversation tests rewritten to one-link rule.
  3. ✅ **Review "People in this note" chip bar — DONE 2026-06-15 (chunk 3).** `Features/Review/PeopleChipBar.swift`
     in `NoteDisplayView.column` after `NoteProperties`. `Sanitiser.detectedPeople` → chips (plain/OFF by default);
     tap → `ProcessingCoordinator.toggleAbout` flips `pf.aboutPeople` + `resanitiseForNames` (re-link the body LIVE,
     deterministic no-LLM, recompile, save). ON = full name + accent ✓; OFF = `＋ short`. Conversations: matched
     speakers (`Sanitiser.matchedSpeakers`) render LOCKED-ON (auto-linked in their header, can't toggle off) — that's
     how "auto-link matched speaker" + the `people:` list land without seeding `aboutPeople`. Snapshot-verified all
     3 states (`-snapshot-people` PNG, matches mock); 3 detection unit tests. ("Someone else…" add-chip → chunk 4.)
  4. ✅ **`people:` frontmatter — DONE 2026-06-15 (chunk 2).** `Compiler.peopleLinks(in: body)` emits
     `people: [[A]], [[B]]` from the body's DISTINCT linked canonicals (reading order; img markers excluded;
     alias-display resolved to canonical). Derived from the rendered body (not `aboutPeople`) so it can't drift
     and auto-includes conversation matched speakers. Empty `people:` when nobody linked. +2 CompilerTests; gates green.
  5. ✅ **Names settings redesign — DONE 2026-06-15 (chunk 4).** `Features/Settings/PersonEditor.swift` (shared,
     labeled detail editor: Full name / Aliases + recognition demo / Short + link-display hint / Voice). `SettingsView`
     Names section is now a clean LIST (`nameListRow`: avatar · full name · "aka" aliases · voice) → tap a row → the
     editor; "Add person…" row → new. The SAME editor opens from a note's right-click "A new person…" (`addName` →
     pre-filled) + the chip bar's "Someone else…"; on save → `NamesStore.upsert(replacing:)` (rename-safe, carries
     voiceprints) + `coordinator.resanitiseForNames(open note only)` so the new person shows as a chip — no global
     re-scan. `NamesStore.delete` tombstones. Snapshot-verified (`-snapshot-names` panel 4, `-snapshot-person-editor`
     panel 3) + 3 upsert/delete/rename unit tests.
  **ALL 5 BUILD STEPS DONE 2026-06-15.** Gates each chunk: UnitTests 288 green (+21 over baseline) + full
  `-skipMacroValidation` build green. Review UI eyeballed via dedicated PNG snapshots (chip bar 3 states, names list,
  person editor) — all match the mock. Deploy desktop per [[feedback_desktop_dev_deploy]] (owed, prod idle).
  **Adversarial review pass (4-dimension workflow + verify) → 4 real fixes:** (1) `processConversation` ambiguity was
  computed over the WHOLE names DB, not the in-play (about ∪ speakers) set → tapping one of two same-alias people now
  links inline (matches `process`); (2) `people:` now filters to KNOWN PERSONS + skips `![[embeds]]` (a place/embed in
  an Apple-Note/capture body no longer pollutes the people graph) — `Compiler.compile(knownPeople:)` threaded through
  all production call sites incl. export; (3) `NamesStore.upsert` MERGES on an add-name collision instead of clobbering
  an existing person's aliases/voice; (4) `linkInline` demotes to the canonical when a person has no short. +3 tests.

  ⭐ **CONTINUE HERE (2026-06-16) — naming/sanitising RE-DERIVED FROM FIRST PRINCIPLES → ✅ DESIGN LOCKED in `NAMING_MODEL.md`.**
  A deep `/grill-me` session resolved the WHOLE solution from the job-to-be-done. **Read `NAMING_MODEL.md`** — it's the
  authoritative spec (supersedes `mocks/opt-in-naming.html` + shipped chunks 1–5). Headline: flip opt-in → **OPT-OUT**
  (auto-link known people, prune side-characters); recognition = **known-roster-only seeded from the `People/` folder**,
  new people added manually (no NER/LLM — must stay phone-portable); keep ONE body link (first mention) for the backlink
  **snippet** + keep `people:` frontmatter; **KILL** the chip bar + the per-occurrence resolver; click-a-name-in-the-prose
  popover replaces the chip bar; mistranscribed known names normalise (dotted + revertible). It's mostly DELETION + a
  default-flip, not new building. **Status (2026-06-16): design LOCKED + research-validated** (prior-art pass verdict =
  "sound as-is, build it"). Refinements folded into `NAMING_MODEL.md`: risk-tiered opt-out (auto-commit
  full/distinctive names, dotted-suggest common-word/ambiguous ones via a stoplist), aliases live in the PORTABLE DB
  (not the Obsidian note — phone may not use Obsidian), one-keystroke fuzzy add-picker; REJECTED the new-person hint
  (even deterministic). Plus NON-NEGOTIABLE build-guards (FP guards, skip audiobook-quote spans, re-scan on roster
  collision, frontmatter-canonical lockstep, fuzzy-vs-strict golden-set, date-sorted person view).
  **BUILD (2026-06-16, on `main`):**
  - ✅ **Chunk 1 — Sanitiser → opt-out + risk-tiering.** `aboutPeople` include-gate + `gated` DROPPED;
    `Sanitiser.process`/`processConversation` now link ALL known people by default (first mention,
    `unlinkedNames`-pruned). Risk-tiered via new `NameStoplist.swift`: full/distinctive names auto-commit;
    common-word / ≤2-char / ambiguous names → dotted **suggestions** in `Result.ambiguous`
    (`candidates.count` 1 = common-word, ≥2 = ambiguous), capitalization-guarded. `nonProseRanges` skips
    leading YAML / fenced+inline code / audiobook-quote spans (build-guard). Callers updated; opt-in tests
    rewritten opt-out + risk-tier + quote-span. **Gate: 288 UnitTests green + full app build green.** The
    `pf.aboutPeople` field + chip-bar/resolver wiring are now INERT — deleted in chunk 3.
  - ✅ **Chunk 2 — Roster seeding from `People/` titles.** New `PeopleFolderScanner` lists
    `<vault>/People/*.md` filenames (privacy: titles only, no contents, no AI); `NamesStore.seedRoster`
    upserts each new title (canonical = title; aliases = full title + first-name token), idempotent +
    non-clobbering + synced. Seeded before each processing run. **Gate: 295 UnitTests green + full app
    build green.**
  - ✅ **Chunk 3 — Delete + data-model flip.** Deleted `PeopleChipBar.swift` + `InlineResolver.swift`
    (model/banner/`ResolverPopover`) + the per-occurrence Sanitiser engine (`applyResolved*` /
    `applyPartialOccurrences` / `PartialChoice`/`PartialApplyResult` / `plainSlotMap` / `detectedPeople`
    / `matchedSpeakers`; kept `plainOccurrences` for the unlink popover). Unwired from
    `NoteDisplayView` + `BodyTextView` (the click-a-linked-name **unlink/change popover stays**).
    Data-model: dropped `PipelineFile.aboutPeople`, added the `namePicks` ambiguity-pick record;
    removed `toggleAbout` + the `-snapshot-resolver`/`-snapshot-people` modes. **Gate: 273 UnitTests
    green + full app build green.**
  - ✅ **Chunk 4 (the heavy one) — in-prose 3-tier UX.** ENGINE: `namePicks` (force-link / `""`
    silence) + `neverLink` refined to PRUNE→SUGGEST (unlinked name stays dotted + re-promotable),
    via a shared `Overrides` struct. UI (`BodyTextView` NSTextView): linked #9d8ff7 / suggested tan
    dotted / plain, model→storage offset-mapped past image markers; `SuggestionPopover` (state 2) +
    `LinkedNamePopover` (state 3). `NoteDisplayView` wires each decision → set-mutation +
    `resanitiseForNames` + undo toast. **Gate: 278 UnitTests green + full app build green; visual
    verified vs the mock via `-snapshot-naming`.** OWED: live in-NSTextView body eyeball after deploy.
  - ✅ **Chunk 5 — Robustness.** `RosterAudit` (`newlyAmbiguous`/`affectedFiles`) +
    `ProcessingCoordinator.rescanRoster` wired into `savePerson`: a fresh same-name collision
    re-derives every memo that auto-linked that name (→ dotted suggestion) + flashes the count.
    Matcher kept STRICT (whole-word + capitalization, no edit-distance fuzz — boost + manual-add
    cover mangles); `NamingGoldenTests` pins the tiering + prune/pick round-trip. Build-guards
    finalized (FP guards / non-prose skip / re-scan / frontmatter-lockstep / own-the-files ✅;
    date-sorted person view = Obsidian-side, deferred). **Gate: 286 UnitTests green + full app build green.**
  ✅✅ **ALL 5 CHUNKS DONE (2026-06-16).** The opt-out naming model is built, gated, committed on
    `main` (chunks 1–5: `67de42f`, `6d458e8`, `8ae5f4f`+`d7852c3`, `19979f8`, + chunk 5; fixes `3fc55a1`
    change-person force-link + `ba1c779` change-person scoped to same-name). Deployed to
    `/Applications/Skrift Dev.app`; `-naming-demo` flag seeds a self-consistent live example.
    Device-eyeballed by the user (change-person bug found + fixed). NOTE: a parallel session committed
    mobile work onto `main` mid-build (see `feedback_parallel_orchestration`) — recovered cleanly.

  **Naming — open questions (post-build review, 2026-06-16; answers logged, none blocking):**
  - ✅ Q1 DONE (`commit below`): monologue `process` existing-link check is now PIPE-TOLERANT —
    swapped the literal `occurrences(of: "[[Name]]")` for `linkOccurrences(of: canonKey)` (matches bare
    AND `[[Name|short]]`), so a piped link can never slip past into a 2nd link; removed the now-dead
    literal `occurrences` helper. Regression test `testExistingPipedLinkSuppressesSecondLink`. (Was
    latent-not-live; folded in as cheap insurance per the user.)
  - Q2 (edge): `nonProseRanges` skips only a LEADING audiobook quote (contract C1 guarantees `> ` at
    offset 0). A mid-body `>` blockquote (only from a hand-authored Apple-Note import) isn't protected →
    names inside auto-link. Optional: skip ALL `>`-line runs, not just leading. ⏳ optional.
  - Q3/Q4 (real limitation): `rescanRoster` re-derives the IN-APP `f.sanitised`/`ambiguousNames` + flashes;
    it does NOT rewrite already-EXPORTED vault `.md` (the user re-Exports). `affectedFiles` scans body
    links (`people:` is derived from them in lockstep, so they match). Per-note `namePicks` ARE preserved
    through the re-derive. ⏳ FOLLOW-UP: auto-re-export affected exported notes + also scan `people:` as a
    belt-and-suspenders.
  - Q5 (intent): `minAutoCommitLength = 3` → ≤2-char names suggest, 3+ auto-commit. INTENTIONAL — 3-char
    given names (Sam/Tom/Ben/Kim/Jan) are distinctive under whole-word+capitalization; the vocab-booster's
    ≤3–4-char flag was about FUZZY transcription spotting, not exact naming. One-line bumpable if FPs show.
  - Q6 (intent): the capitalization guard fires a dotted suggestion on a sentence-initial stoplisted word
    that's also a roster name ("Will you…"). ACCEPTED noise — it's a dotted SUGGESTION (no link written,
    one-click dismiss). A following-token/POS check is possible but adds heuristic FP risk; hold unless annoying.
  - Q7 (real friction) — DECIDED 2026-06-16: NOT NOW (user). A FREQUENT person whose name is on the stoplist
    (Mark/Rose/Max…) is dotted-suggested every memo (click-to-confirm), never auto-linked. The fix if it ever
    bites: a per-Person "treat as distinctive" override (opt out of the stoplist guard). Parked, not built.
  - Q8 (scale): the auto-link pass is O(people × aliases) whole-word regex + recomputes `nonProseRanges`
    per person (link-find + demote). Fine at hundreds; at thousands (lifelong/phone roster) it adds up,
    worse in `rescanRoster` over many files. ⏳ FOLLOW-UP if it slows: one alternation-regex/Aho-Corasick
    candidate pass + compute `nonProseRanges` ONCE per `process` (edits are localized).
  The grill detail below is kept as the audit trail.
  --- (original re-open framing, now resolved by NAMING_MODEL.md) ---
  User's call (do NOT narrow this to a bug fix): the "two Jacks" friction is a SYMPTOM that made the user question
  whether the entire naming/sanitising approach is the right shape. Next session = re-derive it from the
  job-to-be-done, NOT patch the chip. We may delete/replace large parts of what we just built — that's on the table.
  - **The trigger (symptom, evidence — not the task):** a note about two friends both named "Jack" shows two
    identical `+ Jack` chips; the chip MODEL ("note is about person X → link X everywhere, one-note-one-link")
    conflicts with the per-occurrence reality (different mentions = different people = the existing
    `Sanitiser.applyResolvedOccurrences`/`InlineResolver` resolver). The opt-in gate also stopped the resolver from
    auto-appearing on fresh notes. The signed-off mock only covered DISTINCT names → same-name is unspecified.
  - **First-principles questions to grill (the real agenda):**
    1. What JOB does name-linking actually do for the user in the vault? (find "all notes about X" / a people graph /
       …?) Everything else is downstream of this.
    2. Do we even need INLINE `[[links]]`, or does the `people:` frontmatter list ALONE deliver the job? (The mock
       itself says "the people: list carries the graph connection" → the inline first-canonical/rest-alias machinery,
       per-occurrence resolver, unlink/relink, alias-display may all be solving a non-problem.)
    3. Is the names DB + alias normalisation pulling its weight, or accidental complexity from "ASR mishears names"?
    4. Two-Jacks / per-occurrence disambiguation: real recurring need or over-engineered edge?
    5. Right layer & time for linking: Mac pipeline now vs tap-on-phone vs let Obsidian resolve at read-time.
  - **Process for next session (user-locked):** (1) deep `/grill-me` on the WHOLE solution (Claude interviews the user
    relentlessly to reach shared understanding); (2) research agents to hunt SIMPLER / better prior-art solutions
    (how do other tools link/disambiguate same-name entities — Obsidian plugins, Roam, Logseq, Tana, Reflect, etc.);
    THEN decide → mock → build. Re-read this block + `mocks/opt-in-naming.html` first.
  - **What's already SHIPPED (unaffected, on `main`, may be partly reverted after the rethink):** opt-in chunks 1–5
    (Sanitiser `aboutPeople` gate, first-only inline, `people:` frontmatter, chip bar, Names list→detail editor) +
    the adversarial-review fixes. All gated/tested/deployed; see the BUILD STEPS + review block above.

## Sync says "connected" but memos stay "Waiting" (2026-06-15)

Device-reported: Dev mobile → Dev Mac, Settings shows connected, memos keep saying Waiting.
**Diagnosis (from pulling the phone's prefs + Mac `lsof`):**
- The Settings green "Connection" dot showed **whenever a pairing was merely SAVED** (`MacConnection.load() != nil`)
  — NO live check. So it claimed "connected" even when the Mac was off / on another Wi-Fi / a stale port.
- The sync path had **zero logging** (a silent `catch {}` left memos Waiting) → undiagnosable.
- The user's Mac was running **TWO `Skrift Dev` instances** (PID from Xcode DerivedData on `:8000` + a 2nd from
  `/Applications`). Two instances share one bundle id → one SwiftData store → writes contend. GET health/files
  (reads) answered 200, but the upload **POST (write)** is the likely casualty → the phone leaves the memo Waiting.
  (CLAUDE.md already warns: "quit the running app first — a 2nd instance races the shared SwiftData store.")
**Fixes (committed):**
- Settings dot is now a **live `/health` probe** — green only when the Mac actually answers; amber + "unreachable"
  + a hint when paired-but-not-answering (`SettingsView.checkReachability`).
- **Sync is now DevLog-traced** (`SyncCoordinator` + `URLSessionMacTransport`): target host:port, eligible count,
  each `POST …/upload → HTTP <code>` (or the error), final `newlySynced`. Pull `devlog.txt` after a sync tap.
**Owed / user action:** quit the duplicate `Skrift Dev` Mac instance (keep ONE), ensure the phone is on the same
Wi-Fi (Mac is `192.168.50.111:8000`), then tap Sync — read the `sync:` trace to confirm. Possible follow-ups:
single-instance lock on the Mac; auto re-resolve the Bonjour host/port at sync when the saved one is unreachable
(self-heal a changed Dev port); manual-sync is by design (no auto-sync).

## Cross-app parity gaps (audited 2026-06-15 — 9-agent verify-vs-code sweep)

The desktop↔mobile split is overwhelmingly INTENTIONAL (phone records/captures → Mac processes/links/
enhances/exports). The audit (verified each `FEATURES.md` row against real code in both apps + a completeness
critic) found exactly **two real functional gaps** to bridge; everything else is by-design or already parity:

1. ✅ **DONE 2026-06-15 — Desktop list search + sort.** Added to the Mac sidebar: a text-search field
   (title/transcript/summary), a Newest/Oldest/Title sort cycle, and a "No matches" empty state, on top of the
   existing 3-way `QueueFilter`. `AppModel.matchesSearch`/`SidebarSort`/`visible` + `SidebarView.searchField`/
   `sortControl`/`noMatches`. Live-verified via `SidebarSearchSortUITests` (the sidebar can't be `-snapshot`'d —
   ImageRenderer can't render its `FilePromiseDropCatcher`/`dropDestination`; macOS XCUITest needs Automation
   permission enabled). Sort is a cycle BUTTON (not a Menu) on purpose — a Menu also breaks ImageRenderer.
2. ✅ **DONE 2026-06-15 — Mobile direct "Add voice" enrollment.** `VoiceEnrollView` now records a short
   on-device sample (`FeedbackRecorder` → FluidAudio `AudioConverter` 16 kHz → `VoiceEnroller.enroll` → embed +
   `NamesStore.addVoiceEmbedding` + sync) — the SAME pipeline the conversation speaker-naming path already used
   (was a "Got it" placeholder). ≥3 s guard (`SpeakerEmbedder.minSamples` 32 000 = 2 s); audio discarded after
   embedding. UI-probe-verified (`VoiceEnrollUITests` on the iPhone 17 sim — seeded "Bob Smith" → Add voice →
   real recorder renders; screenshot `/tmp/skrift-enroll-shots`). On the sim the SeededEmbedder stands in for the
   ANE; device-eyeball owed for a real wespeaker embedding.

Deferred-by-choice (intentional, not gaps; do only if symmetry wanted): desktop **Models tab** mirror
(`FEATURES.md` "Mac mirror = later"); **custom-vocab word-list sync** (per-device by design — the only
intentional contract data-exclusion); desktop **Send-feedback** port; desktop **auto-copy transcript**.
Doc drift fixed in the same pass (`FEATURES.md`): capture-items `➖/➖`→`✅/✅` (was the worst — implied a
shipped feature was unbuilt), diarize/voice-match/persist-segments/bold-headers mobile statuses corrected,
search/sort desktop `✅`→`🟡`.

## Other deferred items
- **Watched-folder ingest** — point Skrift at a folder (e.g. the Mac Voice Memos export) for zero-friction auto-ingest. (The overhaul keeps ingest simple: drag/picker + phone sync.)
- **Summary prompt quality** — summaries read stale / not in my voice. Dedicated prompt-tuning pass once the rest is stable.
- **Tagging matchable-subset + lemma expansion** — which vault tags are auto-matchable (flag-per-tag vs separate list) and conjugation/lemma handling. Being decided in the mobile-app chat; align the desktop to it.
- **Git housekeeping** — remove the empty `claude/competent-haslett-718d5a` worktree; finish mining `robustness-cleanup` for any remaining good fixes before deleting it.
- ✅ **DONE (2026-06-09, parallel-lanes batch)** — **Import VIDEO → transcribe (with the real recording date)** —
  both apps. Phone: PHPicker + share/open-in video UTIs → extract audio (`AVAssetExportSession`) + ONE frame
  thumbnail as `[[img_001]]`, `recordedAt` from the embedded creation date. Mac: `IngestService` detects video →
  extracts audio. Open-Q resolved: **audio-only + 1 frame thumbnail** (original video discarded). Original plan kept below.
  accept video files on the
  phone (e.g. self-recorded "life advice to myself" clips) and transcribe their audio.
  Plan: extend the import path to video UTIs (`CFBundleDocumentTypes` += `public.movie` /
  `public.mpeg-4` / `com.apple.quicktime-movie`; `AppURLHandler` → `MemoSaver`) and/or a
  Photos picker (`PHPickerViewController`, filter `.videos`). Extract the audio track via
  `AVAssetExportSession` / `AVAssetReader` → feed FluidAudio on-device.
  **The memo's `recordedAt` MUST come from the video's embedded creation date**
  (`AVAsset` `.creationDate` metadata, or `PHAsset.creationDate` from the library) — NOT the
  import time. Mirrors how the Mac reads the embedded m4a recording date. Open Qs: keep/attach
  the original video or audio-only? a frame thumbnail as a `[[img]]`? Desktop side:
  `UploadService` / ingest needs the same audio-extraction if videos sync to the Mac.

## Mobile ↔ desktop unification + mobile UX (2026-06-08 brain-dump)
Captured from a session brain-dump; parity audit done (file refs are on branch `native`).
Locked process for the UI items: spec → mock → build → XCUITest (feedback_native_ui_process).

### Decisions taken (this session)
- **Significance gates sync — flag-to-send / opt-in.** Add a per-memo significance value on
  MOBILE, mirroring desktop's slider (0–1.0, snap 0.1, labels Passing/Useful/Significant —
  `SkriftDesktop/.../NoteProperties.swift:118`, stored `PipelineFile.swift:90`). **Default 0 =
  stays on the phone; > 0 = eligible to sync to the Mac.** Persist it on `Memo` + send it in the
  upload metadata (NEW, additive/optional contract field) so the Mac pre-fills its slider.
  (User: "only if they have more than 0 significance are they suitable for transfer — I don't
  need to send stupid messages to the Mac.") NOTE: this flips today's behavior (mobile currently
  uploads ALL `waiting` memos unconditionally — `SyncCoordinator.swift:31`).
- ✅ **DONE (2026-06-09)** — **Liquid-glass playback bar.** Replaced the ghosting `LinearGradient`
  with a real iOS-26 Liquid Glass floating bar (`.glassEffect(.clear)` + `.safeAreaInset(edge:.bottom)`
  so transcript scrolls cleanly *under* it), and slimmed its vertical height. The iOS-18-target note
  below is OUTDATED — we run iOS 26 and use `glassEffect`. **Device gotcha (logged for the next chat):**
  the lensed look needs `.clear` (`.regular` reads frosted), and **Reduce Motion ON throttles Liquid
  Glass on A15** (user's phone — turn Reduce Motion OFF); the Simulator never renders specular/chromatic
  glass, so judge glass on-device only.

### Items
1. ✅ **DONE** — **Significance slider on mobile + sync gating** — slider + flag-to-send live; the
   2026-06-09 batch also fixed the list to show **no sync pill** for significance-0 (phone-only) memos.
2. ✅ **DONE (2026-06-09 batch)** — **Append-more-transcription to an existing note** — a visible top-right
   "+" button on memo detail (and the ⋯ menu) records more audio → transcribes → appends + merges audio. Mobile-led.
3. ✅ **DONE (2026-06-09)** — **Karaoke on mobile** (unification): word-level highlight + tap-to-seek
   during playback. Was: mobile stored word timings (`WordTiming.swift`/`WordTimingsStore`) but never
   rendered them. Device-verified ("karaoke and edit work well").
3.5 **Mobile delete/select UX** — ✅ swipe-to-delete DONE (native List `.swipeActions`, full-swipe
   commits, in `MemosListView`; verified 2026-06-12 status audit). Still open: a nicer
   drag-to-multi-select (Photos/Mail-style) to replace the Select button.
4. **Feedback/email in Settings** — NEITHER app has any feedback/contact mechanism today. Port from
   the user's **Shhhcribble** app at `/Users/tiurihartog/Hackerman/ShhcribbleiOS` →
   `ShhhcribbleiOS/Features/Feedback/` (explored 2026-06-08). Its module:
   - `FeedbackStore` — file-based `Documents/Feedback/<uuid>/{metadata.json, screenshot.png}`,
     items = {createdAt, transcript, note, hasScreenshot, durationSeconds, sentAt?}; CRUD + markSent.
   - `FeedbackRecorder` — dictate feedback (record→transcribe→keep TEXT, discard audio).
   - `FeedbackCaptureView` / `FeedbackListView` — capture (note + optional pasted screenshot + dictation)
     + list with "Sent ✓" badges.
   - `FeedbackMailComposer` — `MFMailComposeViewController` (MessageUI, `UIViewControllerRepresentable`);
     To: `tiurihartog@icloud.com`; subject/body = transcript+note+timestamp+device; attaches a `.zip`
     of the raw folders (via `NSFileCoordinator .forUploading`). `canSendMail()` guard.
   **Skrift port plan:** add a "Send Feedback" row in `SettingsView.swift` → a capture sheet (typed note
   + optional dictation REUSING Skrift's `TranscriptionService`/`LiveRecordingService` + optional
   screenshot) → `FeedbackStore` (mirror, file-based) → email via an MFMailComposer wrapper. Needs
   `UIFileSharingEnabled`-style access if we want Files visibility. Consider desktop later (unification).
   Recipient `tiurihartog@icloud.com` (configurable).
5. **Capture items** — the big deferred cross-app feature (share URL/text/image + annotate): mobile
   share-extension target + App Group + `attachments` multipart; desktop `UploadService` accepts a
   non-audio "capture" content type through pipeline/compile/export. (Also in root CLAUDE.md.)
6. **"Transcription a bit weird" on cold auto-start** — user UNSURE it's a real bug now; park / quick-
   check only (live caption catching up while the model loads mid-recording).

### Dev/prod separation — ✅ DONE (verified implemented 2026-06-09)
Both apps split by config: Debug = `com.skrift.{mobile,desktop}.dev`, **"Skrift Dev"**, own data container +
test vault; Release = the real **"Skrift"**. The 2026-06-09 session also fixed the desktop menu-bar NAME
(`PRODUCT_NAME` per config, since `INFOPLIST_KEY_CFBundleName` was being dropped) and installed prod "Skrift"
to `/Applications`. **Open follow-up:** inverted-color dev app ICON (both apps) so dev is unmistakable by icon too.
Original decision recorded below.

#### (original decision, 2026-06-08)
Goal: use Skrift for real (real recordings/notes/vault) while still iterating, with the
real data OS-guaranteed safe from dev churn. **Approach = bundle-ID split** (chosen):
- **Production** keeps the current bundle IDs (`com.skrift.mobile` / `com.skrift.desktop`)
  — the install already on the phone, real data preserved.
- **Dev** builds get `.dev` bundle IDs → a brand-new, SEPARATE OS data container; dev
  builds physically can't touch prod memos/recordings/names. macOS Dev defaults its
  export to the **test vault** (`~/Hackerman/Obsidian_LLM_Test_Vault`), never the real one.
- iOS `.dev` plumbing: own App Group (`group.com.skrift.mobile.dev`) + widget/shared
  bundle IDs + automatic signing (team 9W82X49JZS handles new IDs); dev Mac advertises a
  distinct Bonjour name so the dev phone pairs with the dev Mac.
- **Look = name only** ("Skrift Dev"), same icon (user's call).
- Implement via an xcodegen build configuration that overrides bundle ID + display name
  (+ App Group/Bonjour for dev); keep Release = production.
- **"Switch them out" = promote** dev code under the prod bundle ID; SwiftData migrates in
  place. SAFE BY CONSTRUCTION if model changes stay **additive** (defaults, like
  `significance: Double = 0`) → lightweight migration. Test the migration on a copy first.

### Unification audit (mobile vs desktop) — exists on ONE side only
- significance slider → desktop only (→ add to mobile, item 1)
- karaoke word-highlight → ✅ DONE on mobile (2026-06-09); was desktop-only
- per-memo sync gating → NEITHER (→ new, item 1)
- feedback/email → NEITHER (→ new, item 4)
- swipe-to-delete → NEITHER (→ mobile, item 3.5)
- deep settings (vault/author/model/prompts) → desktop only (intentionally NOT unified — Mac-side concerns)

## Features to implement (added 2026-06-09)
- **Direct "record a voice" enroll in Settings → Names & voices** — today the "Add voice" row is a
  status label only; voices enroll ONLY via conversation-mode naming. Add a tap-to-record-a-sample
  enroll flow so a Person can be given a voiceprint directly. (Tied to the embedding-cosine pivot —
  see `CONVERSATION_MODE_HANDOFF.md` §5.) Both apps (the Names & voices tab is on phone + Mac).
- ✅ **DONE (2026-06-09 batch)** — **Desktop Liquid Glass pass** — the Mac review transport bar is now a
  floating glass capsule (`.glassEffect(.regular)` on macOS 26 + `.ultraThinMaterial` fallback). Judge live;
  flip `.regular`→`.clear` for a more lensed look. Sidebar left opaque (could extend).
- **Re-ingest the ~30 old notes** from `~/Desktop/Skrift old notes/` — run the existing ingest over
  them (DO WITH the user: needs the prod desktop app quit for the shared-store race, and it writes
  into the REAL Obsidian vault).
- **In-app feedback → `backlog.md` (not just email)** — today dictated/typed feedback is emailed
  (mobile `Features/Feedback/FeedbackCaptureView.swift` → `FeedbackMailComposer`, recipient
  `tiurihartog@icloud.com`; desktop has none yet). Idea: route feedback straight into this
  `backlog.md` so ideas become triage-ready items without copy-paste. **Constraint:** `backlog.md`
  lives in the repo (Mac/dev side) — the phone can't write it directly. Options: (a) sync feedback
  phone→Mac like memos, then the Mac appends to a dedicated `## Inbox (from in-app feedback)` section
  here; (b) a small scheduled agent reads the feedback inbox/email and appends + lightly tidies into
  the right section; (c) the desktop feedback module writes locally. Open Q: append raw vs. have an
  agent dedupe/route into existing sections. Pairs with the feedback port (item 4 above).
- **Show downloaded models in phone Settings** — a Settings → "Models / Storage" section listing
  the on-device models (Parakeet ASR; the diarization + voiceprint models once enrolled): downloaded?
  size, version, and optional actions (re-download, delete to free space). The state already exists
  (onboarding download + the record-ready preload status, `RecordView.swift:271-292`) — surface it in
  `Features/Settings/SettingsView.swift`. **Unification:** desktop also downloads models (~600 MB ASR
  + ~9 GB Gemma) — mirror a Models/Storage view on Mac Settings (ties to the desktop model-unload
  idle-timer backlog item). Open Q: read-only display vs. management (delete/re-download).

## Follow-ups from the 2026-06-09 parallel-lanes batch
Most of the brain-dump shipped this batch (record-screen polish, list fixes, video import, desktop glass,
diarization-segment persistence) — see `FEATURES.md`. Remaining threads it opened:
- **Task A — auto-sync names after voice enrollment (REAL BUG, confirmed).** Naming a speaker enrolls the
  voiceprint into the phone's local `names.json` but **never auto-pushes** — it only reaches the Mac on a manual
  sync-button tap (`SyncCoordinator.syncAll` is the ONLY caller of `NamesSync`). So cross-device auto-match
  silently lacks the new voiceprint until a manual sync. Fix: fire a names-sync right after a successful enroll
  (tail of `VoiceEnroller.enroll` / `learnVoice`, or on memo-save / app-foreground), debounced + guarded on a
  paired Mac. The merge/UNION itself is correct (now covered by `SkriftDesktopTests/NamesSyncRoundTripTests`).
- **Task A — live device round-trip** (human-gated): enroll on phone → confirm it lands in the Mac `names.json`
  with the server running → process that person's clip on the Mac → confirm `VoiceMatcher` auto-labels them.
- **Task B — Mac "name a speaker" review UI** (build phase): mock done (`SkriftDesktop/mocks/name-a-speaker.html`,
  awaiting sign-off); backend done (segments persisted: `DiarizationSidecar` + `PipelineFile.diarizationSegments`).
  Owed: a conversation-turn renderer in `Features/Review/` + click-to-name → people picker → relabel `**[[Person]]:**`
  → `DiarizationService.embedSpeaker` + `NamesStore.addVoiceEmbedding`.
- **F3 live confidence-color** is a positional approximation (trailing 6 words = "settling") — FluidAudio's live
  path exposes no finalized/volatile flag. Revisit if/when it does, for true locked-vs-volatile coloring.
- **Inverted-color dev app ICON** (both apps) so dev is unmistakable by icon (not just name).
  ✅ DONE same day (Debug → `AppIcon-Dev`, RGB-inverted; both apps).

## Device-testing feedback — 2026-06-10 (12 memos + feedback note pulled off the dev phone)
User ran the full TESTING_2026-06-09.md pass. Transcripts pulled via `devicectl` from the dev container;
crash logs via `idevicecrashreport`. **PASSED:** title-on-rows ✓, sig-0-no-pill ✓, + append button exists ✓,
keyboard-dismiss ✓, inline photos ✓, caption scrollback ✓, video date ✓, desktop video ingest (via Finder) ✓,
glass bar acceptable ✓.

### P0 — ✅ ALL FOUR FIXED (2026-06-11 fix batch, merged + all tests green; awaiting device re-test)
Fixes in brief: (1) crash → caption is ONE AttributedString in a single Text (run-count pinned by test);
(2) append → .transcribing shown throughout, clip kept until text lands, retry-with-backoff, terminal
failure surfaces as Error pill, editor-clobber window closed; (3) tail cutoff → explicit AVAudioFile
close() finalizes the m4a before transcription reads it (same race also hit append clips); (4) Live
Activity → staleDate+keep-alive, "Recording interrupted" stale fallback, foreground orphan reaping.
PLUS: instant record (locked decision — every record entry auto-starts), Spotify ducks only on Play,
paste keeps scroll position, row swipe/long-press Copy, desktop editable summary, first-mention-only
name links (incl. conversation turn headers), desktop video thumbnail, drag-from-Photos promised files,
retranscribe clears stale segments, list-delete cleans the diar sidecar. Original P0 list below.
1. **CRASH mid-recording (3× today, one recording LOST).** All three .ips identical: SIGSEGV "stack size
   exceeded due to excessive recursion" in SwiftUI `ConcatenatedTextStorage.resolve` — the live caption is
   built as per-word concatenated `Text` runs (solid+volatile+photo tokens), so a long recording → thousands-
   deep `Text + Text` chain → stack overflow. Fix: build ONE `AttributedString` and render a single
   `Text(attributedString)` (constant depth). Crash files: `/tmp/skrift-crashes/SkriftMobile-2026-06-10-*.ips`.
2. **Append silently adds NO text** (3× repro, BROADER than the model-cold theory — verifier-corrected).
   Repros: (a) stopped the append recording before the ASR model loaded; (b) tried AGAIN with the model
   presumably warm — still no text; (c) appended after manually editing the note body — nothing added.
   `MemoSaver.appendRecordingAsync` merges audio but can silently add no text with no error. Fix: REPRODUCE
   first (all three sequences), then harden the whole append-text path — never silent-no-op, queue
   transcription when the engine isn't ready (status `.transcribing`), surface failures; regression tests
   for cold-model append and append-after-manual-edit.
3. **Tail of recording cut off after Stop** (BOTH dev + prod, intermittent): live caption had the full text,
   then the final one-shot file transcription replaced it WITHOUT the last bit. Likely a race: final
   transcribe reads the file before the writer flushes the last buffers, or stop truncates. Investigate
   `LiveRecordingService.stop` → final transcribe ordering. "This shit needs to be very robust."
4. **Live Activity doesn't end**: lock screen still showed "recording, 45min" long after stop+save. End/
   dismiss the activity reliably on stop (and on app foreground if stale).

### P1 — bugs (post-promotion ok)
- **Confidence colors wrong in practice**: "white text is supposed to be non-changing but it also changes" —
  the positional approximation visibly fails (re-transcription rewrites the 'solid' body too). Either find a
  real finalized signal or drop/soften the distinction.
- **Opening a memo stops Spotify**: audio session activates on note open (player setup) instead of on Play.
  Use `.ambient`/don't activate until playback; respect `.mixWithOthers` when idle.
- **Paste into note body teleports scroll to top** (mobile editor) — keep scroll position after paste.
- **Share-a-video from Photos doesn't list Skrift** (mobile): document types alone don't surface the app for
  videos in the share sheet — likely needs a share extension or different UTI handling. (Photos→file works.)
- **Desktop: drag direct from Photos app doesn't ingest** (works via Finder) — Photos drags provide promised
  file/`NSItemProvider`, not a file URL; accept promised files in the drop handler.
- **No video thumbnail seen — check BOTH apps** (verifier: source ambiguous). Desktop `ingestVideo` has no
  frame-grab by design → add one (mirror mobile). Mobile claims `[[img_001]]` — verify it actually renders
  on a real import.
- *(doc fix, not a bug: TESTING guide said the desktop glass play bar is at the BOTTOM — it's pinned at the TOP.)*
- **Desktop: summary not editable** in review.
- **Desktop: name-linking brackets EVERY mention** (user expects `[[Name]]` first mention only, alias after —
  the Sanitiser's design intent; verify what produced all-bracket output, possibly the conversation-turn
  headers or a regression).
- **`SkriftMobile.diskwrites_resource-2026-06-10-221621.ips`** — disk-writes resource warning; check what's
  writing heavily (likely model download or audio writes).

### Feature decisions — LOCKED 2026-06-10 (user sign-off)
1. **Feedback loop = plug-in-phone → Claude pulls + parses + triages into this file** (devicectl app-container
   pull, proven 2026-06-10). Email path dead. **Valid only while the user is the sole user** — revisit if the
   app ever gets other users. Skill: `.claude/skills/pull-phone-feedback/`.
2. **Share extension = build as FULL capture items** (not a video-only hack): share URL/text/image/video +
   annotate, share-extension target + App Group + `attachments` multipart + desktop capture content-type.
   **OWED TOMORROW: walk the user through what (if anything) must be set up in the Apple Developer portal /
   App Store Connect for the new extension target + App Group** (likely nothing manual — automatic signing
   team 9W82X49JZS auto-registers bundle IDs + App Groups for dev builds; explain + verify).
3. **Custom vocabulary** — GO. ✅ SPIKE DONE (2026-06-11): FluidAudio `main` (7f963cd, identical checkout in
   both apps) ships a full custom-vocab system — CTC word-spotting + rescoring (NeMo arXiv:2406.07096,
   "separate CTC encoder"; works with the Parakeet TDT 0.6B v3 both apps use). Neither app uses
   `SlidingWindowAsrManager` (its built-in `configureVocabularyBoosting` doesn't apply); both call
   `AsrManager.transcribe` directly → integrate like the CLI batch pattern: after `transcribe`, run
   `CtcKeywordSpotter.spotKeywordsWithLogProbs` over the same samples, then
   `VocabularyRescorer.ctcTokenRescore(...)`, take rescored text when `wasModified`. Cost: one extra
   ~97.5 MB HF model. Build next: Settings "Custom words" list (both apps) + the rescore pass in each
   transcriber.
4. ✅ **DONE (2026-06-11 batch)** — **Trash / 2-week retention** — all delete paths soft-delete (list +
   detail), "Recently Deleted" sheet, lossless Restore, startup purge ≥14 days. ✅ **DESKTOP MIRROR DONE
   2026-06-13** (`Pipeline/DesktopTrash.swift` + `PipelineFile.deletedAt` + `Features/Sidebar/RecentlyDeletedView.swift`):
   soft-delete keeps the working folder (lossless Restore), 14-day launch purge, trashed excluded from
   sidebar/queue/process + the phone's `GET /api/files/`; sidebar footer "Recently Deleted (N)" → restore
   sheet; `-snapshot-trash` verified; 236 unit + build green.
5. ✅ **DONE (2026-06-11 batch)** — **Auto-copy transcript** — opt-in Setting, default OFF; copies on
   transcription success incl. appends.
6. ✅ **DONE (2026-06-11 batch)** — **Front camera toggle** — flip button in CameraSheet; front hides
   zoom presets, pinch floored at 1×.
7. ✅ **DONE (2026-06-11 batch)** — **Click-`[[name]]`-to-unlink (desktop)** — built per signed-off mock:
   two scopes (this mention → alias as spoken; all mentions in note + persisted no-relink-on-reprocess via
   `PipelineFile.unlinkedNames`), undo toast, 15 tests. Note: single-mention unlink is a body edit (not
   persisted across re-transcribe) — by design, consistent with hand edits.
8. **Audiobook quote-capture** — direction written below; design after the current wave.
9. **Significance wall** — GO, threshold **≥ 0.8**; AirPrint; refine-gate before export; design with the
   audiobook session. ✅ The locked **circles UI is DONE (2026-06-11 batch, BOTH apps)** — 10 tappable
   circles per the signed-off mock (all three ≥0.8 wall cues, re-tap clears, tier labels); the wall
   PIPELINE (refine gate + print) remains the design-session item.

### Audiobook quote-capture — DESIGN LOCKED 2026-06-11 (grill session; supersedes the direction below)
Build-ready spec, every branch user-approved. **MOCK SIGNED OFF same day** ("wouww looks great, let's go").
✅ **BUILT 2026-06-11 (4-lane batch, all tests green, merged to native)** — see FEATURES.md "Audiobook
quote-capture" for the full capability×file map. Also in that batch: ✅ the resolver per-occurrence
INSTANT-apply fix (each pick renders immediately, document-order demotion, progress counter).
Owed from lane flags: device-test the capture flow end-to-end (grains/scrubber feel, ramble append,
Mac round-trip of a quote memo incl. quote protection + [[Author]] export).

#### Device-test results — 2026-06-11 23:00 — ✅ ALL FIXED same night (3-lane batch + polish, tests green)
Fixes: scrubber gesture rewrite (root cause: .contentShape applied AFTER .offset stacked both hit-zones in
the strip corner → 56pt latched per-handle targets, min-span clamp, pannable window w/ edge-bump); preload
on capture-open; post-ramble = review-first (green SAVED card w/ live appended text, resume ONLY on Save &
keep listening, button flips to "Add more"); single import affordance; MULTI-FILE BOOKS (multi-select →
one book, filename-ordered chapters, continuous cross-file playback, capture confined to one file —
cross-file spans flagged as a possible later enhancement); styled quote + attribution caption BOTH apps
(presentation-only, raw "> " preserved); desktop book glyph + "Audiobook quote · <Title>" source; list chip
truncation (all chips capped 220pt). POLISH: mini-player 104pt (~2×), 2h-idle session auto-end, Siri
"Resume my book in Skrift" (plain-AppIntent pattern). Owed: morning phone install + re-test (esp. scrubber
feel, folder import, AirPods re-insert recheck). Original findings below.

#### Morning re-test — 2026-06-12 (round 2)
**PASSED:** folder import → one book ✓ · scrubber handles respond ✓ · post-ramble review flow "way better" ✓
· styled quote + ch. attribution ✓ · in-note BOOK AUDIO playback loved ✓.
**New fixes:**
- **Chapter titles unreadable** (full filename per row): strip the files' longest-common-prefix + extension
  → "chapter_01"/"Chapter 1". Compare Bound's chapter list.
- **Mini-player bar grotesquely oversized** (Capture text wraps vertically; ORCHESTRATOR'S OWN MISS — scaled
  by arithmetic, never rendered): proper resize ~72-76pt, fixedSize/lineLimit(1) so wrap is impossible.
- **Capture screen round 2:** (a) grains/preview "always talking" — add explicit pause/mute + only sound
  while actively dragging; (b) span/pan semantics confusing — pan moved the SPAN with the window, span
  ended up "now+99s→now+256s" (future of the pause point!), labels relative-to-now unreadable → labels in
  BOOK TIME (or chapter time), pan moves WINDOW only, add "back to pause point" jump; (c) long quote text
  not scrollable on the sheet; (d) pressing Capture yanked AirPods from the Mac (session activation —
  don't activate audio for grains until first drag).
- **Edit book AFTER import:** title + author + cover (⋯ menu in the player — user expected it there; keep
  Chapters in the menu too, add "Edit book details" sheet; cover pick from Photos/Files).
- **P0 RECORDING ROUTE STILL BROKEN (worse):** memo recording with AirPods → pull out → recording DIES (no
  fallback to phone mic — the earlier restart-without-tap-reinstall fix is insufficient on device, the
  flagged format-mismatch follow-up is the likely cause); re-insert → still dead AND THE AUDIOBOOK STARTED
  PLAYING (AirPods auto-play remote command hit AudiobookSession while a recording was supposedly active).
  Fix: reinstall the tap with the new route's input format on EVERY route change; AudiobookSession must
  IGNORE remote-play while a recording is active (session priority).
- Bookmarks: user considered, DECIDED AGAINST (linking back into books = complexity/fragility). Skip.

#### Round-2 re-test — 2026-06-12 — ✅ P0 FIXED (validate-before-install + own-activation echo filter + stale-format check), DevLog shipped (Documents/devlog.txt, devicectl-pullable), swipe-down player + tap-cover-to-edit. CAPTURE DESIGN STILL PAUSED. Owed: device re-test w/ devlog pull.
- **P0 CRASH: first tap of Record crashed the app** (fresh install, round-2 build). Crash log pull attempted
  to /tmp/skrift-crashes2 (check SkriftMobile-2026-06-12-*.ips; if absent, pull next plug-in via
  idevicecrashreport). Suspects: instant-record path or the new route-change tap-reinstall init.
- **P0 DIAGNOSED (crash log SkriftMobile-2026-06-12-081100.ips, kept in /tmp/skrift-crashes3): BOTH
  morning failures are ONE bug — the round-2 route fix itself.** NSException → SIGABRT in
  `LiveRecordingService.installRecordingTap` ← `rebuildTapForCurrentRoute` ← `handleRouteChange`
  (AVFAudio InstallTapOnNode raise). First record tap: session-activation fires .categoryChange →
  rebuild installs a tap with an invalid mid-transition input format (0 Hz/0 ch) or double-installs →
  abort. AirPods pull: same path = app CRASHED (user read it as "stopped recording"). FIX DIRECTION:
  (a) ALWAYS removeTap before install; (b) VALIDATE input format (sampleRate>0 && channelCount>0)
  before installTap — NSExceptions are uncatchable from Swift, preconditions are the only defense;
  retry on a short delay while the route settles; (c) ignore route events caused by our OWN session
  activation (.categoryChange at start); (d) build WITH the dev file-logging item so the fix is
  verified from traces, not vibes.
- **P0 STILL BROKEN: AirPods pull-out stops the recording** (started with AirPods → pulled → recording
  stopped). The tap-reinstall fix did NOT hold on device. NEXT: stop guessing — add DEV-BUILD FILE LOGGING
  (user explicitly asked): a ring-buffer log file in the app container (os.Logger mirror or simple appender;
  recording/route/session events), pullable via devicectl like the feedback skill → diagnose from REAL traces.
- **Capture tool still confusing — STOP REBUILDING (user decision): design pause.** Next session = sit down
  with the user / produce interaction mocks for the capture-adjust flow BEFORE more code. No more iteration
  batches on CaptureMomentView until the design is agreed.
  - **🧠 DESIGN THINKING 2026-06-22 (for that paused session — overlaps the note-editing sprint's selection
    primitive).** Direction the user is leaning: **pull capture INTO the reader via in-place text selection**
    (highlighter / Kindle model) instead of a separate capture screen — select a passage → small menu
    (Highlight · Note · Bookmark), stay on the page. Keep Skrift's edge (the **voice ramble**) as a
    LIGHTWEIGHT inline bar (talk while staying on the page; grab the quote audio behind the scenes), not a
    full screen. **Bookmark vs Note = same gesture, different keepsake:** a bookmark is a *breadcrumb*
    (stays in-book, jump-back, throwaway); a note is a *souvenir* (becomes a memo → sync → tags/significance
    → Obsidian, permanent). Don't merge the entities; unify the gesture. **Missing middle tier = a plain
    HIGHLIGHT** (save the passage's words, no ramble) — the literal highlighter act, between bookmark (a
    point) and note (a voice capture). Possible unified model to MOCK: **"Marks"** = bookmarks + highlights
    (a point OR a text span; both in-book, both jumpable) and **"Notes"** = a mark you've talked over →
    promoted to a memo (bookmark = mark w/ no text; highlight = mark w/ text; note = highlight + your voice).
    Mock-first; shares the selection mechanic with the note-editing sprint.
- **Bar at bottom: looks good now** ✓.
- **Full player (big-thumbnail screen): add swipe-down to close.** Also: user still couldn't change the
  cover ("still needs to be able to be changed") — Edit-book-details shipped in round 2 under the ⋯ menu;
  either they tested before finding it or discoverability is poor → check + consider a tap-on-cover edit
  affordance.

#### (original findings)
**WORKED:** import (single file + manual title/author confirm) ✓ · play + mini-player + nudged FAB ✓ ·
capture E2E ✓ · ramble append ✓ · circles + Will-sync line ✓ · sync to dev Mac ✓ · **QUOTE PROTECTION
held — the book quote came through enhancement untouched** ✓.
**P0 fixes (capture UX):**
- **IN/OUT scrubber handles barely respond / freeze**; dragging toward IN makes OUT jump (gesture grabs
  the wrong/nearest handle; persisted across audio-route changes, so it's the gesture system, not routes).
- **Post-ramble flow wrong ×2**: the book auto-resumed IMMEDIATELY on recorder dismiss (user couldn't
  review what they spoke) AND the record-thoughts button stayed big/purple (rambleAdded state never
  showed). Fix: no auto-resume after a ramble — resume only on "Save & keep listening"; show the
  ramble-added state + the appended text for review.
- **Span can't extend past the proposed 30s window** — the micro-scrubber window must PAN (scroll
  left/right beyond the initial span) so IN/OUT can be placed further back/forward.
- **First-capture transcription slow** — preload the transcriber the moment the capture screen opens
  (second capture was instant; warm-model). 
- **Multi-file books unsupported**: many audiobooks are file-per-chapter (the user's is ~30 mp3s); Bound's
  importer multi-selects a whole folder as ONE book ("the selector in Bound is way better"). Import must
  accept multi-select/folder → one book, files = chapters in order. *Verifier nuance: Bound's PICKER UX
  itself is the model (Select All over a chapter folder, one obvious flow) — not just the capability;
  the scrubber bug presented as PROGRESSIVE freezing (handles fully unresponsive on later attempts), so
  the gesture fix must address freeze, not only wrong-handle grabs.*
- **Two import affordances in the Library** (big dashed row + toolbar +): keep ONLY the toolbar +.
**P1 presentation:**
- **Memos-list capture row: the book chip overflows off-screen** (long book title; needs truncation).
- **Quote styling missing in the note body (BOTH apps)**: shows as plain "> " lines — no italics, no
  quote bar, no chapter/author attribution → "looks like I recorded twice". Render the C1 blockquote
  styled (italic + bar) with an attribution caption derived from C2 metadata (presentation-layer; the
  real `[[Author]]` line stays export-time).
- **Desktop source wrong for captures**: shows "Voice memo" + mic glyph; should be an audiobook-quote
  source (book glyph) when C2 bookTitle is present — sidebar + properties. (NOT a sync bug: the C2 book
  metadata arrives fine — the phone derives its book glyph from it; the desktop just never does.)
- **Backlog (capture-items umbrella): unify the SOURCE taxonomy across both apps** — voice memo / URL /
  document-PDF / video / audiobook quote / Apple Note — consistent glyphs + labels everywhere (user:
  "all the sources should be done well"). 
- **Mini-player bar ~2× vertical height** (user, 2026-06-11 late): buttons too small to hit comfortably;
  it only shows during an active session so it can afford the space. Apply post-merge (fix-lane owns the file).
- **Mini-player AUTO-HIDE after idle** (user, 2026-06-11: "I'm always listening to one book or another —
  the player will be there always"): the bar must end its session automatically after X paused time
  (start ~2h idle, + on app launch when last-played is >~6h old; constants flippable). Zero loss: progress
  persists per-book; reopening from the Library resumes exactly. Post-merge pass, with the 2x-height tweak.
- **Siri: "play/resume my book in Skrift"** — an App Shortcut that resumes the last-played audiobook.
  SAFE SHAPE per this repo's SIGTRAP history: plain `AppIntent` + `openAppWhenRun` (like
  StartRecordingIntent), NOT an audio-playback intent; opens the app + resumes playback. Phrases:
  "Resume my book in Skrift", "Play Skrift book". (True background-start via AudioPlaybackIntent = later
  experiment, device-tested carefully.)
- Watch: scrubbing while another device held the AirPods felt entangled with the route (audio yanked
  from Mac to phone) — recheck after the gesture fix lands.
1. **Skrift IS the player** for actively-mined books — model it on **Bound** ("there isn't a feature
   there I don't like"): Files/iCloud import, library w/ covers + sort, per-book resume, speed, sleep
   timer, embedded m4b chapters, background playback + lock-screen transport. One book at a time moves in.
2. **One memo per capture** (NOT a per-book note): each capture = quote block + ramble + book metadata in
   frontmatter; full existing pipeline applies (significance, sync, enhance, export). A generated
   per-book index note is a possible later export-side addition.
3. **Capture gesture = RETROACTIVE**: one Capture button (in the full player AND the mini-player) pauses
   the book and proposes span [now−30s → now]; the ~15s **micro-scrubber** adjusts IN (and OUT), with
   **snippet audio scrubbing** in v1 (hear grains as you scrub; DaVinci-style varispeed = v2 polish).
   **Sentence-snap OUTWARD** on both edges (sloppy markers always yield whole sentences). Optional
   long-press marker-in for the foresight case if it falls out cheap.
4. **Transcription = span-on-demand ONLY** (marked range ±~20s buffer through Parakeet, seconds-fast).
   Whole-book indexing explicitly REJECTED ("I don't see the point").
5. **Quote audio = the memo's audio** (span extracted to the memo .m4a) → playback/karaoke/sync/export
   toggle all work for free; you can hear the author from Obsidian. **Ramble = the append flow**
   (A-dominant: record-your-thoughts is the big button on the capture sheet; "Save & keep listening"
   secondary; book auto-pauses during ramble, resumes in place after).
6. **Metadata from file tags at import** (title/author/chapters; one editable confirm screen only if
   missing). Chapter per capture derived from marker position. Capture itself asks NOTHING.
7. **Export**: italic quote block + attribution "— [[Author]], *Book*, ch. N". `[[Author]]` is written
   as a literal wikilink AT EXPORT ONLY — authors NEVER enter the names DB (would pollute alias matching).
8. **Enhancement protects the quote — option (b) from day one**: strip quote block behind an anchor
   (image-marker pattern), copy-edit ONLY the ramble, reinsert, then **assert the quote is byte-identical**;
   any mismatch → fall back to skip-all-copy-edit + flag. Title/summary generate normally.
9. **Placement**: Library behind a book toolbar icon on the memos list. **Conditional mini-player** —
   exists ONLY while a book session is active (Bound-style glass capsule: cover, ⟲15, play, 15⟳,
   **Capture ❝**, expand ˄); the record FAB nudges up above it; mini-player YIELDS on memo detail (book
   keeps playing in background); record-FAB-while-playing auto-pauses the book and resumes after save.
   Captures appear in the memos list with a book glyph. App identity stays notes-first.
10. Mobile-first; capture memos sync to the Mac as normal memos (book files never sync). Open/minor (mock
   decides): significance circles on the capture sheet vs detail-only; mini-player on the Library screen.

### (original direction, 2026-06-10 — superseded above)
Capture a passage from an audiobook as a quoted, attributed note + your own thoughts under it.
- **Flow (preferred shape, in-app):** audiobook section in Skrift → loads the transcription model in the
  background → fine scrubber for precise positioning (a ~15s micro-scrubber alongside the normal one — a
  15h book makes one scrubber useless) → set marker-in, listen, marker-out → that span is transcribed,
  **snapped to natural sentence boundaries** (don't cut mid-sentence; markers are imprecise by nature) →
  inserted as a QUOTE block (italics) with book/chapter/author metadata asked-or-inferred → free rambling
  space below the quote (the user's own thinking — the actual point).
- **Alt shape (lock-screen markers):** marker-in/out from the lock-screen player controls — iOS gives 3rd-
  party apps limited lock-screen control, so realistically this degrades to the in-app flow; park it.
- **Player inspiration:** "Bound" audiobooks app (one-time payment; loads audio straight from Files/iCloud —
  that ingestion model is the one to copy). User has it; could inspect on the jailbroken iPhone for UX.
- **Maybe-later:** linking the quote-note to existing notes at capture time (or leave linking to Obsidian).

### P2 — feature requests from testing
- **Instant record**: tapping record (or + append) should START RECORDING IMMEDIATELY — no record-ready
  screen stop; model loads in background (it already catches up).
- **Feedback rework**: not email — user wants Claude to read feedback directly off the phone (PROVEN possible
  today via devicectl pull) or append to backlog.md. Plus: floating/shake-to-feedback affordance w/ screenshot
  (Henry's idea), not while recording.
- **Copy-transcript button on each memo row** (today: open → ⋯ → copy). Multiple paths to the same action.
- **Auto-copy transcript to clipboard after transcription** (cheap backup against data loss).
- **Custom vocabulary / word boosting** ("Skrift" mis-recognized; FluidAudio CTC boosting exists per memory).
- **Trash with ~2-week retention** instead of permanent delete (like Apple Voice Memos).
- **Front camera option** for in-recording photo capture (selfie).
- **Click a `[[name]]` to revert to alias** (desktop review): popup like the disambiguator with "unlink".
- **Audiobook quote capture** (BIG idea, design doc needed): mark in/out while listening (in-app audiobook
  player or lock-screen scrubber), transcribe the marked span snapped to sentence boundaries, insert as a
  quote block (chapter/book/author metadata) + space for own rambling below. Inspiration: Bound audiobooks
  app (loads files from iCloud/Files). Possibly later: link to existing notes.
- **Significance-gated "wall" pipeline**: notes above a significance threshold require a manual refine pass
  (desktop gate: can't export to Obsidian until refined) → then export + send to printer for the physical wall.

## Device-testing feedback — 2026-06-11 (4 memos pulled; verifier-passed; screenshot of two-Jacks on dev Mac)
**PASSED:** front-camera flip ✓ (photo mid-record, `[[img_001]]` inline) · circles on phone ✓ (0.4 set via
circles) · circles render on dev Mac ✓ (screenshot) · "the black screen is fixed" ✓ (ambiguous which —
ask) · feedback-via-memos + pull workflow accepted (no dedicated feedback feature wanted).

**Not a bug:** two-Jacks file on the dev Mac showed NO name linking — the dev container has NO `names.json`
(starts empty by design; prod has the Jacks). To test names on dev: add the people in dev Settings or sync
from the dev phone first.

### New items
- **P1 — instant-record flashes the old ready screen** before recording starts (model-loaded screen with
  the legacy record button). Remove the transient screen (or skip straight to the live caption) — it no
  longer serves a purpose on the auto-start path.
- **P1 — AirPods RE-insertion doesn't resume**: pull-out mid-record survives (route-change fix works), but
  putting them back in didn't move input back to AirPods ("I think it was a fail"). Confound: they may have
  re-paired to the Mac. Repro with Mac BT off; likely the `newDeviceAvailable` branch needs the same
  restart treatment as removal.
- **WATCH — Live Activity "still going on the last thing"** on the lock screen right after the new install.
  Possibly a stale activity from the PRE-fix build (new build reaps on foreground). Observe once more on
  the new build; if it recurs, the reaper has a gap.
- **Confirms backlog priority:** Settings → Models/Storage list ("we have three models — transcription,
  diarization and something else") — already specced under "Show downloaded models in phone Settings".
- Next focus per user: the BIGGER design items (capture-items build, audiobook, significance-wall pipeline,
  vocab build).
- **Reassign in the unlink popover** (from the two-Jacks discussion): clicking a linked `[[Name]]` should
  offer not just Unlink but **"Change to → <other person>"** (one-tap fix when the deterministic alias
  match picked the wrong person — e.g. a spoken "Jack" auto-linked to Timmons but meant Hutton). Reuses
  the people-picker; per-mention scope.

## Audit findings (2026-06-09 post-batch error sweep — triaged, verified against code)
Two read-only agents swept both apps after the batch; orchestrator verified each claim before listing.
None are release blockers; fix in a follow-up pass.

**Mobile:**
- **`[photo N]` markers anchor by WORD COUNT at capture** (`RecordView.swift:83`) but the live caption
  re-transcribes wholesale, so the token can drift later than the real capture point (clamped, no crash).
  Fix: anchor by TIME offset (stable across re-transcription) — `LiveCaptionLayout` maps time→word at render.
- **Recorder teardown hygiene** (`LiveRecordingService.swift`): route observer + timers rely on `stop()`
  running before `deinit`; an abnormal teardown can leak them (`[weak self]` prevents a crash). Fix: explicit
  `stopTimers()` + `teardownRouteObserver()` in `deinit`.
- UX nits: silent video (no audio track) imports as a silently-`failed` memo (no user feedback); a failed
  video import shows import-time instead of the video's date; rapid photo taps are silently debounced (0.6s).
- *Dismissed as false positives (so future sweeps don't re-flag): "SwiftData off-main in append" (`MemoSaver`
  is `@MainActor`); "append audio format corruption" (export re-encodes via `AppleM4A`; merge-failure falls
  back to base-audio+text by design; temp-export→swap order is safe).*

**Desktop:**
- **Re-transcribe leaves STALE diarization segments** (`ProcessingCoordinator.retranscribe` resets transcript
  but not `diarizationSegmentsJSON`/sidecar) → re-transcribed conversation memos can carry old speaker
  segments → wrong enrollment slices. Fix FIRST: clear segments + delete the sidecar in `retranscribe()`.
- **Sidecar write is `try?`** (`DiarizationSidecar.swift:47`) — a failed write is silent. SwiftData copy
  still survives (so no data loss), but log + surface it; the sidecar is the portability/enroll copy.
- Pre-existing, already-tracked (now slightly more pressing with video uploads): full multipart body
  buffered in RAM (256 MB cap; `SyncServer.swift:90`); `DispatchQueue.main.sync` SwiftData bridge in the
  Bonjour handlers (`SkriftDesktopApp.swift:46,59` — deadlock-free only while handlers never run on main);
  health endpoint vs the model idle-unload interplay (phone may see `available=false` after 60s idle).
- Minor: HEIC→JPG conversion failure falls back silently w/ a possibly-broken md ref (`IngestService.swift:282`);
  snapshot PNG write is `try?`; `SpeakerFusion.foldShortIslands` indexing deserves explicit bounds asserts.

#### DevLog verdict 2026-06-12 09:14 (log in /tmp/devlog.txt — DevLog works perfectly)
NO crash ✓, echo-filter ✓, re-insert recovery ✓. REMAINING BUG: `canInstallTap` requires hw format ==
old tap/file format → REFUSES legitimate cross-rate rebuilds (AirPods 24k ↔ built-in 48k), gives up after
4×250ms permanently → recording goes DEAF on the new route (both the first-record race and the pull-out).
FIX: tap must install in the CURRENT hw format whenever valid (rate>0,ch>0) — the AVAudioConverter in the
write path bridges tap→file; only refuse transient invalid/disagreeing formats; retry with backoff ~3s;
NEVER permanent give-up — re-arm on every later route/config notification + observe
AVAudioEngineConfigurationChange (the canonical format-changed signal).

#### DevLog round 3 (2026-06-12 09:40, /tmp/devlog2.txt): DEADLOCK ON STALE VENDED FORMAT
ACCEPT path + echo-filter + start-retry all work. BUG: after a route flip the inputNode keeps VENDING the
old format (vended=48k vs sessionHw=24k, frozen across every retry) — AVAudioEngine caches node formats
until `engine.reset()`. The rebuild never calls reset → vended never converges → refuse-loop until user
cancels. FIX: on vended≠sessionHw in rebuild: removeTap → engine.stop() → **engine.reset()** → re-query
vended → install (+ reconnect/restart as the start path does). DevLog the reset.

#### DevLog round 4 (09:56, /tmp/devlog3.txt): DIAGNOSIS COMPLETE — WRONG PROPERTY
Even after engine.reset(), vended (inputNode.outputFormat) stays 48k forever — it's the ENGINE RENDER
format, not hardware. nodeIn (inputNode.inputFormat) = 24k AGREES with sessionHw on every line. The
validator demands the un-convergeable property. FIX (orchestrator doing it DIRECTLY, no agent): validate
nodeIn vs sessionHw; install the tap with format = inputFormat(forBus:0) (or nil); converter bridges to
file. Drop the vended check entirely.

#### ✅ AirPods P0 CLOSED — 2026-06-12, round 4 DEVICE-VERIFIED ("it works!")
Four layers, each peeled by a device trace: crash (NSException on install) → policy (refused legit
cross-rate) → cache (no engine.reset) → WRONG PROPERTY (validated outputFormat — engine-render-pinned,
can never converge — instead of inputFormat, which tracked hardware on every logged line). Final fix
applied by the orchestrator directly. Recording now survives pull-out AND re-insert.

#### Capture redesign — HYBRID SIGNED OFF 2026-06-12 ("everything works quite nicely")
Spec = `mocks/capture-redesign.html` mode 4 ⭐. One screen, one playhead, play/paused is the only state:
- ENTRY: auto-replays from −45s at 1.5× immediately (model preload stays). Full transport beneath
  (⟲5 · ▶/⏸ · 5⟳); rate pill (1×/1.5×/2×) pinned RIGHT of the row, transport stays centered.
- MARK: two buttons (「 Mark In / Mark Out 」) drop flags AT the playhead — −0.7s reaction bias while
  playing, exact while paused. Re-tap moves the flag. NO draggable handles, NO window/pan mode, NO gain
  graph, NO grains (playback IS the audio feedback).
- FINE-TUNE: ±1s chips per edge; in-chip nudges AND INSTANTLY REPLAYS from the new in-mark (the
  spam-to-find-start mechanism — MUST work while the span is playing, no pause needed; mock couldn't,
  code must); out-chips replay only the last ~5s up to the new out.
- ⟲ past the strip's left edge extends the window arbitrarily far back (clamped to the chapter file).
- Sentence-snap OUTWARD stays on confirm. ▶ Play span before Continue.
Replaces CaptureMomentView's interaction wholesale; capture SHEET (quote+ramble) unchanged.

#### Hybrid capture — first device test 2026-06-12 13:11
Screen matches the mock ✓ (sweep, transport, rate pill, marks, hints). Findings:
- **Make the capture screen FULLSCREEN + swipe-down to close** (currently floats with dead space below).
- **UX: start landed wrong — "I think it just added an extra sentence"** (user deleted the capture).
  Diagnosis: the −0.7s reaction bias can push the in-mark back ACROSS a sentence boundary into the
  previous sentence's tail; snap-OUTWARD then swallows that ENTIRE previous sentence. Bias + always-
  outward compose badly at the IN edge. Proposed (awaiting sign-off):
  (1) NEAREST-boundary snap at IN: if the mark sits in the last ~1s of the previous sentence (bias
      overshoot) snap FORWARD to the next sentence start; only snap back when the mark is genuinely
      inside the sentence. Outward stays for OUT.
  (2) Sentence-level trim on the capture SHEET: render the quote with first/last sentence droppable
      (one tap removes the leading/trailing sentence) — fix-by-reading after the fact, no re-scrub.

#### Capture round 2 — SIGNED OFF 2026-06-12 ("this works great, let's go"); one Sonnet lane
1. NEAREST-boundary snap at IN: mark in last ~1.0s of the PREVIOUS sentence (bias overshoot) → snap
   FORWARD to next sentence start; genuinely mid-sentence → snap back as today. OUT stays outward.
2. SENTENCE-TRIM on the capture sheet (spec = mocks/capture-sheet-trim.html): one grey context sentence
   each side; tap grey → include (context window slides); tap bright EDGE → drop (middles refuse w/ hint);
   audio span FOLLOWS included sentences via word timings; transcript = the existing span±buffer (already
   transcribed — zero wait). Sentence granularity only, no sub-sentence scrubber.
3. Capture adjust screen FULLSCREEN. 4. Swipe-down closes it.

#### Capture round 2 — DEVICE-VERIFIED working ("it works, very well done"). Two bugs:
1. KARAOKE broken on captured notes (word highlight/tap-to-seek no longer works during playback).
   Suspect: round-2 trim re-derives quote text+audio but the word-timings sidecar isn't re-derived/rebased
   to the final trimmed audio — or the styled-quote rendering path skips karaoke.
2. MEMO PLAYBACK and the AUDIOBOOK can play SIMULTANEOUSLY (play in a note while the book plays).
   Fix: AudioPlayerModel.play() pauses AudiobookSession (and book play should pause the memo player).
DIAGNOSIS (orchestrator): the sheet's trim is DISPLAY-ONLY — `included` changes never write back
(onFinish just closes; no re-derive of memo transcript/audio/timings). Karaoke on captures likely
collateral (sidecar/rebase or the styled-quote render path skipping karaoke). Fix design: apply trim
at the two moments that matter — when "Record your thoughts" is tapped (await apply, THEN open the
recorder so the ramble lands on trimmed audio) and on finish/close; re-derive from included sentences:
audio = exportSpan(bufferAudioURL, firstWord.start→lastWord.end), transcript = C1 blockquote of joined
sentences, timings = rebased included words → memo + WordTimings sidecar + duration. Plus: memo player
and AudiobookSession must be mutually exclusive (each pauses the other on play).

#### Session log 2026-06-12 morning (superseded — the ⭐ CONTINUE HERE entry is at the BOTTOM of this file)
STATE: `native` is green + fully landed (audiobook player + Hybrid capture + sentence-trim persistence +
playback exclusion all device-installed on Skrift Dev). NOT pushed to main; prod untouched.

1. ✅ **BUILT 2026-06-12 (refactor, inline/sole-editor) — KARAOKE on capture memos. AWAITING DEVICE VERIFY.**
   Done per the 1b mandate: the whole capture render path unified into ONE component —
   `Features/MemoDetail/TranscriptBodyView.swift`, three explicit modes derived in one place
   (playing wins → reading while transcribing → editing default). PLAYING = classic full-text karaoke
   over the WHOLE memo via new `Memo.karaokeText` (quote with "> " markers STRIPPED + ramble, one
   continuous text, word indices 1:1 with the sidecar from 0); EDITING = styled quote + attribution
   above the quote-protected ramble editor (raw "> " write-back untouched, tests still green);
   READING (transcribing) = styled quote + pill, no editor (append-clobber protection kept).
   DELETED: TranscriptContentView + overrideText/baseWordOffset plumbing + CaptureQuote.spokenWordCount
   (~215 lines out of MemoDetailView). BONUS FIX: the old "working" karaoke counted the ">" markers as
   words → captures were silently off-by-N vs the timings; karaokeText fixes the alignment by design.
   3 dup imageURL(markerIndex:) helpers consolidated onto Memo. Gate: full sim suite green (33 UI +
   unit bundles, 0 failures); new tests pin karaokeText + mode precedence. Dev build installed on the
   iPhone. **USER: verify karaoke on a capture WITH a ramble present (and quote-only).**
1c. ✅ **KARAOKE DEVICE-VERIFIED 2026-06-12 ("it pretty much works")** — full-text quote+ramble highlight
   confirmed on device. Follow-up finding: "tap a word → jump" did nothing — NOT a bug: tap-to-seek was an
   opt-in Settings toggle (`karaokeTapToSeek`, default OFF) and the device prefs (pulled over USB) had it
   unset. USER CALL: **default flipped to ON** (commit 0808543; toggle kept for opting back to the crisp
   single-Text rendering).
1d. ✅ **Round 2 (same day) — tap-to-seek verified working; two presentation findings, BOTH FIXED:**
   (a) quote+ramble "all mixed together, no division" — root cause: the tap-to-seek FlowLayout flattens
   ALL whitespace, so the \n\n division the AttributedString path kept (their first, toggle-off test)
   collapsed once tap-to-seek became default. (b) layout jumped on play (styled quote swapped out).
   FIX (design-level, playing mode evolved): the capture KEEPS its styled quote frame during playback —
   `CaptureQuoteFrame` (accent bar + attribution, shared by all 3 modes) now wraps the LIVE karaoke quote
   text (italic, offset 0) with the ramble karaoke below (offset `spokenWordCount`, re-added) → no jump,
   unmistakable book-vs-own-words division, highlight still continuous. Plus `KaraokeWordLayout.lines`
   (pure + tested): the word grid stacks per-line FlowLayout blocks so paragraph breaks survive in ALL
   memos (multi-append rambles included). `Memo.karaokeText` deleted again (regions replaced it).
   ✅ DEVICE-VERIFIED same day ("very close, looks way better"). One P2 polish nit logged, NOT blocking
   (user: "pretty good", moved on): on play the text spreads slightly vertically — the tap-to-seek word
   grid's FlowLayout lineSpacing 6 + per-line VStack spacing 8 vs the static text's lineSpacing 4; tune
   the grid constants to match. USER MOVED ON TO THE BOARD → capture items build started 2026-06-12.
5. **CAPTURE ITEMS BUILT 2026-06-12 (board item 1) — two Sonnet lanes + orchestrator integration; AWAITING
   DEVICE VERIFY.** Contract-first: `Skrift_Native/CAPTURE_CONTRACT.md` (C3) pinned the wire seam (no audio
   part + sharedContent = capture; literal fixture both lanes test against). Lane M = SkriftShare extension
   target + App Group inbox + share sheet (mock state 1) + capture upload + list/detail (state 2). Lane D =
   UploadService capture branch + skip/enhance-lite pipeline + compile/export pinned block + review surface
   (state 3). Integration fixes (orchestrator): 3 one-line compile slips; QueueDerivations read snake_case
   only (phone sends camelCase); ADDED the mock's shared-content card to the review column (lane built it
   export-only); **launch crash fixed** — `SkriftAppGroup` Info.plist key was extension-only + CaptureInbox
   assertionFailure trapped Debug at launch (every UI test "app not running") → key added to the APP plist,
   fallback derives dev/prod group from the bundle ID instead of trapping. Gates: desktop UnitTests 223/0 +
   full build + `-snapshot-capture` mock-faithful; mobile full suite green (see commit). V1 flags: no mic in
   the sheet (memory ceiling), no location/weather on captures, tags/title Mac-suggested only. **USER:
   share a URL → annotate → rate → Save; check the row/detail; then sync to the dev Mac and check the
   review surface + export.** Known-untested: real share-sheet payloads from third-party apps (sim tests
   cover the inbox/upload logic, not the OS share UI).
2. Then user re-tests: trim persistence end-to-end (tap sentence → ramble → saved audio/text/karaoke match).
3. Owed smalls — **BUILT 2026-06-12 (this session, pending device verify):**
   - ✅ Reverse playback exclusion BUILT — `AudioPlayerModel.nowPlaying` (static weak) +
     one guarded `pause()` at the top of `AudiobookSession.play()`; cleared on pause/stop/finish.
   - ✅ Ready-screen flash BUILT — instant record now shows a quiet "Starting…" placeholder instead of
     the legacy ready screen (RecordView `showManualReady`); the mic-button screen survives ONLY as the
     empty-stop retry surface + a ~7 s fallback when the auto-start retry loop gives up.
   - Mini-player idle auto-hide (2 h `idleEndDelay`) + Siri "Resume my book" (`ResumeAudiobookIntent`):
     CONFIRMED SHIPPED in code — user test still owed.
   - ✅ Watch item (stale Live Activity on lock screen): user considers it fixed — CLOSED.
4. THE BOARD — **ORDER LOCKED BY USER 2026-06-12:**
   1) **Capture-items build** (mock signed off — share URL/text/image + annotate; mobile share-extension
      target + App Group + `attachments` multipart; desktop non-audio capture content type; folds in the
      unified source taxonomy + "share video from Photos doesn't list Skrift").
   2) **Custom vocabulary build** (spike done — CTC keyword-spot + rescore in both transcribers +
      Settings "Custom words" list; ~97.5 MB extra model).
   3) **Models tab in phone Settings** (user re-confirmed: "a tab that says models" — list the on-device
      models w/ downloaded state/size; spec already under "Show downloaded models in phone Settings";
      Mac mirror later).
   4) **Prod promotion LAST** — push native→main + Release builds both apps when prod idle.
   **Significance-wall design session: DEFERRED** (user call).
   Status audit done same session: swipe-to-delete ALREADY DONE (native `.swipeActions` in MemosListView
   — item 3.5 partially closed; nicer drag-multi-select still open); confirmed-bugs list all still open
   (names auto-sync after enroll, Mac name-a-speaker UI, photo marker drift, confidence colours). QoL
   user picks: record-a-sample voice enroll = yes (later); desktop unlink-popover "Change to →" = yes.
PROCESS (now in skill rules): single bugs = orchestrator edits directly; lanes ONLY for batches; Sonnet for
specced lanes / Opus for taste; verify lane CLAIMS against write-paths. Feedback loop: "pull my feedback"
(skill) + devlog.txt for anything hardware-ish.
1b. ✅ **DONE 2026-06-12 — the refactor mandate was executed as specified** (whole path read first, then
   unified into the 3-mode `TranscriptBodyView`; quote-protection intact; inline as sole editor; sim
   gate green; installed to device). See item 1 for the full shape. Device verification owed by user.

#### (superseded by the ⭐ block at the bottom) — session wrap 2026-06-12 evening
STATE: `native` green through `df4850b`. Everything below is committed, sim-gated green (mobile 336 unit +
33 UI; desktop 223 unit + full build), and the DEV builds are installed: phone = Skrift Dev with capture
items; Mac dev build in DerivedData (launch on request for the round-trip test). NOT pushed to main; prod
untouched. The C3 contract doc is `Skrift_Native/CAPTURE_CONTRACT.md`; capability map in FEATURES.md.

SHIPPED THIS SESSION:
- ✅ DEVICE-VERIFIED: karaoke refactor (3-mode `TranscriptBodyView`, full-text capture karaoke), tap-to-seek
  default ON, round-2 presentation (styled quote frame stays live during playback; paragraph-true word grid).
- 📲 INSTALLED, AWAITING USER TEST: reverse playback exclusion; instant-record "Starting…" placeholder
  (ready-flash gone); CAPTURE ITEMS both apps (share extension + App Group inbox + share sheet + capture
  upload + list/detail; desktop ingest/pipeline/compile/export + review surface, snapshot-verified).
- Process: lanes rules.md gained "prove your base" (user-approved); CLAUDE.md records the App-Group CLI
  signing limitation (Xcode one-time visit done for dev IDs; Release IDs owe one at prod promotion).

USER FEEDBACK 2026-06-12 evening: "coming in from Safari was a bit shit" → ✅ REPRODUCED IN SIM + FIXED
(commits 7f76a77 + 6b95070; full gate green). A Safari-driving XCUITest probe
(`ShareFlowProbeUITests`, opt-in via TEST_RUNNER_RUN_SHARE_PROBE=1, screenshots to
/tmp/skrift-share-shots) reproduced the whole flow and caught FOUR stacked share-sheet bugs:
(1) keyboard buried significance+Save with no dismiss (ignoresSafeArea(.bottom) ate the keyboard
safe area → .container + keyboard-Done + scrim-tap unfocuses first — Save was literally
unreachable while typing, captures got lost); (2) light-mode innards on the dark shell
(preferredColorScheme is a no-op in extension UIHostingControllers → overrideUserInterfaceStyle);
(3) annotation TextEditor greedily filled the sheet (cap maxHeight 110); (4) the host content-hugs
the remote view leaving an unpaintable gray sheet backdrop (preferredContentSize 10k + opaque
#0e0f16 canvas). Sim E2E now verified: share → annotate → rate (works with keyboard up) → Save →
app inbox drain → capture row → detail (Open ↗ / annotation / Will-sync). SIM GOTCHA learned:
the share-sheet host caches extension processes per boot — reboot the sim after reinstalling
or you'll screenshot the stale extension. The fixed dev build is INSTALLED on the iPhone
(build 2026-06-12 evening, incl. share-sheet fixes); prod untouched.

USER FEEDBACK round 2 ("no way to record a voice message from sharing in safari — only type")
→ ✅ BUILT same evening + INSTALLED on the phone. The mock's mic, deferred-transcription design
(the v1 "no mic" flag is CLOSED): extension only RECORDS (Parakeet can't fit its ~120 MB memory
ceiling) → audio rides the App Group inbox → the APP transcribes on drain with the same Parakeet
engine → appends to the annotation, audio discarded (kept + Error pill on failure, re-kicked every
drain). Sync holds captures until transcription lands; detail editor swapped out meanwhile (clobber
window). Sim-verified (recording state + voice-note chip screenshots; 7 new unit tests incl. sync
gate + crash recovery; full gate green). DEVICE TEST OWED: share → tap mic (first time: mic
permission prompt INSIDE the share sheet) → talk → Save → open Skrift Dev → watch the annotation
fill in; then rate + sync → Mac gets the full text. C3 contract untouched (uploads stay text-only).

NEXT-SESSION DEVICE TEST LIST (in rough order):
1. CAPTURE phone half: Safari → Share → "Skrift Dev" (first time: enable via the share sheet's More/Edit
   row) → annotate + rate → Save → OPEN Skrift Dev (inbox drains on launch/foreground) → capture row +
   detail (Open ↗, editable annotation, no player bar). Also try a TEXT selection share + a PHOTO share.
   ↳ 2026-06-12 evening: sim-verified incl. the UX fixes above; device re-test still owed (esp. the
   share-from-Photos / text-selection variants + the first-time enable row).
2. CAPTURE Mac half: launch the dev desktop app → phone syncs the rated capture → review surface (source
   strip + banner + SHARED CONTENT card + url prop row) → Export to the test vault → check the .md
   (frontmatter url:/source:, pinned block above the annotation).
   ↳ 2026-06-12 evening: the WHOLE Mac half verified headlessly (commit 7799848) — real POST of the C3
   fixture → dev server → store row contract-perfect → REAL Gemma enhance-lite (title+summary on the
   annotation, no copy-edit) → compile → export to the test vault. New DEBUG flag `-processfile <id>
   [-exportafter]` (RunFile) runs Process+Export headlessly on any stored file — reuse it for future
   round-trips. CAUGHT + FIXED two export bugs affecting ALL notes: (1) filenames kept Obsidian-forbidden
   chars (Gemma's "Title: Subtitle" colons); (2) frontmatter title:/summary: unquoted → ': ' in a Gemma
   title makes Obsidian reject the whole frontmatter — both now sanitised/quoted + tests. What's left for
   the user here = just the visual review-surface check on a phone-synced capture. NOTE: a probe capture
   (Stoicism - Wikipedia, from the sim run) lives in the DEV store + an exported probe .md in the test
   vault — delete on sight if they get in the way. The dev desktop GUI app is currently QUIT.
3. Trim persistence end-to-end (OWED since the morning): capture sheet → tap a sentence in/out → ramble →
   saved audio/text/karaoke all match the trimmed span.
4. Reverse exclusion: play a memo in detail → start the audiobook → the memo must pause.
5. Instant record: no legacy ready-screen flash — brief "Starting…" then the live caption.
6. Mini-player 2 h idle auto-hide + Siri "Resume my book in Skrift" (shipped 2026-06-11, never tested).
7. Karaoke playback spacing nit (P2): confirm the slight vertical spread during playback is acceptable,
   or ask for the word-grid constant tune (FlowLayout lineSpacing 6 / VStack 8 vs static lineSpacing 4).

THE BOARD (user-locked order):
1. ✅ Capture items — BUILT, verify above.
2. CUSTOM VOCABULARY build (spike done 2026-06-11): CTC keyword-spot + rescore in BOTH transcribers +
   Settings "Custom words" list; one extra ~97.5 MB HF model. Integration pattern documented in the
   "Feature decisions — LOCKED 2026-06-10" §3 entry above.
3. MODELS TAB in phone Settings (list on-device models w/ state/size; spec under "Show downloaded models
   in phone Settings"; Mac mirror later).
4. PROD PROMOTION LAST: push native→main + Release builds both apps while prod idle. NOTE: Release bundle
   IDs need the one-time Xcode App-Group signing visit (same two clicks as dev, recorded in CLAUDE.md).
Significance-wall design session: DEFERRED (user call 2026-06-12).

OUTSTANDING (later, off the board):
- Confirmed bugs: names DON'T auto-sync after voice enroll (manual sync only); Mac "name a speaker" review
  UI (backend done, mock `name-a-speaker.html` awaits sign-off) + live enroll→auto-label round-trip;
  photo `[[img_NNN]]` marker drift (anchor by TIME not word count); confidence colours wrong in practice.
- Capture-items v1 flags (deliberate, flip on demand): no mic dictation in the sheet (extension memory
  ceiling); no location/weather on captures; "file" share type has no pinned block; UI-test capture
  seeding skipped (unit tests cover the logic); real third-party share payloads untested.
- QoL: drag-multi-select on the memos list (swipe-delete done); record-a-sample voice enroll in Names &
  voices; desktop unlink popover "Change to → <person>"; karaoke playback-grid spacing tune (P2).
- ✅ Audit nits — RECONCILED 2026-06-13 (verified each against CURRENT code + live on the fixture; the
  "open" citations were stale, written mid-desktop-track and never reconciled after the fixes landed):
  desktop sidecar try? writes (logged), 256 MB cap + early 413 (done), main.sync bridge (marshaled to
  main + NOW guarded by `dispatchPrecondition(.notOnQueue(.main))`), model idle-unload (real `unload()`
  fires 60 s idle — proven: idle `/health` returns available:false), real word_timings→karaoke (done,
  `BatchRunner:40`; runfile logs `word_timings: 90` on the two-Jacks fixture), `/health` truthful
  (`isModelReadySync`, not hardcoded), parity golden tests (`UnlinkTests`/`CompilerTests` cover it),
  HEIC→JPG (ImageIO now, fallback recomputes the md ref — old `sips` nit gone), snapshot try? (now
  logs write FAILED). Mobile — recorder deinit (belt-and-braces inline), silent-video import (titles
  "Video had no audio track"), photo-marker drift + confidence colours (fixed this wave). Commit dd…
  (`harden(desktop)`). NOTHING in this list is still open.
- With-user sessions: re-ingest ~30 old notes (`~/Desktop/Skrift old notes/`, prod quit, real vault);
  "transcription a bit weird" cold-start (parked unless seen again).

#### Session 2026-06-13 — desktop architecture A-list verified-done + Trash mirror built
- Verified the desktop "A-list" against CURRENT code + live (the backlog/CLAUDE citations were stale):
  model-unload, real word_timings→karaoke, 256MB cap+413, main-actor SwiftData marshal, truthful /health
  — ALL already done. Hardened the two genuine remainders: SwiftData-bridge invariant now enforced
  (`dispatchPrecondition(.notOnQueue(.main))`), snapshot write no longer claims success on failure
  (commit `2ac3d32`). Audit-nits section reconciled (`4a6a982`).
- ✅ **Desktop Trash / Recently Deleted** built (commit after `4a6a982`) — see board item 4 above.
- STILL genuinely open (features needing a pick/mock/user, NOT bugs): Mac "name a speaker" UI (mock
  awaits sign-off), drag-multi-select (mock first), watched-folder ingest, Backlink Weaver, unified
  source taxonomy, record-a-sample voice enroll (device voice), re-ingest 30 notes (with user), prod
  promotion (device tests + Release App-Group Xcode visit). Significance-wall = user-deferred.
- Deferred ideas: watched-folder ingest; summary prompt quality pass; tag lemma expansion; north-star
  semantic timeline ("how my thinking evolved").

#### CONTINUE HERE (SUPERSEDED — see the ⭐ block at the BOTTOM of this file, 2026-06-13 night) — session wrap 2026-06-12 night (the "do all outstanding" batch)
STATE: `native` green; every gate passed per commit (mobile 352 unit + 38 UI; desktop 231 unit + full
build). NOT pushed to main; prod untouched. PHONE: has capture items + share-sheet UX fixes + DICTATION
(installed earlier tonight); the LAST build (vocab + models tab + bug fixes + QoL) is STAGED in
`build-device/` — phone went unavailable before install. Install when plugged in + unlocked:
`xcrun devicectl device install app --device 00008110-001208C902EA201E Skrift_Native/SkriftMobile/build-device/Build/Products/Debug-iphoneos/SkriftMobile.app`

SHIPPED THIS SESSION (all sim/headless-verified, commits in order):
- Share-sheet UX pass (7f76a77+6b95070): keyboard buried Save (captures losable!) / light-on-dark mix /
  giant TextEditor / gray host backdrop — all fixed; Safari+Photos probes (opt-in) screenshot the flow E2E.
- Mac capture half verified LIVE (7799848): C3 fixture POST → store → real Gemma enhance-lite → export.
  New DEBUG flag `-processfile <id> [-exportafter]`. CAUGHT: Obsidian-forbidden filename chars + unquoted
  YAML title/summary (Gemma colons break Obsidian frontmatter) — both fixed, all exports affected.
- VOICE DICTATION in the share sheet (user ask): extension records (no model in-process), app transcribes
  on drain → annotation; sync holds till done; crash/failure recovery; ON THE PHONE already.
- CUSTOM VOCABULARY (board 2): CTC spot+rescore in BOTH transcribers + Settings editors both apps +
  word-timings re-alignment; `-runfile -vocab "A,B"`; LIVE-verified (planted "Jacques" replaced, real
  Jacks untouched). Dev Mac settings carry ["Skrift"]. Lists are per-device v1 (no sync — possible later).
- MODELS TAB (board 3): Settings → Library → Models (3 models, downloaded state + sizes). Mac mirror later.
- CONFIRMED BUGS fixed: names AUTO-SYNC after voice enroll (debounced push, no-op unpaired); photo-marker
  drift (marks anchored to the words they followed); caption colours now TRUTHFUL (solid = rotated
  committed chunks — a real finalized signal; volatile = live chunk; expect a LARGER lighter tail
  on device, up to ~25s — that's honest, not a regression).
- QoL: desktop unlink popover "CHANGE THIS MENTION TO →" (two-Jacks one-tap fix, Sanitiser.relinkOccurrence);
  karaoke grid spacing matches static text; silent-video failures self-titled. Git housekeeping done
  (haslett worktree + robustness-cleanup local branch removed — both targeted archived apps only).

DEVICE-TEST LIST (新, on top of the morning list):
1. Share from Safari with the NEW sheet: type + tap circles + Save WITH the keyboard up; dictate a
   voice note (first time = mic permission inside the sheet) → open Skrift Dev → annotation fills in.
2. Custom words: Settings → Capture → Custom words → add "Skrift" → record a memo saying it.
3. Models tab shows real sizes once models are on the phone.
4. Voice-enroll someone → names should reach the Mac WITHOUT a manual sync tap (~3s).
5. Live caption: solid text never changes now; lighter tail is longer than before (honest).
6. Desktop: click a [[Name]] → "Change this mention to →" the other Jack.

NOT DONE, with reasons:
- Significance wall / printer pipeline — user said skip.
- PROD PROMOTION — blocked on the device tests above + the one-time Xcode App-Group signing visit for
  the Release bundle IDs (CLAUDE.md records the steps).
- Mac "name a speaker" review UI — mock `name-a-speaker.html` still awaits sign-off (locked process).
- Drag-to-multi-select on the memos list — interaction design wants a mock first (locked UI process).
- Record-a-sample voice enroll in Names & voices — conversation-track; needs real-voice device
  validation; do with the next conversation-mode session.
- Desktop trash mirror, source-taxonomy unification pass, desktop A-list perf nits (multipart RAM cap,
  main.sync bridge, desktop real-timings karaoke, parity golden tests) — pre-existing backlog, untouched.
- Re-ingest ~30 old notes + "transcription a bit weird" — with-user sessions.

#### Text-first audiobook capture — DESIGNED + WAVE 1 BUILT 2026-06-13 (installed on the phone)
Trigger: real (non-builder) testers couldn't use the shipped Hybrid audio-marking capture
(didn't get in/out marks, too many buttons, didn't know sentences were tappable). Designed a
**text-first** alternative WITH the user + 2 verification agents (code-reality + locked-decisions)
+ 2 UX critics (caught the warming-screen purple-button misfire — "brightest element must be the
one intended action"). Full design + all decisions/nuances: `SkriftDesktop/mocks/text-capture-DESIGN.md`;
signed-off interactive mock: `mocks/text-capture.html`.

**LOCKED design points:** ships ALONGSIDE audio mode (A/B, Settings → Audiobooks Audio·Text toggle,
default Audio), surgically removable; the isolation seam is the `QuoteCaptureOutput` (Text mode emits
a GLOBAL span → SAME processor/sheet/save/sync/export). Tap-+-to-add / ✕-to-drop sentence select;
last line pre-picked; scroll (no button); "Hear selection" plays the span at 1.5×; warming screen is
just a wait (whole-book offer is a bottom link, NOT a button); no-speech = tiny "back to book"; no
false "place saved" reassurance. 35 s = one-time engine WARM-UP (not inference; ~1 s warm/screen).
Chunking = the path; **resumability locked** (chunk sidecar IS the resume state; discard the in-flight
half-chunk; pause-on-unplug/auto-resume). Whole-book transcribe = best overnight/plugged; ≈X-min/hr
estimate is a PLACEHOLDER pending real phone measurement.

**WAVE 1 BUILT (commit + installed):** the toggle, `TextCaptureView` (sentence-select),
`QuoteCaptureProcessor.transcribeWindowForDisplay`, the router in `QuoteCaptureFlowView` (both modes →
`confirmCapture(_:span:)`). 343 unit (+7 TextCaptureTests) + 38 UI green. Real transcription is
device-owed (no audiobook UI harness in the sim).
**OWED — DEVICE TEST (put it in front of the same testers):** flip Settings → Audiobooks → Text;
in a book, hit Capture → sentence-select; the two things to watch — (1) does +/✕ read as tappable
WITHOUT being told? (2) does the pre-pick + sandwich make EXTENDING feel natural, or do they just
confirm one line? If +/✕ still isn't instant, next lever = a one-time coachmark.
**WAVE 2 — BUILDING 2026-06-13 (user greenlit):** `BookTranscript` sidecar + chunker + resumable
overnight transcribe job + the transcribe-book button + instant-capture-from-sidecar + pre-warm-on-
book-open. Measure the real per-hour transcribe speed on the phone to replace the placeholder.
Multi-file/chapter-boundary confinement is already code-enforced (`QuoteCaptureProcessor:69-76`) — kept.
- ✅ Sidecar (`BookTranscript`/`FileTranscript` + `BookTranscriptStore`, per-file JSON, atomic write,
  `size:mtime` staleness, file-local word-timings; sentences derived on read via `buildSentences`).
- ✅ Chunk-seam fusion (`ChunkFusion`): cut at the last complete sentence, re-transcribe the tail next
  chunk — no split/dup words, uses `SentenceSnap`; run-on/silence fallbacks. Unit-tested.
- ✅ Resumable job (`BookTranscriptionJob`): sequential per-file chunk loop, save-after-complete =
  resume state (in-flight chunk discarded on interruption), pause-on-unplug + auto-resume on charge,
  foreground Pause/Resume, yields to live capture between chunks. Engine path device-owed.
- ✅ ⋯ "Transcribe book" button + sheet (`TranscribeBookView`, Text mode only): progress + %, Start/
  Pause/Resume, design §12/§13 copy. Instant-capture-from-sidecar (`TextCaptureView` Source +
  `buildOutputFromSidecar`; un-chunked → wave-1 fallback). Pre-warm on book-open in Text mode when the
  spot is un-chunked; live capture pauses the bg job.
- ✅ Real per-device speed: the job measures its own RTF (persisted) → the sheet shows a measured
  "≈ N min" estimate (placeholder removed). Mac `-asrbench` = ~100–134× realtime (inference tiny vs
  audio); the phone's absolute number is device-measured (job DevLogs per-chunk timing).
- **DEVICE-OWED:** real ASR on the phone (sim has no ANE) — run "Transcribe book" on a real book,
  watch the progress + the measured min/hr in the devlog, then capture at a done spot (instant, no
  warming screen) and at an un-done spot (wave-1 fallback); verify pause-on-unplug/auto-resume + that
  an interrupted job resumes from the last saved chunk.

#### Player redesign DEVICE TEST 2026-06-13 (night) — 2 fixes
- ✅ **Transcribe sheet showed "Resume transcribing" at 100% done** (device screenshot). Cause: the
  job clears `activeBookID` on finish → `isThisBook` flips false → the `.finished` control case was
  skipped → fell to the "Resume" default. Fixed: TranscribeBookView gates the done-state on
  **progress ≥ 0.999** (lede "Done…", a "Fully transcribed" indicator instead of a button, estimate
  hidden) — robust for both just-finished and a re-opened already-done book.
- ✅ **Read-along "text smaller & jumps fast" → Spotify lyrics** (device feedback). Reworked
  `ReadAlongView` from one re-coloring/reloading paragraph to discrete **lyric LINES**: current line
  large + bright (21 pt), neighbours dim by distance, **smooth auto-scroll** (centered, animated),
  soft edge fade, tap-a-line-to-seek. Loads the WHOLE covered prefix once (reloads only on coverage-
  frontier cross / file change) so scrolling is smooth, not jumpy. Device-owed re-look.
- ✅✅ **ROOT CAUSE of read-along trailing — chunker time-DRIFT (2026-06-13, proven on Mac).** Built a
  headless harness (`-readalongcheck`, `-chunksim` + `anchorDrift`, desktop `RunFile`): pulled the
  real book audio + sidecars off the phone, transcribed each chapter WHOLE on the Mac as ground truth,
  aligned on words unique-in-both. f0 (2 chunks) was clean (±0.08 s); **f2 "Beginning" (14 chunks)
  drifted monotonically late: thirds +0.40/+0.81/+1.99 s** — so no fixed lead could fix it. `-chunksim`
  reproduced + isolated the cause: **per-chunk `AVAssetExportSession` extraction from the compressed
  MP3 isn't time-accurate (error grows with seek position): thirds −0.24/+0.38/+0.96; sample-accurate
  `AVAudioFile` PCM frame reads = −0.02/−0.02/−0.01 (flat).** FIX (mobile): `BookTranscriptionJob`
  now extracts chunks via `extractPCM` (AVAudioFile → temp WAV), NOT exportSpan. `FileTranscript`
  schema 1→2 so the already-drifted sidecars re-transcribe. Quote-audio carving keeps exportSpan (a
  few-ms shift there is inaudible). Device re-test: re-transcribe "Do the Work", read-along should now
  ride the voice the whole chapter.
- ✅ **Read-along "text lags behind voice"** (device feedback) — also addressed the latency layer. The
  AVPlayer playhead (`session.currentTime`) only ticks every 0.5 s, so the lit line was quantized to
  half-second steps and always trailed. Fixed: `ReadAlongView` now INTERPOLATES the playhead between
  ticks (anchor + wall-elapsed × `session.rate`) on a 0.1 s timer, plus a small `lead` (0.2 s) for
  Parakeet-TDT's slightly-late word timings, and a snappier highlight (0.18 s). Lit line now tracks
  the narrator. `lead` is tunable if it reads early/late on device.

#### Wave-2 DEVICE TEST 2026-06-13 (evening) — vocab + transcribe-book
- ✅ **Custom vocab WORKS on device now** (user: "customs words are working"). Pre-warm-at-launch was
  the fix, confirmed.
- ✅ Transcribe-book runs: progress moves, measured estimate shows ("~11-12 min left"), pause-on-
  unplug → "plug in to continue" → auto-resume on charge all confirmed ("very cool"). Resume after
  force-quit PRESERVES progress (11% survived) — the sidecar resume state works.
- ✅ FIXED two device-found bugs (commit): (1) the transcribe sheet showed **0% on reopen** until
  Start (saved % wasn't displayed — data was fine); now `reflectSavedProgress` seeds the bar/label/
  estimate from the sidecar on open. (2) **Start while already charging showed "paused, plug in"** —
  `isPluggedIn` was read before battery monitoring was enabled (→ `.unknown` → false unplugged);
  monitoring now enabled in `init` + before the read in `start`.
- ✅ **UX — library long-press to transcribe (BUILT 2026-06-13):** `AudiobookLibraryView` rows got a
  `.contextMenu` — "Transcribe book" (Text mode) presents `TranscribeBookView` for that book without
  opening it; + Delete. No need to open book → ⋯.
- ✅ **UX — Control Center / record-widget icon (BUILT 2026-06-13):** the literal app icon CAN'T be a
  Control Center glyph (it's a detailed 3-D render; Control Center renders simple MONOCHROME templates
  → its silhouette is an indistinct blob). Control Center control kept as `mic.fill` (clear record
  glyph, already labelled "Skrift"). Real fix applied: the Home/Lock **record widget** was a generic
  RED mic-dot while the in-app record button is `skAccent` purple — rebranded the widget to the Skrift
  accent (`RecordWidget.accent` = 0x7c6bf5) so it reads as Skrift. A custom monochrome Skrift logomark
  for Control Center is a later option (needs simple mark artwork, not the 3-D icon).
- ✅ **Audiobook player UI redesign — DESIGN SIGNED OFF 2026-06-13** (grill-me). Spec mock:
  `Skrift_Native/SkriftDesktop/mocks/audiobook-player-redesign.html`. Direction = **text-forward
  A+D hybrid**: warm cover-derived tint header; cover demoted to a 56px chip; **live read-along text
  is the hero**, current line lit (reuse `Karaoke.activeWordIndex` on the sidecar word-timings); `Ch
  N/M` pill; speed◁ transport ▷sleep; slim **Chapters + Bookmark** icon row above a hero **Capture
  this** pill. Un-transcribed spot → **"Transcribe this book to read along →" nudge** (routes to
  `TranscribeBookView` — the player sells the transcribe feature). No read-along on/off toggle (v1).
  Resolved via grill: feature set = bookmarks + surfaced chapters (NOT AirPlay — Control Center
  covers it; NOT skip-silence/EQ). **Bookmark = NET-NEW, lightweight:** tap drops a marker (global
  position + chapter + timestamp), haptic + toast; list in the Chapters sheet under a Bookmarks tab
  (jump / swipe-delete); Capture stays the rich save. Mock-first step done.
  - ✅ **BUILT 2026-06-13** (autonomous): `Bookmark.swift` (model + `BookmarkStore`, per-book JSON,
    near-dupe guard, 6 unit tests); `ChaptersBookmarksSheet.swift` (Chapters | Bookmarks tabs);
    `ReadAlongView.swift` (sidecar-fed read-along, current line lit via cached window + per-tick
    recompute; nudge when un-chunked → TranscribeBookView); `AudiobookPlayerView` rewritten to the
    text-forward layout (cover-tint header from `UIImage.averageColor`, 56px cover chip, Ch N/M pill,
    speed◁/sleep▷ flanking transport, slim Chapters+Bookmark row, hero "Capture this"). Chapters
    removed from the ⋯ menu (now the sheet + slim row). App builds, bookmark unit tests green.
  - **DEVICE-OWED:** visual check (no headless iOS screenshot) + the read-along is only real on a
    transcribed book (sim has no ANE → shows the nudge). Verify: cover-tint band, read-along lit line
    tracking playback on a transcribed book, nudge on an un-transcribed one, bookmark drop+toast,
    Chapters/Bookmarks sheet jump + swipe-delete.
  - **GATES:** app builds (sim + device) ✓; **396 unit tests green** (incl. 6 bookmark); device build
    ✓ + INSTALLED. UI suite (re-run at low load): 36/38 ran-and-passed; the 2 failures
    (`testEnrolledPersonAutoLabeledOnSplit`, `testSplitSpeakersButtonSplitsIntoTurns` — both
    speaker-diarization, UNRELATED to the player/library/widget changes) fail on the fresh-erased-sim
    permission-dialog + onboarding wall (`allow-media`/`allow-location`/`get-started-button`), not an
    assertion — they passed earlier this session on a stateful sim (412-green). No UI tests exercise
    the changed audiobook player/library/widget surfaces. (Earlier mass UI failures were the host at
    load ~80 SIGTERM-ing the runner; resolved once load dropped.)
- Note: charging-state can lag a second after plugging in mid-run (iOS `batteryStateDidChange`
  latency); self-corrects. Acceptable.

#### Text-capture round 2 device feedback 2026-06-13 (evening)
PASSED: text-capture double-select GONE ("I can record my thoughts. Nice."); +/✕ & extend confirmed.
SHIPPED + installed: share-sheet PROMINENT record button (was a missed tiny mic — "why doesn't it
just have a button to record like the rest of the app"); ShareSheetView reworked (record primary,
type secondary). Vocab booster INSTRUMENTED with DevLog (spot/rescore outcome + replacements).
CONFIRMED BUG — custom vocab does NOT correct "Script"→"Skrift" with the model loaded. Next:
user records one more Skrift memo → pull devlog.txt → the `vocab:` line says whether the SPOTTER
missed it (phonetic limit) or the RESCORER declined (loosen minSimilarity/cbw). Don't blind-tune.
OPEN: (a) old stuck-"Transcribing" memos from the pre-fix build — delete, or add a launch
reconciler that re-transcribes stuck .transcribing memos (offered). (b) "sentence breaks up
strangely" in text capture — awaiting the capture-screen screenshot; likely Parakeet punctuation
(abbreviations like "Dr.") splitting sentences in SentenceSnap.isSentenceEnd.

#### ✅ CUSTOM VOCAB — VERDICT + FIX (2026-06-13, both apps)
**Devlog verdict = NEITHER spotter nor rescorer; the booster was never READY.** The fresh
`vocab:` lines (14:26:58) read `not ready (loaded=[], rescorer=false) → bg prepare, unboosted` —
no `wasModified` line ever appeared, so the boost never reached spot/rescore. Root cause: the
booster's spotter/rescorer are per-PROCESS in-memory state that resets every launch, and the
non-blocking design (the queue-jam fix) makes the FIRST transcribe skip while the ~97 MB ctc110m
loads in the background. The user records ~one memo per launch → it always raced the load → always
unboosted. "Model downloaded" (Models tab = on-disk) ≠ "booster warm" (in-memory, per-session).
**Mac ground truth** (`-runfile -vocab` with a synchronous prewarm + booster stderr diagnostic;
no phone audio needed): once warm, the spotter detects + the rescorer replaces — proven
(`Jacques: jack` alias surfaced `Jacques` at sim 0.43, below the 0.50 floor, and replaced).
script→Skrift is an EASIER case (sim 0.667, candidate already surfaces; the audio genuinely says
"skrift" so the acoustic gate favours it).
**FIX (committed, both apps):** (1) **pre-warm** the booster at launch when custom words exist →
the confirmed bug; (2) **aliases** via `"Canonical: alias1, alias2"` → user-controllable widening
for stubborn mis-hearings; (3) **trust guard** → FluidAudio's spotter-anchored rescue mangles
ordinary speech once warm (negative-control clip turned `room→Rox`, `its alias.→Tiuri`); the
booster now drops a boost when EVERY replacement is a distant acoustic-only guess (sim < 0.55 AND
no alias) → negative control verified CLEAN. cbw tuning was a DEAD END (even cbw=2.0 kept the FPs —
the original words' constrained-CTC scores are too low). cbw stays at FluidAudio's 4.5.
**DEVICE RE-TEST (owed — phone was unavailable this session):** with the new build, in Skrift Dev
say "Skrift" once → it should now correct (booster warm at launch). If a SHORT/uncommon word
(≤3-4 char, e.g. "Rox") still mis-fires on unrelated speech, drop it or add it with an explicit
alias; report and we tighten further. Note: very short words are inherently spotter-FP-prone.

#### ⭐ CONTINUE HERE — session wrap 2026-06-13 night
STATE: branch `native`, all committed, **`main` untouched / not pushed, prod untouched**. Mobile dev
build ("Skrift Dev", `com.skrift.mobile.dev`) **installed on the iPhone 13** (devicectl UUID
`A9195A77-601A-54C1-B3BD-659FBFE1DC54`). Desktop dev build in `build/` (vocab fix + read-along sync
harness). Gates per chunk: mobile 396 unit green (the 2 UI fails are the documented permission/
testmanagerd sim flake on unrelated speaker tests — pass on a stateful sim); desktop 248 unit + full
`-skipMacroValidation` build.

✅ SHIPPED + DEVICE-CONFIRMED:
- **Custom vocab fix** (both apps) — pre-warm booster at launch + aliases (`"Canonical: alias"`) +
  trust guard (drop distant spotter-rescue FPs, sim<0.55). **User confirmed working** ("customs words
  are working"). Root cause was readiness (per-process booster never warm), not spotter/rescorer.
  See the `✅ CUSTOM VOCAB` block above + [[project_vocab_booster]].

✅ SHIPPED (mobile, on the phone; real-ASR / read-along behaviour is device-owed to eyeball):
- **Text-capture WAVE 2** — `BookTranscript` sidecar (per-file JSON, file-local times) + `ChunkFusion`
  (cut-at-sentence, redo-tail) + `BookTranscriptionJob` (resumable charger job: save-after-complete,
  pause-on-unplug/auto-resume, yields to capture) + ⋯/long-press "Transcribe book" sheet + instant
  capture from the sidecar (else wave-1 fallback) + measured per-device speed (no placeholder).
- **Audiobook player redesign — text-forward A+D hybrid** (signed-off mock
  `Skrift_Native/SkriftDesktop/mocks/audiobook-player-redesign.html`): warm cover-tint header, 56px
  cover chip, `Ch N/M` pill, **Spotify-style read-along** (current line lit, smooth auto-scroll, edge
  fade, tap-line-to-seek), speed/sleep flanking transport, slim **Chapters + Bookmark** row, hero
  "Capture this". **Bookmarks** (light position markers) + **Chapters/Bookmarks TOC sheet**.
- **Library long-press → Transcribe book**; **record widget** rebranded red→Skrift purple.
- **Read-along sync — fully chased down + fixed (Mac harness, real data):**
  1. timings drift — per-chunk `AVAssetExportSession` on compressed MP3 drifts late, growing to
     ~+2s deep in a chapter (proven via `-chunksim`); fixed with sample-accurate `AVAudioFile`
     extraction (`extractPCM`), sidecar schema 1→2 to force re-transcribe of drifted transcripts.
  2. latency — interpolate the playhead between the 0.5s AVPlayer ticks + advance at line-END.
  3. stuck-nudge — the player now re-checks coverage every ~1.5s even paused, so a finishing
     transcribe flips nudge→read-along live (devlog proved the data was fine; it was stale UI state).
  4. smoothness + lead (device feedback "too early" + "words hustle"): lead 0.3→0.1; lines are now a
     UNIFORM 18 pt (font-size change can't animate → reflowed/shoved neighbours = the hustle), the
     current line emphasised by a smooth `scaleEffect(1.08, anchor:.leading)` (transform, no reflow) +
     brightness. Device re-eyeball owed.
  Desktop harness (`-readalongcheck`, `-chunksim`, `anchorDrift`) committed for reuse.

⏳ STILL OPEN / DEVICE-OWED (next session):
1. **Read-along final eyeball** — drift/latency/stuck-nudge/smoothness/lead all fixed + installed;
   confirm on a re-transcribed book it tracks the whole chapter, smoothly (no hustle), in-sync (not
   early). `ReadAlongView.lead` is the dial (now 0.1s) if still slightly off.
2. **Vocab — RESOLVED on device:** user confirms **both "Rox" and "Skrift" work** as custom words.
   The short-word-FP worry didn't materialise; keep as a watch-only note, no action.
3. **Control Center glyph — ✅ RESOLVED 2026-06-13: user chose A (`quote.opening` ❝).** Swapped
   `mic.fill`→`quote.opening` in BOTH `SkriftWidget/RecordControlWidget.swift` (the CC tile) and
   `SkriftWidget/RecordWidget.swift` (the Lock/Home widget — all four families: circular / inline /
   rectangular / systemSmall) for one consistent Skrift-forward mark. Sim build+test gate green
   (38 UI tests, 0 failures) + device build+install kicked off. The ONE thing no gate can prove for a glyph (SF Symbol names are plain
   strings — a typo renders blank, never a compile error) is that it draws ❝ → quick device eyeball
   owed. Options B (`pencil.line`) and C (custom carved-strokes template asset) not taken.
4. **Wave-2 deferred** (design doc §9): cross-chapter quotes; auto-transcribe-ahead while playing;
   **A/B test integrity** for text vs audio capture (assign the arm, pre-transcribe the test book,
   define the success metric); desktop mirror of wave-2 (mobile-only today).
5. **Bookmarks**: viewing the list is via Chapters sheet → Bookmarks tab (the Bookmark button only
   drops). Consider a more direct path if it feels hidden.
6. Pre-existing untouched: **prod promotion** (one-time Xcode App-Group signing for the Release bundle
   IDs, then Release build + `native`→`main`); Mac "name a speaker" mock sign-off; drag-multi-select
   mock; record-a-sample voice enroll (conversation track); desktop A-list perf nits (multipart RAM
   cap, off-main SwiftData on the Bonjour queue, real word_timings→karaoke, parity golden tests);
   re-ingest ~30 old notes; "transcription a bit weird" investigation.

#### ⭐ CONTINUE HERE — capture redesign + full-screen player (2026-06-13, DONE — installed, eyeball owed)
User signed off the **merged note-style capture screen + full-screen player** (mock
`mocks/audiobook-capture-merged.html`). **Text capture is now the only flow — the audio mark-in/out arm is
retired.** Built in 3 gated chunks on `native` (all committed + sim-green + on the dev phone):
1. ✅ **Player fills** — `ReadAlongView` flexible-height (geo-relative head/tail spacers, was a fixed 234 pt
   panel) + `AudiobookPlayerView` controls pinned at the bottom (dropped the dead `Spacer`). Sim green
   (38 UI + units, TEST SUCCEEDED). Committed.
2. ✅ **Merged capture** — `MergedCaptureView.swift` (NEW): one note-style screen = header (❝ + book·ch) →
   the real `SignificanceCircles` card → build-your-quote sentence rows (reuses `TextCaptureSelection`) →
   Record-your-thoughts pinned. On record: build quote from the selection → `saveQuoteCapture` → apply
   significance → `RecordView(appendTo:)` → recorder dismiss auto-resumes the book + lands as the normal
   note (NO preview; the ramble append is fire-and-forget so it's safe). Routed via a rewritten
   `QuoteCaptureFlowView` (all capture → merged). A bail before recording discards the quote-only memo
   (always-records). Sim green (TEST SUCCEEDED), committed. Old views still present-but-dead (deleted in 3).
3. ✅ **Retire audio arm** — deleted `CaptureMomentView` / old `CaptureSheetView` / `TextCaptureView`
   (pure `TextCaptureSelection`+`TextCaptureMath` relocated to `Models/TextCaptureSelection.swift`) /
   `AudiobookCaptureStyle` + its Settings toggle / `CapturePausedRow` / the now-orphaned `GrainPlayer` +
   `SpanWaveform`. Kept `CaptureMath` (`QuoteCaptureProcessor` still uses it). Ungated the `.text` checks
   (Transcribe-book always in player ⋯ + library long-press; `prewarmIfUseful` always). Dropped
   `testCaptureStyleDefaultsToAudio`. Sim gate green (TEST SUCCEEDED), committed.

ALL 3 CHUNKS DONE + sim-green + **DEVICE-INSTALLED** on the iPhone 13 (`com.skrift.mobile.dev`, devicectl
UUID `A9195A77-601A-54C1-B3BD-659FBFE1DC54`). `main` untouched / un-pushed. Commits: glyph `806645b`,
player-fills `605efec`, merged-capture `24d6e85`, retire-audio `6a08df7`.
DECISIONS (locked w/ user): always records voice (no quote-only save, may revisit); auto-resume + no
preview; significance on top mirrors the note (verified: note order is title→chips→significance→body).
⏳ OWED (device-only — sim has no ASR): eyeball the **❝ glyph** (CC + Lock/Home widget), the **full-screen
player**, **read-along sync** (`ReadAlongView.lead` 0.1 s is the dial), and the **merged capture E2E**
(Capture → significance + build-quote → Record your thoughts → auto-resume into note). Re-transcribe a
book first (schema-2 sidecar). If read-along reads early/late, say which → tune `lead` (+ desktop
`-readalongcheck` to separate data-drift from offset).

✅ BUILT 2026-06-14 — **bidirectional + bounded build-your-quote** (`MergedCaptureView`). Took two
corrections to land the shape: (1) first attempt went BACKWARD-only (an "Earlier ↑" control) — the user
meant scroll DOWN / select AFTER the tap ("i cannot scroll down. only allows selection from before capture
point"); (2) the fix then over-shot to load the whole file = INFINITE scroll — user: "8 is plenty". FINAL:
the tapped line is the pre-picked anchor in the MIDDLE; the displayed slice = the ~90 s heard BEFORE it +
up to **8** lines AFTER (transcribed) / **4** (un-chunked) — scroll up earlier, down a little later, NO
infinite. Transcribed → sidecar (`fileTranscript().words`, file-local); un-chunked → transcribe ≈90 s back
… ≈45 s forward. `sel` indexes the full array; only the bounded slice (`displayLo…displayHi`) renders;
auto-scrolls to the tapped line. Compile + unit gate green; device-eyeball owed.

#### Audit 2026-06-14 — P1 bugs + build-ready features verified against code (read-only agent)
Most of the old P1 list is ALREADY FIXED (code + a doc comment naming the original bug); device re-verify only:
- ✅ Desktop summary editable (`NoteDisplayView.swift:394`); ✅ name-link first-mention-only
  (`Sanitiser.swift:81-111`, handles per-turn `**[[Person]]:**`); ✅ desktop Photos-drag ingest
  (`SidebarView.swift:495-615` FilePromiseDropCatcher); ✅ confidence colours use the real committed-word
  boundary (`RecordView.swift:227` + `TranscriptionService.liveCommittedWordCount`); ✅ video thumbnail BOTH
  apps (mobile `MemoSaver.swift:162`, desktop `IngestService.writeVideoThumbnail` — the "desktop has none"
  note was stale); ✅ Spotify-stops-on-open + paste-scroll-to-top both fixed.
- ✅ **FIXED 2026-06-14 — share-a-video from Photos.** Added `NSExtensionActivationSupportsMovieWithMaxCount`
  (`project.yml` → regenerated `SkriftShare/Info.plist`) so Skrift appears in the Photos share sheet for
  videos; `SharePayloadLoader.loadVideo` copies the movie to the App Group inbox as a `"video"` entry
  (raw-string type — NO `ShareContentType`/contract change; extension copies the file, never loads it into
  its memory ceiling) and bypasses the capture sheet (`ShareViewController.completeVideo`); `CaptureInboxDrainer`
  imports it via `MemoSaver.importVideo` → a normal voice memo (audio + frame thumbnail + transcribe; delete-
  before-import so a re-drain can't double-import). Compiles (both targets), installed on the dev phone.
  ✅ **DIAGNOSED + FIXED 2026-06-14 (DevLog device trace).** It was NOT a delete or a crash — the memo
  **relocates**. `importVideo` inserts it at `recordedAt = now` (top of the list, where you see it), then
  `processVideo` rewrites `recordedAt` to the video's EMBEDDED filming date (trace: `recordedAt=2026-06-11`
  vs `now=2026-06-14`) — intended ("sort by when it happened") — so it jumps from the top down to its real
  date and "vanishes" from where you're watching. The trace proved the relay + extract + thumbnail +
  transcribe all COMPLETE (`done; final status=done`); none of the three delete-vectors fired. FIX (user
  picked "keep the date, open it on import"): `MemoOpenBridge` (mirrors `RecordingIntentBridge`) — the drain
  calls `open(memoID)` after a shared-video import; `MemosListView` consumes it (`.onChange` + `.onAppear`
  for cold-launch-from-share) and sets `path = [id]`, landing the user ON the memo regardless of where it
  sorts. The `DevLog` markers along drain→importVideo→processVideo + the delete vectors are kept (DEBUG-only).
  Original symptom below.
  ⓘ Earlier repro note: share a video → it preps → share UI closes (no confirm = expected) → open Skrift →
  memo appears, flashes `transcribing`, then **VANISHES** (= relocates, per above). STATIC READ rules out the obvious causes: (1) nothing
  auto-deletes a non-trashed memo (`purgeExpiredTrash` only touches `deletedAt`-set / ≥14-day memos; there's
  NO purge of empty/transcribing memos); (2) the extract-failure path does NOT delete — `MemoSaver.processVideo`
  marks the memo `.failed` + title "Video had no audio track" and keeps it. So a true vanish is runtime/
  device-specific (AVFoundation reading the App-Group→temp copy, a drain timing thing, or security-scope on
  the shared file — note the leaked app-temp `shared_import_<id>` too). PLAN: add `DevLog` to the
  drain→importVideo→processVideo path (entry found · temp path · importVideo memoID · extractAudio result ·
  final transcriptStatus · any delete), repro on device, pull `Documents/devlog.txt` — share-ext + AVFoundation
  + device-only, the sim can't repro (CLAUDE.md: instrument + diagnose from the trace FIRST). The bidirectional+
  bounded capture (8/4) is the OTHER thing on the phone from tonight; eyeball both.
- (g) disk-writes `.ips` = profiling, not a clear fix (model downloads + whole-book transcribe = suspects).

Build-ready feature TRUE status (corrects the stale lists above):
- Models/Storage: ✅ MOBILE (`Features/Settings/ModelsView.swift` + `ModelInventory.swift`); ❌ DESKTOP (none).
- Record-a-voice enroll: ⏳ PLACEHOLDER both apps (`PersonDetailView`/`VoiceEnrollView` doesn't record; enroll only via conversation-naming).
- Mac "name a speaker" review UI: ⏳ OPEN (backend `DiarizationService.embedSpeaker` ready, called only from the `-voiceloop` harness; no turn-renderer / click-to-name in `Features/Review/`).
- Drag-multi-select (Photos-style lasso): ⏳ OPEN (native edit-mode drag works only AFTER the Select button; the lasso-replacing-Select wants a mock).
- In-app feedback → inbox/backlog: ⏳ OPEN (only the email zip; routing today is the external pull-phone-feedback skill).
- Source taxonomy: ⏳ PARTIAL — glyph/label maps DUPLICATED (`QueueDerivations.swift:61` desktop vs `MemoDisplay.swift:184` mobile), coincidentally in sync, no shared module; no PDF/video first-class type.

#### ✅ Memo sort/filter by date (recorded / added / edited) — built 2026-06-14
From the share-video discussion (user: "the date of recording just stays true"). `Memo` gains `createdAt`
(when it entered Skrift) + `editedAt` (bumped on title/transcript/tags/append edits via `markEdited()`) —
both nil-default, so legacy memos fall back to `recordedAt` (NO migration/backfill). Sort sheet:
**Recently added (NEW DEFAULT)** / Recently edited / Recently recorded / Oldest / Longest; the day-headers
follow the active sort (`groupDate`). Filter gains a **date range** on Recorded OR Added (from/to,
inclusive). `recordedAt` stays the content's TRUE date — so a shared video keeps its filming date but
sorts to the TOP under "added": this (not the open-on-import patch) is the real resolution of the "video
vanishes" report — both shipped, belt-and-suspenders. Compile + unit gate green; device-eyeball owed (the
date-range pickers + the edited-sort over real edits). Not added to the Mac upload contract (local-only).
Deferred edit-sites: conversation-turn text edits + C3 annotation don't bump `editedAt` yet (fall back to
`createdAt` — fine; add if it matters).

## ⭐ PARALLEL BOARD 2026-07-12 (last Fable-5 day — three lanes launched as separate chats)

Base for ALL lanes: origin/main ≥ `8d65ea6` (base-proof file: `Skrift_Native/SkriftMobile/Services/MemoDeduper.swift` —
if missing in your worktree, your base is stale: reset before any work). Every lane: OWN worktree branch,
explicit-path staging, sim-green end state, **NO phone installs / NO CFBundleVersion bumps** (device rounds
queue centrally — one phone), ledger edits only as small appends in the lane's FINAL commit, PR to main.
LOCKED design rule for all lanes: shared inputs never get bubble/box chrome (memory feedback_no_bubbles_on_shared_input).
- **Lane D (desktop)** — Boards A+B at "CONTINUE HERE — desktop-parity board" above (mock v2 = spec).
  Board C is HELD until Lane P merges (SpeakerTranscript move touches MemoDetailView = Lane P territory).
- **Lane P (phone editor)** — capture-as-note + note-editing follow-ups (memory project_capture_as_note_kickoff),
  on TOP of tonight's Wave-3 MemoDetail changes (borderless annotation, voice-annotate, PDF disclosure, rich url card).
- **Lane B (podcasts, C3 ⭐ STRONG GO)** — episode share/URL → RSS enclosure download → lands in the Books tab
  (playable, whole-transcribed via BookTranscript infra, read-along + quote capture). Audiobooks area only.

**Roadmap sweep 2026-07-12 (Command Center chat, v17):** the three lanes got roadmap nodes —
**DParityB** (Lane D) · **CapNote** (Lane P) · **Podcasts** (Lane B), all `inprogress`; **flip YOUR node
to `done` in your final commit** (don't mint a new one). Same sweep: fixed roadmap.yaml being INVALID
YAML since the 2026-07-11 TrEngine entry (unquoted `probe:` colon — the hub couldn't parse the file);
NEdit → done 2026-07-10; ShareW2 note refreshed to the chapter close (+ multi-item WhatsApp follow-up
in its backlog); duplicate idea id i5 → print-to-wall is now **i8**; i4 removed (shipped as ShareW1);
new idea **i9** = Tuur voice-over easter egg (tap About ~3×, everything goes weird); SSOT §4 Mac + P8
flipped done; STANDALONE_PLAN Phase 8 header marked done; stale NFeat desktop items pruned
(lock gate / link resolver / OCR search shipped in DParityA; body parity → DParityB).
**v18 history fix (2026-07-13):** H_rn re-ordered AFTER the Electron desktop (Tuur: the phone
companion came later — both sat at order -1.92); new first node **H_whisper** = the undated
pre-repo whisper-fork tinkering (from memory, no dates). Hub-side: lane bands now absorb
fractional rows into their parent lane (Tiuri-Command-Center PRs #82/#83).
