# Spec extraction — mocks · FEATURES.md · roadmap (2026-09-21)

Sources read in full: 71 HTML mocks + `text-capture-DESIGN.md` under `Skrift_Native/SkriftDesktop/mocks/`, `FEATURES.md` (397 lines), `roadmap/roadmap.yaml` (v45, 2656 lines), `roadmap/README.md`, `Skrift_Native/IPAD_PLAN.md`, `JOURNAL_RETRIEVAL_PLAN.md`. `backlog.md` lines cited only where the brief named an item that lives nowhere else.

Path shorthand: `m/` = `Skrift_Native/SkriftDesktop/mocks/` · `F:` = `FEATURES.md` · `R:` = `roadmap/roadmap.yaml` · `B:` = `backlog.md` · `JRP:` = `JOURNAL_RETRIEVAL_PLAN.md` · `IP:` = `Skrift_Native/IPAD_PLAN.md`.

Tags: `mechanical` = how it works today, no verdict needed · `locked` = a dated decision Tuur made, he confirms · `needs-verdict` = open, or built without a recorded decision.

---

## A · RULES

### Body/image model

- [mechanical] Raw marker is `[[img_NNN]]`; capture injects `\n\n[[img_NNN]]\n\n` at the end of the word nearest the photo's time; a shared picture has no time → offset 0 → lands after the first word — src: F:99, B:679-683 (2026-09-18 audit)
- [locked] A photo marker mid-sentence renders the SENTENCE WHOLE, then the photo as its own full-width `\n\n` block; two in a sentence → both blocks in order; before any sentence → block at top — src: m/accessory-bar-v2.html (signed 2026-07-07), F:54 (2026-07-16 snapImages)
- [locked] The stored RAW keeps the marker at its recorded moment until a user EDIT; edited notes are trusted and never re-injected; the moment lives in `imageManifest.offsetSeconds` — src: F:54 (2026-07-16)
- [mechanical] `snapImages` is ONE shared idempotent transform with a raw→snapped offset map, driving both renderers AND the Obsidian export — src: F:54
- [mechanical] Both renderers collapse the 11-char marker to a 1-char glyph with a second offset remap (Mac `suggestedRanges`, phone `NoteBodyView:551-583`); karaoke seeks translate back through it — src: B:690-694
- [locked] v2 invariant "a picture is always its own paragraph", enforced where a body is WRITTEN; a shared picture goes to the TOP of the note (Tuur's verdict); old notes normalised once on read; snap layer + `SnapResult` + display-only `imageBreaks` deleted; export stops transforming — src: B:698-706, R:704-715 V2Core (2026-09-18)
- [needs-verdict] Picture drag-to-reposition = "move a block" in v2; design/mock first; waits for the body v2 — src: B:900, B:668, B:700
- [needs-verdict] Mixed-share picture placement (8 voice notes + 1 picture → marker in the wrong spot) — fixed by "shared picture → top" or needs its own rule? — src: B:896-898
- [mechanical] Photo tap hit-tests the glyph's DRAWN rect; tap beside a portrait photo = caret placement; checkbox gets finger slop — src: F:51
- [mechanical] Markup save-back writes into the photo file → CloudKit re-mirror + fresh OCR + rebuilt thumbnail; edit chain reports on dismissal only — src: F:51
- [mechanical] A tall portrait frame shrinks width to keep aspect when the 320 height cap kicks in — src: F:310 (4)
- [mechanical] Untitled-row snippet strips `[[img_NNN]]` markers — src: F:310 (3)
- [locked] PDF capture (doc scan or shared) renders its first page inline full-width + an "N pages" chip; tap → zooming viewer with markup; non-PDF/unreadable keeps the file card — src: m/pdf-inline-capture.html (signed A, 2026-07-07), F:52
- [mechanical] Capture-image markers in an annotation convert + copy exactly like memos; the pinned embed is skipped; legacy marker-less captures keep the old path — src: F:157
- [locked] Headings: `#`+space = heading, `#`+word = tag; `#` marks stay visible but recede; characters verbatim so export is already markdown — src: F:47 (2026-07-16)
- [locked] Markdown marks stay DIM-VISIBLE (layout-stable, zero offset math); Obsidian's vanish-off-caret-line is the trap — src: R:2342-2353 i10 (2026-07-16, pinned)
- [locked] `- [ ]`/`- [x]` at line start render as checkboxes; raw keeps the literal syntax → exports as Obsidian tasks; Return continues the list, Return on an empty item dissolves it — src: F:45 (2026-07-07)
- [mechanical] Memo-link raw = `[[memo:UUID|Title]]`; chips show the target's LIVE title; the raw snapshot title is kept as the export fallback so reconstruct round-trips byte-exact — src: F:44
- [mechanical] `**Name:**` turn headers stay VERBATIM in the model; Mac gutter render only when a real conversation (≥2 headers, ≥2 distinct speakers); phone renders conversations in `SpeakerTurnsView` — src: F:255, F:257
- [locked] Derived title = clip at the last word boundary + "…"; `MemoExporter.exportTitle` deliberately keeps the hard slice because it feeds the vault filename — src: F:66 (2026-07-26)
- [locked] Shared inputs never get bubble chrome; pinned shared text = audiobook-quote idiom (accent bar, italic, borderless) — src: m/mac-notes-list-rich.html m2 ("house rule"), memory feedback_no_bubbles (2026-07-12)
- [locked] Bodies stay plain Markdown prose + tasks: no tables, no Aa rich-text styles — src: m/accessory-bar-v2.html (2026-07-07)
- [mechanical] Karaoke on any body (raw or polished) goes through `AlignmentCore` (n-gram anchors + DP); a body that doesn't match its audio returns no times and degrades to an honest sweep — src: F:56 (2026-07-27)
- [needs-verdict] v2 invariants for the diff gate: markers in = markers out, paragraph count never drops unless the shrink guard fired, editor round-trip returns the same string, every transform idempotent — src: B:648-653

### Copy-edit (Mac polish)

- [mechanical] Runs on the RAW transcript; `[[img]]` stripped, 6 words each side kept as anchors, re-found in the model output (degrades to 1-word → proportional) — src: F:327, B:686-688
- [mechanical] Only HORIZONTAL whitespace collapses when stripping markers; blank lines survive; ≥3 breaks normalise to one — src: F:157 (2026-08-20)
- [mechanical] Gemma at temperature 0 does not restore paragraph breaks; `ensureParagraphs` exists for that — src: F:157
- [locked] Summary is SKIPPED when body < `summaryMinWords` (default 75); manual Redo summary forces it — src: F:327 (2026-06-15)
- [locked] Polish = copy-edit + title + summary with the SAME prompts as the Mac; EN/NL preserved, fillers removed, no rewriting; NO "Note/Bullets/Email/To-do" modes — src: m/standalone-models-polish.html, F:327
- [locked] Default prompt text + model repo single-sourced in `Shared/Pipeline/PolishPrompts.swift`; Mac user overrides win locally; prompt edits SYNC whole-blob LWW — src: F:123, F:328 (2026-07-22/23)
- [locked] Quote protection: copy-edit touches ONLY the ramble; the quote is byte-identical or the whole edit falls back to unedited — src: F:235, m/audiobook-capture.html state 4
- [mechanical] LLM escrow for memo-links: links → titles → reattach; whole-body fallback on a lost title — src: R:383-387 (2026-07-07)
- [locked] The Mac only processes `enhanceStatus != .done`; once polished it is never auto-re-polished (no clobber); raw = input, polished(+edits) = output; nothing re-derives polished from raw — src: m/phone-polished-display.html (2026-06-26)
- [locked] Phone edits to a polished body write `MemoEnhancement.copyedit` stamped (this phone, now) → the synced source of truth — src: m/phone-polished-display.html (2026-06-26), F:300
- [locked] `MemoEnhancement` LWW by `enhancedAt`, ANY author (Mac or iPad); double-polish safe — src: F:122, IP "Polisher rule"
- [locked] Mac polishes automatically (unattended, wall power); iPad polishes ONLY the note you ask for while you look; polish-on-open automation DELETED — src: IP roles table, F:122 (v2 2026-07-23)
- [locked] "Has a pass RUN?" (`processedAt`/`isProcessed`) is separate from "is there polish worth showing?" (`hasContent`); a pass records an EMPTY result, a manual-edit re-sync does not; pre-`processedAt` rows use the all-three-parts fallback — src: F:69 (2026-08-26)
- [mechanical] Phone edit to an already-ingested memo → re-link + recompile only, NO LLM re-enhance (user call) — src: F:298
- [mechanical] A Mac manual body/title edit debounces ~1.5s → upserts the enhancement; the body is sent UN-linked to each person's spoken word (`unlinkToSpoken`) so the phone stays bracket-free — src: F:297
- [mechanical] Write-back happens only for a memo that exists in the cloud store, only when there is content, idempotent — src: F:295
- [mechanical] Re-transcribe + Redo copy-edit are hidden for diarized memos; `redo(.copyEdit)` keeps a conversation verbatim — src: F:258
- [locked] Desktop conversation mode defaults OFF; "Flatten to monologue" drops headers, clears diarization, re-enhances as monologue, no re-ASR — src: F:29 (2026-06-15)
- [mechanical] Capture (no audio) = enhance-lite: title + tags + summary + name-link on the annotation; empty annotation → fallback title urlTitle → text head → filename — src: F:156
- [mechanical] ≥0.8 importance buys a refine pass — src: m/significance-circles.html, m/related-panel.html
- [locked] Local-model doctrine: code owns retrieval/ranking/counting/dates; prefer selection over generation; one verb per call; closed-book; NO proper noun in output absent from input; degrade on gate failure — src: R:2581-2598 i19 (2026-08-11)
- [needs-verdict] Copy-edit fix wave (dynamic budget, shrink guard, deterministic paragraphs, visible errors, 8192 token cap) proven by harness only — pre-register the 6 fixture failure classes as required v2 differences? — src: B:767-770, B:905-910
- [needs-verdict] Size budget for v2 copy-edit ("≤ 40% of v1 lines or say why") — src: B:643-644

### Reconcile sweep

- [locked] Only `significance > 0` is ingested into a `PipelineFile`; CloudKit syncs EVERY memo; the `processEverything` toggle is retired in favour of the band's bulk button — src: F:269, m/lifecycle-ia-explorations.html Q6 (2026-07-21)
- [locked] MacMemoAuthor: Mac-local uploads author synced Memos with a 0.1 floor + backfill + transcript-reflect (both devices are collectors) — src: R:559-561 (2026-07-21)
- [locked] Nil significance on a `PipelineFile` is resolved ONCE: projection = unrated · `isLocalRecording` = unrated · 0.1-floor import = rated (`NoteConsent`) — src: F:64 (2026-07-28)
- [locked] Rating is a ONE-WAY door: once a rating creates a row, the row survives un-rating (`needsProcessing` ignores significance) — Tuur decided as-is; do not "fix" without asking — src: F:71, R:912-916 (2026-07-26)
- [mechanical] Dedup by UUID OR `memo_<uuid>` filename; filename dedup may NOT claim a row already owned by another memo (the quote-capture twin fight) — src: F:294, R:2069 W4 (2026-07-27)
- [mechanical] A text-only memo (no audio, no sharedContent) ingests as a `.note` row; decided by an explicit `isTextOnly` flag, never sniffed from parts (an unsynced audio blob must keep its audio) — src: F:61, R:743-746 (2026-08-20)
- [mechanical] A FRESH row adopts a `MemoEnhancement` this Mac wrote; the self-echo guard applies only to existing rows — src: F:61, R:746-748
- [mechanical] `SweepOutcome.stranded` counts + logs rated rowless memos; `WayOutRules.stranded` renders them in the list as a standing floor — src: F:61, R:748-749
- [mechanical] Late-asset heals in the sweep: `adoptLateWordTimings` (idempotent, never clobbers Mac-ASR timings), `MemoPhotoMaterializer.materializeMissing` + manifest refresh each sweep — src: F:56, F:99, R:2045-2055 W3
- [mechanical] Delete mirror is watermarked by `syncedSourceDeletedAt`: reflects only a real change, never un-trashes a pre-existing Mac-local trash — src: F:89 (2026-07-15)
- [mechanical] Phone edits reflect once per `syncedSourceEditedAt` watermark; echo guard by `enhancedByDeviceID`; re-export follows if already in the vault — src: F:298
- [mechanical] Tags + importance sync both ways (`MacCloudMetaSync` on Mac edit, echo-guarded; `MemoCloudUpdate`/`MemoCloudIngest` reflect + backfill) — src: F:297, R:1379-1383
- [mechanical] Sweep triggers: launch / activation / CloudKit import; fired async, SwiftData on main — src: F:296
- [locked] `cloudKitMacSync` defaults ON; an explicit user `false` still wins — src: R:2026-2037 W2 (2026-07-27)
- [mechanical] The sweep races the capture path and its backfill floors to 0.1, so "is this a capture" is the row's own stored fact (`isLocalRecording`, stamped at construction) — src: F:307 (2026-07-28)
- [mechanical] `MacCloudWriteBack.memoID(for:)` must resolve via the store, not the filename UUID (a take's filename names the audio file) — src: F:307
- [mechanical] Re-export skips trashed + locked rows; unlock triggers re-export — src: F:41, F:89
- [mechanical] Locked/remindAt/imageOCRText mirror onto the row at ingest + update sweep; blob refresh fixes stale book fields — src: R:236-237
- [needs-verdict] The Mac's only ingest path re-encodes the typed shared Memo into fake multipart for the retired Bonjour parser — map Memo + assets → PipelineFile directly (golden parity test first) — src: R:2391-2394 i5 (2)
- [needs-verdict] Sweep chain watermarks + off-main; Mac twin `MemoCloudReconciler` 117-122; `allAssets` unscoped faults every blob every sweep — src: R:1707-1708 AuditFix2
- [needs-verdict] The `diarization` asset late-arrival heal: W3 says "no heal yet, owed", W4 says shipped — which is true? — src: R:2053, R:2071, F:56

### Export compiler

- [locked] The picked folder IS the destination — no `Skrift/` prefix, no source subfolders — src: F:70, R:645-660 SharedExport (2026-07-26)
- [locked] The folder is an INBOX; identity lives in the file's stamp (`skriftID`/`skriftHash`/real `lastTouched`); a moved note is reported (`movedAway`), never respawned; the plugin owns following moves — src: F:70 (2026-07-26)
- [locked] Never write over anything not provably ours + untouched: foreign → `<stem> <id8>.md`; pre-stamp legacy → blocked with NO twin; vault-edited → backed off, their version wins; the hash spans frontmatter so an Obsidian tag edit counts — src: F:70
- [mechanical] Atomic + coordinated writes everywhere; unchanged notes write NOTHING (iCloud-churn discipline) — src: F:70
- [mechanical] Ledger is per-picked-folder convenience; the stamp is the safety; a fresh ledger ADOPTS its own file by stamp (the cross-device case) — src: F:70
- [locked] The stamp keys are a PUBLIC contract for the Obsidian plugin (ordinary Obsidian Properties) — src: R:852-855, m/obsidian-plugin-menu.html footer
- [locked] Export requires a PROCESSED note (enhancement with content), not merely a rated one; export controls render only where the device can PROCESS (iPad + Mac); the folder picker stays everywhere (the phone READS the vault) — src: F:67 (2026-08-11)
- [locked] The Settings "Obsidian publish" toggle + "Export now" are DELETED; the picked folder IS the consent; Settings → Obsidian = Folder + Author only — src: F:63 (2026-08-18, b151)
- [mechanical] Nothing auto-publishes on iOS; the only trigger is the per-note verb — src: F:67
- [locked] The note's primary verb is ONE three-state rule: Process → Export to Obsidian → Re-export (`NoteWorkState`); processed is processed whichever device ran it — src: F:63 (2026-08-14)
- [mechanical] Every tap answers: `exportRefusal` names the first failing gate; refusals alert; a write flashes "Exported ✓" then flips to Re-export; author key = `skrift.publish.author` — src: F:63
- [locked] Four destinations, ONE per note (never two): Personal → vault (default, today's behaviour); Made/Idea/Inspiration → the archive repo; a stored field, not a tag; reserved words refused in the free tag field; whole feature behind one Settings switch, off by default; NO suggestion engine — src: m/note-destination-tags.html (signed B collapsed 2026-08-26), F:68
- [locked] The destination is a PRIVACY BOUNDARY, not a filing shelf: a private thought can never land in a folder an AI reads — src: R:758-772 (2026-08-26)
- [locked] Archive entries are FLAT and NAMED: `_ideas/<name>.md`, media beside them, `![](file)` not `![[file]]`; no date folder, no timestamp except as fallback for a titleless capture — src: F:68 (2026-08-28)
- [locked] Archive frontmatter: Skrift stopped squatting on `type:` and `source:` (`capture:` instead); `author:` dropped; `voice:` + `needs: - credit` added — src: F:68 (2026-08-28)
- [locked] People `[[links]]` SURVIVE to the archive (Tuur reversed the privacy call — public site, credit his friends); places plainify — src: F:68 (2026-08-28)
- [locked] Video export CLOSED: Skrift never keeps the movie; a video note exports markdown + extracted audio + photos, no movie — src: R:792-796 (2026-08-27)
- [mechanical] Vault frontmatter: title/date/author/source/people/location/weather/tags/significance/summary; `source:` = true origin (Video / Voice-memo / Apple-Note / Audiobook-quote / capture-url|text|image|file) — src: F:346
- [mechanical] `people:` = the DISTINCT canonical wikilinks in the body, reading order, img markers excluded, alias-display resolved; empty when nobody linked — src: F:347
- [locked] Locked notes are EXCLUDED from publish (sync continues); lock-after-export → honest vault notice, never deletes vault files — src: F:41 (2026-07-07), R:330-332
- [mechanical] Memo-links on export: phone resolves precise `[[<stem>|Title]]` via the frozen export path, else `[[Title]]`; Mac `MemoLinkStems` over ONE `noteStem` derivation — src: F:44
- [mechanical] Quote export `> — [[Author]], *Book*, ch. N` inside the blockquote; `[[Author]]` written at export only; frontmatter book/bookAuthor/chapter — src: F:236
- [mechanical] Capture export: frontmatter `source: capture-url/text/image` + `url:`; pinned block (bold title+URL / blockquote / `![[embed]]`) above the annotation — src: F:157
- [mechanical] `includeAudioInExport` (default on) copies the `.m4a`; the flag is Mac-only (`PipelineFile`), never syncs; the iPad's switch stays hidden until a synced field reaches the Mac — src: F:348, m/mac-note-header.html "Include audio on the iPad" (2026-07-25), R:982-986
- [needs-verdict] Vault folder model: Mac's 3 fields → the phone's one pick; A (keep doctrine, picked folder = destination) vs B (Skrift makes its own folder — reverses 2026-07-26); subfolder names Recordings/Images vs `1 Recordings`/`0 Images`; PDFs export (asset kind exists, exporter ignores it) — src: m/vault-folder-model.html (open, undated)
- [needs-verdict] v2 export compiler stops running the image snap (raw already block-shaped) — src: B:700
- [needs-verdict] Wave-2 PDF text: export = ramble + embed only, or expanded text in the body too? — src: m/share-ingest-wave2.html state 3 Q2 (never answered)
- [needs-verdict] `standalone-export-obsidian` batch export (multi-select → "Exported 4 notes") + Markdown/PDF/plain-text/quote-card export verbs: built (`MemoExporter` per mock) but never surfaced in FEATURES.md — src: m/standalone-export-obsidian.html states 1+4
- [needs-verdict] i1 "Export All" portability escape hatch — src: R:2356-2361
- [needs-verdict] P2 backlog: split-note + skrift-id hybrid (#6 per-book aggregation) — src: R:82-83

### Ingress (share/import)

- [locked] EVERY share jumps to its note on the next app-open (one `MemoOpenBridge` request per drain, last-created wins) — src: m/share-ingest-wave1.html (signed 2026-07-10), F:148
- [locked] Audio shares carry NO ramble UI — the voice note IS the content; append inside the note later — src: m/share-ingest-wave1.html (2026-07-10)
- [locked] N voice notes → chooser "One note" (default: clips merged in timestamp order, ONE transcription pass, continuous karaoke) or "N notes"; significance applies to every note created — src: m/share-ingest-wave1.html, F:149
- [locked] N photos ALWAYS one note (no chooser); header spells the combine ("4 photos → one note"); photos KEEP the ramble — src: m/share-ingest-wave1.html, F:149
- [locked] Clip preview = 3 rows + "+N more", oldest → newest — src: m/share-ingest-wave1.html
- [locked] Feedback states: Saved ✓ flash (~0.8-0.9s, says what saved + "Skrift opens on it next time"); honest error + Try again (temps kept); "Skrift can't import this" with NO Save button — src: m/share-ingest-wave1.html state 4, F:150
- [locked] Sheet dictation RETIRED — iOS entitlement-blocks extension recording (device-proven builds 60-62) — src: F:151 (2026-07-10)
- [mechanical] Audio branch runs BEFORE the url check; selected text beats the url (quote kept, link alongside); odd-UTI audio (Signal/Telegram) rerouted — src: F:148, F:153
- [mechanical] `.md/.txt` shares become the note BODY directly (no sheet) — src: F:152, m/share-ingest-wave2.html state 2
- [mechanical] A `.pdf` LINK downloads into a real file capture, magic-byte sniffed, link-card fallback; extensionless links → HEAD content-type sniff — src: F:152, R:1199-1200
- [mechanical] Apple/Google Maps shares → place chip + place search — src: F:152
- [mechanical] ≥1h audio offers the Books tab (default Books, memo fallback when unreadable) — src: F:152
- [mechanical] Image captures date to the earliest EXIF taken-date (read pre-downsample); images downsampled ≤2048px via ImageIO — src: F:152, F:149
- [mechanical] Shared links enrich ON DRAIN: one GET → title/description/LOCAL og:image thumb + Readability-lite article text into `sharedContent.text` (searchable, never rendered) — src: F:153
- [mechanical] Mixed chat bundles (voice + photos + text) → ONE note — src: F:153
- [locked] Video + documents get the slim sheet (thought + significance); silent imports retired — src: F:153 (Track B green-lit as drawn 2026-07-12), m/share-ingest-wave2.html states 1-2
- [mechanical] Video import: strip audio to `.m4a` + one frame as `[[img_001]]`; `recordedAt` = the video's EMBEDDED creation date; `sourceType: "video"`; `.avi/.mpg` fail honestly — src: F:310, F:152
- [mechanical] PDF text extracted on drain (PDFKit, 120k cap, shared `PDFTextExtract`) into `sharedContent.text`; the document blob syncs as `MemoAsset.Kind.document`; Mac materialises it + gains Open — src: F:147
- [mechanical] C3 discriminator: zero audio `files` parts + `metadata.sharedContent` → capture; both apps test the doc's literal fixture — src: F:145, `Skrift_Native/CAPTURE_CONTRACT.md`
- [mechanical] App Group inbox drains on launch + foreground; idempotent, delete-after-save; poison-pill tombstones; UIKit bg-task claims on drain — src: F:154, R:1199, F:152
- [mechanical] Doc scan → one PDF through the C3 file-capture path; pages OCR'd into `sharedContent.text` — src: F:40
- [locked] A Mac take is a CAPTURE, not an import: arrives UNRATED, transcribes IMMEDIATELY (transcription is capture; polish/name-linking/export are gated by the rating); Stop hands the file to the SAME arrival path Import uses — src: F:307 (2026-07-28), R:2180-2182 W7
- [locked] Book sharing = ONE `.skriftbook` (ZIP), ONE button, no options: audio + ePub if any + transcript/alignment as plumbing; never bookmarks/position/rate/notes/captures; per-config UTI (`com.skrift.book` / `.dev`); import keyed on `bookID` → "already in your books"; transcript re-stamped on arrival via one shared re-stamper — src: m/book-sharing.html, R:1654-1666 (cut twice 2026-07-30, signed 2026-08-11)
- [mechanical] Apple Notes import + HEIC→JPG relink; folder/drag-drop ingest; Photos-app drags provide promised files (fixed) — src: F:308-309, B:8602
- [needs-verdict] Multi-ITEM WhatsApp bundles: `SharePayloadLoader` reads only the FIRST attachment (Tuur-found, devlog-proven) — src: R:1177-1179
- [needs-verdict] Voice-annotate playable-audio attach needs the Mac ingest counterpart (dictation model v1 shipped, UNVERIFIED on device) — src: R:1180-1181, F:153
- [needs-verdict] Wave-2 Q: video keeps the typed thought or audio's no-ramble rule? (built with the thought — no recorded verdict) — src: m/share-ingest-wave2.html state 1
- [needs-verdict] Wave-2 Q: voice-annotate mic pill on captures only, or on every audio-less note (Apple-Notes style)? — src: m/share-ingest-wave2.html state 4
- [needs-verdict] Podcasts → Books: episode share/URL → RSS enclosure download → Books tab — node `inprogress` with no shipped entries and no FEATURES row — src: R:1419-1435
- [needs-verdict] Ingress corpus for v2: one real source file per media type (WhatsApp/Signal/Telegram audio, video, web/YouTube/Instagram URL, text/image/PDF, Apple Note, audiobook, Mac import), network recorded — src: R:718

### Names & sanitise

- [locked] Opt-out + risk-tiering: known people auto-link by default at first mention; full or distinctive first name auto-commits; common-word (`NameStoplist`) / ≤2-char / ambiguous (alias shared by 2+) → dotted SUGGESTION; capitalization guard ("I will call" stays plain) — src: m/naming-review.html (signed 2026-06-16), F:336
- [locked] One note, one link per person: first mention links, every later mention is the plain short; conversations include their matched speakers — src: F:340, F:347, m/naming-review.html
- [locked] Monologue inline display = `[[Canonical|spoken]]` (reads as the spoken word); the "first-mention canonical / rest short" rule applies to conversation turn headers, NOT inline prose — src: m/phone-name-linking.html (locked 2026-06-25)
- [locked] Conversations: merge consecutive same-speaker turns; first header → full `[[Canonical]]`, later headers → plain short; inline mentions normalise misheard forms ("tyr"/"cherry") to the SHORT name — src: F:256 (2026-06-14/15)
- [locked] The phone keeps the transcript RAW and re-derives 4 tiers on demand (linked / suggested / ambiguous / plain-kept); choices persist per note in `Memo.nameResolutionsData`; the contract is untouched — src: F:335 (2026-06-25)
- [locked] Unlink scopes: this mention (alias as spoken, possessive kept) or all mentions in this note (`unlinkedNames`, survives reprocess); never touches the Names DB; NO "never link anywhere" scope — src: m/name-unlink.html, F:342
- [locked] Whole-note resolution: picking a person for a suggested name applies to the whole note; a rarer second Jack is tapped and resolved separately; NO per-occurrence resolver — src: m/standalone-naming-review.html "Whole-note resolution (locked)", m/naming-review.html state 2
- [locked] Tap a LINKED name → Unlink / Change person… (only when AMBIGUOUS) / Open card; "Keep as plain text" is reversible (faint dotted token); Unlink → Undo toast — src: m/phone-name-linking.html (2026-06-25), F:339
- [locked] iOS uses the native bottom `confirmationDialog` WITH a separate Cancel card — never an anchored caret-popover — src: m/phone-name-linking.html (2026-06-25)
- [mechanical] `isAttributed` = line-anchored `**Name:**` regex + ≥2 DISTINCT labels (a `**Pros:**/**Cons:**` body is not a conversation) — src: F:257
- [mechanical] `nonProseRanges` skips leading YAML / fenced+inline code / audiobook-quote spans / memo-link titles — src: F:336, R:385-387
- [mechanical] Roster seeding from `People/*.md` FILENAMES only (canonical = title, aliases = full title + first-name token); idempotent; never clobbers; app code, no AI, never reads a body — src: F:338
- [mechanical] Roster-collision re-scan: a new person whose name collides re-derives every processed memo that auto-linked it → dotted suggestion + count flash — src: F:337
- [locked] Names LWW per canonical with UNION `voiceEmbeddings`; `names.json` byte-compatible across both apps; one shared reconcile core — src: F:243, F:286, `CLAUDE.md` hard rules
- [mechanical] Voice match = embedding cosine, threshold 0.5 (measured diff ≤0.22 / same ≥0.62), ≥2s samples; audio discarded after embedding — src: F:244-245
- [mechanical] Name-a-speaker on the Mac: matched speakers auto-link in their turn header; picking a person links every "Speaker N" turn and learns the voice — src: m/name-a-speaker.html, F:74
- [locked] Speaker hue = stable tint per diarization SLOT, keyed by resolved IDENTITY (first-appearance order), fallback past ~4 speakers; a long gutter name TRUNCATES; the phone KEEPS its cards with the shared hues — src: F:255, R:2196-2210 W6 (2026-07-27)
- [locked] Authors of audiobook quotes NEVER enter the names DB — `[[Author]]` is written at export only — src: F:236, m/audiobook-capture.html state 4
- [mechanical] Custom vocab: CTC-spot custom terms → token-rescore → keep the boost ONLY when EVERY applied replacement is trusted (string-similar to canonical OR alias hit); booster pre-warmed at launch when the list is non-empty; failures never fail the transcription — src: F:135-138 (2026-06-13/15)
- [mechanical] Custom-vocab sync = whole-list LWW by `modifiedAt`; a fresh never-edited device never pushes an empty list — src: F:287
- [mechanical] Deterministic tags = NLTagger lemma + spoken `#`; vault tag scan is app-only (privacy) — src: F:344-345
- [locked] Inline `#tags` in the Mac body (Obsidian idiom): typing `#word` opens a passive caret menu; accepting inserts inline AND files the tag → frontmatter; a bare `#` browses the full library; TagComplete rules (no spaces, `_-/`, nested `/`) — src: F:46 (2026-07-16, user-picked)
- [needs-verdict] Stz020: a name added on the phone isn't recognised (`AddPersonView` saves empty aliases) — seed the alias from the name on add — src: R:265-266
- [needs-verdict] Stz020: phone can't select a word + "add as name" (the Mac has it) — src: R:267
- [needs-verdict] Stz020: "desktop tags every note a conversation (≥2 headers) + no re-transcribe button" — likely closed by F:257's ≥2-distinct-speakers rule; confirm and drop — src: R:268-269
- [needs-verdict] i6: Mac Names screen parity with the phone (avatars, voice status, side-by-side editor) + Mac in-place linking immediate + tappable on the RAW transcript (today only after enhance) — src: m/names-mac.html (no sign-off), R:2406-2412
- [needs-verdict] i21 unlinked-mention mining via NLTagger `.nameType` (suggestions with counts, never auto-link; measure Dutch hit rate first) — src: R:2614-2621
- [needs-verdict] i5 (1): `SpeakerTranscript` is a per-app twin behind the shared Sanitiser — parser drift risk — src: R:2389-2391

### Consent/rating/lifecycle

- [locked] The rating is CONSENT: 0 = unrated → Skrift spends nothing, shows it nowhere but back to you; >0 = the Mac/iPad may process; CloudKit syncs EVERYTHING regardless (flag-to-PROCESS, not flag-to-send) — src: F:59, F:64, R:340-343 (2026-07-20), m/lifecycle-ia-explorations.html "What must be true"
- [locked] NO "Flag" verb anywhere — rating IS the flag; the band's bulk button reads "Mark all as Passing" (the 0.1 tier's own word) — src: m/ipad-app.html m1b (Tuur 2026-07-23), F:114
- [locked] 10 tappable circles: tap the Nth → 0.N, re-tap the set circle → Not rated; tiers Passing / Useful / Important at 0.4 / 0.7; amber refine wall before circle 8; 0.8+ warms the top circles + flame "refine pass" — src: m/significance-circles.html (2026-06-11), F:59
- [locked] User-facing word is "Importance" (was "significance"); internal symbols, SwiftData attr, contract key UNCHANGED — src: F:203 (2026-06-19)
- [needs-verdict] i23: importance = 3 (or 4) BUTTONS not 10 circles — steps 0.3 / 0.6 / 1.0 (or 0.3 / 0.6 / 0.7 / 1.0 to keep the refine-pass escape hatch); Double contract kept, no migration; mock pass owed first — src: R:2639-2654 (voice 2026-09-08)
- [locked] ONE fade clock per note: `clockStart = max(recordedAt, keptAt)`; every touch (edit/title/tag/keep/bring-back) writes `keptAt = now`; quiet 30d → Fading 30d → Recently Deleted 14d → gone; `held` only = locked / pending reminder / backlinked; no immortal Parked limbo — src: m/lifecycle-triage-peek.html m6 (Tuur yes 2026-07-22), F:87
- [locked] v3 "no note dies unseen": the final doors move ONLY at an app-open (phone launch + foreground; Mac launch + activation; day-change + 24h heartbeat RETIRED); purge clock = synced `trashSeenAt` (first open with the note in trash; stamp < `deletedAt` = stale) — src: F:87 (2026-07-23), R:617-631
- [locked] The copy trio, verbatim everywhere from the spine: "starts fading" (day 30) · "moves to Recently Deleted" (day 60) · "gone for good ~" (day 74, iPhone purges) — src: m/lifecycle-ia-explorations.html Q7 (2026-07-21)
- [locked] One-home law: every station has exactly ONE counting surface; editorial views may show any live note; a countdown may only appear where it is computed true — src: m/lifecycle-ia-explorations.html spine (2026-07-21)
- [locked] ONE Recently Deleted, in Review, backed by `Memo`; Mac-only local uploads appear as a small tail; the queue trash sheet is retired — src: m/lifecycle-ia-explorations.html Q5, F:87
- [locked] Direction 2 (two rooms, one spine) as chassis + Direction 3's conveyor as the shelf model; Queue|Review stays — src: m/lifecycle-ia-explorations.html m4 (2026-07-21)
- [locked] The Queue shows unpipelined notes in a collapsed "Not in the pipeline · N" band (Q1); band excludes locked — src: m/lifecycle-ia-explorations.html Q1, F:87
- [locked] The peek (`UnpipelinedMemoSheet` m6): clock chip + ONE explanatory sentence + photos at `[[img_NNN]]` + the real `SignificanceCircles` AS the flag (no silent 0.1) + soft Delete; Done = let the clock run — src: m/lifecycle-triage-peek.html m6 (2026-07-22)
- [locked] Lock is a BACKGROUND verb (quiet-row right-click + phone toggle), never a peek button (Tuur locked one note ever) — src: m/lifecycle-triage-peek.html (2026-07-22)
- [locked] Delete is soft everywhere a note is triaged (peek footer, quiet-row right-click, conveyor rows); 14d; no confirm dialog on the Mac — src: m/lifecycle-triage-peek.html Q2, R:614-616
- [locked] Rows keep the terse spine one-liners; only the peek expands to the sentence — src: m/lifecycle-triage-peek.html Q3
- [locked] The conveyor is named "Fading" on both apps (one decay word); "Bring back" = Keep or Restore; phone conveyor lives in the REVIEW feed row (placement B) with the unread dot on the row — src: R:568-572, m/wayout-phone-placement.html (B picked 2026-07-21)
- [locked] Trash is NOT searchable; Fading IS searchable and untouched notes narrate their fade date in search — src: R:571-572 (2026-07-21)
- [locked] Fade timers are fully automatic from install (b84 — the arming gate read as friction); the ⋯ dot has UNREAD semantics (b85) — src: F:87 (2026-07-18)
- [locked] Fade runs on the PHONE too ("when I take a note that I know is important I give it a score straight away"); unrated = untriaged at every width; phone keeps its urgency-only amber line, iPad/Mac the always-on spine line — src: m/ipad-app.html m1b amendment (Tuur 2026-07-23)
- [locked] An unrated note IS a normal note: ONE renderer via `MemoNoteProjection` (never inserted into the pipeline store); capabilities DERIVE from the note (no Process/Export/Connections, no include-audio switch); edits via `writeBack`, never `MacCloudEditSync` — src: F:60 (2026-07-26, "its just a normal note. nothing special")
- [locked] A typed note (✎/⌘N) is born UNRATED, labelled "Note" (`mediaSource:"typed"`), no player/karaoke ever; title falls back to the first line, "Note" when empty; typing restarts the fade clock, a rating-only change does not — src: m/mac-new-note.html m2 (signed 2026-07-28), F:61
- [locked] `NoteConsent.isRated` is THE one predicate for both dialects (memo 0 / file nil-and-0); Connections index membership + `canSummon` + capabilities all route through it — src: F:64 (2026-07-28)
- [locked] Un-rating is an EVENT driven by the circles' `onChange`; `mirror` declines to guess nil — src: F:71 (2026-07-26)
- [mechanical] `ProcessPile.waiting` = rated + live + unlocked + real transcript + not-yet-enhanced; `unrated` = waiting on a human; provably disjoint; "Process N" counts + RUNS the waiting pile, shown only where the device can process — src: F:115, F:120
- [mechanical] Unrated rows at regular width render QUIET (dim, hollow ○, spine one-liner in the date slot); status pill outranks; the count line taps into the Not-rated filter — src: F:114, m/ipad-app.html m1b B
- [locked] Status-pill POLICY per app: Mac always (its pipeline dashboard), iPad in-flight/error only — src: F:62 (2026-08-19)
- [mechanical] Locked notes: auth gate (Face/Touch ID) per session, backgrounding re-locks; list shows title + 🔒 only; the detail placeholder gates content/photos/audio; v1 = auth gate, not crypto — src: F:41
- [mechanical] Reminders: `remindAt` is synced DATA; the alarm is derived per device (`UNUserNotificationCenter` reconcile); rings whichever device you hold, clears everywhere; Mac reconciler still owed — src: F:42
- [locked] Retention: the permanent corpus = rated memos (the rating is the curation act); unrated are provisional; auto-prune (i2) only via a user-approved review, suppressed while the app hasn't been opened; prune audio before text — src: JRP "Retention & pruning" (2026-07-06)
- [needs-verdict] i2 auto-prune needs a design pass before it earns a node — src: R:2362-2368
- [needs-verdict] LifeIA close-out: Tuur's walkthrough of both apps over the one-clock vocabulary is the only owed item — src: R:534-542

### Sync contract

- [locked] The phone carries the RAW transcript (+ confidence / `userEdited` / markers / metadata / optional `title`), NEVER `sanitised`; the Mac links names; trust = `transcriptUserEdited || transcriptConfidence ≥ 0.7` — src: `CLAUDE.md` hard rules, F:270
- [locked] Mac polish rides back as `MemoEnhancement` (copyedit / title / summary + `enhancedByDeviceID` / `enhancedAt`), LWW by `enhancedAt`; the phone's exporter PREFERS it — src: F:295 (2026-06-22)
- [mechanical] `Memo`/`MemoAsset`/`DeviceID` are shared @Models; `id` app-level unique (CloudKit forbids `.unique`); `MemoAsset.blob` is plain `Data` (no `.externalStorage`; CloudKit auto-promotes >~1MB to CKAsset) — src: F:283-284, F:292
- [mechanical] `AssetMaterializer` is idempotent both ways (materialize synced blob → `recordings/<filename>`; capture disk → asset, refresh-on-append via `byteCount`); asset rows deleted with the memo — src: F:284
- [mechanical] Sidecars `wt_<id>.json` + `diar_<id>.json` ride as `MemoAsset` kinds; the Mac synthesizes `pf.wordTimings` (drives Mac karaoke) + `pf.diarizationSegments`; Mac re-diarize gates on `didTranscribe` — src: F:271, F:285
- [mechanical] A phone-diarized conversation sets `transcriptUserEdited = true` so the Mac trusts the `**Name:**` turns regardless of ASR confidence — src: F:272 (2026-06-14)
- [mechanical] CloudKit delivers asset rows INDEPENDENTLY of the Memo record (a wordTimings asset trailed by 10½h) → every consumer of a late asset needs a heal — src: R:2045-2055 W3, F:56
- [locked] LOCAL-ONLY doctrine for derived book fields: `epubFilename(s)` / `epubChapters` / `detectedChapters` sanitized out of every sent blob, preserved at every adopt site; embeddings never sync; each device builds its own index — src: F:189, F:386, JRP "Storage"
- [mechanical] Whole-blob LWW carriers (names / vocab / polish prompts): duplicate carriers collapse, content merged first; a fresh device never mints a default-@-now carrier; Mac pushes prompts on Settings-window close — src: F:123, F:286, F:287
- [mechanical] Delete carrier = `Memo.deletedAt` (both directions); permanent removal stays device-local — src: F:89
- [mechanical] Audiobook audio = RAW CloudKit `CKRecord` + `CKAsset(fileURL:)` per book (`ab_<bookID>_<index>`) with DETERMINATE %; state via `AudiobookSyncRecord` LWW by `lastPlayedAt` / `modifiedAt`; Wi-Fi default; Apple Books model (global unshare keeps local audio; per-device Remove download) — src: F:291, m/standalone-audiobook-sync.html (locked 2026-06-18)
- [mechanical] Read-along transcript sidecars sync (`ab_<bookID>_t<i>`) and are RE-STAMPED to the receiver's audio; alignment sidecars (`_al<n>`) mirror them, applied only once the transcript matches — src: F:291, F:187
- [mechanical] Additive synced fields since the base contract: `sourceType`, `bookID`/`bookPosition`, `ImageManifestEntry.text`, `locked`, `remindAt`, `keptAt`, `trashSeenAt`, `destination`, `PolishPromptsRecord`; unknown keys ignored by old decoders — src: F:43, F:222, F:41-42, F:87, F:68, F:123
- [mechanical] CloudKit silent push registered both apps (mobile `remote-notification`, Mac `registerForRemoteNotifications`) → sync in seconds even backgrounded — src: F:289
- [needs-verdict] Stz020: deploy the prod CloudKit PRODUCTION schema (`MemoEnhancement` + `NamesRecord` + `VocabularyRecord` + `PolishPromptsRecord`) — phone↔Mac sync hangs in prod; Push capability + `iCloud.com.skrift.mobile` on the Release App IDs — src: R:262-264, F:289, F:296, F:123
- [needs-verdict] Stz020: custom-vocab LWW phone↔Mac round-trip device-unverified — src: R:270-272
- [needs-verdict] `includeAudioInExport` as a synced `Memo` field (its own chunk with its own verification) — src: m/mac-note-header.html, R:659
- [needs-verdict] `AudiobookAsset` @Model is dead but retained until prod promotion (dropping a synced @Model risks a load fatalError vs the deployed dev schema) — src: F:291
- [needs-verdict] i7: port `bookID`/`bookPosition` into `Shared/Model/MemoMetadata.swift` (carry-forward from the SharedKit dedup) — src: R:2415-2421
- [needs-verdict] i5 (5): desktop legacy readers (`PhoneMetadata` + `SharedContent` lenient decoders) collapse once old payloads are gone; needs a lenient shared `init(from:)` + goldens first — src: R:1354-1358, R:2398-2400
- [needs-verdict] Live-edit sync Mac↔phone (Part B): built + unit-tested, TWO-DEVICE round-trip still device-owed — src: R:152-156, F:297-298

### Recording & audio

- [locked] Instant record: every entry auto-starts (FAB, + append, Siri/widget); PRESTART parks the service at the button, RecordView claims it in onAppear (new-memo flow only); unclaimed prestarts expire in 8s; pre-warm only on the main record button (never append / quote ramble) — src: F:21 (2026-06-11, b115-118)
- [locked] b119 policy: with Bluetooth around the WHOLE memo records on the built-in mic (`.allowBluetoothA2DP`); output stays full-quality A2DP; a live HFP input at start is never yanked — src: F:21 (2026-07-26)
- [locked] A mid-recording mic flip is REJECTED (the OS stops the mic at a route-transition START, posts at its END → ~1.9s hole mid-speech) — src: F:21 b117, R:1283-1288
- [mechanical] On every route transition the tap is torn down + REINSTALLED in the current hw format (cross-rate accepted; only transient 0Hz/0ch refused); rebuild retries ~3s total and NEVER permanently give up; route-change + config-change + media-reset observers re-arm — src: F:28
- [mechanical] Interruption observer (call/Siri/alarm) with `.ended` rebuild + foreground re-arm; a display-timer capture WATCHDOG rebuilds when the engine is dead >2s with no rebuild in flight — src: F:28 (2026-07-07)
- [mechanical] Live caption: words in rotated (committed) chunks render solid, the live chunk lighter; `[photo N]` tokens are ANCHORED to the words they followed (re-located on rewrite, ±12-word window) — src: F:22
- [locked] Live-transcription toggle is sticky + works mid-recording; auto-off timer Never / 30s / 1 min / 2 min (default 1 min), transient per recording — src: F:23-24 (2026-06-17/22)
- [mechanical] Caption polling is SELF-PACING: next poll ≥1.5× the last snapshot's cost, thermal floors 2.5s/6s, 6s cap; rotation commits EARLY (>10s window once snapshots exceed 1.2s) — src: F:27
- [locked] Settle = TEXT STABILITY (2 identical tail decodes); the RMS/VAD lane is DEAD on his mic — never re-tune levels, extend stability — src: R:2119 W8 (2026-07-28), memory project_live_transcription
- [locked] Mac live transcription (m2): the note pane IS the draft; settled text is the user's (editable mid-take, engine only appends), the wet tail is the engine's; first edit flips finalize authority; words final on stop; lands unrated + `transcriptUserEdited`; stop just stops (m4 trimmed) — src: m/mac-live-transcription.html m2, R:2095-2119 W8
- [mechanical] Paragraph rule: `longFormGap` 2.0s live + file (a paragraph needs a deliberate stop, not a breath); the Paragrapher is single-sourced in Shared — src: R:2150, R:2117
- [mechanical] Pause hides the paused interval from elapsed time; append merges into the existing recording — src: F:21, F:30
- [mechanical] Launch sweeps re-run any memo stuck `.transcribing` (no Task survives relaunch) and any `pendingDiarizationTarget` — src: F:31-32
- [mechanical] Camera `AVCaptureSession` runs ONLY while the camera sheet is open; front camera hides zoom presets — src: F:96-97
- [mechanical] Mac recorder = `AVCaptureSession` → `AVAudioFile`; encoding derived from the FIRST delivered buffer; fail-fast (no buffer in 1.5s → named-device alert); TCC denial → typed refusal + Open Settings — src: F:307 (2026-07-28)
- [mechanical] Filler-word strip is opt-in (default OFF), memos only, never audiobook quotes / live caption; text + timings in lockstep — src: F:319
- [mechanical] Phantom-transcript guard: RMS decoded lazily only when the transcript came back ≤3 words — src: F:317
- [mechanical] Memo↔book playback exclusion is MUTUAL; remote/AirPods play is IGNORED while a recording is live — src: F:57, F:232
- [mechanical] A book survives an interruption: `pausedByInterruption` latches on `.began`, `.ended` resumes only OUR pause, only with `.shouldResume`, never over a live recording — src: F:232 (2026-07-26)
- [needs-verdict] AuditFix2 D4: an in-flight recording is persisted nowhere until `stop()` — a phone call loses the whole recording (GitHub issue 14) — src: R:1702-1703
- [needs-verdict] Revisit AirPods-mic recording (pre-flip BEFORE capture on explicit intent, or accept the phone mic) — src: R:1295-1298
- [needs-verdict] RecHard device round on the 13: call/alarm mid-record survives; camera latency; freeze gone; b119 count-to-10 re-run — src: R:1290-1291, F:21
- [needs-verdict] i17 "dictate anywhere" mode 2 — near-half parked; if ever built, dictated audio NOT kept — src: R:2545-2564
- [needs-verdict] FluidAudio pin: F:317 says `7f963cdc`, EPubAlign says bumped to v0.15.5 — which is current? — src: F:317, R:1613-1615

### Audiobooks

- [locked] Text capture is the ONLY flow; the audio mark-in/out arm (`CaptureMomentView`, A/B seam, Settings toggle, sentence-trim sheet) is retired — src: m/audiobook-capture-merged.html (signed 2026-06-13), F:165, F:230
- [locked] Capture = ONE note-style screen: header (❝ + book·ch) → the real `SignificanceCircles` card → build-your-quote sentence rows (+ to add, ✕ to drop) → Record your thoughts pinned; always records voice; a bail before recording discards the quote-only memo; no preview step — src: m/audiobook-capture-merged.html (2026-06-13), F:177
- [locked] Selection is bidirectional + BOUNDED: the tapped line is the anchor in the middle, ~90s before it + up to 8 lines after (4 un-chunked); NO infinite scroll — src: F:166 (2026-06-14)
- [locked] v1 quote text is NOT free-text-editable (would diverge from the audio + rebased timings) — src: m/text-capture-DESIGN.md §9 (2026-06-13)
- [locked] Pre-select the last sentence that ENDED at/before the playhead, never the in-progress one — src: m/text-capture-DESIGN.md §7
- [mechanical] Chunk extraction = sample-accurate `AVAudioFile` frame reads, NEVER `AVAssetExportSession` (drifts word-times late on compressed audio) — src: F:171 (2026-06-13/07-11)
- [mechanical] Sidecar per file `transcript_f<n>.json` (file-local time basis), staleness `size:mtime`, atomic per-file write; `ChunkFusion` cuts at the last complete sentence; 180s chunks; capture/pause/conserve CANCEL the in-flight chunk and redo the same frontier — src: F:169-174
- [locked] The transcribe job runs on battery; conserve only < 20% on battery; Low Power Mode never stops it (the OS still won't launch the BGProcessingTask under LPM) — src: F:171 (2026-07-30)
- [locked] Speed estimate only from the MEASURED per-device RTF; never ship a placeholder number — src: F:178, m/text-capture-DESIGN.md §13
- [locked] Chapter precedence: ePub TOC > transcript-detected > embedded/file-split; detection needs ≥2 detections + sane numbering else nil ("better no info than bad info"); local-only, never synced — src: F:173, F:187 (Q1 lock 2026-07-21)
- [locked] Aligned sentences (≥0.5 confidence) show the BOOK's text; below it the ASR words splice back in; display is a UNION (bridged holes with interpolated times + ASR gap fill), never a replacement; wrong-book self-detect at 150:1; quote captures export the VERBATIM published sentence — src: F:188 (2026-07-21/23)
- [locked] ONE "Text…" verb everywhere (player ⋯ + library long-press): Level 1 Transcript over Level 2 Book text; A0 "Give this book text" appears ONCE per book post-import, per-device UserDefaults (deliberately not synced); attach during transcribe defers, never a bogus verdict — src: m/book-text-unified.html (signed + built 2026-07-23), F:186, F:190
- [locked] Book-text sheet = variant B timeline-first; the coverage bar is STRICTLY time-true (grey background, colored spans at exact fractions); rows with dc:title (garbage honestly displayed); Add / Re-check / Remove; attach outcomes = explicit alerts — src: m/book-text-sheet.html, F:189 (2026-07-22)
- [locked] Player = text-forward A+D hybrid: read-along hero, cover demoted to a header chip, cover-derived tint, speed + sleep flank the transport, slim Chapters + Bookmark row, one hero "Capture this"; AirPlay / skip-silence / EQ out of scope — src: m/audiobook-player-redesign.html (signed 2026-06-13), F:180-194
- [locked] Bookmarks are lightweight (position + chapter label + timestamp; no audio/text; per-book JSON; ±2s dupe guard) — Capture is the rich save — src: m/audiobook-player-redesign.html, F:193
- [locked] Reading mode: chrome auto-recedes after ~3.5s idle or on reader scroll, tap toggles, NEVER while paused, ~250ms crossfade; flat 3-step ramp (past `#6E6E7E` · now `#F4F4F8` · ahead `#A6A6B6`); current WORD = weight + thin underline, no box; now-line pinned at y=0.34; free-scroll + transient "Back to playing"; column capped ~660pt; skip back-15 / forward-30 — src: m/audiobook-player-reading-mode.html (v2 locked), F:204-205
- [locked] "Aa" = size (14-22pt) + spacing Tight/Cozy/Loose, persisted app-wide; light/sepia/dark themes are a fast-follow (shown dimmed) — src: m/audiobook-player-reading-mode.html, F:206
- [locked] Bookmark = page-corner fold on the ACTIVE line only (hollow outline = affordance); tap a fold to lift it; NO bottom "Mark" button; removal span-aware; Chapters/Bookmarks sheet browses only — src: m/audiobook-bookmark-fold.html, F:207 (2026-06-21/22)
- [locked] Read-along lines split with `NLTokenizer(.sentence)`; uniform 18pt lines (current via `scaleEffect`); playhead interpolated between AVPlayer ticks, advance at line END with `lead` 0.1s — src: F:191 (2026-06-13/15)
- [locked] Tab IA = Notes · Books · Review · Settings; Highlights placeholder CUT (P6 lives in the book context, never a tab); Library renamed Books; one 30pt `ScreenTitle` in hand-rolled compact headers — src: F:202, F:217 (2026-07-07)
- [locked] Notes bottom chrome: card-at-rest ("Continue listening" as the first list row above search, × hides for today) / pill-when-live (V2a: cover · time-left · ❝ Add note · filled play beside the record button, one 60pt row); no launch restore; Journal/Settings carry nothing — src: m/notes-compact-header.html (locked), m/notes-pill-v2-iterations.html (V2a), F:218-219
- [locked] Tap a book row → it plays; PLAYING/PAUSED badge dropped; sorts (Recently played default, persisted) + status filters (transient) live in the header chip — src: m/books-tab-and-resume.html (2026-07-07), F:220-221
- [locked] One verb "Add note"; "memo" → "note" in every user-facing string; internal symbols unchanged — src: F:223, m/books-tab-and-resume.html (DECIDED 2026-07-07)
- [locked] Capture memos carry `bookID` + `bookPosition` (additive; the per-book join key) — src: F:222
- [locked] Per-book sync: books local by default; toggle from BOTH library long-press + player ⋯; Wi-Fi auto, cellular = tap-to-pull; Apple Books model; per-book size on the toggle + Settings "Synced audiobooks", no iCloud-quota claim — src: m/standalone-audiobook-sync.html (locked 2026-06-18)
- [locked] Library delete-confirm is sync-aware: synced → "Remove from all devices" + demoted "Remove from this iPhone only" + Cancel; local → "Remove" + Cancel; bookmarks + captured notes are kept — src: F:210, m/audiobook-player-reading-mode.html screen 7
- [locked] iPad: the shelf grid STAYS ("I like the little icons"); the three-zone player is RETIRED — ONE player at every width, read-along capped at 680pt; a book-expert chat redesigns it later — src: m/ipad-app.html m6 v2 (2026-07-23), F:118
- [mechanical] An un-transcribed (audio-only) book has no gutter → no bookmark affordance (accepted trade-off) — src: F:207
- [mechanical] Whole-book transcribe = "Transcribe book" sheet copy: "keep listening — capture works for done parts", "best overnight, plugged in", "resumes if interrupted" — src: F:172, m/text-capture.html screen 3
- [needs-verdict] Reading-mode remainder: light/sepia/dark themes; the iPad measure question (~34em / 60-68ch) — src: m/audiobook-player-reading-mode.html "Still open", F:206
- [needs-verdict] P9b polish: sleep timer end-of-chapter + fade, per-book speed memory, skip-silence / volume boost, annotatable bookmarks, clips (quote audio .m4a / video card), skip-back-on-resume — src: R:1619-1632, R:2290-2313
- [needs-verdict] ePub images in the reader (the 44s calendar-art gap); book 2/3 ePubs when found — src: R:1560-1563
- [needs-verdict] i16 Book pages (per-book quote aggregation, one derivation → app Review/Books + vault literature note + plugin) — mock-first — src: R:2535-2543
- [needs-verdict] Book sharing device round: only AirDrop/Messages between two physical devices is left; neither sheet eyeballed by Tuur — src: R:1645-1650

### Search/retrieval

- [locked] Engine = EmbeddingGemma-300M at dim 512 via CoreML-LLM (bake-off 10/10 vs Apple NL 5/10 — eliminated, don't revisit); pick dim at load, never switch on a live instance; 295 MB runtime download; never run concurrently with ASR on the 13 — src: JRP "Engine" (2026-07-07), F:380
- [locked] Grain = ONE gist vector (title + summary + placeName + people + tags) PLUS body chunks at sentence boundaries every ~150-200 words; strip `**Name:**` headers before chunking; relevance = max over vectors, dedupe by memo; trashed excluded; captures included; book sidecars out — src: JRP "Grain", F:381
- [locked] Storage is derived-local, NEVER synced (own container `EmbeddingStore`); each device re-derives; sweep-based invalidation by `textHash`; brute-force cosine via vDSP — src: JRP "Storage"/"Index"/"Query", F:382
- [locked] Related floor 0.45 (calibrated on-device: random-pair p50 .31 / p90 .49); Mac lists the closest `relatedKMac`=7 with the EARLIEST match always kept (FIRST MENTION can't lie) + "Show all N" — src: R:1528-1530, F:386 (2026-07-20)
- [locked] Search "Related · similar in meaning" appears under exact Matches only when the query has ≥2 words or exact hits < 3; top 8 above floor minus exact hits; chips prefilter person/place/month/kind — src: m/journal-retrieval.html (signed 2026-07-06), JRP
- [locked] No similarity numbers on the phone — relevance = presence + order; on the Mac closeness = hover tooltip "N% match · shares: …" (always a %, never ambient); rows carry the P1 importance decimal (0.x, warm past 0.8), unrated rows show nothing — src: m/journal-retrieval.html, m/related-panel.html (P1 picked 2026-07-16)
- [locked] Corpus = Skrift memos only; the vault is NEVER indexed in v1; a later opt-in vault lens excludes `<vault>/Skrift/` and dedupes by skrift-id — src: JRP "Corpus"
- [locked] Juxtapose, don't judge: no sentiment / stance / mood inference anywhere; vault-side edits stay in the vault — src: JRP "Juxtapose"
- [locked] Looking back = spaced lookbacks 1 week / 1 / 3 / 6 / 12 months, highest-importance note per window, empty windows hidden, a literal "On this day" card once prior-year history exists; journal axis = `recordedAt` — src: JRP, F:385, R:1533 (b41 1-week window)
- [locked] Thread = `related()` sorted by date; header = first mention's title + date; RETIRED on iPad/Mac (it IS Connections in Date mode); survives ONLY on compact (the ≤4-row Related footer card) — src: m/journal-retrieval.html, F:386 (2026-07-25)
- [locked] Connections panel: ONE list + Date⇄Closest pill (Date = the arc rail with THIS NOTE + FIRST MENTION / CLOSEST MATCH flags; Closest = flat best-first rows); why-chips (people/tags/terms); hover-✕ = per-note hide; LINKED FROM lives inside the panel; in-panel consent gate: real download % → PREPARING (ANE compile) → indexing N of M → FINDING — src: m/related-panel.html v3 (signed 2026-07-16), F:386
- [locked] Connections is summoned by the WORD "Connections" (quiet → accent capsule), no ◨ glyph, no count badge (a count capped at 7 reads "7" forever = zero signal) — src: m/ipad-note-chrome-belongs.html (Tuur "perfect" 2026-07-24), F:386 (2026-07-25)
- [locked] iPad: Connections = a per-note VISITOR sheet over the note (never standing, never remembered, gone on note switch); Mac: a floating INSPECTOR that stays open across notes and re-queries; `NoteMeasure` narrows the column only when the window can't afford the overlay — src: m/ipad-note-chrome-belongs.html, F:386 (2026-07-25)
- [locked] One consent covers Related + thread + Journal search per device; index membership requires a RATED note (`joinsConnectionsIndex`); un-rate removes on the orphan pass — src: m/related-panel.html m4, F:64
- [locked] Tightness lens DEFERRED until the vault is connected; design agreed: a NAMED 3-step lens (Related 0.45 · Close ~0.60 · Tight ~0.80) beside the Date⇄Closest pill, LIVE counts, its own empty state, no step below 0.45, FIRST MENTION reads as scoped — not a slider — src: R:2439-2462 i13 (2026-07-25)
- [locked] Review rail mini-map = static `MKMapSnapshotter` under PLACES (A picked over map-first), merged pins, click → full map — src: m/review-minimap.html, R:354-358 (2026-07-17)
- [locked] Map contract on all three devices: owned camera, dive-down-only, pin tap never zooms out, in-frame card scrolls the selected place's notes; the map is a MODE of the column/pane, the river never leaves — src: m/ipad-app.html m4b, m/journal-desktop.html 1b, F:117
- [locked] Then-vs-now on all three devices from `Shared/Retrieval/ThenVsNow.swift` (juxtaposition only) — src: F:117, JRP fast-follows
- [locked] Journal on the Mac reads the CLOUD Memo store read-only; a card click jumps to the queue row when processed; an in-flight note is a slim row, never a card — src: m/journal-desktop.html (signed 2026-07-11), F:385
- [mechanical] Embedder held 10 min + unloads on background; warm-up at first keystroke; cold load ~42s on the 13 — src: R:1534-1540
- [mechanical] Search matches: title, transcript, summary, photo-OCR text, PDF text, link article text; a result tap scrolls + flashes the hit ~1.4s — src: F:43, F:53, F:147, F:153
- [mechanical] Print-to-wall: crossing INTO ≥0.8 silently prints ONE designed card to the saved AirPrint printer (offline queue + notification); "Important lately" atop Review = the wall's twin — src: F:388, R:2376-2385 i8
- [needs-verdict] Voice search (mic on the search field → one-shot ASR → semantic path) — fast-follow, rendered dimmed — src: JRP fast-follows, m/journal-retrieval.html S5
- [needs-verdict] Phase 2 vault lens Mac-first (index `<vault>/**/*.md` excluding `<vault>/Skrift/`, `source: vault` tag) + the vault's move to iCloud Drive — src: JRP "Phase 2"
- [needs-verdict] i18 mine-what-we-have: theme clustering, prosody heat, speaker-scoped retrieval, open loops — src: R:2565-2580
- [needs-verdict] Monthly digest (i15 / i20): map-reduce, model never sees the month, `-digest` harness on Tuur's real July — src: R:2520-2533, R:2599-2612
- [needs-verdict] Wall card design round + first physical print — src: F:388, m/wall-card.html
- [needs-verdict] `related-panel` m6 parked reading-column polish (tags under chips, smaller circles, chip icons) — partly absorbed by mac-note-header; the rest? — src: m/related-panel.html m6

### Editor & note UI

- [locked] The note body is ONE natively scrolling text view (header + footer hosted in its scroll); selection autoscroll / caret-follow / magnifier / undo / find come from UIKit; karaoke = attribute painting on the same view; saves debounced ~1s; B2 pinned title under the nav — src: m/note-editor-redesign.html (signed 2026-07-06), F:38
- [locked] Accessory bar v2 = variant B fixed verbs: undo · redo | ☑ · 📷 · → · Done (the ⋯ overflow dropped while all verbs fit); no play-from-caret, no append button; no "Save highlight" — src: m/accessory-bar-v2.html (2026-07-07), R:424-433, F:48
- [locked] Compact player pill ~44pt: play · ±10s · scrubber-with-times · speed; the whole pill is the scrub target; page dots → a transient "n / total" while swiping — src: m/note-editor-redesign.html, F:57
- [locked] Summary card joins the scrolling header (chips → importance → summary → body) — src: m/note-editor-redesign.html "Locked 2026-07-06"
- [locked] Must not break: inline `[[img]]`, capture-quote protection, speaker-turn view, `transcriptUserEdited`, save-now, polished-body editing, swipe-between-memos paging — src: m/note-editor-redesign.html
- [locked] Phone polished display: ONE editable body starting from the copy-edit (no raw/polished toggle); compact bottom-sheet title chooser (Suggested / From the recording / your own); summary card when the Mac wrote one; "✦ Polished on your Mac · ago" provenance; ordinary monologues only — src: m/phone-polished-display.html (2026-06-26), F:300
- [locked] Mac note header at the iPad's weight: title = ONE editable line with the suggested-vs-recording choice as two quiet words beneath (click REPLACES the title); ONE chips row (date · place · weather · daypart · source · duration · url/reminder/lock) flowing into tags + "+ add tag"; the 4-row properties table, card chrome and `author` row DELETED; include-audio stays a REAL switch, small, under importance; breadcrumb only on the locked path — src: m/mac-note-header.html ("sickk. i like it!" 2026-07-25), F:58, F:75
- [locked] iPad chrome = direction A with Tuur's refinements: the note owns ONE pinned 44pt bar — ◧ · ⟲10 ▶ ⟳10 · elapsed · scrubber (the FLEX element) · remaining · speed · ＋ (iPad/phone only) · Process · ⋯ · ◨; system nav toolbar hidden; Split speakers under ⋯; "Process" is the word on all three apps; processing replaces the button in place with step + n of 3 + a determinate bar; B (edge rails) rejected — src: m/ipad-chrome.html (signed 2026-07-23), F:119
- [locked] Graceful `Density`: portrait drops ±10 skips then time labels so the scrubber never vanishes — src: F:119 (fix wave 13269c1)
- [locked] "Chrome that belongs" v2: ONE pinned ◧ (the only panel glyph), a real toolbar with a hairline, two materials (list + Connections on `Palette.surface`, the note on the paper), text anchored to the list with a fixed ~28pt margin, the player DOCKS with a top hairline (phone keeps its floating capsule) — src: m/ipad-note-chrome-belongs.html + m/ipad-note-surfaces.html (2026-07-24)
- [locked] iPad stacking: ONE flat HStack (sliding 375pt list | workbench), chrome band spanning note + Connections, panels as fixed-width content in width-animated clipped windows (never unmounted), one `withAnimation`; the list column is a fixed 375pt (no drag-resize) — src: m/ipad-note-stacking.html (b130)
- [locked] The Mac note view MIRRORS the signed iPad chrome: floating glass capsule de-floated into a real bar with a bottom hairline, each control in a glass chip, transport inline; the bar gains the notes-list toggle ◧ — src: R:1008-1023 (2026-07-25), m/ipad-chrome.html "Mac — same bar, two changes"
- [locked] Regular-width note chrome band carries the full three-state primary · ⋯ · Connections (the ＋ chip folded into ⋯ as `addRecording`) — src: F:63 (2026-08-18), R:820-829
- [locked] List header at regular width = the Mac's construction: identity line + Import · Record · ✎ (compose chip, tooltip "New note (⌘N)") | Process N full-width + search + count line; the 30pt wordmark gone — src: m/mac-record-button.html B (2026-07-28), m/mac-new-note.html m2 (2026-07-28), F:120, R:820-823
- [locked] Process greys while recording — one mic, one job — src: m/mac-record-button.html "B · recording"
- [locked] ONE notes-list card (m2 = the iPad card): stamp + pill line, title, quote idiom for captures, 2-line snippet, chips (duration · place · #tags), 44px thumb slot, locked/quiet variants; per-app colour tables; sidebar ~292pt; "make sure the iPad also follows that one to the T" — src: m/mac-notes-list-rich.html (signed 2026-08-18), F:62
- [locked] Conversation turn gutter E1 + playing wash (b): right-aligned name in the speaker's hue, 2pt spine the turn's height, `headIndent` clears wrapped lines, playback washes the live turn in accent@7% (the spine means "who", never "now") — src: m/conversation-turns-D-hifi.html (signed 2026-07-27), F:255
- [locked] Tag chips have an explicit ✕ (tap-a-chip never deletes); comma input kept; tap-to-add suggestions most-used first; Mac = auto-focused typeahead (prefix, capped 8, "Create #x") with ≤4 deterministic quick chips — src: F:46 (2026-07-07 / 07-16)
- [locked] Tag sheet rework: no auto-keyboard, suggestions above the fold, merged vault + library source, typing demoted to one row at the bottom; the phone reads vault tags — src: m/note-destination-tags.html (A's sheet ships as B's, 2026-08-26), F:68
- [locked] Destination row sits beside the importance circles, rests as ONE chip, expands to four in place on tap; Personal = quiet purple chip and nothing else; an archive destination also names its folder + "AI READS THIS"; B4 (inline with tags) REJECTED — src: m/note-destination-tags.html (2026-08-26)
- [locked] Journal on the Mac: sidebar Queue|Review switch; rail = dot-density mini calendar + places (+ mini-map); column = Looking-back river; a day selects into the column; map mode swaps the column, ⨯ returns; the rail never changes — src: m/journal-desktop.html (signed 2026-07-11), F:385
- [locked] Journal §3 body-parity panels on the Mac: memo-link chips (click opens target) + LINKED FROM; live checklist toggles write the SOURCE text via Part-B sync; locked panel with Touch ID; PDF capture inline (phone variant A) — src: m/journal-desktop.html §3, R:1316-1326 DParityB
- [locked] Context chips (place · weather · daypart) on both apps from the synced typed metadata; `DayPeriod.symbol/label` shared — src: F:75 (2026-07-16)
- [locked] Locked-note placeholder: list shows title + 🔒 only; detail placeholder gates content; pager/notifications can't bypass — src: F:41
- [mechanical] Dynamic Type on the editor body; full-app sweep still open — src: F:55
- [mechanical] Row label: titled memos lead with the title (snippet secondary); every row carries a leading source glyph from the shared `SourceTaxonomy` — src: F:83, R:567-568
- [locked] Sorts = Recently added (default) / Recently edited / Recently recorded / Oldest / Longest; day headers follow the sort; filters place / photos / unsynced / date range — src: F:85 (2026-06-14)
- [needs-verdict] i10 Obsidian-grade markdown body: bold/italic/==highlight==/strike live in BOTH bodies; phone headings + inline-# popup; ⌘B/⌘I Mac + B/i/🖍 accessory buttons phone; ~2-3 sessions Mac-first — src: R:2342-2355 (pinned 2026-07-16)
- [needs-verdict] CapNote: a capture opens as one normal editable note — the annotation folds into the body, file/PDF becomes a body block (marker machinery generalised); touches C3 + exporter + Mac; mock-first — src: R:1400-1418 (inprogress, nothing shipped)
- [needs-verdict] Mac thumbnails (m2 chunk 3b, cached loader not per-row decode) and Mac place/tags chips (join via cloud Memo) — parked, "if Tuur wants them" — src: R:692-694, B:875-876
- [needs-verdict] Selection handles: not retested since build 35; armed probes in b39 — src: R:505-507
- [needs-verdict] Scan-into-this-note accessory verb (today scan = a NEW memo) — src: R:512, m/accessory-bar-v2.html "open"
- [needs-verdict] The Mac's "Mark all as Passing" wording question — src: R:895
- [needs-verdict] Apple-Notes-bar note editing + drag-multi-select lasso replacing the Select button (wants a mock) — src: B:8642, B:788
- [needs-verdict] iPad `ipad-player-position` A (native chrome + bottom player) / B / C — never picked; superseded in practice by the docked player of "chrome that belongs"? — src: m/ipad-player-position.html
- [needs-verdict] Mac in-place name linking as interactive as the phone's (i6 half 2) — src: R:2409-2412

### Other

- [locked] Standalone push: $0.69, no IAP; CloudKit internal sync (not iCloud Drive); one-way Obsidian publish; on-device Polish = a GATED spike; Mac + Obsidian = optional sinks over one source of truth — src: `CLAUDE.md` STANDALONE_PLAN summary, R:1670-1684 P11
- [locked] The product ladder: phone alone → add Mac/iPad for processing → add Obsidian + the plugin for power users; the plugin does NOT compete with the standalone push and needs no App Store cycle — src: R:847-864 ObsidianPlugin
- [locked] Plugin v1 bundle = (2) the real inbox + (4) sync doctor + (1) listen to any note — all vault-files-only (work in Obsidian on iPhone/iPad); Connections is Mac-live ONLY (static sidecar REJECTED: "dont like stale data"); don't start until Tuur picks off the menu — src: R:855-864, m/obsidian-plugin-menu.html
- [locked] iPad = the same SkriftMobile app (never a third app), same four tabs, all orientations; compact = the phone app byte-for-byte; prose capped at a reading measure (~68ch); phone bones everywhere, MAC dress for Mac jobs, system chrome where iPadOS owns it — src: IP "Product shape", R:878-881
- [locked] Roles: phone captures (source of truth); iPad = reading room + on-demand polisher; Mac = factory + sink (automatic, unattended) — src: IP roles table
- [locked] Shared code FIRST: anything living on both apps (logic, labels, constants, wire structs) is single-sourced in `Shared/` in the same change — src: R:327-332 NFeat HARD RULE, R:220-221 SharedKit win
- [locked] Mock-first is the locked process for new UI; a mock Tuur approved IS the spec; "your mock differs from the app" = blocking defect — src: `CLAUDE.md` Ledgers, m/lifecycle-ia-explorations.html "Receipts"
- [locked] Dev/prod isolation: per-config bundle IDs, App Groups, CloudKit containers and UTIs; Dev accepts both — src: `CLAUDE.md` Dev vs prod, m/book-sharing.html
- [locked] Auto-copy transcript to clipboard is opt-in, default OFF — src: F:357 (2026-06-11, user-locked)
- [mechanical] Settings → Models: Transcription / Speaker recognition / Custom-word spotting with size-on-disk; manual Download + retry for Transcription — src: F:129
- [mechanical] Live Activity pushes a word-aligned ~220-char caption TAIL at ≥1.5s; intents are plain `AppIntent` + `openAppWhenRun` (SIGTRAP-safe); ❝ glyph on CC tile + widgets — src: F:364-366
- [mechanical] Location / weather / day-period / steps / pressure captured on the phone, rendered by the Mac into frontmatter — src: F:372
- [needs-verdict] P4 on-device polish: the iPhone 13 spike is the gate (zero jetsam + ≥300 MB headroom, ships no-polish if it fails); Apple Intelligence needs A17 Pro / M-series so the 13's answer is "the Mac does it"; P4b adaptive picker; P4c ramble modes = prompts + picker over existing plumbing — src: R:1436-1454, R:2581-2598 i19, m/standalone-models-polish.html
- [needs-verdict] P3 remainder: standalone onboarding rewrite (mock unsigned; open: "iCloud" vs "across my devices" copy, Connect-a-Mac placement, hard-require the engine before Start?) — src: m/standalone-onboarding.html, R:111-115
- [needs-verdict] P6 Commonplace Book: Highlights feed (in the book context, not a tab), Daily Review (opt-in vs always-on, 3/day?), shareable quote card (tint for cover-less memos?) — src: m/standalone-commonplace-book.html, R:1455-1471
- [needs-verdict] P5 Organization: the folders model is an OPEN decision — don't build until decided; pins + nested tags — src: R:1472-1486
- [needs-verdict] P7 People & backlinks: person pages with profile + voice + every mention — src: R:1487-1499
- [needs-verdict] P11 App Store readiness: privacy nutrition label, screenshots + copy, review prep (graceful model download, plain AppIntent) — src: R:1670-1684, R:2322-2341
- [needs-verdict] AuditFix2 D1-D3 data-loss paths: `names.json` non-atomic write (LWW propagates the loss), re-transcribe clears the transcript when audio is missing, vault attachment copy deletes a file the ledger doesn't claim; plus P1-P4 main-thread lag items — src: R:1685-1712
- [needs-verdict] Send-feedback desktop port deferred — src: F:358
- [needs-verdict] i9 voice-over easter egg (no spec — don't node until a design pass) — src: R:2422-2428
- [needs-verdict] i22 EventKit "during / just after" + SoundAnalysis ambient labels (permission + eyeball pass first) — src: R:2625-2637
- [needs-verdict] P10 Apple Watch capture — deferred (user has no Watch) — src: R:1713-1724

---

## B · MOCK INVENTORY (71 HTML + 1 MD)

Status key: **S+B** = signed-off + built · **S+NB** = signed-off, NOT built (or a named remainder unbuilt) · **SUP** = superseded · **EXP** = exploration / unsigned proposal. ⚑ = approved-but-unbuilt (flagged per brief).

| # | File | Specifies | Status | Maps to |
|---|---|---|---|---|
| 1 | accessory-bar-v2.html | Accessory bar A vs B (B picked) + inline-photo display block | S+B 2026-07-07 (same day) | NFeat; F:48, F:54 |
| 2 | audiobook-bookmark-fold.html | Dog-ear bookmark on the active read-along line; no Mark button | S+B 2026-06-21/22 (b16-20) | D3; F:207 |
| 3 | audiobook-capture-merged.html | Full-screen player + ONE note-style capture screen; audio arm retired | S+B 2026-06-13 | H_sprint; F:177 |
| 4 | audiobook-capture.html | Original 5-state quote capture (micro-scrubber, mark in/out, capture sheet, mini-player) | SUP (audio mark-in/out retired 2026-06-13); flagged choices 1-5 mostly rebuilt later | H_sprint; F:229-232 |
| 5 | audiobook-player-reading-mode.html | Reading mode, tab-bar IA, Aa, dog-ear ribbon, delete confirm | S+B 2026-06-19 build 14 per F:196-210 + R:1984-1992 D3 done ⚑ CLAUDE.md still says "not yet built" — see D1. **Remainder S+NB:** light/sepia/dark themes; iPad measure Q | D3; F:196-210 |
| 6 | audiobook-player-redesign.html | Text-forward A+D hybrid player, bookmarks, Chapters/Bookmarks sheet | S+B 2026-06-13 | H_sprint; F:180-194 |
| 7 | book-sharing.html | `.skriftbook` one-file share, importer, UTI, format | Per R:1633-1669 signed 2026-08-11 + built + round-trip PROVEN 2026-08-12 ⚑ CLAUDE.md says "NOT signed off yet"; memory says branch `claude/book-sharing-devices-rygara` NOT on main — see D2. Owed: two-device AirDrop/Messages, Tuur's eyeball of both sheets | BookShare |
| 8 | book-text-sheet.html | 3 variants for the multi-ePub sheet; B timeline-first picked | S+B 2026-07-22 (b95-102, device-confirmed) | EPubAlign; F:189 |
| 9 | book-text-unified.html | ONE "Text…" verb, Level 1/2, A0 import prompt | S+B 2026-07-23 (same session); mock header still says "NOT BUILT" — see D23 | EPubAlign / i12; F:190 |
| 10 | books-tab-and-resume.html | Books tab, global capsule, cold-launch resume, sort/filter chip, "Add note" | S+B 2026-07-07; capsule-everywhere later SUP by card-at-rest / pill-when-live (b46-51) | D4; F:213-223 |
| 11 | capture-items.html | Share URL/text/image: sheet → phone → Mac (C3) | S+B 2026-06-12 | H_sprint; F:141-159 |
| 12 | capture-redesign.html | 4 audio-marking concepts (Hybrid ⭐ shipped, then retired) | SUP 2026-06-13 | text-capture-DESIGN §0 |
| 13 | capture-sheet-trim.html | Sentence-level trim on the capture sheet | SUP (interaction promoted into the merged select screen; trim skipped in Text mode) | F:166; text-capture-DESIGN §1, §14 |
| 14 | conversation-turn-headers-D.html | D1-D6 gutter wireframes | EXP (D1 picked → hifi) | W6 |
| 15 | conversation-turn-headers.html | A/B/C/D — how much syntax a speaker label wears | EXP (D chosen) | W6 |
| 16 | conversation-turns-D-hifi.html | E1 right gutter + colour per speaker, playing wash (b) | S+B 2026-07-27 Mac ("way better looking"); phone = hues only on its cards | W6; F:255 |
| 17 | fading-shelf.html | Fading shelf v3 (rail row / phone ⋯), Keep / Sweep now, first-run prompt | S+B 2026-07-17/18 → then SUP by LifeIA conveyor (2026-07-21) + one clock (2026-07-22) — see D7 | NFeat; F:87 |
| 18 | index.html | Duplicate of v2.html (review surface v2) | SUP | H_desk |
| 19 | ipad-app.html | Wave-1 m1-m7 + m1b; v2 verdicts inline | S+B 2026-07-22/23 (v2 same-day) | IPadWave1; F:103-123 |
| 20 | ipad-chrome.html | 3 chrome directions; A signed with bar refinements | S+B 2026-07-23 (b120) | IPadWave1; F:119 |
| 21 | ipad-note-chrome-belongs.html | v2 "chrome that belongs": visitor Connections sheet, word summon, one ◧, docked player | S+B 2026-07-24 (b132, Tuur "this looks soo good"); mirrored to the Mac 2026-07-25 | IPadWave1; F:386 |
| 22 | ipad-note-stacking.html | Rebuilt stacking (flat HStack, pinned ◨, fixed 375 list) | Built 2026-07-24 (b130) | IPadWave1 |
| 23 | ipad-note-surfaces.html | Surfaces pass (two materials, toolbar hairline, docked player) | Built 2026-07-24 (b131) | IPadWave1 |
| 24 | ipad-player-position.html | Where the player lives: A native / B custom / C keep top | EXP; no pick recorded; the docked player of #21 resolved it in practice — see D-list | IPadWave1 |
| 25 | journal-desktop.html | Journal on Mac (§1 rail+column, §1b map mode), iPad §2, §3 body-parity panels | Signed 2026-07-11. §1/1b built 2026-07-13 (Mac); §2 built 2026-07-22/23 (iPad); §3 memo-link chips + checklists + lock BUILT; **§3 PDF-inline on the Mac S+NB** ⚑ ("inline first-page render on the Mac" = follow-up) — CLAUDE.md still says "not yet built" — see D3 | DParityB (inprogress); F:385, F:147 |
| 26 | journal-retrieval.html | P8 five surfaces (Journal home, calendar, map, thread, search, Related card) | S+B 2026-07-06/07; tab renamed Review; thread later retired at regular width | P8 done; F:376-388 |
| 27 | lifecycle-ia-explorations.html | Five-axis problem, the spine, 3 directions; 2 + conveyor picked; Q1-Q7 | S+B 2026-07-21 (locked + built same day); only Tuur's walkthrough owed | LifeIA (inprogress); F:87 |
| 28 | lifecycle-triage-peek.html | Peek repair m0-m6; m6 = the build spec | S+B 2026-07-22 | LifeClock done; F:87 |
| 29 | mac-live-transcription.html | m1-m5; m2 picked, m4 trimmed | S+B 2026-07-28; owed: mid-take edit LIVE check, paragraph eyeball, clean phone re-run | W8 (inprogress) |
| 30 | mac-new-note.html | Typed note on the Mac; m2 compose chip picked | S+B 2026-07-28 | W9; F:61 |
| 31 | mac-note-header.html | Mac header at the iPad's weight | S+B 2026-07-25 ("sickk. i like it!"); include-audio-on-iPad deferred with reason | IPadWave1 r3; F:58, F:75 |
| 32 | mac-notes-list-rich.html | m1 compact-rich vs m2 iPad card (m2 picked) | S+B 2026-08-19 (m2 signed 2026-08-18). **Remainder S+NB ⚑:** Mac thumbnails (3b) + Mac place/tags chips | NoteCardM2 (inprogress); F:62 |
| 33 | mac-record-button.html | Record verb A/B/C/D; B picked (Import + Record pair, Process full-width) | S+B 2026-07-28 | W7 done; F:307 |
| 34 | name-a-speaker.html | Click "Speaker 2" → pick a person; links every turn + learns the voice | S+B via naming chunk 4 (2026-06-16) as the in-prose popover; "learns the voice on pick" on the Mac unverified in F:74 | P0; F:74 |
| 35 | name-unlink.html | Two unlink scopes + undo toast | S+B (F:342) | P0; F:342 |
| 36 | names-mac.html | Mac Names screen at phone parity (avatars, voice status, side-by-side editor) | EXP / unsigned; list→detail editor built 2026-06-15 (F:343), parity remainder = idea i6 ⚑ | i6 → P7; F:343 |
| 37 | naming-review.html | Opt-out + risk-tiered naming, 3 tiers, popovers | S+B 2026-06-16 | P0; F:336, F:339 |
| 38 | note-destination-tags.html | A/B/C; B collapsed signed; tag sheet rework | S+B 2026-08-26/27 (b156-164); device round + merge to main owed | ExportDestinations (inprogress); F:68 |
| 39 | note-editor-redesign.html | Editor re-foundation, B2 pinned title, accessory, compact player | S+B 2026-07-06/07 | NEdit done; F:38, F:57 |
| 40 | notes-book-presence-debate.html | Card vs live chrome vs Hendri's dashboard | EXP; "cards for starting, chrome for controlling" picked → built | D4; F:218 |
| 41 | notes-bottom-chrome.html | A split row vs B centered record | EXP; A → built (60pt row) | D4; F:218 |
| 42 | notes-compact-header.html | Compact header + Continue-listening card above search | S+B (b49) | D4; F:217-218 |
| 43 | notes-pill-v2-iterations.html | V2a / V2b / V2c separation | V2a picked + built | D4; F:218 |
| 44 | notes-pill-variants.html | V1 / V2 / V3 pill interiors | EXP; V2 picked → iterations | D4 |
| 45 | obsidian-plugin-menu.html | 10 plugin wireframes + recommended v1 bundle | EXP menu; NOT built; Tuur's verdicts in backlog 🔌 (Connections static tier rejected) ⚑ | ObsidianPlugin (planned) |
| 46 | opt-in-naming.html | Opt-in naming (2026-06-15) | SUP by naming-review 2026-06-16 | P0 |
| 47 | pdf-inline-capture.html | PDF first page inline (A) vs page strip (B) | S+B 2026-07-07 phone (A). **Mac inline S+NB ⚑** (F:147 follow-up) | NFeat / DParityB; F:52, F:147 |
| 48 | phone-name-linking.html | Phone 4-tier name linking, dialogs, chip bar, person editor | S+B 2026-06-25 | P2; F:335 |
| 49 | phone-polished-display.html | Mac polish visible on the phone, title chooser, summary, provenance | S+B 2026-06-26 | P2; F:300 |
| 50 | related-panel.html | Connections on the Mac v3 (Date⇄Closest, P1, hover %, gate, collapse) | S+B 2026-07-16; chrome later SUP (word summon, no badge, floating inspector 2026-07-25); m6 polish PARKED | NFeat / P8; F:386 |
| 51 | resolver-inline.html | R3 inline disambiguation A/B/C (A recommended) | Popover idiom built (chunk 4); the per-occurrence promise resolved AWAY to whole-note — see D13 | P0; F:339 |
| 52 | review-minimap.html | A rail mini-map vs B map-first | S+B 2026-07-17 (A) | NFeat; R:354 |
| 53 | review-note-detail.html | Read-only detail for unpipelined Review cards + "Process on this Mac" | SUP by LifeIA ② (2026-07-21) → `UnpipelinedMemoSheet` → MemoNoteProjection "an unrated note IS a normal note" (2026-07-26); its open Qs void | LifeIA; F:60 |
| 54 | share-ingest-wave1.html | Audio single / 8-clip chooser / photos / feedback states | S+B 2026-07-10 (device-verified b60-63) | ShareW1 done; F:148-150 |
| 55 | share-ingest-wave2.html | E1 video/PDF sheets, PDF text disclosure, voice-annotate | Green-lit "as drawn" 2026-07-12 + built (Wave 3); voice-annotate UNVERIFIED; its 4 round questions never answered | ShareW2 done; F:153 |
| 56 | significance-circles.html | Slider → 10 circles both apps | S+B 2026-06-11; i23 (3 buttons) proposes to supersede — mock pass owed | H_sprint; F:59; R:2639 |
| 57 | standalone-audiobook-sync.html | Per-book sync toggle, source/receiver states, Apple Books model | Locked 2026-06-18 + built (builds 5-13) | D1/D2; F:291 |
| 58 | standalone-commonplace-book.html | P6 Highlights feed, Daily Review, quote card | EXP; NOT built; 3 decisions open ⚑ | P6 (planned) |
| 59 | standalone-export-obsidian.html | Phase-2 export sheet, first-run vault pick, Settings Export, batch export, alias editor | Engine built 2026-06-21; the `<vault>/Skrift/` subfolder, "Only important" scope and phone-off-when-paired are SUP by SharedExport (2026-07-26) + 2026-08-11 — see D12; batch export state 4 unverified in FEATURES | P2 (inprogress) |
| 60 | standalone-models-polish.html | Models tab + Polish row per device + polished memo display | Models tab built 2026-06-12 (F:129); Polish row / Apple Intelligence engine NOT built (P4; i19: the 13 can't run FM); memo display SUP by phone-polished-display | P4 (planned); F:129 |
| 61 | standalone-naming-review.html | Earlier phone name-linking draft | SUP by phone-name-linking.html (2026-06-25) | P2 |
| 62 | standalone-onboarding.html | 3 onboarding states + standalone Settings IA | EXP / unsigned; Settings de-Mac'd built (Part A 2026-07-06); onboarding rewrite NOT built ⚑ | P3 (inprogress), P11c |
| 63 | text-capture.html | Text-first capture v3 (select / warming / transcribe / settings / no-speech) | S+B 2026-06-13, then folded into the merged screen | H_sprint; F:166-172 |
| 64 | text-capture-DESIGN.md | Design decisions for text-first capture + resumability | Companion doc; built; A/B concluded (Audio removed) | H_sprint; F:165 |
| 65 | unrated-shelf.html | A third "Unrated" shelf in the Review rail; A vs B row action | SUP by lifecycle-ia (band inside the Queue instead of a shelf; Q1/Q2) | LifeIA |
| 66 | v2.html | Desktop review surface v2 | EXP (iteration) | H_desk |
| 67 | v3.html | Review surface v3 (sidebar reworked) | EXP (iteration) | H_desk |
| 68 | v4.html | Review surface v4 (use-driven sidebar) | EXP (iteration) | H_desk |
| 69 | v5.html | Review surface v5 (glyphs, native select, wider body) | S+B 2026-06-07 (the shipped desktop shell) | H_desk; R:1858 |
| 70 | vault-folder-model.html | Mac's 3 vault fields → the phone's one pick; A vs B; PDFs/video | EXP / OPEN — needs Tuur's A-or-B ⚑ | SharedExport (inprogress) |
| 71 | wall-card.html | WallCardView print preview | Built 2026-07-07 (WallPrinter, b43); physical print + card-design round owed | P8 / i8; F:388 |
| 72 | wayout-phone-placement.html | Conveyor on the phone: A ⋯ / B Review row / C both | B picked + built 2026-07-21 (b88-91) | LifeIA; R:570 |

Approved-but-unbuilt, explicit list: #5 remainder (reading themes), #25 §3 Mac PDF-inline, #32 remainder (Mac thumbnails + place/tags chips), #47 Mac inline, picture drag-reposition (no mock yet — B:900 says mock first), #7 device round (and its branch status), #70 (needs a pick), #45, #58, #62 (unsigned explorations with decisions still open).

---

## C · DONE-STATES

### The 15 `inprogress` roadmap nodes

| Node | done when: (what Tuur holds/sees) | Still owed |
|---|---|---|
| P2 Export & Obsidian publish | done when: a phone memo lands in the vault with on-device name-links, no Mac involved — on the iPhone 13 he taps the verb and sees the file in Obsidian (R:97) | Per F:67 the PHONE can't export any more (only processing devices) — the win as written is now false; needs re-word to "iPad/Mac export a processed note, phone reads the vault"; batch export + i1 Export All unowned |
| P3 De-Mac the UX | done when: first run on the iPhone 13 never mentions a Mac; Settings is capture-first; Importance relabel everywhere (R:114) | Standalone onboarding rewrite (mock #62 unsigned); Importance/pin reframe nod |
| Stz020 Stabilize 0.2.0 | done when: a memo recorded on his PROD phone shows up polished on his PROD Mac (CloudKit prod schema deployed) and the 5 findings are cleared (R:273) | Prod schema deploy + Release App ID push/iCloud; IJsbrand alias seed; phone add-as-name; conversation over-tagging (likely closed); vocab LWW device round-trip |
| NFeat Note feature wave | done when: the six gap features run on BOTH apps from shared code — a locked note stays out of the vault, an OCR'd photo is searchable, a reminder rings on whichever device he holds (R:519) | Mac reminder reconciler; prod schema deploy; selection-handles repro; viewer-zoom eyeball; scan-into-note verb |
| LifeIA Lifecycle IA | done when: every note carries ONE honest status on both apps — he walks the Mac Dev + phone over the one-clock vocabulary and sees no zombie row, one Recently Deleted, one conveyor (R:531) | Only Tuur's walkthrough of both apps |
| SharedExport ONE export engine | done when: the same note exports byte-identical from Mac and iPad into the folder he picked; foreign/edited files never overwritten; the iPad exports photos + audio (R:641) | Tuur's first real-device run (throwaway folder first); Re-export flip on a vaulted device; includeAudio sync parked; vault-folder-model A/B pick |
| NoteCardM2 ONE note card | done when: Mac sidebar and iPad list render the SAME card and he sees photo thumbs + book-quote rows on b155 / Dev Mac (R:690) | Tuur's eyeball both sides; 3b Mac thumbnails (cached loader); Mac place/tags chips |
| RateToRow rating hands to pipeline | done when: rating any note on the Mac (typed included) produces its pipeline row and no rated note is ever invisible (R:731) — promoted + verified on his real store 2026-08-20 | Tuur's own redo on his important note to see the paragraphs hold |
| ExportDestinations four destinations | done when: a note carries ONE of four destinations picked in one tap on the note and a Personal note can never land in the archive; he sees `_ideas/<name>.md` beside its media on his Mac (R:758) | Phone/iPad device round (throwaway folder), merge to main |
| IPadWave1 iPad reading room | done when: on the iPad Pro he sees list↔note split, Review river + standing pane, Books shelf + wide reader, record card + ⌘-keys, and a ✨ Polish that writes a MemoEnhancement the Mac honours (R:874) | Mac eyeball incl. the snapshot-blind ⋯ chip; polish + prompt-sync live test on the iPad; the undiagnosed "could not process"; "Mark all as Passing" wording; promote to main |
| RecHard Recording hardening | done when: his hot iPhone 13 records a 10-min memo without freezing and a call/Siri/alarm mid-recording never silently kills capture (R:1303) | Device round on the 13 (devlog snapshot-ms; call/alarm survives; camera latency; freeze gone); b119 count-to-10 with AirPods + speaker |
| DParityB Desktop B-list + Journal | done when: the Mac renders checklists, memo-link chips and PDF captures like the phone, and Journal mode shows Looking-back + map from the shared rules (R:1324) | Mac PDF-inline first-page render + C3 text fallback (unbuilt); live round-trips for delete/tags/link-picker (device); i5 tail |
| CapNote Capture reads as a note | done when: a capture opens as one normal editable note — annotation in the body, file/PDF as a body block — on phone, export and Mac (R:1416) | Everything: mock first, then build; waits on the body/image v2 |
| Podcasts → Books | done when: a podcast episode shared into Skrift lands in Books, plays with read-along and quote-captures like a book (R:1434) | Everything; no shipped entries — status looks aspirational |
| W8 Mac live transcription | done when: he talks, the note writes itself in front of him, he fixes a word mid-take and the fix survives; words final on stop, unrated (R:2095) | Mid-take edit LIVE check (chip + survival); resting-note paragraph eyeball; karaoke-after-edit decision (parked); clean phone suite re-run before prod |

### Approved-but-unbuilt mocks (+ the named parked items)

| Item | done when: | Owed |
|---|---|---|
| audiobook-player-reading-mode remainder (#5) | done when: on the iPhone 13 the Aa sheet offers Light / Sepia / Dark and the page recolours | Unbuilt (themes); confirm the core reading mode itself matches the mock on device (D1) |
| journal-desktop §3 Mac PDF-inline (#25) | done when: a shared/scanned PDF shows its first page inline in the Mac note column with an "N pages" chip, tap opens it | Unbuilt on the Mac (phone built) |
| picture drag-reposition (B:900) | done when: he long-presses a photo in a note on the iPhone 13 and drops it between two other paragraphs; export shows it there | No mock; design/mock first; waits for body/image v2 ("move a block") |
| Mac thumbnails 3b (#32) | done when: a photo note shows its 44px thumb in the Mac sidebar card without per-row decode lag | Unbuilt (cached loader) |
| Mac place/tags chips (#32) | done when: the Mac card shows place + #tags chips exactly like the iPad's | Unbuilt; "if Tuur wants them" — needs his yes |
| book-sharing (#7) | done when: he AirDrops `The Odyssey.skriftbook` from the iPhone 13 to another person's phone and it plays with read-along + Ch 1/13 on arrival | Two-device AirDrop/Messages round; both sheets eyeballed; branch landing (memory: not on main) |
| vault-folder-model (#70) | done when: the Mac Settings shows ONE Obsidian folder pick and his 0 Inbox/Skrift layout doesn't nest a second Skrift/ | Tuur's A-or-B + folder names + PDFs/video scope |
| names-mac / i6 (#36) | done when: Settings → Names on the Mac shows avatars + voice status + a side-by-side editor, and a linkable word is dotted + clickable on a RAW transcript before enhance | Unsigned; not built |
| obsidian-plugin-menu (#45) | done when: in Obsidian on his Mac a Skrift note plays inline with karaoke, the inbox files a note into PARA and Skrift follows it, and the sync doctor names a conflict copy | Tuur picks his features; TypeScript repo; nothing built |
| standalone-onboarding (#62) | done when: a fresh install on the iPhone 13 walks Record anywhere → Private + engine download → Sync your devices, Mac demoted to "Connect a Mac (optional)" | Unsigned; three open copy/placement questions |
| standalone-commonplace-book (#58) | done when: inside a book he sees its quotes as a feed, gets one Daily Review card, and shares a 1080×1080 quote card | Unsigned; nav placement, cadence, tint open |
| i23 three-button importance (R:2639) | done when: the note shows Not / Somewhat / Medium / Very (3 or 4 buttons) instead of 10 circles on all three apps; legacy 0.5/0.7/0.9 still bucket | Mock pass first (re-baseline both render gates); the refine-pass escape-hatch decision |
| i10 markdown body (R:2342) | done when: `**bold**`, `*italic*`, `==highlight==`, `~~strike~~`, headings and inline #tags render live on the iPhone 13 AND the Mac with dim-visible marks | ~2-3 sessions, Mac-first; unbuilt |
| share-ingest-wave2 open Qs (#55) | done when: the four round questions have a recorded answer (video thought, PDF text in export, collapsed-by-default, mic pill scope) | Verdicts only |
| CapNote mock (R:1400) | done when: the mock is signed — a capture rendered as one note with the file/PDF as a body block | Mock; then build after body v2 |

---

## D · CONTRADICTIONS

1. **Reading-mode built or not** — `CLAUDE.md` Ledgers: audiobook-player-reading-mode "signed off 2026-06-19 — not yet built" vs F:196-210 "built 2026-06-19 (build 14)" + R:1984-1992 D3 `done 2026-06-19`. Only the reading themes are unbuilt.
2. **Book sharing signed or not** — `CLAUDE.md`: "NOT signed off yet; board = backlog 📦" vs R:1633-1669 BookShare `done 2026-08-12` ("2026-08-11 signed off, then built end to end … round trip PROVEN"). Memory: branch `claude/book-sharing-devices-rygara` NOT on main; check whether R's done-date reflects main.
3. **journal-desktop built or not** — `CLAUDE.md`: "signed off 2026-07-11 — not yet built" vs F:385 Mac Journal built 2026-07-13, F:117 iPad §2 built 2026-07-22/23; DParityB still `inprogress` for the §3 Mac PDF-inline.
4. **Photo block: export changed or unchanged** — m/accessory-bar-v2.html: "the breaks are display-only … sync, export, and the Mac see no difference" vs F:54 (2026-07-16): the snap transform "drives BOTH renderers AND the Obsidian export" (export output DID change). The v2 plan (B:700) returns export to non-transforming.
5. **Flag-to-send vs flag-to-process** — m/significance-circles.html + m/capture-items.html + m/audiobook-capture.html: "0 = stays on the phone, >0 = syncs" vs R:340-343 (2026-07-20) "CloudKit syncs everything; the rating gates the Mac's pickup"; F:269 row header still says "flag-to-send" while its body says LIVE gate = ingest.
6. **"Waiting" sync pill** — F:84 ">0 keeps Waiting/Synced" vs R:150-151 (2026-07-06) "per-memo 'Waiting' sync pill removed (statusKind no longer Bonjour-keyed)". F:84 is stale.
7. **Fading doctrine superseded twice** — m/fading-shelf.html "Keep = never fades again; a kept or re-touched note can't come back here" + first-run "Start the timers" prompt vs F:87 b84 (timers automatic from install) vs m/lifecycle-triage-peek.html m5/m6 (2026-07-22): touch RESTARTS the 30d clock; "touched never fades" revoked with Tuur's explicit yes.
8. **Diarization late-asset heal** — R:2053 W3 note: "The `diarization` asset still has no heal — same race, same shape, owed"; F:56: "(The `diarization` asset has the same race and NO heal yet.)" vs R:2071 W4 shipped the same day: "diarization late-asset heal — the wordTimings twin". One of the three is stale.
9. **FluidAudio pin** — F:317 "pinned to `7f963cdc` in both project.yml" vs R:1613-1615 EPubAlign "FluidAudio pin bumped v0.15.2→v0.15.5 both apps". FEATURES never updated.
10. **Thread view** — m/journal-retrieval.html + F:387 (phone Related card "View thread") vs F:386 (2026-07-25): View thread RETIRED on iPad + Mac, survives only on compact. The mock's "threads are not a Journal-home list" is still true; the CTA location changed.
11. **Chapter precedence wording** — F:173 "Detected chapters WIN over file-split/embedded everywhere" vs F:187 "ePub TOC > detected > embedded (Q1 lock)". Consistent as an ordering; F:173's "everywhere" predates the ePub layer.
12. **standalone-export-obsidian vs SharedExport** — mock #59: writes only into `<vault>/Skrift/` (Voice Memos / Audiobook Quotes), publish scope "Only important (>0)", phone publish OFF when a Mac is paired; vs F:70 (2026-07-26) "picked folder IS the destination, `Skrift/` prefix + source subfolders GONE" and F:67 (2026-08-11) export only from processing devices of PROCESSED notes. The mock's Settings/first-run screens are superseded; its share/export verbs are still the only spec for batch export.
13. **Per-occurrence vs whole-note resolution** — m/resolver-inline.html A promises per-occurrence ("two friends named Jack stay separate") vs m/naming-review.html + m/standalone-naming-review.html (locked): pick once → whole note; a second Jack is tapped separately.
14. **Include-audio on the phone** — m/mac-note-header.html (2026-07-25): "The phone's publisher copies no audio at all" vs F:70 (2026-07-26, one day later): the phone publisher gained "photos→embeds, audio, lazy blobs". The mock's deferral reason is half-stale; the flag still never syncs (R:659 "includeAudioInExport sync parked").
15. **BookTranscript local-only** — m/standalone-audiobook-sync.html "BookTranscript stays device-local — re-derives per device" vs F:291 build 13: read-along transcript sidecars sync as `ab_<bookID>_t<i>` and are re-stamped. The mock predates build 13.
16. **"Process on this Mac" / silent 0.1** — m/review-note-detail.html + m/unrated-shelf.html A ("Process" sets 0.1) + m/lifecycle-ia-explorations.html Q2 (band Process → 0.1, built 2026-07-21) vs m/lifecycle-triage-peek.html m2/m6 (2026-07-22): "the rating IS the flag — no hidden 0.1", Flag verb removed 2026-07-23 (m/ipad-app.html m1b). Yet R:559 MacMemoAuthor still floors Mac-local uploads at 0.1 and F:64 keeps "0.1-floor import = rated" as a deliberate door. Two 0.1s: one killed (the button), one kept (the import floor).
17. **CloudKit schema freeze** — JRP gotchas (2026-07-06): "Do NOT add fields or models to the CloudKit config — the prod schema deploy (Stz020) is still pending" vs F:41/42/87/68/123: `locked`, `remindAt`, `keptAt`, `trashSeenAt`, `destination`, `PolishPromptsRecord` all added since. The rule was not followed; Stz020's deploy is now larger.
18. **Journal vs Review** — JRP + m/journal-retrieval.html + m/journal-desktop.html name the tab "Journal"; shipped name is "Review" (R:1527, F:217 "Journal took the slot" then renamed). Mocks and plan use the old word.
19. **Podcasts node** — R:1419-1435 `status: inprogress` with no `shipped:` entries and no FEATURES row; ShareW2 E2 only routes ≥1h clips to Books. Either demote to `planned` or record what exists.
20. **Onboarding rewrite ownership** — R:113 P3 backlog "Standalone onboarding rewrite" AND R:2330-2333 P11c "Onboarding rewrite" — one item, two nodes.
21. **NFeat win vs reminders** — R:519-521 win says "reminders ring on whichever device you're holding" while F:42 says the Mac alarm reconciler is still owed; the node can't close on its own win without it.
22. **book-text-unified header** — the mock's own comment says "NOT BUILT — awaiting sign-off" vs F:190 + R:2430-2435 i12 "SIGNED OFF AND BUILT 2026-07-23, same session". Stale mock header.
23. **Fading-shelf phone placement** — m/fading-shelf.html "Phone placement (v3, PICKED): behind a ⋯ in the Notes header" vs R:570 (2026-07-21) placement B: the conveyor row lives in Review, ⋯ entry retired (m/wayout-phone-placement.html B).
24. **CLAUDE.md "Capture-screen redesign DESIGN PAUSED — no more code iterations on `CaptureMomentView`"** — `CaptureMomentView` was retired 2026-06-13 (F:230, m/audiobook-capture-merged.html). Stale instruction.
25. **Related-panel v3 vs later chrome** — m/related-panel.html m5 "the toolbar toggle keeps a count badge; state app-wide, persists" + "Panel replaces the bottom LINKED FROM strip; collapses with a count badge" vs F:386 (2026-07-25): summon glyph + count badge GONE, panel = floating inspector. The mock's decisions block is partially superseded without a note in the mock.
26. **IPAD_PLAN polish-on-open** — IP §Roles "On-demand polisher (Polish now / polish-on-open)" vs F:122 v2 (2026-07-23): "polish-on-open automation DELETED", only the visible ✨ Polish verb.
27. **Highlights tab** — m/audiobook-player-reading-mode.html locked "Tab bar: Notes · Library · Highlights(soon) · Settings" vs F:202/217: Highlights CUT 2026-07-07, Library → Books, Review took the slot.
28. **Custom vocab "per-device, no sync"** — F:139 "Per-device v1 — no phone↔Mac sync" vs F:287 + R:217 whole-list LWW sync both apps (2026-06-18 / 07-07). F:139 stale.
29. **Chip bar** — m/phone-name-linking.html + F:335 ship a "People in this note" chip bar on the phone, while m/naming-review.html DELETED the chip bar on the Mac and m/standalone-naming-review.html calls it "reference only … default IA is prose-only". Phone has it, Mac doesn't; no recorded verdict that this asymmetry is wanted.
30. **Mock count** — the brief says 71 mocks; the folder holds 71 `.html` + `text-capture-DESIGN.md` (72 files). `CLAUDE.md` Ledgers lists only 12 of them as "signed-off design specs".
