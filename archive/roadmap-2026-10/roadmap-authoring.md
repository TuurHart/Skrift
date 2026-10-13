# Editing `roadmap.yaml`

The project's plan and single source of truth — the Command Center reads and renders it. Update it
in the same change as the work it describes.

- A **node** is a chunk of work with a done-state. `status`: `done | now | inprogress | planned | deferred`. Exactly one is `now`.
- `id` is permanent (edit the `title`, never the `id`).
- Layout is computed from `lane` (kind of work) + `order` (left→right) — set those, never position by pixel. `lane` is usually an integer track; a fractional `lane` is fine to draw a convergence (parallel tracks merging).
- The past is just nodes to the left: `done` nodes at negative `order`.
- Every node should carry a `win:` — the done-state in one line ("done when: …").
- The roadmap root should carry a `north:` — the project's one-line bet; weigh every node and idea against it.
- Optional fields: `note`, `backlog`, `shipped` (dated log on done work), `deps`/`via`, `ms`, `eff`, `risk`.
- A `backlog` item is a plain string (open) or `{text, done: <date>}` (shipped). Tick sub-parts when their work ships; done steps drop out of build kickoffs.
- Keep it lean — few nodes, short notes.

Validate against `roadmap.schema.json` — the Command Center renders this file, and its CI rejects a roadmap that breaks the schema or the one-NOW rule.
