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
Pull it over USB, parse, verify, triage. Proven 2026-06-10; live-store path corrected 2026-06-21.

## Constants
- iPhone UDID: `00008110-001208C902EA201E` (phone must be connected + unlocked)
- Dev bundle: `com.skrift.mobile.dev` (prod `com.skrift.mobile` — only pull prod if asked)
- ⚠️ **LIVE store is in the APP GROUP container**, not the per-app container: domain-type
  `appGroupDataContainer`, domain-identifier `group.com.skrift.mobile.dev`, path
  `Library/Application Support/default.store` (+`-wal`, `-shm` — pull all three; WAL holds
  recent writes). The store moved here when App Groups landed ~2026-06-12. **The per-app
  container's `Library/Application Support/default.store` is a STALE ORPHAN frozen at 06-12 —
  do NOT triage from it** (it bit the 06-12 *and* 06-17 *and* 06-21 pulls). App-group reads
  need the **CoreDevice service tunnel up** (`devicectl` prints "Acquired tunnel connection");
  if it's down (error 1011), see the AFC fallback gotcha.
- In-app feedback: `Documents/Feedback/<uuid>/metadata.json` (text in the `note` field) —
  per-app `appDataContainer`, AFC-readable.

## Steps
1. **Check device + locate the LIVE store**: `xcrun devicectl list devices`, then list the
   **app group** container (note `--subdirectory`, not `--source`, for `info files`):
   `xcrun devicectl device info files --device <UDID> --domain-type appGroupDataContainer --domain-identifier group.com.skrift.mobile.dev --subdirectory "Library/Application Support" --no-recurse`.
   Confirm `default.store`'s **modification date is recent** (today/this session) — if it's
   frozen at an old date you're looking at a dead store.
2. **Pull** the three store files from the **app group** container (+ any feedback
   metadata.json from the per-app `appDataContainer`):
   `xcrun devicectl device copy from --device <UDID> --domain-type appGroupDataContainer --domain-identifier group.com.skrift.mobile.dev --source "Library/Application Support/<file>" --destination <tmp>`.
3. **Extract transcripts**: `sqlite3 default.store "PRAGMA wal_checkpoint(FULL);"` then select from
   `ZMEMO` — columns `ZTITLE`, `ZTRANSCRIPT`, `ZSIGNIFICANCE`, `ZDURATION`,
   `ZRECORDEDAT` (Core Data epoch: +978307200 → unix), `ZDELETEDAT`. Order by `ZRECORDEDAT DESC`.
   **Sanity-check you're on the live store:** `SELECT COUNT(*) WHERE ZDELETEDAT IS NULL` should
   equal the number of notes the user sees in-app, and `MAX(ZRECORDEDAT)` should be recent.
   **Triage only the `ZDELETEDAT IS NULL` rows** — the table is full of soft-deleted tombstones
   from prior sessions (65 of 71 on 2026-06-21).
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
- **Wrong-store trap (the recurring one):** the per-app `appDataContainer` store is a dead orphan;
  always pull from the **app group** container and verify the mtime/`MAX(ZRECORDEDAT)` is recent.
  If the user says "there are only N notes" and your dump shows hundreds, you're on the orphan or
  forgot to filter `ZDELETEDAT IS NULL`.
- **Tunnel down (error 1011) — AFC fallback:** if `appGroupDataContainer` reads fail, the app group
  store is unreachable over AFC house-arrest. Recover recent memos from the per-app container's
  `Documents/recordings/wt_<uuid>.json` **word-timing sidecars** (AFC-readable): join each entry's
  `word`s in order to reconstruct the transcript; match by mtime. Raw audio (`memo_<uuid>.m4a`) is
  there too. This recovered the 06-17 bug report when the tunnel was down.
- `devicectl ... info files` lists recursively; grep, don't dump. Use `--subdirectory` (not
  `--source`) for `info files`; `--source` is for `copy from`.
- Copy the store to a tmp dir before opening — never sqlite3 a live container path.
- Crash `.ips` files: first line is a metadata header, JSON body starts line 2.
- If the phone is locked, devicectl fails — ask the user to unlock it.
