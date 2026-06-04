"""
Enhancement service
Handles AI enhancement with MLX models and streaming
"""

import time
import asyncio
import threading
import re
import subprocess
import json as _json
import os
import datetime as _dt
import re as _re
import logging
from pathlib import Path
from config.settings import settings
from services.mlx_runner import generate_with_mlx, stream_with_mlx, plan_generation, MLXNotAvailable
from utils.status_tracker import status_tracker, ProcessingStatus

logger = logging.getLogger(__name__)

# Track active streams to prevent concurrent encodes per file
ACTIVE_ENHANCE_STREAMS: set[str] = set()

# File IDs the user has requested to cancel. Streams check this between
# tokens and break out of the loop. The MLX call itself can't be preempted
# mid-forward-pass, but a forward pass is ~10–50ms so the user perceives
# cancellation as instant.
CANCELLED_ENHANCE_STREAMS: set[str] = set()


def request_enhance_cancel(file_id: str) -> bool:
    """Mark a streaming enhancement for cancellation. Returns True if a
    stream was active for this file. The stream loop checks the flag once
    per token and breaks out cleanly."""
    if file_id in ACTIVE_ENHANCE_STREAMS:
        CANCELLED_ENHANCE_STREAMS.add(file_id)
        return True
    return False


def is_enhance_cancelled(file_id: str) -> bool:
    return file_id in CANCELLED_ENHANCE_STREAMS


def build_enhancement_context(file_id: str) -> str:
    """
    Build combined input text for enhancement, incorporating shared content context.
    For regular voice memos, returns the transcript as-is (unchanged behavior).
    For capture items, prepends shared content context before the annotation.
    """
    pf = status_tracker.get_file(file_id)
    if not pf:
        return ""

    base_text = pf.transcript or ""
    shared = (pf.audioMetadata or {}).get('shared_content')
    if not shared:
        return base_text

    preamble_parts = []
    share_type = shared.get('type', '')

    if share_type == 'url':
        url = shared.get('url', '')
        title = shared.get('urlTitle', '')
        preamble_parts.append(f"[Shared URL: {url}]")
        if title:
            preamble_parts.append(f"[Page title: {title}]")
        desc = shared.get('urlDescription', '')
        if desc:
            preamble_parts.append(f"[Description: {desc[:300]}]")
    elif share_type == 'image':
        fname = shared.get('fileName', 'image')
        preamble_parts.append(f"[Shared image: {fname}]")
    elif share_type == 'text':
        snippet = shared.get('text', '')
        if snippet:
            preamble_parts.append(f"[Shared text: {snippet[:500]}]")
    elif share_type == 'file':
        fname = shared.get('fileName', 'file')
        preamble_parts.append(f"[Shared file: {fname}]")

    if not preamble_parts:
        return base_text

    context = "\n".join(preamble_parts)
    if base_text:
        return f"{context}\n\nAnnotation:\n{base_text}"
    return context


async def _schedule_idle_cache_clear():
    """
    Wait 10 seconds after enhancement completes, then clear MLX cache if still idle.
    Only runs in manual mode - batch mode clears cache explicitly.
    """
    await asyncio.sleep(10)
    
    try:
        from services.mlx_cache import get_model_cache
        cache = get_model_cache()
        
        if cache.should_clear_idle_cache(idle_timeout_seconds=10):
            cache.clear_cache(reason="10s idle after manual enhancement")
            logger.info("✅ MLX model auto-unloaded after 10s idle (manual mode)")
    except Exception as e:
        logger.error(f"Failed to auto-clear MLX cache: {e}")


def test_model() -> dict:
    """
    Quick test to validate the currently selected MLX model loads and can generate text.
    Returns dict with sample output, timing, and model info.
    Raises MLXNotAvailable or ValueError if test fails.
    """
    from pathlib import Path
    from config.settings import get_mlx_models_path

    mlx_cfg = settings.get('enhancement.mlx') or {}
    model_path = (mlx_cfg.get('model_path') or '').strip()
    if not model_path:
        raise ValueError("MLX model not selected. Set one in Settings > Enhancement.")
    if not Path(model_path).exists():
        raise ValueError(f"Model folder not found: {Path(model_path).name}. Check Settings > Enhancement.")

    # Enforce that the selected model lives under the current dependencies_folder/models/mlx
    models_root = get_mlx_models_path()
    try:
        p = Path(model_path).resolve()
        root = models_root.resolve()
        if root not in p.parents and p != root:
            raise MLXNotAvailable(
                "Selected MLX model is outside the current dependencies folder. "
                "After changing Dependencies Folder in Settings > Paths, please re-select a model in Settings > Enhancement."
            )
    except MLXNotAvailable:
        raise
    except Exception:
        # If resolution fails for any reason, fall back to the lower-level checks in mlx_runner
        pass

    prompt = "You are a minimal test. Respond with a single short line confirming MLX works."
    t0 = time.time()
    
    # Prepare plan first for visibility
    plan = plan_generation(
        prompt=prompt,
        input_text="Hello",
        model_path=model_path,
        max_tokens=int(mlx_cfg.get('max_tokens', 64)),
        temperature=float(mlx_cfg.get('temperature', 0.7)),
    )
    sample = generate_with_mlx(
        prompt=prompt,
        input_text="",
        model_path=model_path,
        max_tokens=int(mlx_cfg.get('max_tokens', 64)),
        temperature=float(mlx_cfg.get('temperature', 0.7)),
        timeout_seconds=int(mlx_cfg.get('timeout_seconds', 20))
    )

    elapsed = time.time() - t0
    return {
        "selected": model_path,
        "elapsed_seconds": round(elapsed, 3),
        "sample": (sample or "").splitlines()[0][:200],
        "used_chat_template": plan.get("used_chat_template"),
        "effective_max_tokens": plan.get("effective_max_tokens"),
        "prompt_preview": plan.get("prompt_preview"),
    }


def _get_image_manifest(file_id: str):
    """Load image manifest for a file, or return None if no images."""
    pf = status_tracker.get_file(file_id)
    if not pf:
        return None
    file_folder = Path(pf.path).parent
    manifest_path = file_folder / "image_manifest.json"
    if not manifest_path.exists():
        return None
    try:
        return _json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _resolve_text_model_path(mlx_cfg: dict) -> str:
    """Get the lighter/faster model for text-only tasks.

    Resolution order:
      1. configured `fallback_model_path` if it exists on disk
      2. smallest valid model dir found under the MLX models root
      3. configured `model_path` if it exists on disk

    Raises FileNotFoundError if none resolve to a real path, so callers fail
    loudly rather than passing an empty/missing path into MLX.
    """
    fallback = (mlx_cfg.get('fallback_model_path') or '').strip()
    if fallback and Path(fallback).exists():
        return fallback
    try:
        from config.settings import get_mlx_models_path
        models_root = get_mlx_models_path()
        default_path = (mlx_cfg.get('model_path') or '').strip()
        smallest = None
        smallest_size = float('inf')
        for candidate in models_root.iterdir():
            if candidate.is_dir() and str(candidate.resolve()) != str(Path(default_path).resolve()):
                size = sum(f.stat().st_size for f in candidate.glob("*.safetensors"))
                if size > 0 and size < smallest_size:
                    smallest = str(candidate)
                    smallest_size = size
        if smallest:
            return smallest
    except Exception:
        pass
    default_path = (mlx_cfg.get('model_path') or '').strip()
    if default_path and Path(default_path).exists():
        return default_path
    raise FileNotFoundError(
        "No usable MLX text model found. Configure enhancement.mlx.model_path "
        "or place a model in the dependencies models folder."
    )


def _reinsert_image_markers(text: str, img_nums: list, anchors: dict) -> str:
    """
    Reinsert [[img_NNN]] markers into copy-edited text using surrounding-word
    anchors saved from the original transcript.

    Strategy:
      1. Find a target insertion position for each marker in the original
         (unmodified) edited text. Positions don't affect each other since
         we don't insert anything yet.
      2. Sort markers by target position descending.
      3. Insert from the end working backward, so earlier insertions don't
         shift later positions.

    For each marker, the target is found by searching for the last few
    transcript words that came before the marker. Place after the sentence
    containing those words. Falls back to proportional placement.

    Args:
        text: The copy-edited text (markers already stripped)
        img_nums: List of img_num ints in their original order
        anchors: Dict mapping img_num → (before_words_str, after_words_str)
    """
    if not img_nums:
        return text

    text_lower = text.lower()

    # Phase 1: compute insertion position for each marker in the ORIGINAL text
    # `min_pos` = lower bound for this marker's insert (must come after the
    # previous marker's insert, so order is preserved)
    targets = []  # list of (img_num, insert_pos)
    min_pos = 0

    for i, img_num in enumerate(img_nums):
        before_anchor, after_anchor = anchors.get(img_num, ('', ''))
        insert_pos = -1

        # Try the "before" anchor (transcript words just before the marker)
        if before_anchor:
            words = before_anchor.lower().split()
            for length in range(min(len(words), 6), 0, -1):
                search = ' '.join(words[-length:])
                if len(search) < 4:
                    continue
                idx = text_lower.find(search, min_pos)
                if idx >= 0:
                    end_of_anchor = idx + len(search)
                    rest = text[end_of_anchor:]
                    sent_end = _re.search(r'[.!?]\s', rest)
                    insert_pos = end_of_anchor + sent_end.end() if sent_end else end_of_anchor
                    break

        # Fallback: try the "after" anchor (transcript words just after marker)
        if insert_pos < 0 and after_anchor:
            words = after_anchor.lower().split()
            for length in range(min(len(words), 6), 0, -1):
                search = ' '.join(words[:length])
                if len(search) < 4:
                    continue
                idx = text_lower.find(search, min_pos)
                if idx >= 0:
                    # Place at start of sentence containing this anchor
                    lookback = text[:idx]
                    last_sent = max(lookback.rfind('. '), lookback.rfind('! '), lookback.rfind('? '))
                    insert_pos = (last_sent + 2) if last_sent >= 0 else idx
                    break

        # Last fallback: proportional placement
        if insert_pos < 0:
            insert_pos = int((i + 1) / (len(img_nums) + 1) * len(text))
            # Snap to nearest sentence boundary backwards
            lookback = text[max(0, insert_pos - 80):insert_pos]
            last_period = lookback.rfind('. ')
            if last_period >= 0:
                insert_pos = max(0, insert_pos - 80) + last_period + 2

        # Ensure we don't place this marker before the previous one
        if insert_pos < min_pos:
            insert_pos = min_pos
        if insert_pos > len(text):
            insert_pos = len(text)

        targets.append((img_num, insert_pos))
        min_pos = insert_pos  # next marker must come at or after this point

    # Phase 2: insert from the end backward so positions stay valid.
    # Secondary sort by img_num desc — at the same position, the larger
    # img_num inserts FIRST, then smaller img_num inserts at the same
    # absolute offset which pushes the larger one rightward. So the
    # smaller img_num ends up earlier in the text. Preserves natural order.
    final = text
    for img_num, pos in sorted(targets, key=lambda t: (t[1], t[0]), reverse=True):
        marker = f"[[img_{img_num:03d}]]"
        final = final[:pos] + f"\n\n{marker}\n\n" + final[pos:]

    return final


def copy_edit_with_image_markers_stream(file_id: str, input_text: str, text_prompt: str, model_path: str, mlx_cfg: dict):
    """
    Copy-edit a transcript that contains [[img_NNN]] markers, preserving
    marker placement.

    Strategy:
      1. Save the transcript words around each marker as anchors
      2. Strip the markers (the model can't be trusted to preserve them)
      3. Run a normal copy-edit
      4. Reinsert markers programmatically by finding the anchor words in
         the edited text and placing the marker after the matching sentence

    No vision step — photos are placed by position only, not described.
    """
    import re as _re_split

    manifest = _get_image_manifest(file_id)
    parts = _re_split.split(r'(\[\[img_\d{3}\]\])', input_text)

    if not manifest or not any(_re_split.match(r'\[\[img_\d{3}\]\]', p) for p in parts):
        # No image markers — standard text-only copy-edit
        for piece in stream_with_mlx(
            prompt=text_prompt, input_text=input_text,
            model_path=model_path,
            max_tokens=int(mlx_cfg.get('max_tokens', 512)),
            temperature=float(mlx_cfg.get('temperature', 0.7)),
        ):
            yield ("token", piece)
        return

    # (1) Save anchor words around each marker before stripping
    # Anchor = last ~6 words before marker + first ~6 words after
    marker_anchors = {}  # img_num → (before_words, after_words)
    img_nums_in_order = []
    for i, part in enumerate(parts):
        m = _re_split.match(r'\[\[img_(\d{3})\]\]', part)
        if m:
            img_num = int(m.group(1))
            before_text = parts[i-1] if i > 0 else ""
            after_text = parts[i+1] if i+1 < len(parts) else ""
            before_words = [w for w in before_text.split() if w.strip()][-6:]
            after_words = [w for w in after_text.split() if w.strip()][:6]
            marker_anchors[img_num] = (' '.join(before_words), ' '.join(after_words))
            img_nums_in_order.append(img_num)

    # (2) Strip markers and clean whitespace
    stripped = _re.sub(r'\[\[img_\d{3}\]\]', ' ', input_text)
    stripped = _re.sub(r'\s+', ' ', stripped).strip()

    yield ("status", "Loading model...")
    yield ("status", "Editing text...")

    # (3) Run plain copy-edit — no special prompt about photos
    text_acc = []
    for piece in stream_with_mlx(
        prompt=text_prompt,
        input_text=stripped,
        model_path=model_path,
        max_tokens=int(mlx_cfg.get('max_tokens', 512)),
        temperature=float(mlx_cfg.get('temperature', 0.7)),
    ):
        text_acc.append(piece)
        yield ("token", piece)

    final = ''.join(text_acc).strip()

    # (4) Reinsert markers using the saved anchor words
    final = _reinsert_image_markers(final, img_nums_in_order, marker_anchors)

    final = _re.sub(r'\n{3,}', '\n\n', final).strip()

    yield ("done", final)


async def generate_enhancement_stream(file_id: str, input_text: str, prompt: str, step: str = "", model_override: str = None):
    """
    Generate SSE stream for enhancement using MLX.
    Yields SSE-formatted events: start, plan, stats, token, done, error.
    
    Args:
        file_id: file identifier
        input_text: source text to enhance
        prompt: enhancement prompt
    
    Yields:
        SSE-formatted string events
    """
    # Concurrency guard
    if file_id in ACTIVE_ENHANCE_STREAMS:
        raise RuntimeError("Enhancement stream already in progress for this file")
    ACTIVE_ENHANCE_STREAMS.add(file_id)
    # Stale cancel flag from a prior aborted run — clear so this fresh stream
    # doesn't get cancelled instantly.
    CANCELLED_ENHANCE_STREAMS.discard(file_id)

    # Capture prior step status so we can restore it on completion. enhance
    # only flips to DONE after compile runs (separate path); during streaming
    # we mark it PROCESSING so the UI can lock other files' enhance buttons.
    _prior_enhance_status = None
    try:
        _pf = status_tracker.get_file(file_id)
        if _pf:
            _prior_enhance_status = _pf.steps.enhance
            status_tracker.update_file_status(file_id, 'enhance', ProcessingStatus.PROCESSING)
            # Expose which step is running so the Inspector can show stage
            # info even when the local SSE isn't attached (background mode).
            # Normalise to one of: title / copy_edit / summary / tags.
            _step_norm = (step or '').lower().replace(' ', '_').replace('-', '_')
            if _step_norm in ('title', 'copy_edit', 'copyedit', 'summary', 'tags'):
                _pf.enhance_step = 'copy_edit' if _step_norm == 'copyedit' else _step_norm
                status_tracker.save_file_status(file_id)
    except Exception:
        pass

    try:
        # Helper to emit SSE with proper multi-line data framing
        def _sse(event: str, data: str) -> str:
            # Split payload into lines per SSE spec (one data: line per line)
            lines = (data or "").splitlines()
            buf = [f"event: {event}\n"]
            if not lines:
                buf.append("data: \n")
            else:
                for ln in lines:
                    buf.append(f"data: {ln}\n")
            buf.append("\n")
            return ''.join(buf)

        # Clear any stale enhance error without changing step status
        try:
            status_tracker.clear_error(file_id)
        except Exception:
            pass
        
        # Start
        yield _sse("start", "")

        # Resolve model path
        from pathlib import Path
        from config.settings import get_mlx_models_path

        mlx_cfg = settings.get('enhancement.mlx') or {}
        default_model_path = (mlx_cfg.get('model_path') or '').strip()

        # Photo-aware copy-edit (no vision) — strips [[img_NNN]] markers,
        # runs plain copy-edit, reinserts markers via transcript-word anchors.
        _has_images = _get_image_manifest(file_id) is not None
        _step_lower = (step or '').lower()
        _is_copy_edit = _step_lower in ('copy_edit', 'copyedit', 'copy edit')
        _has_image_markers = _has_images and _is_copy_edit

        # Single model for everything — E4B (or whatever the user has selected)
        if model_override:
            model_path = model_override
        else:
            text_model = _resolve_text_model_path(mlx_cfg)
            model_path = text_model if text_model else default_model_path

        if not model_path:
            yield _sse("error", "MLX model not selected. Set one in Settings > Enhancement.")
            return
        if not Path(model_path).exists():
            yield _sse("error", f"Model folder not found: {Path(model_path).name}. Check Settings > Enhancement.")
            return

        # Enforce that model_path lives under the current dependencies_folder/models/mlx
        try:
            models_root = get_mlx_models_path()
            p = Path(model_path).resolve()
            root = models_root.resolve()
            if root not in p.parents and p != root:
                yield _sse("error", "Selected MLX model is outside the current dependencies folder. After changing Dependencies Folder in Settings > Paths, re-select a model in Settings > Enhancement.")
                return
        except Exception:
            # If resolution fails, downstream MLX calls will emit a clearer error
            pass

        # RAM check — warn if model won't fit in total system memory.
        # Skip if model is already loaded (no new RAM needed).
        #
        # IMPORTANT: We compare against TOTAL system RAM, not psutil's
        # "available" which only counts free+inactive pages. On macOS with
        # unified memory, the OS aggressively caches file data (including
        # memory-mapped model weights from prior loads) and reports that as
        # "used" — but releases it instantly under pressure. Using "available"
        # produces false positives (e.g., 4.5GB "available" on a 24GB Mac).
        #
        # Uses 40% of safetensors size for MoE models (sparse activation).
        try:
            from services.mlx_cache import get_model_cache
            cache = get_model_cache()
            model_already_loaded = cache._current_path == str(Path(model_path).resolve())

            if not model_already_loaded:
                import psutil
                total_gb = psutil.virtual_memory().total / (1024 ** 3)

                model_dir = Path(model_path)
                model_bytes = sum(f.stat().st_size for f in model_dir.glob("*.safetensors"))
                required_gb = (model_bytes / (1024 ** 3)) * 0.4 + 2.0

                # Only block if the model physically can't fit in the machine's
                # total RAM (with headroom for OS + other processes).
                headroom_gb = min(total_gb * 0.25, 6.0)  # 25% or 6GB, whichever is less
                if required_gb > (total_gb - headroom_gb):
                    fallback = ''
                    try:
                        models_root = get_mlx_models_path()
                        for candidate in sorted(models_root.iterdir()):
                            if candidate.is_dir() and candidate.resolve() != Path(model_path).resolve():
                                candidate_bytes = sum(f.stat().st_size for f in candidate.glob("*.safetensors"))
                                candidate_req = (candidate_bytes / (1024 ** 3)) * 0.4 + 2.0
                                if candidate_req < (total_gb - headroom_gb):
                                    fallback = str(candidate)
                                    break
                    except Exception:
                        pass

                    import json as _json_ram
                    yield _sse("insufficient_ram", _json_ram.dumps({
                        "required_gb": round(required_gb, 1),
                        "available_gb": round(total_gb - headroom_gb, 1),
                        "model_name": Path(model_path).name,
                        "fallback_model": fallback,
                        "fallback_name": Path(fallback).name if fallback else None,
                    }))
                    return
        except ImportError:
            pass
        except Exception as e:
            logger.warning(f"RAM check failed (non-fatal): {e}")

        # Emit plan/debug info first (full metrics) and a separate ping-able stats event
        try:
            import json as _json
            plan = plan_generation(
                prompt=prompt or "You are an assistant that enhances transcripts.",
                input_text=input_text,
                model_path=model_path,
                max_tokens=int(mlx_cfg.get('max_tokens', 512)),
                temperature=float(mlx_cfg.get('temperature', 0.7)),
            )
            yield _sse("plan", _json.dumps(plan))
            # Also send a stats snapshot (input length, dynamic budget)
            stats = {
                'input_length': len(input_text or ''),
                'effective_max_tokens': plan.get('effective_max_tokens'),
                'used_chat_template': plan.get('used_chat_template')
            }
            yield _sse("stats", _json.dumps(stats))
        except Exception:
            pass

        # Try true streaming first
        try:
            if _has_image_markers:
                logger.info(f"Enhance stream: copy-edit with image markers for {file_id}")
            else:
                logger.info("Enhance stream: attempting true MLX streaming")
            acc = []  # collector fed by model thread
            sse_chunks = []  # authoritative stream buffer of what we actually emitted

            async def stream_tokens():
                # stream_with_mlx is a regular generator; iterate in thread to avoid blocking loop
                loop_acc = {"error": None, "cancelled": False}

                def run_and_collect():
                    try:
                        if _has_image_markers:
                            # Strip markers → copy-edit → reinsert markers
                            logger.info(f"Starting copy_edit_with_image_markers_stream for file {file_id}")
                            for evt_type, piece in copy_edit_with_image_markers_stream(
                                file_id=file_id,
                                input_text=input_text,
                                text_prompt=prompt or "You are an assistant that enhances transcripts.",
                                model_path=model_path,
                                mlx_cfg=mlx_cfg,
                            ):
                                # Honour user cancel between tokens
                                if is_enhance_cancelled(file_id):
                                    loop_acc["cancelled"] = True
                                    break
                                if evt_type == "token":
                                    acc.append(piece)
                                elif evt_type == "done":
                                    acc.append(f"\n__HYBRID_FINAL__\n{piece}")
                                elif evt_type == "status":
                                    # Forward progress events — prefix with __SSE__ so the
                                    # flush loop can emit them as separate SSE events
                                    acc.append(f"\n__SSE__{evt_type}__{piece}\n")
                        else:
                            logger.info(f"Starting stream_with_mlx for file {file_id}")
                            # Emit loading status — model load happens inside stream_with_mlx
                            # on first token, so send a status event before streaming starts
                            acc.append(f"\n__SSE__status__Loading model...\n")
                            first_token = True
                            for piece in stream_with_mlx(
                                prompt=prompt or "You are an assistant that enhances transcripts.",
                                input_text=input_text,
                                model_path=model_path,
                                max_tokens=int(mlx_cfg.get('max_tokens', 512)),
                                temperature=float(mlx_cfg.get('temperature', 0.7)),
                            ):
                                if is_enhance_cancelled(file_id):
                                    loop_acc["cancelled"] = True
                                    break
                                if first_token:
                                    step_label = (_step_lower or 'text').replace('_', ' ').title()
                                    acc.append(f"\n__SSE__status__Generating {step_label.lower()}...\n")
                                    first_token = False
                                acc.append(piece)
                        logger.info(f"Stream completed for file {file_id}, got {len(acc)} pieces")
                    except Exception as e:
                        logger.error(f"MLX stream failed for {file_id}: {e}", exc_info=True)
                        loop_acc["error"] = str(e)
                
                th = threading.Thread(target=run_and_collect, daemon=True)
                th.start()
                
                # Flush buffer periodically while thread runs
                def _flush_acc(from_idx):
                    """Process accumulated items, emitting SSE events and tokens."""
                    events = []
                    chunk_parts = []
                    for item in acc[from_idx:]:
                        if item.startswith('\n__SSE__'):
                            # Format: \n__SSE__type__data\n — split after removing prefix
                            stripped = item.strip()  # __SSE__type__data
                            after_prefix = stripped[len('__SSE__'):]  # type__data
                            sep_pos = after_prefix.find('__')
                            if sep_pos >= 0:
                                evt_type = after_prefix[:sep_pos]
                                evt_data = after_prefix[sep_pos + 2:]
                                events.append((evt_type, evt_data))
                            elif after_prefix:
                                events.append((after_prefix, ""))
                        elif '\n__HYBRID_FINAL__\n' in item:
                            before = item.split('\n__HYBRID_FINAL__\n')[0]
                            if before.strip():
                                chunk_parts.append(before)
                        else:
                            chunk_parts.append(item)
                    return events, ''.join(chunk_parts)

                last_idx = 0
                while th.is_alive():
                    if len(acc) > last_idx:
                        events, chunk = _flush_acc(last_idx)
                        last_idx = len(acc)
                        for evt_type, evt_data in events:
                            yield _sse(evt_type, evt_data)
                        if chunk:
                            sse_chunks.append(chunk)
                            yield _sse("token", chunk)
                    await asyncio.sleep(0.02)

                # Flush tail
                if len(acc) > last_idx:
                    events, chunk = _flush_acc(last_idx)
                    for evt_type, evt_data in events:
                        yield _sse(evt_type, evt_data)
                    if chunk:
                        sse_chunks.append(chunk)
                        yield _sse("token", chunk)
                
                if loop_acc["error"]:
                    raise RuntimeError(loop_acc["error"])
                # Stash cancel flag on outer scope so the post-stream code
                # can short-circuit before persisting partial output.
                stream_tokens.cancelled = loop_acc.get("cancelled", False)
            
            async for evt in stream_tokens():
                yield evt

            # If the user cancelled mid-stream, discard partial output and
            # emit a `cancelled` event. The frontend treats this distinctly
            # from `error` and `done`.
            if getattr(stream_tokens, 'cancelled', False):
                logger.info(f"Enhance stream cancelled for {file_id}")
                yield _sse("cancelled", "")
                return

            # Build final strictly from what we actually emitted as tokens
            # For hybrid pipeline, use the reassembled final text from the generator
            all_acc = ''.join(acc)
            if '__HYBRID_FINAL__' in all_acc:
                final = all_acc.split('__HYBRID_FINAL__\n', 1)[-1]
            else:
                final = ''.join(sse_chunks) if sse_chunks else all_acc
        except Exception as e:
            # Streaming failed. Do not persist this as a pipeline error; surface to client only.
            err = f"Streaming not available: {e}"
            yield _sse("error", err)
            return

        yield _sse("done", final)
        
        # Schedule cache clearing after 10 seconds idle (manual mode only)
        # Batch mode clears cache explicitly at batch end
        asyncio.create_task(_schedule_idle_cache_clear())
    
    finally:
        # Release lock regardless of outcome
        try:
            ACTIVE_ENHANCE_STREAMS.discard(file_id)
            CANCELLED_ENHANCE_STREAMS.discard(file_id)
        except Exception:
            pass
        # Restore step status — leave at PROCESSING is wrong; if we don't
        # restore, the UI will think enhance is still running forever.
        try:
            if _prior_enhance_status is not None:
                pf = status_tracker.get_file(file_id)
                if pf and pf.steps.enhance == ProcessingStatus.PROCESSING:
                    status_tracker.update_file_status(file_id, 'enhance', _prior_enhance_status)
        except Exception:
            pass
        # Clear the transient step indicator regardless of outcome.
        try:
            pf = status_tracker.get_file(file_id)
            if pf and pf.enhance_step is not None:
                pf.enhance_step = None
                status_tracker.save_file_status(file_id)
        except Exception:
            pass


# =========================
# Compile / Auto-compile
# =========================

def _all_enhancement_parts_present(pf) -> bool:
    """Return True when tags have been applied — tags are the final user-confirmed step.
    Title, copy edit and summary are compiled if present but are not required to trigger compile."""
    return bool(pf.enhanced_tags or [])


async def compile_file(file_id: str) -> dict:
    """
    Core compile logic: assembles Obsidian-ready markdown from status.json fields.
    Returns {'success': True, 'compiled_path': str} or raises on error.
    """
    pf = status_tracker.get_file(file_id)
    if not pf:
        raise ValueError(f"File not found: {file_id}")

    is_note = pf.source_type == 'note'

    date_str = None
    if not is_note:
        try:
            cmd = ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", pf.path]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
            if res.returncode == 0:
                info = _json.loads(res.stdout or '{}')
                tags_meta = (info.get('format') or {}).get('tags') or {}
                ctime = tags_meta.get('creation_time') or tags_meta.get('com.apple.quicktime.creationdate')
                if ctime:
                    date_str = ctime[:10]
        except Exception:
            pass
    try:
        if not date_str:
            st = os.stat(pf.path)
            ts = st.st_mtime if is_note else getattr(st, 'st_birthtime', st.st_mtime)
            date_str = _dt.datetime.fromtimestamp(ts).strftime('%Y-%m-%d')
    except Exception:
        date_str = None

    folder = Path(pf.path).parent
    working = pf.enhanced_copyedit or pf.sanitised or pf.transcript or ''
    summary = pf.enhanced_summary or ''
    tags = pf.enhanced_tags or []

    raw_stem = pf.filename.rsplit('.', 1)[0].rstrip('.')
    note_title_meta = (pf.audioMetadata or {}).get('note_title') if is_note else None
    title_str = (pf.enhanced_title or '').strip() or note_title_meta or raw_stem

    # Extract phone metadata from audioMetadata (mobile recordings)
    audio_meta = pf.audioMetadata or {}

    # Determine source string
    shared_content = audio_meta.get('shared_content') or {}
    is_capture = pf.source_type == 'capture' or bool(shared_content)
    if is_note:
        source_str = 'Apple-Note'
    elif is_capture:
        share_type = shared_content.get('type', 'unknown')
        source_str = f'Capture-{share_type.capitalize()}'
    else:
        source_str = 'Voice-memo'

    author = (settings.get('export.author') or '').strip()
    phone_location = audio_meta.get('phone_location') or {}
    phone_weather = audio_meta.get('phone_weather') or {}
    phone_pressure = audio_meta.get('phone_pressure') or {}
    phone_day_period = audio_meta.get('phone_day_period')
    phone_daylight = audio_meta.get('phone_daylight') or {}
    phone_steps = audio_meta.get('phone_steps')

    # Build location string: prefer phone location placeName, fall back to empty
    location_str = ''
    if phone_location.get('placeName'):
        location_str = phone_location['placeName']

    yaml_lines = [
        '---',
        f'title: {title_str}',
        f'date: {date_str or ""}',
        'lastTouched:',
        f'author: {author}',
        f'source: {source_str}',
        f'location: "{location_str}"' if location_str else 'location:',
    ]

    # Add phone metadata fields when available
    if phone_weather.get('conditions') is not None and phone_weather.get('temperature') is not None:
        unit = phone_weather.get('temperatureUnit', '°C')
        yaml_lines.append(f'weather: "{phone_weather["conditions"]}, {phone_weather["temperature"]}{unit}"')

    if phone_pressure.get('hPa') is not None:
        yaml_lines.append(f'pressure: {phone_pressure["hPa"]}')
    if phone_pressure.get('trend'):
        yaml_lines.append(f'pressureTrend: {phone_pressure["trend"]}')

    if phone_day_period:
        yaml_lines.append(f'dayPeriod: {phone_day_period}')

    if phone_daylight.get('sunrise') and phone_daylight.get('sunset'):
        yaml_lines.append('daylight:')
        yaml_lines.append(f'  sunrise: "{phone_daylight["sunrise"]}"')
        yaml_lines.append(f'  sunset: "{phone_daylight["sunset"]}"')
        if phone_daylight.get('hoursOfLight') is not None:
            yaml_lines.append(f'  hoursOfLight: {phone_daylight["hoursOfLight"]}')

    if phone_steps is not None:
        yaml_lines.append(f'steps: {phone_steps}')

    yaml_lines.append('tags:')
    for t in tags:
        yaml_lines.append(f'  - {t}')
    # Use cached significance score (computed after summary, before tags)
    importance = pf.significance
    significance_line = f'significance: {importance}' if importance is not None else 'significance:'

    # Add capture-specific frontmatter
    if is_capture and shared_content:
        if shared_content.get('url'):
            yaml_lines.append(f'sourceUrl: "{shared_content["url"]}"')
        if shared_content.get('urlTitle'):
            yaml_lines.append(f'sourceTitle: "{shared_content["urlTitle"]}"')

    yaml_lines.extend([significance_line, 'summary:', '---', ''])
    if summary:
        yaml_lines[yaml_lines.index('summary:')] = f"summary: {summary}"

    # For capture items, prepend a source reference before the body content
    source_block = ''
    if is_capture and shared_content:
        st = shared_content.get('type', '')
        if st == 'url' and shared_content.get('url'):
            link_title = shared_content.get('urlTitle', shared_content['url'])
            source_block = f'\n> Source: [{link_title}]({shared_content["url"]})\n\n'
        elif st == 'image' and shared_content.get('fileName'):
            source_block = f'\n![[{shared_content["fileName"]}]]\n\n'
        elif st == 'text' and shared_content.get('text'):
            text_preview = shared_content['text'][:500]
            source_block = f'\n> {text_preview}\n\n'

    content = '\n'.join(yaml_lines) + source_block + working

    out_path = folder / 'compiled.md'
    out_path.write_text(content, encoding='utf-8')

    pf.compiled_text = content
    pf.lastModified = _dt.datetime.now()
    status_tracker.save_file_status(file_id)

    if _all_enhancement_parts_present(pf):
        status_tracker.update_file_status(file_id, 'enhance', ProcessingStatus.DONE)

    return {'success': True, 'compiled_path': str(out_path)}


async def auto_compile_if_complete(file_id: str):
    """Silently compile if all four enhancement parts are present. Never raises."""
    try:
        pf = status_tracker.get_file(file_id)
        if pf and _all_enhancement_parts_present(pf):
            await compile_file(file_id)
    except Exception:
        pass


# =========================
# Deterministic tag matching (vault-derived, no LLM)
# =========================

# The user mixes Dutch and English, so we lemmatize trying both languages.
_LEMMA_LANGS = ("nl", "en")

# A "word" for lemmatization: unicode letters, digits, apostrophes and hyphens.
# Kept deliberately broad so Dutch/English words survive intact.
_WORD_RX = _re.compile(r"[^\W\d_]+(?:['\-][^\W\d_]+)*", _re.UNICODE)


def _get_simplemma():
    """Lazily import simplemma so the server still boots if it's missing.

    Raises a clear ValueError (surfaced to the user) only when tagging is
    actually invoked without simplemma installed.
    """
    try:
        import simplemma  # noqa: F401
        return simplemma
    except ImportError as e:
        raise ValueError(
            "simplemma is not installed in the backend venv. Install it with "
            "`~/Skrift_dependencies/mlx-env/bin/pip install simplemma` "
            "(it is declared in backend/requirements.txt)."
        ) from e


def _lemmatize_word(simplemma, word: str) -> str:
    """Lemmatize a single (already-lowercased) word trying Dutch then English."""
    try:
        return simplemma.lemmatize(word, lang=_LEMMA_LANGS).lower()
    except Exception:
        # simplemma can raise on unexpected input; fall back to the raw word.
        return word


def _lemmatize_tokens(simplemma, text: str) -> list[str]:
    """Tokenize free text and return the lemma of every word (lowercased)."""
    if not text:
        return []
    return [_lemmatize_word(simplemma, m.group(0).lower()) for m in _WORD_RX.finditer(text)]


def _tag_lemmas(simplemma, tag: str) -> list[str]:
    """Lemmatize a tag into its component word-lemmas.

    Multi-word / hyphenated tags (e.g. `car-leasing`, `to_process`) are split on
    hyphens/underscores/slashes/spaces and each de-hyphenated word is lemmatized.
    Numeric and empty fragments are dropped.
    """
    # De-hyphenate: treat - _ / and whitespace as separators.
    parts = [_lemmatize_word(simplemma, p.lower()) for p in _re.split(r"[\s\-_/]+", tag) if p]
    return [p for p in parts if p]


def match_tags_in_text(text: str, matchable: list[str], min_occurrences: int | None = None) -> list[str]:
    """Rule B — return the matchable tags whose lemma occurs in `text` often enough.

    A tag becomes a candidate when its lemma appears in the lemmatized
    transcript >= min_occurrences times (default from settings). Multi-word tags
    require EACH component lemma to clear the threshold.
    """
    if not text or not matchable:
        return []
    simplemma = _get_simplemma()

    if min_occurrences is None:
        tag_cfg = settings.get('enhancement.tagging') or {}
        min_occurrences = int(tag_cfg.get('match_min_occurrences', 2))

    # Count lemma frequencies in the transcript once.
    from collections import Counter
    lemma_counts = Counter(_lemmatize_tokens(simplemma, text))

    out = []
    for tag in matchable:
        lemmas = _tag_lemmas(simplemma, tag)
        if not lemmas:
            continue
        if all(lemma_counts.get(lem, 0) >= min_occurrences for lem in lemmas):
            out.append(tag)
    return out


def extract_spoken_hashtags(text: str) -> list[str]:
    """Return explicit #hashtags literally present in the text (high precision).

    These are committed directly even if not in the vault list. Returns
    lowercased tag words without the leading '#', numeric-only dropped,
    de-duplicated preserving order.
    """
    if not text:
        return []
    seen = set()
    out = []
    for m in _re.finditer(r"(?<!\w)#([^\W\d_][\w\-/]*)", text, _re.UNICODE):
        t = m.group(1).strip().lower()
        if t and t not in seen:
            seen.add(t)
            out.append(t)
    return out


# =========================
# Tag generation service
# =========================

def load_tag_whitelist() -> dict:
    """Load the tag whitelist from disk. Raises ValueError on read failure.

    The file may be the legacy shape ({version, count, tags}) or the enriched
    shape that also carries a `matchable` list. Either is returned verbatim.
    """
    cfg = settings.get('enhancement.obsidian') or {}
    wl_path = (Path(cfg.get('tags_whitelist_path') or '')).expanduser()
    try:
        if wl_path and wl_path.exists():
            return _json.loads(wl_path.read_text(encoding='utf-8', errors='ignore'))
    except Exception as e:
        raise ValueError(f"Failed to read whitelist: {e}")
    return {'version': 1, 'count': 0, 'tags': [], 'matchable': []}


async def generate_tags_service(file_id: str) -> dict:
    """Generate tag suggestions deterministically from the vault tag list — no LLM.
    Returns suggestions only (does not persist the final selection).

    Return shape (unchanged for the frontend / batch_manager):
      {'success': True, 'old': [...], 'new': [...], 'raw': str, ...}
      - `old` = vault tags whose word the user actually said often enough
      - `new` = spoken `#hashtag` tags not already present in the vault tag list

    The text matched is `enhanced_copyedit or sanitised or transcript`.
    Raises ValueError for user-facing errors.
    """
    pf = status_tracker.get_file(file_id)
    if not pf:
        raise ValueError(f"File not found: {file_id}")

    text = pf.enhanced_copyedit or pf.sanitised or pf.transcript or ''
    if not text:
        raise ValueError("No text available for tagging (need enhanced copy edit, sanitised or transcript)")

    wl_data = load_tag_whitelist()
    all_tags = {str(t).strip().lower() for t in wl_data.get('tags', []) if str(t).strip()}
    if not all_tags:
        raise ValueError("Tag whitelist is empty; refresh it in Settings > Enhancement.")

    tag_cfg = settings.get('enhancement.tagging') or {}
    min_occ = int(tag_cfg.get('match_min_occurrences', 2))

    # Suggest vault tags whose word (lemma) the user actually said >= min_occ times.
    old_final = match_tags_in_text(text, sorted(all_tags), min_occurrences=min_occ)

    # Spoken/explicit #hashtags committed directly (high precision). Surface
    # only the ones that aren't already known vault tags as "new".
    spoken = extract_spoken_hashtags(text)
    new_final = [t for t in spoken if t not in all_tags and t not in set(old_final)]

    legacy_cap = settings.get('enhancement.tags') or {}
    max_old = int(legacy_cap.get('max_old', 10))
    max_new = int(legacy_cap.get('max_new', 5))
    if len(old_final) > max_old:
        old_final = old_final[:max_old]
    if len(new_final) > max_new:
        new_final = new_final[:max_new]

    logger.info(
        f"Deterministic tags for {file_id}: {len(old_final)} matched vault tags, "
        f"{len(new_final)} spoken hashtags (min_occ={min_occ}, vault_tags={len(all_tags)})"
    )

    raw = (
        f"--- matched vault tags (lemma occurs >= {min_occ}x) ---\n"
        + ("\n".join(f"- {t}" for t in old_final) if old_final else "(none)")
        + "\n\n--- spoken #hashtags ---\n"
        + ("\n".join(f"- #{t}" for t in new_final) if new_final else "(none)")
    )

    pf.tag_suggestions = {'old': old_final, 'new': new_final}
    status_tracker.save_file_status(file_id)

    return {
        'success': True,
        'old': old_final,
        'new': new_final,
        'raw': raw,
        'whitelist_count': len(all_tags),
        'min_occurrences': min_occ,
    }
