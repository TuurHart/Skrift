# Q64 simulator half — results (iPhone 17 sim, synthetic corpus, in-memory store)

Test: `Skrift_Native/SkriftMobile/SkriftMobileUITests/QuickNoteQ64SimUITests.swift` (4 tests + 1 probe, all passed). Base 28c698be.

1. PASS — cold launch with a REAL orphan take planted in the app container (`rec_tmp_q64sim-orphan.m4a`, so the actual `recoverInterruptedRecordings` sweep rebuilt the note), tapped ✎ the moment the button existed: a NEW empty draft opened (placeholder "Add a title", no `quick-note-menu` / `quick-note-add-recording`, no "Recovered recording" text on screen). The sweep did produce the note afterwards ("Recovered recording (the app closed mid-take)", Transcribing, 0:02 — `1b`). A second ✎ with the recovered note already listed also opened a new empty draft (`1c`). Shots: 1a, 1b, 1c.
2. PASS (with one oddity, below) — typed 3 lines. Before typing and after each line: date chip (`quick-note-date`), tag row (`add-tag-button`), importance (`importance-balls`), keyboard up, and the accessory toolbar (`accessory-done`, `accessory-undo`, `accessory-find`) all present and asserted. Shots: 2a, 2b (toolbar pill visible above keyboard).
3. PASS — back on the list the note is listed at the top of TODAY ("Tram 28 idea…"). Chip switches Needs Work / Done / Unrated / All all tapped without a miss; shots 3a (All), 3b-Unrated, 3b-Done.
4. PASS — opened ✎, waited 1.5 s (> the 1 s save debounce), went back: row count identical before and after; no blank row (4a vs 4b).

## Oddity found (not a gate failure)
In test 2 the Return that ended line 1 was lost when typed by XCUITest at full speed right after the first character: the note reads "Tram 28 ideaBuy pastel de nata" (visible in 2b, 3a). Lines 2-3 were fine. Test 5 types the same with pauses: all Returns kept. So it is either an XCUITest typing race or `updateUIView`'s `if tv.text != text { tv.text = text }` overwriting the text view with a stale binding while the first keystroke creates the draft Memo. A human thumb is very unlikely to hit it; dictation or a paste could. Unverified which; worth one look on the device.

## Still needs the real iPhone 13
- The real crash: force-quit mid-record, relaunch, ✎ (sim only proved the sweep+✎ race with a planted file).
- Real keyboard behaviour (hardware keyboard, dictation, keyboard-toolbar visibility while typing on device, the "ideaBuy" question above).
- The location / weather permission prompt from Q73 (a sim has no real prompt or location).
