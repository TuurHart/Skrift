# STANDALONE_PLAN.md — Skrift mobile → standalone App Store app

The plan to ship **SkriftMobile to the App Store as a full-fledged, standalone audiobook +
notetaking app** that works great with **no Mac required** — while keeping the Mac (and Obsidian)
as optional power-ups, not requirements.

> Companion ledger: tick items off in `backlog.md` (`## ⭐ Standalone App Store push`). Update
> `FEATURES.md` whenever a feature lands. Branch: **`standalone`** (off `main`, 2026-06-15).

---

## North star

Today the **phone captures** and the **Mac makes it nice** — AI cleanup, name-linking, tagging,
and *all* export live only on the desktop. A phone-only memo (the default; `significance == 0`
never leaves the device) is raw transcript + audio + photos + sensor metadata, editable and
searchable, but **the only way out is copy-to-clipboard.** Standalone = close that gap and pile on
the polish that makes a $0.69 notes+audiobook app worth buying.

The realisation that makes this not-a-fork: **the phone becomes the full app; the Mac and Obsidian
become optional output sinks over one source of truth.** Same architecture whichever way a user
leans, so we can't bet wrong.

---

## Locked decisions (user sign-off, 2026-06-15)

1. **Price: $0.69 one-time. NO in-app purchases.** → no subscription/Pro tier, no StoreKit
   subscription plumbing. Critically: with no recurring revenue we **cannot afford per-use cloud
   LLM cost**, so all intelligence is on-device/free-Apple — which *is* the privacy story. (Tradeoff
   to accept: a flat paid app with no IAP **cannot offer a free trial** on the App Store.)
2. **Scope = full vision for v1.** Build the whole thing before first release. (A recommended build
   order + an "earliest-shippable" gate is marked below, in case we ever want to ship sooner.)
3. **Internal sync = CloudKit** (SwiftData CloudKit mode), NOT iCloud-Drive file sync. This is what
   makes "my notes on all my devices" reliable with **no `filename 2.md` conflict copies**.
4. **On-device Polish = a gated spike.** User leaning Gemma over Apple, but "better no model than an
   unreliable one." So: build the eval harness, measure on the **real iPhone 13**, ship polish only
   if it clears a hard memory + quality bar — otherwise no-polish (Mac / 15 Pro+ still polish).
5. **Three coexisting modes, one architecture:** standalone / standalone+Obsidian / paired-with-Mac.
   The existing Mac sync stays byte-compatible and becomes opt-in.

---

## The architecture spine — one source of truth, fan-out sinks

```
                         ┌──────────────────────────────┐
   Record / Import  ──▶  │  SwiftData (CloudKit-mirrored)│  ◀── device↔device sync (always on)
                         │        = SOURCE OF TRUTH       │
                         └───────────────┬───────────────┘
                                         │  read-only fan-out
              ┌──────────────────────────┼──────────────────────────┐
              ▼                          ▼                          ▼
   ObsidianPublisher              MacTransport (existing)       (future sinks)
   one-way, create-only           Bonjour + HTTP, opt-in
   security-scoped bookmark       Services/Sync/* (unchanged)
```

| Mode | CloudKit | Obsidian publish | Mac transport |
|---|---|---|---|
| **Standalone** | on (or local-only if no iCloud) | off | off |
| **Standalone + Obsidian** | on | on (vault folder set) | off |
| **Paired with Mac** | on | optional | on (Bonjour paired) |

All three are **independent toggles over the same store** — mirroring how
`MacTransportFactory.make()` (`Services/Sync/MacTransport.swift:82-97`) already returns
Disconnected / URLSession / Mock by config. CloudKit syncs *your own devices*; the Mac is
*processing/enhancement*; they don't fight (a memo made on iPhone shows on iPad via CloudKit, and
when a Mac is later paired it uploads via the unchanged multipart contract).

### Cross-app consistency — no drift (user requirement)

Concern: features that live on BOTH apps and are synced must not drift out of step (update one,
forget the other → mismatch + errors). Two guarantees handle this:

- **Shared CODE, not parallel copies.** Anything both apps must agree on — name-linking, markdown
  compile, tag matching, the names data types, the contract DTOs — lives in the **`SkriftPipelineKit`
  package** (Phase 0). There is ONE copy; you can't update one app's linker without the other's. This
  retires today's verbatim duplication (`NamesData.swift` is hand-copied between the apps — exactly
  the drift trap). Wire/byte compatibility stays covered by the existing fixtures
  (`CAPTURE_CONTRACT.md`, `NamesSyncRoundTripTests`).
- **Deterministic re-derivation, not "who already did it".** Name-linking is deterministic over the
  synced names DB. So the phone links for its own display + export **and still sends RAW to the Mac**
  (contract spine unchanged); the Mac re-links RAW with the *same code over the same names DB* →
  **identical** links. The Mac therefore needs **no "phone already linked" flag**, and there's **no
  double-linking**. Re-deriving is strictly safer than shipping linked text + a skip-signal that could
  be missed. (Same idea covers tags/compile: re-derive from the shared package, don't trust a
  one-sided "done" bit.)

---

## Portability map — what Mac pipeline code moves on-device

From a full read of `SkriftDesktop/`. The pure stages **don't** depend on the SwiftData `@Model`;
they take plain value types — so most of the "make it nice" pipeline is portable.

| Stage | File | Class | Effort | Standalone use |
|---|---|---|---|---|
| **Sanitiser / name-linking** | `Pipeline/Sanitisation/Sanitiser.swift` | **PURE-PORTABLE** (Foundation regex only) | **S** | Phone already owns `Person`/`NamesMerge`/`SpeakerTranscript`; bring `AmbiguousOccurrence`/`NameCandidate` (~16 lines). Enables `[[Name]]` links in standalone export. |
| **Compiler → Obsidian MD** | `Pipeline/Export/Compiler.swift` | PURE logic, adapt seam | **S–M** | Refactor `compile(file: PipelineFile)` → a neutral input DTO; then both apps reuse it. Ships `QuoteProtection`. |
| **TagMatcher** (NLTagger lemma + `#tags`) | `Pipeline/Tags/TagMatcher.swift` | NEEDS-ADAPTATION (NaturalLanguage is on iOS) | **S–M** | On-device tag suggestion. Vault tag whitelist (`VaultTagScanner`) stays Mac-only (privacy) → sync the whitelist. |
| **QuoteProtection / ImageMarkerReinsert** | `Pipeline/Enhancement/*` | PURE-PORTABLE | **S** | Wrap every on-device polish engine; byte-protect audiobook `> ` quotes + `[[img_NNN]]`. |
| **VaultExporter** | `Pipeline/Export/VaultExporter.swift` | filesystem/vault-bound | N/A | Mac-only by design; the phone uses its own `ObsidianPublisher` (Phase 2). Only the pure `convertImageMarkers` string transform is reusable. |
| **EnhancementService (Gemma/MLX)** | `Engines/EnhancementService.swift` | **NEEDS-A-MODEL** | **L** | ~9 GB Gemma E4B can't fit a phone. On-device polish = adaptive engine (Phase 4); the *prompts* + guard wrappers port verbatim. |

**→ Phase 0 stands up a shared `SkriftPipelineKit` Swift package** with the pure stages + shared
value types, retiring the verbatim `NamesData.swift` duplication (`SkriftDesktop/Models/NamesData.swift:1-7`
is an explicit copy of the mobile file). MLX engine + VaultExporter stay platform-specific behind
the existing `Enhancing` protocol.

---

## On-device LLM reality (drives Phase 4)

**Apple Foundation Models (free, on-device, ~3B, ANE, zero app-memory cost) requires Apple
Intelligence = A17 Pro / iPhone 15 Pro and newer.** The whole iPhone 13/14/15-non-Pro span — our
stated floor — **can't use it.** And a bundled MLX model has to share RAM with the always-resident
Parakeet (~600 MB) inside iOS's jetsam ceiling (~2–2.3 GB on a 4 GB iPhone 13).

| iPhone | Chip / RAM | Apple FM? | Bundled small LLM (4-bit) + Parakeet |
|---|---|---|---|
| 13 / 13 Pro | A15 · 4/6 GB | **No** | 4 GB = no-polish, period. 6 GB = only ~1–1.5B class, risky. |
| 14 / 15 (non-Pro) | A15/A16 · 6 GB | **No** | ~1–1.5B class only (Qwen2.5-1.5B / Llama-3.2-1B). |
| **15 Pro** + 16/17 | A17 Pro+ · 8 GB+ | **Yes** | FM (no footprint) is the win. |

**Adaptive engine design (Phase 4b):**

| Tier | When | Engine | Footprint |
|---|---|---|---|
| **A — FM** | iOS 26 + `SystemLanguageModel.isAvailable` (15 Pro+) | Apple Foundation Models | ~0 (system/ANE) — **best default** |
| **B — Mac offload** | a Mac is paired & reachable | defer to Mac (current contract) | 0 |
| **C — bundled small** | 6 GB+, no FM, no Mac, **opt-in** | MLX Qwen2.5-1.5B-4bit, **ASR unloaded first** | ~1 GB peak |
| **D — no-polish** | 4 GB, or declined, or memory-pressure | identity passthrough (tidy whitespace) | 0 — **fully acceptable ship state** |

Honest expected outcome: **FM for 15 Pro+, Mac-offload when paired, no-polish RAW everywhere else**,
with Tier C only if the 6 GB iPhone 13 cleanly clears the memory gate (the single most likely thing
to fail). RAW transcript stays the source of truth + the Mac payload regardless; polish is a local
display layer. Always wrap engines in `QuoteProtection` + `ImageMarkerReinsert`. FM is
availability-gated (`#available(iOS 26)`), **no forced min-target bump** that would drop devices.

**The Models tab is the home for this** (existing `Features/Settings/ModelsView.swift` +
`ModelInventory.swift`, today read-only). Extend it from read-only to **managed**, with a
**device-gated model picker**: a dropdown that only offers what the device can actually run — "Apple
built-in" on 15 Pro+ (no download), downloadable small models on 6 GB+, "None / raw" on 4 GB — each
row showing size-on-disk + a RAM-headroom note, defaulting to the recommended option, with
download/delete actions. The picker is just the UI surface over the Phase-4b capability probe; the
spike sets the default per tier. **iPad is the upside (user insight):** M-series iPads (Apple
Intelligence on M1+, 8–16 GB RAM) clear the memory gate the iPhone 13 can't, so the same picker
offers them **bigger/better models (up to Gemma-E4B-class)** — making iPad the strongest
standalone-polish device. (Apple Intelligence/FM also runs on M-series iPads, so iPad gets Tier A
*and* a larger Tier-C option.)

---

## Phases

Build order = top to bottom; **commit per chunk, verify each chunk** (iPhone 17 sim build+test;
DEV build on the real 13 for hardware/memory/ASR). Phases 0–3 = the **standalone-capable core**
(the "earliest-shippable" gate, if we ever ship before the full vision). 4–11 = the full-vision pile.

### Phase 0 — shared naming engine (`Skrift_Native/Shared/Naming/`)  · ✅ DONE 2026-06-17

**✅ DONE 2026-06-17** — commits `ea3eeed` (0a) · `faece91` (0b) · `71cd8d2` (0c), branch `standalone`.
**Mechanism = shared source folder, NOT an SPM package** (decided from the data: ~50 files consume these
types, so a folder — one physical copy compiled into each app's own module — gives the identical "single
source, can't drift" guarantee with **zero** `import`/access churn; keep-it-simple). `Skrift_Native/Shared/
Naming/` now holds: `NamesData` (Person/NamesMerge/VoiceEmbedding), `NameMatch` (AmbiguousOccurrence/
NameCandidate), `NameStoplist`, `QuoteProtection`, `Sanitiser` — wired via each `project.yml` into the
mobile app target + the desktop app & host-less test bundle. **Stayed desktop-side** (not needed for the
phone's linking): `RosterAudit` (`affectedFiles` is `PipelineFile`-bound), `NamesStore`, `PeopleFolderScanner`.
**Mobile `SpeakerTranscript`** gained the line-anchored `headerPattern` + `parseWithPreamble` (aligned to
desktop so the shared engine's conversation parse is identical). **Gate met:** desktop UnitTests 288 +
mobile SkriftMobileTests 400 green; canonical byte-identical to both pre-move originals; a mobile
`SanitiserSmokeTests` proves the engine *executes* on iOS. **`Compiler`/DTO extraction deferred to Phase 2.**

_Original plan (for reference):_

Extract the **post-rework deterministic name-linking engine** (`NAMING_MODEL.md`, 2026-06-16) + the
shared value types into one Swift package both apps compile — the "single source, can't drift"
guarantee, which also retires the verbatim `NamesData.swift` duplication. **Re-scoped 2026-06-16**
after a phone audit: the engine is what just changed *and* what the phone needs first; `Compiler`/DTO
extraction moves to **Phase 2** (build it when on-device export actually needs it, not before).

Phone reality (audit): the phone does **zero** on-device linking today (sends RAW) but already carries
the name *data* — `Person`/`NamesData` byte-identical to desktop, `NamesStore` (local `names.json`, no
vault), and `SpeakerTranscript.parse`. So Phase 0 *gives it the engine for the first time*; the gap is
tiny.

- **Into the package:**
  - **Value types** — `Person` + `VoiceEmbedding` + `NamesMerge` (make `keyName` non-`private`);
    `SpeakerTranscript` (PURE `parse` + `parseWithPreamble` + `mergeAdjacentTurns`, split out of the
    phone's UI-coupled `SpeakerTurnsView` + the desktop's `Diarizing`); `AmbiguousOccurrence` +
    `NameCandidate` (today in desktop `PipelineFile.swift:24-39`).
  - **Engine** — `Sanitiser` (`process` + `processConversation` + `Overrides` + unlink/relink), the
    opt-out/risk-tier guards `NameStoplist` + `RosterAudit`, and `QuoteProtection` (its
    `splitLeadingQuote` is used by `Sanitiser.nonProseRanges`).
  - **Tests** — `SanitiserTests`, `RosterAuditTests`, `NamingGoldenTests`, the relevant `NamesTests`.
- **Phone deltas to close (small — substrate exists):** (a) `NamesMerge.keyName` `private`→accessible
  (`SkriftMobile/Models/NamesData.swift:93`); (b) add `SpeakerTranscript.parseWithPreamble` (phone has
  `parse` only); (c) slim `SkriftMobile/Models/NamesData.swift` to import the shared `Person`/`NamesMerge`
  (verify field-identical first, then unify — strictly *better* for the byte-compat contract).
- **Keep OUT / not Phase 0:** `Compiler` + DTO (→ Phase 2), `TagMatcher` (→ later), `VaultExporter`
  (Mac-only FS), MLX `EnhancementService` (behind `Enhancing`, → Phase 4), `People/`-folder roster
  seeding (Mac-vault-only — the phone's roster is just `names.json`).
- **Scope guardrail (engine-only):** Phase 0 makes the engine *compile + test green* on both apps. It
  does NOT add `Memo` fields (`namePicks`/`unlinkedNames`/`sanitised`/`ambiguousNames`), NOT wire the
  engine into the phone's flow, NOT touch the sync contract, NOT build link UI. Wiring + the `Memo`
  fields + the 3-tier dotted/linked review UI land in **Phase 2** (mock first).
- **Gate:** desktop `UnitTests` + full `-skipMacroValidation` build green; mobile `xcodebuild test`
  (iPhone 17 sim) green; package tests green; a golden test pinning `Sanitiser` output byte-identical
  to today on a known fixture (zero behavior change for the Mac).

### Design system — `SkriftDesignKit` (tokens, not a library)  *(Phase 2; user-confirmed 2026-06-17)*

Cross-app **UI** consistency uses the same "single source" idea as the code — but at the **token** level,
NOT a full component library. A small SPM package **`SkriftDesignKit`** holds shared design tokens (colors
incl. the naming tiers `nameLink`/`nameSuggest`, type scale, spacing, significance colors) + a few
genuinely-portable SwiftUI components (e.g. `SignificanceCircles`, tier-colored name text). Both apps read
from it → the phone's naming-review UI *looks like* the Mac's even though its layout adapts to the small
screen. Platform-divergent surfaces (the `NSTextView` body editor, popover-vs-sheet, hover-vs-touch) stay
per-app but draw from the tokens. Introduced when the first cross-app UI lands (**Phase 2** — export sheet /
naming review); the **phone naming-review mock is a Phase 2 mock**, adapted from the Mac's `naming-review.html`.
A full unify-every-screen library is rejected (high churn, diminishing returns) — the package is only for the
small new design-system code where a module actually pays off. (Note: a real SPM *package* fits here — few
consumers, new code — unlike the naming engine, where the ~50-consumer surface made a shared folder the right
call.)

### Phase 1 — CloudKit internal sync ("my notes on all my devices")  · effort L
- `Models/Memo.swift:34` — **drop `@Attribute(.unique)` from `id`** (CloudKit forbids it); keep the
  UUID default; enforce uniqueness in-app. Fix `CaptureInbox`/`CaptureInboxDrainer` to dedup
  manually via `NotesRepository.memo(id:)` (they relied on the unique constraint).
- `Services/NotesRepository.swift:13-21` — add
  `cloudKitDatabase: inMemory ? .none : .private("iCloud.com.skrift.mobile{.dev}")`. `.none` keeps
  the `-inMemoryStore` UI/unit test path offline + deterministic.
- Entitlements + `project.yml` — add iCloud/CloudKit container + remote-notifications (push),
  **per-config** (dev/prod split, like the App Group). **One-time Xcode "Signing & Capabilities"
  visit per target** — `-allowProvisioningUpdates` registers IDs but can't add a capability
  (CAPTURE_CONTRACT lesson). Keep entitlement values literal (no `$(VAR)`).
- **Media files** (`.m4a`/photos are loose files, don't sync with the row): new
  `@Model MemoAsset { memoID, kind, filename, blob: Data }` (SwiftData mirrors `Data > 1 MB` as a
  **CKAsset**) + an `AssetMaterializer` that writes the blob back to
  `Documents/recordings/<filename>` on first access → **all filename-based code stays unchanged**
  (`Memo.audioURL:138`, photo load, playback, export).
- **Audiobooks:** migrate audiobook *state* (library entries, resume position, rate, bookmarks,
  `BookTranscript` sidecar) → SwiftData `@Model`s for CloudKit; audiobook **audio stays
  device-local** (`Audiobook.swift:12` "books never sync" invariant — quota). Result: start on
  iPhone, resume position on iPad, each device holds its own copy of the audio.
- **Account-state fallback:** no iCloud / iCloud Drive off → degrade to pure-local SwiftData, zero
  behavior change. Settings toggle "Sync across my devices (iCloud)" default on.
- **Gotchas:** additive-only schema + explicit **Production promotion in CloudKit Dashboard**;
  first-sync/large-asset latency UI ("row present, audio materializing"); main-actor mutations only;
  soft-delete/`deletedAt` propagates as normal LWW; keep the startup purge idempotent.
- **Significance does NOT gate CloudKit** — every memo (incl. significance 0) syncs to your own
  devices unconditionally.

### Phase 2 — Export & Obsidian publish (the #1 table-stakes)  · effort L · needs Phase 0
- New `Services/Export/MemoExporter.swift`: `Memo → {Markdown (Obsidian frontmatter, `[[img_NNN]]`→
  embed), plain txt, PDF, quote-card image}` reusing the Phase-0 `Compiler` (via DTO) + `ImageMarkers`.
- New `ObsidianPublisher` (one-way, create-only):
  - User picks the vault folder once → persist a **security-scoped bookmark** (precedent:
    `MemoSaver.swift:61`, `AudiobookImporter.swift:99`); resolve stale bookmarks by re-prompting.
  - Always write under a dedicated **`<vault>/Skrift/`** subfolder (`Skrift/Voice Memos/`,
    `Skrift/Audiobook Quotes/`) — Skrift owns it, never touches hand-authored notes.
  - Per-memo export identity on `Memo` (additive/defaulted → CloudKit + SwiftData clean):
    `exportRelativePath: String?`, `exportedContentHash: String?`, `exportedAt: Date?`. Sticky path
    → re-export overwrites **only its own file** (single owner per file = no conflict copy).
    Content-hash idempotency → skip unchanged (no needless iCloud churn).
  - Atomic + `NSFileCoordinator` writes (Obsidian/iCloud never see a half-written `.md`).
- New `PublishCoordinator` (peer to `SyncCoordinator`) fanning the store out to configured sinks.
- UI: `ShareLink`/activity sheet into `MemoDetailView.swift:128-133` confirmationDialog ("Share…",
  "Export to Obsidian"); batch "Export selected" in `MemosListView` selection bar `:394-407`;
  Settings "Export" section (default format, vault folder, include-audio, publish-all vs important-only).
- **On-device name-linking — YES (resolved).** Run the Phase-0 `Sanitiser` over the on-device
  `names.json` **automatically after transcription** (no extra UI for the linking itself — it just
  runs, like the Mac does), so the phone's display + standalone Obsidian export get `[[Name]]` links.
  **Phone still sends RAW to the Mac** — the Mac re-links identically (see "Cross-app consistency").
  Add **alias management UI in Settings → Names & voices, mirroring the Mac** (alias add/edit/delete —
  today the phone is voice-first with no alias editing); it syncs via the existing NamesData LWW.
  Ambiguous-name resolution (the Mac's "two Jacks" resolver) can mirror later — v1 may leave ambiguous
  mentions unlinked.
- **Paired-mode export:** when a Mac is paired, default the Obsidian export to the **Mac** (it has the
  enhanced text) and keep the phone's publish off, so two writers don't race the same note —
  user-toggleable. Per-memo file ownership + content-hash idempotency make a stray double-write
  harmless anyway.
- **Privacy (hard rule):** write-only into the chosen folder; never scan/read vault contents.

### Phase 3 — De-Mac the UX (Mac = opt-in power-up)  · effort M · needs Phase 1
Gate ~6 Mac-leading surfaces behind `MacConnection.load() != nil` or an opt-in flag (service layer
needs no change — `MacTransportFactory` already no-ops when unpaired):
- `OnboardingView.swift:28` tagline ("synced to your Mac" → standalone value prop); `:39-47,145-150`
  pair card + `discovery.start()` Bonjour (demote to optional "Connect a Mac (advanced)", gate the
  scan behind opt-in).
- `SettingsView.swift:46-76` — the Mac section is currently *first*; demote/hide until opted in.
- `MemosListView.swift:294-303` sync button + `:338-339` "Pair a Mac" banner — hide unless paired.
- Significance UI — relabel as importance/pin (see significance reframe below).
- New standalone onboarding: on-device record+transcribe value prop → "Sync across devices (iCloud)"
  → optional Mac.
- **Navigation / IA decision (NEW, folded in 2026-06-19 from device testing).** Today the audiobook
  Library is a top-bar button opening a `.sheet` (`MemosListView:130`) — it feels secondary (pull-to-
  refresh just dismisses it) yet the vision treats notes AND books as co-equal ("second brain +
  audiobook commonplace book"). Decide the home: a **tab bar** (Notes · Library · Highlights · Settings)
  is the natural fix — makes both first-class, kills the dismiss-on-pulldown bug, and is where the
  Phase-6 Highlights tab lives anyway. Mock-first; this is foundational and overlaps Phase 6. (Detail +
  the smaller library bugs — one-swipe delete needs a confirm — in `backlog.md` "Audiobook player
  reading-experience redesign".)

### Phase 4 — On-device Polish (GATED by spike)  · effort L · highest risk · needs Phase 0
**4a — SPIKE FIRST (the gate).** Throwaway harness (or hidden DEBUG screen): load **Parakeet first**
(reproduce co-residency), test both co-resident AND unload-then-load; reuse the Mac prompts
(`AppSettings.Prompts.defaultCopyEdit/Title/Summary`); fixtures = 8–12 **real raw transcripts**
(≥2 EN↔NL code-switch, 1 long ≥1k tokens, 1 with `[[img]]`, 1 audiobook `> ` quote); candidates
Qwen2.5-1.5B-4bit → Llama-3.2-1B-4bit → (ceiling check) Qwen-3B / Gemma-E2B. **Run on the real
iPhone 13** (DEV build; confirm 4 GB vs 6 GB variant). Measure: peak memory (**zero jetsam incl. a
photos-open run, ≥300 MB headroom** — hard gate), latency, quality vs the Mac's Gemma output,
**no NL→EN translation / no meaning change**, marker/quote byte-pass (100%). **Decision rule:** ship
Tier C only if all gates pass; else ship Tier D no-polish for that device class.

**4b — Adaptive `EnhancementEngine`** (mirror the Mac `Enhancing` protocol): Tier A Apple Foundation
Models (`#available iOS 26` + `SystemLanguageModel.isAvailable`), Tier B Mac-offload when paired,
Tier C bundled small MLX (6 GB+, opt-in, **unload ASR before loading LLM**, memory-pressure abort →
return RAW), Tier D no-polish identity. Always wrap in `QuoteProtection` + `ImageMarkerReinsert`.
RAW stays source of truth + uploaded to Mac.

**4c — AudioPen-style "Clean up my ramble" modes:** selectable output presets (note / bullets /
email / to-do), each a saved prompt; surfaced on mobile. The differentiator vs Voice Memos.

**4d — Models tab = the picker (UI for 4b).** Extend Settings → Models (`ModelsView.swift` /
`ModelInventory.swift`) from read-only to **managed**: a **device-gated dropdown** offering only
run-able engines (Apple built-in / downloadable small model / None-raw), size-on-disk + RAM note per
row, download/delete, default = the spike-recommended option for the device. iPad (M-series) is
offered the larger models the iPhone 13 can't run — the same picker, more options.

**Confirmed + verified (2026-06-15):**
- **Polish behavior = title + summary + copy-edit** (the Mac's three ops, same prompts). Locked.
- **VERIFIED from code:** the phone↔Mac transport only `uploadMemo` / `listFilenames` / `health` +
  names sync — **the Mac never pushes polished/enhanced text back to the phone** (the phone has no
  concept of enhanced text). So pairing a Mac polishes the *vault*, NOT the phone's copy. Therefore on
  non-Apple-Intelligence devices the honest reality is **raw transcript** (today's behavior); polish
  comes only from Apple Intelligence (15 Pro+/M-series) or (maybe) the spike-gated bundled model.
- **Possible NEW feature (deferred, rec NO for v1):** "Mac polishes → pushes the result back to the
  phone" so a paired iPhone 13 shows polished memos. Net-new (Mac→phone enhanced push, contract
  addition). Revisit later if missed.

**PARKED (2026-06-15):** the **title-presentation UI on mobile** is unresolved — the desktop's
"Suggested vs From-recording" two-card chooser doesn't work on a phone (cramped/awkward). The
`standalone-models-polish` mock is **on hold** until that interaction is figured out. Engine design
+ Polish behavior above are NOT parked — only the title-UI + the mock.

### Phase 5 — Organization  · effort M  *(steal: Apple Notes, Bear)*
Pins (flag + pinned cluster above list); folders/notebooks (assign on save; a folder = an Obsidian
export subfolder); **navigable nested tags** (`#book/quotes` tree, tap-to-filter — tags already
exist, just make them navigation); smart folders (saved searches over significance / source /
has-photo / tag / date — all metadata already captured).

### Phase 6 — Commonplace Book / Highlights  · effort M–L  *(steal: Readwise, Snipd, Kindle)* — the headline differentiator
- **Highlights tab:** quote-captures + significant memos in one searchable/taggable feed, grouped by
  book/source; the user's **voice ramble surfaced as the annotation** (data already exists).
- **Daily Review** resurfacing (on-device, spaced-repetition-ish) — retention hook; *this is the
  app's north star ("see how my thinking evolved") in embryo*.
- **Shareable quote cards** (`ImageRenderer`: quote + book + author + cover tint via
  `UIImage.averageColor`) — the App-Store virality lever.
- Snipd-style instant auto-transcribe + one-line auto-title of a capture.
- Readwise-style per-source highlight `.md` export (append-update, not duplicate) — folds into Phase 2.

### Phase 7 — People & backlinks  · effort M  *(steal: Reflect, Obsidian)*
People tab: a person page = profile + voice sample + every memo mentioning them; **linked /
unlinked mentions** panel (one-tap to link). Uses Phase-0 `Sanitiser` + the names DB + voice
enrollment — near-free given the substrate already exists.

### Phase 8 — Journal & retrieval  · effort L  *(steal: Day One, Mem/Reflect)*
**On This Day** (memos from this date in prior years — pure presentation over existing timestamps);
**map view** (geotagged memos); calendar/timeline view; **semantic "Related notes" + search** via
on-device text embeddings (`NLContextualEmbedding`) — the north-star backbone, offline-reachable.

### Phase 9 — Audiobook player polish  · effort M  *(steal: Audible, Apple Books, Spotify)*
**9a — Reading-experience redesign (NEW, the 2026-06-19 feedback batch; mock-first — see `backlog.md`
"Audiobook player reading-experience redesign").** Organizing idea = **"reading mode": less chrome, more
page.** Compress the header (drop "NOW PLAYING"); accent-the-now-don't-hide-the-rest read-along with free
scroll + "back to playing" + more text real estate; adjustable font size (+ line-spacing/theme later);
margin-marker bookmarks + fix the Chapters/Bookmarks model (add = action, sheet = browse-only); floating
play button (consistency w/ the memo); shrink + rename "Capture this" → "Add note". *(The cheap, IA-
adjacent wins overlap Phase 3's navigation decision — see there.)*
**9b — Player polish (original):** Sleep timer incl. **end-of-chapter** + fade; per-book speed memory;
skip-silence / volume-boost; **annotatable bookmarks** (note on a marker); chapter list w/ durations +
read-state; **skip-back-on-resume** (rewind 5–30 s); tap-a-word-to-seek in read-along (have the core);
"Clips" (export quote-audio as `.m4a` / video card); position + bookmark handoff across your own devices
(CloudKit state from Phase 1).

### Phase 10 — Capture reach  · effort L  *(steal: Just Press Record, AudioPen)*
**Apple Watch one-tap capture** app (record → transcribe-or-defer → sync to phone; scope = JPR-minimal,
its own target/review). Capture modes/presets (folds with 4c). *(Open: v1 or fast-follow — Watch is
a separate target + review surface.)*

### Phase 11 — App Store readiness  · effort M
Price tier $0.69, **no IAP** (no StoreKit subscription needed; just the App Store Connect price tier;
note: no free trial possible without IAP); privacy nutrition label (all on-device, no tracking —
strong story); onboarding rewrite (Phase 3) + graceful model-download UX (Wi-Fi, progress — exists);
marketing (quote cards, screenshots, copy: "private, offline — your second brain + audiobook
commonplace book"); review prep (ASR/LLM downloads handled gracefully; keep plain `AppIntent` —
no background-record intents that SIGTRAP).

---

## UI surfaces needing mocks (mock-first — locked process)

Per the locked process (spec → mock → build → test; HTML mocks in `SkriftDesktop/mocks/*.html`,
signed off before any UI code). NET-NEW **mobile** surfaces, grouped + prioritized — mock the v1-core
ones (Phases 2–4, 6) first.

**Front-load (v1 core):**
- **Export + Obsidian** (Phase 2): the Share/Export action sheet (MD / PDF / txt / audio); the
  first-run "choose your Obsidian vault folder" flow + `Skrift/` subfolder explainer; Settings →
  Export section (default format, vault folder, include-audio, publish all-vs-important); batch
  "Export selected" in the multi-select bar.
- **Alias management** (Phase 2): add/edit/delete aliases in Settings → Names & voices, **mirroring
  the Mac** (the Mac UI is the reference).
- **Standalone onboarding + Settings IA** (Phase 3): new first-run (on-device record/transcribe value
  prop → "Sync across my devices" → optional "Connect a Mac"); Settings reorg with Mac demoted.
- **Models picker + Polish** (Phase 4) — ⏸ **PARKED.** Polish behavior is locked (title + summary +
  copy-edit, mirroring the Mac; NO invented "modes," NO raw/polished toggle, best-body precedence).
  Held on the **title-presentation UI** (desktop's Suggested/From-recording chooser is wrong for a
  phone). Resume the `standalone-models-polish` mock once that interaction is decided.
- **Commonplace Book** (Phase 6): the Highlights feed, the Daily Review screen, and the shareable
  **quote card** (doubles as the App-Store marketing asset).

**Next wave:**
- **People & backlinks** (Phase 7): People tab, person page (profile + mentions + voice), linked/
  unlinked-mentions panel.
- **Organization** (Phase 5): nested-tag navigation + smart-folder builder. *(Folders mock waits on
  the parked folders decision.)*
- **Journal & retrieval** (Phase 8): On This Day, map view, calendar, related-notes strip + semantic
  search results.
- **Audiobook additions** (Phase 9): mostly extend existing screens; mock only the genuinely new bits
  — "Clips" (audio clip / video card) + the annotatable-bookmark sheet.

**Probably no formal mock (standard patterns):** CloudKit sync toggle + first-sync "audio downloading"
placeholder (Phase 1); pins (Phase 5).

---

## ⭐⭐ RESUME — 2026-06-19 (read THIS first) — next: Phase 2 — Export & Obsidian publish

**✅ DONE 2026-06-19 — the full audiobook player reading-mode redesign + tab-bar IA is BUILT** (build 14, 439/439
SkriftMobileTests green; 8 commit-per-chunk steps `7d31b60`→`4bcca6e`, all to the signed-off mock
`mocks/audiobook-player-reading-mode.html`). Chunks: **1** tab-bar shell (`AppTabView` — Notes·Library·Highlights(soon)·
Settings; the audiobook Library + Settings stopped being `.sheet`s, so a sheet's swipe-down no longer eats pull-to-
refresh) · **2** "significance"→**"Importance"** (visible copy only; `Memo.significance` attr, `significance-*` test
IDs, the contract JSON key all untouched) · **3** one-bar header + cover-tint ambiance + gradient play sphere + skip
back-15/forward-30 · **4** reading mode (auto-recede ~3.5s idle/on-scroll/never-while-paused/~250ms; 3-step past/now/
ahead ramp; current-WORD weight+underline via model `currentWordIndex`; now-line pinned upper-third; free-scroll +
"Back to playing"; column cap ~660pt; the device-tuned interpolation untouched) · **5** "Aa" size+spacing persisted
(`ReadingPrefs` @AppStorage; light/sepia themes dimmed = fast-follow) · **6** bookmark "Mark" toggle + browse-only
sheet + margin glyph anchored to the line · **7** "Add note" centred accent chip + utility reflow (speed/sleep moved
off the transport) + read-along states (nudge / live transcribing-% / empty) · **8** sync-aware library delete-confirm.
**Tab bar visually verified on the iPhone 17 sim; player screens 3–7 owe a device eyeball — the USER's step** (needs a
real book + transcript; the sim has no ASR). **Owed fast-follows:** light/sepia reading themes; a global cross-tab
mini-player (today it's Notes-tab-only). Files: `Features/Root/AppTabView.swift` (new), `App/SkriftApp.swift`,
`Features/MemosList/MemosListView.swift`, `Features/Settings/SettingsView.swift`, `Features/MemoDetail/
SignificanceCircles.swift`, `Features/Audiobooks/{AudiobookPlayerView,ReadAlongView,TextSettingsSheet(new),
ChaptersBookmarksSheet,AudiobookLibraryView}.swift`, `Services/Audiobooks/AudiobookSession.swift`. (`main`, local —
unpushed; build number now 14 in `project.yml`.)

**▶ NEXT = Phase 2 — Export & Obsidian publish** (the ship-blocker: today a phone-only note can only escape via copy-
paste). Then P3 de-Mac finish (onboarding/Settings demote) + Mac→CloudKit (option A).

**Installable now: build (13)** on `main` (local, **unpushed** — push only when asked). Phase 1 sync is COMPLETE +
per-book audiobook sync does a **REAL upload/download %** + cover/transcript/position/rate all cross devices. Install
(13) on both devices to use. (Build number lives in `project.yml` → `xcodegen generate` no longer resets it.)
**Visual roadmap = `ROADMAP.html`** (Artifact; now shows the audiobook deep-dive as a DETOUR that merges back to P2).

**✅ Done 2026-06-19 — raw-CloudKit audiobook AUDIO transfer (REAL %) + the "Turn it on" size sheet** (commits
`974abfd`/`08adbf5`/`a353a49`/`d012353`/`e16531c`; 435/435 unit). Audio left the SwiftData `AudiobookAsset` blob (which
gave NO % — confirmed: `NSPersistentCloudKitContainer.eventChangedNotification` is start/done only) for a **raw-CloudKit
transfer**: `AudiobookAudioTransport` → `CloudKitAudiobookTransport` writes `AudiobookAudio` `CKRecord` + `CKAsset(fileURL:)`
to the private-DB **default zone**; `CKModifyRecordsOperation`/`CKFetchRecordsOperation` `perRecordProgressBlock` → a
byte-weighted **DETERMINATE** per-book bar ("Uploading audio · 38%" / "Downloading · 61%"). Fetched by exact recordID
(`ab_<bookID>_<index>`/`_cover` — ASCII/slash-free) → **no queryable index**. **No `CKQuerySubscription`** (verified: it
wouldn't fire for the default zone anyway): the source stamps `audioUploadedAt` on the carrier when upload completes →
that @Model change pushes (Core Data's zone DOES push) → the receiver's import nudges `reconcile` to fetch by id. The
**"Turn it on" sheet** (`AudiobookSyncSheet`, mock screen 1) replaces the bare menu toggle in BOTH the library long-press
and player ⋯: cover + title + on-device size + the switch + a live % card + iCloud note. **BONUS done:** `CKAsset(fileURL:)`
streams off-disk → no `Data(contentsOf:)` on main for large books (task #18 converged). Wi-Fi default
(`allowsCellularAccess=false`). `AudiobookAsset` @Model **retained-but-dead** (dropping a synced @Model risks a load
`fatalError` vs the deployed dev schema — remove at prod promotion with a CloudKit **dev-env reset**). Design was
**adversarially verified vs current Apple docs** (4-claim workflow: coexistence with NSPersistentCloudKitContainer,
fetch-by-id/no-index, perRecordProgressBlock + CKAsset(fileURL:), drop-@Model + re-push trigger).

**⚠️ DEVICE-VERIFY OWED (the user's step):** real iCloud — install (12) on iPhone + iPad, opt a book in on the iPhone via
the new sheet, watch the **% climb** on its row, then watch it **download on the iPad with a %** and become playable +
resume in place. The `AudiobookAudio` record type auto-creates in the DEV CloudKit env (no Dashboard step); at prod
promotion it must be **Deployed** (and the dead `CD_AudiobookAsset` type removed via a dev-env reset). Both devices must
run the **dev** bundle + same iCloud account; real-CloudKit push doesn't work on the simulator.

**Earlier this session (build 11→12 base):** memo media→CKAsset (1c, **device-verified**); sidecars (1d); names+voices (1e);
custom vocab (1f); **CloudKit push** (device-verified fast sync) + pull-to-refresh; real version-in-About; floating+debounced
"Syncing…" indicators; double-transcription guard; Settings "iCloud sync" line; de-Mac toolbar gate; `DEVELOPMENT_TEAM` in
`project.yml`; the first cut of per-book audiobook sync (toggle/row states/Settings/Remove-download).

**⭐ NEXT:** (a) rest of **Phase 3 de-Mac** — significance → **"Importance"/pin** reframe (**NEEDS a label nod from the
user** before building) + onboarding/Settings Mac-demote; (b) **Phase 2** export/Obsidian + unify Compiler/TagMatcher/DTOs
into `Shared/`; (c) **Mac → CloudKit** (option A); (d) the 10 pre-existing iOS-26 `SkriftMobileUITests` failures. **Also
deferred (folds into 1h):** the cellular **"Ready to sync · N MB"** tap-to-pull affordance (`NWPathMonitor`) — today the
transfer is Wi-Fi-only by hard default. **Build/deploy unchanged:** dev = Xcode Cmd-R / CLI; prod = Xcode Organizer;
capabilities via Xcode.

---

**Done + on `main` (local, unpushed; worktree merged in + removed — everything's on `main`):**
- **Phase 0** — shared naming engine in `Skrift_Native/Shared/Naming/` (`NamesData`/`NameMatch`/`NameStoplist`/`QuoteProtection`/`Sanitiser`), compiled into BOTH apps via each `project.yml` (shared SOURCE FOLDER, not an SPM package). Both green: desktop UnitTests 288 + mobile SkriftMobileTests 400; engine runs on iOS (`SanitiserSmokeTests`). Commits `ea3eeed`/`faece91`/`71cd8d2`/`ebea0b6`.
- **Phase 1a** (`9764183`) — dropped `@Attribute(.unique)` on `Memo.id` (CloudKit forbids it); app-level dedup (the capture drainer's existing `memo(id:)` check).
- **Phase 1b** (`345ea0a`) — `cloudKitDatabase: .private(<per-config container>)` on `NotesRepository` (forced `.none` under inMemory + XCTest so the sim stays offline); iCloud entitlement (literal per config: `iCloud.com.skrift.mobile.dev` / `.mobile`). **DEVICE-VERIFIED: a memo recorded on the iPhone synced to the iPad via CloudKit, no Mac.** Manual Xcode step done: iCloud→CloudKit capability + container added (the CLI can't add a capability).
- **Icons** (`a184d2b`) — one universal icon per config (prod `icon-light`, dev `dev-icon-light`); dropped the light/dark variants (killed the 4-icon mess).
- **Phase 1c — audio/photos → CKAsset** (`c5824eb` 1c-i model/schema · `ec10bf5` 1c-ii materializer/wiring/tests). The recording `.m4a` + photos now sync as CloudKit-mirrored blobs, not just the `Memo` row. `@Model MemoAsset {memoID, kind, filename, byteCount, blob: Data}` — **plain `Data`, NO `@Attribute(.externalStorage)`** (NSPersistentCloudKitContainer rejects external binary storage on a synced attr and would `fatalError` at init; CloudKit auto-promotes `Data >~1 MB` to a CKAsset). Loose `memoID` FK (no `@Relationship` → dodges CloudKit's optional/inverse rules); blob lives in a separate row so the memos-list/search queries never fault it. `AssetMaterializer` (idempotent, both directions, run on launch + `scenePhase==.active`): **materialize** (synced blob → `recordings/<filename>`, never clobbers) so `Memo.audioURL`/photo-load/playback/export are UNCHANGED + **capture** (disk → asset, incl. migrating pre-1c memos + refresh-on-append via `byteCount`); immediate per-memo capture in `MemoSaver.save()`. Asset rows deleted with the memo in `permanentlyDelete`. **✅ DEVICE-VERIFIED 2026-06-18 — image + audio synced iPhone→iPad over CloudKit** (the migration backfilled an existing memo; user-confirmed).
- **Phase 1d — sidecar sync** (`026d4ca`). `wt_<id>.json` + `diar_<id>.json` ride the asset system as new `MemoAsset.Kind`s (`wordTimings`/`diarization`) → **karaoke/read-along + speaker labels work on the receiving device**. Stores expose a shared `filename(for:)` so the name can't drift. Sim-green (+2 tests).
- **Phase 1e — names + enrolled voices sync** (`5ca7c1e`). New `@Model NamesRecord` (CloudKit blob carrier) reconciled with local `names.json` via the SAME `NamesMerge.mergeByCanonical` (per-canonical LWW + **voiceEmbeddings union**) the Mac uses → add-a-person / enroll-a-voice on one device shows on the other. **`names.json` + the byte-compatible Mac contract are UNTOUCHED.** Duplicate carriers collapse to one (content merged first). Coexists with the phone↔Mac names LWW; both converge. Sim-green (+5 `NamesCloudSyncTests`).
- **Phase 1f — custom vocabulary sync** (`fddf690`). New `@Model VocabularyRecord` carrier; `CustomVocabularyStore` gains a `modifiedAt`; `VocabularyCloudSync` reconciles **LWW-by-`modifiedAt`** (whole list, so a DELETE propagates — a union would resurrect removed words). List stays UserDefaults-backed for the booster's synchronous off-main reads. Sim-green (+4 tests).

**Test gate after 1f: 420/420 `SkriftMobileTests` green.** All sync sweeps run together on launch + foreground in `SkriftApp` (`AssetMaterializer.run` + `NamesCloudSync.run` + `VocabularyCloudSync.run`), all idempotent. **⚠️ Device-verify owed for 1d/1e/1f** (rides along with any DEV reinstall — e.g. add a person on the phone → it appears on the iPad).

> **Pre-existing UI-test breakage (NOT from this work):** 10 of 40 `SkriftMobileUITests` fail on the current Xcode/iOS-26 sim — confirmed pre-existing on clean `main` by stash-and-rerun (mostly seeded demo memos not exposing transcript text to XCUITest — likely an iOS-26 `TextEditor` `.value` accessibility change). The **unit suite is the gate** (matches how 1a/1b were gated: "SkriftMobileTests 400"). Flagged as a separate background task.

**📱 DEVICE-VERIFY HANDOFF (Phase 1c — your step):**
1. Build + install the **DEV** build on BOTH the iPhone 13 and the iPad (Xcode Cmd-R, or CLI device build — same iCloud account on both, iCloud Drive on).
2. **First run does the CloudKit schema step automatically:** the dev container (`iCloud.com.skrift.mobile.dev`) auto-creates the new `MemoAsset` record type on first save (dev env auto-schema — no Dashboard visit needed for DEV; PROD needs a "Deploy Schema Changes" in CloudKit Dashboard at promotion, like the Memo type).
3. Record a memo **with a photo** on the iPhone. Wait for CloudKit (seconds–minutes; foreground both apps to nudge the sweep — `AssetMaterializer.run` fires on launch + every foreground).
4. On the iPad: the memo row appears (1b, known good), then the **audio becomes playable + the photo renders** once the CKAsset materializes (1c). Expect "row first, media a beat later."
5. Pull the DEV `devlog.txt` to confirm: look for `asset: captured audio …` on the iPhone and `asset: materialized audio …` on the iPad.
- If audio never crosses: check the iPad's iCloud account/storage, that both run the **dev** bundle id, and that the `MemoAsset` type exists in the dev CloudKit Dashboard. (CKAsset upload can lag on a cold first sync.)

**ALSO DONE 2026-06-18 (this session):**
- **Sync visibility** (`d49333b`, 425 green) — `CloudSyncMonitor` watches `NSPersistentCloudKitContainer.eventChangedNotification` → a "Syncing with iCloud…" strip under the Memos search + a "Downloading from iCloud…" image state (`ImageEmbed`/`MediaSyncState`/`hasAsset`); on import-complete it runs the materialize/merge sweeps so media/names/vocab land **without a foreground cycle**. Closes the "is it stuck?" gap.
- **Vocab clobber fix** (`70a1058`) — a fresh, never-edited device no longer pushes an empty list that could LWW-wipe another device's words.

**NEXT — Phase 1h-ii: the per-book audiobook sync UI** (the engine below is BUILT).

✅ **Engine DONE 2026-06-18** (`b0c7e41`, 430 green, 5 `AudiobookCloudSyncTests`): `AudiobookSyncRecord` + `AudiobookAsset` @Models + `AudiobookCloudSync` (enableSync / disableSync / reconcile — capture audio→CKAssets, materialize on receiver + add the library entry, position LWW by `lastPlayedAt`, unshare keeps local audio). Reconciles against the untouched `AudiobookLibraryStore`. **Callable-only / NOT auto-wired** (inert until the UI + network policy land — no surprise uploads). The mock is **APPROVED + LOCKED** (`mocks/standalone-audiobook-sync.html`, decisions 1–4 resolved 2026-06-18).

**Remaining (1h-ii UI + wiring):** "Sync this book" toggle in BOTH the library long-press menu + player ⋯; per-book row states (uploading/downloading/synced glyphs); Settings "Synced audiobooks" section (count/total/per-book remove, >1 GB heads-up); per-device "Remove download" (Apple Books model); **Wi-Fi-only auto upload/download with a cellular "ready to sync" tap** (needs `NWPathMonitor`); wire `AudiobookCloudSync.reconcile` into the launch/foreground/`CloudSyncMonitor` sweeps + call enable/disable from the toggle. This is where **device verification matters** (real iCloud uploads of large files).

⭐ **Design insight (worked out 2026-06-18, supersedes the old "migrate the whole library" plan):** resume-anywhere needs the two devices to share the **same book `id`**. But each device mints a fresh UUID at import, so two independently-imported copies of the same book can NEVER match on `id` — meaning state-only sync (1g) of locally-imported books is useless on its own, and syncing every library entry would litter the other device with **un-playable "phantom" books** (entry present, audio absent). So 1g and 1h collapse into a single **per-book opt-in** feature:
- Books are **local-only by default** — the existing `AudiobookLibraryStore` (`library.json`) stays the source of truth, **untouched** (no risky whole-library migration of the user's real books).
- The user flips **"Sync this book to my devices"** on a book → that book (and only that book) gets a CloudKit-synced `@Model` (entry: id/title/author/chapters/duration + position/rate/lastPlayedAt/bookmarks) **and** its audio files as **CKAssets** (reusing the 1c `AssetMaterializer` pattern). Now both devices share the id → resume position + bookmarks sync, and the audio materializes so it actually plays.
- `BookTranscript` stays device-local (its `signature` is per-device size:mtime; re-derive per device).
- **UI surface (mock-first, locked process):** the per-book sync toggle (library long-press / player ⋯) + a "downloading on this device" progress state + an iCloud-storage note. Mock before building.
- This is additive + opt-in → low risk (doesn't touch local-only books or the player's existing JSON path), and it's the honest shape of "resume from anywhere."
- Effort: M–L. Has UI → needs a mock. Keep `-inMemoryStore` → CloudKit `.none` for tests.

**Then:** Phase 2 (export/Obsidian) → Phase 3 (de-Mac UX) = *standalone-capable core* → **Mac → CloudKit client** (read the `Memo` store from CloudKit, enhance/link/export, write the polished result BACK so it syncs to the phone; replaces Bonjour/HTTP + solves "Mac polish doesn't return"; the Mac uses `PipelineFile`≠`Memo` so it's a real change — user-greenlit, AFTER Phases 1–3) → roadmap Phases 4–11.

**Build/deploy (user-locked):** dev = CLI `xcodebuild` (automated sim loop) / Xcode Cmd-R (manual device); **prod = Xcode Organizer** (incl. desktop); capabilities ALWAYS Xcode. `main` is local-ahead of origin — push when ready. Full context in the `project_standalone_app_store` memory.

---

## Decisions (resolved 2026-06-15) + still-open

**RESOLVED:**
1. **On-device name-linking for standalone export — YES.** Port `Sanitiser` (Phase 0); runs
   automatically after transcription. **Phone still sends RAW to the Mac (contract unchanged)** — the
   Mac re-links identically via shared code + synced names DB → no double-link, no skip-signal (see
   "Cross-app consistency"). Add **alias management UI** in Settings → Names & voices, **mirroring the
   Mac**.
2. **Audio/photo sync = CKAsset — YES.** Sync the real audio so memos play on the iPad too.
3. **Tier-C bundled model = OPT-IN.** Device-gated picker in the Models tab; user explicitly downloads
   a polish model (no auto-download). Default per tier set by the Phase-4a spike.
4. **Min iOS = 26.** Simplest (FM / glass / SwiftData-CloudKit all clean, no availability gymnastics);
   accepts dropping pre-26 devices. Revisit later only if a lower floor is wanted.
6. **Apple Watch = deferred** (fast-follow; user has no Watch right now — broke it). Phase 10 stays last.

**STILL OPEN:**
5. **Folders model** — app-native folders vs folders-as-Obsidian-subfolders. **User wants to think
   more.** Do NOT build Phase 5 folders until decided; it doesn't block Phases 0–4.

---

## Significance, reframed (Mac-less users)

Today `significance > 0` means "flag-to-send to the Mac" (`Memo.swift:62-66`,
`SyncCoordinator.swift:24,38`). Decouple the gate from its destinations:
- **CloudKit ignores significance** — every memo syncs to your own devices (unconditional "my notes
  everywhere").
- **`significance` becomes importance/pin**, a *per-sink* publish filter (keep the field + contract
  name for byte-compatibility): Obsidian publish offers "publish all" vs "only important (`>0`)";
  the Mac transport keeps today's `>0` flag-to-send unchanged.
- Wire contract unchanged: `significance` still rides upload metadata only when `>0`
  (`UploadPayload.swift:158`); CloudKit syncs it as a plain field so importance is consistent across
  your devices.

---

## Migration checklist (consolidated)

1. `Memo.swift:34` — drop `@Attribute(.unique)`; enforce uniqueness in-app; fix `CaptureInboxDrainer` dedup.
2. `NotesRepository.swift:13-21` — `cloudKitDatabase`, `.none` when `inMemory`.
3. Entitlements + `project.yml` — iCloud/CloudKit container + remote-notifications, per-config;
   one-time Xcode Signing & Capabilities visit per target.
4. `@Model MemoAsset` (→ CKAsset) + `AssetMaterializer` (filename-based code untouched).
5. Audiobook *state* → SwiftData `@Model`s (audio stays device-local).
6. `Memo` — add `exportRelativePath` / `exportedContentHash` / `exportedAt` (additive/defaulted).
7. `Services/Export/MemoExporter.swift` + `ObsidianPublisher` + `PublishCoordinator`.
8. De-Mac UX gating (Phase 3 surfaces).
9. Reframe significance (per-sink policy).
10. Keep `-inMemoryStore` → CloudKit `.none` so the 18 UI + 35 unit tests stay offline/green.

---

## ⭐ CONTINUE HERE / resume

- Branch `standalone` created off `main` (2026-06-15). Nothing committed yet — **plan awaiting user
  sign-off** before building.
- **Next action after sign-off:** Phase 0 (`SkriftPipelineKit`) — it unblocks both export (Phase 2)
  and on-device linking. In parallel, schedule the Phase-4a **model spike on the real iPhone 13**
  (independent, longest-pole, decides the whole Polish story).
- Resolve the 6 open decisions above as they come up; don't block Phase 0 on them.
- Grounding research that produced this doc: portability map, CloudKit change-list, device/LLM
  matrix + spike protocol, sync architecture, competitor steal-list (workflow run, 2026-06-15).
