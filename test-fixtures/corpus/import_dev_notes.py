#!/usr/bin/env python3
"""Pull REAL-VOICE notes out of a Skrift Dev store into a corpus-shaped folder that git ignores.

Usage: python3 test-fixtures/corpus/import_dev_notes.py <copy-of-memo_cloud.store> <recordings dir> <out dir> [since ISO]

Writes <out>/manifest.json + <out>/notes/NNN-<slug>/{note.json,audio.m4a,word_timings.json}
in exactly the shape generate.py writes, so CorpusSeed loads it with `-corpus <out>`.
These are the owner's own throwaway rambles (D81): local only, never committed, never his
real notes — the folder must sit under an ignored path (test-fixtures/dutch-rambles/).
"""
import json, os, re, shutil, sqlite3, sys, uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

store, rec_dir, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
since = sys.argv[4] if len(sys.argv) > 4 else "2026-09-22T00:00:00+01:00"
since_cd = datetime.fromisoformat(since).timestamp() - 978307200
con = sqlite3.connect(store)
rows = con.execute("""select ZID, ZAUDIOFILENAME, ZDURATION, ZRECORDEDAT, ZCREATEDAT, ZSIGNIFICANCE,
  ZTRANSCRIPTSTATUS, ZTRANSCRIPTCONFIDENCE, ZTRANSCRIPTUSEREDITED, ZTRANSCRIPT, ZTITLE, ZMETADATADATA, ZTAGS
  from ZMEMO where ZRECORDEDAT > ? and ZAUDIOFILENAME != '' and ZTRANSCRIPT is not null order by ZRECORDEDAT""", (since_cd,)).fetchall()
(out / "notes").mkdir(parents=True, exist_ok=True)
manifest = []
def cd(ts):
    return datetime.fromtimestamp(ts + 978307200, tz=timezone(timedelta(hours=1))).isoformat(timespec="seconds")
for i, r in enumerate(rows, 1):
    zid, audio, dur, rec, created, sig, st, conf, edited, text, title, meta, tags = r
    mid = str(uuid.UUID(bytes=zid)).upper() if isinstance(zid, bytes) else str(zid).upper()
    slug = f"dutch-real-{i:02d}"
    folder = out / "notes" / f"{i:03d}-{slug}"
    folder.mkdir(exist_ok=True)
    src = rec_dir / audio
    if src.exists(): shutil.copy(src, folder / "audio.m4a")
    wt = rec_dir / f"wt_{mid}.json"
    if wt.exists(): shutil.copy(wt, folder / "word_timings.json")
    try: metadata = json.loads(meta) if meta else {}
    except Exception: metadata = {}
    note = {"id": mid, "slug": slug, "kind": "voice", "lang": "nl", "shape": ["voice", "real-voice", "dutch", "mac-recorded"],
            "title": title, "recordedAt": cd(rec), "createdAt": cd(created) if created else cd(rec), "editedAt": None,
            "duration": round(dur, 2), "audio": "audio.m4a" if src.exists() else None, "transcript": text,
            "transcriptStatus": st, "transcriptConfidence": conf, "transcriptUserEdited": bool(edited),
            "transcriptMarkersInjected": False, "significance": sig or 0.0, "tags": [],
            "destination": "personal", "locked": False, "deletedAt": None, "trashSeenAt": None, "keptAt": None, "remindAt": None,
            "recordingDeviceID": "dev-mac", "annotationText": None, "metadata": metadata, "sharedContent": None, "photos": [],
            "sharedFile": None, "wordTimings": "word_timings.json" if wt.exists() else None, "diarization": None, "enhancement": None,
            "expect": {"note": "REAL Dutch voice (Tuur, throwaway ramble, D81). The synthetic Dutch fooled the model before; this is the honest test of Dutch copy-edit (near-echo) + paragraphs."}}
    (folder / "note.json").write_text(json.dumps(note, indent=2, ensure_ascii=False) + "\n")
    manifest.append({"index": i, "slug": slug, "id": mid, "kind": "voice", "lang": "nl", "shape": note["shape"], "folder": folder.name})
    print(f"{i}: {round(dur,1)}s conf={conf} words={len((text or '').split())} audio={'yes' if src.exists() else 'NO'} wt={'yes' if wt.exists() else 'no'} | {(text or '')[:70]}")
(out / "manifest.json").write_text(json.dumps({"generatedBy": "import_dev_notes.py (local only)", "count": len(manifest), "notes": manifest}, indent=2, ensure_ascii=False) + "\n")
print(f"{len(manifest)} notes → {out}")
