#!/usr/bin/env python3
"""Twin scan — find phone↔Mac duplication candidates for Shared/ extraction.

The mechanical half of the shared-code-first rule: enumerates the places where
SkriftMobile and SkriftDesktop carry the same thing twice, ranked by risk.
Run any time; triage hits into backlog like the SharedKit dedup wave.

    python3 tools/twin-scan.py            # full report
    python3 tools/twin-scan.py --terse    # counts only

Three detectors (cheap, high-signal for THIS codebase — twins historically kept
identical names: SignificanceCircles, VoiceMatcher, SpeakerTranscript…):
  1. FILE twins    — same .swift basename in both apps.
  2. TYPE twins    — same top-level type name declared in both apps.
  3. STRING twins  — the same user-facing string literal (≥ 18 chars) in both
                     apps (the "Journal" vs "Review" label lesson).
Shared/ is the fix target, so anything already under Shared/ is excluded.
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

# --clones mode: normalized-token shingling. Catches code that was copied and
# ADAPTED (identifiers renamed, values tweaked) — the duplication the name-twin
# detectors can't see. Identifiers→I, numbers→N, strings→S; 30-token windows
# hashed; file PAIRS sharing many windows across the app boundary get reported.
SWIFT_KEYWORDS = {
    "func", "var", "let", "if", "else", "guard", "return", "for", "while", "switch",
    "case", "class", "struct", "enum", "actor", "protocol", "extension", "import",
    "init", "self", "try", "await", "async", "throws", "catch", "defer", "in",
    "where", "nil", "true", "false", "private", "static", "final", "some", "default"}
TOKEN_RE = re.compile(r'"(?:[^"\\]|\\.)*"|[A-Za-z_]\w*|\d[\d._]*|[{}()\[\].,:;?!<>=+\-*/&|^%~@#]')
SHINGLE = 30

def normalized_tokens(text: str):
    out = []
    for tok in TOKEN_RE.findall(text):
        if tok.startswith('"'):
            out.append("S")
        elif tok[0].isdigit():
            out.append("N")
        elif tok[0].isalpha() or tok[0] == "_":
            out.append(tok if tok in SWIFT_KEYWORDS else "I")
        else:
            out.append(tok)
    return out

def clone_scan():
    shingle_map = defaultdict(lambda: {"mobile": set(), "desktop": set()})
    for app, root in APPS.items():
        for p in swift_files(root):
            if "Tests" in p.parts[-2] or p.name.endswith("Tests.swift"):
                continue   # parity tests are deliberate twins
            toks = normalized_tokens(p.read_text(errors="ignore"))
            rel = str(p.relative_to(ROOT))
            for i in range(0, max(0, len(toks) - SHINGLE), 5):
                shingle_map[hash(tuple(toks[i:i + SHINGLE]))][app].add(rel)
    pair_hits = defaultdict(int)
    for sides in shingle_map.values():
        for m in sides["mobile"]:
            for d in sides["desktop"]:
                pair_hits[(m, d)] += 1
    ranked = sorted(pair_hits.items(), key=lambda kv: -kv[1])
    print("── CLONE candidates (renamed/adapted copies — normalized-token shingles) ──")
    shown = 0
    for (m, d), hits in ranked:
        if hits < 8:
            break
        print(f"  {hits:4d} shared windows\n       {m}\n       {d}")
        shown += 1
        if shown >= 15:
            break
    if not shown:
        print("  none above threshold")

ROOT = Path(__file__).resolve().parent.parent / "Skrift_Native"
APPS = {"mobile": ROOT / "SkriftMobile", "desktop": ROOT / "SkriftDesktop"}
EXCLUDE_PARTS = {"build", "build-device", "build-release", ".git", "SourcePackages",
                 "SkriftMobileUITests", "SkriftDesktopUITests"}

TYPE_RE = re.compile(r"^(?:public |internal |final |@\w+ )*(?:final )?(class|struct|enum|actor|protocol)\s+([A-Z]\w+)", re.M)
STRING_RE = re.compile(r'"([^"\\\n]{18,})"')

def swift_files(app_root: Path):
    for p in app_root.rglob("*.swift"):
        if not EXCLUDE_PARTS.intersection(p.parts):
            yield p

def collect(app_root: Path):
    files, types, strings = {}, defaultdict(list), defaultdict(list)
    for p in swift_files(app_root):
        rel = p.relative_to(ROOT)
        files[p.name] = rel
        text = p.read_text(errors="ignore")
        for _, name in TYPE_RE.findall(text):
            types[name].append(rel)
        for lit in STRING_RE.findall(text):
            # Skip likely non-UI strings (paths, keys, format-ish, interpolation).
            if "\\(" in lit or "/" in lit or lit.startswith("com."):
                continue
            strings[lit].append(rel)
    return files, types, strings

def main():
    if "--clones" in sys.argv:
        clone_scan()
        return
    terse = "--terse" in sys.argv
    m_files, m_types, m_strings = collect(APPS["mobile"])
    d_files, d_types, d_strings = collect(APPS["desktop"])

    file_twins = sorted(set(m_files) & set(d_files))
    type_twins = sorted(set(m_types) & set(d_types))
    string_twins = sorted(set(m_strings) & set(d_strings))

    print(f"twin-scan · {len(file_twins)} file twins · {len(type_twins)} type twins · {len(string_twins)} string twins\n")
    if terse:
        return

    if file_twins:
        print("── FILE twins (same basename in both apps — the highest-risk drift) ──")
        for name in file_twins:
            print(f"  {name}\n    ↳ {m_files[name]}\n    ↳ {d_files[name]}")
        print()
    if type_twins:
        print("── TYPE twins (same top-level type declared twice) ──")
        for name in type_twins:
            paths = [str(p) for p in (m_types[name] + d_types[name])]
            print(f"  {name}")
            for p in paths[:4]:
                print(f"    ↳ {p}")
        print()
    if string_twins:
        print("── STRING twins (same user-facing literal in both apps) ──")
        for lit in string_twins:
            print(f'  "{lit[:70]}"')
            for p in (m_strings[lit][:1] + d_strings[lit][:1]):
                print(f"    ↳ {p}")
        print()

if __name__ == "__main__":
    main()
