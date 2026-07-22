# PLAN — POLISH lane (iPad wave 1)

Base SHA: `ea51c7e02ec4abdd4732e11ed69193dce88e1e57` · BASE.md verified present.
Feature: the iPad's on-demand enhancement engine (Mac's exact MLX/Gemma stack behind
the `PolishCenter` seam) + the Settings pane (mock m5). Engine + Settings only; the
in-note UI is DETAIL's.

## Ownership (all within POLISH's write set)
- NEW `Services/Polish/Engine/PolishEscrow.swift` — pure, host-testable escrow layer.
- NEW `Services/Polish/Engine/MLXPolishEngine.swift` — `PolishEngine` impl (port of
  desktop `EnhancementService.swift`).
- NEW `Services/Polish/AutoPolishTracker.swift` — pure once-per-session tracker.
- EDIT `Services/Polish/PolishBootstrap.swift` — install `MLXPolishEngine()` when gated.
- EDIT `Services/Polish/PolishCenter.swift` — ADD (additive only; pinned signatures
  untouched): `maybeAutoPolish(_:)`, a model-level download seam (`ModelPhase`,
  `modelPhase`, `refreshModelState()`, `downloadModelForSettings()`).
- NEW `Features/Settings/PolishSettingsView.swift` — the m5 pane (grouped Form).
- EDIT `Features/Settings/SettingsView.swift` — gated NavigationLink row.
- NEW `SkriftMobileTests/IPadPolishTests.swift` — gate + escrow round-trip + tracker.

No `project.yml` edit needed: app target already links MLXLLM/MLXLMCommon/MLXHuggingFace
+ HuggingFace + Tokenizers, and includes `Services/`, `Features/`, `SkriftMobileTests/`
by directory.

## Engine (MLXPolishEngine, actor) — ports EnhancementService 1:1
- Load: `LLMModelFactory.shared.loadContainer(from: #hubDownloader(), using:
  #huggingFaceTokenizerLoader(), configuration: ModelConfiguration(id:
  PolishPrompts.defaultModelRepo), progressHandler:)`. Keep container loaded (session
  reuse); `unload()` on `UIApplication.didReceiveMemoryWarningNotification`.
- `run(prompt,text,maxTokens)`: `ChatSession(container, generateParameters:
  GenerateParameters(maxTokens:, temperature: 0)).respond(to: prompt+"\n\n"+text)`.
  maxTokens: copyEdit 1024 · title 64 · summary 256.
- `polish`: copyedit via `PolishEscrow.copyEdit` (quote-protect → link+img escrow →
  LLM → reinsert/reattach, fallback-on-loss); title on link-stripped transcript;
  summary skipped when `wordCount < 75` (mirrors BatchRunner
  `effectiveSummaryMinWords` default 75; title always runs, matching the Mac).
- `isModelOnDisk`: probe `HubCache.default.snapshotsDirectory(repo: Repo.ID(rawValue:
  repo)!, kind: .model)` for a `*.safetensors` snapshot (library's own path → can't
  drift from where the downloader writes). Advisory (download is idempotent; a wrong
  read only affects the Settings label, never correctness).
- `downloadModel(onProgress:)` = `ensureLoaded(onProgress:)`.
- Init is cheap: registers the memory-warning observer only; NO model load at launch.
- Reads prompts from `PolishPrompts` directly (no `AppSettings` dep on iPad).

## PolishEscrow (pure) — the factored escrow, MLX-free
Mirrors `EnhancementService.copyEdit`/`editProse` but takes a `generate: (String)
async throws -> String` closure so tests inject identity/mock. Uses the SAME Shared
helpers: `QuoteProtection`, `MemoLinkSyntax.escrowForEditing`/`reattach`,
`ImageMarkerReinsert.extractAnchors`/`reinsert`. Owns the quote byte-assert +
whole-body fallback on lost link/quote.

## PolishCenter additions
- `maybeAutoPolish(memo)`: guard toggle (`PolishGate.polishOnOpenKey`, default off) →
  `canPolish` → `tracker.firstAttempt(id)` → `polishNow`. One attempt/memo/session,
  no retry-on-failure (id recorded before generation).
- Model-download seam for Settings (Settings talks only to PolishCenter, per BASE seam).

## Tests (no MLX loaded)
1. `PolishGate.isSupported == false` on sim; `polishOnOpenKey == "polishOnOpen"`.
2. `PolishEscrow.copyEdit` with identity generator on a fixture carrying a leading `>`
   quote + `[[img_001]]` + `[[memo:UUID|Title]]`: quote byte-identical, marker + link
   survive; and a quote-mutating generator falls the body back unedited.
3. `AutoPolishTracker.firstAttempt` true once then false.

## HONESTY / risks
- Live generation DEVICE-OWED (sim can't run Metal-JIT MLX) — per contract.
- MLX-on-iOS-**sim** compile is the known wave risk (IPAD_PLAN §Risks). Mirrored the
  desktop's exact pinned call shapes to minimise drift; EDIT-ONLY so unverified here —
  conductor's sim gate confirms. If it reds, the lane reverts alone (plan §63).
- MemoDetail onAppear → `PolishCenter.shared.maybeAutoPolish(memo)` is a 1-line
  DETAIL follow-up (exposed here; DETAIL's file not in my set).
