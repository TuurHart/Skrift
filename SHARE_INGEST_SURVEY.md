# Share-ingest survey — row-by-row review table

2026-07-07. Everything that can (or should) enter Skrift from outside, one row each:
current behavior + bugs (A), multi-item (B), link enrichment (C), new input types (D),
cross-cutting UX/architecture (E). Bugs verified against build-51 source.

**2026-07-10 — Tuur's verdict pass done (voice review), verdicts in the last column.**
**Round 2 same day:** A1/A11/A12/C4 confirmed GO; D5 SKIPPED; D6 GO (Wave 2);
D1 PARKED for the Books/Journal design chat. **Still pending:** C1 (captions
rejected outright), C2, B4. **Wave 1 scope locked:** A7 + A11 + B1/B2 + A12/E3
+ A15/A16 on the IngestKit skeleton (E5); mock-first, rebase on main at kickoff.

**⭐ WAVE 1 BUILT 2026-07-10** (chunks 1–3, commits `827965f`/`394a916`/`3371fb1`; 610/610
unit green): A7 ✅code · A11 ✅ · B1 ✅ · B2 ✅ · A12/E3 ✅ · A15 ✅ · A16 ✅ · jump-on-open ✅.
Device rounds 1–4 PASSED same day (builds 60→63), merged via PR #11.

**⭐ WAVE 2 TRACK A BUILT 2026-07-11** (one session, `7b597ad`..`f9386cf`; suite 632/632,
desktop 345/345): A9 ✅ · A14 ✅ · C5 ✅ · D4 ✅ (+loader file-URL fix) · D6 ✅ · D8 ✅ ·
E2 ✅ · A4 ✅ · A6 ✅ · bg-task claims ✅ · Mac capture-marker fix ✅ (Wave-1's unproven
edge was real — literal `[[img_NNN]]` in Mac Review + vault export, stale pinned embed).
**Device round OWED (builds from 64)** — checklist in backlog.md. Track B mock
`mocks/share-ingest-wave2.html` (E1 video/PDF sheets · PDF text-in-note · voice-annotate)
**AWAITS SIGN-OFF**; A1/C4 link enrichment not yet picked up. Remaining decisions:
C1 YouTube, C2 Insta/TikTok, B4 chat-export; C3 podcasts ⭐ = own lane on go.

**Mock SIGNED OFF 2026-07-10** (`mocks/share-ingest-wave1.html`) — locked rules from the
sign-off round: (1) **every share jumps to its note on the next app-open** (extensions can't
launch the app — iOS rule; videos already jump); (2) **audio shares carry NO ramble UI** — the
voice note IS the content, append inside the note later; photos/URLs/text keep the ramble;
(3) combine-mode = the audiobook-capture model: clips append in timestamp order into ONE memo,
plays straight through, one karaoke transcript; (4) photos title spells out "N photos → one
note"; (5) clip preview = 3 rows + "+N more"; (6) honesty line stays.

Status: ✅ works · 🚧 partial/risky · 🐛 bug · 💡 new idea · 📐 policy/architecture

## A — What exists today (bugs included)

| ID | Item | Status | Today / the problem | Fix / idea | Effort | Verdict (Tuur, 2026-07-10) |
|----|------|--------|---------------------|------------|--------|----------------|
| A1 | Share a **web URL** | ✅ | Annotation sheet → link-card capture. Title only when the source app supplies it (Safari/Chrome), else bare domain; no favicon/description/thumbnail (contract fields exist, never populated — extension has no network by design) | Enrich on drain in the main app: after the capture lands, the app fetches the page's title/preview image → rich card (this is what "→ C4/E4" meant) | S | **GO** — expects shared URLs to "look quite good"; today they don't, this fixes that |
| A2 | Share **plain text** | ✅ | Annotation sheet → quote-block capture | — | — | **GO** (keep as is) |
| A3 | Share **selected text from Safari** | 🐛 | Share carries text + page URL; URL branch outranks text → **the selected quote is dropped**, saved as a bare link | Prefer text when both present (keep the URL alongside — SharedContent holds both) | S | **GO — keep it as text.** Side idea logged: create a note by typing only, no voice — separate thing; maps to the parked capture-as-note kickoff |
| A4 | Share an **image** (exactly 1) | 🚧 | Sheet → re-encoded JPEG 0.85 capture. Risks: full UIImage decode inside the ~120 MB extension (48 MP/pano can jetsam mid-share); GIF flattened to static; PNG lossy re-encoded; EXIF stripped → capture dated to *share time* (video keeps its filming date — inconsistent) | ImageIO downsampled decode or file-copy path (like video/file); read EXIF date for `recordedAt` | M | **GO** — "downsample it, sure" |
| A5 | Share a **video** (exactly 1) | ✅ | Silent import (no sheet): audio stripped to m4a + one frame + transcribe → normal memo at filming date, auto-opens next foreground | Bypassed sheet = no ramble/significance (→ A13/E1); original video discarded (by design — revisit?); small crash window (inbox entry deleted before import) can lose the video | M | **GO** |
| A6 | Share a **PDF / document** (exactly 1) | 🚧 | Silent → `.file` capture; PDF renders first page inline + QuickLook; other docs get a filename card + Open. No text extraction → **shared PDFs unsearchable** (doc-scans DO get OCR); device-eyeball still owed | Text-extract/OCR on drain into `sharedContent.text` (deliberately pinned earlier — unpin?); give it the sheet (E1) | M | **GO** |
| A7 | Share an **audio file / voice memo** | 🐛🐛 | **THE headline bug (backlog i4, root-caused).** Loader has no audio branch: WhatsApp voice note also exposes a URL → saved as a **link**; Voice Memos/Files m4a → falls to the file branch → dumb document card, **never transcribed** | Audio fast-path BEFORE the URL branch, mirroring the movie path: `"audio"` inbox entry → `importAudio` on drain → transcribed memo. **Scribbel comparison (checked 2026-07-10):** Scribbel has NO share extension — doc-types + `onOpenURL` → `ImportTranscriber` actor, so nothing shadows the app row; patterns to steal: background-task claim so a share-launched import finishes, toast feedback, one-at-a-time guard, broad format sniff (incl. ogg/flac) | S–M | **GO** — see Scribbel for reference (done — takeaways at left) |
| A8 | Audio via **"Open in" / AirDrop** | ✅ | `CFBundleDocumentTypes` → `onOpenURL` → `importAudio` → transcribed memo. Works, but the extension shadows it in the share sheet, so users rarely reach it | Becomes redundant once A7 lands (keep for AirDrop) | — | **GO** |
| A9 | Video via **"Open in"** | 🐛 | Imports, but the memo id is discarded → no navigation → memo "vanishes" to its filming date (the exact bug fixed on the drain path in June, still live here). Also `avi/mpg` are accepted extensions AVFoundation can't read → misleading "Video had no audio track" | `MemoOpenBridge.open` on this path too; prune or honestly error on unreadable containers | S | **GO** |
| A10 | **Voice dictation inside the share sheet** | ❌ | **RETIRED 2026-07-10 (device rounds 2–4):** iOS blocks recording in share extensions at the entitlement level (mediaserverd refusal — permission granted, `record()` false, both session categories). Never worked on hardware; was sim-verified only | Typed annotation stays; **Wave-2 idea: voice-annotate a capture IN-APP** after the jump-open | — | Retired on evidence |
| A11 | **Multi-select shares** | 🐛 | All activation rules max-count 1 → **Skrift disappears from the share sheet** with 2+ items; loader reads only the first attachment per type | Raise counts + iterate all providers (→ B1–B3). Plain words: today, the moment you select 2+ photos/files, Skrift is simply *not offered* in the share sheet | M | **GO** (confirmed r2) |
| A12 | **Silent failures** | 🐛 | Failed video/file copy → `cancel()` — sheet closes looking like success; `CaptureInbox.write` failure ignored (completes anyway); failed file load → **empty text sheet** → saving creates a husk capture. Plain words: when an import fails, the app never tells you — the share sheet closes as if it worked and the item is just *gone* | Error state in the sheet + "Saved to Skrift ✓" confirmation (→ E3) | S–M | **GO** (confirmed r2) |
| A13 | **Sheet skipped for video + file** | 🐛 | Exactly the heavy media gets no annotation/significance at share time; significance stuck at 0 (check against the flag-to-send Mac-sync gate) | Unified sheet for every type (→ E1) | — | **GO** |
| A14 | **Drain latency & hitches** | 🚧 | Captures materialize only on next app-open; no pending indicator; drainer copies video/file blobs synchronously on the main actor → launch hitch on a big movie | Pending badge/toast; move blob copies off-main | S | **GO** |
| A15 | **Dev + prod both labeled "Skrift"** | 🚧 | Extension display name is static across configs → two identical rows when both apps installed (icons differ) | Per-config `CFBundleDisplayName` ("Skrift Dev") in project.yml | XS | **GO** — user confirms it's a real annoyance; make sure it's correct |
| A16 | **Unknown payload types** | 🐛 | Anything unclassifiable falls back to an *empty text sheet*; Save is enabled → empty husk note | Honest "can't import this" state; disable Save on empty | XS | **GO** |

## B — Multi-item shares

| ID | Item | Status | Idea | Effort | Verdict (Tuur, 2026-07-10) |
|----|------|--------|------|--------|----------------|
| B1 | **N voice memos → "1 note or N notes?"** (the 8-WhatsApp case) | 💡 | Chooser in the sheet: **Combine** = one memo via the existing append-clips mechanism, clips ordered by embedded timestamp (a forwarded thread reads chronologically); **Separate** = N transcribed memos. Depends on A7 + A11 | M | **GO** |
| B2 | **N photos → one note** | 💡 | One memo with an N-image manifest (model already supports multi-photo) + one ramble. **No chooser** — multiple photos ALWAYS become one note (user call 2026-07-10) | S–M | **GO — always one note, never N** |
| B3 | **Mixed bundle** (photos + voice + text from one chat) | 💡 | One note with everything in order. Build after B1/B2 prove the pattern | M–L | **GO** — "one note with everything in order, good" |
| B4 | **Messenger chat export (.zip)** | 💡 | Parse `_chat.txt` + media → one conversation-formatted note (speaker turns, voice notes transcribed inline). Must cover **Signal + other major messengers too**, not just WhatsApp (user 2026-07-10) — each has its own export format | XL | **MAYBE** — "never thought I'd use that, but hey, maybe — if it can do that." Parking lot |

## C — Links that deserve more than a bare card

| ID | Item | Status | Idea | Effort | Verdict (Tuur, 2026-07-10) |
|----|------|--------|------|--------|----------------|
| C1 | **YouTube** | 💡 | Rich card on drain (title/channel/thumbnail/duration). ~~Caption fetch~~ — **rejected**: YT caption quality not trusted vs our local Parakeet. Desktop personal build could do yt-dlp → audio → local Parakeet (the appealing half; not App-Store-shippable on mobile) | M | **Captions: NO. Overall: UNDECIDED** — revisit as rich-card-only (mobile) + local-transcribe (desktop)? |
| C2 | **Instagram / TikTok** | 💡 | Rich link card only (oEmbed-ish metadata); no transcript possible without scraping | S | **UNDECIDED** — "tricky, not too sure" |
| C3 | **Podcasts** ⭐ | 💡 | Episode share → download the RSS enclosure (podcast MP3s are openly distributed — legit) → lands in the **Books tab**: playable, whole-transcribed, read-along + quote capture. Reuses the entire BookTranscript infra | L | **STRONG GO** — "awesome idea, I like that" |
| C4 | **Web article → readable text** | 💡 | Plain words: you share a news/blog link; instead of only a link card, the app downloads the page and pulls out the article's *text* (like Safari Reader view) so the note contains the readable article — searchable, quotable, works offline later. No AI involved, just parsing | M | **GO** (confirmed r2 after plain-words explain) |
| C5 | **URL that points at a PDF** (Safari PDF share sends the URL) | 💡 | Detect `.pdf` links on drain → download → existing file-capture path | S | **GO** — "perfect, just make it a PDF" |

## D — New input types

| ID | Item | Status | Idea | Effort | Verdict (Tuur, 2026-07-10) |
|----|------|--------|------|--------|----------------|
| D1 | **Book quotes** (Apple Books / Kindle share) | 💡 | Arrive as text with attribution — detect the format → structured quote note (quote + book + author), twin of the audiobook quote-captures. ~~Highlights tab~~ — **doesn't exist**: tabs are Notes · Books · Journal · Settings; Highlights-style features land INSIDE Journal (AppTabView.swift:11). A per-book quotes view is NOT built today — would live in Journal or the book detail | S–M | **PARKED** (r2) — decide together with the per-book quotes view in the Books/Journal design chat |
| D2 | **Contact (vCard) → Names DB** | 💡 | Share a contact → new person in names.json | S | **SKIP** — real contacts have weird names; the Names DB wants proper first+last for clarity |
| D3 | **OCR shared images** | ✅ | **Already live (verified 2026-07-10):** the drainer gives shared images an `imageManifest`; `PhotoTextIndexer` sweeps all manifests on launch/foreground → OCR text lands in the synced metadata and memos search reads it. User was right. (Shared *PDFs* remain the OCR gap — that's A6) | — | Already done — no work |
| D4 | **.md / .txt files → note body** | 💡 | A shared text file becomes the note *content*, not a file card | S | **GO** — "that's a good one" |
| D5 | **Calendar event (.ics) → meeting scaffold** | 💡 | Plain words: share a calendar invite/event into Skrift → it creates a note pre-filled with the meeting title, time, and attendee names (already linked to your people DB), ready for you to ramble the debrief into | M | **SKIP for now** (r2 — twice unclear = not a real itch; revisit if ever missed) |
| D6 | **Location (Maps share) → place-tagged note** | 💡 | Plain words: share a place from Apple/Google Maps → a note anchored to that place (name + pin), like the location chip your recorded memos already get — "note about this restaurant/spot" | S | **GO — Wave 2** (r2, after walkthrough) |
| D7 | **Telegram / Signal voice notes** | 💡 | Free once A7 lands (Signal's odd UTIs already half-handled in project.yml) | XS | **GO — important** |
| D8 | **In-app Files importer for audio (+ video)** | 💡 | Today there's NO in-app way to import an audio file; video picker is Photos-only. A Files picker closes the gap without relying on share-sheet mechanics | S | **GO — important** |

## E — Cross-cutting UX & architecture

| ID | Item | Status | Idea | Effort | Verdict (Tuur, 2026-07-10) |
|----|------|--------|------|--------|----------------|
| E1 | **One unified share sheet** | 💡 | Every type gets the same lightweight sheet: type-appropriate preview + ramble + significance + (when multi) the 1-vs-N chooser (audio only — photos auto-combine per B2). Kills A13's inconsistency | M | **GO** |
| E2 | **Audio length routing** | 💡 | Short voice note → memo; long recording → offer the Books tab (read-along). **Threshold: ~1 hour** (user call 2026-07-10 — "45 min… maybe an hour — make it one hour") + per-share override | S–M | **GO — threshold 1 h** |
| E3 | **Feedback & failure UX** | 💡 | "Saved to Skrift ✓" confirmation, pending-until-drain indicator, honest error states (covers A12 + A14). Scribbel's toast pattern is the reference | S | **GO** |
| E4 | **Enrichment on drain, never in the extension** | 📐 | Extension stays dumb/fast/offline; the main app does network fetches (metadata, article text, podcast download) — fetching a public URL the user chose ≠ cloud AI (privacy stance intact) | policy | **GO** |
| E5 | **IngestKit in `Skrift_Native/Shared/` + Mac surfaces** | 📐 | Shared pure-Foundation engine: UTType→kind classification, inbox schema, combine/split policy, oEmbed/readability/RSS parsers, quote/chat-export detectors. Thin adapters per platform — iOS share extension; Mac share-menu extension, drag-drop onto window/dock, Finder "Open with", watch folder. Slots into the ⭐ SharedKit dedup lane | L (umbrella) | **GO** |
