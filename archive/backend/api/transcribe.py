"""
Transcription API endpoints
Handles audio transcription with Parakeet-MLX
"""

import threading
from fastapi import APIRouter, HTTPException, BackgroundTasks
from models import ProcessingRequest, ProcessingResponse, ProcessingStatus
from utils.status_tracker import status_tracker
from services.transcription import process_transcription_thread

router = APIRouter()


@router.post("/{file_id}", response_model=ProcessingResponse)
async def start_transcription(background_tasks: BackgroundTasks, file_id: str, request: ProcessingRequest = ProcessingRequest()):
    """Start transcription for a file using Parakeet-MLX."""
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")

    # Check if already processing (allow force to override stale processing state)
    if pipeline_file.steps.transcribe == ProcessingStatus.PROCESSING and not request.force:
        return ProcessingResponse(
            status="already_processing",
            message="Transcription already in progress",
            file=pipeline_file
        )

    # If already done and not forcing a redo, return early
    if pipeline_file.steps.transcribe == ProcessingStatus.DONE and not request.force:
        return ProcessingResponse(
            status="already_done",
            message="Transcription already completed",
            file=pipeline_file
        )

    # Force redo: clear all downstream data so the UI never shows stale
    # enhancements/tags. Centralised on status_tracker so single-file +
    # batch force paths stay in sync.
    if pipeline_file.steps.transcribe == ProcessingStatus.DONE and request.force:
        status_tracker.reset_for_retranscribe(pipeline_file.id)

    try:
        # Update status to processing
        status_tracker.update_file_status(
            file_id,
            "transcribe",
            ProcessingStatus.PROCESSING
        )

        # Start transcription in a separate thread
        thread = threading.Thread(target=process_transcription_thread, args=(file_id,))
        thread.start()

        return ProcessingResponse(
            status="started",
            message="Transcription started",
            estimatedTime="1-5 minutes",
            file=status_tracker.get_file(file_id)
        )

    except Exception as e:
        status_tracker.update_file_status(
            file_id,
            "transcribe",
            ProcessingStatus.ERROR,
            error=str(e)
        )
        raise HTTPException(status_code=500, detail=f"Failed to start transcription: {str(e)}")
