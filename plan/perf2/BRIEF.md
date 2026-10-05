# Speed sweep reader brief (2026-10-05)

Goal: find wasted work in Skrift that makes the apps slower or less smooth, especially with a BIG library
(~2,000 notes, long transcripts, many photos) on an OLDER phone (iPhone 13). App Store users will have both.
You only read code. Never build, never run tests, never edit any file in the repo, never open anything under
an Obsidian vault. Repo root: /Users/tiurihartog/Hackerman/Skrift/.claude/worktrees/session-3-f90c83
Code: Skrift_Native/{SkriftMobile,SkriftDesktop,Shared}. The phone target also runs on iPad.

Prior static sweep (2026-09-23): plan/perf-sweep.md. Many of its rows were fixed since (Q53 typing, Q54 list
scans, Q55 launch, Q56 Mac main thread). For every row in YOUR area, re-check the current code and say
fixed / still open / changed, with today's file:line. Then look for NEW findings.

Waste patterns to hunt (not exhaustive):
- work inside a SwiftUI `body` / computed property that runs on every redraw: fetching, filtering, sorting,
  decoding JSON, regex compile, date formatter creation, string building over all notes
- per-row work in a ForEach/List that scans all notes (turns 2,000 rows into 2,000 x 2,000)
- per-keystroke work in editors (save, reparse, relayout, recompute spans, re-run search)
- SwiftData fetches without a predicate/limit, faulting big blobs (audio, images) when only metadata is needed,
  missing `propertiesToFetch`, fetching all to count, no #Index on hot filter fields
- disk, network, image decode, JSON decode, or model loading on the main thread / @MainActor
- images decoded at full resolution for thumbnails, no downsampling, no cache
- the same result recomputed in several places per frame; caches never invalidated or never hit
- timers / onReceive / observers firing too often; .task(id:) that re-runs on unrelated changes
- @Observable/@Published objects so broad that one change redraws whole screens
- launch/foreground/sync-event sweeps that re-scan everything instead of only what changed
- O(n^2) algorithms, repeated array `contains` in loops, string concatenation in loops

For each finding report exactly:
| id | file:line | what happens | how often it runs (per launch / per redraw / per row / per keystroke / per sync event / per search keystroke) | grows with (notes / note length / photos / people / nothing) | severity guess (high/med/low) with one-line reason | how to measure it (which user moment, what to time) | fix idea in one line |

Be concrete and conservative: cite the actual code line, quote at most one short line of it. Mark anything you
did not confirm by reading the call chain as "suspect". Do not pad: 5 real findings beat 30 guesses.
Write your report as markdown to the path given in your task, starting with a 3-line summary (top 3 by
severity). Your final message: the path plus the top 3 in one line each.
