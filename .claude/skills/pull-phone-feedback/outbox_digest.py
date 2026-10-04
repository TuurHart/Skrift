#!/usr/bin/env python3
"""Digest a pulled FeedbackKit outbox folder (Q308).

The folder is what `xcrun devicectl device copy from ... --source
"Library/Application Support/FeedbackKit/outbox"` brings down. Per note:
  <id>.json   NoteRecord: id, createdAt (unix s), meta (a JSON STRING), ms, hasAudio,
              text, screenshotCount, questionID, state (pending|failed), attempts,
              lastStatus, lastError
  <id>.m4a    voice note (AAC, 16 kHz mono, max 3:00)
  <id>.png / <id>.2.png   screenshots
meta (JSON v1): id, install_id, ms, question_id, screen, app_version, build, device, os,
recorded_at.

Usage:
  outbox_digest.py <outbox-dir> [--no-asr] [--out FILE]
  outbox_digest.py --self-test

ASR: each <id>.m4a without a <id>.txt is run through $ASR_CMD "<file>" (prints the
transcript on stdout) or else `parakeet-mlx` (same call as netcup-server/tools/feedback.sh).
The transcript is cached as <id>.txt beside the audio; a failed run writes nothing and
is retried next time. Digest goes to stdout, or --out FILE.
"""
import glob
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone


def one(s):
    return " ".join(str(s).split())


def transcribe(audio, txt):
    """Returns the transcript text, or None if ASR failed (nothing is cached then)."""
    work = tempfile.mkdtemp(prefix="fk-asr-")
    try:
        asr_cmd = os.environ.get("ASR_CMD")
        if asr_cmd:
            r = subprocess.run(shlex.split(asr_cmd) + [audio], capture_output=True, text=True)
            if r.returncode != 0:
                return None
            text = r.stdout
        else:
            if shutil.which("parakeet-mlx") is None:
                return None
            r = subprocess.run(["parakeet-mlx", "--output-format", "txt", "--output-dir", work, audio],
                               capture_output=True, text=True)
            if r.returncode != 0:
                return None
            text = "".join(open(p, encoding="utf-8").read() for p in sorted(glob.glob(os.path.join(work, "*.txt"))))
        text = one(text) or "[no speech detected]"
        with open(txt + ".tmp", "w", encoding="utf-8") as f:
            f.write(text + "\n")
        os.replace(txt + ".tmp", txt)
        return text
    finally:
        shutil.rmtree(work, ignore_errors=True)


def load_notes(folder):
    notes = []
    for p in glob.glob(os.path.join(folder, "*.json")):
        try:
            rec = json.load(open(p, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(rec, dict) or "id" not in rec:
            continue
        meta = rec.get("meta")
        if isinstance(meta, str):
            try:
                meta = json.loads(meta)
            except ValueError:
                meta = {}
        if not isinstance(meta, dict):
            meta = {}
        if meta.get("test") is True:
            continue
        notes.append((float(rec.get("createdAt") or 0), rec, meta, p[:-5]))
    notes.sort(key=lambda n: n[0], reverse=True)
    return notes


def digest(folder, asr=True):
    notes = load_notes(folder)
    out = ["# Skrift Dev feedback (phone outbox)", "",
           "%d note(s), newest first. Files live under %s." % (len(notes), folder), ""]
    n_ok = n_fail = 0
    for created, rec, meta, base in notes:
        audio, txt = base + ".m4a", base + ".txt"
        transcript = None
        if os.path.exists(txt) and os.path.getsize(txt) > 0:
            transcript = one(open(txt, encoding="utf-8").read())
        elif os.path.exists(audio) and asr:
            transcript = transcribe(audio, txt)
            if transcript is None:
                n_fail += 1
            else:
                n_ok += 1
        when = datetime.fromtimestamp(created, timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ") if created else (meta.get("recorded_at") or "(no time)")
        screen = meta.get("screen") or "-"
        ver = meta.get("app_version") or "-"
        if meta.get("build"):
            ver = "%s (%s)" % (ver, meta["build"])
        qid = meta.get("question_id") or rec.get("questionID")
        ms = rec.get("ms") or meta.get("ms") or 0
        head = "## %s · %s" % (when, screen)
        if ms:
            head += " · %.0f s" % (ms / 1000)
        out += [head, ""]
        if transcript:
            out += ["> " + transcript, ""]
        elif os.path.exists(audio):
            out += ["> (not transcribed yet)", ""]
        if rec.get("text"):
            out += ["Typed: " + one(rec["text"]), ""]
        line = "- id `%s` · screen %s · app %s" % (rec["id"], screen, ver)
        if qid:
            line += " · answers question " + str(qid)
        out.append(line)
        extra = []
        if meta.get("device") or meta.get("os"):
            extra.append("%s iOS %s" % (meta.get("device") or "?", meta.get("os") or "?"))
        if rec.get("state"):
            s = "outbox state %s, %s attempt(s)" % (rec["state"], rec.get("attempts", 0))
            if rec.get("lastStatus"):
                s += ", last HTTP %s" % rec["lastStatus"]
            if rec.get("lastError"):
                s += ", " + one(rec["lastError"])
            extra.append(s)
        if extra:
            out.append("- " + " · ".join(extra))
        if os.path.exists(audio):
            out.append("- audio `%s`" % audio)
        for suffix in (".png", ".2.png"):
            if os.path.exists(base + suffix):
                out.append("- screenshot `%s`" % (base + suffix))
        out.append("")
    if asr:
        sys.stderr.write("transcribed %d, failed %d\n" % (n_ok, n_fail))
    return "\n".join(out)


def self_test():
    T = tempfile.mkdtemp(prefix="fk-outbox-selftest-")
    fails = []

    def check(name, cond):
        print(("ok   " if cond else "FAIL ") + name)
        if not cond:
            fails.append(name)

    def note(id, created, meta, **rec):
        r = {"id": id, "createdAt": created, "meta": json.dumps(meta), "hasAudio": False,
             "screenshotCount": 0, "state": "pending", "attempts": 0, "retryAt": 0}
        r.update(rec)
        json.dump(r, open(os.path.join(T, id + ".json"), "w"))

    # aaa: voice note with two screenshots, answers Q43, failed once with a 401.
    note("AAA", 1790000000, {"v": 1, "id": "AAA", "install_id": "I", "ms": 4200, "question_id": "Q43",
                             "screen": "Library", "app_version": "1.0", "build": "175",
                             "device": "iPhone18,1", "os": "26.0", "recorded_at": "2026-10-04T10:00:00Z"},
         hasAudio=True, ms=4200, screenshotCount=2, questionID="Q43", state="failed", attempts=3,
         lastStatus=401, lastError="unauthorized")
    for f in ("AAA.m4a", "AAA.png", "AAA.2.png"):
        open(os.path.join(T, f), "wb").write(b"x")
    # bbb: typed only, newer, no screen/version.
    note("BBB", 1790001000, {"v": 1, "id": "BBB", "install_id": "I", "recorded_at": "2026-10-04T10:16:40Z"},
         text="typed note\nwith | pipe")
    # ccc: smoke test, must be left out. ddd: unreadable record, must not crash.
    note("CCC", 1790002000, {"v": 1, "id": "CCC", "test": True}, text="smoke")
    open(os.path.join(T, "DDD.json"), "w").write("{not json")

    fake = os.path.join(T, "fake-asr.sh")
    open(fake, "w").write('#!/bin/sh\necho "fake transcript for $(basename "$1")"\n')
    os.chmod(fake, 0o755)
    os.environ["ASR_CMD"] = fake
    md = digest(T)
    check("transcript folded in", "> fake transcript for AAA.m4a" in md)
    check("transcript cached as .txt", os.path.exists(os.path.join(T, "AAA.txt")))
    check("screen", "screen Library" in md and "· Library · 4 s" in md)
    check("app version + build", "app 1.0 (175)" in md)
    check("answered question id", "answers question Q43" in md)
    check("typed text, newlines flattened", "Typed: typed note with | pipe" in md)
    check("missing screen/version are dashes", "screen - · app -" in md)
    check("newest first", md.index("BBB") < md.index("AAA"))
    check("outbox state shown", "outbox state failed, 3 attempt(s), last HTTP 401, unauthorized" in md)
    check("screenshots listed", "AAA.png" in md and "AAA.2.png" in md)
    check("test note left out", "CCC" not in md and "smoke" not in md)
    check("count excludes test + unreadable", "2 note(s)" in md)
    # failed ASR is not cached and shows as not transcribed
    os.remove(os.path.join(T, "AAA.txt"))
    open(fake, "w").write("#!/bin/sh\nexit 1\n")
    md2 = digest(T)
    check("failed ASR: nothing cached", not os.path.exists(os.path.join(T, "AAA.txt")))
    check("failed ASR: marked not transcribed", "(not transcribed yet)" in md2)
    # --no-asr keeps cached text
    open(os.path.join(T, "AAA.txt"), "w").write("cached words\n")
    check("cached transcript reused with ASR off", "> cached words" in digest(T, asr=False))
    shutil.rmtree(T, ignore_errors=True)
    print("SELF-TEST " + ("PASS" if not fails else "FAIL (%d)" % len(fails)))
    return 1 if fails else 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    args = [a for a in argv if not a.startswith("--")]
    out = None
    if "--out" in argv:
        i = argv.index("--out")
        out = argv[i + 1]
        args = [a for a in args if a != out]
    if len(args) != 1 or not os.path.isdir(args[0]):
        sys.stderr.write(__doc__)
        return 2
    md = digest(os.path.abspath(args[0]), asr="--no-asr" not in argv)
    if out:
        open(out, "w", encoding="utf-8").write(md + "\n")
    else:
        print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
