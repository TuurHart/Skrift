# Naming & people-linking — LOCKED design

**Re-derived from first principles in a grill session 2026-06-16.** This SUPERSEDES the
opt-in approach (`mocks/opt-in-naming.html` + the shipped chunks 1–5, commits
`4bb3839..83b7ce0`). Read this before touching names/sanitising. Status: **design locked +
research-validated (2026-06-16)** — prior-art sanity-check done (verdict: "sound as-is, build
it"); refinements + build-guards folded in below. **Mock next, then build.**

---

## The job (north star)

Every person = **one note** (the user already keeps a `People/` folder — Jack Hutton,
Hendri van Niekerk, …). Memos that are **about** a person collect on that person's note as
**dated Obsidian backlinks**, so decades later you open their note, scroll, and watch the
relationship evolve over time.

Two **separable** jobs we had been conflating (this split is the key insight):
- **A — names right everywhere (normalisation).** Even an unlinked side-mention should be
  spelled correctly ("cherry" → "Tuur"). Plain text, applies to everyone recognised.
- **B — aggregate the subjects (linking).** Only people a note is *genuinely about* become a
  graph edge so they collect on their person-note. Side-characters explicitly do **not**.

---

## Locked decisions (with the WHY — do not re-litigate)

1. **Aggregate via Obsidian backlinks** to one-note-per-person. The **canonical lives in
   Skrift's portable names DB** (see decision 5); when exporting to an Obsidian vault it must
   **match the `People/` note title exactly** — otherwise the link is dead and the person
   silently drops off their own timeline. (On an Obsidian-less phone there's no `People/` note;
   the DB canonical stands alone.)
2. **Keep one inline body link per subject (the FIRST mention).** Reason: a *body* link makes
   Obsidian's backlink pane show the actual **sentence** ("…the dough Jack proofed went
   floppy…") — you read the arc on the person's note without opening anything. First-mention-
   only keeps the prose clean (not a sea of links) and is the right grain for a *cross-memo*
   timeline (one snippet per memo).
3. **Keep `people:` frontmatter.** It overlaps the body link on backlinks, but it's
   **durable** (survives body edits — a fragile inline link can vanish on a re-write and lose
   the person), **queryable** (Dataview/Bases tables), and a clean graph edge. Body link =
   *browse*; `people:` = *query*. User likes it for Dataview.
4. **DEFAULT = OPT-OUT.** Known people auto-link by default; you **prune** the side-characters.
   Reason (the load-bearing one): for a 50-year capture archive, a **missed** link is
   unrecoverable, a **stray** link is a two-second prune. Opt-in (start blank, tap to add)
   taxes every memo and silently drops the ones you forget. The asymmetry points one way.
   *(This flips the shipped opt-in model.)*
   **— RISK-TIERED auto-write (adopted 2026-06-16 after research; the one place the ecosystem
   diverges from us — no other tool auto-*writes* links, they auto-*suggest* and commit on
   click).** So opt-out auto-*commits* only the SAFE matches and downgrades the FP-prone subset
   to dotted-suggested (commit on click):
   - **Auto-commit:** a full name, OR a distinctive first name (not a dictionary word, not
     shared by 2+ roster people). This is the common case — "Hendri", "Bruno", "Mariam", most
     "Jack"s still link with zero clicks; opt-out's benefit is preserved.
   - **Dotted-suggest (click to commit):** a first name that's also a common word
     (Will, Mark, Rose, Grace, Hope, Drew, Bill…), OR a name shared by 2+ roster people (the
     ambiguous Jacks — already decision 9).
   - **Left plain:** a common word that isn't a person here ("I **will** call"). A stoplist /
     dictionary check is what catches Will/Rose-type names. This defuses the #1 documented
     failure of deterministic matching (common-word false positives), which opt-out *amplifies*
     because it writes to the file. It's a scalpel on the default, not a reversal.
5. **Recognition = KNOWN-ROSTER ONLY (option A). No NER, no LLM detection.** The roster +
   aliases live in **Skrift's OWN portable names DB** — the source of truth, because it must
   work **phone + Mac, with or without Obsidian** (the standalone direction; the phone may have
   no vault). The `People/` folder is an **optional Obsidian seed/sink**: on a Mac with a vault
   Skrift can import its note titles to bootstrap the roster (app code, titles only —
   privacy-safe) and can mirror aliases into the note's `aliases:` frontmatter as a courtesy,
   but the **DB is the home, the note is not**. Genuinely-new people are added **manually by
   right-click** during review (make it a one-keystroke fuzzy picker, not a heavy menu — and
   run the existence-check so manual-add can't mint a duplicate of someone already in the
   roster). User's call: "I read the note I'm working on, so I'll right-click a new person."
   The roster is **incomplete and grows for life**; the user *accepts* the manual-catch
   responsibility. **REJECTED 2026-06-16 (do not build):** an auto "new person?" hint — even a
   deterministic capitalized-token-not-in-roster one — because ASR casing on speech is shaky
   (noisy/weak) and the user wants pure-manual. Documented boundary: the system **"never misses
   KNOWN people"**; it does NOT claim to catch unknown/new people — that's accepted.
6. **NO LLM anywhere in the naming path. Pure deterministic string-matching.** Reason: it must
   be **portable to the phone** (the standalone direction). An LLM chains naming to the Mac /
   a big on-device model; deterministic code runs anywhere. Parakeet's custom-vocab boost
   (FluidAudio CTC boosting) already spells most known names right *at transcription*, so
   there's little left to fix. *(This also settles the old "which layer?" question: pick the
   model that runs Mac-now AND phone-later.)*
7. **Normalise mistranscribed KNOWN names to the correct form everywhere** (linked or not).
   When unlinked, show the corrected name **dotted** (recognised-but-unlinked) so the fix is
   **visible and one-click-revertible** — never a silent rewrite. (The exported body already
   isn't the raw audio — the LLM copy-edits it and the verbatim transcript is kept separately,
   so name-correction is in the same spirit.)
8. **Interaction = click a highlighted/dotted name in the prose → small popover → decide:**
   keep · it's a side-mention (unlink) · wrong person (change) · it's new (add) · leave as
   spoken. Demoted names **stay dotted + re-promotable**. This replaces the chip bar — you
   adjudicate names *in the prose as you read*, which is also a great phone interaction.
9. **Ambiguity (two known people sharing a name) = note-level pick + per-mention override.**
   An ambiguous name isn't auto-linked → it's dotted → click → "which one?" (default applies
   to the whole note); the rare second person in the same note = click *that* dotted mention
   and pick the other. **No dedicated per-occurrence resolver.** Two genuinely-different
   same-named subjects in one memo is vanishingly rare (user: never happened) and doesn't
   justify a whole UI.
10. **KILL** the per-occurrence resolver and the opt-in chip bar.

---

## The model, end to end (all deterministic, LLM-free)

1. **Roster.** Lives in Skrift's **portable names DB** (phone + Mac). On a Mac with a vault,
   app code can seed it from `People/` note titles; the DB canonical must match the vault title
   so links resolve. Aliases live in the DB (mirrored to the note's `aliases:` on Obsidian
   export, as a courtesy).
2. **Transcribe.** Parakeet, vocab-boosted with the roster → most names already correct.
3. **Recognise** known names by deterministic alias-match (DB holds nicknames/mishears →
   canonical; needs *some* fuzzy/phonetic tolerance for ASR mangling — see build-guards).
4. **Opt-out link, risk-tiered.** A known person's **first** mention auto-commits to
   `[[Person|name]]` (one snippet on their note) **only if SAFE** (full name / distinctive
   first name); FP-prone names (common-word or shared) go **dotted-suggested** instead; later
   mentions normalise to plain correct text; everything else stays plain.
5. **Review by reading.** Highlighted/dotted names in the prose; click → popover to keep /
   unlink (side-mention, → exclude list) / change / add-new / leave-plain.
6. **Export.** Body = one link per subject (the snippets) + `people:` frontmatter (durable +
   queryable) + correctly-spelled names.

---

## UX + visual language — SIGNED OFF 2026-06-16 (`mocks/naming-review.html`)

The whole interaction lives **in the prose** — no chip bar, no pending bar. Three tiers, plus a
click-popover. Iterated in chat to sign-off; the mock is the spec.
- **Linked** (committed subject): solid accent text `#9d8ff7`, **no background**, highlight only
  on hover. First mention only — repeats render plain.
- **Suggested** (recognised but pending: common-word names + ambiguous twins): soft tan
  `#bda481` text + dotted underline `#ab9676`. The color *is* the "needs a decision" cue (that's
  why the pending-count bar was dropped — deemed extra fluff).
- **Plain**: default text — dictionary words (stoplisted), unknown people, and repeat mentions.
- **Click a suggested name** → popover: pick which person · new person… · leave as plain text.
- **Click a linked name** → popover: unlink (the everyday "just a side-mention" prune) · change
  person (fix a wrong match) · open their note. An unlinked name stays a dotted suggestion
  (re-promotable).
- Hover lifts a name (faint accent bg) to invite the click.
- *Rejected during sign-off:* the filled-highlight link style (too heavy — "sea of links"), the
  pending-count bar (extra chrome), bright/saturated amber for suggested (too flashy).

## Migration from what shipped (chunks 1–5)

- **DELETE:** `PeopleChipBar`; the `InlineResolverModel` / `applyPartialOccurrences` /
  resolver-banner machinery; the opt-in **`aboutPeople` include-list** (flips to opt-out,
  which reuses the **`unlinkedNames` exclude-list that already exists**); any LLM in naming.
- **KEEP / REPURPOSE:** the deterministic alias-match `Sanitiser`; `Compiler` `people:`; the
  click-a-name popover (`unlinkOccurrence` / `relinkOccurrence` already do link/unlink/change);
  the dotted recognised-but-unlinked state (was in the original mock); normalisation.
- **ADD:** opt-out default (link-all-known, prune via exclude-list); **risk-tiering** of
  auto-write (full/distinctive → commit; common-word/ambiguous → dotted-suggest) backed by a
  small **dictionary/stoplist** FP-guard; **roster seeding** into the portable DB (from
  `People/` titles on Mac); optionally feed that roster into the Parakeet vocab boost (closed
  loop: same roster → correct transcription → deterministic match).

Net: this is mostly **deletion + flipping a default**, not new building.

### Data-model deltas to work out at build time
- Drop `aboutPeople` (include) → the prune record is the existing `unlinkedNames` (exclude).
- A small per-note record for an ambiguity pick ("this note's Jack = Jack Hutton") so a
  re-process remembers the choice.
- The names DB becomes a **thin alias-cache** layered over the `People/` roster.

---

## Build-time guards (from the 2026-06-16 prior-art sanity-check — NON-NEGOTIABLE)

The research verdict was "sound as-is, build it" — every core choice is validated by mature
tools (backlink-timeline = Granola/Reflect/Roam; first-mention-only = Capacities + Wikipedia
MOS:OVERLINK; known-roster/no-NER/manual-add = Obsidian Entity Notes / obsidian-people-link /
Virtual Linker; killing the per-occurrence resolver = UNANIMOUS, no tool ships one;
roster-only matching structurally dodges Tana's #1 pain, duplicate person-nodes). These guards
are the price of getting it right:

- **Common-word / short-name FP guards (the #1 documented failure; opt-out amplifies it):**
  whole-word + capitalization match; roster-scoped only; **prefer multi-token full-name over a
  bare first name**; never auto-commit a single name that's a dictionary word or collides with
  2+ roster entries → those go dotted-suggested (decision 4 tiering). (Our own vocab-booster
  memory already flags ≤3–4-char names as FP-prone — same hazard here.)
- **Skip non-prose spans when scanning:** existing links, YAML, code blocks, and **verbatim
  audiobook-quote spans** — a name inside a quoted book passage is NOT "about" that roster
  person. (Matters for the quote-capture feature.)
- **Retroactive re-scan on roster collision:** the day a SECOND same-name person is added,
  every previously auto-linked first-`[[Jack]]` memo is now mis-resolved and nothing warns you.
  Plan a re-scan/flag pass over already-exported notes — the per-note ambiguity-pick record
  only helps NEW processing.
- **`people:` frontmatter is the canonical record:** keep it and the body link in lockstep on
  every keep/prune/change/normalize, update BOTH atomically on rename/merge, and NEVER let the
  timeline depend on the fragile body link surviving an edit (chunk-fusion / same-speaker-merge
  can delete the sentence holding the sole link).
- **Fuzzy-vs-strict is the central engineering tension:** the "ASR boost already spells names
  right" premise is optimistic (Whisper-class is weak on proper nouns; boost budget ~224
  tokens, caps a lifelong roster). The matcher needs *some* edit-distance/phonetic tolerance to
  catch a mangled name — but fuzzy-enough-to-catch vs strict-enough-to-avoid-common-word-FPs is
  the hard part the rest of the field offloads to an LLM (which we've excluded). **Budget a
  parity golden-set** for the matcher; keep normalization conservative (reuse the existing
  sim<0.55 drop-rule) so it never "corrects" a different word into a roster name.
- **Aggregation view:** every backlink needs a reliable **date**, and the decades-long person
  page needs a **date-sorted / filterable** view from day one (long backlink walls get
  unscrollable — a known Logseq-at-scale complaint), the Dataview/Bases analogue of Tana's
  "LINKS TO + sort by date".
- **Frame it honestly in docs/UI:** "**never misses KNOWN people**" — NOT "catches all
  people". Recall of unknown names is structurally capped at roster + ASR boost.
- **Own the files, never depend on a live plugin** to render the timeline (Obsidian's Virtual
  Linker broke on a 2025 API change and had to be forked). Skrift writes real `[[ ]]` +
  frontmatter to disk → the timeline survives without any runtime plugin.

---

## Deferred / explicitly out of scope
- **Skrift creating or enriching person notes** (`firstMentioned`, profiles, `confidence`) —
  a separate "people CRM" track. For now Skrift only *links*; the user maintains `People/`
  notes by hand. Unresolved links still aggregate via backlinks, so the timeline works without
  it.
- **Phone-side picking UI** — build Mac-first, but the model is deliberately portable.
- **Any auto "new person?" hint for unknown people** — rejected 2026-06-16, INCLUDING the
  deterministic capitalized-token-not-in-roster version (not just the LLM one). Pure manual.
- **Tag normalisation** (e.g. "filosofaties") — a parallel issue, not this.

---

## Next steps
1. ✅ **Research sanity-check DONE (2026-06-16).** Verdict: sound as-is. Refinements adopted —
   risk-tiered opt-out (decision 4), aliases live in the portable DB not the note (decision 5),
   one-keystroke fuzzy add-picker. Rejected — the new-person hint (decision 5).
2. ✅ **Mock signed off (2026-06-16) → `mocks/naming-review.html`.** Visual language locked
   (see the UX section above).
3. **BUILD** — ordered, gated chunks (UnitTests + `-skipMacroValidation` build per chunk; commit
   per chunk updating FEATURES.md + backlog.md + this doc's status). Read "Migration" before
   deleting:
   - ✅ **Chunk 1 — Sanitiser → opt-out + risk-tiering. DONE 2026-06-16.** Dropped the
     `aboutPeople` include-gate from `Sanitiser.process`/`processConversation` (+ the `gated`
     helper); known people now auto-link by DEFAULT (first mention), pruned by `unlinkedNames`.
     Risk-tiered: a full name OR a distinctive first name auto-commits; a common-word
     (`NameStoplist`) or ≤2-char single name, OR an alias shared by 2+ people, is downgraded to a
     **suggested** `AmbiguousOccurrence` (carried in `Result.ambiguous`, `candidates.count == 1`
     for common-word / `>= 2` for ambiguous). Capitalization FP-guard on common-word suggestions
     ("I will call" stays plain; "Will came over" suggests). `nonProseRanges` skips a leading
     YAML block / fenced+inline code / a verbatim audiobook-quote span. New `NameStoplist.swift`;
     callers (`BatchRunner`, `ProcessingCoordinator`) drop the `aboutPeople:` arg. Host-less tests
     rewritten opt-in→opt-out + risk-tier + quote-span; **288 UnitTests green + full app build
     green**. (`PipelineFile.aboutPeople` field + the now-inert chip bar/resolver wiring are
     deleted in chunk 3.)
   - ✅ **Chunk 2 — Roster seeding. DONE 2026-06-16.** New `PeopleFolderScanner.titles(vaultRoot:)`
     lists `<vault>/People/*.md` FILENAMES (top-level, no recurse, no contents, no AI — privacy);
     `NamesStore.seedRoster(titles:)` upserts each NEW title as a Person (canonical = title so the
     `[[ ]]` link resolves; aliases = full title + first-name token so opt-out can auto-link a bare
     "Hendri"), existence-checked (idempotent, never clobbers an existing person's aliases /
     voiceprints / grown state), synced via `writeWithSmartBumps`. Wired into
     `ProcessingCoordinator.process` (seed off the main actor before the runner reads the roster).
     7 host-less tests; **295 UnitTests green + full app build green**.
   - ✅ **Chunk 3 — Delete + data-model flip. DONE 2026-06-16.** Deleted `PeopleChipBar.swift` +
     `InlineResolver.swift` (`InlineResolverModel` / banner / `ResolverPopover`) and the per-occurrence
     Sanitiser engine (`applyResolvedNames` / `applyResolvedOccurrences` / `applyPartialOccurrences` /
     `PartialChoice` / `PartialApplyResult` / `plainSlotMap` / `detectedPeople` / `matchedSpeakers` —
     kept `plainOccurrences` for the unlink popover's mention count). Unwired the resolver + chip bar
     from `NoteDisplayView` (dropped `resolver` state + `syncResolver`/`wireResolver`/`resolveAlias`/
     `decideOccurrence`/`rerenderPartial`/`maybeCompleteAlias`/`commitResolution`) and `BodyTextView`
     (dropped the `resolver`/`refresh` params + ambiguous marking/click + jump) — the click-a-linked-
     name **unlink popover stays** (`unlinkOccurrence`/`relinkOccurrence`/`unlinkAll`). Data-model flip:
     dropped `PipelineFile.aboutPeople`, added the `namePicks` ambiguity-pick record (`namePicksJSON`
     + accessor, consumed by the Sanitiser in chunk 4); removed `ProcessingCoordinator.toggleAbout`;
     dropped the `-snapshot-resolver`/`-snapshot-people` snapshot modes. Deleted/updated the resolver
     tests. **Gate: 273 UnitTests green + full app build green.** (Suggested-tier rendering + the
     which-person popover are chunk 4.)
   - **Chunk 4 — In-prose UX (the heavy one).** Render the three tiers in the body
     (linked solid `#9d8ff7` / suggested tan `#bda481` dotted / plain) + the click-popover
     (which-person · unlink · change · new), reusing `unlinkOccurrence`/`relinkOccurrence`. Build
     to `mocks/naming-review.html`. Verify via `-snapshot` (inject people) / UITest / deploy-eyeball.
   - **Chunk 5 — Robustness.** Re-scan/flag pass when a 2nd same-name person joins the roster;
     matcher fuzzy-vs-strict tuning + a parity golden-set; finalize the remaining build-guards.
