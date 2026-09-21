#!/usr/bin/env python3
"""Build the synthetic note corpus under test-fixtures/corpus/notes/.

Every note is authored in src/notes_*.py as a small dict; this script turns each one
into a folder the apps can seed (Shared/Corpus/CorpusSeed.swift):

    notes/NNN-slug/
      note.json          the Memo fields + metadata / sharedContent blobs (see README)
      audio.m4a          spoken audio for voice notes (macOS `say` → AAC)
      photo_NNN.jpg      generated pictures (PIL)
      word_timings.json  uniform per-word timings over the audio (synthetic)
      diar.json          speaker segments for conversations (synthetic)
      document.pdf       for file captures

Deterministic: ids are uuid5 of the slug, dates are fixed, audio is regenerated only
when the transcript text changed (hash in .audio-hash). Run from the repo root:

    python3 test-fixtures/corpus/generate.py            # everything
    python3 test-fixtures/corpus/generate.py --no-audio # skip `say` (fast)
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "src"))

from roster import ROSTER, NAMESPACE  # noqa: E402
import notes_typed, notes_voice, notes_pictures, notes_captures, notes_other  # noqa: E402

NOTES = (
    notes_typed.NOTES + notes_voice.NOTES + notes_pictures.NOTES
    + notes_captures.NOTES + notes_other.NOTES
)

OUT = HERE / "notes"
BASE = datetime(2026, 9, 20, 18, 0, tzinfo=timezone(timedelta(hours=1)))  # Europe/Lisbon, DST
MARKER = re.compile(r"\[\[img_(\d{3})\]\]")
TURN = re.compile(r"^\*\*([^*]+):\*\*\s*", re.M)
LINK = re.compile(r"\[\[memo:([0-9A-Fa-f-]{36})\|[^\]]*\]\]")

VOICE = {"en": "Daniel", "nl": "Ellen", "mix": "Ellen"}


def nid(slug: str) -> str:
    return str(uuid.uuid5(NAMESPACE, slug)).upper()


def iso(dt: datetime) -> str:
    return dt.isoformat(timespec="seconds")


def spoken_text(transcript: str) -> str:
    t = MARKER.sub(" ", transcript)
    t = TURN.sub("", t)
    t = LINK.sub(lambda m: "the other note", t)
    t = re.sub(r"\[\[([^\]|]+)(\|[^\]]*)?\]\]", r"\1", t)   # wikilinks → plain
    t = re.sub(r"^[#>\-\s]+", "", t, flags=re.M)             # markdown marks
    t = re.sub(r"\[[ x]\]", "", t)
    t = re.sub(r"https?://\S+", "a link", t)
    return re.sub(r"\s+", " ", t).strip()


def words_of(transcript: str):
    return spoken_text(transcript).split()


def say(text: str, voice: str, out: Path) -> float:
    """Render `text` with macOS `say` to AAC m4a at `out`; returns the duration."""
    aiff = out.with_suffix(".aiff")
    subprocess.run(["say", "-v", voice, "-r", "185", "-o", str(aiff), text], check=True)
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "48000", str(aiff), str(out)],
                   check=True, capture_output=True)
    aiff.unlink()
    return duration_of(out)


def duration_of(path: Path) -> float:
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                        "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True)
    return round(float(r.stdout.strip()), 2)


def say_conversation(turns, out: Path) -> tuple[float, list[float]]:
    """One m4a from alternating voices; returns (total, per-turn durations)."""
    parts, durs = [], []
    for i, (speaker_idx, text) in enumerate(turns):
        p = out.parent / f".turn{i}.m4a"
        voice = ["Daniel", "Ellen", "Eddy (English (UK))"][speaker_idx % 3]
        durs.append(say(text, voice, p))
        parts.append(p)
    lst = out.parent / ".concat.txt"
    lst.write_text("".join(f"file '{p.name}'\n" for p in parts))
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(lst),
                    "-c", "copy", str(out)], check=True, cwd=out.parent)
    for p in parts:
        p.unlink()
    lst.unlink()
    return duration_of(out), durs


def uniform_timings(words, duration: float, start=0.0):
    n = max(1, len(words))
    step = duration / n
    return [{"word": w, "start": round(start + i * step, 3), "end": round(start + (i + 1) * step - 0.02, 3)}
            for i, w in enumerate(words)]


def make_photo(path: Path, label: str, seed: int, portrait=False, big_text=None):
    from PIL import Image, ImageDraw, ImageFont
    w, h = (1080, 1440) if portrait else (1600, 1200)
    rnd = hashlib.sha256(str(seed).encode()).digest()
    bg = (60 + rnd[0] % 120, 60 + rnd[1] % 120, 60 + rnd[2] % 120)
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    # a few shapes so the thumbnails are distinguishable at a glance
    for k in range(4):
        x, y = rnd[3 + k] * w // 255, rnd[7 + k] * h // 255
        r = 120 + rnd[11 + k] % 200
        d.ellipse([x - r, y - r, x + r, y + r], fill=(min(255, bg[0] + 50), bg[1], min(255, bg[2] + 60)))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 64)
        big = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 150)
    except OSError:
        font = big = ImageFont.load_default()
    d.text((60, h - 140), label, fill="white", font=font)
    if big_text:
        d.rectangle([40, 200, w - 40, 420], fill="white")
        d.text((80, 220), big_text, fill="black", font=big)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "JPEG", quality=85)


def make_pdf(path: Path, title: str, body: str):
    from PIL import Image, ImageDraw, ImageFont
    img = Image.new("RGB", (1240, 1754), "white")
    d = ImageDraw.Draw(img)
    try:
        f1 = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 48)
        f2 = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28)
    except OSError:
        f1 = f2 = ImageFont.load_default()
    d.text((100, 120), title, fill="black", font=f1)
    y = 240
    for line in body.split("\n"):
        d.text((100, y), line, fill="black", font=f2)
        y += 40
    img.save(path, "PDF")


def build(note: dict, index: int, with_audio: bool):
    slug = note["slug"]
    folder = OUT / f"{index:03d}-{slug}"
    folder.mkdir(parents=True, exist_ok=True)
    memo_id = nid(slug)
    kind = note.get("kind", "typed")
    transcript = note.get("transcript")
    recorded = note.get("recordedAt") or iso(BASE - timedelta(hours=17 * index + 3))
    lang = note.get("lang", "en")

    out = {
        "id": memo_id,
        "slug": slug,
        "kind": kind,
        "lang": lang,
        "shape": note.get("shape", []),
        "title": note.get("title"),
        "recordedAt": recorded,
        "createdAt": note.get("createdAt", recorded),
        "editedAt": note.get("editedAt"),
        "duration": 0,
        "audio": None,
        "transcript": transcript,
        "transcriptStatus": note.get("transcriptStatus", "done" if transcript is not None else "pending"),
        "transcriptConfidence": note.get("transcriptConfidence", 0.94 if kind in ("voice", "conversation", "quote", "video") else None),
        "transcriptUserEdited": note.get("transcriptUserEdited", False),
        "transcriptMarkersInjected": note.get("transcriptMarkersInjected", bool(MARKER.search(transcript or ""))),
        "significance": note.get("significance", 0.5),
        "tags": note.get("tags", []),
        "destination": note.get("destination", "personal"),
        "locked": note.get("locked", False),
        "deletedAt": note.get("deletedAt"),
        "trashSeenAt": note.get("trashSeenAt"),
        "keptAt": note.get("keptAt"),
        "remindAt": note.get("remindAt"),
        "recordingDeviceID": note.get("recordingDeviceID"),
        "annotationText": note.get("annotationText"),
        "metadata": dict(note.get("metadata", {})),
        "sharedContent": note.get("sharedContent"),
        "photos": [],
        "sharedFile": None,
        "wordTimings": None,
        "diarization": None,
        "enhancement": note.get("enhancement"),
        "expect": note.get("expect", {}),
    }
    meta = out["metadata"]
    meta.setdefault("capturedAt", recorded)
    meta.setdefault("tags", out["tags"])
    if kind == "typed":
        meta.setdefault("mediaSource", "typed")
    if kind == "video":
        meta.setdefault("sourceType", "video")

    # --- audio + timings -------------------------------------------------------------
    has_audio = kind in ("voice", "conversation", "quote", "video") and not note.get("noAudio")
    duration = note.get("duration", 0)
    if has_audio:
        audio = folder / "audio.m4a"
        out["audio"] = "audio.m4a"
        text_for_speech = spoken_text(transcript or note.get("speech", ""))
        hfile = folder / ".audio-hash"
        h = hashlib.sha256((text_for_speech + kind).encode()).hexdigest()
        stale = not audio.exists() or (hfile.read_text() if hfile.exists() else "") != h
        if with_audio and stale:
            if kind == "conversation":
                turns = [(t["speaker"], t["text"]) for t in note["turns"]]
                duration, turn_durs = say_conversation(turns, audio)
                note["_turn_durs"] = turn_durs
            else:
                duration = say(text_for_speech or "silence", VOICE[lang], audio)
            hfile.write_text(h)
        elif audio.exists():
            duration = duration_of(audio)
        else:
            duration = duration or max(4.0, len(text_for_speech.split()) / 2.6)
        out["duration"] = duration
        if out["transcriptStatus"] == "done" and transcript:
            if kind == "conversation":
                words, segs, t = [], [], 0.0
                per = note.get("_turn_durs") or [duration * len(x["text"].split()) / max(1, len(words_of(transcript))) for x in note["turns"]]
                for turn, td in zip(note["turns"], per):
                    tw = turn["text"].split()
                    words += uniform_timings(tw, td, start=t)
                    segs.append({"speaker": turn["speaker"], "start": round(t, 3), "end": round(t + td, 3)})
                    t += td
                (folder / "word_timings.json").write_text(json.dumps(words, indent=0))
                slot_names = note.get("slotNames", {})
                (folder / "diar.json").write_text(json.dumps({
                    "segments": segs, "slotNames": slot_names,
                    "turnSlots": [x["speaker"] for x in note["turns"]]}, indent=0))
                out["wordTimings"], out["diarization"] = "word_timings.json", "diar.json"
            else:
                words = words_of(transcript)
                (folder / "word_timings.json").write_text(json.dumps(uniform_timings(words, duration), indent=0))
                out["wordTimings"] = "word_timings.json"
    else:
        out["duration"] = duration

    # --- photos ---------------------------------------------------------------------
    photos = note.get("photos", [])
    manifest = []
    words = words_of(transcript or "")
    for i, p in enumerate(photos, start=1):
        fname = f"photo_{memo_id}_{i:03d}.jpg"
        local = f"photo_{i:03d}.jpg"
        if not p.get("missingFile"):
            make_photo(folder / local, f"{slug} · {i}", seed=index * 10 + i,
                       portrait=p.get("portrait", False), big_text=p.get("bigText"))
            out["photos"].append({"filename": fname, "file": local})
        if "offsetSeconds" in p:
            off = p["offsetSeconds"]
        elif "atWord" in p and words and out["duration"]:
            off = round(out["duration"] * p["atWord"] / len(words), 2)
        else:
            off = 0
        entry = {"filename": fname, "offsetSeconds": off}
        if "text" in p:
            entry["text"] = p["text"]
        if not p.get("noManifest"):
            manifest.append(entry)
    if manifest:
        meta["imageManifest"] = manifest

    # --- shared file (PDF etc.) ------------------------------------------------------
    if note.get("sharedFile"):
        sf = note["sharedFile"]
        local = sf["file"]
        if local.endswith(".pdf"):
            make_pdf(folder / local, sf.get("title", slug), sf.get("body", ""))
        else:
            (folder / local).write_text(sf.get("body", ""))
        out["sharedFile"] = {"file": local, "filename": sf["filename"]}
        sc = dict(out["sharedContent"] or {})
        sc.setdefault("filePath", sf["filename"])
        sc.setdefault("fileName", sf.get("displayName", sf["filename"]))
        out["sharedContent"] = sc

    (folder / "note.json").write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    return {"index": index, "slug": slug, "id": memo_id, "kind": kind, "lang": lang,
            "shape": out["shape"], "folder": folder.name}


def main():
    with_audio = "--no-audio" not in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    slugs = [n["slug"] for n in NOTES]
    dupes = {s for s in slugs if slugs.count(s) > 1}
    assert not dupes, f"duplicate slugs: {dupes}"
    rows = [build(n, i + 1, with_audio) for i, n in enumerate(NOTES)]
    (HERE / "manifest.json").write_text(json.dumps({
        "generatedBy": "test-fixtures/corpus/generate.py",
        "count": len(rows), "notes": rows}, indent=2, ensure_ascii=False) + "\n")
    (HERE / "names.json").write_text(json.dumps(ROSTER, indent=2, ensure_ascii=False) + "\n")
    kinds = {}
    for r in rows:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    print(f"{len(rows)} notes → {OUT}")
    print("  " + ", ".join(f"{k}: {v}" for k, v in sorted(kinds.items())))


if __name__ == "__main__":
    main()
