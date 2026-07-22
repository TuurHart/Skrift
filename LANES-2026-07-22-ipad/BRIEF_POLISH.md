# POLISH — the iPad's on-demand enhancement engine + Settings pane (mock m5)

FEATURE: the local-models play. The Mac's exact enhancement stack (mlx-swift-lm, Gemma 4 E4B,
shared PolishPrompts) as an on-demand engine behind the PolishCenter seam, plus the Settings
surface. UI elsewhere is DETAIL's — you ship the engine + Settings only.

Build:
1. NEW `Services/Polish/Engine/MLXPolishEngine.swift` implementing `PolishEngine`:
   PORT `SkriftDesktop/Engines/EnhancementService.swift` (read it first — 116 lines) to iOS:
   same `ModelContainer` load via `#hubDownloader()` / `#huggingFaceTokenizerLoader()`,
   `PolishPrompts.defaultModelRepo`, temperature 0, maxTokens 1024/64/256. Escrow parity via
   the SAME Shared helpers: `QuoteProtection` leading-quote split + byte-assert,
   `MemoLinkSyntax.escrowForEditing`/`reattach` (whole-body fallback on lost link),
   `ImageMarkerReinsert.extractAnchors`/`reinsert` (now in Shared/Pipeline). Title+summary skip
   for very short transcripts mirroring the Mac's BatchRunner rules (read
   `Pipeline/BatchRunner.swift` for the thresholds; if none exist, always-run and note it).
   `isModelOnDisk`: probe the HF cache dir for the repo (see desktop `ModelInventory`
   patterns); `downloadModel` = `ensureLoaded` with the progress handler; keep the container
   loaded after polish (session reuse), but `unload()` on memory-warning notification.
2. Rewrite `PolishBootstrap.installEngineIfSupported()`: when `PolishGate.isSupported` →
   `PolishCenter.shared.install(engine: MLXPolishEngine())`. Engine init must be lazy/cheap —
   NO model load at launch.
3. NEW `Features/Settings/PolishSettingsView.swift` (mock m5 pane) + a row in
   `SettingsView` gated on `PolishCenter.shared.isAvailable` (invisible on phones/sim): the
   pane = explainer ("Your Mac polishes every synced note automatically…" — mock copy),
   model card (name, "the model your Mac uses", ~size, Download button with live % /
   "Downloaded ✓" state), the `PolishGate.polishOnOpenKey` toggle ("Polish when I open a
   note" + sub-copy), the on-device footnote. Use the Settings idiom already in SettingsView
   (grouped sections).
4. Polish-on-open (the toggle's behavior): implement INSIDE PolishCenter as
   `maybeAutoPolish(_ memo: Memo)` — respects the toggle + canPolish, one auto-attempt per
   memo per session (no loops on failure). DETAIL's view calls the seam if present — since
   DETAIL runs parallel, ALSO wire it via a notification-free path: expose it and note in your
   wrap that MemoDetail onAppear wiring is a 1-line follow-up if DETAIL didn't add it.
5. Tests (`IPadPolish*Tests.swift`): PolishGate sim behavior, engine escrow round-trip on a
   marker+quote fixture WITHOUT loading MLX (factor the escrow into a pure testable layer),
   auto-polish once-per-session rule.

HONESTY CONTRACT: the sim can't run Metal-JIT MLX — your deliverable is compile-green +
escrow-tested + gate-correct; live generation is DEVICE-OWED and your wrap must say so.
Escalate: mlx-swift-lm API drift vs the desktop call shapes (do NOT improvise a different
generation API), memory-pressure design doubts, any need outside your file set.
