# Q333 step 1: can the Mac app read a copy of NoteStore.sqlite?

Probe run 2026-10-07 by the Q333 worker.

- The Mac app is NOT sandboxed. Neither entitlements file has `com.apple.security.app-sandbox`:
  `Skrift_Native/SkriftDesktop/SkriftDesktop.entitlements:5-18` (Release) and
  `SkriftDesktop.dev.entitlements:5-15` (Debug) carry only aps-environment + iCloud/CloudKit. The no-sandbox
  decision is stated at `Skrift_Native/SkriftDesktop/project.yml:117-137` (`ENABLE_HARDENED_RUNTIME: NO`).
  With no sandbox, the only gate on `~/Library/Group Containers/group.com.apple.notes/` is the macOS
  privacy prompt (Full Disk Access), which Tuur grants to "Skrift Dev" / "Skrift" in System Settings.
- The worker's own shell could not run the empirical read: `ls ~/Library/Group\ Containers/group.com.apple.notes/`
  fails with `Operation not permitted` (the agent host has no Full Disk Access, and must not be given it).
  That is the host's privacy state, not the app's entitlements, so it does not answer the question either way.
- Nothing about Tuur's notes was read: no row counts, no schema.
- Owed (Tuur, 30 seconds): grant Skrift Dev Full Disk Access, open Import > Apple Notes. The sheet's start
  screen says "Allow Skrift to read your Notes" until the copy + open succeeds, then shows the note count.
  The reader's own error strings (copy denied / cannot open / schema missing) are what the sheet prints.
