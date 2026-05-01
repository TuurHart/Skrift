"""
Names sync API for the mobile app.

The mobile app keeps a local copy of names.json. On every memo-sync it does a
cheap meta GET to decide whether to do the expensive merge, then GETs the full
file, merges with its local copy by canonical name (last-write-wins per entry
using `lastModifiedAt`), and PUTs the merged result back.

The desktop UI continues to use `/api/config/names` (POST) which has its own
"bump only changed entries" semantics. Both endpoints share the same
underlying file via `utils.names_store`.
"""

import logging
from typing import List, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from utils import names_store

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/meta")
async def get_names_meta():
    """Return only `{ lastModifiedAt }` so callers can short-circuit a sync
    when nothing has changed since their last pull."""
    try:
        data = names_store.read_names()
        return {"lastModifiedAt": data.get("lastModifiedAt")}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read names meta: {e}")


@router.get("")
async def get_names():
    """Return the full names.json contents (timestamped schema)."""
    try:
        return names_store.read_names()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read names: {e}")


class Person(BaseModel):
    canonical: str = Field(..., min_length=1)
    aliases: List[str] = Field(default_factory=list)
    short: Optional[str] = None
    lastModifiedAt: Optional[str] = None
    deleted: bool = False


class NamesPayload(BaseModel):
    lastModifiedAt: Optional[str] = None
    people: List[Person]


@router.put("")
async def put_names(payload: NamesPayload):
    """Replace the entire names.json with the caller's merged payload.

    Caller is responsible for the merge — server writes verbatim. Top-level
    `lastModifiedAt` is recomputed from `people[].lastModifiedAt` regardless
    of what the caller sent, to keep it authoritative.
    """
    try:
        result = names_store.write_names(payload.model_dump())
        try:
            pruned = names_store.prune_old_tombstones(max_age_days=90)
            if pruned:
                logger.info(f"[names] pruned {pruned} old tombstones")
                result = names_store.read_names()
        except Exception as e:
            logger.warning(f"[names] tombstone prune failed: {e}")
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write names: {e}")
