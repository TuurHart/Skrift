# Export v2 — what changes in your vault and portfolio (Q434)

**For Tuur (Q435).** Export v2 is written and checked against every corpus note on both destinations. The app still exports with v1; nothing you have changes until the swap. Read this, and say go or name what to change.

## The size

`Skrift_Native/Shared/ExportV2/` is **383 lines** (2 files). v1's compile half it replaces is 943 lines (`Compiler` 413, `CompilerInput` 93, `CompilerInputBuilder` 130, `ExportProfile` 178, `ExportNaming` 86, `ExportBody` 43): **41%**. The queue's cap was 1,094 lines (40% of the 2,734 the plan measured). The writer half (`VaultWrite`, `VaultStamp`, `VaultLayout`, `DestinationMove`, `ExportGate`, `ExportOutcomeCopy`, 1,245 lines) is reused as it is: folder layout, ownership, stamps and the ledger already meet C53–C55, C192 and C193 (orchestrator's call, recorded in RUN.md). v2 reads the same `CompilerInput` both apps already build, so the body, voice and name-linking rules stay one copy.

## The count

218 exports (109 notes × vault and portfolio). **189 change**, **29 stay identical**: 21 are refusals that never export (locked, trashed, unrated, still pending), and 8 are portfolio entries v2 writes byte for byte as v1 did (notes with your own title and nothing else that changed). 0 unexplained: every change is registered in `test-fixtures/corpus/expected-differences-export.json` with its clause.

## What changes, by clause

### 1. `title:` is the note's real title (C25) — 85 vault exports
v1 wrote the row's file name (`memo_<UUID>`, `capture_<UUID>`, a bare UUID) into `title:` whenever a note had no polished title, while the FILE was already named by the C25 ladder (your title, else the Mac's, else the first line). v2 writes the same ladder title in both places, always on one line. Every processed note already has a polished title, so in practice this only shows on notes exported before processing.

### 2. The portfolio writes `title:` only when you gave one (C130) — 86 portfolio exports
v1 wrote a title on every portfolio entry. v2 writes it only when you typed one; the file is still named by the title.

### 3. `created:` and `duration:` (D12, R38) — 99 vault exports
Two new keys after `editedAt:` on every vault note: `created:` the moment the note was made, in the same local date-time form as `editedAt:` (`2026-08-16T22:00:00`); `duration:` the recording's length in whole seconds (`duration: 7`), empty for a note with no recording. The portfolio gets neither (C130).
**Your call:** seconds is sortable and unambiguous; `4:41` would read better but YAML may read it as a number. Say if you want the clock form.

### 4. `people:` as a list of plain names on the portfolio (R51) — 33 portfolio exports
`people: [[Lotte Vos]]` (which the portfolio's own parser garbles to `['[Lotte Vos]']`) becomes
```
people:
  - Lotte Vos
```
The vault keeps `people: [[Lotte Vos]], [[Jack Morrow]]` (Obsidian links).

### 5. No `![[…]]` on the portfolio (C129, R51) — 3 portfolio exports
A shared picture's embed, and an Apple Note attachment, now use the portfolio's `![](file)` like every other picture: `cap-image-no-words.portfolio`, `cap-image-typed-note.portfolio`, `cap-image-voice-ramble.portfolio`.

### 6. Keys outside the portfolio's list go (C130) — 12 portfolio exports
`url:`, `book:`, `bookAuthor:`, `chapter:` are no longer written on portfolio entries (the link line and the quote attribution in the body still carry them), and `needs:` moves after `location:` in the list's order: `cap-url-dutch-annotation.portfolio`, `cap-url-instagram.portfolio`, `cap-url-link-only.portfolio`, `cap-url-no-title.portfolio`, `cap-url-voice-ramble.portfolio`, `cap-url-with-title.portfolio`, `cap-url-youtube.portfolio`, `dest-inspiration-credit.portfolio`, `quote-en-with-ramble.portfolio`, `quote-nl-with-ramble.portfolio`, `quote-only-no-ramble.portfolio`, `quote-with-names.portfolio`.

### 7. Tags are valid YAML (R50) — 3 vault exports
A tag typed with Obsidian's `#` (`#studio`) is written `studio`: in YAML a bare `- #studio` is a comment, so v1's vault showed an empty tag. A vault tag containing `: ` is quoted; on the portfolio it is reworded to ` - ` (C130 never quotes). `typed-bracket-tag-bug.vault`, `typed-tags-with-spaces.portfolio`, `typed-tags-with-spaces.vault`.

### 8. A shared document goes with the note (R38) — 4 exports
A `.file` capture's document (the PDF Marco sent) is copied with the note, named by the note's stem, into `Documents/` in the vault or beside the entry on the portfolio. A PDF is embedded above your words (`![[….pdf]]`); any other file is linked. `cap-file-pdf.portfolio`, `cap-file-pdf.vault`, `cap-file-txt.portfolio`, `cap-file-txt.vault`.

## Built but not visible in the corpus

- **OCR text (R38):** a picture's recognised text follows its embed in the vault as an Obsidian comment, `%% GREY BODY €18 %%`: searchable, hidden when reading. Never on the portfolio, where everything below the `---` is your words (C131). No corpus photo carries OCR text yet, so only the unit test shows it. **Your call:** a comment, a callout, or not at all.
- **A hand-typed `[[word]]` that leads nowhere (R49, C59):** in the vault it is written escaped (`\[\[the kiln\]\]`), so it reads as you typed it and never becomes a link to an empty note. A link to anyone in your names list, and a memo-link, stay links. The corpus's only hand-typed link is a person, so only the unit test shows it. **Watch:** an Apple Note's own link to a place that is not in your names list (`[[Hotel Du Vin]]`) is escaped too; v1 kept it as a link.
- **Dangling picture markers** are dropped, never printed (C196), as in v1.

## Unchanged on purpose

`date:` (the recording's local day, C64), the stamp trio and its place, the sensor block, `voice:`, `capture:`, `needs: - credit` on `inspiration` (C134), the quote attribution (C60), the source-link line, the file names and folders (Personal → `Skrift/`, Portfolio → `_inbox/<slug>.md`, D189), audio and the video's movie on the portfolio (C136), and every refusal. `location:` stays quoted on the portfolio as in v1. C130 says plain values are reworded, never quoted; I left it because v1 quotes it and the harness's flat-YAML check accepts a quoted value. Whether `capture/tools/vault_index.py` reads the quotes is unverified. **Your call:** quoted, or plain with any `: ` reworded.

## Before the swap

- The Mac row does not mirror the memo's `createdAt` or whether you typed the title yourself; the harness reads them off the memo. The swap needs both mirrored (like `memoEditedAt`).
- The iPad's exporter (`ObsidianPublisher`) is not yet wired to v2; it is the same `ExportV2.compile` with the iPad's asset lane.

## Examples

`dest-idea` on the portfolio:
```diff
 ---
-title: "9A147D60-9B56-5122-A046-9F00C46BBFF1"
 date: 2026-07-11
 capture: Typed-note
 voice: written
 tags:
   - idea
   - studio
-people: [[Lotte Vos]]
+people:
+  - Lotte Vos
 location:
```

`voice-en-full-context` in the vault:
```diff
 title: "Rain ride to Kralingen"
 date: 2026-08-16
 editedAt:
+created: 2026-08-16T22:00:00
+duration: 7
 author: Tiuri
```

`cap-file-pdf` in the vault:
```diff
-title: "capture_FDA21613-E326-5919-98D2-8205AD1580C2"
+title: "Marco's quote for the kiln line. Nine metres, dedicated 16 A, €640 plus the box."
 ...
+![[Marco's quote for the kiln line. Nine metres, dedicated 16 A, €640 plus the box.pdf]]
 Marco's quote for the kiln line. Nine metres, dedicated 16 A, €640 plus the box.
```

## Every changed export, by clause

- **C25 title** (85): `cap-file-pdf.vault`, `cap-file-txt.vault`, `cap-image-no-words.vault`, `cap-image-typed-note.vault`, `cap-image-voice-ramble.vault`, `cap-text-article.vault`, `cap-text-plain.vault`, `cap-url-dutch-annotation.vault`, `cap-url-instagram.vault`, `cap-url-link-only.vault`, `cap-url-no-title.vault`, `cap-url-voice-ramble.vault`, `cap-url-with-title.vault`, `cap-url-youtube.vault`, `conv-dutch.vault`, `conv-one-unnamed.vault`, `conv-three-speakers.vault`, `conv-two-named.vault`, `conv-with-picture.vault`, `dest-idea.vault`, `dest-inspiration-credit.vault`, `dest-personal.vault`, `dest-project.vault`, `edge-literal-marker-typed.vault`, `edge-old-rated-never-exported.vault`, `edge-quote-in-name-roster-word.vault`, `edge-tag-case-dupes.vault`, `pic-at-end.vault`, `pic-at-start.vault`, `pic-in-blockquote.vault`, `pic-in-task-list.vault`, `pic-manifest-no-marker.vault`, `pic-mid-sentence.vault`, `pic-missing-file.vault`, `pic-nl.vault`, `pic-ocr-text.vault`, `pic-shared-no-timestamp.vault`, `pic-three-spread.vault`, `pic-two-same-second.vault`, `pic-user-snapped-markers.vault`, `pic-wall.vault`, `quote-en-with-ramble.vault`, `quote-missing-book-metadata.vault`, `quote-nl-with-ramble.vault`, `quote-only-no-ramble.vault`, `quote-with-names.vault`, `share-signal-single.vault`, `share-whatsapp-thread.vault`, `typed-blockquote-ordinary.vault`, `typed-bracket-tag-bug.vault`, `typed-crlf-tabs-nbsp.vault`, `typed-heading-only.vault`, `typed-memo-links.vault`, `typed-numbered-list.vault`, `typed-reminder.vault`, `typed-reserved-word-tags.vault`, `typed-tags-with-spaces.vault`, `typed-tasks.vault`, `typed-title-derived.vault`, `typed-two-liner.vault`, `typed-urls-in-prose.vault`, `typed-user-wikilink.vault`, `typed-wall-one-paragraph.vault`, `typed-whitespace-only.vault`, `video-landscape.vault`, `video-no-speech.vault`, `video-portrait.vault`, `voice-en-asr-wall.vault`, `voice-en-duplicate-a.vault`, `voice-en-duplicate-b.vault`, `voice-en-eight-minutes.vault`, `voice-en-failed.vault`, `voice-en-names-all-tiers.vault`, `voice-en-paragraphed-by-pauses.vault`, `voice-en-pricing-ramble.vault`, `voice-en-processed-no-content.vault`, `voice-en-rated-floor.vault`, `voice-en-rated-max.vault`, `voice-en-three-words.vault`, `voice-en-triple-blank-lines.vault`, `voice-en-untrusted-but-edited.vault`, `voice-en-untrusted.vault`, `voice-mix-code-switch.vault`, `voice-nl-kiln.vault`, `voice-nl-names.vault`
- **C130 portfolio title** (86): `cap-file-pdf.portfolio`, `cap-file-txt.portfolio`, `cap-image-no-words.portfolio`, `cap-image-typed-note.portfolio`, `cap-image-voice-ramble.portfolio`, `cap-text-article.portfolio`, `cap-text-plain.portfolio`, `cap-url-dutch-annotation.portfolio`, `cap-url-instagram.portfolio`, `cap-url-link-only.portfolio`, `cap-url-no-title.portfolio`, `cap-url-voice-ramble.portfolio`, `cap-url-with-title.portfolio`, `cap-url-youtube.portfolio`, `conv-dutch.portfolio`, `conv-one-unnamed.portfolio`, `conv-three-speakers.portfolio`, `conv-two-named.portfolio`, `conv-with-picture.portfolio`, `dest-idea.portfolio`, `dest-inspiration-credit.portfolio`, `dest-personal.portfolio`, `dest-project.portfolio`, `edge-literal-marker-typed.portfolio`, `edge-old-rated-never-exported.portfolio`, `edge-quote-in-name-roster-word.portfolio`, `edge-tag-case-dupes.portfolio`, `pic-at-end.portfolio`, `pic-at-start.portfolio`, `pic-in-blockquote.portfolio`, `pic-in-task-list.portfolio`, `pic-manifest-no-marker.portfolio`, `pic-mid-sentence.portfolio`, `pic-missing-file.portfolio`, `pic-nl.portfolio`, `pic-ocr-text.portfolio`, `pic-shared-no-timestamp.portfolio`, `pic-three-spread.portfolio`, `pic-two-same-second.portfolio`, `pic-user-snapped-markers.portfolio`, `pic-wall.portfolio`, `quote-en-with-ramble.portfolio`, `quote-missing-book-metadata.portfolio`, `quote-nl-with-ramble.portfolio`, `quote-only-no-ramble.portfolio`, `quote-with-names.portfolio`, `share-signal-single.portfolio`, `share-whatsapp-thread.portfolio`, `typed-blockquote-ordinary.portfolio`, `typed-bracket-tag-bug.portfolio`, `typed-crlf-tabs-nbsp.portfolio`, `typed-heading-only.portfolio`, `typed-memo-links.portfolio`, `typed-numbered-list.portfolio`, `typed-reminder.portfolio`, `typed-reserved-word-tags.portfolio`, `typed-tags-with-spaces.portfolio`, `typed-tasks.portfolio`, `typed-title-derived.portfolio`, `typed-two-liner.portfolio`, `typed-urls-in-prose.portfolio`, `typed-user-wikilink.portfolio`, `typed-wall-one-paragraph.portfolio`, `typed-whitespace-only.portfolio`, `video-landscape.portfolio`, `video-no-speech.portfolio`, `video-portrait.portfolio`, `voice-en-asr-wall.portfolio`, `voice-en-duplicate-a.portfolio`, `voice-en-duplicate-b.portfolio`, `voice-en-eight-minutes.portfolio`, `voice-en-failed.portfolio`, `voice-en-names-all-tiers.portfolio`, `voice-en-paragraphed-by-pauses.portfolio`, `voice-en-pricing-ramble.portfolio`, `voice-en-processed-no-content.portfolio`, `voice-en-rated-floor.portfolio`, `voice-en-rated-max.portfolio`, `voice-en-three-words.portfolio`, `voice-en-triple-blank-lines.portfolio`, `voice-en-untrusted-but-edited.portfolio`, `voice-en-untrusted.portfolio`, `voice-en-with-mac-polish.portfolio`, `voice-mix-code-switch.portfolio`, `voice-nl-kiln.portfolio`, `voice-nl-names.portfolio`
- **D12 created/duration** (99): `applenote-headings-checklist.vault`, `applenote-with-attachment.vault`, `cap-file-pdf.vault`, `cap-file-txt.vault`, `cap-image-no-words.vault`, `cap-image-typed-note.vault`, `cap-image-voice-ramble.vault`, `cap-text-article.vault`, `cap-text-plain.vault`, `cap-url-dutch-annotation.vault`, `cap-url-instagram.vault`, `cap-url-link-only.vault`, `cap-url-no-title.vault`, `cap-url-voice-ramble.vault`, `cap-url-with-title.vault`, `cap-url-youtube.vault`, `conv-dutch.vault`, `conv-one-unnamed.vault`, `conv-three-speakers.vault`, `conv-two-named.vault`, `conv-with-picture.vault`, `dest-idea.vault`, `dest-inspiration-credit.vault`, `dest-personal.vault`, `dest-project.vault`, `edge-emoji-title-tags.vault`, `edge-literal-marker-typed.vault`, `edge-old-rated-never-exported.vault`, `edge-quote-in-name-roster-word.vault`, `edge-tag-case-dupes.vault`, `pic-at-end.vault`, `pic-at-start.vault`, `pic-in-blockquote.vault`, `pic-in-task-list.vault`, `pic-manifest-no-marker.vault`, `pic-mid-sentence.vault`, `pic-missing-file.vault`, `pic-nl.vault`, `pic-ocr-text.vault`, `pic-shared-no-timestamp.vault`, `pic-three-spread.vault`, `pic-two-same-second.vault`, `pic-user-snapped-markers.vault`, `pic-wall.vault`, `quote-en-with-ramble.vault`, `quote-missing-book-metadata.vault`, `quote-nl-with-ramble.vault`, `quote-only-no-ramble.vault`, `quote-with-names.vault`, `share-signal-single.vault`, `share-voicememo-named.vault`, `share-whatsapp-thread.vault`, `typed-blockquote-ordinary.vault`, `typed-bracket-tag-bug.vault`, `typed-crlf-tabs-nbsp.vault`, `typed-heading-only.vault`, `typed-headings-and-tags.vault`, `typed-hostile-title.vault`, `typed-memo-links.vault`, `typed-numbered-list.vault`, `typed-reminder.vault`, `typed-reserved-word-tags.vault`, `typed-same-title-a.vault`, `typed-same-title-b.vault`, `typed-tags-with-spaces.vault`, `typed-tasks.vault`, `typed-title-derived.vault`, `typed-title-set.vault`, `typed-two-liner.vault`, `typed-unicode-emoji.vault`, `typed-urls-in-prose.vault`, `typed-user-wikilink.vault`, `typed-wall-7k.vault`, `typed-wall-one-paragraph.vault`, `typed-whitespace-only.vault`, `video-landscape.vault`, `video-no-speech.vault`, `video-portrait.vault`, `voice-en-asr-wall.vault`, `voice-en-duplicate-a.vault`, `voice-en-duplicate-b.vault`, `voice-en-eight-minutes.vault`, `voice-en-failed.vault`, `voice-en-full-context.vault`, `voice-en-names-all-tiers.vault`, `voice-en-paragraphed-by-pauses.vault`, `voice-en-pricing-ramble.vault`, `voice-en-processed-no-content.vault`, `voice-en-rated-floor.vault`, `voice-en-rated-max.vault`, `voice-en-raw-title.vault`, `voice-en-three-words.vault`, `voice-en-triple-blank-lines.vault`, `voice-en-untrusted-but-edited.vault`, `voice-en-untrusted.vault`, `voice-en-with-mac-polish.vault`, `voice-mix-code-switch.vault`, `voice-nl-kiln.vault`, `voice-nl-names.vault`
- **R51 people list** (33): `applenote-headings-checklist.portfolio`, `cap-image-typed-note.portfolio`, `cap-url-dutch-annotation.portfolio`, `cap-url-voice-ramble.portfolio`, `cap-url-with-title.portfolio`, `conv-dutch.portfolio`, `conv-three-speakers.portfolio`, `conv-two-named.portfolio`, `conv-with-picture.portfolio`, `dest-idea.portfolio`, `dest-inspiration-credit.portfolio`, `pic-nl.portfolio`, `pic-three-spread.portfolio`, `pic-wall.portfolio`, `typed-headings-and-tags.portfolio`, `typed-reminder.portfolio`, `typed-tasks.portfolio`, `typed-unicode-emoji.portfolio`, `typed-urls-in-prose.portfolio`, `typed-user-wikilink.portfolio`, `typed-wall-7k.portfolio`, `typed-wall-one-paragraph.portfolio`, `video-landscape.portfolio`, `voice-en-asr-wall.portfolio`, `voice-en-eight-minutes.portfolio`, `voice-en-names-all-tiers.portfolio`, `voice-en-paragraphed-by-pauses.portfolio`, `voice-en-pricing-ramble.portfolio`, `voice-en-triple-blank-lines.portfolio`, `voice-en-with-mac-polish.portfolio`, `voice-mix-code-switch.portfolio`, `voice-nl-kiln.portfolio`, `voice-nl-names.portfolio`
- **R51 portfolio embeds** (3): `cap-image-no-words.portfolio`, `cap-image-typed-note.portfolio`, `cap-image-voice-ramble.portfolio`
- **C130 keys** (12): `cap-url-dutch-annotation.portfolio`, `cap-url-instagram.portfolio`, `cap-url-link-only.portfolio`, `cap-url-no-title.portfolio`, `cap-url-voice-ramble.portfolio`, `cap-url-with-title.portfolio`, `cap-url-youtube.portfolio`, `dest-inspiration-credit.portfolio`, `quote-en-with-ramble.portfolio`, `quote-nl-with-ramble.portfolio`, `quote-only-no-ramble.portfolio`, `quote-with-names.portfolio`
- **R50 tags** (3): `typed-bracket-tag-bug.vault`, `typed-tags-with-spaces.portfolio`, `typed-tags-with-spaces.vault`
- **R38 document** (4): `cap-file-pdf.portfolio`, `cap-file-pdf.vault`, `cap-file-txt.portfolio`, `cap-file-txt.vault`

Identical in v1 and v2 (29): `applenote-dutch.portfolio`, `applenote-dutch.vault`, `applenote-with-attachment.portfolio`, `edge-emoji-title-tags.portfolio`, `share-voicememo-named.portfolio`, `typed-dutch-boodschappen.portfolio`, `typed-dutch-boodschappen.vault`, `typed-empty-body.portfolio`, `typed-empty-body.vault`, `typed-hostile-title.portfolio`, `typed-locked.portfolio`, `typed-locked.vault`, `typed-same-title-a.portfolio`, `typed-same-title-b.portfolio`, `typed-title-set.portfolio`, `typed-trashed.portfolio`, `typed-trashed.vault`, `voice-en-full-context.portfolio`, `voice-en-other-device-transcribing.portfolio`, `voice-en-other-device-transcribing.vault`, `voice-en-pending.portfolio`, `voice-en-pending.vault`, `voice-en-raw-title.portfolio`, `voice-en-unrated-fresh.portfolio`, `voice-en-unrated-fresh.vault`, `voice-en-unrated-kept.portfolio`, `voice-en-unrated-kept.vault`, `voice-en-unrated-old.portfolio`, `voice-en-unrated-old.vault`
