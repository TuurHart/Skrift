# Naming & people-linking — LOCKED design

**Re-derived from first principles in a grill session 2026-06-16.** This SUPERSEDES the
opt-in approach (`mocks/opt-in-naming.html` + the shipped chunks 1–5, commits
`4bb3839..83b7ce0`). Read this before touching names/sanitising. Status: design locked;
research sanity-check in flight; mock + build next.

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

1. **Aggregate via Obsidian backlinks** to one-note-per-person. **Canonical = the user's
   `People/` note title** — if it doesn't match exactly, the link is dead and the person
   silently drops off their own timeline.
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
5. **Recognition = KNOWN-ROSTER ONLY (option A). No NER, no LLM detection.** The roster is
   **seeded from the `People/` folder** by simple app code (note titles only — privacy-safe).
   Genuinely-new people are added **manually by right-click** during review. User's call:
   "I read the note I'm working on, so I'll right-click a new person — not a big issue." The
   roster is **incomplete and grows for life**; the user *accepts* the manual-catch
   responsibility rather than trust auto-detection.
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

1. **Roster.** App code reads `People/` note titles → the known cast. Canonical = title.
2. **Transcribe.** Parakeet, vocab-boosted with the roster → most names already correct.
3. **Recognise** known names by alias-match (DB holds nicknames/mishears → canonical).
4. **Opt-out link.** Each known *unambiguous* person's **first** mention → `[[Person|name]]`
   (one snippet on their note); later mentions normalise to plain correct text. Ambiguous →
   dotted, pending a click. Everything else stays plain.
5. **Review by reading.** Highlighted/dotted names in the prose; click → popover to keep /
   unlink (side-mention, → exclude list) / change / add-new / leave-plain.
6. **Export.** Body = one link per subject (the snippets) + `people:` frontmatter (durable +
   queryable) + correctly-spelled names.

---

## Migration from what shipped (chunks 1–5)

- **DELETE:** `PeopleChipBar`; the `InlineResolverModel` / `applyPartialOccurrences` /
  resolver-banner machinery; the opt-in **`aboutPeople` include-list** (flips to opt-out,
  which reuses the **`unlinkedNames` exclude-list that already exists**); any LLM in naming.
- **KEEP / REPURPOSE:** the deterministic alias-match `Sanitiser`; `Compiler` `people:`; the
  click-a-name popover (`unlinkOccurrence` / `relinkOccurrence` already do link/unlink/change);
  the dotted recognised-but-unlinked state (was in the original mock); normalisation.
- **ADD:** opt-out default (link-all-known, prune via exclude-list); **`People/`-folder roster
  seeding** (canonical = title); optionally feed that roster into the Parakeet vocab boost
  (closed loop: same roster → correct transcription → deterministic match).

Net: this is mostly **deletion + flipping a default**, not new building.

### Data-model deltas to work out at build time
- Drop `aboutPeople` (include) → the prune record is the existing `unlinkedNames` (exclude).
- A small per-note record for an ambiguity pick ("this note's Jack = Jack Hutton") so a
  re-process remembers the choice.
- The names DB becomes a **thin alias-cache** layered over the `People/` roster.

---

## Deferred / explicitly out of scope
- **Skrift creating or enriching person notes** (`firstMentioned`, profiles, `confidence`) —
  a separate "people CRM" track. For now Skrift only *links*; the user maintains `People/`
  notes by hand. Unresolved links still aggregate via backlinks, so the timeline works without
  it.
- **Phone-side picking UI** — build Mac-first, but the model is deliberately portable.
- **NER / LLM "nudge" for unknown people** — rejected (pure manual).
- **Tag normalisation** (e.g. "filosofaties") — a parallel issue, not this.

---

## Next steps
1. **Research sanity-check (in flight):** how Tana / Reflect / Logseq / Roam / Obsidian
   people-plugins handle "auto-link known people, prune the rest, capture new ones manually" —
   purely to catch an obviously-simpler pattern. Won't change the locked decisions unless it
   surfaces something compelling.
2. **Mock** the dotted-prose + click-popover UX (that's the whole UX now).
3. **Build** (mostly the deletions + the default flip + roster seeding).
