"""
Centralised names.json read/write with timestamp-based sync support.

Schema:
{
  "lastModifiedAt": "<ISO 8601 UTC>",
  "people": [
    {
      "canonical": "[[Full Name]]",
      "aliases": ["Nick"],
      "short": "Nick",
      "lastModifiedAt": "<ISO 8601 UTC>",
      "deleted": false  // optional; tombstones for sync
    }
  ]
}

The top-level `lastModifiedAt` is recomputed on every write as the max of
all per-entry timestamps. It exists so callers (mainly the mobile app) can
do a cheap meta GET to decide whether they need to pull the full payload.

Migration: on first read after this module is introduced, any entry missing
`lastModifiedAt` is backfilled with the current time. The result is
persisted so the migration runs at most once.
"""

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from config.settings import get_names_path

logger = logging.getLogger(__name__)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _normalise_canonical(c: str) -> str:
    s = (c or "").strip()
    if s.startswith("[[") and s.endswith("]]"):
        return s
    return f"[[{s}]]" if s else ""


def _normalise_entry(p: dict) -> dict | None:
    canonical = _normalise_canonical(str(p.get("canonical", "")))
    if not canonical:
        return None
    aliases = p.get("aliases") or []
    aliases = [str(a).strip() for a in aliases if str(a).strip()]
    short = (str(p.get("short", "")).strip() or None)
    entry = {
        "canonical": canonical,
        "aliases": aliases,
        "short": short,
    }
    # Preserve voice profiles (forthcoming mobile diarization feature) as an
    # opaque pass-through so we never drop the phone's data, whatever shape the
    # embedding entries eventually take. Omitted from output when empty/absent
    # to keep names.json clean.
    voice = p.get("voiceEmbeddings")
    if voice:
        entry["voiceEmbeddings"] = voice
    # Preserve sync fields verbatim if present.
    if p.get("lastModifiedAt"):
        entry["lastModifiedAt"] = p["lastModifiedAt"]
    if p.get("deleted"):
        entry["deleted"] = True
    return entry


def _sort_people(people: list[dict]) -> list[dict]:
    def key(e):
        c = e.get("canonical", "")
        core = c[2:-2] if c.startswith("[[") and c.endswith("]]") else c
        return core.lower()
    return sorted(people, key=key)


def _recompute_top_level_timestamp(people: list[dict]) -> str:
    timestamps = [p.get("lastModifiedAt") for p in people if p.get("lastModifiedAt")]
    if not timestamps:
        return _now_iso()
    return max(timestamps)


def _migrate_legacy_shape(raw: Any) -> dict:
    """Coerce any older shape (list, {entries: [...]}, no timestamps) into the
    canonical shape. Adds `lastModifiedAt` to entries that lack one."""
    now = _now_iso()
    if isinstance(raw, list):
        people = raw
    elif isinstance(raw, dict):
        if "people" in raw and isinstance(raw["people"], list):
            people = raw["people"]
        elif "entries" in raw and isinstance(raw["entries"], list):
            people = raw["entries"]
        else:
            people = []
    else:
        people = []

    migrated = []
    for p in people:
        if not isinstance(p, dict):
            continue
        e = _normalise_entry(p)
        if not e:
            continue
        if "lastModifiedAt" not in e:
            e["lastModifiedAt"] = now
        migrated.append(e)

    return {
        "lastModifiedAt": _recompute_top_level_timestamp(migrated),
        "people": _sort_people(migrated),
    }


def read_names() -> dict:
    """Load names.json, applying one-time migration if needed.

    If the file doesn't exist, returns an empty canonical structure (does NOT
    create the file — that happens on first write).
    """
    path = get_names_path()
    if not path.exists():
        return {"lastModifiedAt": _now_iso(), "people": []}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        logger.warning(f"Failed to parse names.json at {path}: {e}; returning empty")
        return {"lastModifiedAt": _now_iso(), "people": []}

    canonical = _migrate_legacy_shape(raw)

    # Detect whether migration changed anything; if so, persist.
    needs_persist = False
    if not isinstance(raw, dict):
        needs_persist = True
    elif raw.get("people") != canonical["people"] or raw.get("lastModifiedAt") != canonical["lastModifiedAt"]:
        # Compare only the fields we care about — don't re-write if only key order differs
        before = [{k: v for k, v in p.items() if k != "lastModifiedAt"} for p in (raw.get("people") or [])]
        after = [{k: v for k, v in p.items() if k != "lastModifiedAt"} for p in canonical["people"]]
        if before != after or any("lastModifiedAt" not in p for p in (raw.get("people") or [])):
            needs_persist = True
    if needs_persist:
        try:
            _write_raw(path, canonical)
            logger.info("[names] migrated names.json to timestamped schema")
        except Exception as e:
            logger.warning(f"Failed to persist migrated names.json: {e}")

    return canonical


def _write_raw(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def write_names(data: dict) -> dict:
    """Write the canonical structure verbatim. Caller owns merge logic.

    Used by the phone sync PUT (caller has already merged) and by internal
    helpers that bump per-entry timestamps explicitly. Top-level
    `lastModifiedAt` is always recomputed from people[].
    """
    people = data.get("people") or []
    normalised = []
    for p in people:
        if not isinstance(p, dict):
            continue
        e = _normalise_entry(p)
        if not e:
            continue
        if "lastModifiedAt" not in e:
            e["lastModifiedAt"] = _now_iso()
        normalised.append(e)
    canonical = {
        "lastModifiedAt": _recompute_top_level_timestamp(normalised),
        "people": _sort_people(normalised),
    }
    _write_raw(get_names_path(), canonical)
    return canonical


def write_with_smart_bumps(new_people: list[dict]) -> dict:
    """Used by the desktop UI's POST endpoint: bump `lastModifiedAt` only for
    entries that actually changed compared to the on-disk version.

    New entries get a fresh timestamp. Unchanged entries keep theirs. Deleted
    entries (canonical no longer present) get a tombstone with the current
    timestamp so the next sync propagates the deletion.
    """
    existing = read_names()
    existing_by_canonical = {p["canonical"]: p for p in existing.get("people", []) if not p.get("deleted")}

    normalised: list[dict] = []
    incoming_canonicals = set()
    now = _now_iso()

    for p in new_people:
        e = _normalise_entry(p)
        if not e:
            continue
        canonical = e["canonical"]
        incoming_canonicals.add(canonical)
        prev = existing_by_canonical.get(canonical)
        # Preserve voice profiles the desktop UI doesn't round-trip: if this
        # save omits voiceEmbeddings but we have them on disk, carry them
        # forward so a desktop names edit never wipes phone-enrolled diarization
        # profiles. Done before the change-comparison so it doesn't bump the
        # timestamp spuriously.
        if not e.get("voiceEmbeddings") and prev and prev.get("voiceEmbeddings"):
            e["voiceEmbeddings"] = prev["voiceEmbeddings"]
        # Compare semantically (ignore timestamps when deciding "changed").
        prev_compare = {k: v for k, v in (prev or {}).items() if k not in ("lastModifiedAt", "deleted")} if prev else None
        new_compare = {k: v for k, v in e.items() if k not in ("lastModifiedAt", "deleted")}
        if prev_compare == new_compare and prev:
            # Unchanged — keep prior timestamp.
            e["lastModifiedAt"] = prev.get("lastModifiedAt", now)
        else:
            e["lastModifiedAt"] = now
        normalised.append(e)

    # Detect deletions: any existing canonical not in incoming gets a tombstone.
    for canonical, prev in existing_by_canonical.items():
        if canonical not in incoming_canonicals:
            normalised.append({
                "canonical": canonical,
                "aliases": prev.get("aliases", []),
                "short": prev.get("short"),
                "deleted": True,
                "lastModifiedAt": now,
            })

    # Preserve any existing tombstones we already had — last-write-wins keeps
    # the newer timestamp on the next sync.
    for prev in existing.get("people", []):
        if prev.get("deleted") and prev["canonical"] not in incoming_canonicals \
           and not any(n["canonical"] == prev["canonical"] for n in normalised):
            normalised.append(prev)

    canonical_data = {
        "lastModifiedAt": _recompute_top_level_timestamp(normalised),
        "people": _sort_people(normalised),
    }
    _write_raw(get_names_path(), canonical_data)
    return canonical_data


def prune_old_tombstones(max_age_days: int = 90) -> int:
    """Drop tombstones older than `max_age_days`. Returns count pruned."""
    data = read_names()
    cutoff = datetime.now(timezone.utc).timestamp() - max_age_days * 86400
    kept = []
    pruned = 0
    for p in data.get("people", []):
        if p.get("deleted"):
            try:
                ts = datetime.fromisoformat(p["lastModifiedAt"].replace("Z", "+00:00")).timestamp()
                if ts < cutoff:
                    pruned += 1
                    continue
            except Exception:
                pass
        kept.append(p)
    if pruned:
        write_names({"people": kept})
    return pruned
