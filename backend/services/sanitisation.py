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


def apply_resolved_names(text: str, decisions: list) -> str:
    """Apply review-time choices for ambiguous aliases to the (already sanitised) body.

    decisions: [{ 'alias': str, 'canonical': '[[Full Name]]', 'short': 'Nick' }]
    For each decided alias, link its first remaining plain occurrence to the
    canonical [[link]] and replace later mentions with the short name — mirroring
    the auto-linker's first-mention rule. Occurrences already inside [[...]] are
    left alone, so prior links and the user's edits are preserved. Aliases the
    user left unresolved are simply absent from `decisions` → they stay plain.
    """
    san_cfg = app_settings.get("sanitisation") or {}
    linking_cfg = san_cfg.get("linking", {}) or {}
    whole_word = bool(san_cfg.get("whole_word", True))
    avoid_inside = bool(linking_cfg.get('avoid_inside_links', True))
    preserve_poss = bool(linking_cfg.get('preserve_possessive', True))

    def not_inside_link(s: str, start: int) -> bool:
        open_idx = s.rfind("[[", 0, start)
        if open_idx == -1:
            return True
        close_idx = s.find("]]", open_idx)
        return close_idx != -1 and close_idx < start

    for d in (decisions or []):
        alias = str(d.get('alias') or '').strip()
        canon = str(d.get('canonical') or '').strip()
        if not alias or not canon:
            continue  # no choice / "leave as plain text" → skip
        link_text = canon if (canon.startswith('[[') and canon.endswith(']]')) else f"[[{canon}]]"
        core = canon[2:-2] if (canon.startswith('[[') and canon.endswith(']]')) else canon
        short = str(d.get('short') or '').strip() or (core.split()[0] if core.strip() else alias)

        wb = "\\b" if whole_word else ""
        poss_group = "(?P<poss>(?:'s|’s)?)" if preserve_poss else ""
        pattern = re.compile(rf"{wb}{re.escape(alias)}{wb}{poss_group}", flags=re.IGNORECASE)

        eligible = [m for m in pattern.finditer(text)
                    if (not avoid_inside or not_inside_link(text, m.start()))]
        if not eligible:
            continue
        out = []
        cur = 0
        for i, m in enumerate(eligible):
            out.append(text[cur:m.start()])
            poss_local = (m.group('poss') if preserve_poss else '') or ''
            out.append(f"{link_text}{poss_local}" if i == 0 else f"{short}{poss_local}")
            cur = m.end()
        out.append(text[cur:])
        text = ''.join(out)

    return text
