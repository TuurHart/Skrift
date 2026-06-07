"""
Processing API endpoints
Handles generic pipeline operations: status checking and cancellation
"""

from fastapi import APIRouter, HTTPException
from models import ProcessingStatus
from utils.status_tracker import status_tracker
from services.transcription import cancel_transcription_process

router = APIRouter()



@router.get("/{file_id}/status")
async def get_processing_status(file_id: str):
    """
    Get current processing status for a file
    Returns complete PipelineFile object
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    return pipeline_file

@router.post("/{file_id}/cancel")
async def cancel_processing(file_id: str):
    """
    Cancel any ongoing processing for a file
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    # Check if the file is stuck (no activity for 5+ minutes)
    is_stuck = False
    if pipeline_file.lastActivityAt:
        activity_age = pipeline_file.get_activity_age_seconds()
        if activity_age and activity_age > 300:  # 5 minutes
            is_stuck = True
    
    # Reset processing steps
    steps = pipeline_file.steps
    message_parts = []
    
    if steps.transcribe == ProcessingStatus.PROCESSING or steps.transcribe == ProcessingStatus.ERROR:
        # Try to kill any running Whisper subprocess as well
        try:
            cancelled_proc = cancel_transcription_process(file_id)
        except Exception:
            cancelled_proc = False
        status_tracker.update_file_status(file_id, "transcribe", ProcessingStatus.PENDING)
        message_parts.append("transcription")
    if steps.sanitise == ProcessingStatus.PROCESSING or steps.sanitise == ProcessingStatus.ERROR:
        status_tracker.update_file_status(file_id, "sanitise", ProcessingStatus.PENDING)
        message_parts.append("sanitisation")
    if steps.enhance == ProcessingStatus.PROCESSING or steps.enhance == ProcessingStatus.ERROR:
        status_tracker.update_file_status(file_id, "enhance", ProcessingStatus.PENDING)
        message_parts.append("enhancement")
    if steps.export == ProcessingStatus.PROCESSING or steps.export == ProcessingStatus.ERROR:
        status_tracker.update_file_status(file_id, "export", ProcessingStatus.PENDING)
        message_parts.append("export")
    
    # Clear error and progress info
    pipeline_file = status_tracker.get_file(file_id)
    if pipeline_file:
        pipeline_file.error = None
        pipeline_file.errorDetails = None
        pipeline_file.progress = None
        pipeline_file.progressMessage = None
        pipeline_file.lastActivityAt = None
        status_tracker.save_file_status(file_id)
    
    message = "Processing cancelled"
    if message_parts:
        message = f"Cancelled {', '.join(message_parts)}"
    if is_stuck:
        message += " (process was stuck)"
    
    return {
        "success": True,
        "message": message,
        "file": status_tracker.get_file(file_id)
    }
