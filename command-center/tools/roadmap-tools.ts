/**
 * Tiuri Command Center — the strict tool layer (the "spine").
 *
 * This is the ONLY way the plan changes. The planning chat (Claude API) is given
 * TOOL_DEFS as its tools; Claude emits a tool call; `applyTool` mutates the in-memory
 * roadmap (the MODEL); the caller then commits the new YAML to GitHub with the file's
 * expected blob SHA (409 → re-read → re-apply → retry) and the canvas re-renders.
 *
 * Invariants enforced HERE (model level), not in the UI:
 *  - node `id` is immutable across every op (it keys reactions). add_node mints a new id.
 *  - at most ONE node is `now`. Promoting to `now` demotes the prior `now` → `inprogress`.
 *  - move_node changes ONLY lane/order. layout is auto-computed from lane+order downstream.
 *  - destructive/bulk ops (reconcile, deferring an inprogress node) are PREVIEWED, then applied.
 *
 * Pure + framework-free on purpose: trivially testable, and Claude can fix it.
 */

export type Status = "done" | "inprogress" | "now" | "planned" | "deferred";

export interface Node {
  id: string;          // STABLE — never mutated
  title: string;
  lane: number;        // matches a lanes[].track
  order: number;       // horizontal index within the lane
  status: Status;
  ms?: string;
  eff?: "S" | "M" | "L";
  done?: string;       // ISO date iff status === "done"
  deps?: string[];
  via?: string;
  risk?: boolean;
  note?: string;
  backlog?: string[];  // constituent todos, linked from backlog.md
}

export interface Roadmap {
  project: string;
  title: string;
  status?: string;
  repo?: string;
  roadmapPath?: string;
  version?: number;
  updated?: string;
  lanes?: { track: number; label: string }[];
  nodes: Node[];
  detours?: unknown[];
  history?: Node[];
  ideas?: { id: string; text: string; source?: string; nodeHint?: string; ts?: string }[];
}

/* ----------------------------------------------------------------------------
 * Tool definitions — pass straight to the Claude API `tools` param.
 * Every tool is strict: true + additionalProperties:false so a malformed edit
 * cannot be emitted. `after` lets Claude position RELATIONALLY ("after P2") so it
 * never reasons about pixel coordinates or raw order numbers.
 * -------------------------------------------------------------------------- */
const STATUS_ENUM = ["done", "inprogress", "now", "planned", "deferred"] as const;

export const TOOL_DEFS = [
  {
    name: "add_node",
    description: "Add a roadmap node. Position relationally with `after` (the id to sit just after in the lane); a fresh stable id is minted.",
    strict: true,
    input_schema: {
      type: "object", additionalProperties: false,
      required: ["title", "lane"],
      properties: {
        title: { type: "string" },
        lane: { type: "number", description: "lane track: 0 Core, <0 Differentiator, >0 Enrichment" },
        after: { type: ["string", "null"], description: "id to place this after in the lane; null = end" },
        status: { enum: [...STATUS_ENUM, null] },
        note: { type: ["string", "null"] },
        deps: { type: "array", items: { type: "string" } },
      },
    },
  },
  {
    name: "set_status",
    description: "Change a node's status. Promoting to 'now' atomically demotes the current 'now' node to 'inprogress' (only one 'now' ever).",
    strict: true,
    input_schema: {
      type: "object", additionalProperties: false,
      required: ["id", "status"],
      properties: { id: { type: "string" }, status: { enum: [...STATUS_ENUM] } },
    },
  },
  {
    name: "move_node",
    description: "Re-lane and/or re-order a node. Changes position only. Use `after` to place relationally.",
    strict: true,
    input_schema: {
      type: "object", additionalProperties: false,
      required: ["id"],
      properties: {
        id: { type: "string" },
        lane: { type: ["number", "null"] },
        after: { type: ["string", "null"], description: "id to place this after in the target lane; null = end" },
      },
    },
  },
  {
    name: "defer",
    description: "Park a node (status → deferred). Reversible.",
    strict: true,
    input_schema: {
      type: "object", additionalProperties: false,
      required: ["id"],
      properties: { id: { type: "string" }, reason: { type: ["string", "null"] } },
    },
  },
  {
    name: "add_idea",
    description: "Drop an unplaced capture into the idea inbox (not positioned on the tape until triaged).",
    strict: true,
    input_schema: {
      type: "object", additionalProperties: false,
      required: ["text"],
      properties: { text: { type: "string" }, nodeHint: { type: ["string", "null"] } },
    },
  },
  {
    name: "reconcile",
    description: "Batch re-plan ('mixdown'). Returns a previewable changeset (no write) — the UI shows tracked-changes and the user confirms before it commits as ONE revertable commit.",
    strict: true,
    input_schema: {
      type: "object", additionalProperties: false,
      required: ["defer", "promote", "note"],
      properties: {
        defer: { type: "array", items: { type: "string" } },
        promote: { type: "array", items: { type: "string" } },
        note: { type: "string" },
      },
    },
  },
] as const;

/* ----------------------------------------------------------------------------
 * The reducer. Returns a NEW roadmap (caller commits it). Throws on invariant
 * violations (unknown id, etc.) so the agent loop surfaces the error and retries.
 * -------------------------------------------------------------------------- */
export type ToolCall =
  | { name: "add_node"; input: { title: string; lane: number; after?: string | null; status?: Status | null; note?: string | null; deps?: string[] } }
  | { name: "set_status"; input: { id: string; status: Status } }
  | { name: "move_node"; input: { id: string; lane?: number | null; after?: string | null } }
  | { name: "defer"; input: { id: string; reason?: string | null } }
  | { name: "add_idea"; input: { text: string; nodeHint?: string | null } }
  | { name: "reconcile"; input: { defer: string[]; promote: string[]; note: string } };

/** A reconcile preview the UI renders as tracked-changes before committing. */
export interface ReconcilePreview {
  kind: "reconcile-preview";
  defer: string[];
  promote: string[];
  note: string;
}

const clone = (r: Roadmap): Roadmap => JSON.parse(JSON.stringify(r));
const find = (r: Roadmap, id: string): Node => {
  const n = r.nodes.find((x) => x.id === id);
  if (!n) throw new Error(`unknown node id: ${id}`);
  return n;
};
/** order just after `afterId` in `lane` (or at the end). Keeps Claude out of order math. */
function orderAfter(r: Roadmap, lane: number, afterId?: string | null): number {
  const inLane = r.nodes.filter((n) => n.lane === lane).sort((a, b) => a.order - b.order);
  if (!afterId) return inLane.length ? inLane[inLane.length - 1].order + 1 : 0;
  const a = find(r, afterId);
  const next = inLane.find((n) => n.order > a.order);
  return next ? (a.order + next.order) / 2 : a.order + 1; // midpoint = no renumbering needed
}
function mintId(r: Roadmap): string {
  let i = 1; while (r.nodes.some((n) => n.id === `N${i}`)) i++; return `N${i}`;
}

/**
 * Apply a tool call. For `reconcile`, returns a preview (no mutation) — apply it
 * later via applyReconcile once the user confirms. Every other call returns the
 * mutated roadmap.
 */
export function applyTool(roadmap: Roadmap, call: ToolCall): Roadmap | ReconcilePreview {
  const r = clone(roadmap);
  switch (call.name) {
    case "add_node": {
      const lane = call.input.lane;
      r.nodes.push({
        id: mintId(r), title: call.input.title, lane,
        order: orderAfter(r, lane, call.input.after),
        status: call.input.status ?? "planned",
        note: call.input.note ?? undefined, deps: call.input.deps ?? [],
      });
      return bump(r);
    }
    case "set_status": {
      const n = find(r, call.input.id);
      if (call.input.status === "now") {
        const prev = r.nodes.find((x) => x.status === "now" && x.id !== n.id);
        if (prev) prev.status = "inprogress";          // one-NOW invariant
      }
      n.status = call.input.status;
      if (call.input.status === "done") n.done = today();
      else delete n.done;
      return bump(r);
    }
    case "move_node": {
      const n = find(r, call.input.id);
      const lane = call.input.lane ?? n.lane;
      n.lane = lane;
      if (call.input.after !== undefined) n.order = orderAfter(r, lane, call.input.after);
      return bump(r);                                  // position only — id/status untouched
    }
    case "defer": {
      find(r, call.input.id).status = "deferred";
      return bump(r);
    }
    case "add_idea": {
      (r.ideas ??= []).push({ id: `i${(r.ideas.length || 0) + 1}`, text: call.input.text, source: "voice", nodeHint: call.input.nodeHint ?? undefined });
      return bump(r);
    }
    case "reconcile":
      return { kind: "reconcile-preview", defer: call.input.defer, promote: call.input.promote, note: call.input.note };
  }
}

/** Commit a confirmed reconcile preview as ONE mutation. */
export function applyReconcile(roadmap: Roadmap, p: ReconcilePreview): Roadmap {
  const r = clone(roadmap);
  for (const id of p.defer) find(r, id).status = "deferred";
  for (const id of p.promote) { const n = find(r, id); if (n.status === "planned" || n.status === "deferred") n.status = "inprogress"; }
  return bump(r);
}

function bump(r: Roadmap): Roadmap { r.version = (r.version ?? 0) + 1; r.updated = new Date().toISOString(); return r; }
function today(): string { return new Date().toISOString().slice(0, 10); }
