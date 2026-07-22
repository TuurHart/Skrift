# DETAIL — the note at regular width: measure, Connections panel, Polish entry (mock m3 + m5 states)

FEATURE: the note page reads like a page (not wall-to-wall), the phone's footer RELATED card +
LINKED FROM strip become a standing side panel at regular width, and the ⋯ menu gains the
polish verbs (via the PolishCenter seam only).

Build:
1. Width: inside `MemoPageView`, cap the content column with `readingMeasure()` (title, chips,
   body, player bar). `NoteBodyView` may need a max-width hint — width cap ONLY, no editor
   behavior changes (it's the re-founded native editor; do not touch its scroll/selection
   machinery).
2. NEW `ConnectionsPanel.swift` (mock m3): at regular width (and only when
   `JournalIndexService.shared.isActive`) a 300pt trailing panel replaces the footer
   relatedSection/backlinks placement: header "Connections · N" + collapse chevron (collapsed =
   a thin edge tab with the count), Closest⇄Date segmented pill (Closest = score order — the
   existing `relatedScores`; Date = `LookbackProvider.journalDate` order), rows = title +
   importance decimal (memo significance, `%.1f`) + date + closeness % (score×100, faint),
   "View thread" CTA (existing `showThreadSheet`), LINKED FROM section (existing backlinks
   data). Consent gate: index off → the panel shows the JournalIndexSettingsSection-style
   explainer + "Turn on" routing to Settings (mirror the Mac's in-panel gate). Compact width:
   today's footer card stays EXACTLY as is (one data source, two presentations).
3. Polish entry (m5 strip, seam only): in the ⋯ menu, when `PolishCenter.shared.canPolish(memo)`
   → "Polish now" (sparkles); while `isWorking` → the "Polishing on this iPad…" pill under the
   title (accent-soft capsule; downloading phase shows "Downloading model · N%"); `.failed` →
   quiet red line with Retry. When an enhancement `hasContent` and was authored by this device,
   the existing polished-display machinery already renders it — add no new rendering.
4. Keep: pager structure (scrollDisabled), karaoke repaint path, photo attachment taps,
   accessory bar, every accessibility id.

Escalate: any temptation to edit JournalIndexService / Shared retrieval (read-only), or to
move the panel's data derivation into Shared (flag it; conductor decides post-wave).
