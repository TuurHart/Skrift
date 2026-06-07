"""
Export API Router
Handles all export-related endpoints including:
- Getting and saving compiled markdown
- Starting document export tasks
"""

from datetime import datetime
from fastapi import APIRouter, HTTPException
from models import ProcessingStatus
from utils.status_tracker import status_tracker
from services.export import get_compiled_markdown as get_compiled_markdown_service, save_compiled_markdown as save_compiled_markdown_service

router = APIRouter()


@router.get("/compiled/{file_id}")
async def get_compiled_markdown(file_id: str):
    """Return current compiled markdown content for a file.
    Resolution order for the active markdown file in the file's output folder:
    1) compiled.md if present
    2) If exactly one *.md exists, use that
    3) Otherwise, use the most recently modified *.md
    Returns 404 only if no *.md exists at all.
    """
    result = get_compiled_markdown_service(file_id)
    
    if result['status'] == 'error':
        if 'not found' in result['error'].lower():
            raise HTTPException(status_code=404, detail=result['error'])
        raise HTTPException(status_code=500, detail=result['error'])
    
    # Get enhanced_title from status.json
    pipeline_file = status_tracker.get_file(file_id)
    enhanced_title = pipeline_file.enhanced_title if pipeline_file else None
    
    return { 
        'path': result['path'], 
        'title': result['title'], 
        'content': result['content'],
        'enhanced_title': enhanced_title
    }

@router.put("/compiled/{file_id}")
async def put_compiled_text(file_id: str, body: dict):
    """Save compiled text edits to status.json (compiled_text field) only. Does not write files to disk."""
    pf = status_tracker.get_file(file_id)
    if not pf:
        raise HTTPException(status_code=404, detail="File not found")
    pf.compiled_text = str(body.get('content') or '')
    pf.lastModified = datetime.now()
    status_tracker.save_file_status(file_id)
    return {'success': True}


@router.post("/compiled/{file_id}")
async def save_compiled_markdown(file_id: str, body: dict):
    """Save compiled markdown edits and optionally export (rename) based on YAML title.
    Body: { content: str, export_to_vault?: bool, vault_path?: string, include_audio?: bool }
    Logic changes:
    - Determine the active markdown filename using the same resolver as GET.
    - A plain Save writes to the active file (overwriting it). It will not create a second .md.
    - Save & Export renames the active file to <YAML title>.md, then deletes any other .md siblings to prevent duplicates.
    - If a vault_path or configured export.note_folder is valid, copy the renamed file there.
    - If include_audio is true, also copy the original audio into export.audio_folder and insert an Obsidian embed.
    """
    content = str(body.get('content') or '')
    export_to_vault = bool(body.get('export_to_vault') or False)
    vault_path = body.get('vault_path') or None
    include_audio = bool(body.get('include_audio') or False)
    
    result = save_compiled_markdown_service(file_id, content, export_to_vault, vault_path, include_audio)

    # Always keep compiled_text in status.json in sync with what was saved
    if result.get('status') != 'error':
        pf = status_tracker.get_file(file_id)
        if pf:
            pf.compiled_text = content
            pf.lastModified = datetime.now()
            status_tracker.save_file_status(file_id)

    if result['status'] == 'error':
        if 'not found' in result['error'].lower():
            raise HTTPException(status_code=404, detail=result['error'])
        if 'missing' in result['error'].lower() or 'must include' in result['error'].lower():
            raise HTTPException(status_code=400, detail=result['error'])
        raise HTTPException(status_code=500, detail=result['error'])
    
    # Return appropriate response based on export type
    if export_to_vault:
        resp = {
            'success': result['success'],
            'exported_path': result.get('exported_path'),
            'vault_exported_path': result.get('vault_exported_path'),
        }
        # Optional audio export details
        if 'audio_exported_path' in result:
            resp['audio_exported_path'] = result.get('audio_exported_path')
        if 'audio_filename' in result:
            resp['audio_filename'] = result.get('audio_filename')
        return resp
    else:
        return {
            'success': result['success'],
            'path': result.get('path')
        }

