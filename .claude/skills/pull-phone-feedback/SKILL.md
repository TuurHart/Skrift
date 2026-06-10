---
name: pull-phone-feedback
description: >-
  Pull the user's recorded feedback (voice-memo transcripts + in-app feedback items +
  crash logs) off the iPhone's Skrift Dev app over USB, parse it into discrete items,
  verify nothing was missed, and triage into backlog.md. Use whenever the user says
  they recorded feedback/test results in the Skrift (Dev) app and wants it read,
  pulled, or processed — e.g. "pull the transcripts from my phone", "I recorded my
  feedback in the app", "read my test notes". Personal-workflow only: valid while the
  user is the app's sole user.
---

# Pull phone feedback (Skrift Dev → backlog.md)

The user records testing feedback as voice memos in **Skrift Dev** on their iPhone.
Pull it over USB, parse, verify, triage. Proven 2026-06-10.

## Constants
- iPhone UDID: `00008110-001208C902EA201E` (phone must be connected + unlocked)
- Dev bundle: `com.skrift.mobile.dev` (prod `com.skrift.mobile` — only pull prod if asked)
- Store: `Library/Application Support/default.store` (+`-wal`, `-shm` — pull all three;
  the WAL holds recent writes)
- In-app feedback: `Documents/Feedback/<uuid>/metadata.json` (text in the `note` field)

## Steps
1. **Check device + container**: `xcrun devicectl list devices`, then
   `xcrun devicectl device info files --device <UDID> --domain-type appDataContainer --domain-identifier com.skrift.mobile.dev`
   (filter the output — the FluidAudio model files dominate it).
2. **Pull** store files + any feedback metadata.json with
   `xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer --domain-identifier com.skrift.mobile.dev --source "<path>" --destination <tmp>`.
3. **Extract transcripts**: `sqlite3 default.store "PRAGMA wal_checkpoint(FULL);"` then select from
   `ZMEMO` — columns `ZTITLE`, `ZTRANSCRIPT`, `ZSIGNIFICANCE`, `ZDURATION`,
   `ZRECORDEDAT` (Core Data epoch: +978307200 → unix). Order by `ZRECORDEDAT`.
4. **Crash logs too** (the user's feedback often mentions crashes):
   `idevicecrashreport -u <UDID> -k /tmp/skrift-crashes`, then parse `SkriftMobile-*.ips`
   (line 2 is JSON: `exception`, `faultingThread` → frames). Match timestamps to the memos.
5. **Parse** every memo into discrete items (bugs / features / UX / passed-confirmations).
   The transcripts are rambly Dutch-English with ASR errors — "script"/"Slrift" = Skrift.
   Read EVERYTHING; items hide mid-tangent.
6. **Verify (mandatory):** a second agent reads the RAW dump against your parsed list with
   the single job "what was missed or misread?" Fold its findings in. Do not skip this —
   it caught real corrections on the first run.
7. **Triage into `backlog.md`** (dated section, P0/P1/P2 + passed-list), commit with
   explicit paths. Keep the raw dump at `.claude/memos_dump.txt` (untracked).
8. **Report** to the user: headline findings first (crashes!), then the parse, then
   proposed next actions.

## Gotchas
- `devicectl ... info files` lists recursively; grep, don't dump.
- Copy the store to a tmp dir before opening — never sqlite3 a live container path.
- Crash `.ips` files: first line is a metadata header, JSON body starts line 2.
- If the phone is locked, devicectl fails — ask the user to unlock it.
