# Scenario probes — 50 real-life traces against SPEC.md (2026-09-21)

Read from the worktree at `d21f474c`. Paths: `M/` = `Skrift_Native/SkriftMobile`, `D/` =
`Skrift_Native/SkriftDesktop`, `S/` = `Skrift_Native/Shared`. Verdicts: COVERED / PARTLY /
UNCOVERED / CONTRADICTED. "unverified" = the OS-side behaviour (which UTIs an app hands the
extension) is not confirmed on a device; the code path from that point on is read. Proposed
clauses are numbered C123+ so they can be pasted into SPEC.md without renumbering.

---

## The scenarios

### Ingress — share sheet, open-in, in-app import

**1. He shares 5 WhatsApp voice messages with a picture between the 3rd and 4th, from Bruno.**
- v1: WhatsApp ships a multi-select as several `NSExtensionItem`s; only the first is read
  (`M/SkriftShare/SharePayloadLoader.swift:77`). Even flattened (C67): audio outranks, photos +
  text collected as a "mixed bundle" (`:89-108`), which is ALWAYS one note (`ShareSheetView.swift:169-171,753`).
  Clips are merged in order into one m4a (`M/Features/Recording/MemoSaver.swift:159,201-260`);
  clip boundaries are not kept anywhere. The photo gets `offsetSeconds: 0`
  (`M/Services/Capture/CaptureInboxDrainer.swift:261`) → `ImageMarkers.insert` puts it after the
  first word (`S/Pipeline/ImageMarkers.swift:42-52`). `recordedAt` = first clip's temp-file
  modificationDate = share time (`SharePayloadLoader.swift:237`, `MemoSaver.swift:96`). No sender anywhere.
- Owner: picture sits between message 3 and 4; note dated to when Bruno sent them; "Bruno" on the note.
- Verdict: UNCOVERED (C68 puts the picture at the TOP per C12; C70 dates from the filename but a
  bundle has five filenames and no rule; sender: no clause).
- Clause: C123, C124 (below). Fixture: `ingress/P3-whatsapp-thread-with-picture/` — 5 opus clips
  named `WhatsApp Audio 2026-03-07 at 18.30.4N.opus`, 1 JPEG, `sender: "Bruno"`; golden: markers
  after clip 3's last sentence, `recordedAt` = clip 1's filename date, `metadata.sender`.

**2. He shares the same WhatsApp audio twice (once by accident, a week apart).**
- v1: each share mints a new memo id (`MemoSaver.swift:69`); dedup is same-id only
  (`S/Pipeline/MemoDuplicates.swift:20-26`, `M/Services/MemoDeduper.swift:20`); the Mac dedups by
  id or filename (`D/Pipeline/Ingest/MemoCloudIngest.swift:110-120`) — two rows; two vault files,
  the second as `<stem> <id8>.md` (`S/Export/VaultWrite.swift:258-281`).
- Owner: told it's already in Skrift, or the second lands beside the first, not a silent twin.
- Verdict: UNCOVERED (C48 is same-id clones only).
- Clause: C125. Fixture: corpus `voice-en-duplicate-content-a/b` — different ids, identical audio
  hash + transcript, 7 days apart; golden: second import flagged `duplicateOf`, one vault file.

**3. He shares a Voice Memo he named "kiln idea".**
- v1: the extension renames the blob `shared_<uuid>.m4a` (`SharePayloadLoader.swift:238-240`); the
  original name survives only for documents (`:180`). `recordedAt` from the embedded m4a date
  (`MemoSaver.swift:105-108`) is right; title nil → first transcript line (`M/Models/MemoDisplay.swift:9-45`).
- Owner: the note is called "kiln idea".
- Verdict: UNCOVERED (C25's ladder has "share title" but no audio share ever carries one).
- Clause: C126. Fixture: `ingress/P1-voice-memo-named/kiln idea.m4a` (embedded date); golden:
  `title == "kiln idea"`, `recordedAt` = embedded date.

**4. He shares a Live Photo from Photos.**
- v1 (unverified UTI): `load` checks `public.movie` before `public.image`
  (`SharePayloadLoader.swift:139,143`). If the provider registers the 3-second movie, the share is a
  VIDEO: audio stripped, one frame, transcript of 3 s of street noise → `.failed` or garbage
  (`MemoSaver.swift:316-397`). If only the still is registered → a normal photo capture (P9).
- Owner: it's a picture.
- Verdict: UNCOVERED.
- Clause: C127. Fixture: `ingress/P9-live-photo/` (JPEG + paired MOV as Photos hands them);
  golden: `.captureImage`, one manifest entry, no audio.

**5. He shares a WhatsApp photo that has a caption.**
- v1: image branch (`:143`) runs before text (`:148`) and never collects the text; only the audio
  branch collects captions (`:99-107`). Caption dropped.
- Owner: the caption is the note's text under the picture.
- Verdict: UNCOVERED (ingress needs-verdict 8; no clause).
- Clause: C128. Fixture: `ingress/P9-photo-with-caption/` (JPEG + plain-text provider); golden:
  `annotationText == caption + "\n\n[[img_001]]"`.

**6. He shares an email from Mail.**
- v1 (unverified UTI, `.eml`/`message/rfc822`): nothing matches audio/url/movie/image/text →
  `loadFile` (`:154-159`) → a `.file` card `file_<id>.eml` (`CaptureInboxDrainer.swift:383-402`);
  only PDFs get text extraction (`:411-419`) → unsearchable dead card, dated to share time.
- Owner: subject as title, body as text, dated when it was sent, sender named.
- Verdict: UNCOVERED (C73 lists PDF/.txt/.md only).
- Clause: C129. Fixture: `ingress/P10-email.eml` (RFC 822 with Date/From/Subject, one attachment);
  golden: text capture, `title = Subject`, `recordedAt = Date:`, `metadata.sender = From`.

**7. He shares a note from the Apple Notes app on the phone (text + one picture).**
- v1 (unverified UTI): Notes hands text and image providers; image wins (`:143` before `:148`) →
  photo capture, text dropped (same hole as #5). With text only → P7 text capture.
- Owner: the note's text and its picture, as one note.
- Verdict: PARTLY (C76 covers only the Mac's `.md` + `Attachments/` export).
- Clause: C130. Fixture: `ingress/P7-apple-note-share/` (text provider + JPEG provider); golden:
  text body + `[[img_001]]` per C12.

**8. He shares selected text from a Safari page.**
- v1: text + url providers → `type:"text"` with the url riding along (`:123-134`);
  `SharedContent(type:.text, url:, urlTitle:)`, no enrichment (`CaptureInboxDrainer.swift:335`
  enriches `.url` only); the compiler writes `url:` (`S/Export/Compiler.swift`).
- Owner: the quote with its source link; that's what happens.
- Verdict: UNCOVERED — works, but no clause names this door (C69 covers a bare URL as text).
- Clause: C131. Fixture: ingress P6 (Wikipedia paragraph + url); golden: sharedContent + `url:` key.

**9. He shares an Apple Maps pin of a café in Alfama.**
- v1: `PlaceLink.parse` → `metadata.location` + place name as card title, enrichment skipped
  (`CaptureInboxDrainer.swift:336,349-355`); the location chip and `location:` frontmatter follow.
- Owner: a place-anchored note he can find on the map.
- Verdict: UNCOVERED — built, absent from the spec (C72 is the generic URL fetch).
- Clause: C132. Fixture: `maps.apple.com/?ll=38.71,-9.13&q=Café` ; golden: `location.placeName`.

**10. He shares an article URL on the metro with no signal.**
- v1: `LinkEnrichment.enrich` returns nil on any fetch failure (`M/Services/Capture/LinkEnrichment.swift:24-27`);
  the card shows the domain; nothing retries — "enrichment is once, at drain" (`CaptureInboxDrainer.swift:329-343`).
- Owner: the title and thumbnail fill in when he's back online.
- Verdict: CONTRADICTED by C72 ("fetched ONCE on drain").
- Clause: C133. Fixture: ingress P5 replayed with the first GET failing; golden: card enriched on
  the next foreground with network.

**11. A friend AirDrops him a Signal voice note (`signal-2026-04-13-18-15-24-552.aac`).**
- v1: `AppURLHandler.handle` → `importAudio` with no date (`M/App/AppURLHandler.swift:35-38`,
  `MemoSaver.swift:96`) → dated now (no filename parse on the phone); no sheet → significance 0,
  no annotation; jumps to the note.
- Owner: dated 13 April, and asked the rating like a share.
- Verdict: PARTLY (C70 fixes the date as a required difference; C66 "every share offers the
  rating" — open-in has no sheet).
- Clause: C134. Fixture: same file via `.onOpenURL`; golden: `recordedAt` = filename date, and
  the opened note shows the circles.

**12. He picks three clips at once in Import → "Audio or video from Files".**
- v1: `.fileImporter(allowsMultipleSelection: true)` → `AppURLHandler.handle` per URL
  (`M/Features/MemosList/MemosListView.swift:327-333`) → three memos, no chooser, last one opens.
- Owner: the same "One note / 3 notes" question the share sheet asks.
- Verdict: UNCOVERED (C68 is the share sheet only).
- Clause: C135. Fixture: three m4a via the importer; golden: chooser shown; "one note" merges.

**13. He multi-selects four Signal voice notes (non-audio UTI) in the share sheet.**
- v1: no `public.audio` → falls to `loadFile` which takes `attachments.first` (`:154`) → ONE clip
  rerouted as audio by extension (`:198-207`); the other three vanish silently.
- Owner: four clips, the chooser.
- Verdict: PARTLY (C67 says "all extension items"; this is a second `.first` at provider level).
- Clause: amend C67 (below). Fixture: ingress P2 ×4 in one item; golden: 4 clips.

**14. He receives a `.skriftbook` in Messages and taps Share → Skrift.**
- v1: via open-in → `BookBundle.isBookBundle` → import sheet (`AppURLHandler.swift:23-26`). Via
  the share sheet (unverified): a zip conforms to `public.data` → `loadFile` → a dead file card.
- Owner: the book lands in Books either way.
- Verdict: PARTLY (C107 covers the bundle, not the share-sheet door).
- Clause: C136. Fixture: `ingress/P18-bundle-via-share/`; golden: book added, no memo.

**15. He shares a screenshot of a tweet.**
- v1: no EXIF → `recordedAt` = share time (`CaptureInboxDrainer.swift:483-484`); PNG re-encoded to
  JPEG 0.85 (`SharePayloadLoader.swift:361-365`); OCR on the next sweep.
- Owner: dated now, text searchable. Fine.
- Verdict: COVERED C74 (PNG→PNG is D17, a required difference).

**16. He multi-selects 30 photos from a walk in Photos.**
- v1: one note, manifest in provider order, all `offsetSeconds 0`, 30 markers appended to the
  annotation (`CaptureInboxDrainer.swift:426-452,505-510`), `recordedAt` = earliest EXIF.
- Owner: one note, pictures in the order he took them.
- Verdict: COVERED C68/C13/C74. Note for C13: provider order is what Photos hands, not EXIF order —
  worth a fixture (`ingress/P9-thirty-photos/` with shuffled EXIF; golden: EXIF order).

**17. He shares a 61-minute podcast episode from Files.**
- v1: `hasLongClip` → Books chooser defaults on (`ShareSheetView.swift:35-37,191`) → audiobook,
  no note, no jump (`CaptureInboxDrainer.swift:225-236`).
- Owner: a book in the player unless he says note. Fine.
- Verdict: COVERED C79.

**18. He shares a WhatsApp video of a friend's kiln and files it Made.**
- v1: video → audio + one frame; the movie is discarded on the phone (`MemoSaver.swift:316-397`);
  the Mac keeps `source.<ext>` only for its OWN imports (`D/Pipeline/Ingest/IngestService.swift:117-137`)
  and copies it to the archive only then (`D/Pipeline/Export/VaultExporter.swift:171-181`). A
  phone-shared video never reaches the archive as a movie.
- Owner: "I may send a video… that is gold" — the archive gets the movie.
- Verdict: PARTLY (C71 "original discarded on the phone", C63 "video never exported" contradict
  the Made intent).
- Clause: C137. Fixture: corpus `video-made-archive`; golden: archive folder holds `<slug>.mp4`.

**19. The app is killed during a share drain, between deleting the entry and inserting the memo.**
- v1: audio and video entries delete the inbox entry FIRST, then import from a temp copy
  (`CaptureInboxDrainer.swift:150-154, 221-237`); a kill in that window loses the clips (tmp only).
  Other types delete after the save (`:529-531`).
- Owner: nothing shared is ever lost.
- Verdict: UNCOVERED (C75 is the empty-payload husk; C99 is recordings).
- Clause: C138. Fixture: drainer test that throws after `delete(entryDir:)`; golden: entry survives
  or the temps are re-adopted on the next drain.

**20. He taps Share → Skrift with an empty selection.**
- v1: whitespace text → the "unsupported" feedback state, no husk (P7 / A16).
- Verdict: COVERED C75.

### Recording

**21. He records for 40 minutes, takes 30 pictures, and a call comes in at minute 35.**
- v1: the interruption stops the engine; `.ended` rebuilds (`M/Services/Recording/LiveRecordingService.swift:920-945`);
  the audio file has a hole for the call. Photo offsets are wall-clock `service.elapsed`
  (`M/Features/Recording/RecordView.swift:453`, `LiveRecordingService.swift:1433-1434`), which
  keeps counting; duration comes from the file (`:543-544`). Every photo after the call carries
  an offset later than the audio → nearest word = the last word → they all pile at the end
  (`ImageMarkers.swift:42-52`). Same for a photo taken during the call.
- Owner: pictures after the call land where he took them.
- Verdict: UNCOVERED (C16 assumes offset = recording time; interruptions are not "paused").
- Clause: C139. Fixture: corpus `pic-after-interruption` — 60 s audio with a 20 s hole logged in
  metadata, photos at 15 s and 50 s wall-clock; golden: second marker after the sentence at file
  time 30 s.

**22. That 40-minute note is rated and processed.**
- v1: ~6 000 words ≈ 8 000 tokens; budget `min(8192, …)` (`S/Pipeline/PolishPrompts.swift:64-72`);
  output at ≥95% of the cap → `looksTruncated` → the whole body ships unedited (`:130-136`,
  `D/Engines/EnhancementService.swift:94-101`). Long notes are never copy-edited.
- Owner: a long walk gets cleaned up too.
- Verdict: UNCOVERED (C32 codifies the cap; nothing says long input is chunked).
- Clause: C140. Fixture: corpus `voice-en-forty-minutes` (≈6k words, 8 paragraphs); golden:
  copyedit differs from the transcript, paragraph count ≥ input.

**23. He records 3 minutes of Dutch while the language mode is English.**
- v1: the mode is one global synced Bool (`S/Pipeline/ASRLanguageMode.swift:27-29`); the note is
  transcribed with `mel = on` → garbled Dutch (the measured drift, `:5-12`); confidence may still be
  ≥ 0.7 → trusted → the Mac never re-transcribes (C42). No per-note re-transcribe on the phone.
- Owner: flip a switch on that note and it re-transcribes in Dutch.
- Verdict: UNCOVERED (C103 syncs the setting; no per-note language, no phone re-transcribe —
  "Not doing" even forbids it).
- Clause: C141. Fixture: corpus `voice-nl-recorded-in-english-mode` with `metadata.asrMode: "english"`;
  golden: a re-run with `multilingual` yields the Dutch golden.

**24. He long-presses the Lock Screen widget, says "kiln idea", stops.**
- v1: cold launch → `RecordingIntentBridge` → recorder; 2 words; phantom guard passes (RMS ok);
  title = first line; no summary (< 75 words).
- Verdict: COVERED C100/C101/C36 (corpus `voice-en-three-words`).

**25. He pauses for 10 minutes at a café, photographs the menu while paused, resumes.**
- v1: offset excludes paused time (`S/Model/MemoMetadata.swift:151-161`); the photo takes the offset
  at the pause point → after the sentence spoken before the pause.
- Verdict: COVERED C11/C16.

**26. The phone dies at 3% halfway through a take.**
- Verdict: COVERED C99 (required difference D4/D26).

**27. He adds a recording to a note the Mac already polished.**
- v1: the append writes `memo.transcript` only (`MemoSaver.swift:657,660`); the phone shows
  `enhancement.copyedit` when present (`M/Features/MemoDetail/MemoDetailView.swift:1724-1733`); the
  Mac adopts the transcript (path 3) but recompiles over `enhancedCopyedit ?? transcript`
  (`D/Pipeline/Ingest/MemoCloudUpdate.swift:100-103,151`); `enhanceStatus` stays `.done`. The new
  words exist only in the raw transcript: invisible on the phone, the Mac body and the vault.
- Owner: the appended words show up under the polished text and get polished too.
- Verdict: UNCOVERED (C38 "never re-polishes" was written for edits, not new content).
- Clause: C142. Fixture: corpus `voice-en-append-after-polish` (enhancement + longer transcript);
  golden: displayed body = copyedit + "\n\n" + appended raw; `enhanceStatus` back to pending.

### Editing collisions and sync

**28. He edits the same note on the iPad while the Mac is polishing it.**
- v1: the Mac's mid-run guard compares its LOCAL row (`D/Pipeline/BatchManager/BatchRunner.swift:117-120,147-151,170-174`);
  the iPad's edit reaches the row only through a sweep (CloudKit import, coalesced 1 s). If it lands
  mid-run → run discarded, fine. If it lands after the write-back: the Mac's `MemoEnhancement` is
  from the old raw; the iPad's raw edit is adopted (path 3) but the copyedit wins the body
  everywhere (as #27). The write-back guard only refuses rows stamped LATER than `now`
  (`D/Pipeline/Ingest/MacCloudWriteBack.swift:102`).
- Owner: his edit survives; the polish is of what he wrote.
- Verdict: PARTLY (C38 covers the in-run half only).
- Clause: C143. Fixture: `MemoCloudUpdate` test — transcript edited with `editedAt` > `enhancedAt`;
  golden: row back to pending, phone shows the raw edit.

**29. He retitles a note on the Mac and, offline, on the phone; both come online.**
- Verdict: COVERED C98/D24 (per-record LWW, one side loses; decided as-is).

**30. He opens on the iPad a note the phone is still transcribing; the phone's battery dies.**
- v1: the iPad shows "Transcribing…"; recovery is owned by the recorder (`MemoSaver.swift:860-862`);
  the audio blob is already synced. Until the phone relaunches, nothing moves.
- Owner: after a while the iPad just transcribes it from the synced audio.
- Verdict: PARTLY (C97 forbids exactly that; no takeover window).
- Clause: C144. Fixture: corpus `voice-en-other-device-transcribing` aged 2 h; golden: the iPad
  transcribes and stamps `recordingDeviceID` unchanged.

**31. He rates a note 0.1 on the phone, un-rates it a minute later; the Mac already made a row.**
- v1: the row stays (C88). The sweep pulls `significance = 0` onto the row
  (`D/Pipeline/MirroredNoteFields.swift:76-81`), but the queue predicate ignores the rating
  (`D/Pipeline/WayOutRules.swift:102-104`) → the Mac polishes an unrated note and writes the
  enhancement back; the phone then shows polish on a grey note.
- Owner: un-rated means the Mac spends nothing.
- Verdict: CONTRADICTED — C87 (unrated → no processing) vs the as-is C88 row behaviour.
- Clause: amend C88 (below). Fixture: corpus `voice-en-rated-then-unrated` (row exists,
  `significance 0`); golden: `enhanceStatus` stays pending, no `MemoEnhancement`.

**32. He types a note on the Mac (⌘N), rates it, then fixes a typo on the phone.**
- Verdict: COVERED C43/C47 (`.note` row; path 3 adopts the transcript; recompile).

**33. He inserts a photo from the phone editor into a note the Mac polished.**
- v1: file + manifest append + marker in the polished binding (`M/Features/MemoDetail/NoteBodyView.swift:722-749`,
  `:1173-1175`) → the Mac adopts the copyedit and heals the image (`MemoCloudReconciler.swift:112-113`).
- Verdict: COVERED C14/C45.

**34. His iCloud storage is full for a week.**
- v1: CloudKit refuses uploads; `CloudSyncMonitor` exists but no memo, list or export surface says
  "not synced" (the `syncStatus` field is dead — code-core sync contract). Notes sit on one device.
- Owner: a visible "not synced yet" and why.
- Verdict: UNCOVERED.
- Clause: C145. Fixture: none (device); check = a quota error surfaces in the list within a minute.

### Deletion, restore, lifecycle

**35. He trashes a note that was already exported.**
- v1: soft delete syncs (`M/Services/NotesRepository.swift:83-88`); the Mac mirrors trash and
  skips re-export; nothing touches the vault file (no `removeItem` on trash anywhere under
  `S/Export`, `D/Pipeline/Export`, `M/Services/Export`). The `.md` lives on.
- Owner: told the vault copy stays (or offered to take it back).
- Verdict: UNCOVERED (C54/C90 are silent on the exported file).
- Clause: C146 [tuur]. Fixture: corpus `typed-trashed` + ledger entry; golden per verdict.

**36. He purges a note on the phone while the Mac has been off for a month.**
- v1: `permanentlyDelete` removes files, assets and the Memo but NOT its `MemoEnhancement`
  (`NotesRepository.swift:112-126`); the Mac keeps its local row + vault file (purge is
  device-local, `D/App/MacCloudDeleteSync.swift:13-16`). Orphan enhancement forever; orphan row.
- Owner: gone means gone everywhere; no ghosts.
- Verdict: UNCOVERED.
- Clause: C147. Fixture: `NotesRepository` test; golden: no `MemoEnhancement` for a purged id;
  Mac sweep trashes a row whose memo vanished.

**37. He trashes on the phone, restores on the Mac two days later.**
- Verdict: COVERED C90/C47 (watermarked trash mirror, `MemoCloudUpdate.swift:46-57`; Mac restore
  writes `deletedAt = nil`, `MacCloudDeleteSync.swift:28-38`).

**38. He shares ten reading-list links over a month and never rates any.**
- v1: each is unrated; `clockStart = recordedAt`; fade at 30 d, trash at 60 d, purge 14 seen-days
  later (`S/Pipeline/MemoLifecycle.swift:30-36,57-60`). A typed thought at share time is not a touch.
- Owner: as decided — but he may not expect his reading list to die. Flag, no change.
- Verdict: COVERED C87/C89.

**39. He deletes a picture in the editor after the note was exported.**
- v1: marker removed, manifest kept (C14); re-export writes the body without the embed; the old
  `<stem>_002.jpg` stays in `Images/` — assets are only ever written, never removed
  (`S/Export/VaultWrite.swift:369-413`).
- Owner: the vault picture goes too, if it's ours and untouched.
- Verdict: PARTLY (C58 stops removing foreign files; says nothing about removing ours).
- Clause: C148. Fixture: corpus `pic-deleted-after-export`; golden: `Images/<stem>_002.jpg` removed.

### Names

**40. He adds "Bruno" to the roster after 20 notes already mention Bruno.**
- v1 phone: `upsert` → `names.json` → sync (`S/Naming/NamesStore.swift:133-150`); tiers re-derive
  on demand over the raw body, so all 20 link on the phone and in a phone export
  (`M/Services/Export/MemoLinking.swift:21-29`). Mac: only the OPEN note re-scans
  (`D/Features/Shell/ProcessingCoordinator.swift:489-501`) plus the collision rescan (`:508-518`);
  `MemoCloudUpdate` recompiles only on content change (`:130-142`). The other 19 Mac rows and their
  vault files keep no link.
- Owner: Bruno is linked everywhere, once.
- Verdict: PARTLY (C80 + D32 default "every note, once" not yet a clause).
- Clause: C149. Fixture: corpus roster + `voice-en-bruno-before-roster` ×3; golden: all three link
  after the roster change on both apps; untouched vault files re-exported.

**41. He renames "Lena" to "Lena Vos" (canonical change).**
- v1: `upsert(_:replacing:)` replaces the entry (`NamesStore.swift:157-179`). Mac `sanitised` and
  `compiledText` still say `[[Lena]]` until something recompiles that row; phone export re-links
  live → `[[Lena Vos]]`. Exported vault files keep `[[Lena]]` + `people: [Lena]` for good
  (content unchanged on the Mac → no re-export).
- Owner: one rename, every note and file follows (Obsidian would leave dead links otherwise).
- Verdict: UNCOVERED (D20 is about per-note picks, not renames).
- Clause: C150. Fixture: corpus `voice-en-names-all-tiers` + a roster rename event; golden: both
  exports carry the new canonical; `people:` updated.

**42. He records a café conversation with Bruno and Lena, splits speakers, names them.**
- Verdict: COVERED C102/C84/C83 (`MemoSaver.swift:930-965`; names merge into an existing person,
  `NamesStore.swift:164-174`; diar asset healed on the Mac, C45).

**43. He says "ik ga morgen naar Bruno, then we'll fix the glaze" in one note.**
- v1: one transcript; polish keeps both languages (C35, D8 near-echo on Dutch); names link by
  whole word either way; English possessive only (`S/Naming/Sanitiser.swift:40`) — Dutch "Bruno's"
  matches, "Bruno z'n" is a plain mention (fine).
- Verdict: COVERED C35/C80 (language mode itself → #23).

### Audiobooks

**44. He captures a quote on the iPad, rambles, the Mac polishes, the phone shows it.**
- v1: `saveQuoteCapture` (`MemoSaver.swift:496-543`, `M/Features/Audiobooks/MergedCaptureView.swift:451-465`)
  → ramble via `appendRecording` → C1 shape; Mac escrows the quote, edits the ramble
  (`EnhancementService.swift:63-79`); export writes `— [[Author]], *Book*, ch. N`.
- Verdict: COVERED C104/C22/C29/C31/C60.

**45. He spots a mis-heard word inside the captured quote and wants to fix it.**
- v1: the phone editor holds ONLY the ramble and re-prepends the stored quote verbatim
  (`NoteBodyView.swift:1176-1181`); the Mac byte-asserts the quote against the transcript
  (`BatchRunner.swift:143-146`). There is no way to correct the quote text.
- Owner: fix one word in the quote without breaking anything.
- Verdict: UNCOVERED (C22 pins byte-exact round-trip; no edit verb).
- Clause: C151. Fixture: corpus `quote-en-with-ramble` + an edited quote; golden: the new quote is
  the escrowed block; export attribution unchanged.

### Locked notes and reminders

**46. He locks a note the Mac already exported; later the Mac processes it.**
- v1: the vault file stays (`M/Services/Export/PublishCoordinator.swift:78-81` comment); the phone
  refuses future publish, the Mac throws `lockedNote` (`VaultExporter.swift:75-78`). The Mac's
  queue ignores `locked` (`WayOutRules.swift:102-104`) so it still polishes; the iPad refuses
  (`M/Services/Polish/PolishCenter.swift:156`); the shared `ProcessPile` excludes locked (`:25`).
- Owner: a locked note is sealed — not polished, and the plaintext copy is offered back.
- Verdict: PARTLY (C91 export half; D10 open on polish; nothing on the existing file).
- Clause: C152. Fixture: corpus `typed-locked` with a prior ledger entry; golden: no
  `MemoEnhancement`, `exportRefusal` names the file that still exists.

**47. He sets a reminder on a fading note — from the Mac.**
- v1: the Mac only mirrors `remindAt` into the properties card (`D/Features/Review/NoteProperties.swift:86`,
  `MirroredNoteFields.swift:113-118`); no Mac control writes it, no Mac alarm. From the phone: the
  note is held off the clock (`MemoLifecycle.swift:49`); phone AND iPad each schedule → two rings.
- Owner: set it anywhere, one ring where he is.
- Verdict: PARTLY (C92 "each device derives its own alarm" is the double ring; Mac set/ring owed).
- Clause: C153. Fixture: corpus `typed-reminder`; golden: Mac schedules; only the device that
  acknowledges cancels the others (or: rings everywhere, decided).

### Export destinations and the vault

**48. He re-files an exported Personal note as Idea (or an exported Idea back to Personal).**
- v1: destination is an event (`D/App/MacCloudMetaSync.swift:74-80`); the next export writes into
  the archive folder with its OWN ledger (`VaultWrite.swift:27-100`, keyed by folder); the old
  file in the vault stays. Reverse direction: a personal thought remains in the public archive
  repo after he pulled it back.
- Owner: one place, ever — the old file is removed if ours and untouched, else he is told.
- Verdict: UNCOVERED (C62 "one per note", C121 privacy — neither handles the move).
- Clause: C154. Fixture: corpus `dest-idea` exported, then destination → personal; golden: archive
  file gone (ours, untouched), vault file written, refusal copy when the archive file was edited.

**49. He deletes the exported .md in Obsidian, re-exports, then retitles the note and exports again.**
- v1: ledger path missing + `locate(id)` finds nothing → ledger cleared → writable
  (`VaultWrite.swift:242-252`); the retitle keeps the sticky ledger path — the file is never renamed
  (`:235-241`), content updated, `title:` changes.
- Owner: re-export works (yes); the filename follows the title (open question).
- Verdict: PARTLY (C54 covers the delete; C53 implies but does not state "a retitle never renames").
- Clause: C155 [tuur]. Fixture: `VaultWriteTests` retitle case; golden per verdict.

**50. He picks a different vault folder in Settings after 200 exports.**
- v1: the ledger is per picked folder (`VaultWrite.swift:27-100`); `assess` searches for the stamp
  only under the new root → every note is "first contact" → 200 new files; the old folder keeps
  its 200. Two copies of everything.
- Owner: either move them or be told the old exports stay where they are.
- Verdict: UNCOVERED (C53 identity-in-stamp is per root).
- Clause: C156 [tuur]. Fixture: `VaultWriteTests` two-root case; golden per verdict.

---

## Summary table

| # | Scenario | Verdict | Clause |
|---|---|---|---|
| 1 | 5 WhatsApp audios + picture between, from Bruno | UNCOVERED | C123, C124 |
| 2 | Same WhatsApp audio shared twice | UNCOVERED | C125 |
| 3 | Voice Memo named "kiln idea" | UNCOVERED | C126 |
| 4 | Live Photo from Photos | UNCOVERED | C127 |
| 5 | WhatsApp photo with caption | UNCOVERED | C128 |
| 6 | Email from Mail | UNCOVERED | C129 |
| 7 | Apple Notes share on the phone | PARTLY C76 | C130 |
| 8 | Safari selection + page URL | UNCOVERED | C131 |
| 9 | Apple Maps pin | UNCOVERED | C132 |
| 10 | URL shared offline | CONTRADICTED C72 | C133 |
| 11 | AirDropped Signal .aac | PARTLY C66/C70 | C134 |
| 12 | Three clips via in-app Files import | UNCOVERED | C135 |
| 13 | Signal multi-select (fallthrough audio) | PARTLY C67 | C67 amended |
| 14 | .skriftbook via the share sheet | PARTLY C107 | C136 |
| 15 | Screenshot of a tweet | COVERED C74 | — |
| 16 | 30 photos from a walk | COVERED C68/C13/C74 | — |
| 17 | 61-min podcast | COVERED C79 | — |
| 18 | WhatsApp video filed Made | PARTLY C71/C63 | C137 |
| 19 | Kill during share drain | UNCOVERED | C138 |
| 20 | Empty share | COVERED C75 | — |
| 21 | 40 min, 30 pictures, call at 35 | UNCOVERED | C139 |
| 22 | 40-minute note polished (token cap) | UNCOVERED | C140 |
| 23 | Dutch recorded in English mode | UNCOVERED | C141 |
| 24 | Widget record, three words | COVERED C100/C101/C36 | — |
| 25 | Photo during a pause | COVERED C11/C16 | — |
| 26 | Battery dies mid-take | COVERED C99 | — |
| 27 | Append to a polished note | UNCOVERED | C142 |
| 28 | iPad edit while Mac polishes | PARTLY C38 | C143 |
| 29 | Offline retitle on two devices | COVERED C98 | — |
| 30 | In-flight transcription, phone dead | PARTLY C97 | C144 |
| 31 | Rate 0.1 then un-rate, row exists | CONTRADICTED C87 vs C88 | C88 amended |
| 32 | Mac ⌘N note edited on phone | COVERED C43/C47 | — |
| 33 | Editor photo into polished note | COVERED C14/C45 | — |
| 34 | iCloud full | UNCOVERED | C145 |
| 35 | Trash an exported note | UNCOVERED | C146 |
| 36 | Purge while Mac offline | UNCOVERED | C147 |
| 37 | Trash on phone, restore on Mac | COVERED C90/C47 | — |
| 38 | Unrated reading list fades | COVERED C87/C89 | — |
| 39 | Delete picture after export | PARTLY C58 | C148 |
| 40 | Add Bruno after 20 notes | PARTLY C80/D32 | C149 |
| 41 | Rename Lena → Lena Vos | UNCOVERED | C150 |
| 42 | Café conversation, name speakers | COVERED C102/C84/C83 | — |
| 43 | Two-language sentence | COVERED C35/C80 | — |
| 44 | Quote capture on iPad, Mac polish | COVERED C104/C22/C60 | — |
| 45 | Fix a word inside the quote | UNCOVERED | C151 |
| 46 | Lock an exported note; Mac polishes | PARTLY C91/D10 | C152 |
| 47 | Reminder from the Mac; double ring | PARTLY C92 | C153 |
| 48 | Re-file after export (privacy leak) | UNCOVERED | C154 |
| 49 | Delete .md, re-export, retitle | PARTLY C53/C54 | C155 |
| 50 | Switch vault folder | UNCOVERED | C156 |

Counts: COVERED 15 · PARTLY 12 · UNCOVERED 21 · CONTRADICTED 2.

---

## Uncovered / contradicted — proposed clause texts

Ingress:

- C123 [auto] A mixed chat bundle keeps chat order end to end: clips merge in item order; each
  picture's `offsetSeconds` = the merged duration of the clips before it (a picture between clip 3
  and 4 lands after clip 3's last sentence, per C11); `recordedAt` = the earliest clip's content
  date (C70 ladder per clip); the chat text is the annotation. || check: ingress P3 fixture golden.
- C124 [auto] The share sheet has a Sender field for chat shares (pre-filled from nothing; free
  text), stored as `metadata.sender`, editable in the note, exported as `from:` in the frontmatter
  and never linked as a person unless he links it. || check: `MemoMetadata` decode + `CompilerTests`.
- C125 [auto] An imported audio whose content hash matches a live memo's audio is flagged
  `duplicateOf` at import and lands beside it (same date, "Already in Skrift" on the sheet); the
  Mac never mints a second row or vault file for it. || check: corpus `voice-en-duplicate-content-a/b`.
- C126 [auto] An audio share keeps the source filename: a non-pattern name (no WhatsApp/Signal/
  recorder date pattern, not "New Recording N") becomes the share title in the C25 ladder.
  || check: `kiln idea.m4a` → title "kiln idea"; `New Recording 22.m4a` → no title.
- C127 [auto] A Live Photo is a picture: when an image provider also offers its paired movie, the
  still is taken and the movie ignored. || check: ingress P9-live-photo → `.captureImage`, no audio.
- C128 [auto] An image share with a text provider keeps the text as the annotation above the
  pictures (the caption); the audio-branch rule applies to every branch. || check: ingress
  P9-photo-with-caption.
- C129 [auto] An `.eml` share is a text capture: title = Subject, body = the plain-text part,
  `recordedAt` = the `Date:` header, `metadata.sender` = From, attachments as C73 files.
  || check: ingress P10-email.eml.
- C130 [auto] A Notes-app share on the phone with text + images is one note: text as the body,
  pictures per C12; `sourceType .note`. || check: ingress P7-apple-note-share.
- C131 [auto] Selected text + page URL is a text capture carrying `url` and `urlTitle`; no fetch;
  the compiler writes `url:`. || check: ingress P6.
- C132 [auto] A Maps link (Apple `ll=`/`coordinate=`, Google `/place/…/@lat,lng`, `?q=lat,lng`)
  is a link capture with `metadata.location` and the place name as the title; no fetch.
  || check: ingress P5.2 fixture.
- C133 [auto] (replaces "once" in C72) A link capture whose fetch failed is retried at the next
  foreground with network, at most three times over a week; a card never stays bare because the
  metro had no signal. || check: replayed P5 with a failed first GET.
- C134 [auto] Open-in and AirDrop are shares: the opened note shows the slim sheet (rating +
  sender) before the jump, and dates from the filename per C70. || check: `.onOpenURL` of a
  Signal `.aac`.
- C135 [auto] The in-app Files importer offers the same One-note / N-notes chooser as the share
  sheet when more than one audio file is picked. || check: three m4a via the importer.
- C67 (amend) … "Attachments from ALL extension items AND all providers of an item enter the
  dispatcher, including the extension-fallthrough audio branch." || check: 4 Signal notes → 4 clips.
- C136 [auto] A `.skriftbook` arriving through the share sheet is handed to the book importer,
  never saved as a file card. || check: ingress P18-bundle-via-share.
- C137 [tuur] A video note filed Made/Idea/Inspiration keeps the source movie as a synced asset
  (archive-bound only) so the archive gets it from whichever device exports; Personal video
  notes keep discarding it. Default: yes, capped at 200 MB. || check: corpus `video-made-archive`.
- C138 [auto] A share entry is deleted only after its memo is saved, on every type; the audio and
  video branches adopt the memo id from the entry so a re-drain is idempotent. || check: drainer
  test throwing after the entry delete → entry still present.

Recording:

- C139 [auto] An audio interruption (call, Siri, alarm) is a pause: the recording clock stops at
  `.began`, restarts at recovery, and photo offsets read that clock, so a picture after the call
  lands where it was taken; the hole is logged on the memo. || check: corpus `pic-after-interruption`.
- C140 [auto] Copy-edit runs per paragraph block when the input exceeds half the token cap:
  blocks of ≤ 1 500 words at paragraph boundaries, each guarded by C31–C34, re-joined in order;
  a long note is never shipped unedited because it is long. || check: corpus `voice-en-forty-minutes`.
- C141 [auto] Every transcript carries the ASR language mode it was made with
  (`metadata.asrMode`); a per-note "Transcribe again in Dutch/English" verb exists on the phone
  and the Mac and re-runs C42's trust; the global setting is only the default. || check: corpus
  `voice-nl-recorded-in-english-mode`.
- C142 [auto] New content appended to a polished note (append recording, capture ramble) is
  appended to the DISPLAYED body as raw text and sets `enhanceStatus` back to pending so the next
  pass polishes only the new block (C140 blocks). || check: corpus `voice-en-append-after-polish`.

Sync:

- C143 [auto] A raw-transcript edit that arrives with `editedAt` later than the row's
  `enhancedAt` invalidates the polish: the row goes back to pending and the phone shows the raw
  edit until the next pass. || check: `MemoCloudUpdateTests` post-run race.
- C144 [auto] Another device's `.transcribing` memo is taken over after 30 minutes when its audio
  asset is present and the recorder has not touched it; `recordingDeviceID` is kept. || check:
  aged corpus `voice-en-other-device-transcribing`.
- C88 (amend) "… un-rating keeps the row but drops it from the process queue and stops every
  export; a pending pass on an unrated row never runs." || check: corpus `voice-en-rated-then-unrated`.
- C145 [auto] Sync health is visible: a CloudKit quota/auth failure shows on the list within a
  minute and on the note as "not synced yet"; the dead `syncStatus` field is deleted.
  || check: `CloudSyncMonitor` tests with an injected quota error.

Lifecycle:

- C146 [tuur] Trashing an exported note leaves the vault file and says so on the note; Delete Now
  and the purge offer to remove the vault file when it is ours and untouched. Default: as stated.
  || check: corpus `typed-trashed` + ledger.
- C147 [auto] A purge deletes the memo's `MemoEnhancement` and every asset; a Mac row whose memo
  is gone from the store is trashed on the next sweep (never its vault file). || check:
  `NotesRepository` purge test; `MemoCloudReconcilerTests` orphan row.
- C148 [auto] A picture removed from the body is removed from the vault on the next export when the
  file is ours and untouched; the manifest entry stays (C14). || check: corpus `pic-deleted-after-export`.

Names:

- C149 [auto] A roster change (add, alias, rename) re-derives links for every processed row on the
  Mac once, deterministically, and re-exports the untouched vault files; the phone re-derives on
  read as today. || check: corpus `voice-en-bruno-before-roster` ×3 after the roster change.
- C150 [auto] A canonical rename rewrites `[[Old]]` → `[[New]]` and `people:` in every untouched
  vault file we own, and never touches edited or foreign files. || check: rename golden.

Audiobooks:

- C151 [auto] The captured quote is editable through a "Fix quote" verb on the phone; the new
  block becomes the escrowed quote everywhere; export attribution unchanged. || check: corpus
  `quote-en-with-ramble` edited-quote golden.

Locked / reminders:

- C152 [auto] Locking seals: a locked note is not polished on any device (Mac queue, iPad,
  `ProcessPile` agree); locking an exported note tells him the plaintext file still exists and
  offers to remove it when ours and untouched. || check: corpus `typed-locked` + ledger entry.
- C153 [tuur] A reminder set on any device (the Mac gets the control) rings on the device he is
  holding: the first acknowledgement clears the others, or it rings everywhere. Decide.
  || check: corpus `typed-reminder`.

Export:

- C154 [auto] Changing an exported note's destination removes the old file when it is ours and
  untouched, then writes the new one; if the old file was edited or moved the change is refused
  with the file named — a Personal note never remains in the archive. || check: corpus `dest-idea`
  → personal; `ArchiveExportTests`.
- C155 [tuur] A retitle never renames the exported file (the ledger path is sticky); the title
  changes inside. Default: as-is, stated. || check: `VaultWriteTests` retitle.
- C156 [tuur] Switching the vault folder does not move exports: old files stay, new notes go to
  the new folder, and Settings says so; a "move my exports" verb is a later idea. Default: as-is,
  stated. || check: `VaultWriteTests` two-root.

---

## Fixtures to add

Ingress (`test-fixtures/ingress/`, new folder; each = the provider set the extension would see +
the expected `note.json`):

- `P3-whatsapp-thread-with-picture/` — 5 opus clips (`WhatsApp Audio 2026-03-07 at 18.30.41…45.opus`),
  1 JPEG, sender "Bruno" (#1)
- `P1-voice-memo-named/kiln idea.m4a` + `New Recording 22.m4a` (#3)
- `P9-live-photo/` — JPEG + paired MOV (#4)
- `P9-photo-with-caption/` (#5) · `P9-thirty-photos/` shuffled EXIF (#16)
- `P10-email.eml` (#6) · `P7-apple-note-share/` (#7) · `P6-safari-selection/` (#8)
- `P5-maps-pin.url` (#9) · `P5-offline-first-get/` recorded responses, first fails (#10)
- `P12-airdrop-signal/signal-2026-04-13-18-15-24-552.aac` (#11) · `P13-three-clips/` (#12)
- `P2-signal-multiselect/` ×4 (#13) · `P18-bundle-via-share/*.skriftbook` (#14)
- drainer kill test after `delete(entryDir:)` (#19)

Corpus (`test-fixtures/corpus/notes/`, `note.json` shape as today):

- `voice-en-duplicate-content-a/b` — different ids, same audio hash (#2)
- `video-made-archive` — video note, destination made, source movie asset (#18)
- `pic-after-interruption` — 60 s audio, 20 s hole in `metadata.interruptions`, photos at 15 s/50 s (#21)
- `voice-en-forty-minutes` — ≈6k words, 8 paragraphs, word timings (#22)
- `voice-nl-recorded-in-english-mode` — `metadata.asrMode: "english"`, Dutch audio (#23)
- `voice-en-append-after-polish` — enhancement + a transcript longer than the copyedit (#27)
- `voice-en-rated-then-unrated` — `significance 0`, Mac row pre-seeded (#31)
- `voice-en-other-device-transcribing` aged 2 h with its audio asset (#30)
- `pic-deleted-after-export` — manifest of 2, body with only `[[img_001]]`, ledger entry (#39)
- `voice-en-bruno-before-roster` ×3 + a roster add event (#40); a roster rename event on
  `voice-en-names-all-tiers` (#41)
- `quote-en-with-ramble` edited-quote variant (#45)
- `typed-locked` + ledger entry (#46) · `typed-trashed` + ledger entry (#35)
- `dest-idea` → personal re-file (#48)

Unit tests without a corpus note: `MemoCloudUpdateTests` post-run race (#28), `NotesRepository`
purge deletes the enhancement (#36), `MemoCloudReconcilerTests` orphan row (#36),
`VaultWriteTests` retitle (#49) and two-root (#50), `CloudSyncMonitor` quota error (#34).
