"""
Batch processing API endpoints.
Handles batch transcription and enhancement operations.
"""

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from typing import List, Dict, Any
from pydantic import BaseModel
import asyncio

from services.batch_manager import BatchManager, BatchStatus
from utils.status_tracker import status_tracker
from pathlib import Path

router = APIRouter()

# Initialize batch manager (singleton instance)
BATCH_DATA_DIR = Path(__file__).parent.parent / "data"
batch_manager = BatchManager(BATCH_DATA_DIR)


class StartBatchRequest(BaseModel):
    """Request to start a batch operation"""
    file_ids: List[str]
    batch_type: str = "transcribe"  # or "enhance"
    force: bool = False  # Re-run even when files are already done


class CancelBatchRequest(BaseModel):
    """Request to cancel a batch"""
    batch_id: str


@router.post("/transcribe/start")
async def start_transcribe_batch(request: StartBatchRequest):
    """
    Start a new transcription batch.
    
    Files will be processed sequentially in order of audio creation date (oldest first).
    Only one batch can be active at a time.
    """
    if not request.file_ids:
        raise HTTPException(status_code=400, detail="No file IDs provided")
    
    # Verify all files exist; include those still pending or all when force=True
    untranscribed_files = []
    for file_id in request.file_ids:
        file = status_tracker.get_file(file_id)
        if not file:
            raise HTTPException(status_code=404, detail=f"File not found: {file_id}")

        if request.force or file.steps.transcribe != "done":
            untranscribed_files.append(file_id)

    if not untranscribed_files:
        raise HTTPException(
            status_code=400,
            detail="All files have already been transcribed (pass force=true to re-run)"
        )

    # When forcing, clear downstream data via the shared helper so single-file
    # and batch paths stay consistent (clears tag_suggestions, significance,
    # title_approval_status — all of which used to leak stale state into the UI).
    if request.force:
        for file_id in untranscribed_files:
            pf = status_tracker.get_file(file_id)
            if not pf or pf.steps.transcribe != "done":
                continue
            status_tracker.reset_for_retranscribe(file_id)
    
    try:
        # Start the batch
        batch_state = await batch_manager.start_transcribe_batch(
            file_ids=untranscribed_files,
            file_service=status_tracker,
            transcription_service=None  # Will be handled internally by batch_manager
        )
        
        return {
            "success": True,
            "message": f"Batch started with {len(untranscribed_files)} files",
            "batch": batch_state
        }
    
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to start batch: {str(e)}")


@router.get("/{batch_id}/status")
async def get_batch_status(batch_id: str):
    """
    Get the status of a specific batch.
    
    Returns batch state including:
    - Overall batch status (running/completed/cancelled/failed)
    - Progress (completed/total files)
    - Individual file statuses
    - Error information if any
    """
    batch = batch_manager.get_current_batch()
    
    if not batch or batch.get("batch_id") != batch_id:
        raise HTTPException(status_code=404, detail="Batch not found")
    
    # Calculate progress
    total_files = len(batch.get("files", []))
    completed_files = sum(
        1 for f in batch.get("files", []) 
        if f.get("status") in ["completed", "skipped"]
    )
    failed_files = sum(
        1 for f in batch.get("files", []) 
        if f.get("status") == "failed"
    )
    
    return {
        "batch_id": batch_id,
        "status": batch.get("status"),
        "type": batch.get("type"),
        "progress": {
            "total": total_files,
            "completed": completed_files,
            "failed": failed_files,
            "current": completed_files + failed_files,
            "percentage": int((completed_files + failed_files) / total_files * 100) if total_files > 0 else 0
        },
        "files": batch.get("files", []),
        "consecutive_failures": batch.get("consecutive_failures", 0),
        "created_at": batch.get("created_at"),
        "updated_at": batch.get("updated_at")
    }


@router.post("/{batch_id}/cancel")
async def cancel_batch(batch_id: str):
    """
    Cancel an active batch.
    
    This will stop processing new files but won't interrupt the current file.
    The current file will complete (or fail) normally.
    """
    batch = batch_manager.get_current_batch()
    
    if not batch or batch.get("batch_id") != batch_id:
        raise HTTPException(status_code=404, detail="Batch not found")
    
    if batch.get("status") != BatchStatus.RUNNING:
        raise HTTPException(
            status_code=400, 
            detail=f"Cannot cancel batch with status: {batch.get('status')}"
        )
    
    try:
        state = await batch_manager.cancel_batch()
        return {
            "success": True,
            "message": "Batch cancelled successfully",
            "batch_id": batch_id,
            "status": state.get("status") if isinstance(state, dict) else None,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to cancel batch: {str(e)}")


@router.get("/current")
async def get_current_batch():
    """
    Get the currently active batch (if any).
    
    Returns None if no batch is active.
    Useful for UI to check if batch processing is in progress.
    """
    batch = batch_manager.get_current_batch()
    
    if not batch:
        return {
            "active": False,
            "batch": None
        }
    
    # Calculate progress
    total_files = len(batch.get("files", []))
    completed_files = sum(
        1 for f in batch.get("files", []) 
        if f.get("status") in ["completed", "skipped"]
    )
    failed_files = sum(
        1 for f in batch.get("files", []) 
        if f.get("status") == "failed"
    )
    
    return {
        "active": batch.get("status") == BatchStatus.RUNNING,
        "batch": {
            "batch_id": batch.get("batch_id"),
            "status": batch.get("status"),
            "type": batch.get("type"),
            "progress": {
                "total": total_files,
                "completed": completed_files,
                "failed": failed_files,
                "current": completed_files + failed_files,
                "percentage": int((completed_files + failed_files) / total_files * 100) if total_files > 0 else 0
            },
            "files": batch.get("files", []),
            "current_file_id": batch.get("current_file_id"),
            "consecutive_failures": batch.get("consecutive_failures", 0),
            "created_at": batch.get("created_at"),
            "updated_at": batch.get("updated_at")
        }
    }


@router.post("/enhance/start")
async def start_enhance_batch(request: StartBatchRequest):
    """
    Start a new enhancement batch.
    
    Files will be processed sequentially through Title → Copy Edit → Summary → Tags pipeline.
    Skips already-completed steps. Only one batch can be active at a time.
    """
    if not request.file_ids:
        raise HTTPException(status_code=400, detail="No file IDs provided")
    
    # Verify all files exist and have sanitised text
    eligible_files = []
    for file_id in request.file_ids:
        file = status_tracker.get_file(file_id)
        if not file:
            raise HTTPException(status_code=404, detail=f"File not found: {file_id}")
        
        # Must have transcription done
        if file.steps.transcribe != "done":
            raise HTTPException(
                status_code=400,
                detail=f"File {file_id} has not been transcribed yet."
            )

        # Must have content to enhance (sanitised for audio; transcript for notes)
        content = (file.sanitised or file.transcript or '').strip()
        if not content:
            raise HTTPException(
                status_code=400,
                detail=f"File {file_id} has no content to enhance. Run sanitisation first."
            )
        
        # Include file if any enhancement step is incomplete
        # Note: tag_suggestions OR enhanced_tags both count as "tags done" for eligibility
        has_title = bool((file.enhanced_title or '').strip())
        has_copy = bool((file.enhanced_copyedit or '').strip())
        has_summary = bool((file.enhanced_summary or '').strip())
        has_tag_suggestions = bool(file.tag_suggestions and 
                                   (file.tag_suggestions.get('old') or file.tag_suggestions.get('new')))
        has_approved_tags = bool(file.enhanced_tags and len(file.enhanced_tags) > 0)
        has_tags = has_tag_suggestions or has_approved_tags
        
        if not (has_title and has_copy and has_summary and has_tags):
            eligible_files.append(file_id)
    
    if not eligible_files:
        raise HTTPException(
            status_code=400,
            detail="All files have already been enhanced (Title, Copy Edit, Summary, and Tags completed)"
        )
    
    try:
        # Start the batch
        batch_state = await batch_manager.start_enhance_batch(
            file_ids=eligible_files,
            file_service=status_tracker
        )
        
        return {
            "success": True,
            "message": f"Batch started with {len(eligible_files)} files",
            "batch": batch_state
        }
    
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to start batch: {str(e)}")


@router.post("/run/start")
async def start_run(request: StartBatchRequest):
    """Run the canonical pipeline for the given files: transcribe → enhance →
    name-link → compile → Ready for Review. One Process action; a single file is
    a run of one. Files already at Ready (title + copy-edit + summary present)
    are skipped unless they still need transcription.
    """
    if not request.file_ids:
        raise HTTPException(status_code=400, detail="No file IDs provided")

    eligible = []
    for file_id in request.file_ids:
        f = status_tracker.get_file(file_id)
        if not f:
            raise HTTPException(status_code=404, detail=f"File not found: {file_id}")
        needs_transcribe = f.steps.transcribe not in ("done", "skipped")
        ready = bool(
            (f.enhanced_title or '').strip()
            and (f.enhanced_copyedit or '').strip()
            and (f.enhanced_summary or '').strip()
        )
        if needs_transcribe or not ready:
            eligible.append(file_id)

    if not eligible:
        raise HTTPException(
            status_code=400,
            detail="All selected files are already processed (Ready for review)."
        )

    # Fail fast if the enhancement model isn't configured/present.
    from config.settings import settings as _settings
    mlx_cfg = _settings.get('enhancement.mlx') or {}
    model_path = (mlx_cfg.get('model_path') or '').strip()
    if not model_path or not Path(model_path).exists():
        raise HTTPException(
            status_code=400,
            detail="MLX model not selected or not found. Check Settings > Enhancement."
        )

    try:
        batch_state = await batch_manager.start_run(
            file_ids=eligible,
            file_service=status_tracker,
        )
        return {
            "success": True,
            "message": f"Run started with {len(eligible)} file(s)",
            "batch": batch_state,
        }
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to start run: {str(e)}")


@router.delete("/{batch_id}")
async def delete_batch(batch_id: str):
    """
    Delete a batch (only allowed for completed/cancelled/failed batches).
    
    This clears the batch state from disk.
    """
    batch = batch_manager.get_current_batch()
    
    if not batch or batch.get("batch_id") != batch_id:
        raise HTTPException(status_code=404, detail="Batch not found")
    
    if batch.get("status") == BatchStatus.RUNNING:
        raise HTTPException(
            status_code=400, 
            detail="Cannot delete a running batch. Cancel it first."
        )
    
    try:
        batch_manager._clear_state()
        return {
            "success": True,
            "message": "Batch deleted successfully",
            "batch_id": batch_id
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete batch: {str(e)}")


@router.get("/enhance/stream")
async def stream_batch_enhance():
    """
    Stream live output from batch enhancement processing.
    
    Returns SSE stream with events:
    - start: {"file_id", "step"} when a step begins
    - token: text chunk from current LLM generation
    - done: {"file_id", "step"} when a step completes
    - error: {"file_id", "step", "error"} on error
    """
    import logging
    logger = logging.getLogger(__name__)
    print("🔌 [SSE] New SSE client connecting to /api/batch/enhance/stream", flush=True)
    logger.info("🔌 New SSE client connecting to /api/batch/enhance/stream")
    
    async def event_generator():
        # Create a queue for this client
        client_queue = asyncio.Queue(maxsize=100)
        logger.info("📡 Created client queue for batch SSE stream")
        
        # Register with batch manager
        batch_manager.register_stream_client(client_queue)
        logger.info(f"✅ Client registered with batch manager. Total clients: {len(batch_manager._stream_clients)}")
        
        try:
            # Send initial connection event
            yield f"event: connected\ndata: {{}}\n\n"
            
            # Stream events from the queue
            while True:
                try:
                    # Wait for event with timeout for heartbeat
                    event_type, data = await asyncio.wait_for(client_queue.get(), timeout=2.0)
                    
                    # Format as SSE
                    # Split data into lines for proper SSE format
                    data_lines = data.split('\n') if isinstance(data, str) else [data]
                    sse_output = f"event: {event_type}\n"
                    for line in data_lines:
                        sse_output += f"data: {line}\n"
                    sse_output += "\n"
                    
                    yield sse_output
                    
                except asyncio.TimeoutError:
                    # Send heartbeat to keep connection alive
                    yield f"event: heartbeat\ndata: .\n\n"
                    
        except asyncio.CancelledError:
            # Client disconnected
            logger.info("🔌 Client disconnected from batch SSE stream (cancelled)")
            pass
        finally:
            # Unregister client
            batch_manager.unregister_stream_client(client_queue)
            logger.info(f"✅ Client unregistered from batch manager. Remaining clients: {len(batch_manager._stream_clients)}")
    
    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
