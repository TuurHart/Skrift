# SPEC.md self-consistency audit — 2026-09-22

Read of SPEC.md at 1,509 lines (253 clauses C1–C253, 60 R rows, 95 decisions D1–D95).
Every row carries SPEC.md line numbers **as of commit 9e8867a1**.

> **APPLIED 2026-09-22 (uncommitted).** §A, §C.1, §D and §F were written into SPEC.md on top of
> `ab6714c4`, under the coordinator's ten rulings. **Line numbers below are therefore stale — match
> by clause text.** Still OPEN: §B rows not covered by a ruling, §C.2 (three `required difference`
> marks with no R row: C74, C126, C62), §C.3 (ten R rows whose clause is silent), §E (readiness),
> and the two ⚠ needs-Tuur marks now in SPEC.md on C137 and C165.

Status of the decision list, established first because everything in A and C depends on it:
**D1–D36 and D38–D89 all carry ✅ DECIDED or ✅ BUILDER DEFAULT.** Only **D37** (L1240),
**D90** (L1345), **D91** (L1352), **D92** (L1356), **D93** (L1360), **D94** (L1362) and
**D95** (L1365) are still open. So any `⚠ needs-verdict Dn` naming an n outside {37, 90–95}
is stale by construction.

---

## A) CLAUSE vs DECISION — clause text still states the old default (24)

| # | clause (line) | decision (line) | clause says | decision says | corrected clause text |
|---|---|---|---|---|---|
| A1 | C12 L105-107 | D2 L1158, **D69 L1306** | "a lone shared picture, **a video frame**, or a picture with nothing around it goes to the TOP" | D69: in a bundle the video's frame is "a picture paragraph **at that spot**" in selection order | "…a picture inserted in the editor lands at the caret; a VIDEO's frame is a picture paragraph at the video's own place in that sequence (D69); a **lone** shared picture, a **lone** video's frame, or a picture with nothing around it goes to the TOP of the note." |
| A2 | C63 L284-287 | D44 L1258 | "the ARCHIVE export copies the **Mac-kept** source movie **when the Mac exports** … the phone discards the movie" | the movie is a **synced asset** for Made/Idea/Inspiration (cap ~200 MB); only Personal videos discard it | "No video goes to the Obsidian vault: a video note exports markdown + audio + the frame there. A Made/Idea/Inspiration video keeps its source movie as a SYNCED asset (cap ~200 MB, D44), so the archive export copies it from whichever device exports; a Personal video discards the movie." |
| A3 | C71 L318-321 | D44 L1258 | "original discarded on the phone (kept as `source.<ext>` on the Mac, **never synced**)" | synced for archive destinations | "…original kept as a synced `source.<ext>` asset when the destination is Made/Idea/Inspiration (D44), discarded on the phone for Personal…" |
| A4 | C94 L411-412 | D30 L1224 | "Importance control: **10 circles today**; i23 proposes 3 (or 4) buttons — mock first. ⚠ needs-verdict D30" | three balls 0.3 / 0.6 / 1.0, old values still bucket, **no fourth button**; mock first | "[tuur] Importance control = three balls (0.3 / 0.6 / 1.0, D30); existing 0.1–1.0 values bucket into them; no fourth button. Mock first." |
| A5 | C210 L961-963 | D30 L1224, D52 L1275 | "The rating grid: **10 stops** 0.1…1.0 … **refine wall ≥ 0.8**" | three balls; the refine pass is **DROPPED** ("let's remove that friction") | "The rating scale: three stops 0.3 / 0.6 / 1.0 (Passing / Useful / Important); legacy 0.1–1.0 values bucket to the nearest stop; tap the Nth → its value, re-tap → Not rated; no refine wall; user-facing word 'Importance'; ties broken by date." |
| A6 | C183 L855-856 | D52 L1275 | "The refine pass at ≥ 0.8: **keep or drop in v2** — decides D30's fourth button. ⚠ needs-verdict D52" | dropped; "the spec's earlier description was wrong" | delete C183, or: "[tuur] The refine pass is removed (D52); there is no fourth importance button." |
| A7 | C114 L489-490 | D28 L1220 | "What the app opens into (last note / the list / a new note) — **his call**. ⚠ needs-verdict D28" | opens into **the list**, new-note one tap away | "[tuur] The app opens into the list, with the New Note action one tap away (C112, D28)." |
| A8 | C56 L255-260 | D12 L1183 | frontmatter key list has **no `duration`, no created date**; "⚠ needs-verdict D12 on the 'to add' keys" | **add** `duration` and the created date; skip lat/lon and the reminder | add `duration` and `created` to the key list; drop the ⚠; keep "no coordinates, no reminder" as an explicit exclusion; and (R50 L1126) "tags are quoted like `summary:`". |
| A9 | C64 L288-290 | D13 L1185 | "`date:` is computed the same way on every device (ONE timezone rule). ⚠ needs-verdict D13" | **the recording's local day** everywhere | "`date:` = the recording's LOCAL day on every device (D13); one rule, no device-local reinterpretation." |
| A10 | C130 L562 | **D39 revised** L1247, C132 L578 | keys Skrift may write: "`title` (**only when HE gave one**)" | a generated title is as good as a typed one | "`title` (typed or generated, D39)" |
| A11 | C53 L245-248 | D11 L1180, C192 L886-889 | "the picked folder IS the destination … **no forced subfolders**" | keep `VaultLayout.home` as coded: `<pick>/Skrift` is created when the pick is not/does not hold one; **fixed media subfolders** | "The picked folder IS the destination, resolved by `VaultLayout.home` (C192, D11): a pick named Skrift, holding a stamped `.md`, or containing a `Skrift/` is used as-is, otherwise `<pick>/Skrift` is created on first write; media subfolders `Recordings/ Images/ Documents/` are fixed; the archive root is returned unchanged. Identity lives in the file stamp, never in a remembered path." |
| A12 | "Not doing" L1396-1397 | D11 L1180 | "**no `Skrift/` prefix forced in the vault**" | `<pick>/Skrift` **is** created on first write | strike that phrase from "Not doing"; it is now false. |
| A13 | C81 L361-365 | D20 L1200 | "⚠ needs-verdict D20 (**today the Mac ignores the phone's picks**)" | "name sync everywhere" — per-note picks honoured on every device | "…the phone's per-note picks sync and are honoured on every device (D20); the export from either device carries the same links." |
| A14 | C93 L406-410 | D23 L1205 | "⚠ needs-verdict D23 on case-variant duplicates" — no fold rule in the text | **fold to the first spelling** | add "case-variant duplicates fold to the first spelling (D23)"; drop the ⚠; cross-reference C241 for the UI revamp. |
| A15 | C72 L322-327 | D14 L1186, D15 L1189 | "⚠ needs-verdict D14/D15 on YouTube / Instagram" — outcomes absent | YouTube = **card only**, no audio scraping; Instagram/TikTok = **card + caption as body** when the page gives one, never a login-walled fetch | add: "a YouTube link is a card only (D14); an Instagram/TikTok link is a card plus the caption as body when the page gives one, never a login-walled fetch (D15)." |
| A16 | C124 L531-534 | D35 L1237 | "⚠ needs-verdict D35 (show the per-message time in the body or not)" | **hidden**, kept in the manifest | "…each clip's own time is kept in the manifest and NOT shown in the body (D35)." |
| A17 | C120 L511-513 | D29 L1222 | "⚠ needs-verdict D29 on stating them" | "yes, say so for sure" | "…both **stated in-app and in the README** (D29)." |
| A18 | C138 L598-600 | D40 L1251 | "The reverse direction … **is undecided** (i43, i14). ⚠ needs-verdict D40" | **not in v2**; the archive reads Skrift's files, never the reverse | "[tuur] Ideas do not come back into Skrift in v2; the archive reads Skrift's files, never the reverse (D40). Attaching a capture to an existing archive item is out of scope." |
| A19 | C203 L931-932 | D4 L1162 | "Legacy shapes that do NOT migrate under D4 … **Confirm the list**." | D4 already names exactly this list | drop "Confirm the list"; the clause is settled. |
| A20 | C208 L950-953 | **D60** L1290 | "⚠ needs-verdict **D-B12** (tie rule)" | D60: deterministic by device id, ±5 s skew tolerance | "…tie broken deterministically by device id; write-back LWW tolerates ±5 s skew (D60)." (D-B12 is not a SPEC decision id — see D4 below.) |
| A21 | C182 L851-854 | D-rating (C87 L379, C88 L384), R17 L1094 | "the queue = live ∧ not done ∧ **not an unrated Mac take**" — admits every other unrated note | an unrated note is never processed, on any device | "…the queue = live ∧ rated ∧ not done, oldest first, one at a time…" |
| A22 | C215 L975-976 | D10 L1174 | "`ProcessPile.waiting` = rated ∧ live ∧ **unlocked** ∧ real transcript ∧ not processed" | a locked note **IS** processed; lock is about eyes, not the pipeline | "`ProcessPile.waiting` = rated ∧ live ∧ real transcript ∧ not processed (lock does not gate processing, D10); `canSummon` = rated ∧ !locked." |
| A23 | C179 L842-843 | D95 L1365 (open, default yes), R52 L1128 | "Redo … rewrites one part in place" — no guard | Redo over a hand-edited part **asks first** | "…Redo asks before overwriting a part he edited by hand, never silently (D95/R52)." (D95 still needs Tuur's ✅.) |
| A24 | C46 L222-224 | D60 L1290, D93 L1360, R44 L1120 | "LWW by `enhancedAt`" — no skew rule | stamp-to-stamp with tolerance, never against the local clock | "…LWW by `enhancedAt`, stamp compared to stamp with ±5 s tolerance, never to this device's clock (D60/D93)." |

**Decisions with no clause at all** (they cannot reach `/2-plan`):

| decision (line) | what it decided | where a clause is needed |
|---|---|---|
| **D77** L1319 | the phone's "People in this note" **chip bar is REMOVED**; names clickable in the text, one model on both apps | no clause in SPEC.md says it. Add to C80 (L354) or C181 (L847). No clause claims the chip bar survives, so this is a hole, not a contradiction. |
| D85 L1333 | retire the XCUITest suite; the unit suite is the gate | Gate section L43-47 and C6/C9 never mention it |
| D91 L1352 | an untouched empty typed note is discarded on leave | C43 L212 (kinds) is the natural home |
| D93 L1360 | clock-skew rule / a future `recordedAt` is flagged | C46, C89 (R44/R45 cite them but neither states it) |
| D95 L1365 | Redo asks before overwriting a hand edit | C179 (see A23) |

---

## B) CLAUSE vs CLAUSE — two clauses that disagree (27)

Ordered most consequential first.

| # | clauses (lines) | the disagreement | resolution |
|---|---|---|---|
| B1 | **C41 L205-207** vs **C88 L384-386** vs **C187 L866-868** | C41: "**no unrated** … memo has [a Mac row]". C187: "An unrated note has **NO row**." C88: "un-rating **keeps the ROW** but drops it from the process queue." This is the invariant `gate.sh` proves (L45-46) and a C6 invariant (L79-80). | C88 wins (it is the decided one-way door). C41 → "every rated live memo has exactly one row; a memo un-rated after it had a row KEEPS the row, out of queue and export; a never-rated or trashed memo has none." C187 → "a never-rated note has no row." |
| B2 | **C34 L179-182** vs **C20 L131-135** / D7 L1168 | C34 breaks "a wall (>600 chars, <2 breaks, >4 sentences)" deterministically and names **`typed-wall-7k`** as the check. C20/D7: "typed text is **never** paragraphed by any rule … the copy-edit fallback skips typed notes." R14 L1091 and R27 L1104 both pin `typed-wall-7k` under C34. | C34 must say "a wall of SPOKEN text"; `typed-wall-7k` moves to "unchanged" in C34, R14 and R27. |
| B3 | **C193 L893-895** vs C156 L660-662, C158 L666-668, C161 L681-683, C163 L687-691 | C193: "**Skrift never deletes a vault file**." C158: a removed picture "is removed from the vault on the next export". C163: re-filing "removes the old file when ours and untouched". C156/C161: Delete Now / locking "offers to remove the file". | C193 → "Skrift deletes a vault file only through the four named verbs (re-file C163, picture removal C158, Delete Now C156, lock C161), and only when the file is provably ours and untouched." |
| B4 | **C193 L895** vs **C161 L682-683** | C193: locking an exported note "shows **'already in your vault'**". C161: locking "says the plaintext file still exists and **offers to remove it** when ours and untouched". | C161 wins (it is the newer scenario-probe clause). Strike the C193 sentence. |
| B5 | **C136 L594-595** vs C63 L284-287, C148 L629-630, D44 L1258 | C136: the archive export "carries the ORIGINAL audio beside the note and **never a video file**". D44/C148: the movie **is** the archive asset for Made/Idea/Inspiration. | C136 → "…carries the ORIGINAL audio beside the note, and the source movie when the note is a video filed Made/Idea/Inspiration (D44); never a video in the Obsidian vault (C63)." |
| B6 | **C137 L596-597** vs **C62 L279-280** and **C130 L563** | C137: "`people:` and `[[names]]` stay in archive exports; **places do not**." C62: "the archive keeps `[[names]]` **and `location:`**, plainifies place LINKS." C130 lists `location` among the keys Skrift may write. | Unresolved by any Dn — **needs Tuur**. C62+C130 are the newer pair and the archive README allows `location`; C137's "places do not" reads as a leftover from the place-LINK rule. Proposed: keep `location:` as a plain value, never a `[[place]]` link; amend C137. |
| B7 | **C62 L280-281** vs **C130 L564** / R51 L1127 | C62's archive drop-list: "weather, significance, `author`, `type`, `source`" — **`summary` is missing**. C130: "Skrift **never** writes … `summary`"; R51/C252 L783 pin the `summary:` removal. | add `summary` to C62's drop list. |
| B8 | **C53 L246** vs **C192 L886-888** | "no forced subfolders" vs "`<pick>/Skrift` is created on first write; media subfolders … are fixed". | see A11. |
| B9 | **C198 L912-913** vs **C67 L299-302** / **C68 L304-308** | C198: "Share dispatch order: audio → web URL → movie → image(s) → plain text → document; **first match wins**." C67: "Attachments from **ALL** extension items AND all providers of an item enter the dispatcher." C68/D69: a mixed bundle becomes ONE note **in selection order**. | C198 → "the dispatch order classifies **each item/provider** (C67); first match wins **per item**; the note is assembled in selection order (C68)." |
| B10 | **C198 L914** vs **C123 L526-529** / **C145 L620-621** | C198: "a share carries **rating + annotation only** (no title, no tags, destination Personal)". C123: the share sheet carries an optional **sender name** field. C145: "the same slim sheet (**rating + sender**)". | C198 → "rating + annotation + optional sender (C123); no title, no tags, destination Personal." |
| B11 | **C202 L928-929** vs **C144 L617-619** / **C198 L915-916** | C202: "Captures get **no location** or weather." C144: "a Maps link is a link capture **with the place as location** and title". C198: "a Maps link → **location** + place chip". | C202 → "Captures get no **sensed** location or weather; a location carried by the shared content itself (a Maps link, C144) is kept." |
| B12 | **C12 L105-107** vs **C71 L319** / C68 L306-308 | C12: a video frame goes to the TOP. C71: "one frame as **the first picture** (C12)". C68/D69: at the video's place in the bundle. | see A1; C71 → "one frame as a picture paragraph at the video's place in the note (C12/C68), which is the top for a lone video." |
| B13 | **C25 L150-151** vs **C165 L792-794** | C25: derived titles clip at 80 chars "for DISPLAY only (the vault filename keeps its own rule, C165)". C165 says both "**cap 120**" and "the exporter's hard **80-char** slice stays because it feeds the filename" — internally contradictory, and it contradicts C25's "display only". | C165 → state ONE number for the filename stem (the 80-char slice, if that is what feeds it) and delete whichever of 120/80 is dead. Needs a one-line verdict. |
| B14 | **C159 L671-675** vs **C207 L945-949** / **D79 L1322** | C159: a roster change (add, alias, rename) "**re-exports** the untouched vault files we own". D79/C207: after a roster collision, **no re-export**; "the next content change re-exports; log the count". | Distinguish: a **rename** rewrites and re-exports (C159/R21); a **collision** only re-derives in-app (C207/D79). Say so in both clauses. |
| B15 | **C98 L425-427** vs **C242 L718-720** | C98: "he **picks the version to keep**, the other stays recoverable". C242: keep this device's, the other's, "**or both as two notes**". | C98 → "…he picks this device's version, the other's, or both as two notes (C242); the version not kept stays recoverable." |
| B16 | **C19 L127-130** vs **C18 L123-125** / C6 L77 | C19 normalises whitespace ("≥3 line breaks → one blank line") **at write**; C18 requires "reconstruct is **byte-exact**" and C6 requires "editor round-trip returns the **identical string**". | C19 → "…applied at **commit**, once, before the body is stored; the editor's in-session round-trip is exempt so C18/C6 hold." |
| B17 | **C215 L975** vs **C91 L401-403** / **C161 L681** / D10 | "waiting = … ∧ **unlocked**" vs "a locked note keeps processing". | see A22. |
| B18 | **C182 L852** vs **C215 L975** | Two different process-queue predicates: C182 "live ∧ not done ∧ not an unrated Mac take"; C215 "rated ∧ live ∧ unlocked ∧ real transcript ∧ not processed". | ONE predicate, per C115's own single-source rule. Fix both per A21/A22. |
| B19 | **C56 L255-260** vs **C129/C130 L556-568** | C56 is "the" compiler frontmatter clause and writes `date:`, `summary:`, `author`, `source`, `significance`, `weather…`; C130 forbids most of those on the archive profile and expects `added:`. C56's only nod is a bracketed "[archive: voice, needs]". | C56 → split explicitly: "vault profile = <list>; archive profile = the C130 key list only, with `added:` in place of `date:` (D94)." |
| B20 | **C195 L901-903** vs **C136 L594-595** / C61 L271-273 | C195: include-audio is a per-note switch, default on, "**Mac-only** and does not sync". C136: the archive export **carries** the original audio (unconditional). C61: **the iPad** also exports. | C195 → "…the switch is Mac-only and does not sync; an archive-bound export always carries the audio (C136), switch or not; the iPad follows the same default." |
| B21 | **C61 L271-275** vs **C197 L907-909** | C197 records the 2026-07-18 full-exportability doctrine as "superseded in part by C61 … **Confirm the narrowing**" — never confirmed by any Dn. | open [tuur] question. Either confirm (C61 wins, delete C197) or raise it as D96. |
| B22 | **C59 L266-267** vs **R49 L1125** | C59: "the raw syntax never reaches the vault" — about **memo-links only**. R49 requires a hand-typed `[[word]]` that is not a link to be escaped. No clause states it. | C59 → add "a hand-typed `[[word]]` that resolves to nothing is escaped to plain text, never exported as Obsidian syntax (R49)." |
| B23 | **C45 L219-221** vs **R57 L1133** | C45: "unchanged rows are skipped"; R57 requires **content-hash** staleness because byte-count misses same-length changes, and diarization re-adoption on change. C45 says neither. | C45 → add "staleness is a content hash, never a byte count; diarization is re-adopted whenever it changes (R57)." |
| B24 | **R10 L1087** vs **L1138** | R10 sits in the "Required differences (v2 matching v1 here **FAILS**)" table *and* in the "Pre-registered as IDENTICAL" sentence at L1138. Under C5 (L70-73) a row can be one or the other, never both. | delete the R10 row; it is already covered by the IDENTICAL sentence. |
| B25 | table intro **L1073-1074** vs rows R42, R47, R48, R54, R58, R59, R60 (L1118–L1136) | The intro says the table lists "**the ones inside the four rewrite targets**". R42/R59 are audiobook sync, R47 iCloud account, R48 reminders, R54 iPad settings copy, R58 Connections, R60 the speaker-turn view — none inside C10–C65. | reword the intro, or split the table into "inside the targets" and "outside, fixed in v1" (an "Outside the targets" paragraph already exists at L1140-1142). |
| B26 | **C230 L1043** | "the vault is NEVER indexed in **v1**" — in this document "v1" means the old codebase everywhere else (C1, C2, C5). | say "never indexed at all in this spec's scope"; "v1" here reads as the retired code. |
| B27 | **C4 L65** vs **Gate L46** | C4: the corpus is "**109 notes**" (109 directories on disk, verified). Gate: "…the rate→row invariant over all **106 notes**". | make the gate line say 109. |

---

## C) STALE MARKS (44)

### C.1 `⚠ needs-verdict Dn` where Dn is now ✅ DECIDED — clear in one pass (30)

| clause | line | mark | decision (line) | clause text also wrong? |
|---|---|---|---|---|
| C10 | L96 | ⚠ needs-verdict D1 | D1 ✅ L1157 | no — text already correct |
| C12 | L107 | ⚠ needs-verdict D2 | D2 ✅ L1158 | **yes** (A1) |
| C25 | L153 | ⚠ needs-verdict D6 | D6 ✅ L1166 | no |
| C35 | L185 | ⚠ needs-verdict D8 | D8 ✅ L1171 | no |
| C39 | L199 | ⚠ needs-verdict D9 | D9 ✅ L1173 | no |
| C56 | L260 | ⚠ needs-verdict D12 | D12 ✅ L1183 | **yes** (A8) |
| C64 | L289 | ⚠ needs-verdict D13 | D13 ✅ L1185 | **yes** (A9) |
| C69 | L311 | ⚠ needs-verdict D16 | D16 ✅ L1191 | no |
| C72 | L326 | ⚠ needs-verdict D14/D15; D42 | D14 ✅ L1186, D15 ✅ L1189, D42 ✅ L1256 | **yes** (A15) |
| C73 | L331 | ⚠ needs-verdict D22 | D22 ✅ L1204 | no |
| C81 | L364 | ⚠ needs-verdict D20 | D20 ✅ L1200 | **yes** (A13) |
| C82 | L367 | ⚠ needs-verdict D21 | D21 ✅ L1202 | no |
| C93 | L410 | ⚠ needs-verdict D23 | D23 ✅ L1205 | **yes** (A14) |
| C94 | L412 | ⚠ needs-verdict D30 | D30 ✅ L1224 | **yes** (A4) |
| C114 | L490 | ⚠ needs-verdict D28 | D28 ✅ L1220 | **yes** (A7) |
| C120 | L513 | ⚠ needs-verdict D29 | D29 ✅ L1222 | **yes** (A17) |
| C124 | L534 | ⚠ needs-verdict D35 | D35 ✅ L1237 | **yes** (A16) |
| C127 | L542 | ⚠ needs-verdict D36 | D36 ✅ L1239 | no |
| C138 | L600 | ⚠ needs-verdict D40 | D40 ✅ L1251 | **yes** (A18) |
| C142 | L614 | ⚠ needs-verdict D43 | D43 ✅ L1257 | no |
| C148 | L630 | ⚠ needs-verdict D44 | D44 ✅ L1258 | no |
| C151 | L643 | ⚠ needs-verdict D46 | D46 ✅ L1263 | no |
| C154 | L655 | ⚠ needs-verdict D47 | D47 ✅ L1265 | no |
| C155 | L658 | ⚠ needs-verdict D48 | D48 ✅ L1266 | no |
| C156 | L661 | ⚠ needs-verdict D49 | D49 ✅ L1267 | no |
| C160 | L680 | ⚠ needs-verdict D50 | D50 ✅ L1269 | no |
| C162 | L686 | ⚠ needs-verdict D51 | D51 ✅ L1271 | no |
| C183 | L856 | ⚠ needs-verdict D52 | D52 ✅ L1275 | **yes** (A6) |
| C192 | L889 | ⚠ needs-verdict D11 | D11 ✅ L1180 | no |
| C208 | L952 | ⚠ needs-verdict **D-B12** | settled by D60 ✅ L1290 | **yes** (A20) |

**Legitimately still marked:** C128 L545 `⚠ needs-verdict D37` — D37 (L1240) has no ✅. Keep.

**Unnumbered needs-verdict:** C15 L115 — "`— code-core (needs-verdict, marker width)`" names no Dn, and
C15's own text already decides the rule ("every reader accepts `\d+`, every writer emits `%03d`"). Drop the parenthetical.

**Resolved "confirm" asks that read like open marks:** C203 L932 "Confirm the list" (settled by D4 L1162).
Still genuinely open: C197 L909 "Confirm the narrowing" (see B21).

### C.2 `⚠ required difference` with no R row (3)

| clause | line | the difference | where it should be |
|---|---|---|---|
| C74 | L332-335 | image shares: PNG stays PNG, GIF kept as GIF, no JPEG re-encode (D17) | **no R row exists.** Add one, or drop the mark. |
| C126 | L538-540 | a Voice Memo's own filename becomes the title; a messenger filename never does | **no R row exists.** Add one (it is a target-1/ingress difference). |
| C62 | L278 | `_inbox/Skrift/` vs v1's flat `_inbox/` — the words "required difference" appear **in prose, without the ⚠ mark** (D41 L1253 calls it one) | add the ⚠ mark **and** an R row. |

Marked and *not* in the R table but explained by the prose at **L1140-1142**: C110 (L472) and C111 (L476)
— "fixed in v1 now, not waited on". Acceptable; note that R58 (L1134) separately cites C110 for a
*different* bug, which reads as double-coverage.

### C.3 R rows whose cited clause does not carry the requirement (10)

Every R row has a clause id and every cited clause exists, so there is **no R row without a clause**.
These ten cite a clause whose text says nothing about the behaviour, so the R row is the only place it lives —
`/2-plan` parsing clauses will miss them.

| R (line) | cites | the clause is silent on |
|---|---|---|
| R45 L1121 | C89 L388 | clamping a future `recordedAt` age at 0 (D93) |
| R48 L1124 | C92 L404 | checking notification permission before showing a reminder as set |
| R49 L1125 | C59 L266 | escaping a hand-typed `[[word]]` |
| R50 L1126 | C56 L255 | quoting tags that contain `: ` |
| R52 L1128 | C179 L842 | Redo asking before overwriting a hand edit (D95) |
| R53 L1129 | C192 L886 | reading the bookmark `stale` flag / not minting a second `Skrift/` |
| R54 L1130 | C180 L844 | the iPad polish battery floor |
| R56 L1132 | C89 L388 | never sweeping the note currently open |
| R57 L1133 | C45 L219 | content-hash staleness, diarization re-adopt |
| R44 L1120 | C46 L222 | stamp-vs-stamp LWW with skew |

---

## D) NUMBERING (9)

| # | finding | lines |
|---|---|---|
| D-1 | **Clause ids are clean**: C1–C253, 253 clauses, **no duplicates, no gaps.** | L55–L1067 |
| D-2 | **File order is non-monotonic.** C164 is followed by C238 (L698); C253 is followed by C165 (L792). A parser that assumes ascending order will mis-segment. Order on disk: C1–C164, C238–C253, C165–C237. | L698, L792 |
| D-3 | **R34 is out of order**: it sits at L1137, after R60, although R1–R60 are otherwise ascending. It also has no blank line before the `Pre-registered as IDENTICAL` sentence at L1138. | L1137 |
| D-4 | **`D-B12 / D-B15 / D-B26 / D-B33 / D-B37` are referenced but do not exist in SPEC.md.** They are backlog decision ids from another document; there is no D-B list here. | L952 (D-B12), L902 (D-B15), L920 (D-B26), L392 (D-B33), L940 (D-B37) |
| D-5 | **"221 `[auto]` clauses" is stale** — the file now carries **223** `[auto]` and 30 `[tuur]`. The breakdown 66+77+54+24 = 221 predates C252/C253. | L776 |
| D-6 | **106 vs 109 corpus notes.** C4 says 109 (109 directories exist on disk); the Gate paragraph says 106. | L46 vs L65 |
| D-7 | **R10 is withdrawn but still numbered as a required difference** and simultaneously listed as IDENTICAL. | L1087, L1138 |
| D-8 | **Every `Dn` referenced in a clause exists** (D1–D52, D60, D81, D90, D92 are cited; D1–D95 all defined). No dangling decision ids. | L1157–L1366 |
| D-9 | **Every clause cited by an R row exists.** No dangling clause ids in the R table. | L1078–L1137 |

---

## E) /2-plan READINESS (35 clauses across 6 groups)

Every clause carries `[auto]` or `[tuur]` — **none is unmarked**. The gaps are checks.

| group | count | clauses (lines) |
|---|---|---|
| **E-1 `[auto]` with NO `\|\| check:`** | 14 | C137 L596 · C184 L857 · C191 L882 · C202 L928 · C215 L975 · C216 L979 · C218 L987 · C219 L992 · C222 L1007 · C225 L1018 · C226 L1023 · C228 L1032 · C236 L1065 · C237 L1067 |
| **E-2 check names a symbol that does not exist in the repo** | 2 | C103 L446 → `VocabTests` · C209 L954 → `VoiceMatch` (`SpeakerFusion` does exist) |
| **E-3 check names a corpus note that does not exist** in `test-fixtures/corpus/notes/` | 8 | C63 L284 `video-made-archive` · C88 L384 `voice-en-rated-then-unrated` · C149 L633 `pic-after-interruption` · C150 L637 `voice-en-forty-minutes` · C151 L641 `voice-nl-recorded-in-english-mode` · C152 L644 `voice-en-append-after-polish` · C158 L666 `pic-deleted-after-export` · C159 L671 `voice-en-bruno-before-roster`. R16 L1093, R17 L1094 and R19 L1096 cite three of the same missing notes. |
| **E-4 check names a plan file that does not exist and is NOT marked as future** | 2 | C239 L706 → `plan/twins.md` · C244 L733 → `plan/measurements.md`. (`plan/parity.md` C247 and `plan/bug-shapes.md` C248 both exist.) |
| **E-5 check depends on another repo** | 1 | C130 L565 runs the archive's own `capture/tools/vault_index.py` — present at `~/Hackerman/Tiurihartog.com/capture/tools/vault_index.py`, but not reachable from `gate.sh` in this repo. Mark it as a cross-repo check or vendor a copy. |
| **E-6 `[tuur]` clauses that are QUESTIONS, not done-states** | 6 | C94 L411 (A4) · C114 L489 (A7) · C138 L598 (A18) · C183 L855 (A6) · C197 L907 (B21) · C203 L931 (A19). Five are answered by a ✅ decision; only C197 is genuinely open. |

**Properly marked as future, no action:** the v2 diff harness (L47) behind C5 L72, C6 L82, C7 L86, C9 L89;
`plan/scenarios-<subsystem>.md` C251 L772 ("before the swap"); device rounds in C100 L440, C107 L461,
C108 L464, C118 L499, C221 L1006, C243 L729. The coverage note at L777-778 already flags that no test
reads the corpus `expect` field (present in all 109 notes) — that is the diff harness's job.

---

## F) CLEANED CLAUSE LIST — the four rewrite targets, C10–C65 (56 lines)

Final text after the sitting. **UNCHANGED** = paste as-is from SPEC.md; the rest is the replacement line.
Later clauses that amend these (C140–C152, C157–C164, C169–C172, C176–C179, C192–C196) are cross-referenced
where they change the text; the amendments themselves need the edits listed in A and B.

| clause | final text |
|---|---|
| C10 | UNCHANGED, minus `⚠ needs-verdict D1`; append "old notes normalised once at first open on any device, name offsets re-derived once (D4, R25)." |
| C11 | UNCHANGED. |
| C12 | `[auto]` A picture with no moment of its own keeps its PLACE IN THE SEQUENCE it arrived in: in a multi-item share it lands between the clips, texts or videos it sat between (share order); a picture inserted in the editor lands at the caret; a VIDEO's frame is a picture paragraph at the video's own place in that sequence (D69, C68); a **lone** shared picture, a **lone** video's frame, or a picture with nothing around it goes to the TOP of the note. \|\| check: ingress P3 fixture; `cap-image-voice-ramble`; `video-*` bundled → frame in place, `video-*` alone → body starts with the marker. |
| C13 | UNCHANGED. |
| C14 | UNCHANGED. |
| C15 | UNCHANGED, minus "(needs-verdict, marker width)" — the rule is decided in the clause. |
| C16 | UNCHANGED. |
| C17 | UNCHANGED. |
| C18 | UNCHANGED. |
| C19 | `[auto]` Whitespace normalisation is ONE rule applied at **commit**, once, before the body is stored: horizontal runs inside a line → one space; ≥3 line breaks → one blank line; CRLF → LF; ends trimmed. The editor's in-session round-trip is exempt, so C18's byte-exact reconstruct and C6's identical-string invariant hold. \|\| check: corpus `typed-crlf-tabs-nbsp`, `voice-en-triple-blank-lines`. |
| C20 | UNCHANGED (already carries D5's 2.0 s and D7's typed-text rule). |
| C21 | UNCHANGED. |
| C22 | UNCHANGED. |
| C23 | UNCHANGED; append "an edit commits to the turn it started in, even if a rename or merge reshapes the list (R60)." |
| C24 | UNCHANGED. |
| C25 | UNCHANGED, minus `⚠ needs-verdict D6`; change the parenthetical to "(the vault filename stem is C165's single rule)". |
| C26 | UNCHANGED. |
| C27 | UNCHANGED. |
| C28 | UNCHANGED; append "every model repo — including a Settings-entered one — carries a revision; a repo without one is refused (R39)." |
| C29 | UNCHANGED. |
| C30 | UNCHANGED. |
| C31 | UNCHANGED. |
| C32 | UNCHANGED; append "a truncated output returns the ORIGINAL body on both apps (D53)." |
| C33 | UNCHANGED. |
| C34 | `[auto]` Paragraph count of the shipped body ≥ paragraph count of the input, unless the shrink guard fired; a wall of **SPOKEN** text (> 600 chars, < 2 breaks, > 4 sentences) is broken deterministically at 4 sentences / 600 chars; a **TYPED** note is never re-paragraphed (C20, D7). \|\| check: corpus `voice-en-asr-wall`; `typed-wall-7k` **unchanged**; the paragraph ledger `in N → model N → shipped N`, `shipped ≥ in` on every spoken wall (R14, R27). |
| C35 | UNCHANGED, minus `⚠ needs-verdict D8`; append "Dutch near-echoes are accepted for v2; the paragrapher, not the prompt, is the cure (D8, C177)." |
| C36 | UNCHANGED. |
| C37 | UNCHANGED. |
| C38 | UNCHANGED. |
| C39 | UNCHANGED, minus `⚠ needs-verdict D9`; replace the last sentence with "a stale local override is migrated away at first launch; one prompt source wins (D9, R26)." |
| C40 | UNCHANGED. |
| C41 | `[auto]` After any sweep: every rated, live memo has exactly one Mac row (id = memo id); a memo **un-rated after it had a row KEEPS the row**, out of the process queue and out of every export (C88); a never-rated or trashed memo has none; a second sweep changes nothing. \|\| check: `CorpusSeedTests.testEveryRatedNoteGetsAMacRow…`, `MemoCloudReconcilerTests`. |
| C42 | UNCHANGED. |
| C43 | UNCHANGED; append "an untouched empty typed note is discarded when he leaves it and is never listed (D91)." |
| C44 | UNCHANGED. |
| C45 | UNCHANGED; replace "unchanged rows are skipped without faulting blobs" with "staleness is a **content hash**, never a byte count; diarization is re-adopted whenever it changes (R57); unchanged rows are skipped without faulting blobs (R29)." |
| C46 | UNCHANGED; replace "LWW by `enhancedAt`" with "LWW by `enhancedAt`, **stamp compared to stamp** with ±5 s skew tolerance, never against this device's clock (D60, D93, R44)." |
| C47 | UNCHANGED. |
| C48 | UNCHANGED. |
| C49 | UNCHANGED. |
| C50 | UNCHANGED. |
| C51 | UNCHANGED. |
| C52 | UNCHANGED; append "a failed fetch of the cloud store is logged and shown, never swallowed (C168, R40)." |
| C53 | `[auto]` The picked folder IS the destination, resolved by `VaultLayout.home` (C192, D11): a pick named Skrift, a pick holding a stamped `.md`, or a pick containing a `Skrift/` is used as-is; otherwise `<pick>/Skrift` is created on first write; media subfolders `Recordings/ Images/ Documents/` are fixed; the archive root is returned unchanged. Identity lives in the file stamp (`skriftID`, `skriftHash`, `lastTouched`), never in a remembered path; a stale folder bookmark re-prompts and never mints a second `Skrift/` (R53). \|\| check: `VaultLayout`/`VaultStamp` tests. |
| C54 | UNCHANGED. |
| C55 | UNCHANGED. |
| C56 | `[auto]` The compiler is pure: same input → same string. **Vault profile** frontmatter = title · date · **created** · **duration** · author · source · book/bookAuthor/chapter · url · summary · tags · people · significance · location · weather · pressure · pressureTrend · dayPeriod · daylight · steps · stamp trio, in the code's grouped order (`Compiler.swift:60-175`); no coordinates, no reminder (D12). **Archive profile** = the C130 key list only, with `added:` in place of `date:` (D94). Title always quoted; a tag containing `: ` is quoted the same way (R50); `people:` = the distinct linked canonicals of the body, reading order, as a block list of plain names on the archive profile (R51); OCR text and shared documents export (R38). \|\| check: `CompilerTests`; corpus `voice-en-full-context`; every `dest-*` parses with `vault_index.py`. |
| C57 | UNCHANGED. |
| C58 | UNCHANGED. |
| C59 | UNCHANGED; append "a hand-typed `[[word]]` that resolves to nothing is escaped to plain text, never exported as Obsidian syntax (R49)." |
| C60 | UNCHANGED. |
| C61 | UNCHANGED (it supersedes C197's full-exportability doctrine — confirm and delete C197). |
| C62 | `[auto]` Four destinations, one per note: Personal → vault; Made → `_inbox/Skrift/`; Idea → `_ideas/`; Inspiration → `_inspiration/` with `needs: - credit` (v1 writes flat `_inbox/` — **required difference**, D41). The archive keeps `[[names]]` and `people:`, plainifies place LINKS, and drops weather, significance, **summary**, `author`, `type`, `source` (C130); it writes `capture:` and `voice:` (set by each app, never derived) and `added:` in place of `date:` (D94); flat, named, media beside the note. Whether `location:` stays is C137's open question. The whole feature sits behind ONE Settings switch, off by default; a destination is a per-device folder bookmark, one archive root. \|\| check: `ArchiveExportTests`; corpus `dest-*`. |
| C63 | `[auto]` No video goes to the Obsidian vault: a video note exports markdown + audio + the frame there. A video filed Made / Idea / Inspiration keeps its source movie as a **synced asset** (cap ~200 MB, D44, C148), so the archive export copies it from whichever device exports; a Personal video discards the movie. \|\| check: corpus `video-*`; a new `video-made-archive` note (missing today, E-3). |
| C64 | `[auto]` `date:` = the **recording's local day** on every device — one timezone rule, no per-device reinterpretation (D13). \|\| check: phone and Mac export of one corpus note recorded at 23:30 agree (R15). |
| C65 | UNCHANGED. |

---

## Counts

| section | rows |
|---|---|
| A — clause vs decision | 24 (+ 5 decisions with no clause) |
| B — clause vs clause | 27 |
| C — stale marks | 44 (30 stale `needs-verdict` + 1 unnumbered + 3 `required difference` without an R row + 10 R rows whose clause is silent) |
| D — numbering | 9 |
| E — `/2-plan` readiness | 35 clauses in 6 groups |
| F — cleaned C10–C65 | 56 lines (18 changed, 38 unchanged) |
