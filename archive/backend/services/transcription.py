"""
Transcription service — Parakeet-MLX
Handles audio transcription using parakeet-mlx (MLX-accelerated Parakeet TDT).
"""

import subprocess
import time
import threading
from pathlib import Path
from models import ProcessingStatus
from utils.status_tracker import status_tracker
from config.settings import get_dependency_paths

import logging
logger = logging.getLogger(__name__)

# ── Cancellation tracking ───────────────────────────────────
# Parakeet runs in-process (no subprocess), so we use an Event flag
# that the transcription loop can check between chunks.
_ACTIVE_TRANSCRIBE_CANCEL: dict[str, threading.Event] = {}
_ACTIVE_TRANSCRIBE_LOCK = threading.Lock()


def cancel_transcription_process(file_id: str) -> bool:
    """Signal cancellation for an in-flight transcription.

    Returns True if an active transcription was found and signalled.
    """
    if not file_id:
        return False
    with _ACTIVE_TRANSCRIBE_LOCK:
        evt = _ACTIVE_TRANSCRIBE_CANCEL.get(file_id)
    if evt:
        evt.set()
        return True
    return False


# ── Audio preprocessing ─────────────────────────────────────

def _preprocess_audio_to_wav(audio_file_path: str, output_dir: Path, file_id: str | None, force: bool = False) -> Path:
    """Convert audio to 16kHz mono WAV with denoising + loudness normalization.

    Uses ffmpeg afftdn (adaptive FFT denoiser) followed by EBU R128 loudnorm.
    Returns the path to ``processed.wav`` inside *output_dir*.
    """
    import json as _json

    processed_wav = output_dir / "processed.wav"
    if processed_wav.exists() and not force:
        logger.info("processed.wav already exists — reusing")
        return processed_wav
    if force and processed_wav.exists():
        processed_wav.unlink()
        logger.info("Force re-preprocessing audio")

    # Pass 1: analyse loudness
    cmd1 = [
        "ffmpeg", "-hide_banner", "-i", str(audio_file_path),
        "-af", "loudnorm=I=-16:LRA=11:TP=-1.5:print_format=json",
        "-f", "null", "-",
    ]
    logger.info(f"ffmpeg pass-1: {' '.join(cmd1)}")
    r1 = subprocess.run(cmd1, capture_output=True, text=True, timeout=120)
    if r1.returncode != 0:
        logger.error(f"ffmpeg pass-1 failed (rc={r1.returncode}): {r1.stderr[-500:] if r1.stderr else '(no stderr)'}")
    stderr = r1.stderr

    # Extract measured values from JSON block in stderr
    try:
        json_end = stderr.rindex("}") + 1
        depth = 0
        json_start = 0
        for i in range(json_end - 1, -1, -1):
            if stderr[i] == '}':
                depth += 1
            elif stderr[i] == '{':
                depth -= 1
                if depth == 0:
                    json_start = i
                    break
        loud = _json.loads(stderr[json_start:json_end])
        input_i = loud.get("input_i", "-16")
        input_tp = loud.get("input_tp", "-1.5")
        input_lra = loud.get("input_lra", "11")
        input_thresh = loud.get("input_thresh", "-26")
    except Exception as e:
        logger.error(f"Could not parse loudnorm stats from ffmpeg pass-1; using defaults: {e}")
        input_i, input_tp, input_lra, input_thresh = "-16", "-1.5", "11", "-26"

    # Pass 2: denoise + normalise + convert to 16kHz mono WAV
    # Build filter chain from settings
    from config.settings import settings as _settings
    noise_floor = _settings.get("transcription.noise_reduction", -20)
    highpass = _settings.get("transcription.highpass_freq", 80)

    filters = []
    if highpass and int(highpass) > 0:
        filters.append(f"highpass=f={int(highpass)}")
    if noise_floor and int(noise_floor) != 0:
        filters.append(f"afftdn=nf={int(noise_floor)}:tn=1")
    filters.append(
        f"loudnorm=I=-16:LRA=11:TP=-1.5:"
        f"measured_I={input_i}:measured_TP={input_tp}:"
        f"measured_LRA={input_lra}:measured_thresh={input_thresh}"
    )
    af = ",".join(filters)
    cmd2 = [
        "ffmpeg", "-hide_banner", "-y", "-i", str(audio_file_path),
        "-af", af, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
        str(processed_wav),
    ]
    logger.info(f"ffmpeg pass-2: {' '.join(cmd2)}")
    subprocess.run(cmd2, capture_output=True, text=True, timeout=120, check=True)

    if file_id:
        status_tracker.add_audio_metadata(file_id, {"processed_wav_path": str(processed_wav)})

    return processed_wav


# ── Parakeet model singleton ────────────────────────────────
# Keeps the model in memory between transcriptions.
# Thread-safe: guarded by a lock so concurrent requests don't double-load.
_parakeet_model = None
_parakeet_model_id = None
_parakeet_lock = threading.Lock()


def _resolve_parakeet_local_path(model_id: str, cache_dir: str) -> str:
    """Find the local snapshot path for a Parakeet model. Never downloads."""
    cache_path = Path(cache_dir)
    # HF hub cache layout: models--{org}--{name}/snapshots/{hash}/
    hf_dir_name = f"models--{model_id.replace('/', '--')}"
    snapshots_dir = cache_path / hf_dir_name / "snapshots"
    if snapshots_dir.exists():
        # Use the first (usually only) snapshot
        for snapshot in sorted(snapshots_dir.iterdir()):
            if (snapshot / "config.json").exists() and (snapshot / "model.safetensors").exists():
                return str(snapshot)
    # Also check if model_id is already a direct local path
    if (cache_path / "config.json").exists():
        return str(cache_path)
    raise FileNotFoundError(
        f"Parakeet model not found in {cache_dir}. "
        f"Expected HF cache structure for '{model_id}'. "
        f"Run setup.sh or check your dependencies folder."
    )


def _get_parakeet_model():
    """Return a cached Parakeet model, loading on first call or when model id changes.
    Uses local files only — never downloads from HuggingFace."""
    global _parakeet_model, _parakeet_model_id

    from config.settings import settings as _settings
    model_id = _settings.get("transcription.parakeet_model", "mlx-community/parakeet-tdt-0.6b-v3")

    with _parakeet_lock:
        if _parakeet_model is not None and _parakeet_model_id == model_id:
            logger.info("Reusing cached Parakeet model")
            return _parakeet_model

        cache_dir = str(get_dependency_paths()['parakeet'])
        local_path = _resolve_parakeet_local_path(model_id, cache_dir)
        logger.info(f"Loading Parakeet model from local path: {local_path}")
        from parakeet_mlx import from_pretrained
        # Pass local path directly — from_pretrained falls back to local file loading
        _parakeet_model = from_pretrained(local_path, dtype=__import__('mlx.core', fromlist=['bfloat16']).bfloat16)
        _parakeet_model_id = model_id
        return _parakeet_model


# ── Main transcription function ─────────────────────────────

def run_transcription(audio_file_path: str, output_dir: Path, file_id: str = None) -> str:
    """Transcribe an audio file using Parakeet-MLX.

    Produces transcript text + word_timings.json for karaoke display.
    """
    import json as _json

    logger.info("=== PARAKEET TRANSCRIPTION START ===")
    logger.info(f"File ID: {file_id}, audio: {audio_file_path}")

    if not Path(audio_file_path).exists():
        raise FileNotFoundError(f"Audio file does not exist: {audio_file_path}")

    # Register cancellation event
    cancel_evt = threading.Event()
    if file_id:
        with _ACTIVE_TRANSCRIBE_LOCK:
            _ACTIVE_TRANSCRIBE_CANCEL[file_id] = cancel_evt

    try:
        # Pre-process audio (loudness normalization → 16kHz mono WAV)
        if file_id:
            status_tracker.update_file_progress(file_id, "transcribe", 5, "Preprocessing audio…")
        processed_wav = _preprocess_audio_to_wav(audio_file_path, output_dir, file_id)

        if cancel_evt.is_set():
            raise RuntimeError("Transcription cancelled")

        # Load model (cached singleton — instant after first load)
        if file_id:
            status_tracker.update_file_progress(file_id, "transcribe", 10, "Loading Parakeet model…")
        model = _get_parakeet_model()

        if cancel_evt.is_set():
            raise RuntimeError("Transcription cancelled")

        # Progress callback for chunked transcription
        def on_chunk(current_pos, total_pos):
            if cancel_evt.is_set():
                raise RuntimeError("Transcription cancelled")
            if file_id and total_pos > 0:
                pct = 15 + int(80 * current_pos / total_pos)
                pct = min(pct, 95)
                status_tracker.update_file_progress(
                    file_id, "transcribe", pct,
                    f"Transcribing… {pct}%"
                )

        if file_id:
            status_tracker.update_file_progress(file_id, "transcribe", 15, "Transcribing…")

        result = model.transcribe(
            str(processed_wav),
            chunk_duration=600.0,  # 10-min chunks for long files
            overlap_duration=15.0,
            chunk_callback=on_chunk,
        )
    finally:
        if file_id:
            with _ACTIVE_TRANSCRIBE_LOCK:
                _ACTIVE_TRANSCRIBE_CANCEL.pop(file_id, None)

    transcript = result.text.strip()
    logger.info(f"Parakeet transcription done — {len(transcript)} chars, {len(result.sentences)} sentences")

    # ── Build word_timings.json ──────────────────────────────
    # Parakeet emits sub-word tokens (BPE pieces). Tokens whose .text
    # starts with a space begin a new word; others are continuations.
    # We merge them into whole words so karaoke highlights full words.
    segments = []
    audio_dur = 0.0

    for si, sentence in enumerate(result.sentences):
        words = []
        pending_word = None  # accumulator: {"text": str, "start": float, "end": float}
        for token in sentence.tokens:
            raw = token.text
            if not raw:
                continue
            is_new_word = raw.startswith(" ") or pending_word is None
            clean = raw.strip()
            if not clean:
                continue
            s = max(0.0, token.start)
            e = max(s, token.end)
            audio_dur = max(audio_dur, e)

            if is_new_word:
                # Flush previous word
                if pending_word and pending_word["text"].strip():
                    words.append({
                        "token_id": len(words),
                        "word": pending_word["text"].strip(),
                        "start": round(pending_word["start"], 3),
                        "end": round(pending_word["end"], 3),
                    })
                pending_word = {"text": clean, "start": s, "end": e}
            else:
                # Continuation — append to current word
                pending_word["text"] += clean
                pending_word["end"] = e

        # Flush last word
        if pending_word and pending_word["text"].strip():
            words.append({
                "token_id": len(words),
                "word": pending_word["text"].strip(),
                "start": round(pending_word["start"], 3),
                "end": round(pending_word["end"], 3),
            })

        if words:
            segments.append({
                "idx": si,
                "start": words[0]["start"],
                "end": words[-1]["end"],
                "words": words,
            })

    wt = {
        "version": "1",
        "audio": {"processed_wav": "processed.wav", "duration_sec": audio_dur},
        "segments": segments,
    }

    wt_path = output_dir / "word_timings.json"
    wt_path.write_text(_json.dumps(wt, ensure_ascii=False, indent=2), encoding="utf-8")
    if file_id:
        status_tracker.add_audio_metadata(file_id, {"word_timings_path": str(wt_path)})

    logger.info(f"word_timings.json written — {len(segments)} segments")

    # ── Insert image markers if manifest exists ────────────────
    transcript = _insert_image_markers(transcript, output_dir, wt)

    return transcript


def _insert_image_markers(transcript: str, output_dir: Path, word_timings: dict) -> str:
    """Insert [[img_XXX]] markers into the transcript at positions matching photo timestamps.

    Uses word_timings to find the nearest word boundary for each image's offset.
    Pre-computes character positions by scanning words sequentially through the transcript,
    then inserts from last to first to avoid offset drift.
    """
    import json as _json

    manifest_path = output_dir / "image_manifest.json"
    if not manifest_path.exists():
        return transcript

    try:
        manifest = _json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as e:
        logger.warning(f"Failed to read image_manifest.json: {e}")
        return transcript

    if not manifest:
        return transcript

    # Build a flat list of all words with their timing info
    all_words = []
    for seg in word_timings.get("segments", []):
        for w in seg.get("words", []):
            all_words.append({"word": w["word"], "start": w["start"], "end": w["end"]})

    if not all_words:
        return transcript

    # Pre-compute character positions for each word by scanning sequentially.
    # This handles repeated words correctly since we advance through the transcript.
    scan_pos = 0
    for w in all_words:
        word_text = w["word"]
        found = transcript.find(word_text, scan_pos)
        if found != -1:
            w["char_start"] = found
            w["char_end"] = found + len(word_text)
            scan_pos = found + len(word_text)
        else:
            # Word not found in transcript (punctuation mismatch etc.)
            # Estimate position proportionally from timing
            total_duration = max(1, all_words[-1]["end"])
            estimated = int(len(transcript) * w["start"] / total_duration)
            w["char_start"] = min(estimated, len(transcript))
            w["char_end"] = w["char_start"]

    # Sort manifest by offset (ascending) for consistent numbering
    sorted_manifest = sorted(manifest, key=lambda m: m.get("offsetSeconds", 0))

    # For each image, find the nearest word by timestamp and use its pre-computed position
    insertions = []  # [(char_position, marker_text)]

    for i, entry in enumerate(sorted_manifest):
        offset = entry.get("offsetSeconds", 0)
        img_num = i + 1

        # Find the word whose start time is closest to the offset
        best_idx = 0
        best_diff = abs(all_words[0]["start"] - offset)
        for wi, w in enumerate(all_words):
            diff = abs(w["start"] - offset)
            if diff < best_diff:
                best_diff = diff
                best_idx = wi

        # Use pre-computed character position (insert after the word)
        insert_pos = all_words[best_idx]["char_end"]
        marker = f"\n\n[[img_{img_num:03d}]]\n\n"
        insertions.append((insert_pos, marker))

    # Insert from last to first to preserve positions
    for pos, marker in reversed(insertions):
        transcript = transcript[:pos] + marker + transcript[pos:]

    logger.info(f"Inserted {len(insertions)} image markers into transcript")
    return transcript


# ── Thread entry point ──────────────────────────────────────

def process_transcription_thread(file_id: str):
    """Thread function to handle transcription processing without blocking FastAPI."""
    start_time = time.time()

    # Heartbeat thread — updates UI every 10 seconds
    stop_heartbeat = threading.Event()

    def heartbeat_thread():
        while not stop_heartbeat.is_set():
            pipeline_file = status_tracker.get_file(file_id)
            if pipeline_file and pipeline_file.steps.transcribe == ProcessingStatus.PROCESSING:
                elapsed = int(time.time() - start_time)
                if elapsed < 60:
                    time_str = f"{elapsed}s"
                else:
                    time_str = f"{elapsed // 60}m {elapsed % 60}s"
                status_tracker.update_last_activity(
                    file_id,
                    f"Transcribing audio… ({time_str} elapsed)"
                )
            stop_heartbeat.wait(10)

    heartbeat = threading.Thread(target=heartbeat_thread, daemon=True)
    heartbeat.start()

    try:
        pipeline_file = status_tracker.get_file(file_id)
        if not pipeline_file:
            return

        audio_file_path = pipeline_file.path
        output_dir = Path(pipeline_file.path).parent

        transcript = run_transcription(audio_file_path, output_dir, file_id)

        # Record processing time
        processing_time = time.time() - start_time
        status_tracker.add_processing_time(file_id, "transcribe", processing_time)

        # Update status with result
        status_tracker.update_last_activity(file_id, "Transcription completed")
        status_tracker.update_file_status(
            file_id,
            "transcribe",
            ProcessingStatus.DONE,
            result_content=transcript
        )

    except Exception as e:
        status_tracker.update_file_status(
            file_id,
            "transcribe",
            ProcessingStatus.ERROR,
            error=str(e)
        )
        logger.error(f"Transcription error for {file_id}: {e}")

    finally:
        stop_heartbeat.set()
        heartbeat.join(timeout=1)
