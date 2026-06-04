"""
Sanitisation API endpoints
Handles text sanitisation with name linking and disambiguation
"""

from fastapi import APIRouter, HTTPException
from models import ProcessingRequest, ProcessingResponse, ProcessingStatus
from utils.status_tracker import status_tracker
from services.sanitisation import process_sanitisation, resolve_name_disambiguation

router = APIRouter()


@router.post("/{file_id}", response_model=ProcessingResponse)
async def start_sanitise(file_id: str):
    """
    Start text sanitise for a file (British spelling)
    - Removes filler words
    - Links only the FIRST mention of each person to [[Canonical Name]] based on config/names.json
    - Case-insensitive, whole-word matching; supports multi-word aliases
    - Preserves possessives (e.g. "Seb's" -> "[[Sebastiaan Paap]]'s")
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    
    # Ensure transcription completed
    if pipeline_file.steps.transcribe != ProcessingStatus.DONE:
        raise HTTPException(status_code=400, detail="Transcription must be completed before sanitise")
    
    # If already processing, short-circuit
    if pipeline_file.steps.sanitise == ProcessingStatus.PROCESSING:
        return ProcessingResponse(
            status="already_processing",
            message="Sanitise already in progress",
            file=pipeline_file
        )
    
    try:
        text = pipeline_file.transcript or ""
        if not text:
            raise ValueError("No transcript available to sanitise")
        
        # Call service layer
        result = process_sanitisation(file_id, text)

        if result['status'] == 'error':
            raise ValueError(result['error'])

        # Persist the linked text. Unambiguous names are already linked; any
        # ambiguous occurrences are carried as data on the note (resolved at the
        # review step) rather than blocking the pipeline with a 409.
        status_tracker.update_file_status(
            file_id,
            "sanitise",
            ProcessingStatus.DONE,
            result_content=result['result_content']
        )
        pf = status_tracker.get_file(file_id)
        if pf is not None:
            pf.ambiguous_names = result.get('ambiguous_occurrences') or None
            status_tracker.save_file_status(file_id)

        return ProcessingResponse(
            status="done",
            message="Sanitise completed",
            file=status_tracker.get_file(file_id)
        )
    except Exception as e:
        status_tracker.update_file_status(
            file_id,
            "sanitise",
            ProcessingStatus.ERROR,
            error=str(e)
        )
        raise HTTPException(status_code=500, detail=f"Failed to sanitise: {str(e)}")
        

@router.post("/{file_id}/resolve")
async def resolve_sanitise(file_id: str, body: dict):
    """
    Resolve ambiguous alias occurrences.
    Body: { session_id, decisions: [{ alias, offset, person_id, apply_to_remaining?: bool }] }
    - person_id should match a candidate 'id' from the 409 response (we use canonical string as id)
    - apply_to_remaining: if true, all remaining occurrences of alias map to this person
    """
    pipeline_file = status_tracker.get_file(file_id)
    if not pipeline_file:
        raise HTTPException(status_code=404, detail="File not found")
    if pipeline_file.steps.transcribe != ProcessingStatus.DONE:
        raise HTTPException(status_code=400, detail="Transcription must be completed before sanitise")

    text = pipeline_file.transcript or ""
    if not text:
        raise HTTPException(status_code=400, detail="No transcript available to sanitise")

    # Call service layer
    decisions = body.get('decisions') or []
    result = resolve_name_disambiguation(file_id, text, decisions)
    
    if result['status'] == 'error':
        raise HTTPException(status_code=500, detail=result['error'])
    
    # Save result
    status_tracker.update_file_status(
        file_id,
        "sanitise",
        ProcessingStatus.DONE,
        result_content=result['result_content']
    )
    return { 'status': 'done', 'message': 'Sanitise completed', 'file': status_tracker.get_file(file_id) }
