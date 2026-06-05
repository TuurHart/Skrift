"""
File management API endpoints
Handles file upload, listing, and deletion operations
"""

import os
import shutil
import logging
from pathlib import Path
from typing import List

logger = logging.getLogger(__name__)
from fastapi import APIRouter, UploadFile, File, HTTPException, Form, Request
from fastapi.responses import JSONResponse, FileResponse, StreamingResponse

from models import PipelineFile, UploadResponse, TitleApprovalStatus
from utils.status_tracker import status_tracker, clear_transcript_derived
from config.settings import get_input_folder, get_output_folder, get_file_output_folder, settings

router = APIRouter()


def _ingest_markdown_note(pipeline_file, original_path: Path, file_size: int):
    """Parse an Apple Notes .md file and mark transcribe as done. Returns updated pipeline_file."""
    from services.apple_notes_importer import parse_markdown_note
    try:
        note_result = parse_markdown_note(original_path)
        note_text = note_result["text"]
        note_title = note_result["title"]
        attachments = note_result["attachments"]
    except Exception as e:
        logger.warning(f"Markdown note parse failed for {original_path.name}: {e}")
        note_text = original_path.read_text(encoding="utf-8", errors="replace")
        note_title = original_path.stem.rstrip(".")
        attachments = []

    # --- Strip title heading and extract inline #hashtags before saving transcript ---
    import re as _re
    _hashtag_rx = _re.compile(r'(?<!\w)#([A-Za-z][A-Za-z0-9_/-]*)\b')

    # Strip the leading # Title heading — it moves into the frontmatter title field
    body_lines = note_text.splitlines()
    if body_lines and body_lines[0].strip().startswith("# "):
        body_lines = body_lines[1:]
        while body_lines and not body_lines[0].strip():
            body_lines = body_lines[1:]
    body = "\n".join(body_lines)

    # Extract inline #hashtags from body
    extracted_tags: list[str] = []
    seen_tags: set[str] = set()
    for m in _hashtag_rx.finditer(body):
        tag = m.group(1).lower()
        if tag not in seen_tags:
            seen_tags.add(tag)
            extracted_tags.append(tag)

    # Strip # prefix from hashtags but keep the word in the body
    if extracted_tags:
        body = _hashtag_rx.sub(r'\1', body)

    pipeline_file.source_type = "note"
    status_tracker.save_file_status(pipeline_file.id)

    # Save the cleaned body (tags stripped, title removed) as the transcript
    status_tracker.update_file_status(
        pipeline_file.id, "transcribe", "done",
        result_content=body.strip()
    )

    status_tracker.add_audio_metadata(pipeline_file.id, {
        "note_title": note_title,
        "original_format": ".md",
        "uploaded_size": file_size,
        "attachments": [{"filename": a["filename"], "mime": a["mime"]} for a in attachments],
    })

    # Clean up stale .md artifacts from previous runs
    folder = original_path.parent
    for old_md in folder.glob("*.md"):
        if old_md.resolve() != original_path.resolve():
            try:
                old_md.unlink()
            except Exception as e:
                logger.warning(f"Could not remove stale .md {old_md.name}: {e}")

    # Generate compiled.md with YAML frontmatter
    import datetime as _dt
    try:
        st = original_path.stat()
        date_str = _dt.datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d")
    except Exception:
        date_str = ""

    # Format tags for YAML frontmatter
    if extracted_tags:
        tags_yaml = "tags: [" + ", ".join(extracted_tags) + "]"
    else:
        tags_yaml = "tags:"

    yaml_lines = [
        "---",
        f"title: {note_title}",
        f"date: {date_str}",
        "lastTouched:",
        "firstMentioned:",
        f"author: {(settings.get('export.author') or '').strip()}",
        "source: Apple-Note",
        "location:",
        tags_yaml,
        "significance:",
        "summary:",
        "---",
        "",
    ]
    compiled_content = "\n".join(yaml_lines) + body
    try:
        (folder / "compiled.md").write_text(compiled_content, encoding="utf-8")
    except Exception as e:
        logger.warning(f"Could not write compiled.md for note {original_path.name}: {e}")

    # Store compiled content and extracted tags in status.json
    try:
        pf = status_tracker.get_file(pipeline_file.id)
        if pf:
            pf.compiled_text = compiled_content
            if extracted_tags:
                pf.enhanced_tags = extracted_tags
            status_tracker.save_file_status(pipeline_file.id)
    except Exception:
        pass

    return status_tracker.get_file(pipeline_file.id)

@router.post("/upload", response_model=UploadResponse)
async def upload_files(
    files: List[UploadFile] = File(None),
    attachments: List[UploadFile] = File(None),  # Shared content files (images, etc.) from mobile capture
    images: List[UploadFile] = File(None),  # Timestamped photos captured during recording
    conversationMode: bool = Form(False),
    note_folder_paths: str = Form(None),  # JSON array of folder paths (Electron folder drops)
    metadata: str = Form(None),  # JSON string from mobile app with capture context
    photo: UploadFile = File(None),  # Optional photo from mobile app
    transcript: str = Form(None),  # Optional pre-made transcript from mobile on-device Parakeet
):
    """
    Upload audio files or Apple Notes export folders to the processing pipeline.
    Accepts either file uploads, folder paths (Electron), or both in one request.
    """
    import json as _json

    logger.info(f"Upload: files={[f.filename for f in files] if files else None}, note_folder_paths={note_folder_paths}")

    # Allow capture items with no audio (just metadata + optional attachments)
    has_capture_metadata = False
    if metadata:
        try:
            import json as _jcheck
            _meta_check = _jcheck.loads(metadata)
            has_capture_metadata = bool(_meta_check.get('sharedContent'))
        except Exception:
            pass

    if not files and not note_folder_paths and not has_capture_metadata:
        raise HTTPException(status_code=400, detail="No files provided")

    uploaded_files = []
    errors = []

    # --- Process note folders (Electron folder drops) ---
    if note_folder_paths:
        try:
            folder_paths = _json.loads(note_folder_paths)
        except Exception:
            folder_paths = []

        for folder_path_str in folder_paths:
            try:
                folder_path = Path(folder_path_str)
                logger.info(f"Apple Notes import: folder_path={folder_path}, exists={folder_path.exists()}, is_dir={folder_path.is_dir() if folder_path.exists() else 'N/A'}")
                if not folder_path.is_dir():
                    errors.append(f"Not a folder: {folder_path.name}")
                    continue

                md_files = list(folder_path.glob("*.md"))
                logger.info(f"Apple Notes import: found {len(md_files)} .md files: {[f.name for f in md_files]}")
                if not md_files:
                    errors.append(f"No .md file found in: {folder_path.name}")
                    continue

                md_file = md_files[0]
                import uuid as _uuid
                note_file_id = str(_uuid.uuid4())
                file_folder = get_file_output_folder(md_file.name, file_id=note_file_id)

                # Copy .md file
                original_path = file_folder / "original.md"
                shutil.copy2(md_file, original_path)

                # Copy Attachments/ folder if present
                src_attachments = folder_path / "Attachments"
                if src_attachments.is_dir():
                    shutil.copytree(src_attachments, file_folder / "Attachments", dirs_exist_ok=True)

                file_size = original_path.stat().st_size

                pipeline_file = status_tracker.create_file(
                    filename=md_file.name,
                    path=str(original_path),
                    size=file_size,
                    conversation_mode=False,
                    file_id=note_file_id
                )

                pipeline_file = _ingest_markdown_note(pipeline_file, original_path, file_size)
                uploaded_files.append(pipeline_file)

            except Exception as e:
                try:
                    label = Path(folder_path_str).name or folder_path_str
                except Exception:
                    label = str(folder_path_str)
                errors.append(f"Failed to import {label}: {str(e)}")

    # --- Process uploaded files ---
    # Get supported formats
    supported_formats = settings.get("audio.supported_input_formats", [".m4a", ".wav", ".mp3"])
    allowed_formats = set(supported_formats) | {".md"}

    for upload_file in (files or []):
        try:
            # Validate file type
            file_ext = Path(upload_file.filename).suffix.lower()
            if file_ext not in allowed_formats:
                errors.append(f"Unsupported file format: {upload_file.filename} ({file_ext})")
                continue

            # Generate UUID first so the folder name is unique even when two
            # files share the same filename (e.g. two "Voice Memo.m4a" uploads).
            import uuid as _uuid
            file_id = str(_uuid.uuid4())

            # Create file output folder using the UUID prefix
            file_folder = get_file_output_folder(upload_file.filename, file_id=file_id)

            # Save original file
            original_path = file_folder / f"original{file_ext}"
            with open(original_path, "wb") as f:
                content = await upload_file.read()
                f.write(content)

            file_size = len(content)

            pipeline_file = status_tracker.create_file(
                filename=upload_file.filename,
                path=str(original_path),
                size=file_size,
                conversation_mode=conversationMode,
                file_id=file_id
            )

            if file_ext == ".md":
                pipeline_file = _ingest_markdown_note(pipeline_file, original_path, file_size)

            else:
                # --- Audio file path ---
                pipeline_file.source_type = "audio"
                status_tracker.save_file_status(pipeline_file.id)
                audio_metadata = {
                    "original_format": file_ext,
                    "uploaded_size": file_size,
                    "conversation_mode": conversationMode,
                }

                # Extract audio duration using ffprobe
                try:
                    import subprocess
                    import json as json_module
                    duration_cmd = [
                        "ffprobe", "-v", "quiet", "-print_format", "json", "-show_format",
                        str(original_path)
                    ]
                    result = subprocess.run(duration_cmd, capture_output=True, text=True, timeout=10)
                    if result.returncode == 0:
                        probe_data = json_module.loads(result.stdout)
                        duration_seconds = float(probe_data.get("format", {}).get("duration", 0))
                        if duration_seconds > 0:
                            hours = int(duration_seconds // 3600)
                            minutes = int((duration_seconds % 3600) // 60)
                            seconds = int(duration_seconds % 60)
                            audio_metadata["duration"] = f"{hours:02d}:{minutes:02d}:{seconds:02d}"
                            audio_metadata["duration_seconds"] = duration_seconds
                except Exception as e:
                    logger.warning(f"Could not extract duration for {upload_file.filename}: {e}")

                status_tracker.add_audio_metadata(pipeline_file.id, audio_metadata)

                # --- Mobile metadata integration ---
                if metadata:
                    try:
                        import json as _json_meta
                        phone_meta = _json_meta.loads(metadata)
                        # Merge phone metadata into audioMetadata
                        mobile_fields = {}
                        if phone_meta.get("location"):
                            mobile_fields["phone_location"] = phone_meta["location"]
                        if phone_meta.get("weather"):
                            mobile_fields["phone_weather"] = phone_meta["weather"]
                        if phone_meta.get("pressure"):
                            mobile_fields["phone_pressure"] = phone_meta["pressure"]
                        if phone_meta.get("daylight"):
                            mobile_fields["phone_daylight"] = phone_meta["daylight"]
                        if phone_meta.get("dayPeriod"):
                            mobile_fields["phone_day_period"] = phone_meta["dayPeriod"]
                        if phone_meta.get("steps") is not None:
                            mobile_fields["phone_steps"] = phone_meta["steps"]
                        if phone_meta.get("capturedAt"):
                            mobile_fields["phone_captured_at"] = phone_meta["capturedAt"]
                        if phone_meta.get("recordedAt"):
                            mobile_fields["phone_recorded_at"] = phone_meta["recordedAt"]
                        mobile_fields["source"] = "mobile"
                        status_tracker.add_audio_metadata(pipeline_file.id, mobile_fields)

                        # Pre-populate tags from phone metadata
                        phone_tags = phone_meta.get("tags", [])
                        if phone_tags and isinstance(phone_tags, list):
                            pf = status_tracker.get_file(pipeline_file.id)
                            if pf:
                                pf.enhanced_tags = phone_tags
                                status_tracker.save_file_status(pipeline_file.id)
                    except Exception as e:
                        logger.warning(f"Failed to parse mobile metadata: {e}")

                # --- Pre-made transcript from mobile (on-device Parakeet) ---
                if transcript:
                    try:
                        import json as _json_t
                        _tmeta = _json_t.loads(metadata) if metadata else {}
                    except Exception:
                        _tmeta = {}
                    _conf = _tmeta.get("transcriptConfidence")
                    _user_edited = bool(_tmeta.get("transcriptUserEdited"))
                    _confidence_threshold = 0.7
                    try:
                        _conf_f = float(_conf) if _conf is not None else None
                    except Exception:
                        _conf_f = None
                    _trust = _user_edited or (_conf_f is not None and _conf_f >= _confidence_threshold)

                    if _trust:
                        try:
                            (file_folder / "transcript.txt").write_text(transcript, encoding="utf-8")
                        except Exception as e:
                            logger.warning(f"Could not write transcript.txt: {e}")

                        from models import ProcessingStatus as _PS
                        status_tracker.update_file_status(
                            pipeline_file.id, "transcribe", _PS.DONE,
                            result_content=transcript,
                        )
                        _markers_injected = bool(_tmeta.get("transcriptMarkersInjected"))
                        status_tracker.add_audio_metadata(pipeline_file.id, {
                            "transcript_source": "mobile",
                            "transcript_confidence": _conf_f,
                            "transcript_user_edited": _user_edited,
                            "transcript_markers_injected": _markers_injected,
                        })
                        pipeline_file = status_tracker.get_file(pipeline_file.id)
                        logger.info(f"[transcribe] accepted mobile transcript for {pipeline_file.id} (edited={_user_edited}, conf={_conf_f}, markers={_markers_injected})")
                    else:
                        logger.info(f"[transcribe] ignoring mobile transcript: confidence {_conf_f} < {_confidence_threshold}")

                # --- Timestamped photos from recording ---
                image_manifest_data = None
                if metadata:
                    try:
                        import json as _json_img
                        _img_meta = _json_img.loads(metadata)
                        image_manifest_data = _img_meta.get("imageManifest")
                    except Exception:
                        pass

                if images and image_manifest_data:
                    try:
                        images_dir = file_folder / "images"
                        images_dir.mkdir(exist_ok=True)
                        saved_manifest = []
                        for i, img_upload in enumerate(images):
                            if i < len(image_manifest_data):
                                manifest_entry = image_manifest_data[i]
                                img_filename = manifest_entry.get("filename", img_upload.filename or f"img_{i+1:03d}.jpg")
                            else:
                                img_filename = img_upload.filename or f"img_{i+1:03d}.jpg"
                                manifest_entry = {"filename": img_filename, "offsetSeconds": 0}

                            img_content = await img_upload.read()
                            img_path = images_dir / img_filename
                            with open(img_path, "wb") as imgf:
                                imgf.write(img_content)
                            saved_manifest.append({
                                "filename": img_filename,
                                "offsetSeconds": manifest_entry.get("offsetSeconds", 0),
                            })

                        # Write manifest file
                        import json as _json_manifest
                        manifest_path = file_folder / "image_manifest.json"
                        with open(manifest_path, "w") as mf:
                            _json_manifest.dump(saved_manifest, mf, indent=2)

                        status_tracker.add_audio_metadata(pipeline_file.id, {
                            "has_images": True,
                            "image_count": len(saved_manifest),
                        })
                        logger.info(f"Saved {len(saved_manifest)} timestamped photos for {pipeline_file.id}")
                    except Exception as e:
                        logger.warning(f"Failed to save timestamped photos: {e}")

                # --- Mobile photo (single cover photo, legacy flow) ---
                elif photo and photo.filename:
                    try:
                        photo_ext = Path(photo.filename).suffix.lower() or ".jpg"
                        photo_path = file_folder / f"photo{photo_ext}"
                        photo_content = await photo.read()
                        with open(photo_path, "wb") as pf:
                            pf.write(photo_content)
                        status_tracker.add_audio_metadata(pipeline_file.id, {
                            "phone_photo": str(photo_path),
                            "phone_photo_size": len(photo_content),
                        })
                    except Exception as e:
                        logger.warning(f"Failed to save mobile photo: {e}")

            uploaded_files.append(pipeline_file)
            
        except Exception as e:
            errors.append(f"Failed to upload {upload_file.filename}: {str(e)}")
    
    # --- Handle capture items with no audio file ---
    if not uploaded_files and has_capture_metadata and metadata:
        try:
            import json as _json_cap
            import uuid as _uuid
            phone_meta = _json_cap.loads(metadata)
            shared = phone_meta.get('sharedContent', {})
            share_type = shared.get('type', 'unknown')

            file_id = str(_uuid.uuid4())
            file_folder = get_file_output_folder(f"capture_{share_type}", file_id=file_id)

            # Write a placeholder original.json so orphan cleanup doesn't delete this entry
            placeholder_path = file_folder / "original.json"
            with open(placeholder_path, "w") as f:
                _json_cap.dump(shared, f)

            pipeline_file = status_tracker.create_file(
                filename=f"capture_{share_type}",
                path=str(placeholder_path),
                size=0,
                conversation_mode=False,
                file_id=file_id
            )
            pipeline_file.source_type = "capture"

            # Store shared content metadata
            mobile_fields = {"source": "mobile", "shared_content": shared}
            for key in ("location", "weather", "pressure", "daylight", "dayPeriod", "steps", "capturedAt", "recordedAt"):
                if phone_meta.get(key) is not None:
                    mobile_fields[f"phone_{key}" if key != "dayPeriod" else "phone_day_period"] = phone_meta[key]
            status_tracker.add_audio_metadata(pipeline_file.id, mobile_fields)

            # If there's a typed annotation, use it as the transcript directly
            annotation_text = phone_meta.get('annotationText', '')
            if annotation_text:
                pf = status_tracker.get_file(pipeline_file.id)
                if pf:
                    pf.transcript = annotation_text
                    pf.steps.transcribe = 'done'
                    pf.steps.sanitise = 'done'  # no name linking needed for typed text
                    status_tracker.save_file_status(pipeline_file.id)
            else:
                # No annotation at all — skip the pipeline, tag as unprocessed
                pf = status_tracker.get_file(pipeline_file.id)
                if pf:
                    pf.steps.transcribe = 'skipped'
                    pf.steps.sanitise = 'skipped'
                    pf.enhanced_tags = ['inbox/unprocessed']
                    status_tracker.save_file_status(pipeline_file.id)

            # Save shared content attachments
            if attachments:
                shared_dir = file_folder / "shared_content"
                shared_dir.mkdir(exist_ok=True)
                for att in attachments:
                    if att.filename:
                        att_path = shared_dir / att.filename
                        att_content = await att.read()
                        with open(att_path, "wb") as af:
                            af.write(att_content)
                        status_tracker.add_audio_metadata(pipeline_file.id, {
                            "shared_attachment": str(att_path),
                            "shared_attachment_name": att.filename,
                        })

            uploaded_files.append(status_tracker.get_file(pipeline_file.id))

        except Exception as e:
            errors.append(f"Failed to create capture item: {str(e)}")

    # --- Also store shared content metadata for audio uploads with capture context ---
    if uploaded_files and has_capture_metadata and metadata:
        try:
            import json as _json_sc
            phone_meta = _json_sc.loads(metadata)
            shared = phone_meta.get('sharedContent')
            if shared:
                for uf in uploaded_files:
                    if uf.source_type != 'capture':  # audio + capture hybrid
                        uf.source_type = 'capture'
                        status_tracker.add_audio_metadata(uf.id, {"shared_content": shared})
                        # Save attachments alongside audio
                        if attachments:
                            uf_folder = Path(uf.path).parent
                            shared_dir = uf_folder / "shared_content"
                            shared_dir.mkdir(exist_ok=True)
                            for att in attachments:
                                if att.filename:
                                    att_path = shared_dir / att.filename
                                    att_content = await att.read()
                                    with open(att_path, "wb") as af:
                                        af.write(att_content)
                                    status_tracker.add_audio_metadata(uf.id, {
                                        "shared_attachment": str(att_path),
                                        "shared_attachment_name": att.filename,
                                    })
                        status_tracker.save_file_status(uf.id)
        except Exception as e:
            logger.warning(f"Failed to store shared content metadata: {e}")

    if not uploaded_files and errors:
        raise HTTPException(status_code=400, detail=f"All uploads failed: {'; '.join(errors)}")
    
    return UploadResponse(
        success=True,
        files=uploaded_files,
        message=f"Successfully uploaded {len(uploaded_files)} file(s)",
        errors=errors if errors else None
    )

@router.get("/", response_model=List[PipelineFile])
async def get_files():
    """
    Get all pipeline files
    Returns array of PipelineFile objects
    """
    return status_tracker.get_all_files()

@router.get("/{file_id}", response_model=PipelineFile)
async def get_file(file_id: str):
    """
    Get a specific pipeline file by ID
    Returns single PipelineFile object with full details
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    return pipeline_file

@router.delete("/{file_id}")
async def delete_file(file_id: str):
    """
    Delete a pipeline file and all its associated data
    Returns success confirmation
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    try:
        # Delete file folder and all contents
        file_folder = Path(pipeline_file.path).parent
        if file_folder.exists():
            shutil.rmtree(file_folder)
        
        # Remove from status tracker
        status_tracker.delete_file(file_id)
        
        return {
            "success": True,
            "message": f"Successfully deleted {pipeline_file.filename}"
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete file: {str(e)}")

@router.get("/{file_id}/status")
async def get_file_status(file_id: str):
    """
    Get current processing status for a file
    Returns PipelineFile object with current status
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")

    return pipeline_file


@router.get("/{file_id}/images/{filename}")
async def get_file_image(file_id: str, filename: str):
    """
    Serve a timestamped photo from a file's images/ subfolder.
    Used by the desktop UI to render inline images in the note body.
    Supports both literal filenames (IMG_5351.jpeg) and manifest markers (img_001).
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")

    file_folder = Path(pipeline_file.path).parent

    # Resolve img_XXX markers via manifest (img_001 → manifest[0].filename)
    import re as _re_img
    marker_match = _re_img.match(r'^img_(\d{3})$', filename)
    if marker_match:
        import json as _json_img
        manifest_path = file_folder / "image_manifest.json"
        if manifest_path.exists():
            try:
                manifest = _json_img.loads(manifest_path.read_text(encoding="utf-8"))
                idx = int(marker_match.group(1)) - 1  # 1-indexed
                if 0 <= idx < len(manifest):
                    filename = manifest[idx].get("filename", filename)
            except Exception:
                pass

    # Look in the timestamped-photo dir (mobile capture) and the Apple-Notes
    # Attachments dir. Resolve must stay inside the note folder (no traversal).
    folder_resolved = str(file_folder.resolve())
    image_path = None
    for sub in ("images", "Attachments"):
        cand = (file_folder / sub / filename).resolve()
        if str(cand).startswith(folder_resolved) and cand.exists() and cand.is_file():
            image_path = cand
            break

    if image_path is None:
        raise HTTPException(status_code=404, detail=f"Image not found: {filename}")

    # Determine media type
    ext = image_path.suffix.lower()
    media_types = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".gif": "image/gif", ".webp": "image/webp"}
    media_type = media_types.get(ext, "application/octet-stream")

    return FileResponse(str(image_path), media_type=media_type)

@router.post("/{file_id}/title/approve")
async def approve_title(file_id: str):
    """
    Mark AI-generated title as accepted by user
    Sets title_approval_status to 'accepted' in status.json
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    if not pipeline_file.enhanced_title:
        raise HTTPException(status_code=400, detail="No AI-generated title available")
    
    # Update approval status
    pipeline_file.title_approval_status = TitleApprovalStatus.ACCEPTED
    status_tracker.save_file_status(file_id)

    # Recompile immediately so compiled_text in status.json reflects the approved title.
    # Without this, the debounced frontend auto-save might not fire before the user
    # switches files, causing the title to revert on return.
    try:
        from api.enhance import _auto_compile_if_complete
        await _auto_compile_if_complete(file_id)
    except Exception:
        pass

    return {
        "success": True,
        "message": "Title approved",
        "title": pipeline_file.enhanced_title
    }

@router.post("/{file_id}/title/decline")
async def decline_title(file_id: str):
    """
    Mark AI-generated title as declined by user
    Sets title_approval_status to 'declined' in status.json
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    if not pipeline_file.enhanced_title:
        raise HTTPException(status_code=400, detail="No AI-generated title available")
    
    # Update approval status
    pipeline_file.title_approval_status = TitleApprovalStatus.DECLINED
    status_tracker.save_file_status(file_id)
    
    return {
        "success": True,
        "message": "Title declined"
    }

@router.get("/{file_id}/content/{content_type}")
async def get_file_content(file_id: str, content_type: str):
    """
    Get file content (transcript, sanitised, enhanced, exported)
    Returns the requested content as plain text
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    content = None
    if content_type == "transcript":
        content = pipeline_file.transcript
    elif content_type == "sanitised":
        content = pipeline_file.sanitised
    elif content_type == "exported":
        content = pipeline_file.exported
    else:
        raise HTTPException(status_code=400, detail="Invalid content type")

    if content is None:
        raise HTTPException(status_code=404, detail=f"No {content_type} content available")

    return JSONResponse(
        content={"content": content, "type": content_type},
        media_type="application/json"
    )

@router.get("/{file_id}/audio/{which}")
async def get_file_audio(file_id: str, which: str, request: Request):
    """
    Stream audio for a file. `which` can be:
    - processed: the processed.wav (or *_processed.wav) artifact if available
    - original: the original uploaded audio
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")

    file_folder = Path(pipeline_file.path).parent

    path: Path | None = None
    if which == "processed":
        # Prefer explicit metadata path
        try:
            p = pipeline_file.audioMetadata.get("processed_wav_path") if pipeline_file.audioMetadata else None
        except Exception:
            p = None
        if p:
            cand = Path(p)
            if cand.exists():
                path = cand
        if path is None:
            # Look for processed.wav first, then *_processed.wav
            cand1 = file_folder / "processed.wav"
            if cand1.exists():
                path = cand1
            else:
                matches = list(file_folder.glob("*_processed.wav"))
                if matches:
                    path = matches[0]
    elif which == "original":
        path = Path(pipeline_file.path)
    else:
        raise HTTPException(status_code=400, detail="Invalid audio type")

    if not path or not path.exists():
        raise HTTPException(status_code=404, detail="Requested audio not available")

    # Derive media type by extension
    ext = path.suffix.lower()
    media = "audio/wav" if ext in [".wav"] else (
        "audio/mp4" if ext in [".m4a", ".mp4"] else "application/octet-stream"
    )
    # Common headers
    common_headers = {
        "Access-Control-Allow-Origin": "*",
        "Accept-Ranges": "bytes",
        "Content-Disposition": f"inline; filename=\"{path.name}\"",
        "Cache-Control": "no-store, max-age=0",
    }

    # If client requested a byte range, serve 206 with Content-Range
    range_header = request.headers.get("range") or request.headers.get("Range")
    file_size = path.stat().st_size
    if range_header and range_header.startswith("bytes="):
        try:
            range_value = range_header.split("=", 1)[1]
            start_s, end_s = range_value.split("-", 1)
            start = int(start_s) if start_s else 0
            end = int(end_s) if end_s else file_size - 1
            start = max(0, start)
            end = min(file_size - 1, end)
            length = end - start + 1
            def iter_file(p: Path, offset: int, length: int, chunk_size: int = 1024 * 64):
                with p.open("rb") as f:
                    f.seek(offset)
                    remaining = length
                    while remaining > 0:
                        chunk = f.read(min(chunk_size, remaining))
                        if not chunk:
                            break
                        remaining -= len(chunk)
                        yield chunk
            headers = dict(common_headers)
            headers.update({
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(length),
            })
            return StreamingResponse(iter_file(path, start, length), status_code=206, media_type=media, headers=headers)
        except Exception:
            # Fall back to full response if parsing fails
            pass

    # No (valid) Range header: send full file
    headers = dict(common_headers)
    headers.update({"Content-Length": str(file_size)})
    return FileResponse(str(path), media_type=media, filename=path.name, headers=headers)

@router.get("/{file_id}/word_timings")
async def get_file_word_timings(file_id: str):
    """
    Return compact per-word timings JSON for the editor.
    If word_timings.json exists, return it; otherwise synthesize from JSON-full.
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    folder = Path(pipeline_file.path).parent

    wt_path = None
    try:
        wt_path = pipeline_file.audioMetadata.get("word_timings_path") if pipeline_file.audioMetadata else None
    except Exception:
        wt_path = None
    if wt_path:
        p = Path(wt_path)
        if p.exists():
            try:
                txt = p.read_text(encoding='utf-8', errors='ignore')
                return JSONResponse(content=__import__('json').loads(txt), headers={"Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"})
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Failed to read word_timings.json: {e}")

    # Synthesize from JSON-full
    # Reuse the timeline parsing to get tokens and then join into words
    base = await get_file_timeline(file_id)
    tokens = base.get('tokens', [])
    if not tokens:
        raise HTTPException(status_code=404, detail="No tokens available to build word timings")

    def is_control(s: str) -> bool:
        return s.startswith('[_') and s.endswith('_]')
    def punct_only(s: str) -> bool:
        st = s.strip()
        return st != '' and all(not ch.isalnum() for ch in st)

    words = []
    cur_txt = ''
    cur_s = None
    cur_e = None
    def flush():
        nonlocal words, cur_txt, cur_s, cur_e
        if cur_txt:
            s = float(cur_s or 0.0); e = float(cur_e or cur_s or 0.0)
            words.append({ 'token_id': len(words), 'word': cur_txt, 'start': max(0.0, s), 'end': max(s, e) })
            cur_txt = ''; cur_s = None; cur_e = None

    for t in tokens:
        txt = str(t.get('text') or '')
        if is_control(txt):
            flush();
            continue
        starts_new = txt.startswith(' ') or txt.startswith('\t') or txt.startswith('\n') or punct_only(txt)
        stripped = txt.strip()
        if starts_new:
            flush()
        if not stripped or punct_only(stripped):
            flush();
            continue
        if not cur_txt:
            cur_txt = stripped; cur_s = t.get('start'); cur_e = t.get('end')
        else:
            cur_txt += stripped; cur_e = max(float(cur_e or 0.0), float(t.get('end') or 0.0))
    flush()

    if not words:
        raise HTTPException(status_code=404, detail="Failed to synthesize word timings from tokens")

    audio_dur = max((w['end'] for w in words), default=0.0)
    wt = { 'version': '1', 'audio': { 'processed_wav': 'processed.wav', 'duration_sec': audio_dur }, 'dtw_model': None, 'segments': [ { 'idx': 0, 'start': words[0]['start'], 'end': words[-1]['end'], 'words': words } ] }
    try:
        import json as _json
        (folder / 'word_timings.json').write_text(_json.dumps(wt, ensure_ascii=False, indent=2), encoding='utf-8')
        status_tracker.add_audio_metadata(file_id, {"word_timings_path": str(folder / 'word_timings.json')})
    except Exception:
        pass

    return JSONResponse(content=wt, headers={"Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"})


@router.get("/{file_id}/timeline")
async def get_file_timeline(file_id: str):
    """
    Return word-level timeline from word_timings.json (normalised by transcription service).
    Output format: { tokens: [{ text, start, end }], src: 'word_timings' }
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")

    # Prefer the normalised word_timings.json written by transcription service
    wt_path = None
    try:
        wt_path = (pipeline_file.audioMetadata or {}).get("word_timings_path")
    except Exception:
        pass
    if not wt_path:
        wt_path = str(Path(pipeline_file.path).parent / "word_timings.json")

    p = Path(wt_path)
    if not p.exists():
        raise HTTPException(status_code=404, detail="No word timing file found for this item")

    import json as _json
    try:
        data = _json.loads(p.read_text(encoding="utf-8", errors="ignore"))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to parse word timings: {e}")

    tokens = []
    try:
        for seg in (data.get('segments') or []):
            for w in (seg.get('words') or []):
                txt = w.get('word') or w.get('text') or ''
                s = float(w.get('start', 0))
                e = float(w.get('end', s))
                tokens.append({'text': txt, 'start': s, 'end': max(s, e)})
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read tokens: {e}")

    if not tokens:
        raise HTTPException(status_code=404, detail="No token timings found")

    return {'src': 'word_timings', 'tokens': tokens}

@router.put("/{file_id}/transcript")
async def update_transcript(file_id: str, content: dict):
    """
    Update the transcript content for a file
    Allows manual editing of transcripts
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    if "transcript" not in content:
        raise HTTPException(status_code=400, detail="Missing 'transcript' field in request body")
    
    try:
        # Update the transcript content
        pipeline_file.transcript = content["transcript"]
        
        # Save updated status
        status_tracker.save_file_status(file_id)
        
        return {
            "success": True,
            "message": f"Successfully updated transcript for {pipeline_file.filename}",
            "file": pipeline_file
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update transcript: {str(e)}")

@router.put("/{file_id}/sanitised")
async def update_sanitised(file_id: str, content: dict):
    """
    Update the sanitised text for a file without touching the original transcript.
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")

    if "sanitised" not in content:
        raise HTTPException(status_code=400, detail="Missing 'sanitised' field in request body")

    try:
        pipeline_file.sanitised = content["sanitised"]
        status_tracker.save_file_status(file_id)
        return {
            "success": True,
            "message": f"Successfully updated sanitised text for {pipeline_file.filename}",
            "file": pipeline_file
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update sanitised text: {str(e)}")

@router.post("/{file_id}/sanitise/cancel")
async def cancel_sanitise(file_id: str):
    """
    Cancel/reset the sanitise step only, without affecting other steps.
    Useful when the user dismisses the disambiguation dialog.
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    from models import ProcessingStatus
    # Set sanitise to pending and clear sanitised text for a clean rerun
    try:
        pipeline_file.steps.sanitise = ProcessingStatus.PENDING
        pipeline_file.sanitised = None
        status_tracker.save_file_status(file_id)
        return { 'success': True, 'message': 'Sanitise step reset to pending' }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to cancel sanitise: {e}")

@router.post("/{file_id}/reset")
async def reset_file(file_id: str):
    """
    Reset file processing status (for retry operations)
    Clears error status and resets steps to pending
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    try:
        from models import ProcessingSteps, ProcessingStatus

        # Preserve transcript if transcription was already done
        saved_transcript = pipeline_file.transcript if pipeline_file.steps.transcribe == ProcessingStatus.DONE else None

        # Reset all steps to pending
        pipeline_file.steps = ProcessingSteps()

        # Restore transcript and mark transcribe done if it was previously done
        if saved_transcript:
            pipeline_file.transcript = saved_transcript
            pipeline_file.steps.transcribe = ProcessingStatus.DONE

        # Clear all transcript-derived content (single shared invalidation list)
        clear_transcript_derived(pipeline_file)

        # Clear error information
        pipeline_file.error = None
        pipeline_file.errorDetails = None

        # Delete compiled.md so Export tab doesn't show stale content
        try:
            compiled = Path(pipeline_file.path).parent / "compiled.md"
            if compiled.exists():
                compiled.unlink()
        except Exception:
            pass

        status_tracker.save_file_status(file_id)

        return {
            "success": True,
            "message": f"Successfully reset {pipeline_file.filename}",
            "file": pipeline_file
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to reset file: {str(e)}")
