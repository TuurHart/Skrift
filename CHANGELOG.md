# Skrift — Changelog

All notable user-facing changes. Newest first. Skrift is two native apps (iOS + macOS) that
share a names DB and a note store; "phone" = SkriftMobile, "Mac" = SkriftDesktop.

---

## 0.2.0 — 2026-06-26  *(the iCloud round-trip release)*

The headline: **your Mac and your phone now talk over iCloud**, and the Mac's polish finally
shows up on the phone. Plus on-device name-linking, an audiobook import fix, and clearer dates.

### ✨ The Mac polishes your notes — and now you see it on the phone
- **Polished text on the phone (NEW).** When your Mac processes a memo (clean copy-edit,
  suggested title, summary), that result now syncs back and is **shown on the phone**. The note
  opens to the **polished version** — one clean, editable body (the "um"s and false starts gone).
  Your edits to it sync everywhere as the new source of truth.
- **Title chooser.** Tap ✦ next to the title to pick between the Mac's **Suggested** title, the
  **first line of the recording**, or **your own**.
- **Summary card** at the top of polished notes, and a quiet "✦ Polished on your Mac" note so you
  know where it came from.
- **Follow-along while playing** highlights the polished text as the audio plays (word-exact
  scrubbing on polished text is coming in a follow-up).

### 🔗 Name-linking, now on the phone (NEW)
- **Tap a name in a transcript to link it to a person** — the Mac-style review, on iPhone touch.
  Names are colour-coded by how confident Skrift is:
  - **Linked** (solid purple) — a known person, linked at their first mention.
  - **Suggested** (tan dotted) — a likely name; one tap to confirm.
  - **Ambiguous** (purple dotted) — a name two people share; tap to pick which.
- **Tap to resolve:** pick the person, add a **New person**, or **keep it as plain text** (always
  reversible — with an Undo).
- **"People in this note"** chip bar to link / re-link everyone at a glance.
- **Editable person card** on the phone: full name, the spoken aliases that map to them, a short
  display name, and voice-enrollment status.
- The phone keeps your raw transcript untouched and re-derives the links on demand — the same
  engine your Mac and your Obsidian export use, so they always agree.

### ☁️ Mac ↔ phone over iCloud (no more "same Wi-Fi, app open")
- **The Mac is now an iCloud client of your phone's notes.** It reads your synced memos, runs its
  pipeline (transcribe-if-needed → polish → name-link → export), and **writes the polish back** so
  it lands on your phone and iPad — no local-network pairing, no app-foregrounded requirement. The
  old Bonjour/Wi-Fi pairing stays as an opt-in fallback.
- **Prompt sync via push.** Both apps register for CloudKit's silent pushes, so changes propagate
  in **seconds** (even backgrounded) instead of on iCloud's lazy schedule.
- Significance still gates what leaves the phone (a memo rated 0 stays on the phone).

### 📚 Audiobooks
- **Fixed: MP3 audiobooks were rejected** as "not a playable audiobook." MP3 parts now import
  correctly (the fix also tightens MP3 seek + read-along alignment). Swept the same precise-timing
  fix across every audiobook code path that needed it.

### 🗓️ Polish & fixes
- **Memo-list dates read sensibly with age.** A memo older than a week now shows a real date
  ("19 Jun", or "2025-06-19" for a different year) instead of a bare weekday that looked identical
  to last Friday. (Date labels are also now deterministic across midnight.)
- Bookmark affordance in the audiobook player: only the now-playing line folds, with a clearer
  hollow-outline marker.

### 🔧 Under the hood
- The `Memo` data model + the names engine are now **single shared sources** compiled by both apps,
  so the phone and Mac can never drift on schema or name-linking behaviour.
- The phone↔Mac upload contract is unchanged and byte-compatible (phone sends RAW; the Mac links
  names).

---

## 0.1.0 — 2026-06-14  *(first TestFlight)*

- First internal TestFlight build of the native SwiftUI rewrite: on-device recording +
  transcription (Parakeet on the Neural Engine), contextual metadata + photos, memo list/detail,
  voice-first Names, Settings + Bonjour Mac pairing, Live Activity / Control Center / Lock-screen
  widget / Siri App Intents / share-to-import, the audiobook player with quote-capture, and
  internal iCloud sync (iPhone↔iPad) of notes, media, names, vocabulary, and audiobooks.

<!--
Promotion checklist (maintainers) — prod is the Release "Skrift" build + the real CloudKit
containers (iCloud.com.skrift.{mobile,desktop}). Before promoting 0.2.0:
1. Bump CFBundleVersion to 22 (project.yml, both apps) — dev tests reached 21.
2. Xcode → Signing & Capabilities (Release configs, ONE-TIME): add iCloud + Push to the Release
   App IDs (com.skrift.mobile, com.skrift.desktop).
3. CloudKit Dashboard (PROD environment): Deploy Schema Changes so the MemoEnhancement record type
   exists in prod (it auto-created in dev).
4. Promote when prod is idle: Release build + install to the device; deploy the Release Mac.
5. Push `main` to origin (coordinate with concurrent work — see unpushed commits).
-->
