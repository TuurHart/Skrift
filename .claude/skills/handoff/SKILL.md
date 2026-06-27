---
name: handoff
description: >-
  End-of-context handoff for Skrift. Capture this session's state, update the ledgers,
  commit cleanly (without sweeping in another session's staged changes), and write a
  kickoff prompt that front-loads the HEAVY verification work for the NEXT chat. Use when
  the user says they're wrapping up, running low on context, want to "hand off", "save
  state for the next chat", "write a resume/kickoff prompt", or "do the handoff". Runs
  LIGHT on purpose — it does NOT kick off slow builds; the next chat does the heavy lifting.
---

# Handoff (Skrift → next chat)

Triggered at the **end of a session, when context is running low**. The whole point: leave
clean state + a kickoff prompt so the *next* chat (with a fresh full context budget) does the
heavy build/test/device work. So this skill itself stays cheap — **do not start a full
`xcodebuild` here.** Report verification status as it already stands from THIS session.

## Steps

1. **Git safety FIRST (the concurrent-session guard).** Run `git status` and `git diff --staged --stat`.
   A repo may have another live session's changes staged. Identify which changed files YOU
   touched this session; **commit only those, by explicit path** — never `git add -A`/`git add .`.
   If something is staged that you didn't touch, leave it and flag it to the user.

2. **Honest status capture (no claiming-unverified).** Write down, for each thing done this session:
   what was changed, and its **actual** verification state — `tests green` only if you ran them this
   session, else `built but not device-verified`, `unverified`, or `blocked: <why>`. Hardware/visual/
   TestFlight-GUI steps are almost always `blocked` here — say so plainly.

3. **Update the ledgers** (in the same commit as the code):
   - `backlog.md` — THE working ledger: tick off what landed, update the "⭐ CONTINUE HERE" /
     resume point, add any new findings. (User hard rule: triage + tick in the same session.)
   - `FEATURES.md` — if a feature was added/changed (feature × {mobile,desktop} × file × status).
   - The relevant `*_HANDOFF.md` (e.g. `MOBILE_NATIVE_HANDOFF.md`, `DESKTOP_NATIVE_HANDOFF.md`,
     `CONVERSATION_MODE_HANDOFF.md`, `STANDALONE_PLAN.md`) — append a dated status line.
   - Memory: update `MEMORY.md` + the relevant `memory/*.md` file if a durable fact changed.

4. **Commit** the code + ledgers together, explicit paths, descriptive message. Don't push unless
   the user asked (and if pushing, confirm the branch — work happens on `main`).

5. **Write the next-chat kickoff prompt** (see template). This is the deliverable. Front-load the
   HEAVY work so the next chat does it first with a full budget. Output it in a fenced block the
   user can copy, and also note where it's saved if you parked it in a ledger.

## Next-chat kickoff prompt — template

```
Resume Skrift work on branch `main`.

READ FIRST (in order): backlog.md "⭐ CONTINUE HERE", then <the specific HANDOFF doc>,
then <any file the heavy task touches>.

HEAVY WORK TO DO FIRST (full context budget available now — do this before anything light):
  1. <build/test command, e.g. cd Skrift_Native/SkriftMobile && xcodegen generate &&
     xcodebuild test -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build>
  2. <device verify: install signed build, exercise <feature>, pull devlog.txt / idevicesyslog>
  3. <anything left BLOCKED last session — list each with why it was blocked>

RULES: verify before claiming — mark a task `blocked`, not `done`, if you can't prove it on
device/sim. Commit per chunk, explicit paths (a concurrent session may share the index).

STATE FROM LAST SESSION:
  - Done + verified: <…>
  - Done but UNVERIFIED / blocked: <… and why>
  - Open decisions needing the user: <…>
```

## Gotchas
- **Stay light.** No `xcodebuild` of the full MLX scheme here — context is already low. The
  *next* chat runs it. If the user explicitly wants a build run now, do it, but that's the exception.
- **Don't over-claim.** If a fix wasn't device/sim-verified this session, the kickoff prompt says
  so. The next chat's job #1 is to verify it — that only works if you're honest about what's unproven.
- **Explicit-path commits** are the guard against the git-index race that swept files into the wrong
  commit before. Never blanket-add.
- Update `roadmap/` arrays + markdown only if a phase/detour status actually changed (see CLAUDE.md
  update contract) — otherwise skip; it's not part of every handoff.
