# Share-ingest survey — row-by-row review table

2026-07-07. Everything that can (or should) enter Skrift from outside, one row each:
current behavior + bugs (A), multi-item (B), link enrichment (C), new input types (D),
cross-cutting UX/architecture (E). Review one row at a time; record a memo per row and
say the **ID** (e.g. "A7"), or type into the Verdict column. Code refs are in the
2026-07-07 share-system review chat; bugs verified against build-51 source.

Status: ✅ works · 🚧 partial/risky · 🐛 bug · 💡 new idea · 📐 policy/architecture

## A — What exists today (bugs included)

| ID | Item | Status | Today / the problem | Fix / idea | Effort | Verdict (Tuur) |
|----|------|--------|---------------------|------------|--------|----------------|
| A1 | Share a **web URL** | ✅ | Annotation sheet → link-card capture. Title only when the source app supplies it (Safari/Chrome), else bare domain; no favicon/description/thumbnail (contract fields exist, never populated — extension has no network by design) | Enrich on drain in the main app (→ C4/E4) | S | |
| A2 | Share **plain text** | ✅ | Annotation sheet → quote-block capture | — | — | |
| A3 | Share **selected text from Safari** | 🐛 | Share carries text + page URL; URL branch outranks text → **the selected quote is dropped**, saved as a bare link | Prefer text when both present — or keep both (SharedContent has url *and* text fields) | S | |
| A4 | Share an **image** (exactly 1) | 🚧 | Sheet → re-encoded JPEG 0.85 capture. Risks: full UIImage decode inside the ~120 MB extension (48 MP/pano can jetsam mid-share); GIF flattened to static; PNG lossy re-encoded; EXIF stripped → capture dated to *share time* (video keeps its filming date — inconsistent) | ImageIO downsampled decode or file-copy path (like video/file); read EXIF date for `recordedAt` | M | |
| A5 | Share a **video** (exactly 1) | ✅ | Silent import (no sheet): audio stripped to m4a + one frame + transcribe → normal memo at filming date, auto-opens next foreground | Bypassed sheet = no ramble/significance (→ A13/E1); original video discarded (by design — revisit?); small crash window (inbox entry deleted before import) can lose the video | M | |
| A6 | Share a **PDF / document** (exactly 1) | 🚧 | Silent → `.file` capture; PDF renders first page inline + QuickLook; other docs get a filename card + Open. No text extraction → **shared PDFs unsearchable** (doc-scans DO get OCR); device-eyeball still owed | Text-extract/OCR on drain into `sharedContent.text` (deliberately pinned earlier — unpin?); give it the sheet (E1) | M | |
| A7 | Share an **audio file / voice memo** | 🐛🐛 | **THE headline bug (backlog i4, root-caused).** Loader has no audio branch: WhatsApp voice note also exposes a URL → saved as a **link**; Voice Memos/Files m4a → falls to the file branch → dumb document card, **never transcribed** | Audio fast-path BEFORE the URL branch, mirroring the movie path: `"audio"` inbox entry → `importAudio` on drain → transcribed memo | S–M | |
| A8 | Audio via **"Open in" / AirDrop** | ✅ | `CFBundleDocumentTypes` → `onOpenURL` → `importAudio` → transcribed memo. Works, but the extension shadows it in the share sheet, so users rarely reach it | Becomes redundant once A7 lands (keep for AirDrop) | — | |
| A9 | Video via **"Open in"** | 🐛 | Imports, but the memo id is discarded → no navigation → memo "vanishes" to its filming date (the exact bug fixed on the drain path in June, still live here). Also `avi/mpg` are accepted extensions AVFoundation can't read → misleading "Video had no audio track" | `MemoOpenBridge.open` on this path too; prune or honestly error on unreadable containers | S | |
| A10 | **Voice dictation inside the share sheet** | ✅ | Extension records only; main app transcribes on drain with retries, appends to annotation. One take (re-record replaces) | — | — | |
| A11 | **Multi-select shares** | 🐛 | All activation rules max-count 1 → **Skrift disappears from the share sheet** with 2+ items; loader reads only the first attachment per type | Raise counts + iterate all providers (→ B1–B3) | M | |
| A12 | **Silent failures** | 🐛 | Failed video/file copy → `cancel()` — sheet closes looking like success; `CaptureInbox.write` failure ignored (completes anyway); failed file load → **empty text sheet** → saving creates a husk capture; drainer copy failures → husk memos, source deleted | Error state in the sheet + "Saved to Skrift ✓" confirmation (→ E3) | S–M | |
| A13 | **Sheet skipped for video + file** | 🐛 | Exactly the heavy media gets no annotation/significance at share time; significance stuck at 0 (check against the flag-to-send Mac-sync gate) | Unified sheet for every type (→ E1) | — | |
| A14 | **Drain latency & hitches** | 🚧 | Captures materialize only on next app-open; no pending indicator; drainer copies video/file blobs synchronously on the main actor → launch hitch on a big movie | Pending badge/toast; move blob copies off-main | S | |
| A15 | **Dev + prod both labeled "Skrift"** | 🚧 | Extension display name is static across configs → two identical rows when both apps installed (icons differ) | Per-config `CFBundleDisplayName` ("Skrift Dev") in project.yml | XS | |
| A16 | **Unknown payload types** | 🐛 | Anything unclassifiable falls back to an *empty text sheet*; Save is enabled → empty husk note | Honest "can't import this" state; disable Save on empty | XS | |

## B — Multi-item shares

| ID | Item | Status | Idea | Effort | Verdict (Tuur) |
|----|------|--------|------|--------|----------------|
| B1 | **N voice memos → "1 note or N notes?"** (the 8-WhatsApp case) | 💡 | Chooser in the sheet: **Combine** = one memo via the existing append-clips mechanism, clips ordered by embedded timestamp (a forwarded thread reads chronologically); **Separate** = N transcribed memos. Depends on A7 + A11 | M | |
| B2 | **N photos → one note** | 💡 | One memo with an N-image manifest (model already supports multi-photo) + one ramble; or N captures — same chooser as B1 | S–M | |
| B3 | **Mixed bundle** (photos + voice + text from one chat) | 💡 | One note with everything in order. Build after B1/B2 prove the chooser | M–L | |
| B4 | **WhatsApp chat export (.zip)** | 💡 | Parse `_chat.txt` + media → one conversation-formatted note (speaker turns, voice notes transcribed inline). Uniquely Skrift (ties into conversations/diarization) — parking-lot candidate | XL | |

## C — Links that deserve more than a bare card

| ID | Item | Status | Idea | Effort | Verdict (Tuur) |
|----|------|--------|------|--------|----------------|
| C1 | **YouTube** | 💡 | Mobile (App-Store-clean): oEmbed rich card on drain (title/channel/thumbnail/duration) + fetch captions when the video has them → transcript rides along as source text. **No video download on mobile** (ToS = rejection risk). Desktop personal build could go yt-dlp → local Parakeet | M | |
| C2 | **Instagram / TikTok** | 💡 | Rich link card only (oEmbed-ish metadata); no transcript promise — no caption API, scraping only | S | |
| C3 | **Podcasts** ⭐ | 💡 | Episode share → download the RSS enclosure (podcast MP3s are openly distributed — legit) → lands in the **Books tab**: playable, whole-transcribed, read-along + quote capture. Reuses the entire BookTranscript infra. The standout new capability | L | |
| C4 | **Web article → readable text** | 💡 | Reader-style extraction on drain (on-device parsing, no cloud AI): note carries the article text (searchable/quotable) + og:image/favicon. Fixes A1's bare cards | M | |
| C5 | **URL that points at a PDF** (Safari PDF share sends the URL) | 💡 | Detect `.pdf` links on drain → download → existing file-capture path | S | |

## D — New input types

| ID | Item | Status | Idea | Effort | Verdict (Tuur) |
|----|------|--------|------|--------|----------------|
| D1 | **Book quotes** (Apple Books / Kindle share) | 💡 | Arrive as text with attribution — detect the format → structured quote capture (quote + book + author). Feeds the planned Highlights tab; twins with audiobook quote-captures | S–M | |
| D2 | **Contact (vCard) → Names DB** | 💡 | Share a contact → new person (name + nickname as aliases) in names.json. Name-linking synergy, tiny build | S | |
| D3 | **OCR shared images on drain** | 💡 | Reuse PhotoTextIndexer → screenshot captures get `sharedContent.text` → searchable. Quick win, zero new UI | S | |
| D4 | **.md / .txt files → note body** | 💡 | A shared text file becomes the note *content*, not a file card | S | |
| D5 | **Calendar event (.ics) → meeting scaffold** | 💡 | Title/time/attendees (pre-linked as names) + ramble the debrief | M | |
| D6 | **Location (Maps share) → place-tagged note** | 💡 | Memos already carry place metadata — a shared place = a note anchored there | S | |
| D7 | **Telegram / Signal voice notes** | 💡 | Free once A7 lands (Signal's odd UTIs already half-handled in project.yml) | XS | |
| D8 | **In-app Files importer for audio (+ video)** | 💡 | Today there's NO in-app way to import an audio file; video picker is Photos-only. A Files picker closes the gap without relying on share-sheet mechanics | S | |

## E — Cross-cutting UX & architecture

| ID | Item | Status | Idea | Effort | Verdict (Tuur) |
|----|------|--------|------|--------|----------------|
| E1 | **One unified share sheet** | 💡 | Every type gets the same lightweight sheet: type-appropriate preview + ramble + significance + (when multi) the 1-vs-N chooser. Kills A13's inconsistency | M | |
| E2 | **Audio length routing** | 💡 | Short voice note → memo; a 2 h lecture → offer the Books tab (read-along). Threshold + per-share override | S–M | |
| E3 | **Feedback & failure UX** | 💡 | "Saved to Skrift ✓" confirmation, pending-until-drain indicator, honest error states (covers A12 + A14) | S | |
| E4 | **Enrichment on drain, never in the extension** | 📐 | Extension stays dumb/fast/offline; the main app does network fetches (metadata, article text, podcast download) — fetching a public URL the user chose ≠ cloud AI (privacy stance intact) | policy | |
| E5 | **IngestKit in `Skrift_Native/Shared/` + Mac surfaces** | 📐 | Shared pure-Foundation engine: UTType→kind classification, inbox schema, combine/split policy, oEmbed/readability/RSS parsers, quote/chat-export detectors. Thin adapters per platform — iOS share extension; Mac share-menu extension, drag-drop onto window/dock, Finder "Open with", watch folder. Slots into the ⭐ SharedKit dedup lane | L (umbrella) | |
