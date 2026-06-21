# Obsidian export — conflict-model alternatives

> Decision doc (2026-06-22). The current built design (`ObsidianPublisher`) is **option 1** below.
> You said you're unsure about it — here are 6 fleshed-out alternatives + a recommended hybrid.
> Source: a 12-agent exploration (prior art: Readwise→Obsidian, Bear, Day One, Obsidian
> Daily/Periodic Notes, the iCloud-Drive conflict-copy problem).

## The core tension (why this is hard)

Every notes-to-vault tool sits on a spectrum between two philosophies, and **both have a fatal flaw**:

- **Mirror / overwrite** (Readwise *Mirror*, and our current build): the vault file is a disposable
  render of the source of truth → perfect fidelity, but **your edits in the vault get clobbered**.
- **Append-only** (Readwise *official* plugin): never touches your edits → safe, but **updates can't
  flow in** and file identity breaks on rename (the `note 2.md` problem).

Your ask — *"I want to keep editing in my vault"* — is exactly what pure mirror (our current design)
gets wrong. The resolution the research keeps landing on is a **third path**: split each note into a
**Skrift-owned region** (machine text, safe to update) and a **user-owned region** (your notes, never
rewritten), with file identity carried by a **`skrift-id`** (not the filename, so renames never dupe).

## The 6 alternatives at a glance

| # | Model | Can you edit in the vault? | Do updates flow in? | Privacy posture | Effort | Best for |
|---|---|---|---|---|---|---|
| **1** | **One file per memo, overwrite** *(BUILT today)* | ❌ clobbered on re-export | ✅ full overwrite | 🟢 strict write-only (no vault reads) | S (done) | Vault as a read-only archive |
| **2** | **Create-only / edits-are-sacred** | ✅ 100% safe (never re-touched) | ❌ vault goes stale | 🟢 strictest (create-only) | S–M | "Seed it once, then it's mine" |
| **3** | **Append to daily notes** (block-id) | ✅ (outside the block) | ✅ in-place block update | 🟡 reads own daily notes (opt-in) | L | Daily/Periodic-Notes journalers |
| **4** | **Round-trip guard** (conflict-aware) | ✅ detected, never clobbered | ✅ until a real conflict | 🟡 reads back own files only | M | Edit-in-vault power users |
| **5** | **Template routing** (write anywhere) | ⚠️ risky (your own folders) | ✅ overwrite | 🟡 own-file reads + collision checks | M–L | "Make it fit MY taxonomy" |
| **6** | **Index + per-book aggregation** | ✅ (book user-region) | ✅ in-place block | 🟡 reads own book files | L | The audiobook commonplace book |

## Each option, briefly

**1 · One file per memo — overwrite *(what's built)*.** Every memo → one `.md` in a Skrift-owned
`Skrift/<source>/` subtree; path frozen at first export (rename-safe); SHA-256 skip; atomic writes;
**zero vault reads** (privacy-perfect). The sharp edge: it owns the *whole* file, so there's **no safe
place for you to add notes** — any edit you make inside `Skrift/` is overwritten the next time the memo
changes. Honest fit: the vault is a searchable archive you link *from*, never edit *in*.

**2 · Create-only / edits-are-sacred.** Skrift writes each file **once** and never re-touches it —
edits/moves/renames are 100% safe by construction (the whole "did I clobber it?" bug class vanishes).
Cost: the vault goes **stale** — a memo you edit or the Mac later polishes shows the *old* text forever
(updates can only appear as a dated `--rev-` sibling), and the Mac's enhancement can't land in place.

**3 · Append to daily notes.** Each memo becomes a block under `## Skrift` in your `YYYY-MM-DD.md`,
anchored by `^skrift-<uuid>` so re-export updates *just that block* in place. Feels native to Obsidian
journalers and gives true sub-file in-place updates. Cost: it must **read + rewrite your daily notes**
(opt-in trust ask), risks a concurrent-edit window, and adds inline `^anchors`/`%% fences` noise. Heavy
(L) — a Markdown splicer is where data-loss bugs live.

**4 · Round-trip guard — *the cheap "third path"*.** Keep the current publisher, add **one read of
Skrift's own file before overwriting**: if its hash ≠ what we last wrote, the *you* edited it → don't
clobber, flag a **conflict** ("changed in your vault — Keep theirs / Overwrite / View diff"). Mirror
fidelity by default, **never-destroy-your-work** as a hard floor. Surgical delta over code that exists;
reads **only files Skrift wrote** (by its own ledger), never a scan. The honest cost: it relaxes strict
write-only → "read back our own files," and resolution is whole-file (not per-line).

**5 · Template routing.** You configure a destination folder + Markdown template, routed per
tag/source/significance — captures land natively in *your* `People/`, `Daily/`, `Reading/` folders.
Maximum power, but **breaks the owned-subfolder safety**: a generated `People/Jack.md` looks
hand-authored, you edit it, re-export clobbers it (unless paired with the user-region split). Needs
collision guards + a config UI. Best as an opt-in advanced layer on top of the default.

**6 · Index + per-book aggregation — *the commonplace book*.** Route by type: audiobook **quotes
aggregate into one note per book** (Readwise-style, appended under `## Highlights` with `^skrift-id`
anchors), voice memos stay one-file-each, and a regenerated **`Index.md` MOC** ties it together. Leans
straight into the audiobook angle the app is built around (the quote/ramble split already exists). Cost:
re-introduces a *shared* write target (multi-device concurrent append can lose a block), needs the
read-back splicer, and the Mac's flat exporter would need teaching. Heaviest (L), biggest payoff for
*your* core user.

## ⭐ Recommendation — evolve #1 into a split-note + guard hybrid

Don't throw away the built work — **grow it**. Three additive moves turn the current design into the
research-endorsed hybrid and directly fix your "edit in my vault" concern:

1. **User-owned region** (from the hybrid + #6): each exported note splits into a Skrift region
   (frontmatter + transcript/quote, above a `<!-- skrift:end -->` / `## My notes` fence) and **your
   region below the fence that Skrift NEVER rewrites.** You annotate under any note, safely, forever.
2. **Round-trip guard** (#4): before overwriting the Skrift region, read back our own file; if you
   changed *that* region too, flag a conflict instead of clobbering. Never-destroy-your-work floor.
3. **`skrift-id:` frontmatter** (prior-art's #1 lesson): identity ≠ filename, so even if *you* rename
   the file in Obsidian, Skrift re-finds it — no duplicate.

Keep everything #1 already nails: owned `Skrift/` subfolder, sticky path, content-hash skip, atomic
coordinated writes. **Effort ≈ M** (it's the built publisher + a read-back + a fence-aware splice of our
*own* file). Defer the bigger modes as **opt-in** later: daily-note append (#3) for journalers, and
per-book aggregation (#6) for the audiobook commonplace book — #6 is the one I'd prioritize next given
your audiobook focus.

## The one decision this needs from you

The hybrid (and #3/#4/#5/#6) all relax the **strict "never read the vault" hard rule** to:

> *"Skrift may read back only the files it itself wrote, located by its own `skrift-id` — never a scan,
> glob, or read of any note Skrift didn't create."*

The research is clear this is **aligned with privacy, not in tension** — re-finding your own content by
id is exactly what lets you do safe in-place updates *without* touching anyone else's notes. But it's a
genuine change to a stated hard rule, so it's your call:

- **(A)** Keep strict write-only → you're limited to **#1 (built)** or **#2 (create-only)**.
- **(B)** Allow "read back our own files by id" → unlocks the **recommended hybrid (#1+#4+user-region)**,
  and later #3 / #6.

My recommendation: **(B) + the hybrid.** It's the only path that gives you both "I can edit in my vault"
*and* "the Mac's polish still flows in," at moderate effort, while keeping the privacy boundary narrow
and auditable ("our reads ⊆ our writes").
