# JOURNAL — Review at regular width: river + standing calendar/places pane (mock m4 + m4b)

FEATURE: the signed journal-desktop §2 completed with the phone's real cards — river keeps the
left, calendar + places stand on the right; day-select fills the pane; a place opens map mode.

Build:
1. `JournalHomeView` regular width → two columns: LEFT (~520pt) = today's river EXACTLY
   (wallQueueRow → importantCard → thenNowCard → LookbackCards → wayOutRow "Fading"); the
   calendarCard + placesCard LEAVE the river (they're promoted). RIGHT = new
   `JournalSidePane.swift`: month grid (reuse/refactor `JournalCalendarView`'s month math —
   dot density from `LookbackProvider.dayCounts`, ring = today, tap = select day) + selected
   day's note rows (glyph + title + time; tap opens the memo via the existing
   `.navigationDestination(for: UUID.self)`) + Places list (name + count from the existing
   PlaceCluster grouping).
2. Map mode (m4b): tapping Places (or a place row) swaps the pane content for the phone's
   `JournalMapView` map (b89/b90 contract: owned camera, dive-down-only, in-frame card scrolls
   the selected place's notes, gestures clear selection) + "⨯ back to calendar". The river
   never leaves. Reuse JournalMapView's internals — refactor into a host-agnostic subview if
   needed (your files).
3. Compact width: EVERYTHING exactly as today (river with calendarCard + placesCard as cards,
   pushes to Calendar/Map). The Route enum + navigationDestinations stay for compact.
4. Keep: `-seedJournal -mockJournalIndex` demo seeding renders the pane (my screenshot rig),
   wayOutRow unread-dot semantics, `review-wayout-row` id, ScreenTitle header idiom.

Escalate: any Shared/ change (LookbackProvider/PlaceCluster are read-only), any MemoDetail need.
