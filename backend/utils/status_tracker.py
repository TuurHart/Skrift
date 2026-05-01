"""
Status tracking utility for Audio Transcription Pipeline
Manages file processing status using JSON files
"""

import json
import uuid
import threading
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
from models import PipelineFile, ProcessingStatus, ProcessingSteps, TitleApprovalStatus
from config.settings import get_output_folder

# All PipelineFile fields that are derived from the transcript and must be
# cleared when a new transcript arrives. Add new enhancement pipeline fields
# here to ensure they are always cascade-invalidated.
_TRANSCRIPT_DERIVED_FIELDS = (
    "sanitised",
    "enhanced_copyedit",
    "enhanced_summary",
    "enhanced_title",
    "enhanced_tags",
    "tag_suggestions",
    "exported",
    "compiled_text",
    "title_approval_status",
)


class StatusTracker:
    """Manages file processing status using JSON files"""

    def __init__(self):
        self._files: Dict[str, PipelineFile] = {}
        # Per-file locks prevent torn writes when batch threads and the event loop
        # both call save_file_status for the same file concurrently.
        self._locks: Dict[str, threading.Lock] = defaultdict(threading.Lock)
        self.load_existing_files()
    
    def load_existing_files(self):
        """Load existing files from status.json files"""
        output_folder = get_output_folder()
        if not output_folder.exists():
            return
        
        for file_folder in output_folder.iterdir():
            if file_folder.is_dir():
                status_file = file_folder / "status.json"
                if status_file.exists():
                    try:
                        with open(status_file, 'r') as f:
                            data = json.load(f)
                            # Construct model
                            pipeline_file = PipelineFile(**data)
                            
                            # Backfill compiled_text from compiled.md if not yet in status.json
                            if not pipeline_file.compiled_text:
                                compiled_md = file_folder / "compiled.md"
                                if compiled_md.exists():
                                    try:
                                        pipeline_file.compiled_text = compiled_md.read_text(encoding="utf-8")
                                        # Persist so future loads don't need to re-read the file
                                        self._files[pipeline_file.id] = pipeline_file
                                        self.save_file_status(pipeline_file.id)
                                    except Exception:
                                        pass

                            # Validate that the actual audio file exists
                            if Path(pipeline_file.path).exists():
                                self._files[pipeline_file.id] = pipeline_file
                            else:
                                print(f"Warning: Audio file not found, removing orphaned entry: {pipeline_file.path}")
                                # Clean up orphaned status file
                                status_file.unlink()
                                
                    except Exception as e:
                        print(f"Warning: Could not load status file {status_file}: {e}")
                        # Remove corrupted status file
                        try:
                            status_file.unlink()
                        except Exception:
                            pass
    
    def create_file(self,
                   filename: str,
                   path: str,
                   size: int,
                   conversation_mode: bool = False,
                   file_id: str = None) -> PipelineFile:
        """Create a new pipeline file entry"""

        if file_id is None:
            file_id = str(uuid.uuid4())
        
        pipeline_file = PipelineFile(
            id=file_id,
            filename=filename,
            path=path,
            size=size,
            conversationMode=conversation_mode,
            uploadedAt=datetime.now(),
            steps=ProcessingSteps()
        )
        
        self._files[file_id] = pipeline_file
        self.save_file_status(file_id)
        
        return pipeline_file
    
    def get_file(self, file_id: str) -> Optional[PipelineFile]:
        """Get a pipeline file by ID"""
        return self._files.get(file_id)
    
    def get_all_files(self) -> List[PipelineFile]:
        """Get all pipeline files"""
        return list(self._files.values())
    
    def update_file_status(self, 
                          file_id: str, 
                          step: str, 
                          status: ProcessingStatus,
                          error: Optional[str] = None,
                          result_content: Optional[str] = None) -> Optional[PipelineFile]:
        """Update the status of a processing step"""
        
        if file_id not in self._files:
            return None
        
        pipeline_file = self._files[file_id]
        
        # Update step status
        if hasattr(pipeline_file.steps, step):
            setattr(pipeline_file.steps, step, status)
        
        # Handle error: set if provided; if explicitly empty string, clear; if None, leave unchanged
        if error is not None:
            if error == "":
                pipeline_file.error = None
                pipeline_file.errorDetails = None
            else:
                pipeline_file.error = error
                pipeline_file.errorDetails = {
                    "step": step,
                    "timestamp": datetime.now().isoformat(),
                    "message": error
                }
        
        # Store result content
        if result_content:
            if step == "transcribe":
                # When a new transcript arrives, invalidate any stale downstream content
                # that was based on a previous transcript (e.g. from a prior run or
                # a content-bleed bug). This prevents wrong sanitised/enhanced data
                # from silently persisting and polluting later pipeline steps.
                if (pipeline_file.sanitised or '').strip() or pipeline_file.compiled_text:
                    for field in _TRANSCRIPT_DERIVED_FIELDS:
                        setattr(pipeline_file, field, None)
                    pipeline_file.steps.sanitise = ProcessingStatus.PENDING
                    pipeline_file.steps.enhance = ProcessingStatus.PENDING
                    pipeline_file.steps.export = ProcessingStatus.PENDING
                pipeline_file.transcript = result_content
            elif step == "sanitise":
                pipeline_file.sanitised = result_content
            elif step == "enhance":
                # Legacy 'enhanced' field is deprecated; store copy-edit output instead
                pipeline_file.enhanced_copyedit = result_content
            elif step == "export":
                pipeline_file.exported = result_content
        
        # Update timestamps
        pipeline_file.lastModified = datetime.now()
        pipeline_file.lastActivityAt = datetime.now()
        
        # Save to file
        self.save_file_status(file_id)
        
        return pipeline_file
    
    def clear_error(self, file_id: str):
        """Clear top-level error and errorDetails for a file and persist."""
        if file_id not in self._files:
            return
        pf = self._files[file_id]
        pf.error = None
        pf.errorDetails = None
        pf.lastModified = datetime.now()
        pf.lastActivityAt = datetime.now()
        self.save_file_status(file_id)

    def add_processing_time(self, file_id: str, step: str, time_seconds: float):
        """Add processing time for a step"""
        if file_id not in self._files:
            return
        
        pipeline_file = self._files[file_id]
        if pipeline_file.processingTime is None:
            pipeline_file.processingTime = {}
        
        pipeline_file.processingTime[step] = time_seconds
        self.save_file_status(file_id)
    
    def add_audio_metadata(self, file_id: str, metadata: Dict[str, Any]):
        """Add audio metadata to a file. Merge keys instead of overwriting the entire object."""
        if file_id not in self._files:
            return
        
        pipeline_file = self._files[file_id]
        if pipeline_file.audioMetadata is None:
            pipeline_file.audioMetadata = {}
        try:
            # Merge keys
            for k, v in (metadata or {}).items():
                pipeline_file.audioMetadata[k] = v
        except Exception:
            # Fallback: overwrite if merge failed unexpectedly
            pipeline_file.audioMetadata = metadata
        self.save_file_status(file_id)

    def set_enhancement_fields(self, file_id: str, *, working: Optional[str] = None, copyedit: Optional[str] = None, summary: Optional[str] = None, tags: Optional[List[str]] = None):
        """Set enhancement pipeline fields and persist.
        - working: legacy (maps to copyedit)
        - copyedit: preferred name for copy-edited text
        - summary: one-sentence summary
        - tags: selected tags
        """
        if file_id not in self._files:
            return
        pf = self._files[file_id]
        # Back-compat: working maps to copyedit
        if copyedit is None and working is not None:
            copyedit = working
        if copyedit is not None:
            # Model field is enhanced_copyedit
            try:
                pf.enhanced_copyedit = copyedit
            except Exception:
                # Older models: fall back to enhanced_working if present
                setattr(pf, 'enhanced_working', copyedit)
        if summary is not None:
            pf.enhanced_summary = summary
        if tags is not None:
            pf.enhanced_tags = tags
            pf.tag_suggestions = None  # Clear suggestions when tags are applied
        pf.lastModified = datetime.now()
        pf.lastActivityAt = datetime.now()
        self.save_file_status(file_id)
    
    def set_enhancement_title(self, file_id: str, title: str):
        """Set enhanced title for a file and persist. Resets approval status to pending."""
        if file_id not in self._files:
            return
        pf = self._files[file_id]
        pf.enhanced_title = title
        pf.title_approval_status = TitleApprovalStatus.PENDING
        pf.lastModified = datetime.now()
        pf.lastActivityAt = datetime.now()
        self.save_file_status(file_id)
    
    def reset_for_retranscribe(self, file_id: str) -> bool:
        """Clear all downstream state so a forced re-transcribe starts clean.

        Used by both the single-file `/api/process/transcribe/{id}?force=true`
        and the batch `/api/batch/transcribe/start` (with `force=true`) flows
        — keep them in sync so the UI never shows stale enhancements/tags
        after a re-transcribe.

        Also deletes the cached `processed.wav` so audio preprocessing runs
        fresh with current denoiser settings.

        Does NOT change steps.transcribe to PENDING — caller is expected to
        immediately set it to PROCESSING.
        """
        if file_id not in self._files:
            return False
        pf = self._files[file_id]

        pf.transcript = None
        pf.sanitised = None
        pf.exported = None
        pf.enhanced_title = None
        pf.title_approval_status = None
        pf.enhanced_copyedit = None
        pf.enhanced_summary = None
        pf.enhanced_tags = None
        pf.tag_suggestions = None
        pf.compiled_text = None
        pf.significance = None

        pf.steps.transcribe = ProcessingStatus.PENDING
        pf.steps.sanitise = ProcessingStatus.PENDING
        pf.steps.enhance = ProcessingStatus.PENDING
        pf.steps.export = ProcessingStatus.PENDING

        self.save_file_status(file_id)

        try:
            cached_wav = Path(pf.path).parent / "processed.wav"
            if cached_wav.exists():
                cached_wav.unlink()
        except Exception:
            pass

        return True

    def delete_file(self, file_id: str) -> bool:
        """Delete a pipeline file and its status"""
        if file_id not in self._files:
            return False
        
        pipeline_file = self._files[file_id]
        
        # Remove status file without recreating the folder
        try:
            file_folder = Path(pipeline_file.path).parent
            status_file = file_folder / "status.json"
            if status_file.exists():
                status_file.unlink()
        except Exception:
            pass
        
        # Remove from memory
        del self._files[file_id]
        
        return True
    
    def save_file_status(self, file_id: str):
        """Save file status to JSON file"""
        if file_id not in self._files:
            return
        
        pipeline_file = self._files[file_id]
        # Use the actual stored path rather than recalculating from filename.
        # This is collision-safe: two files with the same filename but different
        # UUIDs in their folder names both resolve correctly.
        file_folder = Path(pipeline_file.path).parent
        status_file = file_folder / "status.json"
        
        # Convert to dict for JSON serialization
        data = pipeline_file.model_dump()
        
        # Convert datetime objects to ISO strings
        if isinstance(data.get('uploadedAt'), datetime):
            data['uploadedAt'] = data['uploadedAt'].isoformat()
        if isinstance(data.get('lastModified'), datetime):
            data['lastModified'] = data['lastModified'].isoformat()
        if isinstance(data.get('lastActivityAt'), datetime):
            data['lastActivityAt'] = data['lastActivityAt'].isoformat()
        
        with self._locks[file_id]:
            with open(status_file, 'w') as f:
                json.dump(data, f, indent=2, default=str)
    
    def get_processing_queue(self) -> List[PipelineFile]:
        """Get files that are currently being processed"""
        processing_files = []
        for file in self._files.values():
            steps = file.steps
            if (steps.transcribe == ProcessingStatus.PROCESSING or
                steps.sanitise == ProcessingStatus.PROCESSING or
                steps.enhance == ProcessingStatus.PROCESSING or
                steps.export == ProcessingStatus.PROCESSING):
                processing_files.append(file)
        return processing_files
    
    def get_files_by_status(self, step: str, status: ProcessingStatus) -> List[PipelineFile]:
        """Get files filtered by step status"""
        filtered_files = []
        for file in self._files.values():
            if hasattr(file.steps, step):
                step_status = getattr(file.steps, step)
                if step_status == status:
                    filtered_files.append(file)
        return filtered_files

    def update_file_progress(self, file_id: str, step: str, progress: int, status_message: str):
        """Update file progress percentage and status message"""
        if file_id not in self._files:
            return

        pipeline_file = self._files[file_id]

        # Update progress and message directly
        pipeline_file.progress = progress
        pipeline_file.progressMessage = status_message
        
        # Update timestamps
        pipeline_file.lastModified = datetime.now()
        pipeline_file.lastActivityAt = datetime.now()

        # Save to file
        self.save_file_status(file_id)
    
    def update_last_activity(self, file_id: str, message: Optional[str] = None):
        """Update only the last activity timestamp and optionally the message"""
        if file_id not in self._files:
            return
            
        pipeline_file = self._files[file_id]
        pipeline_file.lastActivityAt = datetime.now()
        
        if message:
            pipeline_file.progressMessage = message
            
        # Save to file
        self.save_file_status(file_id)


# Global status tracker instance
status_tracker = StatusTracker()
