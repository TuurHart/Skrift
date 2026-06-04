"""
Sanitisation service
Handles text sanitisation with name linking and disambiguation
"""

import json
import re
import logging
from pathlib import Path
from models import ProcessingStatus
from utils.status_tracker import status_tracker
from config.settings import settings as app_settings, get_names_path

logger = logging.getLogger(__name__)


def process_sanitisation(file_id: str, text: str) -> dict:
    """
    Process sanitisation for a transcript.
    Returns dict with:
    - status: 'done', 'needs_disambiguation', or 'error'
    - result_content: sanitised text (if done)
    - ambiguous_occurrences: list of ambiguities (if needs_disambiguation)
    - error: error message (if error)
    """
    try:
        # Load sanitisation settings
        san_cfg = app_settings.get("sanitisation") or {}
        linking_cfg = san_cfg.get("linking", {})
        whole_word = bool(san_cfg.get("whole_word", True))
        
        # Names mapping via centralised store (timestamped schema, tombstones excluded).
        try:
            from utils import names_store
            people = [p for p in names_store.read_names().get('people', []) if not p.get('deleted')]
        except Exception as e:
            logger.warning(f"Failed to load names: {e}")
            people = []

        # Helper: ensure canonical is [[Name]]
        def to_link(canon: str) -> str:
            s = (canon or "").strip()
            if s.startswith("[[") and s.endswith("]]"):
                return s
            return f"[[{s}]]" if s else ""
        
        # Helper: check if match is outside existing [[...]] link
        def not_inside_link(s: str, start: int) -> bool:
            open_idx = s.rfind("[[", 0, start)
            if open_idx == -1:
                return True
            close_idx = s.find("]]", open_idx)
            return close_idx != -1 and close_idx < start
        
        # Sort people by canonical (case-insensitive, ignore brackets)
        def sort_key(entry):
            c = str(entry.get('canonical', '')).strip()
            if c.startswith('[[') and c.endswith(']]'):
                c = c[2:-2]
            return c.lower()
        try:
            people = sorted(people, key=sort_key)
        except Exception:
            pass
        
        # For each person, apply linking according to settings
        mode_all = (str(linking_cfg.get('mode', 'first')).lower() == 'all')
        avoid_inside = bool(linking_cfg.get('avoid_inside_links', True))
        preserve_poss = bool(linking_cfg.get('preserve_possessive', True))
        fmt = linking_cfg.get('format', {}) or {}
        style = str(fmt.get('style', 'wiki'))
        base_path = str(fmt.get('base_path', 'People'))

        def build_link(canon: str) -> str:
            core = canon[2:-2] if canon.startswith('[[') and canon.endswith(']]') else canon
            if style == 'wiki_with_path':
                return f"[[{base_path}/{core}|{core}]]"
            return f"[[{core}]]"

        # Build alias -> people mapping for ambiguity detection
        alias_map = {}
        for entry in people:
            aliases = entry.get('aliases', []) or []
            for a in aliases:
                al = str(a).strip().lower()
                if not al:
                    continue
                alias_map.setdefault(al, []).append(entry)

        # Ambiguous aliases = those that map to 2+ people. We no longer block
        # the pipeline on these; instead we leave them UNLINKED and record their
        # occurrences as data on the note so the review step can resolve them.
        ambiguous_aliases = {a for a, c in alias_map.items() if len(c) >= 2}

        ambiguous_occurrences = []
        for alias in ambiguous_aliases:
            candidates = alias_map[alias]
            # Find all occurrences of alias in text (case-insensitive)
            pat = re.compile(rf"\b{re.escape(alias)}\b", flags=re.IGNORECASE)
            for m in pat.finditer(text):
                # skip if inside an existing [[...]] link
                if avoid_inside and not not_inside_link(text, m.start()):
                    continue
                start = m.start(); end = m.end()
                ctx_before = text[max(0, start-40):start]
                ctx_after = text[end:min(len(text), end+40)]
                ambiguous_occurrences.append({
                    'alias': alias,
                    'offset': start,
                    'length': end - start,
                    'context_before': ctx_before,
                    'context_after': ctx_after,
                    'candidates': [
                        {
                            'id': (c.get('canonical') or '').strip(),
                            'canonical': (c.get('canonical') or '').strip(),
                            'short': (c.get('short') or '') or (((c.get('canonical') or '').strip()[2:-2]) if str(c.get('canonical') or '').startswith('[[') and str(c.get('canonical') or '').endswith(']]') else str(c.get('canonical') or '').strip()).split(' ')[0]
                        } for c in candidates
                    ]
                })

        # Process linking for UNAMBIGUOUS aliases only. Ambiguous aliases are
        # skipped (left as plain text) and carried as ambiguous_occurrences.
        for entry in people:
            canonical_raw = entry.get('canonical')
            aliases = entry.get('aliases', []) or []
            if not canonical_raw or not aliases:
                continue
            link_text = build_link(str(canonical_raw))
            if not link_text:
                continue

            # Derive short (unbracketed) first-name for subsequent mentions
            canon_core = canonical_raw[2:-2] if str(canonical_raw).startswith('[[') and str(canonical_raw).endswith(']]') else str(canonical_raw)
            short_override = str(entry.get('short') or '').strip()
            short_name = short_override or (canon_core.split()[0] if canon_core.strip() else '')

            # Prepare alias patterns
            alias_patterns = []
            for alias in aliases:
                alias = str(alias).strip()
                if not alias:
                    continue
                if alias.lower() in ambiguous_aliases:
                    continue  # leave ambiguous mentions unlinked, resolved at review
                poss_group = "(?P<poss>(?:'s|'s)?)" if preserve_poss else ""
                wb = "\\b" if whole_word else ""
                pattern = re.compile(rf"{wb}{re.escape(alias)}{wb}{poss_group}", flags=re.IGNORECASE)
                alias_patterns.append(pattern)
            
            if not alias_patterns:
                continue
            
            if mode_all:
                # Replace all occurrences with link (rarely used per current workflow)
                for pattern in alias_patterns:
                    def repl_all(m):
                        if avoid_inside and not not_inside_link(text, m.start()):
                            return m.group(0)
                        poss_local = m.group('poss') if preserve_poss else ''
                        return f"{link_text}{poss_local or ''}"
                    text = pattern.sub(repl_all, text)
            else:
                # FIRST occurrence across all aliases -> earliest wins; subsequent → short name (unbracketed)
                earliest = None  # (start, end, pattern)
                for pattern in alias_patterns:
                    m = pattern.search(text)
                    if m and (not avoid_inside or not_inside_link(text, m.start())):
                        if earliest is None or m.start() < earliest[0]:
                            earliest = (m.start(), m.end(), pattern)
                if earliest is not None:
                    start, end, first_pattern = earliest
                    replaced_once = False
                    def repl_first(m):
                        nonlocal replaced_once
                        if replaced_once:
                            return m.group(0)
                        if m.start() == start:
                            replaced_once = True
                            poss_local = m.group('poss') if preserve_poss else ''
                            return f"{link_text}{poss_local or ''}"
                        return m.group(0)
                    text = first_pattern.sub(repl_first, text, count=1)
                    
                    # Subsequent replacements: replace all aliases with short_name outside links
                    if short_name:
                        for pattern in alias_patterns:
                            def repl_rest(m):
                                # Skip the exact first occurrence region and any text inside links
                                if avoid_inside and not not_inside_link(text, m.start()):
                                    return m.group(0)
                                if m.start() == start:
                                    return m.group(0)
                                poss_local = m.group('poss') if preserve_poss else ''
                                return f"{short_name}{poss_local or ''}"
                            text = pattern.sub(repl_rest, text)
        
        return {
            'status': 'done',
            'result_content': text,
            'ambiguous_occurrences': ambiguous_occurrences,
        }

    except Exception as e:
        return {
            'status': 'error',
            'error': str(e)
        }


def resolve_name_disambiguation(file_id: str, text: str, decisions: list) -> dict:
    """
    Resolve ambiguous alias occurrences using user decisions.
    
    Args:
        file_id: file identifier
        text: original transcript text
        decisions: list of {alias, offset, person_id, apply_to_remaining?}
    
    Returns:
        dict with:
        - status: 'done' or 'error'
        - result_content: sanitised text (if done)
        - error: error message (if error)
    """
    try:
        # Load names
        san_cfg = app_settings.get("sanitisation") or {}
        linking_cfg = san_cfg.get("linking", {})
        whole_word = bool(san_cfg.get("whole_word", True))
        avoid_inside = bool(linking_cfg.get('avoid_inside_links', True))
        preserve_poss = bool(linking_cfg.get('preserve_possessive', True))

        names_cfg_path = get_names_path()
        people: list = []
        if names_cfg_path.exists():
            try:
                cfg = json.loads(names_cfg_path.read_text(encoding='utf-8'))
                if isinstance(cfg, dict) and 'people' in cfg:
                    people = cfg.get('people') or []
                elif isinstance(cfg, dict) and 'entries' in cfg:
                    people = cfg.get('entries') or []
                elif isinstance(cfg, list):
                    people = cfg
            except Exception:
                people = []

        # Build alias -> people
        alias_map = {}
        for entry in people:
            for a in (entry.get('aliases') or []):
                al = str(a).strip().lower()
                if al:
                    alias_map.setdefault(al, []).append(entry)

        # Turn decisions into alias->chosen person and per-offset overrides
        alias_choice = {}
        per_offset = {}  # (alias_lower, offset) -> person_canonical
        for d in decisions:
            al = str(d.get('alias') or '').strip().lower()
            off = int(d.get('offset', -1))
            pid = str(d.get('person_id') or '').strip()
            apply_all = bool(d.get('apply_to_remaining'))
            if not al or not pid:
                continue
            if apply_all:
                alias_choice[al] = pid
            if off >= 0:
                per_offset[(al, off)] = pid

        # Prepare helpers
        def to_link(canon: str) -> str:
            s = (canon or "").strip()
            if s.startswith("[[") and s.endswith("]]"):
                return s
            return f"[[{s}]]" if s else ""
        
        def not_inside_link(s: str, start: int) -> bool:
            open_idx = s.rfind("[[", 0, start)
            if open_idx == -1:
                return True
            close_idx = s.find("]]", open_idx)
            return close_idx != -1 and close_idx < start

        # Build full match list across all aliases with assigned person per decisions
        matches = []  # list of {start,end,alias,person_id,poss}
        for entry in people:
            canonical_raw = entry.get('canonical')
            aliases = entry.get('aliases', []) or []
            if not canonical_raw or not aliases:
                continue
            for alias in aliases:
                al = str(alias).strip()
                if not al:
                    continue
                wb = "\\b" if whole_word else ""
                poss_group = "(?P<poss>(?:'s|'s)?)" if preserve_poss else ""
                pat = re.compile(rf"{wb}{re.escape(al)}{wb}{poss_group}", flags=re.IGNORECASE)
                for m in pat.finditer(text):
                    s = m.start(); e = m.end()
                    if avoid_inside and not not_inside_link(text, s):
                        continue
                    al_low = al.lower()
                    # Determine assigned person id for this occurrence
                    pid = per_offset.get((al_low, s)) or alias_choice.get(al_low)
                    # If still ambiguous and maps to multiple people and no choice, skip for now
                    # Unambiguous alias (only one person in alias_map) -> auto-assign
                    if not pid:
                        cand = alias_map.get(al_low) or []
                        if len(cand) == 1:
                            pid = (cand[0].get('canonical') or '').strip()
                    if pid:
                        matches.append({'start': s, 'end': e, 'alias': al_low, 'person_id': pid, 'poss': (m.group('poss') if preserve_poss else '')})

        # Group by person and decide first (earliest) occurrence per person as canonical
        by_person = {}
        for m in matches:
            by_person.setdefault(m['person_id'], []).append(m)
        for pid in by_person:
            by_person[pid].sort(key=lambda x: x['start'])

        # Prepare replacement text per match
        repls = []
        # Build helpers: person canon + short
        person_map = { (p.get('canonical') or '').strip(): p for p in people }
        def canon_and_short(pid: str):
            p = person_map.get(pid) or {}
            canon = (p.get('canonical') or '').strip()
            core = canon[2:-2] if canon.startswith('[[') and canon.endswith(']]') else canon
            short = (p.get('short') or '').strip() or (core.split()[0] if core else '')
            return canon, short

        for pid, lst in by_person.items():
            canon, short = canon_and_short(pid)
            link_text = to_link(canon)
            for i, m in enumerate(lst):
                if i == 0:
                    new = f"{link_text}{m['poss'] or ''}"
                else:
                    new = f"{short}{m['poss'] or ''}"
                repls.append( (m['start'], m['end'], new) )

        # Apply replacements using a single pass builder to avoid index drift and partial overlaps
        repls.sort(key=lambda x: x[0])  # ascending by start
        new_buf = []
        cur = 0
        for s, e, new in repls:
            if s < cur:
                # Overlap: skip this replacement as a safety (should not happen with our grouping)
                continue
            new_buf.append(text[cur:s])
            new_buf.append(new)
            cur = e
        new_buf.append(text[cur:])
        text = ''.join(new_buf)

        return {
            'status': 'done',
            'result_content': text
        }

    except Exception as e:
        return {
            'status': 'error',
            'error': str(e)
        }
