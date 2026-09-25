# Sweep D — macOS app (SkriftDesktop)

Read-only, static (no build/run). Scope: Sidebar, Review (BodyTextView/NoteDisplayView/
NoteProperties/ConnectionsPanel), Shell (RootView/ProcessingCoordinator), Pipeline
(BatchRunner/ingest/VaultExporter), App (CloudKit sync). Cites `plan/perf-sweep.md`
(R90–R94) rather than repeating it. Ranked worst first.

## SLOW

1. `Features/Sidebar/SidebarView.swift:79,641,718` — `backlinkedIDs` is a computed
   property (`MemoLifecycle.backlinkedIDs(in: effectiveCloudMemos)`, a full-corpus
   regex scan) that `quietMemoRow(_:)` reads once per call, and `quietMemoRow` is
   invoked **per row** from the `ForEach` at :641. Every quiet (unrated) row in the
   list re-scans the whole cloud-memo corpus for `[[memo:…]]` links. Same O(rows ×
   corpus) shape as perf-sweep's R92, but a distinct Mac call site not in that sweep.
   Fires on every sidebar render, including every keystroke in the sidebar search
   field (`model.searchText`). Fix: hoist `backlinkedIDs` out to a `let` computed
   once per `entries` build, pass it into `quietMemoRow`. Confidence: high.

2. `Features/Shell/ProcessingCoordinator.swift:331` (`func export`, not `async`) →
   `Pipeline/Export/VaultExporter.swift:69-186` — export runs synchronously on the
   main thread: `Compiler.compile` (regex/text pass), image-directory scan +
   per-image `copyOwned` file copies, and `writer.commit`'s atomic/coordinated
   write of markdown + audio + (for archive profile) the kept source **video**.
   Call sites are all un-Task'd: `SidebarView.swift:981` (`for t in exportable {
   coordinator.export(...) }` — a tight synchronous loop over a multi-select
   export) and `:1017`, `NoteActions.swift:132`. `IngestService` was already fixed
   for this exact beachball class (SidebarView.swift:166-168's own comment); export
   never got the same treatment. Fix: wrap `VaultExporter.export` in
   `Task.detached`/off-main like ingest. Confidence: high.

3. `Features/Review/NoteProperties.swift:53-54` → `TagLibrary.mostUsedFirst`/
   `counts` (same file, :251-267) — `context.fetch(FetchDescriptor<PipelineFile>())`
   over every non-deleted file, plus a tag-count dictionary build, evaluated as
   plain call-site expressions inside `NoteProperties.body`. `@Bindable var file`
   means any edit to that file (typing the title, ticking a tag) re-evaluates
   `body`, so this O(corpus) fetch+scan reruns on every keystroke in the note
   header — compounding with R90's per-keystroke `BodyTextView` cost on the same
   screen. Fix: cache `TagLibrary.counts` per note-open (or per `file.modelContext`
   generation), not per body evaluation. Confidence: high.

4. `Features/Sidebar/SidebarView.swift:50-55,74,78,689-698` — `chipCounts`,
   `unpipelinedMemos`, `strandedMemos`, `entries` are all computed properties doing
   O(files+memos) work (`WayOutRules.unpipelined`/`stranded`, each an independent
   scan), recomputed on every render. Typing in the sidebar search field
   (`model.searchText`) re-renders the whole view and reruns all of them, plus (per
   #1 above) `backlinkedIDs` again per quiet row. Fix: fold into one pre-render
   `Derived` struct built once per `files`/`cloudMemos` change, per the C278 pattern
   perf-sweep already prescribes for `MemosListView`. Confidence: high.

5. `Features/Review/NoteProperties.swift:186-196` (`titleBinding`) →
   `App/MacCloudMetaSync.swift:57-71` (`setTitle`/`write`) →
   `Pipeline/Ingest/MacCloudWriteBack.swift:43-51` (`resolve`) — every keystroke in
   the Mac title field calls `setTitle`, which calls `resolve`, which runs up to
   three separate `FetchDescriptor<Memo>` predicate lookups (by derived memo id,
   by filename-embedded UUID, by raw id) against the `Memo` table. Perf-sweep
   already notes "no `#Index` anywhere in `Shared/Model/`" (P3/§1), so each of
   these is an unindexed scan, repeated per character typed. The doc comment's
   claim that "per-keystroke calls don't churn CloudKit" is true for the network
   push but not for these three local fetches. Fix: memoize the resolved `Memo`
   per `pf.id` for the life of the edit session. Confidence: medium (fetch cost
   scales with corpus size — cheap for now, degrades as the vault grows).

6. `App/MacCloudEditSync.swift:47-73` (`flush`) — 1.5s after the user stops typing,
   this runs on the main actor: `Sanitiser.unlinkToSpoken` once for the live body,
   then (for conflict detection) `Sanitiser.process` + `Sanitiser.unlinkToSpoken`
   again over the "before" body — three full-document regex/name-link passes per
   flush, synchronous, on top of `BodyTextView`'s own per-keystroke restyle (R90).
   Long notes pay this twice: once per keystroke (restyle), once per edit-pause
   (this). Fix: move the round-trip comparison off the main actor. Confidence:
   medium (debounced, so lower frequency than R90, but same document-length cost).

7. `Features/Review/ConnectionsPanel.swift:65-71` (`ConnectionsModel.refresh`) —
   `context.fetch(FetchDescriptor<PipelineFile>())` (full corpus) for the backlink
   scan, on every note open (`.task(id: file.id)` in NoteDisplayView.swift:257-260)
   and again on every completed index sweep (:262-265). Same shape as the
   already-known "note opening scans the corpus" item (perf-sweep §2 #5), but that
   entry only covers the phone's `MemoDetailView`; this is the Mac's own instance,
   not yet tracked. Fix: same remedy — cache/scope the backlink scan. Confidence:
   high.

8. `Features/Shell/ProcessingCoordinator.swift:520-530` (`rescanRoster`) — after
   adding/editing a person, fetches every `PipelineFile`, filters to affected
   notes, then calls `resanitiseForNames` (Sanitiser + `Compiler.compile`, both
   full-document passes) **synchronously in a plain `for` loop on the main actor**
   for every affected note, before one `context.save()`. On a vault with many
   notes referencing a common name, this stalls the UI for the whole batch with no
   progress feedback. Fix: yield between notes (`Task.yield()`) or move the loop
   off-main. Confidence: medium (infrequent trigger — only fires on a roster
   collision — but unbounded by corpus size when it does).

9. Cite, don't repeat — already fully documented in `plan/perf-sweep.md`:
   R90 (`BodyTextView.swift:232-239,651-782,1019-1035` — full-document restyle +
   model write per keystroke, no debounce) and the Mac twin of P4
   (`Pipeline/Ingest/MemoCloudIngest.swift:210-228` + `Models/PipelineFile.swift:
   253-256` — `adoptLateDiarization` always faults asset blobs for a monologue).
   Both still open per that sweep's read.

## INELEGANT

10. `Features/Sidebar/QueueDerivations.swift:147-152` (`SkriftFormat.duration
    (seconds:)`, hours-aware: "1:02:03") vs `Features/Review/ReviewHelpers.swift:
    38-42` (`SkriftFormat.clock(_:)`, m:ss only) — two independent time formatters
    on the same `SkriftFormat` enum, split across two files, with **different and
    incompatible behavior**. `.clock` is what `NoteToolbar.swift:35,39` (the audio
    transport) and `NoteProperties.swift:95` (the duration chip) actually call, so
    a recording or audiobook-quote capture over 60 minutes reads e.g. "125:33" in
    the note header/player while the sidebar row for the SAME note (which uses
    `.duration`, QueueDerivations.swift:108) correctly shows "2:05:33" — one note,
    two disagreeing/one-wrong readouts. Fix: delete `.clock`, route both call sites
    through `.duration(seconds:)`. Confidence: high (verified both call graphs).

11. `Features/Sidebar/SidebarView.swift:778-783` (`quietMeta(_:)`) — dead code, zero
    call sites anywhere in the target (only its own definition matches a repo-wide
    grep). Fix: delete. Confidence: high.

12. `Features/Sidebar/SidebarView.swift:800-805` (`private func process(_ memo:
    Memo)`) — dead code: sets `significance = 0.1` and kicks a reconcile, matching
    its doc comment's "Q2: the one-click minimum flag" feature, but nothing in the
    file calls it (every other `process(` call site is `coordinator.process
    (fileIDs:...)`, a different method). Either the wiring for this UI verb was
    never finished or was cut and the function never removed. Fix: wire it to a
    control or delete it. Confidence: high.

13. `Features/Review/BodyTextView.swift` (1,572 lines) and `Features/Sidebar/
    SidebarView.swift` (1,330 lines) are the two largest files in the app by a wide
    margin (next is `Features/Shell/Snapshot.swift` at 1,316, DEBUG-only). Both mix
    several concerns in one file — `SidebarView.swift` alone holds the queue list,
    the header/record transport, the filter popover, an AppKit file-promise NSView
    bridge (:1060-1173), and the shared row/style extensions. Fix: split each along
    its existing `// ──` section markers (e.g. promise-drop bridge and row types
    out of `SidebarView.swift` into their own files). Confidence: med (size is a
    fact; whether it's worth the churn is a judgment call).

Counts: 9 SLOW (7 new + 1 cite bundling 2 known items), 4 INELEGANT. 13 findings total.
