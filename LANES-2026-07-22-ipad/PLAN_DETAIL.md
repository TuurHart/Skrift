# PLAN — DETAIL lane (the note at regular width)

Base SHA: `ea51c7e02ec4abdd4732e11ed69193dce88e1e57` (BASE.md present ✓, branch `lane/ipad-detail`).

Feature = mock m3 (Connections side panel) + m5 in-note polish states. Layout branches on
`@Environment(\.horizontalSizeClass) == .regular` (NEVER idiom). Compact = today, byte-for-byte.

Ownership (write set): `Features/MemoDetail/MemoDetailView.swift`, `Features/MemoDetail/NoteBodyView.swift`
(width cap only), NEW `Features/MemoDetail/ConnectionsPanel.swift`, NEW
`SkriftMobileTests/IPadDetailConnectionsTests.swift` (pure logic). Everything else READ-ONLY.

## Steps (commit per step, explicit paths)

1. **PLAN file** (this).

2. **NoteBodyView width cap** — the ONLY editor change. `contentWidth` (line ~249) hardcodes
   `UIScreen.main.bounds.width` → inline images size to the full iPad screen, not the 640 column.
   Add `var readingWidthCap: CGFloat? = nil`; `contentWidth = max(80, (readingWidthCap ??
   UIScreen.main.bounds.width) - 2*margin)`. No scroll/selection/gesture changes.

3. **ConnectionsPanel.swift (NEW)** — mock m3, phone-flavored (simpler than the Mac's: no why-chips).
   - Pure, testable helpers `enum ConnectionsPanelLogic`: `importanceText(Double)->String?`
     (SignificanceScale.litCount → "0.8"/"1.0"/nil when unrated — matches the significance control +
     the Mac panel; the brief's `%.1f` with the no-bad-info unrated-hidden guard), `closenessPct(Float)->Int`
     (score×100 rounded), `ordered([Row], byDate:)->[Row]` (Closest = score desc, Date = journalDate).
   - `ConnectionRowVM { id,title,date,score,significance }` (Sendable/Equatable — testable).
   - Live `ConnectionsPanel(memo:onOpenMemo:onViewThread:)`: `.task(id: memo.id)` loads
     `JournalIndexService.relatedScores` → VMs (Closest order) + backlink scan (same as
     `recomputeBacklinks`, index-independent) + thread first-mention. Header "CONNECTIONS · N" +
     collapse chevron (collapsed = thin edge tab w/ count, `@AppStorage ipadConnectionsCollapsed`),
     Closest⇄Date pill (`@AppStorage ipadConnectionsSortByDate` default false=Closest per mock),
     rows title + importance + date + faint %, "View thread" CTA, LINKED FROM. Consent gate when
     `!JournalIndexService.shared.isActive`: shared `RetrievalGate.Copy` explainer + "Turn on
     Connections" → presents `Form { JournalIndexSettingsSection() }` sheet (reuses the canonical
     consent+download UI, zero drift). Backlinks show regardless of gate (mirror Mac).

4. **MemoDetailView wiring:**
   - Body: extract `notePager` (ScrollViewReader + its bottom-bar safeAreaInset). At regular:
     `HStack { notePager.readingMeasure(); ConnectionsPanel }` (bar + reading measure scope to the
     note column only, per m3); at compact: `notePager` unchanged. Hoist toolbar/dialogs/sheets/
     lifecycle onto the Group. Panel hidden when currentMemo nil/locked.
   - `noteFooter(includeConnections:)` — false at regular (related + backlinks move to the panel;
     only peopleInNoteRow stays); true at compact (today). MemoPageView keeps loading its data
     (rotation-robust; panel loads independently — double compute at regular accepted).
   - `readingWidthCap`: editorPage passes `hSize == .regular ? Adaptive.readingMaxWidth : nil`.
   - Polish (m5, seam only): ⋯ dialog gains "Polish now" when `PolishCenter.shared.canPolish(memo)`
     → `.polishNow`. `polishStatusBand` pinned under the title (both page builders): `.downloading`
     → "Downloading model · N%", `.polishing` → "Polishing on this iPad…" (accent-soft capsule +
     spinner), `.failed` → quiet red line + Retry. Done = existing polished-display machinery (no
     new rendering, per brief).

5. **IPadDetailConnectionsTests.swift** — cover the 3 pure helpers (ordering, importance formatting,
   closeness %).

Keep: pager scrollDisabled, karaoke path, photo taps, accessory bar, every a11y id; new surfaces get
`ipad-`-prefixed ids.

## Uncertain decisions (also in wrap block)
- Panel shows at regular width ALWAYS (gate when index off), reconciling the brief's "(only when
  isActive)" against its own consent-gate line + the mock hint + Mac precedent. Flip: gate the whole
  panel on `isActive` and drop the in-panel gate.
- Importance uses SignificanceScale.litCount (unrated→hidden), not literal `%.1f`. Flip: `String(format:"%.1f",_)`.
- "Turn on" presents the real `JournalIndexSettingsSection` in a sheet (one non-pinned cross-lane
  symbol ref). Flip: replicate the explainer + a pinned public enable seam (escalate).
- Double related-derivation at regular (MemoPageView footer hidden but still loads). Flip: gate
  `loadRelated`/`recomputeBacklinks` on `hSize != .regular` + `.onChange(of: hSize)` reload.
