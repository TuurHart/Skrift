# Audit plan — 2026-09-01

A read-only audit of both apps, run while Tuur was away. Six agents across mobile main-thread,
SwiftData, SwiftUI rendering, concurrency, the Mac app, and outside tooling research. Nothing was
built or tested: **there is no Xcode in the container this ran in.** Every fix below is unbuilt.

Trigger was "the phone feels laggy everywhere" at **under 200 notes**, on the **prod (Release)
build** — so neither data volume nor the Debug penalty. The audit also found three ways to lose
data, which outrank the lag.

**Two confidence levels, and they matter.** ✅ = I re-read the code and confirmed it myself.
🔶 = an agent reported it and I did not verify. Agents were wrong at least once (see §7), so
treat 🔶 as a lead, not a finding — same rule `LANE_PLAYBOOK.md` already applies to lane output.

---

## 0. Measure first — before any fix

**Correction (2026-09-01, from Tuur): he uses the PROD build, not Skrift Dev.** So the lag is real,
in optimized code, at under 200 notes. None of it is the `-Onone` penalty.

That removes two findings from the explanation — §2 P3 and the `callStackSymbols` line at
`NotesRepository.swift:84` are both DEBUG-only and never ran on his phone — and it promotes
everything else: P1, P2, P4 and tier 3 are now the *whole* story rather than part of it.

Profile the build you actually run:

1. **⌘I (Product ▸ Profile).** The Profile action builds the **Release** configuration, so this
   profiles the code you feel. Never diagnose from the simulator or from Skrift Dev.
2. **Time Profiler first.** One question: during a stall, is the main thread **busy** (too much work
   — tier 2/3) or **blocked** (I/O, a lock, CloudKit — different fixes entirely)? Everything
   downstream branches on that answer. It also labels hangs directly in the process track.
3. **On-device hang detection** — Settings ▸ Developer, enable it. Works on a development-signed
   build with no Instruments attached, so you can use the app for a day and collect real stalls.
4. **Thread Performance Checker + Main Thread Checker are still worth running on Skrift Dev.** They
   detect *which thread* code runs on, and that does not change between configurations — a sweep on
   the main actor is on the main actor in both builds. Only the timing differs. So Dev is a valid
   place to find the offenders even though it is the wrong place to judge speed.
5. Then the **SwiftUI instrument** for specific screens. ⚠️ Instruments 26.3 bug (FB22288896, Apple
   forums thread 818910): **Show Cause & Effect Graph** has driven Instruments to 18–34 GB and
   kernel-panicked a 16 GB M1. Save the trace before opening that view.

**Xcode Organizer field metrics are unavailable to you right now.** Hang rate, launch time and
hitches come from TestFlight, and TestFlight is account-blocked — see
`TESTFLIGHT_INSTALL_HANDOFF.md`: 29 builds across 5 apps force-expired in a 3-second window on
2026-08-26, Apple-side. Ad Hoc is the current distribution path and does not feed Organizer.
Revisit once that is unblocked; it is the cheapest real-user signal there is.

---

## 1. Data loss — fix regardless of what the profiler says

None of this is about speed. All three are verified.

### D1 ✅ The names database can lose entries permanently, across every device
`Shared/Naming/NamesStore.swift:12, :29-33, :44-51, :113-127`

`NamesStore` is a plain `final class` singleton — no lock, no queue, no isolation. Three problems
compound:

- `save` (`:50`) is `try? encoded.write(to: fileURL)` — **not `.atomic`**.
- `load` (`:29-33`) returns `NamesData(people: [])` on any decode failure, silently.
- `addVoiceEmbedding` (`:113-127`) is `var data = load()` → mutate → `save(data)`, unguarded.

`VoiceEnroller.enroll` is a non-isolated `static async func`, so it runs that read-modify-write off
the main actor while `NamesCloudSync.run` can be doing its own load-merge-save on main. Ordinary
lost update — and because `save` recomputes `lastModifiedAt`, CloudKit LWW then propagates whichever
side lost to every device, permanently.

Worse path: a reader hitting the file mid-overwrite gets a truncated document, `decode` fails, and
`load` hands back an **empty roster**. If that empty roster is then mutated and saved, the whole
names DB becomes one person and LWW pushes it everywhere. Needs a real coincidence; nothing prevents it.

**Fix.** `options: .atomic` on that one line kills the torn-read half today — `ExportLedger.persist`
(`Shared/Export/VaultWrite.swift:84`) already uses it, so the pattern is in the codebase. Then
serialise the store behind an actor or a private queue with an in-memory cache for the lost-update
half. `SettingsStore` (`SkriftDesktop/Models/AppSettings.swift:136,171,173`) has the identical shape.

### D2 ✅ Re-transcribe destroys a transcript when the audio has moved
`SkriftDesktop/Features/Shell/ProcessingCoordinator.swift:368-385`, `:175-177` ·
`Pipeline/BatchManager/BatchRunner.swift:48-66`, `:103-107`

`retranscribe` nils the transcript and every derivative, then saves. `process()` computes `hasAudio`
with a `fileExists` check and passes `audioURL: nil` when the file is gone. `BatchRunner` then skips
the whole `if let audioURL` block but still runs `pf.transcribeStatus = .done` (`:66`). Line 103 sees
an empty transcript, sets `enhanceStatus = .done`, returns. No error, no `lastError`. The note reads
as fully processed with nothing in it.

**Blast radius is narrow, and that's what makes it survivable.** A phone-sourced memo is restored by
the next CloudKit sweep, and `MacMemoAuthor.reflectTranscripts:114` refuses to publish an empty
transcript, so the phone's copy is never poisoned. The permanent loss is a **Mac-local** row — a
drag-dropped import, a video ingest, a Mac recording — whose audio has since moved.

**Fix.** Check the audio exists before clearing, or clear into a scratch and commit only once ASR
returns. Either way `BatchRunner` should set `.done` inside the `if let audioURL` branch, not outside it.

### D3 ✅ Vault export can delete files in the Obsidian vault
`SkriftDesktop/Pipeline/Export/VaultExporter.swift:269-270`, `:293-294`

Both do `try? fm.removeItem(at: dest)` then copy, where `dest` is the attachments folder plus the
**original filename**. An Apple Note attachment or a legacy capture image called `IMG_0001.jpg` or
`Screenshot.png` deletes whatever is already at that path. If the copy then fails, `loggedCopy` writes
a log line and the file is gone.

The markdown lane is properly protected — `VaultWriter` refuses foreign and user-edited files and
writes atomically under `NSFileCoordinator` (`Shared/Export/VaultWrite.swift:355-366`). These two
attachment lanes bypass it entirely.

**Fix.** Route them through `VaultWriter`, or refuse to overwrite a destination the ledger doesn't claim.

### D4 ⚠️ A whole recording is lost if the app dies mid-recording
`SkriftMobile/Services/Recording/LiveRecordingService.swift:433`

**Not an audit finding** — Tuur reported it from prod on 2026-08-22, after a phone call ate a long
recording, and it is added here so this section isn't read as the complete data-loss list. An
in-flight recording is persisted nowhere until `stop()`, and `rec_tmp` appears exactly once in the
whole repo: the line that creates it. So any process death mid-recording loses the take, orphans the
`.m4a` forever, and never tells the user. It has happened before — the 2026-06-10 crash-mid-recording
P0 ("3× today, one recording LOST") fixed that crash and left the durability gap untouched.

**Fix.** Four steps, cheapest first, in `backlog.md` under `## 🚨 OPEN P0`; tracked as
[issue #14](https://github.com/TuurHart/Skrift/issues/14). `tools/rescue-lost-recordings.py` pulls
the existing orphans off the phone (Mac only — it needs `devicectl`).

---

## 2. Cheap performance wins — one afternoon, no schema change, no behaviour change

Ordered by payoff per minute of work. P1 was found independently by three agents.

### P1 ✅ Two full-corpus scans per rendered row
`SkriftMobile/Features/MemosList/MemosListView.swift:462-463` (and `:544`)

```swift
MemoRow(memo: memo, enhancedTitle: enhancedTitleByMemoID[memo.id],
        fading: searchFadingIDs.contains(memo.id), …)
```

Both are computed properties, read **inside** `ForEach(group.memos)`.

- `enhancedTitleByMemoID` (`:900`) rebuilds a `Dictionary` over every `MemoEnhancement` per access,
  trimming every title. Touching `e.title` faults each enhancement row, dragging in `copyedit` and
  `summary` with it.
- `searchFadingIDs` (`:1154`) reads `lifecycle` (`:1139`) → `MemoLifecycle.partition(memos)` →
  `backlinkedIDs`, a string scan of **every transcript in the store**. While searching, that runs
  once per row, per keystroke.

The comment at `:436-441` establishes the "never per row" rule and correctly hoists `derived` and
`backlinked`. These two were missed twenty lines below it.

**Fix.** Hoist both next to `let d = derived` and fold into the `Derived` struct (`:1167`). Also bind
`let split = lifecycle` once inside `filtered` (`:1145-1152`) — `lifecycle.live` and `lifecycle.fading`
are two separate accesses, so each partitions the corpus again.

### P2 ✅ `mkdir` on every path access, 44 call sites
`Shared/Model/AppPaths.swift:19-23`

`recordingsDirectory` is a computed `static var` that calls `createDirectory` every read. It sits
behind `memo.audioURL`, `memo.imageURL(markerIndex:)`, and the sidecar stores. `AssetMaterializer`
hits it ~4× per memo and adds a `stat` — on the order of 1,600 syscalls per sweep at 200 notes, and
the sweep runs at launch, at every foreground, and on every CloudKit import burst.

**Fix.** `static let`, with the directory created once at bootstrap. Purely mechanical.

### P3 ✅ DEBUG only — does NOT affect the prod lag, still worth deleting
`SkriftMobile/Features/MemosList/MemosListView.swift:306-318`

Inside `#if DEBUG`, every keystroke walks every memo, decodes each image manifest, and lowercases
every OCR string. Then the `DevLog.log` line interpolates `filtered.count` — and in DEBUG,
`DevLog.log` evaluates its `@autoclosure` **on the calling thread**, so the entire filter/sort/partition
pipeline runs a second time on main.

The comment records that the Release half of this was caught and wrapped. **Since Tuur runs prod,
this never ran on his phone** — it is not part of the lag being investigated. It still slows Skrift
Dev, which is the build the `pull-phone-feedback` loop records into, so it is worth deleting; it just
isn't tier-2 urgent any more.

**Fix.** Delete it, or gate it behind a launch flag.

### P4 ✅ The asset sweep faults every audio and photo blob into memory
`SkriftMobile/Services/NotesRepository.swift:131` · `Services/AssetMaterializer.swift` (`captureMissing`)

`allAssets()` is an unscoped `FetchDescriptor<MemoAsset>()`. `indexByFilename` then touches
`$0.filename` on every row, and SwiftData's faulting is row-level, so every inline blob is realised.
`MemoAsset.blob` is plain `Data` and deliberately **not** `.externalStorage` (`Shared/Model/MemoAsset.swift:16`).
Runs on the main actor at launch, at every foreground, and on every import burst.

`materializeMissing` twenty lines above already solves this with `propertiesToFetch` and a comment
explaining exactly this trap. `captureFile` only ever reads `byteCount` off the existing assets, so
the blobs are loaded for nothing.

**Fix.** Give `allAssets()` (or a new scoped variant) `propertiesToFetch = [\.filename, \.kind, \.byteCount, \.memoID]`.

**Do not "fix" this by adding `.externalStorage`.** The type doc is right that it `fatalError`s under
`NSPersistentCloudKitContainer`. Generic SwiftData advice says otherwise; it does not apply here.

### P5 🔶 The source-type lookup parses the metadata blob twice, per row
`Shared/Pipeline/SourceTaxonomy.swift:54-71`, called from `MemosListView.swift:1397`

For an ordinary voice memo it falls through to a `JSONSerialization` parse of `metadataData` **and**
a `SharedContent.decode` over the same bytes — two full uncached parses of a blob that carries
location, weather and the whole image manifest including per-photo OCR text. `Memo.metadata`
(`Shared/Model/Memo.swift:325-338`) already has an NSCache for exactly this reason; `SourceKind.of`
reaches around it to the raw bytes.

### P6 🔶 `SpeakerTranscript.parse` compiles a fresh regex 4-6× per note page
`Shared/Pipeline/SpeakerTranscript.swift:39-40`

`try? NSRegularExpression(pattern:)` inside the function, not a static. Called from
`MemoDetailView.swift:887`, `:1537`, `:1585`, `:1727`. Four other files in the codebase cache their
regexes as `static let` — this type is the outlier. Fix is one line plus a `transcript.contains("**")`
short-circuit.

### P7 🔶 `names.json` is re-read and re-decoded on every access
`Shared/Naming/NamesStore.swift:28-39`

No memoization anywhere in the type. The file carries 256-dim voice embeddings as `[Double]`, unioned
per person, written pretty-printed. Hot callers include `MemoDetailView.swift:895` (once per realized
pager page, so per note open) and every `NamesCloudSync.run`. The cache this needs is the same one D1
needs for its actor — **do D1 and P7 as one change.**

---

## 3. Structural performance — needs §0 measurement to justify

Real work, but sequence it behind the profiler so you fix what's actually costing frames.

- 🔶 **The launch/foreground sweep chain.** `SkriftApp.swift` hangs nine `@MainActor` synchronous
  sweeps off `RootView` as `.task` modifiers ✅, and `CloudSyncMonitor.swift:127-160` fires five of
  them again on every CloudKit import burst — a third trigger with no floor. None are checkpointed:
  each re-derives from scratch whether one memo arrived or none. Fix shape is a stored high-water mark
  per sweep plus moving the non-UI ones off the main actor. Also `DemoDataSeeder.seedIfRequested`
  fetches every memo as the first statement of `App.init`, **before** checking its launch flag.
- 🔶 **Note opening does the corpus twice, per pager page.** `MemoDetailView.swift:882-901` — a
  word-timing sidecar decode, a `names.json` read, `recomputeBacklinks()` (which allocates a full copy
  of every transcript before detaching), then `backlinkedIDs(in: repository.allMemos())` scanning the
  corpus a second time. The pager is a `LazyHStack`, so this runs for the current page and its neighbours.
- 🔶 **Read-along and conversation playback redraw whole screens on a timer.**
  `ConversationTurnsSection` observes a 20 Hz clock and rebuilds a non-lazy `ForEach` over every turn,
  compiling a regex per turn. `AudiobookPlayerView` observes the session, so a 2 Hz position write
  invalidates header, scrubber, transport and the read-along subtree together. Fix shape for both:
  a separate small observable for position, read only by the leaves that display it.
- 🔶 **Mac twin of P4.** `MemoCloudReconciler.swift:117-122` — `adoptLateDiarization`'s guard can never
  become false for a monologue (the setter stores `nil` for an empty array), so `fetchAssets()` faults
  every blob per memo per sweep, on every window activation. It breaks the sweep's own stated invariant
  at `:61-65`.
- 🔶 **Mac vault scan with no cap.** `Shared/Export/VaultStamp.swift:140-154` enumerates every `.md`
  in the vault and opens each to read 2 KB of frontmatter, uncapped, on the main thread — once per
  updated row inside the sweep. `VaultTagScanner` caps at 5000; this doesn't.
- 🔶 **No `#Index` anywhere in either app**, on iOS 18 / macOS 15 deployment targets where it's
  available. Candidates: `Memo.deletedAt` + `recordedAt` (compound), `MemoAsset.memoID`,
  `MemoEnhancement.memoID`. Store-level index, not a CloudKit schema change — but verify the migration
  against a copy of the dev store before promoting.

---

## 4. Concurrency — real bugs the compiler will never show you

Both apps build `SWIFT_VERSION: "5.9"` with **no** `SWIFT_STRICT_CONCURRENCY` setting anywhere ✅.

Fix these on their own merits, independent of any compiler flag:

- 🔶 **`isTranscribing` is a `Bool` on a re-entrant actor** and it gates model teardown
  (`SkriftMobile/Services/Transcription/TranscriptionService.swift:24,118,130`). Two overlapping
  transcribes — a book chunk and a voice memo — both set it; the first to finish clears it, and a
  memory warning can then `cleanup()` the manager the other is still decoding on. `TranscriptionActivity`
  twelve lines away is a counter under `OSAllocatedUnfairLock` for exactly this reason. Make it a depth counter.
- 🔶 **`MacRecorder.stop` finalises a take by dropping a reference** with no queue drain
  (`SkriftDesktop/Engines/MacRecorder.swift:298,348`). The phone fixed this identical bug and documented
  it — `LiveRecordingService.swift:536-556` does `writerQueue.sync {}` then an explicit `close()`, with
  a comment naming "the intermittent cut-off-tail bug". The Mac never got the port.
- 🔶 **Live-caption buffers go through one unstructured `Task` per buffer** into an order-critical
  consumer (`LiveRecordingService.swift:833`, `LiveRecordingSession.swift:111`). On the phone that's a
  scrambled caption; **on the Mac settled text becomes the saved transcript**, so mis-ordering can commit
  garbled words. Fix is an `AsyncStream` with one consumer, ordered by construction.
- 🔶 **`GemmaEmbedder.downloadProgress`** is a `nonisolated(unsafe)` closure nil'd from main exactly
  when callbacks are still landing from the download thread (`Shared/RetrievalEngine/GemmaEmbedder.swift:27,96`).

**On turning the flag on.** `targeted` is ~3 days and catches the actor-boundary clusters. `complete`
is 10–15 days, dominated by whether FluidAudio, CoreML-LLM and mlx-swift ship Swift 6 modes — check
their `Package.swift` before committing to a number. Note that **neither setting catches D1**, because
`NamesStore` adopts nothing and is invisible to the checker. Do the bugs first; the flag second.

---

## 5. Tooling — so the next year doesn't accumulate the same way

Day one is measurement infrastructure, not fixes.

- **SwiftLint with a baseline ratchet.** `swiftlint --write-baseline Baseline.json`, commit it, set
  `baseline:` in `.swiftlint.yml`, run `--strict` in CI so only *new* violations fail. This lets you turn
  on `file_length`, `type_body_length`, `cyclomatic_complexity` today without a thousand-warning wall —
  and the baseline JSON is a ranked worst-offenders list for free. 0.65.1 (Aug 2026) made baselines
  path-relative, so a committed baseline works across machines.
- **Duplication report.** The highest-signal metric for a codebase built this way, and SwiftLint won't
  find it. `npx jscpd --languages swift --min-tokens 70 Skrift_Native`, or `lizard -l swift`.
- **Long-compile hunt, two-for-one.** Add `-Xfrontend -warn-long-function-bodies=200 -Xfrontend
  -warn-long-expression-type-checking=200` for one diagnostic build. The functions it names are usually
  giant SwiftUI bodies — frequently the same ones that are slow at runtime.
- **`OSSignposter` around the pipeline stages** — transcribe, enhance, name-link, `MemoCloudIngest`,
  compile, export. Your slow paths are named domain operations, so labelled intervals in Instruments beat
  anonymous frames. This is what makes round two measured instead of guessed.
- **Dead code — Periphery, with a caveat.** The open-source repo was **archived 12 Aug 2026** and moved
  commercial (periphery.pro). Reportedly still free for solo/indie use in open beta, but that's secondhand
  — the research agent's proxy blocked the site. **Check the terms yourself before building it into CI.**
  Free partial substitute: `swiftlint analyze --compiler-log-path build.log` (`unused_declaration`,
  `unused_import`) — needs a clean full build log, so run it weekly, not per-commit.
- **Test the tests.** ~1,890 test functions, written largely by assistant. Coverage isn't the question;
  whether the assertions bite is. Mutation testing answers it, but Swift's `muter` looks stale — verify
  before spending time. The manual substitute costs ten minutes: pick ten important functions, break each
  deliberately (invert a condition, drop a `save()`), and see if the suite goes red.
- **`XcodeBuildMCP`** (getsentry, actively developed) gives an agent your build → install → drive UI →
  read debugger loop, headless. The highest-value agent tooling for this repo specifically.

**Worth knowing about the general problem.** Thoughtworks' "Maintainability sensors for coding agents"
(Fowler / Böckeler, May 2026) is the one piece of non-marketing writing worth reading. Its useful claim:
deterministic tools work well at file and function level and **struggle with cross-file concerns like
modularity**, where an LLM review pass is far more effective — which is precisely the "structural problems
I can't see" worry. Quantitative work (GitClear, arXiv 2603.28592) points the same way: not new *categories*
of debt, but a shifted distribution of familiar ones — duplication where a human would have abstracted,
dead code from abandoned approaches, high coverage with thin assertions. Every one of those maps to a tool
above. Both sources were proxy-blocked and read via search summaries; verify figures before quoting them.

---

## 6. Suggested fortnight

| Day | Work |
|---|---|
| 1 | §0 measurement. ⌘I Time Profiler on the prod build — settle busy-vs-blocked first. |
| 1 | SwiftLint baseline + CI ratchet. Duplication report. One `-warn-long-function-bodies` build. |
| 2 | **D1** (atomic write + actor + cache — folds in P7). Highest risk, do it fresh. |
| 3 | **D2** and **D3**. Both small and self-contained. |
| 4 | Tier 2: P1, P2, P4 (P3 is Debug-only). One afternoon, then verify against the day-1 traces. |
| 5 | Time Profiler + SwiftUI instrument on whatever still feels slow. Signposts around the pipeline. |
| 6–8 | Tier 3, ordered by what the traces actually showed. Not before. |
| 9–10 | Tier 4 concurrency bugs. Then `targeted` as a pilot on `Shared/`. |
| 11+ | Break-ten-functions test of the suite. LLM modularity pass for the cross-file work. |

Commit per chunk and verify each chunk, per CLAUDE.md. Tier 2 items are independently revertable —
don't batch them into one commit.

---

## 7. Where the agents were wrong

Recorded because it calibrates how much to trust the 🔶 items.

- One agent claimed `Thread.callStackSymbols` in `NotesRepository.softDelete:84` runs in Release. It
  does not — `DevLog.log` takes an `@autoclosure` and the Release build's body never calls it, so the
  argument is never evaluated. The agent reasoned it was a normal call. **It does run in DEBUG**, which
  is the build you test on, so the finding survived in a different form.
- The research agent's generic SwiftData advice says to put large `Data` behind `@Attribute(.externalStorage)`.
  For `MemoAsset` that is wrong and would crash: it `fatalError`s under `NSPersistentCloudKitContainer`,
  which the type doc already records. It *is* valid for `PipelineFile`'s JSON blobs, which live in a
  local-only store.
- Three agents independently reported P1, which is why it's first in tier 2. One agent reported P4's
  `materializeMissing` as already-fixed and correctly did not re-report it.

---

*Produced 2026-09-01. Ten findings hand-verified; the rest are leads. Nothing built, nothing tested —
no Xcode in the audit environment.*
