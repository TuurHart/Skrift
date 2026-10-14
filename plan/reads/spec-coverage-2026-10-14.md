# Spec coverage audit, 2026-10-14

Read-only. Branch `claude/skrift-parity-audit-e9fa0c`, HEAD `e123229f`. Question: did we do all the outstanding spec points, did we redo the whole app?

## Answer

No. Rewrite target 1 (body/image) is done and its v1 code is deleted (tag `v1-body`). Targets 2, 3 and 4 (copy-edit, reconcile sweep, export compiler) were never started: no v2 code exists for them (no `CopyEdit`/`Reconcile`/`Export` V2 symbol anywhere in `Skrift_Native/`), and `QUEUE.md` still lists them under `## Later`. The queue instead spent its 381 done items on feature builds from the signed mocks, door-by-door parity fixes between phone/iPad/Mac, a 97-item twin and dead-code cleanup, a perf lane, Library, and release prep. 166 of 298 clauses have no done item behind them; 164 of those are cited by no queue item at all.

## Method and limits

- Parsed all 298 `- Cn [auto|tuur]` clauses, the 93 R rows, the 208 D decisions in `SPEC.md`, and all 407 `### Qn` items in `QUEUE.md`.
- A clause counts as done when a done item lists it in its `spec:` line (125), or names it in its body text (7 more, weaker). It does not prove the whole clause is met: an item often covers one slice of a multi-part clause.
- `[T/P/U/N]` after a clause id is the status from `plan/test-coverage.md` (2026-09-22, before the queue ran): Tested, Partial, Untested, Untestable-as-written. It is old; read it as a hint only.
- Code check was clause-id grep plus spot greps for the newest rules (C254-C260, C261-C274, C275, C284, C292, C297, C298). Those found no implementation. Baseline clauses were not re-verified in code; I did not run builds or tests.
- Queue state totals: 381 done, 13 tuur, 10 dead, 1 doing (Q407), 1 stuck (Q335), 1 todo (Q370).

## Totals

| Class | Count | Of |
|---|---|---|
| Clauses cited by a done item | 125 | 298 |
| Clauses only named in a done item's text | 7 | 298 |
| C132 (no item; Q258's log says the code matches it) | 1 | 298 |
| Clauses with no done item: cited by no item at all | 164 | 298 |
| Clauses with no done item: only a dead item (C160 Fix quote, dropped by D183) | 1 | 298 |
| Done clauses with a device check still open (C99 Q17, C112/C114 Q64, C115 Q221, C277 Q63, C282 Q369, C229 Q375) | 7 | 125 |
| `[tuur]` clauses: done / never cited | 21 / 11 | 32 |
| R rows cited or named by a done item | 31 | 93 (R10, R61 withdrawn; R1-R95) |
| R rows not cited, but every clause they map to is done (probably fixed, R never ticked) | 16 | 93 |
| R rows not cited, and a mapped clause is not done (open) | 46 | 93 |
| D decisions cited by a done item / open item / cited by none (verdict only) | 85 / 7 / 116 | 208 |

By class, of the 298 clauses: 105 `[auto]` cited by a done item, 6 more named, 153 `[auto]` never cited, 20 `[tuur]` done, 1 named, 11 never. One `[auto]` clause (C160) is dead-only.

## Clauses with no done item, by group

Group A is the real gap. Groups C to F are new work nobody queued. Group H is mostly existing v1 behaviour that the spec says "stays as is", so the missing item is expected, but nobody has re-proved it against the spec.

### A. v2 rewrite targets 2-4 (copy-edit, reconcile sweep, export compiler): the v2 code does not exist (36)

- C1 [N] v2 is built one subsystem at a time, in this order: body/image model → copy-edit → reconcile sweep →
- C7 [N] (drafter's harness design) Recorded model outputs are keyed by the exact prompt text and input; a mi
- C29 [T] The model sees prose only: memo-links escrowed to plain titles, picture paragraphs stripped, quote b
- C30 [U] Reinsert pictures by paragraph index (count picture paragraphs before, place after the same-index pa
- C32 [T] Token budget = min(8192, max(1024, chars/4 × 1.5)); output at ≥95% of the cap = truncated → unedited
- C33 [T] Shrink guard: input > 40 words and output < 55% of input words → unedited body + a logged line.
- C34 [P] Paragraph count of the shipped body ≥ paragraph count of the input, unless the shrink guard fired; a
- C35 [U] Fillers (um/uh/eh) and repeated words go; decisions, numbers, names and both languages stay; nothing
- C36 [T] Summary only when ≥ 75 words (manual Redo forces it); title always; a SHARE capture (url/text/image/
- C37 [T] Every pass writes ONE MemoEnhancement with processedAt, even when the model had nothing to say; isPr
- C38 [P] The Mac processes only enhanceStatus != .done; a phone edit to a polished note re-links and recompil
- C39 [P] The prompt is ONE source (PolishPrompts + synced override blob); a stale local override is migrated 
- C41 [T] After any sweep: every rated, live memo has exactly one Mac row (id = memo id); a NEVER-rated or tra
- C42 [P] Trust: a .done phone transcript is adopted iff userEdited
- C44 [P] v2 maps Memo + assets → PipelineFile directly (no fake multipart); the resulting row is field-identi
- C45 [P] Late assets (photos, word timings, diarization) heal on the next sweep; a heal never overwrites Mac-
- C46 [T] The Mac's polish goes back as MemoEnhancement, LWW by enhancedAt — stamp compared to STAMP with ±5 s
- C47 [T] Phone → Mac reflect is content-based per field (tags, rating, trash with its watermark, lock, remind
- C48 [T] Duplicates: same-id clones resolve to one keeper (alive > most content > latest edit); differing con
- C52 [U] The sweep runs at launch, activation and CloudKit import (coalesced), through a fresh context; no he
- C53 [T] The picked folder IS the destination, resolved by VaultLayout.home (C192, D11): a pick named Skrift,
- C55 [T] Unchanged content writes nothing; writes are atomic and file-coordinated; frontmatter key order is s
- C171 [P] Filler strip is opt-in (default off), voice memos only (never quotes or live caption), drops token +
- C177 [U] Post-conditions on every model output: no proper noun absent from the input; the language never flip
- C178 [P] After generation the deterministic tail runs in this order: tags → name-link (last) → compile; no [[
- C185 [U] Names and vocab reconcile BEFORE the memo sweep so linking sees the fresh roster; then notify → save
- C186 [T] Every Mac → phone writer resolves the memo through the STORE, never by filename alone; a Mac recordi
- C188 [P] Row match = memo id, else audioFilename — but never a row already owned by another memo (quote captu
- C189 [U] Auto re-export after a sweep happens only for notes already in the vault (unlocked, live); the first
- C190 [P] Asset materialisation never overwrites a file and refreshes on byte count only; stuck .transcribing 
- C191 [U] cloudKitMacSync defaults ON (an explicit false is honoured); silent push is registered on both apps 
- C192 [P] VaultLayout.home: a pick named Skrift, or holding a stamped .md, or containing a Skrift/ folder, is 
- C193 [P] The stamp hash spans the frontmatter (an Obsidian tag edit is a user edit) and every line but its ow
- C195 [T] Include audio in export = a per-note switch, default on, file named by the stem under Recordings/; t
- C285 The summary voice stays implied first person, present participle, never third person ("the speaker")
- C286 A golden model-output baseline is recorded once over the synthetic corpus so every later run diffs a

### B. Portfolio contract (export target), not started and now stale against D189 (two destinations) (8)

- C129 [T] What Skrift writes for Inspiration / Idea / Project is exactly what the portfolio stores: one flat m
- C130 [P] Portfolio frontmatter is flat YAML: one line per value, no :  inside a plain value (reword, never qu
- C131 [U] THE AUTHORSHIP LINE: everything above the closing --- is the machine's, everything below is HIS. A p
- C133 [P] Destination is one of four, single-select; "Personal" never reaches the portfolio; Project → _projec
- C134 [P] Credit is captured as a PHOTOGRAPH, not typed: an extra picture of the label travels with the entry;
- C135 [U] Empty body is a valid, common portfolio state (a bare picture); Skrift exports it without inventing 
- C136 [U] The portfolio-bound export carries the ORIGINAL audio beside the note (he reuses audio in videos), a
- C137 [T] people:, [[names]] and location: stay in portfolio exports (public site, credit his friends; C62, C1

### C. The one shared import layer (ingress rules with no item) (13)

- C67 [P] Attachments from ALL extension items AND all providers of an item enter the dispatcher, the extensio
- C69 [U] Audio outranks the URL representation (a WhatsApp voice note is audio); odd UTIs (Signal .aac, Teleg
- C75 [T] A share with an empty payload never saves a husk; failures are honest ("Skrift can't import this").
- C125 [N] Several text messages in one share keep their order among the clips and pictures; none is dropped.
- C126 [N] A Voice Memo shared with its own name ("kiln idea.m4a") keeps that name as the note's title; a messe
- C127 [N] Sharing the same file twice yields one note (same bytes → same note), with a "already in Skrift" not
- C141 [U] An image share with a text provider keeps the text as the annotation above the pictures (WhatsApp ph
- C142 [U] An email share (.eml / Mail) is a text capture: title = Subject, body = the plain text, recordedAt =
- C144 [U] Selected text + page URL is a text capture carrying the url and title, no fetch; a Maps link is a li
- C146 [P] A .skriftbook arriving through the share sheet goes to the book importer, never a file card.
- C198 [P] Share dispatch order: audio → web URL → movie → image(s) → plain text → document; first match wins; 
- C200 [N] Whether FluidAudio decodes ogg-opus on device is UNVERIFIED (the doc promises a Mac fallback, the co
- C201 [P] Inbox entries that cannot be deleted are tombstoned (cap 200) so nothing re-imports on every open; t

### D. Names fixes C254-C260 (R62-R69), none queued (7)

- C254 Same full name = same person. Adding a person whose full name matches an existing one merges into th
- C255 A Dutch bare possessive on an alias (Wims, Lottes) is recognised like the apostrophe form.
- C256 Name matching ignores diacritics both ways (Ines/Inés, Månsson/Mansson).
- C257 Naming a speaker who is not on the roster seeds the alias from the typed name or opens the person ed
- C258 A roster change that arrives by sync while a note is open re-derives that note's name spans at once,
- C259 A deleted person's voiceprints go with the tombstone; a sync merge never unions embeddings onto a to
- C260 An inline #tag is never split by name-linking, even when it equals an alias.

### E. Data-loss rows C261-C274 not covered by Q16/Q18/Q19 (R70-R87), none queued (10)

- C261 An editor commit that nets to empty (raw transcript or the Mac's polished copy) never lands silently
- C264 A .transcribing memo orphaned on a now-gone device is eventually adoptable by any device, or a Mac-s
- C267 A vocabulary/word-list edit merges with the latest synced state at write time, or re-reads immediate
- C268 Removing a synced audiobook's local download only frees storage once its upload to iCloud has comple
- C269 Removing a bookmark removes exactly the one nearest the tap and always confirms which/how many were 
- C270 A shared-book import re-checks it isn't already in the library immediately before unpacking, not jus
- C271 A capture-inbox entry is deleted only after its import into a memo is confirmed to succeed; a failed
- C272 A manual reprint keeps a note's prior printedAt stamp until the reprint itself succeeds; a failed re
- C273 A photo annotated with Markup keeps its un-annotated original recoverable; markup is never a destruc
- C274 A capture whose transcription yields no text is kept (or the user is told) until the note is saved o

### F. Small new rules with no item (C275, C283-C284, C289-C294, C297-C298, C280, C296) (13)

- C275 A spoken hashtag becomes a real tag, by rule and not by the model: "hashtag motivation" / "hashtag m
- C280 A directory-locating accessor creates its directory at most once per process launch, never on every 
- C283 A roster change re-exports every already-exported vault .md file whose people: frontmatter is now st
- C284 YAML frontmatter carries editedAt alongside the createdAt/duration fields D12 already added.
- C289 A whole ePub import ingests every part of the source file, or reports exactly what it skipped and wh
- C290 A long ePub/book import shows real progress and states whether listening can continue during the imp
- C291 ePub upload is blocked, with a clear message, while the same book's transcription is still running.
- C292 The model-download completeness check verifies the actual download by byte count or hash, not a size
- C293 Multi-select import of several distinct books never merges them into one.
- C294 A query issued mid-sweep never observes a partially-swapped memo; the sweep's await points are guard
- C296 The performance debt list is a queue lane: every site named in plan/perf-sweep.md §2 and in plan/sou
- C297 An imported book's title never repeats its author: "Title — Author" plus a separate author byline co
- C298 Unsharing an audiobook never leaves a phantom library entry: an entry with no local audio and no clo

### G. Sync, lifecycle and export-hygiene scenario rules (C149-C164): no item, behaviour unverified (12)

- C149 [U] An interruption (call, Siri, alarm) is a pause: the recording clock stops and photo offsets read tha
- C151 [U] A transcript carries the ASR language mode it was made with, and a per-note "Transcribe again in Dut
- C152 [U] Text appended to a polished note (append recording, capture ramble) appears in the body he sees and 
- C153 [P] A raw edit newer than the row's enhancedAt sends the row back to pending; the phone shows the edit u
- C154 [U] Another device's .transcribing memo is taken over after 30 minutes when its audio is present and the
- C155 [U] Sync health is visible: a CloudKit quota or sign-in failure shows on the list within a minute and on
- C157 [P] A purge deletes the note's polish row and every asset; a Mac row whose memo is gone is trashed on th
- C158 [U] A picture removed from the body is removed from the vault on the next export when the file is ours a
- C159 [U] A roster change (add, alias, rename) re-derives links for every processed row on the Mac once, deter
- C163 [U] Changing an exported note's destination removes the old file when ours and untouched, then writes th
- C164 [P] A retitle never renames the exported file ("rename just has to be done in Obsidian" — Tuur 2026-09-2
- C245 [P] Whatever device records, every other device gets the same note: a Mac take's word timings (and diari

### H. Baseline behaviour in "stays as is" sections: v1 code exists, no item was needed (verify by test, not by queue) (43)

- C18 [T] BodyTransform stays the ONE raw ⇄ display transform: [[img_N]], [[memo:UUID|Title]], line-start - [ 
- C22 [T] The leading >  block is the quote (not gated on book metadata); the ramble is everything after the b
- C23 [P] A conversation = ≥2 line-anchored **Name:** headers with ≥2 distinct names; **Pros:** mid-body is no
- C24 [P] Headings ^#{1,6}  and inline #tags are recognised from text; marks stay dim-visible; characters verb
- C26 [P] Karaoke: raw body word N = timing N; polished body aligned via AlignmentCore; a body that doesn't ma
- C82 [P] Names inside a quote block, code, YAML or a memo-link title are never linked.
- C85 [T] names.json is byte-compatible across apps (one encoder, sorted keys); sync = per-person LWW with voi
- C86 [U] Audiobook authors never enter the roster.
- C89 [T] ONE clock: clockStart = max(recordedAt, keptAt); touch restarts 30 days; fading at 30, Recently Dele
- C95 [T] The phone carries the RAW transcript + confidence / userEdited / markers / metadata / optional title
- C96 [P] Every synced field is additive with a default; MemoAsset.blob is plain Data; local-only derived fiel
- C97 [T] A receiver never re-transcribes another device's in-flight memo.
- C100 [P] Instant record on every entry; with Bluetooth present the whole memo records on the built-in mic; ev
- C101 [T] Live caption seeds the note; the stop-pass file transcription is the truth; the ASR tail order is on
- C103 [P] Custom vocabulary syncs whole-list LWW; the booster pre-warms at launch; a boost is dropped when eve
- C104 [P] Skrift is the player; one memo per quote capture (quote block + ramble + book metadata; quote audio 
- C105 [T] Chapter precedence ePub TOC > transcript-detected > embedded; "better no information than bad": inco
- C106 [P] Whole-book transcription: 180 s chunks via sample-accurate frame reads (never AVAssetExportSession),
- C107 [T] Book sharing = one .skriftbook with audio + ePub + sidecars, never position / bookmarks / notes; imp
- C109 [P] Embedder = EmbeddingGemma-300M via CoreML-LLM, per-device index, never synced; only rated live notes
- C116 [N] Markdown marks stay dim-visible; bodies stay plain Markdown prose + tasks (no tables, no rich-text s
- C120 [N] No cloud AI, ever; the only network calls are weather at capture and the one URL fetch on drain, bot
- C121 [T] Personal notes never land in a folder a CLOUD AI reads; the destination is a stored field, one of fo
- C122 [N] The corpus is synthetic; agents never read his vault and never screenshot the live app at a real not
- C174 [T] Conversation detection is gated on an audio source; an Apple Note with two bold headings is prose.
- C176 [T] Capture-image markers in an annotation convert and copy like memo photos; the pinned embed is skippe
- C184 [P] The verb is "Process" on every device; "memo" → "note" in every user string. — A33
- C204 [T] Canonical = the People/ note title; Skrift writes links and people:, never the person page; roster s
- C205 [T] Normalisation ≠ linking: registered aliases fix a misheard KNOWN name everywhere (dotted when unlink
- C206 [T] Two unlink scopes, note-local (this mention / all mentions in this note), persisted in the note's re
- C207 [P] A roster collision re-derives every processed memo that auto-linked the name (dotted suggestion + co
- C208 [T] names.json merge: per-person LWW on the stamp, tombstones win when newer, pruned after 90 days; alia
- C209 [P] Voice identity: true cosine, ≥ 2 s of speech, max over the stored list, audio discarded after embedd
- C211 [T] The three lifecycle strings are byte-pinned in the spine ("starts fading <date>" · "moves to Recentl
- C216 [P] Memo.id is the spine: never regenerated, embedded in the audio filename, equal to the Mac row id; as
- C219 [N] The schema is additive-only; a synced @Model is never renamed or dropped (dead AudiobookAsset stays)
- C221 [T] The recorder survives every route change and interruption: the tap is reinstalled in the current har
- C223 [T] Append never lands empty: audio merged sample-accurate, text appended with a blank line, timings shi
- C225 [P] Memo playback and the book session are mutually exclusive; ducking only on Play; the book resumes on
- C226 [P] Capture always records voice (a bail discards the quote-only memo); build-your- quote is bounded (~9
- C227 [T] ePub alignment: unique n-gram anchors → LIS → banded DP, exact per-word times, verdict aligned / par
- C228 [P] detectedChapters: [] = ran and found nothing, nil = not yet; sidecars are file-local; a quote span n
- C230 [P] Index grain = one gist vector (title + summary + place + people + tags) plus body chunks every ~150–

### I. Method / process clauses (rules for how work is done, not app behaviour) (11)

- C166 [U] Mac corpus goldens come from -ingestfile → -processfile -exportafter on the Dev store (GUI quit firs
- C167 [U] Every engine and the model are revision-pinned; a pin bump is its own commit and owes a device round
- C168 [U] No swallowed error on any write surface (vault, store, sync); every refusal reaches the UI as text; 
- C244 [U] Battery is measured, not guessed: one hour of playback and one hour of whole-book transcription on t
- C246 [P] No "expected" without a citation: any claim in a report or a spec clause that a behaviour is intende
- C247 [T] PARITY TABLES, generated from the code, not from memory: (A) every item a note carries × every devic
- C248 [T] THE BUG-SHAPE SWEEP: a checklist of the shapes this codebase has already produced — the silent empty
- C249 [P] ROUND TRIPS AS TESTS: the corpus goes in on one side and is read on the other, field by field — Mac 
- C250 [P] Every "expected", "by design", "harmless" or "fine" in a report, a clause or a message carries a src
- C251 [T] A fresh scenario probe (20 cross-device scenarios, traced through the code, like plan/extraction/sce
- C276 A cited document is not a folded document. Every plan, handoff, audit and backlog doc in the repo (a

### J. [tuur] clauses that need his eyes and have no check item (11)

- C108 Player, reading mode, bookmarks and the Text sheet match their signed mocks on the iPhone 13; remain
- C118 Built on main, his eyeball owed (⚠ unverified): the m2 note card on Mac + iPad (b155), the one-clock
- C138 Ideas do NOT come back into Skrift in v2: the portfolio reads Skrift's files, never the reverse, and
- C139 "AI reads this" is a statement about the portfolio repo only; what reads it (the teleprompter sessio
- C156 Trashing an exported note leaves the vault file and says so; Delete Now offers to remove the file wh
- C175 Mac turns = right gutter + spine (E1, signed 2026-07-27); the phone KEEPS its turn cards with the sh
- C197 Full-exportability doctrine (2026-07-18: the vault is a complete mirror of rated notes; timings, emb
- C214 Retention doctrine: the permanent corpus is the rated notes; nothing is pruned without a review he a
- C235 Built UI matches the signed-and-built rows of mocks-roadmap §B (editor, accessory bar, player pill, 
- C243 A playing book NEVER stops when the app is backgrounded or the phone locks; after a call or Siri it 
- C295 Print-to-wall fires only to the saved printer, never a random or office-network printer.

### K. Dead / withdrawn (1)

- C160 [U] A captured quote can be corrected ("Fix quote" on the phone); the corrected block is the escrowed qu

## Partial: cited by a done item, but only a slice of the clause

These are in the 125 above but the done item covers one narrow part. The rest of each clause belongs to targets 2 to 4.

- C28: C150: Q157 only added a blank-prompt fallback and Reset to default; the one-model/pinned-revision and long-note rules are v1 code, not rebuilt.
- C31: Q112 only made the Mac quote block read-only; the escrow rule ("lost link or changed quote byte = ship unedited") is v1.
- C57 C64 C196: Q142, Q153-Q155 made phone and Mac export the same names, dates and embeds. The compiler is still v1 (`Shared/Export/Compiler.swift`), not an export v2.
- C54 C56 C58: Q19, Q32, Q34 added the ownership rule to the attachment lanes; the "pure compiler" and byte-identical-output parts are not proved.
- C61 C180 C194: Q117/Q118/Q156 unified the Process/Export input and copy; the process-queue rules sit on v1 code.
- C62: Q84/Q98/Q158 built four-destination behaviour, then D189 (Q338) cut it to two. The clause text still says four.
- C65: Q13/Q15/Q226 removed the snap. Closed for body; the export side is only as good as the v1 compiler.
- C277 C282: Q53/Q56/Q363 fixed typing cost; Q63 (feel on Mac) and Q369 (perf re-run) are tuur checks still open. Q52 (R92) is dead.
- C229: Library: Q147-Q151, Q352-Q356, Q403, Q404 done; Q375 (his look at the tab on Dev) open; Kindle/Readwise highlights and talks (D90) not queued.

## R rows

### Open (46): a mapped clause has no done item

- R3 (C30 C34) paragraphs as without pictures; pictures in place
- R4 (C67) every clip, in chat order
- R14 (C34) judged per block
- R16 (C152) appended text shown + re-polished
- R18 (C157) row + assets gone; orphan row trashed
- R19 (C149) offsets follow the recording clock
- R20 (C163) old file removed when ours
- R21 (C159) rewritten everywhere we own
- R22 (C125 C141) all texts, in order
- R26 (C39) one prompt source
- R27 (C34) shipped ≥ in on every corpus wall
- R28 (C208) deterministic tie, ±5 s skew
- R29 (C45) 0 blob fetches on an unchanged corpus
- R30 (C23 C115) a monologue never carries turn markers; one parser on both apps
- R31 (C89) every content edit is a touch
- R35 (C245) timings + diarization ride back as assets
- R40 (C168) a failed sweep is logged and shown (C168)
- R41 (C131) voice: derives from ONE rule on both apps
- R43 (C76 C168) a read failure is an error, never an empty note
- R44 (C46) LWW compares stamps to stamps, with skew tolerance (D60)
- R45 (C89) age clamps at 0; a future date is flagged
- R47 (C155) the app notices, stops syncing, says so
- R53 (C192) stale bookmark → re-prompt, never a second folder
- R56 (C89) the open note is never swept from under the user
- R57 (C45) content-hash staleness; re-adopt on change
- R60 (C23) an edit commits to the turn it started in
- R62 (C254) the merge is announced and case-insensitive on every path
- R63 (C259) a tombstone carries nothing
- R64 (C82) every quote run protected (D21)
- R65 (C260) tags never split
- R66 (C257) alias seeded or the editor opens
- R68 (C256) both directions match
- R69 (C255) recognised like Wim's
- R70 (C261) an empty commit asks first, or the prior text is kept recoverable
- R72 (C223) append gates on / waits for transcriptStatus != .transcribing, or writes are version-
- R75 (C264) \
- R76 (C100) the pending intent either fast-paths into recording once onboarding completes, or the
- R80 (C267) a concurrent addition on two offline devices is never silently dropped; merge additiv
- R81 (C268) removing a synced audiobook's local download only frees storage once its upload to iC
- R82 (C269) removing a bookmark removes exactly the one nearest the tap and always confirms which
- R83 (C270) re-check alreadyImported immediately before unpack, or diff file hashes before overwr
- R84 (C271) the inbox entry is retried, never silently discarded, until import actually succeeds
- R85 (C272) a manual reprint keeps the prior printedAt stamp until the reprint itself succeeds
- R86 (C273) copy the source aside (or a second MemoAsset blob) before presenting .updateContents
- R87 (C274) a capture whose transcription yields no text is kept (or the user is told) until save
- R89 (C168) a second consecutive store-save failure is a visible error, matching C168's letter fo

### Probably fixed under a done clause, R never ticked (16)

Spot-check these in the next sitting; each maps only to done clauses. Known good: R5 (Q94, Q96, Q134 filename date), R6 (Q34, Q153), R11 (Q138), R13 (Q137).

R5, R6, R11, R13, R17, R23, R32, R38, R39, R48, R49, R50, R52, R54, R55, R73

## `## Later` bullets in QUEUE.md

| Bullet | Status | Evidence |
|---|---|---|
| Builds of Q3 tag UI, Q4 conflict prompt, Q6 sources tab | Done | Q28, Q36, Q41, Q44 (tags); Q29, Q38, Q39, Q42, Q45 (conflict); Q352-Q356, Q403, Q404 (Library). Q375 look still open. |
| Target 2 copy-edit v2 (C28-C40, C150, C177-C182), first C30 C35 C40 as tests | Not started | C30 and C35 uncited. C40 was touched only by Q90, Q127 (Process floors a note to 0.1). No copy-edit v2 code. |
| Target 3 reconcile v2 (C41-C52, C185-C191), first C52 as a test; twin audit before it | Twin audit done, reconcile not started | Twin lane Q171-Q248 done (97 items citing C239/C240, `plan/twin-check.sh` in the gate per Q175). `plan/twins.md` was never written; the twin audit lives in `plan/sweep-e-shared-twins.md`. C41-C48, C52 uncited. |
| Target 4 export v2 (C53-C65, C129-C137, C192-C196), first C57 C64 C65 as tests | Partial | C57, C64, C65, C196 touched by Q153-Q155, Q13/Q15, Q226 as parity fixes. C53, C55, C129-C137, C192, C193, C195 uncited. |
| Perf lane after the Q20 baseline | Mostly done | Q20 baseline; Q52 dead, Q53-Q56, Q313-Q323 (phone), Q361-Q365 (Mac). Uncited: C280 (directory accessor, R93 only named) and C296 itself; Q369 re-run open. |
| Editor rebuild on body v2 with Apple Notes formatting (C113, C234, D112, D115) | Done | Q349-Q350 mocks, Q358-Q360, Q379, Q382, Q387 built. |
| One shared import layer (C238, C66-C79, C123-C128, C140-C147) with ingress fixtures | Partial | Door parity fixed one at a time: Q74, Q92-Q96, Q132-Q137, Q286, Q307, Q333, Q337. No single import layer; ingress clauses C67 C69 C75 C125-C127 C141-C146 uncited; no `ingress/` fixture folder in `test-fixtures/corpus`. |
| Mock refreshes: Mac Names screen (D108), `resolver-inline` vs shipped popover (D109) | Open | No item cites D108 or D109. |
| Library imports: Kindle/Readwise highlights and talks (D90), Library on iPad/Mac widths | Open | After Q352-Q356 nothing queued for Kindle/Readwise, talks, or Library at iPad/Mac width. |
| Data-loss rows C261-C274 not covered by Q16/Q18/Q19 | Open | Groups E above. Only C262 and C263 (Q17 area) and C265/C266 got items. |
| Names fixes C254-C260 | Open | Group D above; no item. |
| Mac feedback transport (D111, host owed) | Partly done | Q342 (FeedbackKit button in the Mac app) done. Q308 reads FeedbackKit outbox over USB. D111 itself (transport on the Mac, host owed) has no item. |

## Open tuur items (device checks and decisions)

| Item | State | What |
|---|---|---|
| Q17 | tuur | Force-quit and phone-call mid-take; pull devlog. Written for iPhone 13, the phone is now the 17 Pro. |
| Q64 | tuur | Quick note full screen, pencil opens a new note, toolbar stays. Same iPhone 13 wording. |
| Q63 | tuur | Mac typing feel after Q56 (headings and links restyle after 1 s). |
| Q221 | tuur | Camera pinch zoom compounds; media-services reset brings back the Bluetooth mic. Unrun, read-only finding. |
| Q280 | tuur | Look at phone list header and filter date picker after Q171. Body says "(fill in)". |
| Q281 | tuur | Share a voice memo, video, URL, photo into Skrift (Q245). "(fill in)". |
| Q302 | tuur | Mac Dev: custom word, person, polish prompt sync from the phone (Q242). "(fill in)". |
| Q304 | tuur | Mac Dev: Add recording to a rated voice note. "(fill in)". |
| Q309 | tuur | Mac and iPad Dev: command-N, shift-command-N, command-F, command-1/2. "(fill in)". |
| Q311 | tuur | Phone Dev 177+: add a recording to a voice note, play across the join. "(fill in)". |
| Q375 | tuur | Library tab on Dev: shelf, podcast link, PDF share and reader, send to a note, jump back. |
| Q368 | tuur | Mac upgrade test on a copy of the real Mac data. |
| Q369 | tuur | Perf re-run on phone and Mac before promotion (D186). |
| Q335 | stuck | Real Skrift on the Mac: grant Full Disk Access, run the Apple Notes import. |
| Q370 | todo | Update the real Skrift on phone and Mac once Dev checks pass; D206 then gives a month of real use. |
| Q407 | doing | Install Dev 190 on the iPhone 17 Pro and the Mac (auto item, in flight). |

`[tuur]` clauses with no check item at all (group J): C108 (player and Text sheet against signed mocks), C118 (unverified-on-device list), C138, C139, C156, C175, C197, C214, C235, C243 (book keeps playing when backgrounded), C295 (print only to the saved printer). SPEC.md carries 35 `⚠` marks (built on main, never seen on a device by him).

## Spec drift found on the way

- C62, C121, C133 still say four destinations; D189 and Q338 shipped two (Personal, Portfolio). The portfolio clauses C129-C137 need a re-baseline before anyone builds export v2 from them.
- `SPEC.md` Done-means and Q17/Q64 name the iPhone 13; the test phone is the iPhone 17 Pro.
- C253 asked for the 19 untested clauses of targets 2 to 4 to become tests first; Q9/Q10 cited it but only for body clauses. C30, C35, C52 and the rest were never turned into tests.
- C3 (v2 at most 40% of v1 lines) and C5-C7 (v1-vs-v2 diff harness) exist for body only (`BodyV2HarnessTests`, `plan/reads/body-v2.md`).
- `plan/RESUME.md` still says 2026-09-23 state; the Q349-Q407 work (Library, Apple Notes clone, attachments, Dev-era merge) has no spec clauses, only D190-D208.

