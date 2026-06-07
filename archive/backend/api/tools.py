"""Backfill metadata tool — scan and update Obsidian vault frontmatter."""

import os
import re
from pathlib import Path
from typing import List, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/api/tools", tags=["tools"])

# ── Models ──────────────────────────────────────────────────

class BackfillRequest(BaseModel):
    vault_path: str
    fields: List[str]
    recursive: bool = True

class FileToUpdate(BaseModel):
    relative_path: str
    absolute_path: str
    missing_fields: List[str]

class ScanResult(BaseModel):
    total_files: int
    already_complete: int
    to_update: List[FileToUpdate]
    no_frontmatter: int

class ApplyDetail(BaseModel):
    file: str
    status: str  # "updated" or "error"
    error: Optional[str] = None

class ApplyResult(BaseModel):
    updated: int
    errors: int
    details: List[ApplyDetail]

# ── YAML helpers ────────────────────────────────────────────

FRONTMATTER_RE = re.compile(r'^---\s*\n(.*?)\n---\s*\n', re.DOTALL)

# Nested fields need special handling
DAYLIGHT_SUBFIELDS = ['sunrise', 'sunset', 'hoursOfLight']

def parse_frontmatter_fields(fm_text: str) -> set:
    """Extract top-level field names from YAML frontmatter text.

    Handles various formats:
    - key: value
    - key: "value"
    - key:
    - key: (empty)
    Also detects nested blocks like daylight:
    """
    fields = set()
    for line in fm_text.split('\n'):
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        # Top-level field: doesn't start with space/tab
        if not line[0].isspace() and ':' in stripped:
            key = stripped.split(':')[0].strip()
            if key:
                fields.add(key)
    return fields

def generate_missing_yaml(missing_fields: List[str]) -> str:
    """Generate YAML lines for missing fields with empty placeholder values."""
    lines = []
    for f in missing_fields:
        if f == 'daylight':
            lines.append('daylight:')
            lines.append('  sunrise: ""')
            lines.append('  sunset: ""')
            lines.append('  hoursOfLight: ""')
        else:
            lines.append(f'{f}: ""')
    return '\n'.join(lines)

def insert_fields_into_frontmatter(content: str, missing_fields: List[str]) -> str:
    """Insert missing fields into existing YAML frontmatter.

    Adds them just before the closing --- line.
    Preserves all existing content exactly as-is.
    """
    match = FRONTMATTER_RE.match(content)
    if not match:
        return content  # No frontmatter, skip

    fm_text = match.group(1)
    after_fm = content[match.end():]

    new_yaml = generate_missing_yaml(missing_fields)

    # Insert new fields at the end of frontmatter (before closing ---)
    updated_fm = fm_text.rstrip() + '\n' + new_yaml

    return f'---\n{updated_fm}\n---\n{after_fm}'

# ── Endpoints ───────────────────────────────────────────────

def find_md_files(vault_path: Path, recursive: bool) -> List[Path]:
    """Find all .md files in the vault."""
    if recursive:
        return sorted(vault_path.rglob('*.md'))
    else:
        return sorted(vault_path.glob('*.md'))

@router.post("/backfill/scan", response_model=ScanResult)
async def scan_vault(req: BackfillRequest):
    vault = Path(req.vault_path).expanduser()
    if not vault.is_dir():
        raise HTTPException(400, f"Directory not found: {req.vault_path}")

    if not req.fields:
        raise HTTPException(400, "No fields selected")

    md_files = find_md_files(vault, req.recursive)

    total = len(md_files)
    complete = 0
    no_fm = 0
    to_update: List[FileToUpdate] = []

    for f in md_files:
        try:
            content = f.read_text(encoding='utf-8')
        except Exception:
            continue

        match = FRONTMATTER_RE.match(content)
        if not match:
            no_fm += 1
            continue

        existing = parse_frontmatter_fields(match.group(1))
        missing = [field for field in req.fields if field not in existing]

        if not missing:
            complete += 1
        else:
            to_update.append(FileToUpdate(
                relative_path=str(f.relative_to(vault)),
                absolute_path=str(f),
                missing_fields=missing,
            ))

    return ScanResult(
        total_files=total,
        already_complete=complete,
        to_update=to_update,
        no_frontmatter=no_fm,
    )

@router.post("/backfill/apply", response_model=ApplyResult)
async def apply_backfill(req: BackfillRequest):
    # First scan to find what needs updating
    vault = Path(req.vault_path).expanduser()
    if not vault.is_dir():
        raise HTTPException(400, f"Directory not found: {req.vault_path}")

    md_files = find_md_files(vault, req.recursive)

    updated = 0
    errors = 0
    details: List[ApplyDetail] = []

    for f in md_files:
        rel_path = str(f.relative_to(vault))
        try:
            content = f.read_text(encoding='utf-8')
            match = FRONTMATTER_RE.match(content)
            if not match:
                continue

            existing = parse_frontmatter_fields(match.group(1))
            missing = [field for field in req.fields if field not in existing]

            if not missing:
                continue

            new_content = insert_fields_into_frontmatter(content, missing)
            f.write_text(new_content, encoding='utf-8')
            updated += 1
            details.append(ApplyDetail(file=rel_path, status="updated"))
        except Exception as e:
            errors += 1
            details.append(ApplyDetail(file=rel_path, status="error", error=str(e)))

    return ApplyResult(updated=updated, errors=errors, details=details)
