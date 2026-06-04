"""
Enhancement API Router
Handles all enhancement-related endpoints including:
- Model testing and streaming enhancement
- Tag whitelist management and tag generation
- Copy edit, summary, tags field updates
- Compilation to Obsidian-ready markdown
- MLX model management (list, upload, delete, select)
"""

from fastapi import APIRouter, BackgroundTasks, HTTPException, UploadFile, File, Form
from fastapi.responses import StreamingResponse
from pathlib import Path
import json as _json
import os
import re as _re

from utils.status_tracker import status_tracker, ProcessingStatus
from services.enhancement import (
    test_model,
    generate_enhancement_stream,
    MLXNotAvailable,
    _all_enhancement_parts_present,
    compile_file,
    auto_compile_if_complete,
    load_tag_whitelist,
    generate_tags_service,
    score_importance_for_file,
    request_enhance_cancel,
)
from config.settings import settings as app_settings

router = APIRouter()

import asyncio, logging
_logger = logging.getLogger(__name__)

async def _score_importance_bg(file_id: str):
    """Background task: score importance while user picks tags."""
    try:
        await score_importance_for_file(file_id)
    except Exception as e:
        _logger.warning(f"Background importance scoring failed for {file_id}: {e}")

# =========================
# Enhancement Core APIs
# =========================

@router.post("/test")
async def test_enhance_model():
    """
    Quick test to validate the currently selected MLX model loads and can generate text.
    Returns a short sample output and timing along with the selected model path.
    """
    try:
        return test_model()
    except MLXNotAvailable as e:
        raise HTTPException(status_code=500, detail=f"MLX not available: {e}")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Test generation failed: {e}")

@router.post("/chat-template")
async def save_chat_template_override(body: dict):
    """Save or clear a custom chat template override for the currently selected model. Pass null to clear."""
    cfg = app_settings.get('enhancement.mlx') or {}
    model_path = (cfg.get('model_path') or '').strip()
    if not model_path:
        return { 'success': False, 'error': 'No model selected' }
    template = body.get('template')  # None/null clears the override for this model
    overrides = dict(cfg.get('chat_template_overrides') or {})
    if template:
        overrides[model_path] = template
    else:
        overrides.pop(model_path, None)
    app_settings.set('enhancement.mlx.chat_template_overrides', overrides)
    return { 'success': True }


@router.get("/input/{file_id}")
async def get_enhance_input(file_id: str):
    """Return exactly the text that would be sent to the LLM for enhancement.
    This mirrors the source selection logic used by enhance_stream.
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    from services.enhancement import build_enhancement_context
    input_text = build_enhancement_context(file_id)
    source = 'capture-context' if (pipeline_file.audioMetadata or {}).get('shared_content') else ('sanitised' if pipeline_file.sanitised else 'transcript')
    return { 'source': source, 'length': len(input_text), 'input_text': input_text }

@router.get("/stream/{file_id}")
async def enhance_stream(file_id: str, prompt: str = "", step: str = "", model_override: str = ""):
    """
    Stream enhancement output via SSE for a given file_id.
    MVP: run MLX generation in a background thread, send heartbeat tokens during work,
    then stream the final text in chunks to simulate real-time output, and persist result.
    Rejects with 409 if a stream is already active for the same file.
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")

    from services.enhancement import build_enhancement_context
    input_text = build_enhancement_context(file_id)
    if not input_text:
        raise HTTPException(status_code=400, detail="No text available to enhance. Run sanitise or transcribe first.")

    try:
        return StreamingResponse(
            generate_enhancement_stream(file_id, input_text, prompt, step=step or prompt, model_override=model_override or None),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )
    except RuntimeError as e:
        # Concurrency error
        raise HTTPException(status_code=409, detail=str(e))

@router.post("/{file_id}/cancel")
async def cancel_enhance_stream(file_id: str):
    """Request cancellation of a running enhancement stream for a file.

    The MLX model can't be preempted mid-forward-pass, but the stream
    generator checks the cancel flag once per token, so the loop breaks
    on the next token boundary (~10–50ms). Partial output is discarded
    and the file's `steps.enhance` reverts to its prior state.
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    requested = request_enhance_cancel(file_id)
    return {"success": True, "was_active": requested}


# =========================
# Enhancement Fields APIs
# =========================

async def _auto_compile_if_complete(file_id: str):
    await auto_compile_if_complete(file_id)


@router.post("/title/{file_id}")
async def set_enhance_title(file_id: str, body: dict):
    title = str(body.get('title') or '')
    if not title:
        raise HTTPException(status_code=400, detail="Missing 'title'")
    pf = status_tracker.get_file(file_id)
    if not pf:
        raise HTTPException(status_code=404, detail="File not found")
    status_tracker.set_enhancement_title(file_id, title)
    await _auto_compile_if_complete(file_id)
    return { 'success': True, 'file': status_tracker.get_file(file_id) }

@router.post("/copyedit/{file_id}")
async def set_enhance_copyedit(file_id: str, body: dict):
    text = str(body.get('text') or '')
    if not text:
        raise HTTPException(status_code=400, detail="Missing 'text'")
    pf = status_tracker.get_file(file_id)
    if not pf:
        raise HTTPException(status_code=404, detail="File not found")
    status_tracker.set_enhancement_fields(file_id, copyedit=text)
    await _auto_compile_if_complete(file_id)
    return { 'success': True, 'file': status_tracker.get_file(file_id) }

@router.post("/summary/{file_id}")
async def set_enhance_summary(background_tasks: BackgroundTasks, file_id: str, body: dict):
    summary = str(body.get('summary') or '')
    pf = status_tracker.get_file(file_id)
    if not pf:
        raise HTTPException(status_code=404, detail="File not found")
    status_tracker.set_enhancement_fields(file_id, summary=summary)
    await _auto_compile_if_complete(file_id)
    # Score importance in background while user picks tags
    background_tasks.add_task(_score_importance_bg, file_id)
    return { 'success': True, 'file': status_tracker.get_file(file_id) }

@router.post("/tags/{file_id}")
async def set_enhance_tags(file_id: str, body: dict):
    tags = body.get('tags') or []
    if not isinstance(tags, list):
        raise HTTPException(status_code=400, detail="'tags' must be a list")
    tags = [str(t).strip() for t in tags if str(t).strip()]
    pf = status_tracker.get_file(file_id)
    if not pf:
        raise HTTPException(status_code=404, detail="File not found")
    status_tracker.set_enhancement_fields(file_id, tags=tags)
    await _auto_compile_if_complete(file_id)
    return { 'success': True, 'tags': tags, 'file': status_tracker.get_file(file_id) }

# =========================
# Tag Management APIs
# =========================

@router.get("/tags/whitelist")
async def get_tag_whitelist():
    """Return the cached tag whitelist. Does not scan the vault."""
    try:
        return load_tag_whitelist()
    except ValueError as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/tags/whitelist/refresh")
async def refresh_tag_whitelist():
    """
    Scan the configured Obsidian vault (read-only) and rebuild the tag whitelist.
    - Reads tags from YAML frontmatter (tags: [...]) and inline #tags.
    - Excludes numeric-only and code-block tags; requires a letter.
    - Writes to enhancement.obsidian.tags_whitelist_path.
    """
    cfg = app_settings.get('enhancement.obsidian') or {}
    vault = (Path(cfg.get('vault_path') or '')).expanduser()
    wl_path = (Path(cfg.get('tags_whitelist_path') or '')).expanduser()

    if not str(vault):
        raise HTTPException(status_code=400, detail="Obsidian vault path not configured")
    if not vault.exists() or not vault.is_dir():
        raise HTTPException(status_code=400, detail="Obsidian vault path not found or not a directory")

    # Frontmatter only at file start; we only extract tags from YAML frontmatter, never inline #tags
    fm_start_rx = _re.compile(r"^---\n([\s\S]*?)\n---\n?", _re.MULTILINE)
    tags_key_rx = _re.compile(r"^tags:\s*(.+)$", _re.MULTILINE)
    yaml_list_rx = _re.compile(r"\[(.*?)\]")
    dash_item_rx = _re.compile(r"^-\s*([A-Za-z][A-Za-z0-9/_-]*)$", _re.MULTILINE)
    numeric_only_rx = _re.compile(r"^\d+$")

    tags = set()
    scanned = 0
    for p in vault.rglob('*.md'):
        # skip Obsidian internals
        if any(part.startswith('.obsidian') for part in p.parts):
            continue
        scanned += 1
        try:
            txt = p.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            continue
        # Frontmatter block only if at file start
        mfm = fm_start_rx.search(txt)
        if not mfm:
            continue
        block = mfm.group(1)
        # tags: line (list or scalar)
        for m in tags_key_rx.finditer(block):
            val = m.group(1).strip()
            mlist = yaml_list_rx.search(val)
            if mlist:
                for item in mlist.group(1).split(','):
                    t = item.strip().strip('"\'')
                    t = t.lstrip('-').lstrip('#').strip().lower()
                    if t and not numeric_only_rx.match(t):
                        tags.add(t)
            else:
                # Scalar form: tags: project
                t = val.strip().strip('"\'')
                t = t.lstrip('-').lstrip('#').strip().lower()
                if t and not numeric_only_rx.match(t):
                    tags.add(t)
        # dash items directly under tags: key
        if 'tags:' in block:
            # capture only contiguous dash lines after a 'tags:' line
            lines = block.splitlines()
            for i, line in enumerate(lines):
                if line.strip().startswith('tags:'):
                    j = i + 1
                    while j < len(lines) and lines[j].lstrip().startswith('-'):
                        m = _re.match(r"^\s*-\s*([A-Za-z][A-Za-z0-9/_-]*)\s*$", lines[j])
                        if m:
                            t = m.group(1).strip().lower()
                            if t and not numeric_only_rx.match(t):
                                tags.add(t)
                        j += 1
                    break

    data = { 'version': 1, 'count': len(tags), 'tags': sorted(tags) }
    try:
        wl_path.parent.mkdir(parents=True, exist_ok=True)
        wl_path.write_text(_json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write whitelist: {e}")

    return { 'success': True, 'count': len(tags), 'path': str(wl_path), 'scanned_files': scanned }

@router.post("/tags/generate/{file_id}")
async def generate_tags(file_id: str, body: dict = None):
    """
    Generate tag suggestions using MLX. Returns suggestions only (does not persist the final selection).
    """
    try:
        return await generate_tags_service(file_id)
    except ValueError as e:
        status = 404 if "not found" in str(e).lower() else 400
        raise HTTPException(status_code=status, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Tag generation failed: {e}")

# =========================
# Compilation API
# =========================

async def _compile_file(file_id: str) -> dict:
    return await compile_file(file_id)


@router.post("/compile/{file_id}")
async def compile_for_obsidian(file_id: str):
    """Compile a final Obsidian-ready markdown file (code only, no LLM)."""
    if not status_tracker.get_file(file_id):
        raise HTTPException(status_code=404, detail="File not found")
    try:
        return await compile_file(file_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write compiled note: {e}")

# =========================
# MLX Model Management APIs
# =========================

@router.get("/models/selected/chat-template")
async def get_selected_chat_template():
    """Return the chat template for the currently selected model plus any saved override."""
    cfg = app_settings.get('enhancement.mlx') or {}
    model_path = (cfg.get('model_path') or '').strip()
    if not model_path:
        return { 'template': None, 'override': None, 'source': 'none' }

    p = Path(model_path)
    template = None
    try:
        tc = p / 'tokenizer_config.json'
        if tc.exists():
            data = _json.loads(tc.read_text(encoding='utf-8', errors='ignore'))
            template = data.get('chat_template') or None
    except Exception:
        pass

    overrides = cfg.get('chat_template_overrides') or {}
    override = overrides.get(model_path) or None

    if override:
        source = 'override'
    elif template:
        source = 'tokenizer'
    else:
        source = 'none'
    return { 'template': template, 'override': override, 'source': source }


@router.get("/models")
async def list_enhance_models():
    # Derive models_dir from dependencies_folder via settings helper
    from config.settings import get_mlx_models_path

    cfg = app_settings.get('enhancement.mlx') or {}
    models_dir = get_mlx_models_path()
    selected = cfg.get('model_path')
    items = []

    def dir_size(path: Path) -> int:
        total = 0
        for root, dirs, files in os.walk(path):
            for f in files:
                try:
                    total += (Path(root) / f).stat().st_size
                except Exception:
                    pass
        return total

    for p in models_dir.iterdir():
        try:
            if p.is_file():
                size = p.stat().st_size
            elif p.is_dir():
                size = dir_size(p)
            else:
                continue
        except Exception:
            size = None
        items.append({
            'name': p.name,
            'path': str(p),
            'size': size,
            'selected': str(p) == str(selected) if selected else False
        })
    # Auto-select first model if current selection is missing or invalid
    if items and (not selected or not Path(str(selected)).exists()):
        first = items[0]['path']
        app_settings.set('enhancement.mlx.model_path', first)
        selected = first
        for it in items:
            it['selected'] = str(it['path']) == str(first)

    return { 'models': items, 'selected': selected }

@router.post("/models/upload")
async def upload_enhance_model(file: UploadFile = File(...)):
    import shutil
    from config.settings import get_mlx_models_path

    cfg = app_settings.get('enhancement.mlx') or {}
    models_dir = get_mlx_models_path()
    dest = models_dir / file.filename
    try:
        with dest.open('wb') as out:
            shutil.copyfileobj(file.file, out)
    finally:
        await file.close()
    return { 'success': True, 'path': str(dest), 'name': file.filename }

@router.delete("/models/{filename}")
async def delete_enhance_model(filename: str):
    from config.settings import get_mlx_models_path

    cfg = app_settings.get('enhancement.mlx') or {}
    models_dir = get_mlx_models_path()
    target = models_dir / filename
    if not target.exists():
        raise HTTPException(status_code=404, detail="Model file not found")
    # If currently selected, clear selection
    if cfg.get('model_path') and str(target) == str(cfg.get('model_path')):
        app_settings.set('enhancement.mlx.model_path', None)
    try:
        target.unlink()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete model: {e}")
    return { 'success': True }

@router.post("/models/select")
async def select_enhance_model(path: str = Form(...)):
    from config.settings import get_mlx_models_path

    cfg = app_settings.get('enhancement.mlx') or {}
    models_dir = get_mlx_models_path()
    p = Path(path)
    if not p.exists():
        raise HTTPException(status_code=400, detail="Invalid model path (not found)")
    # Only allow selections inside the app's models_dir
    try:
        p_resolved = p.resolve()
        models_dir_resolved = models_dir.resolve()
        if models_dir_resolved not in p_resolved.parents and p_resolved != models_dir_resolved:
            raise HTTPException(status_code=400, detail="Selecting external model paths is disabled. Use models in the app's models folder.")
    except Exception:
        raise HTTPException(status_code=400, detail="Unable to resolve model path")

    # Clear MLX model cache so next enhancement loads the new model fresh
    try:
        from services.mlx_cache import MLXModelCache
        MLXModelCache.get_instance().clear_cache()
        _logger.info(f"MLX cache cleared for model switch → {p.name}")
    except Exception as e:
        _logger.warning(f"Could not clear MLX cache: {e}")

    # Clear chat template overrides keyed by old model path
    old_path = (app_settings.get('enhancement.mlx.model_path') or '').strip()
    if old_path and old_path != str(p):
        overrides = dict((app_settings.get('enhancement.mlx.chat_template_overrides') or {}))
        if old_path in overrides:
            del overrides[old_path]
            app_settings.set('enhancement.mlx.chat_template_overrides', overrides)
            _logger.info(f"Cleared stale chat template override for {Path(old_path).name}")

    # Save selection
    app_settings.set('enhancement.mlx.model_path', str(p))
    return { 'success': True, 'selected': str(p) }
