# Speed sweep 2 — merged (2026-10-05)

Nine static readers (Sonnet), briefs in BRIEF.md, reports a- to i-. ~150 findings, nothing measured yet.
They collapse to 13 root causes. Each becomes a queue item only after a trace on the iPhone 13 (Dev build,
Release optimisation, Q313 perf library) or the Mac shows it; every fix carries a before/after number (C282).

| # | root cause | where it bites | findings |
|---|---|---|---|
| 1 | Lists recompute over the whole library on every redraw, and redraw on unrelated changes (any save, any sync tick, transfer progress, meter ticks) | phone list scroll/typing, Mac sidebar clicks, Books tab | A1 A2 L1, M1 M2 M3, D-B2a-d, I13 |
| 2 | Opening a note scans the library: backlinks + a title for every note, per pager page; Connections name-links every related note | note open, pager swipe, Connections | N1 N2 N11, E7 E8, P2 (h), M7, I4 |
| 3 | Title/snippet text built with 5-6 regex passes over the full transcript, per row and for every note in ReminderScheduler | list rows, launch, every foreground | A3 A4, P1 P3 (h) |
| 4 | Search: every keystroke lowercases every note's text and decodes JSON, no debounce | search typing | E1 E2 E4, S1 (h), A9, M11 |
| 5 | Launch/foreground/sync sweeps run on the main thread over everything; LaunchWorkGate never marked at launch, so the first foreground repeats them | cold launch, return to app, after sync | A5 A6 A7, C2, E5, I10, M10 |
| 6 | Mac reconcile: adoptLateDiarization faults every monologue's blobs, per-file Memo-by-id scans, JSON re-serialise, one-by-one ingest on main | Mac activation, notes arriving | G1-G4 G7, M1-M3 (h), I2 |
| 7 | Playback ticks at 20 Hz redo whole-note work (Mac re-decodes word timings; phone per-word Text views) | Mac and phone playback | I1 M5, N3 |
| 8 | Big files on the main thread: Stop-save loads audio+photos; book sidecars decoded on open; whole-file audio resample in memory (~230 MB/h) | Stop, open a book, capture a quote, long recordings | C1 C3, I3, D-B1a-d D-B4-6 |
| 9 | Images never downsampled: covers, camera photos, thumbnails, decoded on main | Library scroll, photo notes, memory | D-B3, I5-I9, C8, A10, N14 |
| 10 | Editor save path: double save, conflict watch fetches all notes; Mac title saves + full reload per keystroke; Mac restyle on every SwiftUI update | typing on both apps | N4 N5, M4, M6 M13 |
| 11 | Data model: no #Index, NamesStore re-decodes names.json, SourceKind.of parses uncached | everywhere, multiplies 1-6 | P5 P7, L1-L6 (h) |
| 12 | Semantic search model unloaded on every background; cold load 44-120 s on A15 | first smart search after return | E10 |
| 13 | Mac Process/export: 5,000-file vault scan before each run, ledger re-decoded and rewritten per note, full byte compares | Process, re-export | G8-G10 |

Correctness, not speed: M6b (f-mac-ui.md) — Mac `updateNSView` restyle inside the 1 s debounce can put back
older text and drop typed characters. Folded into Q63.
