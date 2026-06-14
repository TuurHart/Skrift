# Skrift — Conversation + Name-Linking Pipeline: WILD bug-hunt & fix

> Paste this as the opening message of a NEW chat. Mission: trace the WHOLE
> conversation/diarization → name-linking → Obsidian-export pipeline across BOTH apps,
> find **every** bug like the ones below, root-cause each, and fix them *really well*.
> The user's words: "go WILD, find all the bugs like this, trace everything, spend all
> the tokens — I want this fixed really good."

## READ FIRST
- `CLAUDE.md` — build/run, hard rules, **dev/prod data safety** (build+install the **DEV**
  build to test; NEVER clobber prod mid-use). We live on **`main`** now (the trunk).
- **`CONVERSATION_MODE_HANDOFF.md`** — the conversation/diarization + voice-identity design
  ledger. **START HERE** — it has the locked design (Sortformer diarize + wespeaker
  embedding-cosine, measured 0.5 threshold) + current status + the mandatory codebase-read step.
- `FEATURES.md` (feature × app × file × status) and `backlog.md` (live ledger).

## USE ULTRACODE
Author and run **Workflows** for this — it's exactly the job they're for: fan out parallel
agents per pipeline stage to trace, then **adversarially verify** each suspected bug with
independent skeptics before declaring it real, and **loop until the trace is dry** (K rounds
with nothing new). Don't solo it; orchestrate. Token cost is not a constraint — correctness is.
Run separate workflows per phase (understand → fix → verify) so you stay in the loop.

## THE EVIDENCE (a real synced conversation memo, rendered on the Mac)
A two-person memo (Tiuri + Roksana) recorded in **conversation/diarization mode on the phone**,
synced to the Mac, name-linked + enhanced, exported to Obsidian. Defects observed in the output:

1. **Over-canonicalization of names.** EVERY name mention is replaced with a full
   `[[Canonical Name]]` wikilink — *including the spoken form*. The joke "We are **Tuur** and
   **Tuur** rocks" rendered as "We are [[Tiuri Hartog]] and … rocks" — the actually-spoken
   "Tuur" is GONE, replaced by the canonical display. Likely wrong: should preserve what was
   said (e.g. `[[Tiuri Hartog|Tuur]]` alias display) and/or link **first-mention-only**, not
   nuke the spoken word on every occurrence.
2. **Speaker labels all full canonical** — every turn header is `**[[Roksana Gurova]]:**` /
   `**[[Tiuri Hartog]]:**`. Decide if that's wanted or noisy.
3. **Diarization fragmentation** — consecutive utterances by the SAME speaker are split into
   many tiny separate turns ("**[[Tiuri Hartog]]:** But what" / "**[[Tiuri Hartog]]:** we're
   actually doing is") instead of merged into one turn.
4. **Speaker mis-attribution** — the single sentence "We are Tuur and Tuur rocks" got split
   across TWO speakers (Roksana: "We are [[Tiuri Hartog]] and"; Tiuri: "rocks and this is the
   first memo…"). Turn boundaries / speaker assignment look wrong.
5. **Open question — answer it in code:** if the user **re-transcribes** this memo on the Mac,
   does it PRESERVE the phone's diarization/turns or re-run ASR and DESTROY them? (Trust rule:
   `transcriptUserEdited || transcriptConfidence ≥ 0.7` → ASR skipped.) Is re-transcribe even
   exposed on desktop? What's the correct behavior?

## TRACE EVERY STAGE (cite file:line at each; both apps)
- **Phone capture (`SkriftMobile`)** — conversation/diarization mode: how speaker turns are
  produced (Sortformer + embedding-cosine), what's written into the transcript/markers.
- **Upload contract** — what the phone SENDS for a diarized memo (how are speaker turns encoded
  in the RAW transcript? a field? markers?). Verify **byte-compat both directions** (handoffs §4:
  multipart `POST /api/files/upload`, RAW transcript, never `sanitised`).
- **Mac ingest (`SkriftDesktop` UploadService / BatchRunner)** — how the diarized transcript is
  parsed; is anything lost or reinterpreted?
- **Name-linking (`Sanitiser` + `NamesStore`)** — occurrence policy (every vs first),
  replace-vs-alias, fuzzy/partial matching (is "Tuur"→canonical correct or over-eager? does it
  ever link common words?), significance/confidence gating, and how SPEAKER labels get linked
  vs INLINE mentions.
- **Conversation rendering → markdown** — turn formatting, **missing same-speaker merge**,
  speaker→name mapping, voice-identity → canonical-name resolution.
- **Obsidian export (`VaultExporter`)** — final markdown, alias syntax, anything mangled.

## FOR EACH BUG
Root-cause (file:line) → fix → **gate** → **commit per fix** → update `FEATURES.md` + `backlog.md`
in the same commit. Mock-first for any UI change (locked process).
- Desktop gate: `xcodebuild test -scheme UnitTests -destination 'platform=macOS'` (fast, MLX-free);
  `xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation` (full).
- Validate behavior headlessly: `<app binary> -runfile <audio> [-transcript <txt>] [-vault <path>]`
  (quit the running app first — a 2nd instance races the shared SwiftData store). Two-friends-both-"Jack"
  fixture: `test-fixtures/Hotel Du Vin.m4a`. A diarized fixture would help — capture/synthesize one.
- Mobile gate: iPhone 17 sim unit suite (`-only-testing:SkriftMobileTests`) + device eyeball
  (UDID in CLAUDE.md). Hardware-flavored bugs: instrument via `DevLog` and pull the trace.

## DECISIONS TO GET FROM THE USER (they have strong taste — ask, mock if UI)
- **Name-link display:** spoken-preserving alias `[[Canonical|Tuur]]` vs first-mention-only vs
  current replace-all? (Their reaction to current: "fucks it up" — they do NOT want the spoken
  word destroyed.)
- **Merge consecutive same-speaker turns?** (Almost certainly yes — confirm.)
- **Re-transcribe a diarized memo:** preserve diarization (skip re-ASR) / warn / disable?

## CONTEXT
On **`main`** (native folded in + pushed 2026-06-14). Prod Mac app rebuilt from `main` today.
Mobile **build 1** is live on **TestFlight** (internal). Conversation/diarization + voice identity
is the **current focus** (CLAUDE.md). Data safety: test on the DEV build only; never rebuild prod
mid-use. **Deliverable:** a corrected pipeline — every bug found, root-caused, fixed, gated,
committed — plus a crisp report of what was broken and how each was fixed.
