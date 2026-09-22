# RESUME — 2026-09-22 evening (written at 94% context, before auto-compact)

Branch `claude/skrift-v2-core-rewrite-564928`, HEAD pushed at `9e8867a1` + this file. Gate green (770/0).
SPEC.md is CONFIRMED (sitting done, 95 decisions), 253 clauses, R1–R60 required differences.
Tuur's instructions in force: NO handoff yet ("I don't trust we got everything"); keep hunting with
SONNET agents (Fable weekly budget 61% used, resets Sun); the spec re-read runs on OPUS.

## Five agents still running when this was written — their outputs to FOLD when they land
| output file | what | fold into |
|---|---|---|
| plan/spec-consistency.md (Opus) | clause-vs-decision contradictions, stale ⚠ marks, numbering, /2-plan readiness, §F = clean clause text for C10–C65 | APPLY §F to SPEC.md (replace the target clauses), clear stale marks, fix numbering |
| plan/scenarios-names.md | 25 names scenarios + bug-shape sweep | R61+ rows, BUGS.md §2, new D if any |
| plan/scenarios-capture.md | 25 capture-path scenarios + sweep | same |
| plan/data-loss.md | every destructive op with its guard; candidates | same; the worst go to BUGS.md §1 |
| plan/research/multiplatform-swiftui.md | how other Swift apps share UI across iPhone/iPad/Mac; recommendation | a Decision line + amend C240; input to the twin audit |

Fold pattern used so far: SPEC R-table rows (`| Rn | v1 does | v2 must | fixture | clause |`),
BUGS.md §2 bullets with file:line, a Decisions line dated 2026-09-22, commit with explicit paths, push.
Then: update memory `project_v2_core_rewrite.md`, and ONLY when Tuur says so, the handoff → `/2-plan`.

## Corpus / local-only
`test-fixtures/dutch-rambles/` = his 5 real Dutch rambles (git-ignored, with word timings pulled from
the Mac row). Skrift Dev on the Mac is running; never start a second instance.
