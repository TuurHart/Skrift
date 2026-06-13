# Text-first audiobook capture — design decisions (2026-06-13)

Design-session output. The shipped **Hybrid** audio-marking capture (mode 4 of
`capture-redesign.html`) tested badly with real (non-builder) users. This is the
spec for a **text-first** alternative that ships *alongside* it for an A/B test.
Mock comes next; build only after sign-off.

## 0. Why (the trigger + the failures)
- Shipped Hybrid works for the builder (video-editor mental model) but **real
  testers couldn't use it.** Builder-bias confirmed.
- Specific failures, from the user: (1) **didn't understand In/Out marks**;
  (2) **too many buttons**; (3) the text review had **text too small** and they
  **didn't realise you can tap a sentence** to add/remove it.
- Root mismatch: the thing you want is *"those two sentences the narrator just
  read,"* but Hybrid makes you find them by scrubbing **audio time** + dropping
  **markers**. Text is the natural domain for a quote.

## 1. Direction
- **Text-first capture:** show the recent narration as **selectable sentences**;
  tap to pick the quote. Essentially "phrase-hopper with words" — discrete,
  readable, no scrubbing/marks/transport.
- We already have the building block: the **sentence-trim sheet**
  (`capture-sheet-trim.html`) does text-sentence select → audio span via
  word-timings. Promote that interaction from a *refinement* to the *primary*
  selection.

## 2. Two modes coexist (A/B), cleanly isolated
- **Keep BOTH** the current audio-marking mode and the new text mode. Ship both,
  test with real users, **surgically remove the loser later.**
- **Naming:** NOT "Classic" (it's 2 days old). Name by what they are —
  **"Audio" / "Text"** (alt: "Scrubber" / "Transcript"). Settings reads
  **"Capture by: Audio · Text."**
- **Default = Audio** (the current, proven one). You opt INTO Text.
- **Isolation seam = the `QuoteCaptureOutput`, NOT just a span.** (Corrected per
  code verification.) The shared `CaptureSheetView` consumes the processor's full
  output — `quote`, `wordTimings`, `bufferSentences`, **`bufferAudioURL`** (a
  per-capture temp `.m4a`), `bufferOffset` — and its sentence-trim/`applyTrim`
  re-slices from that `bufferAudioURL`. So the seam both modes must emit is the
  `QuoteCaptureOutput` shape.
  - Mode A = `CaptureMomentView` (existing) → span → `QuoteCaptureProcessor` —
    **not touched.**
  - Mode B = new `TextCaptureView` (reads a `BookTranscript` sidecar) + the
    transcribe button/job — **all new files.** On confirm, Mode B **exports its
    selected sentence-span to a temp `.m4a`** (reuse `QuoteCaptureProcessor.exportSpan`
    / `AVAssetExportSession`) and emits the SAME `QuoteCaptureOutput` (carrying that
    `.m4a` + the chunk's word-timings rebased to the buffer) → the shared sheet,
    trim, ramble, significance, sync, export all work **unchanged.** (This is the
    key correction: a chunked-spot capture has no per-capture buffer otherwise, and
    the trim sheet would break.)
  - The **router** slots at `QuoteCaptureFlowView`'s stage switch (one layer below
    the Capture *button*, which is the right place) and switches on the Settings
    flag. BOTH entry points — full-player Capture pill + mini-player ❝ — are
    preserved for both modes.
  - Remove B later = delete its files + the router branch + the toggle. Remove A
    = delete `CaptureMomentView` + its branch. Neither touches the other or the
    shared sheet.

## 3. Transcription — facts (measured / user-confirmed)
- **35 s = one-time ENGINE WARM-UP** (model load / ANE-compile into memory),
  even with the model already downloaded. **NOT inference.** (User device
  observation; Mac measurement was irrelevant and is disregarded.)
- **Warm inference ≈ 1 s per screenful of text.**
- **Engine serializes** — `TranscriptionService` is an actor, one inference at a
  time.
- **File-transcription does NOT contend with playback** — it reads file samples,
  no mic, separate from the playback audio session. So **listen + transcribe
  simultaneously is fine.** (Recording + playback contend; this is not that.)
  Thermal throttle would slow *transcription*, never stutter playback.

## 4. Transcription — model (chunking)
- **Chunking is the path.** Transcribe the book in chunks; **save each chunk to a
  sidecar as it lands** → the partial transcript is usable; never wait for the
  whole book.
- **A chunked spot needs the engine for NOTHING** — capture = read text +
  word-timings from the sidecar. Instant. No warm-up, no contention. The engine
  is only ever needed for an **un-chunked** spot.
- **Three ways text gets populated** (v1 ships 1 + 2):
  1. **"Transcribe whole book" button** — deliberate, whole thing, chunked,
     resumable, **recommended overnight / on charger.** Book ⋯ menu (next to
     "Edit book details"). Progress bar. "Best left plugged in."
  2. **Auto on-capture** — playhead-window first, then fill forward.
  3. *(later, optional)* auto-transcribe-ahead while playing.
- **Chunk ORDER is playhead-aware for the live case** — chunk outward from the
  current position, not page 1. The overnight whole-book job can go sequential.
- **Pre-warm the engine on book-OPEN / play** (background), NOT at capture-tap →
  hides the 35 s so the warming screen rarely shows.
- **Keep warm only around active capture — do NOT pin it the whole session.**
  Holding ~1 GB resident in a long *background* audio session is a **jetsam
  risk** (not a battery one). The phone already unloads on memory warning
  (`didReceiveMemoryWarningNotification`). After such an unload during an active
  session, **re-warm in the background**, don't wait for the next tap.
- **On-tap window must PREEMPT a running background chunk job** (pause bg → do
  the urgent window → resume). Cheap when warm.

## 5. Battery (the hike question)
- **Warmth ≠ battery.** A loaded-but-idle model is just resident memory; the ANE
  is power-gated when not running. **Keeping warm draws ~nothing.**
- **The battery cost is INFERENCE**, which only runs when actually transcribing.
- **Pre-transcribed book ⇒ zero engine at runtime ⇒ zero ASR battery** (e.g. on a
  hike). The engine can be fully unloaded. This is why the overnight button is
  the recommended path for long / off-charger listening.
- **Un-transcribed + capturing live ⇒ battery ∝ how much you capture** (opt-in).
- (Honest caveat: reasoned from ANE/CoreML behaviour, not a measured mAh; can
  measure a fixed-listen delta on device if we want certainty.)

## 6. Chunk fusion / seams
- The **fused big transcript is the right end state.**
- **Can't cut AUDIO at sentence ends pre-transcription** (chicken-and-egg —
  sentences are a text concept; no transcript yet).
- **Audio cut = silence-based:** cut at the **longest pause** near the boundary.
  Sentence-end pauses are the longest silences, so this lands at a sentence break
  almost every time → no split words. **Overlap** as backstop.
- **Fusion seam = reuse the existing sentence tech** (`CaptureMath.isSentenceEnd`
  / `sentenceStartIndices`, which run on `[WordTiming]`): overlap chunks, splice
  at a sentence boundary **both chunks agree on** in the overlap zone.
- **Capture = `CaptureMath` sentence-snap, unchanged.**
- **Offset each chunk's word-timings to absolute book time** on fusion.

## 7. The text-capture SELECTION screen (the part that actually failed — fix discoverability)
- **BIG** sentences, each a visually distinct **tappable line** (not prose you
  have to discover is interactive).
- **Pre-select the last sentence that ENDED at/before the playhead** — NOT the
  in-progress one. (Correction: at capture you're usually mid-sentence;
  pre-selecting the incomplete sentence reproduces the "added an extra/partial
  sentence" bug that round-2's IN-snap rule was created to kill. Port that intent:
  the in-progress sentence is the first grey *extend* target, not pre-selected.)
- **Reuse the signed-off trim-sheet interaction wholesale** (`capture-sheet-trim.html`
  rules — don't reinvent): grey neighbour sentences carry a visible **"+ include"**
  affordance (not just dimmed prose); **tap a bright edge to DROP** it; middle
  sentences refuse with a hint; keep the **legend** (bright = in the quote / grey =
  tap to include). Selection grows AND shrinks — not extend-only.
- **Discoverability trap to avoid:** pre-selection + one-tap-confirm means a happy
  user never taps and never learns the gesture. So the neighbour **+include**
  affordance must be visually obvious on first view, and the legend present.
- **Literal instruction:** "Tap the sentences you want to quote."
- **One primary button:** "Use as quote →" (into the existing shared
  `CaptureSheetView` — same ramble / significance / "Save & keep listening" /
  no-auto-resume semantics; NOT a forked lightweight sheet).
- **No waveform, no marks, no transport.**
- Selection + window are **confined to the current chapter file** (honour the
  code-enforced no-cross-file-boundary invariant). At a file's start there's no
  earlier context — show a "start of chapter" stop, don't silently pull the
  previous file. Cross-chapter quotes stay a later enhancement.
- *(later, opt-in)* "✎ adjust" for sub-sentence audio precision — the audio
  Hybrid demoted to a fine-tune fallback. NOT in the v1 default path.

## 8. The un-chunked / warming state
- Capturing a not-yet-chunked spot → a screen that: says it isn't ready, shows
  **model-loading progress**, frames it as **"getting this bit…"** + a tip:
  **"transcribe the whole book to skip this — best overnight on charger."**
- **Must not cost you your place** in the book (book pauses at capture / position
  captured at tap).
- Pre-warm (§4) makes this rarely appear.

## 9. Open questions / flags (resolve in mock or note)
- Quotes **longer than the available transcribed window** → a **"↑ earlier"
  scroll-back** on the select screen that triggers backward chunk-fill (within the
  chapter), with its own brief loading. Also the foresight case (good bit ended a
  while ago) uses the same scroll-back instead of many taps up.
- **Transcription errors in the written quote: v1 = NOT free-text-editable.**
  (Correction.) Editing the quote text would diverge it from the quote audio + the
  rebased karaoke word-timings and collide with §8's byte-identical assertion —
  the exact class of bug round-2 paid for. The audio is exact regardless; a
  text-edit is a later, carefully-designed feature (re-derive nothing, or exclude
  from karaoke). Drop it from v1.
- **Storage cleanup** when a book is deleted; **transcript staleness** on
  re-import (key the sidecar by book id + file hash; natural home =
  `Documents/audiobooks/<id>/`).
- Frontier **seeded at import vs first-play** — converged on **button +
  on-capture**; auto-ahead-on-play is later/optional.

## 11. Verification findings folded in (2026-06-13, two agents)
Corrections already applied inline above: real seam = `QuoteCaptureOutput` (§2),
mid-sentence pre-select rule + drop/affordance/legend (§7), cross-file confinement
(§2,§7), no free-text quote edit in v1 (§9). Remaining decisions/states to honour:

- **Warming/jitter state.** While the window transcribes (~1 s warm), do NOT stream
  partial sentences into the tappable list — they'd re-flow and the pre-selection
  would jump. Show a clear loading beat, reveal the **stable** sentence list only
  when the window is done. (The trim sheet sidestepped this because Audio mode had
  already transcribed before the sheet; Text inverts that ordering.)
- **Empty / failed window** (music intro, silence, foreign passage): the select
  screen has no markers to adjust → explicit empty state ("Couldn't find speech
  here — try Audio capture, or re-transcribe this chapter").
- **Place preservation on the normal select screen too** (not just the warming
  case): book pauses at capture; resume point stays the pre-capture position.
- **Pre-warm on book-open is NET-NEW.** Today `ensureLoaded()` fires on capture-
  FLOW open (after the tap, book already paused) — there's no warm on player-open.
  Build it: warm on opening a book in Text mode.
- **Mis-fused seam** → a "re-transcribe this chapter" path (rare, but captures
  cluster at boundaries).
- **A/B TEST INTEGRITY (do before testers touch it):**
  - **Assign** the arm for the test cohort — don't rely on opt-in (self-selection
    over-samples power users; we're testing the non-builder population).
  - **Pre-transcribe the test book** before the Text arm so the 35 s warming screen
    doesn't get blamed as "text is slow" (confound).
  - **Define the success metric** up front (capture completion rate / time-to-quote
    / abandonment) — "remove the loser" is otherwise subjective.
  - Acknowledge **polish asymmetry**: Audio is 2-day-matured (round-2 fixes); Text
    is v1. Keep that in mind reading results.
- **Net-new build surface** (none of this exists yet): `BookTranscript` sidecar +
  chunker (silence-cut + overlap + sentence-splice fusion, absolute→file-local time
  basis), playhead-window + backward-fill, preempt/re-warm wiring, pre-warm-on-open,
  the `TextCaptureView` + router, the Settings toggle, the transcribe-book button.
  Transcribe API takes **no time-range** → every chunk/window must be **exported to
  audio first** (`exportSpan` pattern) before the call. Chunk size/overlap must be
  chosen aware of FluidAudio's own internal ~15 s chunking.

## 12. UX-pass v2 (two design critics — resolutions applied to the mock)
Both critics independently caught the screen-2 purple-button misfire (a "please
wait" screen whose brightest control launched the whole-book job) and a cluster on
the Select screen. Rule adopted: **the brightest tappable element on a screen must
BE its single intended action — never a heavy detour, always present when one
exists.** Changes baked into `text-capture.html` v2:

- **Select interaction redesigned for discoverability.** Every unselected line is
  an obvious card with a **`+`**; tapping ANY of them extends the quote to cover it
  (not just immediate neighbours — kills "didn't know you could tap"). Selected end
  lines show a **`✕`** to drop (the shrink gesture now has a visible affordance —
  was cursor-only, invisible on touch). The pre-picked line is **sandwiched**
  between an add-able line above and the in-progress "playing here" line below (was
  stranded at the bottom over a dead "…still reading" line). The "…still reading"
  refusal is gone — the in-progress line is just add-able.
- **CTA teaches before it ships.** "Use as quote" starts **tonal/outline** and only
  goes solid-purple **after the first interaction**, so the sentence list wins the
  hierarchy until you've engaged (defuses confirm-and-leave-never-learning).
- **Instruction reworded** to match the pre-selected state + name both actions
  ("We grabbed the line you just heard — tap + to add the ones around it").
- **Footer de-cluttered:** removed the dead `✎ adjust on audio` link (v1-deferred,
  and "audio/fine-tune" is the vocab that confused testers); "Hear selection" is a
  tertiary text link, single primary button.
- **Place-preservation** reassurance ("● Paused here — your place is saved") now on
  the Select screen too (was only on Warming).
- **Warming (screen 2):** stripped to spinner + one line + "place saved"; the
  whole-book offer is a small **underlined text link at the bottom**, NOT a purple
  button.
- **Transcribe (screen 3):** the load-bearing message "**Keep listening — capture
  already works for the done parts**" is now the prominent lede (was buried under
  the %); % + bar demoted; explicit "Keep listening" + "Pause" (both secondary
  grey); "leave any time, keeps running" stated.
- **Settings (screen 4):** segment now defaults to **Audio** (matches §2; was
  wrongly showing Text selected). NB the real A/B arm is *assigned*, not this toggle
  (§11).
- **No-speech (screen 5):** primary is now **"Pick another moment"** (don't
  dead-end into the audio mode they may have fled); "use audio capture instead" is
  the secondary link.

## 13. UX-pass v3 (user review) + resumability
- **Select = scroll, not a button.** Dropped "↑ show earlier lines"; the sentence
  list just scrolls, earlier lines lazy-load (chunk-fill within the chapter) as you
  reach the top. Auto-scrolls the pre-picked line into view on open.
- **"Hear selection" plays the span from its start at 1.5×** (fast review — the
  whole reason quote-capture beats re-listening).
- **Removed the "your place is saved" reassurance** (both Warming and Select). The
  book is merely *paused* — reassuring against a non-threat invents a worry. (This
  overrides the earlier agent suggestion / §11 line — user's logic is better.)
- **No-speech (screen 5) minimised.** It is a rare edge (a 2-min window is almost
  never all music), and "switch to audio capture" was nonsense (audio can't quote
  music either). Reduced to a tiny fallback: "Nothing to quote here → Back to the
  book." Not a feature, just graceful handling of an empty/failed window.
- **Transcribe-book screen** now states the guidance: best overnight + plugged in,
  a per-hour time estimate (PLACEHOLDER "≈ 8 min/hr" — real per-device speed TBD
  on the phone, do NOT ship the number unmeasured), and "resumes where it left
  off."

### Resumability (whole-book transcription) — DECISION
The chunk sidecar **is** the resume state, because each chunk is saved as it
finishes. On any interruption (unplugged, app crash, force-quit, OS jetsam):
- completed+saved chunks survive;
- the single **in-flight chunk that didn't finish saving is discarded** and
  re-transcribed from the last saved boundary (idempotent per chunk — user's
  "delete the last half-chunk and go again");
- the job is **resumable** on next launch / re-plug;
- **pause when unplugged, auto-resume on re-plug** (it's the overnight/charger
  job — don't drain battery silently). A foreground "Pause / Keep listening"
  control is also offered.
No partial chunk is ever half-written into the usable transcript (atomic
append-after-complete), so a capture never reads a torn chunk.

## 10. Process
- **Mock first** (locked process), sign-off, then build.
- **Mobile-first** (the player + capture live on the phone). NB: the capture
  design mocks historically live in `Skrift_Native/SkriftDesktop/mocks/`.

## 14. Device walkthrough 2026-06-13 — flow fixes + open items
PASSED on device: pill fix (new memos land ✓), +/✕ "worked well", pre-pick+extend
"feels natural", warm capture "really nice", start-of-chapter, Models tab.

FIXED (commit — no double-select + no re-transcribe):
- **Double sentence-select KILLED.** Text mode no longer re-transcribes on confirm and
  no longer shows the trim sheet (you already picked sentences). `QuoteCaptureProcessor.
  buildOutput` carves the quote straight from the window selection; `CaptureSheetView`
  `skipTrim` renders the quote read-only and opens straight at record-your-thoughts +
  significance. Audio mode unchanged (keeps trim).
- **Cut the "Hear selection · 1.5×" preview** — didn't play on device + user lukewarm
  ("if you can read it, maybe you don't need to hear it"). Text mode is read-not-listen.

OPEN (next):
- **Share sheet: typing sucks ("typing is for caveman").** Voice dictation ALREADY
  exists in the share extension (`ShareDictationRecorder`, the mic on the annotation
  field) but the user went straight to typing and never found it. Fix = DISCOVERABILITY:
  make voice-record the prominent/primary affordance in the share sheet, typing
  secondary. (Extension change + device build.)
- **Custom vocab still spelled "Script", NOT corrected — UNCONFIRMED, not yet a bug.**
  Both test recordings were still transcribing while the ctc110m model loaded in the
  background (the new non-blocking behaviour), so NEITHER was boosted. Needs a clean
  re-test: confirm the custom-word model shows downloaded in Models tab, THEN record
  saying the word — the 2nd+ recording should correct. If it STILL says "Script" with
  the model loaded, it's a real booster-efficacy bug (CTC spotter not catching
  Script→Skrift) to investigate.
