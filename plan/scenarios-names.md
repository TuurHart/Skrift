# Names subsystem — scenario trace + bug-shape sweep (2026-09-22)

Scope: `Shared/Naming/*.swift` (Sanitiser 781, NameStoplist, NameMatch, NamesData,
NamesStore, NamesSyncCore, PersonEditCore, QuoteProtection), `Shared/Pipeline/SpeakerTranscript.swift`
+ `SpeakerTurnStyle.swift`, `SkriftMobile/Models/Memo+Mobile.swift` (nameResolutions),
`SkriftMobile/Features/Names/*`, `SkriftMobile/Features/MemoDetail/MemoDetailView.swift`
(name-span dialog + person sheet, ~960–1990), `SkriftMobile/Services/Export/MemoLinking.swift`,
`SkriftDesktop/Pipeline/Sanitisation/*`, `SkriftDesktop/Features/Review/BodyTextView.swift`
(popovers ~954–1200) + `NoteDisplayView.swift` (savePerson/rescanRoster), `SkriftDesktop/Features/Settings/{SettingsView,PersonEditor}.swift`,
`SkriftDesktop/Pipeline/Ingest/MemoCloudUpdate.swift`, `SkriftDesktop/App/NamesCloudSync.swift`.
Every candidate below was read in context, not inferred from a filename or doc comment.

Already known, not repeated as new findings (cited where a scenario lands on them):
Mac ignores the phone's picks / phone's export ignores its own picks (**R37**, `MemoCloudUpdate.swift:156`,
`MemoLinking.swift:26`); phone-added person has no aliases (**R12**); rename leaves `[[Old]]`
in Mac rows + vault files (**R21**, `C159`). `names.json` non-atomic write / torn-read →
empty roster (**R8**/`C50`) is also pre-registered — flagged below only because the CURRENT
Swift port (`NamesStore.swift:49-51`) still has the exact defect, which is new information
(it wasn't re-verified against the native rewrite before).

---

## 1. Twenty-five scenarios

| # | Scenario | Verdict |
|---|---|---|
| 1 | Two people, same full name | **CONTRADICTED** |
| 2 | First name is a Dutch word (Wil/Lot/Roos) | COVERED |
| 3 | Sentence-start capital ("Rose is here" vs "rose is here") | COVERED |
| 4 | Possessives: "Lotte's" vs bare Dutch "Lottes" | PARTLY |
| 5 | Hyphenated + initials aliases (Pieter-Jan / PJ) | COVERED |
| 6 | Diacritics: Ines vs Inés, Månsson | **UNCOVERED** |
| 7 | Name inside a memo-link title | COVERED |
| 8 | Name inside a mid-body `> ` quote (not the leading one) | **CONTRADICTED** |
| 9 | Name inside a heading line | COVERED |
| 10 | Name inside a `[[ ]]` the user typed | COVERED (linking) / see R49 (export) |
| 11 | Speaker header for a person NOT on the roster | PARTLY |
| 12 | Renaming a person while a note mentioning them is open on another device | **PARTLY / CONTRADICTED** |
| 13 | Deleting a person who has voiceprints | **UNCOVERED** |
| 14 | Adding an alias that is another person's canonical | COVERED |
| 15 | Alias that is a substring of another ("Ann" vs "Anna") | COVERED |
| 16 | 200 mentions of one name in one note | COVERED |
| 17 | Name appears only in the polished body, not the raw | PARTLY |
| 18 | Person added in the roster on the Mac while the phone is offline | COVERED |
| 19 | `people:` frontmatter for a conversation | COVERED |
| 20 | Unlinking on the phone, then processing on the Mac | **CONTRADICTED** (= R37) |
| 21 | The stoplist for Dutch — does it exist, what's in it | COVERED (documented below) |
| 22 | A name that is also a tag | **UNCOVERED** |
| 23 | A name that is also a place | N/A (no in-body place-linking exists) |
| 24 | Person with an empty canonical or `[[ ]]` only | COVERED |
| 25 | Two devices adding the same person at once | **CONTRADICTED** |

Counts: **8 COVERED-clean**, 2 N/A/documented, 4 **PARTLY**, **11 UNCOVERED/CONTRADICTED**.

---

## 2. Scenario detail

### #1 — Two people, same full name — CONTRADICTED

The app cannot hold two live people with the same canonical name; adding a second one
silently **fuses** them into the first.

- `NamesStore.upsert(_:replacing:)` (`NamesStore.swift:157-179`): when there's no
  `replacing` match (a genuine new person, not a rename) but the new canonical
  case-insensitively matches an EXISTING live person, it takes the **merge** branch
  ("ADD whose name collides with an existing person → MERGE rather than clobber"):
  unions the two people's aliases, keeps the existing short/voice unless the new one set
  them. There is no code path that creates a second, distinct `Person` for a repeated
  canonical.
- `NamesMerge.mergeByCanonical` (`NamesData.swift:154-184`) keys its dictionaries by the
  literal `canonical` string (`localBy[p.canonical] = p`), so even at the sync layer two
  distinct people sharing a canonical cannot coexist — the second silently overwrites the
  first in the merge dictionary before LWW is even applied.
- Consequence: adding "John Smith" (coworker) when "John Smith" (family friend) is already
  in the roster does not create a second person — it appends the coworker's aliases onto
  the friend's entry and, if the coworker is later voice-enrolled, their voiceprint unions
  onto the SAME `Person` (`unionEmbeddings`, unconditional). Every future mention of either
  "John Smith" auto-links to one conflated identity, and a voice match can misattribute
  either person's speech to the other.
- This is a different shape than C207's "two-Jacks" (`Jack Hutton` / `Jack Timmons` — two
  DIFFERENT canonicals sharing one alias, explicitly legal). Two IDENTICAL canonicals were
  never designed for.

Proposed clause: **C254** — "Two people cannot share a canonical name silently: adding a
person whose full name exactly (case-insensitive) matches a live person must not merge them.
Either the second add is refused with a disambiguation prompt (append a distinguisher, e.g.
a middle name / initial) or the two are kept as genuinely distinct roster rows with distinct
storage keys (not the bare canonical string)." Fixture: `roster-duplicate-canonical` — add
"John Smith" with alias "Johnny", then a second "John Smith" with alias "JJ" and a
voiceprint; expect two rows, not one with aliases `[Johnny, JJ]` and a shared voiceprint.

### #2 — First name is a Dutch word (Wil / Lot / Roos) — COVERED

`NameStoplist.commonWords` (`NameStoplist.swift:30-33`) explicitly lists the Dutch
collisions: `wil, roos, lente, floor, lot, fleur, bloem, guus, storm, loes, mees, duif,
vlinder`. All three requested names (`wil`, `roos`, `lot`) are present. `isFpProne` treats
them as FP-prone regardless of case, so they surface as a dotted suggestion
(`suggestedOccurrences`, `Sanitiser.swift:526-531`, capitalized-only) rather than
auto-linking — same treatment as the English list, verified by reading the shared code path.

### #3 — Sentence-start capital ("Rose is here" vs "rose is here") — COVERED

`suggestedOccurrences`'s FP-prone branch only records a **capitalized** occurrence
(`startsUppercase` gate, `Sanitiser.swift:509,730-733`). "rose is here" (lowercase) is never
suggested or linked; "Rose is here" (capital, sentence-initial) IS suggested — dotted,
tap-to-link — which is the documented, accepted trade-off (C207: "sentence-initial 'Will
you…' noise is accepted"). Both directions traced and match spec intent.

### #4 — Possessives: "Lotte's" vs Dutch "Lottes" — PARTLY

`possPattern = "(?<poss>(?:'s|'s)?)"` (`Sanitiser.swift:40`) only recognises an
**apostrophe**-s. "Lotte's boek" correctly matches alias "Lotte", links `[[Lotte]]'s`, the
possessive riding outside the brackets (`possText`, line 758-763).

A **bare** Dutch possessive with no apostrophe on a consonant-final name — "Wims auto" for
"Wim's car", or the requested "Lottes" — is invisible to the matcher: `wordRegex` requires a
`\b` word boundary immediately after the alias (`Sanitiser.swift:751-753`), and inside
"Lottes"/"Wims" the character right after the alias is another word character (`s`), so
there is **no boundary** there — the regex simply never fires, and the name is neither
linked nor suggested; it reads as plain, unremarkable text.

Proposed clause: **C255** — "A Dutch bare possessive (`Wims`, `Lottes` — no apostrophe) on a
registered alias is recognised the same as the apostrophe form." Fixture:
`edge-name-dutch-possessive` — "Wims auto stond er nog" with "Wim" on the roster; expect a
linked/suggested span, not silence.

### #5 — Hyphenated + initials aliases (Pieter-Jan / PJ) — COVERED

`isFpProne` treats internal whitespace as "always distinctive" but a hyphen is not
whitespace, so "Pieter-Jan" (7+ chars, no space) is checked against `minAutoCommitLength`/
`commonWords` like any single token — not in the stoplist, length ≥ 3 → auto-links.
`wordRegex`'s `\b…\b` correctly brackets the whole hyphenated token (hyphen is a non-word
character, so `\b` sits at "Pieter" and after "Jan"). "PJ" (2 chars) is FP-prone by the
length rule alone → suggested, one tap — exactly the documented ≤2-char-name behaviour
(`NameStoplist.swift:35-39`). Both forms traced and behave as specified.

### #6 — Diacritics: Ines vs Inés, Månsson — UNCOVERED

`wordRegex` (`Sanitiser.swift:748-756`) compiles with `options: [.caseInsensitive]` only —
no `.diacriticInsensitive`. `NSRegularExpression` is diacritic-**sensitive** by default, so
an alias stored as "Ines" will not match a transcript token "Inés" (or vice versa), and an
alias "Mansson" will not match "Månsson". Given the app's own English/Dutch-mixed voice
input and ASR output can plausibly drop or add diacritics inconsistently between what the
user types into the roster and what the transcript renders, this is a real, silent miss —
no suggestion, no link, nothing.

Proposed clause: **C256** — "Name matching is diacritic-insensitive: a registered alias
matches its accented/unaccented transcript form either direction." Fixture:
`edge-name-diacritics` — roster alias "Ines", transcript "Inés was there"; and roster
"Månsson", transcript "the Mansson report" — both directions.

### #7 — Name inside a memo-link title — COVERED

`nonProseRanges` explicitly protects memo-link spans: `for occ in
MemoLinkSyntax.occurrences(in: text) { ranges.append(occ.range) }` (`Sanitiser.swift:722-724`,
comment: "an alias inside a link TITLE must never be name-linked"). Verified this is a
distinct protected-range entry, not incidentally covered by the `[[ ]]`-skip logic (memo
links use `[[memo:UUID|Title]]`, a different syntax `notInsideLink` alone wouldn't
necessarily gate correctly against).

### #8 — Name inside a mid-body `> ` quote — CONTRADICTED

D21 (decided **today**, 2026-09-22, per `SPEC.md`): "a name inside **any** quote block is
never linked." The code only protects ONE quote shape: `QuoteProtection.splitLeadingQuote`
requires `text.hasPrefix(">")` — i.e. only a blockquote that opens the WHOLE note (the
audiobook-capture C1 shape) is excluded from scanning (`Sanitiser.swift:713-716`). A `> `
blockquote that appears anywhere else in the body — a pasted email reply, a quoted text
message referenced mid-note, a second quote later in a long capture — is ordinary prose to
the scanner and a roster name inside it WILL auto-link or suggest exactly like unquoted
text. This directly contradicts the now-decided C82/D21 wording.

Proposed clause: **C82 (tightened)** — extend `nonProseRanges` to protect every `(?m)^>`
line-run in the body, not only one anchored at offset 0. Fixture:
`edge-name-midbody-quote` — a note whose SECOND paragraph is `> Jack said hi` with "Jack" on
the roster; expect no link/suggestion inside the quoted lines.

### #9 — Name inside a heading line — COVERED

No special-casing exists for markdown heading lines (`#`/`##`) in `nonProseRanges`, and none
is called for — C82 only lists quote/code/YAML/memo-link-title as protected, so a name in a
heading (`## Meeting with Jack`) is expected to link like any other prose, and does.
Confirmed by absence, not presence, of a guard.

### #10 — Name inside a `[[ ]]` the user typed — COVERED (linking) / see R49 (export)

`eligible()`'s `notInsideLink` gate (`Sanitiser.swift:686-689, 765-771`) skips any scan
location already inside an EXISTING `[[…]]` span, regardless of what it links to — a
hand-typed `[[Some Other Thing Jack]]` is never touched by the name pass. What happens to
that literal link on EXPORT if its target isn't a known person is a separate, already-
registered concern (R49/C59, `Compiler.plainifyNonPeopleLinks`) — not re-derived here.

### #11 — Speaker header for a person NOT on the roster — PARTLY

`SpeakerTurnStyle.HeaderResolver.person(for:)` (`SpeakerTurnStyle.swift:36-45`) correctly
returns `nil` for an unmatched header — it stays plain, uncoloured-by-identity (falls back to
a raw-label slot), matching C207's "unnamed stays unnamed."

But the ASSIGN flow that names a "Speaker N" turn (`MemoDetailView.assign`,
`MemoDetailView.swift:1648-1690`) does more than relabel text: when `enroll` is true it
calls `VoiceEnroller.enroll(name: new, …)` → `NamesStore.addVoiceEmbedding(canonical: name,
…)` (`NamesStore.swift:113-128`), and `addVoiceEmbedding` **creates the person if they don't
exist** — with `aliases: []`. This is the SAME shape as R12 (alias-less, never links by
text) but via a silent, no-confirmation path: typing any new name into the speaker-assign
sheet mints a permanent roster entry with a voiceprint and zero aliases, with no editor
shown and no way to notice it happened short of opening Names & Voices later.

Proposed clause: **C257** — "Naming a speaker who isn't on the roster either opens the
person editor (so aliases can be set) or seeds the alias from the typed name, same as
`PersonEditCore.materialise`'s empty-alias default — never a bare `aliases: []` roster
entry." Fixture: `edge-speaker-assign-new-name` — assign "Speaker 2" to a fresh name typed
inline; expect the resulting `Person` to have ≥1 alias.

### #12 — Renaming a person while a note mentioning them is open on another device — PARTLY / CONTRADICTED

Two distinct layers:
- **Already known**: R21/C159 — the Mac's own batch re-derive + vault rewrite exists, but
  "today only the open note re-scans; phone and Mac exports diverge after a rename."
- **New, narrower**: on the phone, `MemoDetailView`'s `people` state is loaded exactly once
  per note-open (`.task(id: memo.id)`, `MemoDetailView.swift:821, 893-896`) and refreshed
  only from the two LOCAL edit callbacks (save/delete a person from THIS device,
  `MemoDetailView.swift:982, 986`). `NamesCloudSync.run` (`NamesCloudSync.swift:21-36`,
  mobile) never posts a notification on completion — there is no
  `.namesDidChangeFromSync`-equivalent listener on the phone (the Mac has one,
  `SettingsView.swift:47`, but only refreshes its Settings list, see finding under the
  sweep below). So a rename that lands via CloudKit sync **while the note is open** on the
  phone leaves the visible name spans/tiers silently stale for the rest of that viewing
  session — not just "diverges on export," but the live reading experience shows the old
  name.

Proposed clause: **C258** — "A names roster change that lands via sync while a note is open
re-derives that note's visible name spans immediately, not only on next open." Fixture:
device-pair test — rename a person on device A while device B has the mentioning note open;
assert device B's rendered spans update without navigating away.

### #13 — Deleting a person who has voiceprints — UNCOVERED

`NamesStore`'s tombstone constructor (`writeWithSmartBumps`, `NamesStore.swift:88-97`)
builds `Person(canonical:, aliases: prev.aliases, short: prev.short, lastModifiedAt: now,
deleted: true)` — **no `voiceEmbeddings:` argument**, so the local tombstone drops the
voiceprint immediately (defaults to `nil`).

But `NamesMerge.mergeByCanonical` (`NamesData.swift:154-184`) unions `voiceEmbeddings`
**unconditionally**, independent of which side's scalar fields (including `deleted`) won:
`winner.voiceEmbeddings = unionEmbeddings(local?.voiceEmbeddings, remote?.voiceEmbeddings)`.
So: delete "Jack" (with a voiceprint) on device A; device B hasn't synced the delete yet and
still holds "Jack" live with the embedding. Next sync, the merge takes local's newer
tombstone as the scalar winner (correct — Jack is deleted) but the merge STILL unions in the
voiceprint from B's still-live copy and writes it onto the tombstoned `Person`. The
voiceprint the user just tried to delete is silently resurrected onto the deleted record,
and if "Jack" is ever re-added (a new distinct person, or the same one un-deleted), the OLD
voice enrollment reappears attached to it with no indication where it came from.

Proposed clause: **C259** — "A deleted person's voiceprints are dropped, not merged forward:
`mergeByCanonical` must not union `voiceEmbeddings` onto a tombstoned winner." Fixture:
`roster-delete-with-voiceprint` — enroll a voice, delete on device A, sync a stale still-live
copy from device B; assert the merged tombstone carries no embeddings.

### #14 — Adding an alias that is another person's canonical — COVERED

E.g. Person B adds "Jack Hutton" (Person A's exact canonical) as one of THEIR OWN aliases.
`Overrides.init` builds `aliasMap` per-alias across all live people
(`Sanitiser.swift:80-91`); "jack hutton" now maps to both A and B →
`ambiguousAliases.contains("jack hutton")` → every mention becomes the AMBIGUOUS tier
(`suggestedOccurrences` branch (a), `Sanitiser.swift:522-525`) — a pick-one dotted
suggestion, not a silent misattribution. Same machinery as the documented "two-Jacks" case
(C207); traced and confirmed to generalize correctly to this variant.

### #15 — Alias that is a substring of another ("Ann" vs "Anna") — COVERED

`wordRegex`'s `\b…\b` framing (`Sanitiser.swift:751-753`) prevents "Ann" from matching
inside "Anna": there is no boundary between the two adjacent word characters `n`/`a` at that
internal position, so the "Ann" pattern simply never fires inside "Anna". Verified by
reading the regex construction directly, not assumed from `\b` semantics in the abstract.

### #16 — 200 mentions of one name in one note — COVERED

The auto-link pass does ONE `nsReplace` for the first mention, then re-derives
`nonProseRanges`/matches **fresh against the mutated text** for every subsequent step
(`Sanitiser.swift:172-199`) — `NSRegularExpression` re-scans live text on each call, so there
is no static-offset drift as earlier replacements shift later positions. All 199 remaining
mentions correctly demote to the short name via the same live re-match loop
(`Sanitiser.swift:194-199`). No cap, no drift bug found.

### #17 — Name appears only in the polished body, not the raw — PARTLY

By design, the Mac links names against whichever text is "working" —
`pf.enhancedCopyedit ?? pf.transcript` (`MemoCloudUpdate.swift:151`) — so a name the Gemma
polish pass introduces (a corrected mishearing, or worse, a hallucinated name not actually
spoken) gets auto-linked exactly like a spoken one, with **no cross-check against the raw
transcript** to flag "this name wasn't in what was actually said." Given C131's own contract
("cleaned means grammar and punctuation ONLY — his words, his order"), the polish pass
shouldn't be introducing names at all, so this sits at the boundary between an
enhancement-quality issue and a naming-subsystem gap — flagged PARTLY rather than a clean
miss, since the naming code is doing exactly what it's told.

No new clause proposed (this is an enhancement-prompt/guard concern, not a Sanitiser bug) —
noted for cross-reference if `EnhancementService`/`PolishEscrow` audits want it.

### #18 — Person added in the roster on the Mac while the phone is offline — COVERED

Standard CloudKit-carrier eventual-consistency path (`NamesRecord` ↔ `NamesSyncCore.reconcile`,
run on both apps' launch+foreground). No special-casing needed or found; the phone picks it
up on its next reconcile. (The narrower "note open during the sync" staleness is scenario
#12, not this one.)

### #19 — `people:` frontmatter for a conversation — COVERED

`Compiler.peopleLinks` (`Compiler.swift:273-284`) scans ALL `[[ ]]` occurrences in the
rendered body — including conversation turn headers, which use the identical
`[[Canonical]]`/`[[Canonical|spoken]]` syntax as inline links (`Sanitiser.processConversation`,
`Sanitiser.swift:384-402`) — filters to known non-deleted persons, de-dupes
case-insensitively in reading order. A matched speaker who only ever appears in their own
header (never named inline by anyone) still lands in `people:` since headers are `[[ ]]`
links too. Traced end to end, no special-case gap found.

### #20 — Unlinking on the phone, then processing on the Mac — CONTRADICTED

This is R37 by another name: the phone's unlink is stored as
`Memo.nameResolutions.namePicks[alias] = ""` (`Memo+Mobile.swift:144-151`,
`keepNamePlain`), a **phone-only** field. `MemoCloudUpdate.resanitiseAndCompile`
(`MemoCloudUpdate.swift:150-163`) re-links using `pf.namePicks`/`pf.unlinkedNames` — the
Mac's OWN, separate resolution fields — never reading `memo.nameResolutions` at all. The
Mac re-links the just-unlinked name right back. Cited, not re-derived as new (R37/C81).

### #21 — The stoplist for Dutch — is there one, what's in it — COVERED (documented)

Yes: `NameStoplist.commonWords` (`NameStoplist.swift:30-33`) — explicit Dutch section:
`wil, roos, lente, floor, lot, fleur, bloem, guus, storm, loes, mees, duif, vlinder` (13
words), alongside ~35 English ones. `minAutoCommitLength = 3` (line 39) additionally
suggests-not-links any ≤2-char single-token alias regardless of language. No separate
Dutch-specific matching mode exists beyond this shared list — same tiering rules apply to
both languages uniformly.

### #22 — A name that is also a tag — UNCOVERED

`nonProseRanges` has no awareness of inline `#tag` tokens. `wordRegex`'s `\bAlias\b`
framing treats `#` as a non-word character, so it produces a boundary match: in `#Jack loves
this`, `\bJack\b` matches "Jack" immediately after the `#`. If "Jack" is a live, distinctive
(non-FP-prone) alias, the auto-link pass replaces it in place:
`#Jack` → `#[[Jack]]` — corrupting the tag into invalid Obsidian syntax (the tag no longer
parses as `#Jack`; the text now reads as a stray `#` followed by a wiki-link). No test or
guard for this was found; `TagComplete.swift`/`VaultTagScanner.swift` operate on tag
completion/vault-wide tag scanning, not on protecting tag spans from the name-linker.

Proposed clause: **C260** — "An inline `#tag` token is never split by name-linking, even
when it matches a roster alias exactly." Fixture: `edge-name-is-tag` — "#Jack needs
follow-up" with "Jack" a distinctive live alias; expect the tag left intact and the alias
NOT auto-linked inside it (matches the memo-link-title precedent, C82).

### #23 — A name that is also a place — N/A

There is no in-body place-linking feature to collide with: `PlaceLink.swift`
(`SkriftMobile/Services/Capture/PlaceLink.swift`) only parses shared Apple/Google Maps URLs
into location METADATA (a chip on the memo, lat/long) — it never writes a `[[Place]]` wiki
link into the transcript body. A place name that happens to match a person's alias in prose
text is therefore handled by the ordinary name-linker with no competing mechanism to
conflict with. Genuinely not applicable, not merely untested.

### #24 — Person with an empty canonical or `[[ ]]` only — COVERED

`PersonEditCore.materialise` guards on `plainName.isEmpty` after stripping brackets
(`PersonEditCore.swift:48-50`) — a literal `[[ ]]` (brackets around only whitespace)
normalises, then `keyName` strips the brackets leaving a single space, which trims to empty
→ `guard` fails → `nil`, no person created. Traced through `NamesMerge.normaliseCanonical`
+ `keyName` by hand for this exact input; refused correctly. `NamesStore.upsert(canonical:…)`
(the simpler mobile path) has the same guard (`NamesStore.swift:135`).

### #25 — Two devices adding the same person at once — CONTRADICTED

Compounds #1: since the app can't represent two distinct people sharing a canonical at all,
two devices independently adding "John Smith" as two DIFFERENT real people converge, on
sync, to ONE `Person` via `NamesMerge.mergeByCanonical`'s LWW (`NamesData.swift:154-184`) —
and LWW here is **wholesale**, not per-field: the loser's entire aliases/short list is
discarded outright (only `voiceEmbeddings` are unioned). So device A's "John Smith" with
aliases `[Johnny]` and device B's DIFFERENT "John Smith" with aliases `[JJ]` sync down to
one person with only ONE of the two alias lists (whichever has the newer timestamp) plus a
merged voiceprint set spanning both real people's voices. No conflict is ever surfaced to
either user (contrast D24's now-decided "offline conflict is NOT silent" policy for note
edits — no equivalent exists for the names roster).

No separate clause proposed beyond C254 (#1) — this is that same root cause reached via the
sync path instead of a single-device double-add; the fix for C254 (distinct storage keys /
disambiguation) resolves this too. Fixture: `roster-concurrent-duplicate-add` — two device
snapshots each adding a distinct "John Smith" with different aliases + one voiceprint each;
merge; assert two people survive, not one.

---

## 3. Bug-shape sweep (Names subsystem only)

Read `plan/bug-shapes.md`'s ten shape definitions; applied fresh against the files in scope
above (not reusing that doc's own findings, which covered different files).

| Shape | Hits checked | Verdict |
|---|---|---|
| 1. Silent empty result | `NamesStore.load()`, `.save()` | **CANDIDATE** (below) |
| 2. Two lists, nobody in the gap | `NameResolutions.unlinkedNames` vs `.namePicks` | SAFE — `unlinkedNames` is documented dead/reserved ("today's gestures use per-alias `namePicks`"), not a live second predicate to drift from the first. |
| 3. Echo guard refuses the only copy | — | N/A — no device-echo guard pattern in Naming. |
| 4. Only the first one | `PersonEditorView.loadOnce`, `NamesStore.upsert(canonical:)` `.firstIndex` | SAFE individually — see shape 7 for the real defect this exposes. |
| 5. Waiting thing → different thing | `PersonEditCore.isEnrolled` (nil person vs 0 embeddings) | SAFE — a nil person genuinely has no enrollment; not a miscategorized wait state. |
| 6. One-way paths | `NameResolutions` (phone) → `PipelineFile.namePicks` (Mac) | Confirms R37 (already known) — not re-filed. |
| 7. Twin copies | `NamesStore.upsert(canonical:aliases:short:)` vs `.upsert(_:replacing:)`; three "add person" UI flows | **CANDIDATE** (below) |
| 8. Fallback returns wrong input | — | N/A — no LLM/truncation fallback in Naming. |
| 9. Unpinned dependency | — | N/A. |
| 10. State that only moves on a path that doesn't always run | `MemoDetailView.people`; `RosterAudit`/`rescanRoster` wiring | **CANDIDATE** (below) — two separate instances |

### CANDIDATE — shape 1: `NamesStore.save()` writes non-atomically; a torn read silently reads as zero people

```swift
// NamesStore.swift:44-53
func save(_ data: NamesData) -> NamesData {
    let out = NamesData(...)
    if let encoded = try? encoder.encode(out) {
        try? encoded.write(to: fileURL)     // no .atomic — a crash/kill mid-write torns the file
    }
    return out
}

// NamesStore.swift:28-34
func load() -> NamesData {
    guard let data = try? Data(contentsOf: fileURL),
          let parsed = try? decoder.decode(NamesData.self, from: data) else {
        return NamesData(lastModifiedAt: ISO8601.now(), people: [])   // ANY decode failure → empty
    }
    return parsed
}
```
This is a pre-registered SPEC row (**R8**/**C50**: "`names.json` non-atomic; torn read →
empty roster") from an earlier (pre-rewrite) sweep, but it was written against the retired
Python backend. Reading the CURRENT native Swift port confirms the same defect is present,
unfixed, in `Shared/Naming/NamesStore.swift` today: `write(to:)` has no `.atomic` option, and
`load()`'s failure path returns a fully empty roster indistinguishable from "no one's been
added yet" — no error surfaced, no log, and (per `NamesData.swift:99-103`'s own comment) this
exact silent-zero-roster failure mode was already the reason the *lastModifiedAt-missing*
legacy case got a tolerant decode — but a **fully malformed** file (a genuine torn write, not
just an old schema) still falls straight through to the empty-roster fallback.
- **What the user does:** nothing wrong — the app is killed (OS memory pressure, force-quit,
  crash) mid-write to `names.json`, or the file syncs through a corrupting intermediary.
- **What they get:** the ENTIRE roster reads as empty on next load — no names auto-link
  anywhere, silently, until the next write happens to repopulate it (and a `writeWithSmartBumps`
  call from an empty base could itself then tombstone-delete every real person, since
  "previously-live canonical not in the incoming set → tombstone").
- **What they should get:** an atomic write (`Data.write(to:options:.atomic)`) so a kill
  mid-write can't produce a torn file, and a decode failure on a non-empty file logged as an
  error rather than silently treated as "zero people."
- **Fix location:** `Shared/Naming/NamesStore.swift:28-53`.
- **SPEC clause:** already exists — R8/C50; this confirms it is unresolved in the rewritten
  Swift code, worth re-flagging in `backlog.md` since a prior sweep may have assumed the
  rewrite fixed it by construction.

### CANDIDATE — shape 7: two "add/edit person" upsert paths disagree on collision case-sensitivity, and a third bypasses alias-seeding entirely

Three call sites end up creating a `Person`, with three different behaviors:

| Call site | Collision check | Empty-alias handling |
|---|---|---|
| `NamesStore.upsert(canonical:aliases:short:)` (`NamesStore.swift:133-150`) — used by mobile `NamesListView.AddPersonView` (`NamesListView.swift:202`) | `$0.canonical == c` — **exact, case-sensitive** string equality (canonical is bracket-wrapped but never case-normalised) | Always passes `aliases: []` from the caller — **never** seeds a default alias; a same-name-different-case entry doesn't even collide, it silently duplicates |
| `NamesStore.upsert(_:replacing:)` (`NamesStore.swift:157-179`) — used by `PersonEditorView` (phone), `PersonEditor`/Settings + `NoteDisplayView` (Mac), via `PersonEditCore.materialise` | `key($0.canonical) == key(newKey)` — **trimmed, lower-cased** | `PersonEditCore.materialise` defaults empty aliases to `[plainName]` (`PersonEditCore.swift:56`) — never leaves a person truly alias-less from this path |

So the SAME logical action — "add a person by full name" — has a case-sensitive
duplicate-vs-merge decision on the simple mobile flow and a case-insensitive one everywhere
else, AND only the simple mobile flow can mint a genuinely alias-less person (reinforcing
R12's failure mode from a second, distinct code path: `NamesListView.swift:202` rather than
whatever site R12 was originally filed against).
- **What the user does:** on the phone, uses the quick "Add Person" screen (name + short
  name only, footer says "Aliases … managed on your Mac") to add "jack hutton" when "Jack
  Hutton" already exists.
- **What they get:** a second, alias-less, duplicate roster entry (`[[jack hutton]]` next to
  `[[Jack Hutton]]`) instead of either merging (like the fuller editor would) or refusing —
  and because it has no aliases, it never auto-links, so it just sits in Names & Voices as
  a dead, confusing duplicate.
- **What they should get:** ONE collision rule (case-insensitive, trimmed) used by every
  "add a person" call site, and no path that produces `aliases: []` without going through
  `PersonEditCore`'s default-alias rule.
- **Fix location:** `Shared/Naming/NamesStore.swift:133-150` (align with the
  case-insensitive key used at line 159), and route `NamesListView.AddPersonView.save()`
  (`NamesListView.swift:202`) through `PersonEditCore.materialise` instead of calling
  `upsert(canonical:aliases:short:)` directly with a hardcoded `[]`.
- **SPEC clause:** C83 (alias seeding) + the new C254 (duplicate-canonical handling, #1
  above) — this is the concrete mechanism that makes #1's case-insensitive path
  inconsistent with itself.

### CANDIDATE — shape 10: the roster-collision safety net doesn't run on the paths most likely to trigger it

`RosterAudit` exists specifically to catch "the day a SECOND same-name person is added"
(`RosterAudit.swift:3-9`, the NAMING_MODEL.md NON-NEGOTIABLE build-guard) and IS wired up —
but only from ONE of three places a collision can be introduced:

```swift
// NoteDisplayView.swift:426-430 — the in-note "A new person…" flow
private func savePerson(_ original: String?, _ person: Person, for file: PipelineFile) {
    let before = NamesStore.shared.livePeople()
    NamesStore.shared.upsert(person, replacing: original)
    coordinator.resanitiseForNames(file, context: ctx)
    coordinator.rescanRoster(previousPeople: before, context: ctx)   // ← the ONLY call site
}
```

`SettingsView.swift`'s `PersonEditor.onSave` (Settings → Names → Add/Edit, the OTHER Mac
entry point, line 50-53) calls `NamesStore.shared.upsert(...)` directly and does **not**
call `rescanRoster` — adding a colliding person from Settings never triggers the re-scan.

More importantly: `NamesCloudSync.swift:54` posts `.namesDidChangeFromSync` whenever a
**remote** roster merge changes the local roster (i.e. exactly when a collision introduced
by ANOTHER DEVICE — the phone, an iPad — first becomes visible on this Mac). The only
subscriber, `SettingsView.swift:47`, just calls `reloadNames()` to refresh the visible list
— it never calls `rescanRoster`. So the single most realistic way a same-name collision
actually happens in practice — two people added independently on two devices, syncing
together, exactly scenario #25 above — is the one path the NAMING_MODEL.md build-guard was
never connected to. Every memo that had auto-linked the now-ambiguous alias keeps resolving
to whichever person happened to win it first, forever, with no "N notes now share a name"
flash and no re-derive.
- **What the user does:** nothing wrong on the Mac itself — the phone (or another device)
  adds a person whose alias collides with an existing Mac-known person, and it syncs in.
- **What they get:** every previously-processed memo that had auto-linked that alias keeps
  the OLD, now-ambiguous link, silently possibly-wrong, with zero signal anything changed.
- **What they should get:** the same re-scan + "N notes now share a name" flash that the
  in-note add flow gets, driven off `.namesDidChangeFromSync` (and wired into the Settings
  add/edit flow too).
- **Fix location:** `SkriftDesktop/Features/Settings/SettingsView.swift:47` (subscriber) and
  `:50-53` (onSave) — both need `coordinator.rescanRoster(previousPeople:context:)`.
- **SPEC clause:** C207 ("A roster collision re-derives every processed memo that
  auto-linked the name") — currently true only for one of three entry points; propose
  **C207 (tightened)**: "…re-derives every processed memo … regardless of whether the
  colliding person was added locally or arrived via sync."

---

## Summary — the 8 most load-bearing findings

1. Two people can never share a full name — adding a second "John Smith" silently **fuses**
   into the first, unioning aliases and voiceprints (`NamesStore.swift:157-179`,
   `NamesData.swift:154-184`). New clause **C254**.
2. The Mac's roster-collision safety net (`RosterAudit`/`rescanRoster`) is wired to only ONE
   of three add-person paths — it never fires for a collision introduced via Settings or via
   CloudKit sync from another device, which is the realistic case (`SettingsView.swift:47,
   50-53`; `NamesCloudSync.swift:54`).
3. Deleting a person with a voiceprint doesn't reliably delete the voiceprint: the local
   tombstone drops it, but the next sync's unconditional `unionEmbeddings` can resurrect it
   from a stale remote copy onto the tombstoned record (`NamesStore.swift:88-97`,
   `NamesData.swift:180`). New clause **C259**.
4. Name matching has no diacritic-insensitive mode — "Ines"/"Inés" and similar never match
   each other (`Sanitiser.swift:748-756`). New clause **C256**.
5. Only the LEADING quote block is protected from name-linking; a mid-body `> ` quote is
   scanned like ordinary prose, contradicting the freshly-decided D21 ("any quote block")
   (`Sanitiser.swift:713-716`).
6. An inline `#tag` that matches a roster alias gets split by the linker into `#[[Name]]`,
   corrupting the tag (`Sanitiser.swift:751-756`, no tag-span guard anywhere). New clause
   **C260**.
7. Naming a not-on-roster speaker (assign sheet) silently mints an alias-less `Person` with
   a voiceprint and no editor shown — a second, silent instance of R12's failure shape
   (`MemoDetailView.swift:1671-1690` → `NamesStore.swift:113-128`).
8. `NamesStore.save()` still writes non-atomically and `load()` still treats any decode
   failure as "zero people" in the rewritten Swift code — R8/C50 is pre-registered but
   unresolved in the native port (`NamesStore.swift:28-53`).

Two duplicate-canonical scenarios (#1, #25) and the case-sensitivity split between the two
`upsert` overloads share one root cause and one fix (distinct, non-string-keyed identity for
a `Person`, or a mandatory disambiguation prompt) — fixing C254 closes three findings at
once.
