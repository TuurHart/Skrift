"""
Data models for Audio Transcription Pipeline API
Defines the PipelineFile structure matching frontend expectations
"""

from typing import Optional, Dict, Any, List
from enum import Enum
from datetime import datetime
from pydantic import BaseModel, Field, model_validator

class ProcessingStatus(str, Enum):
    """Status values for pipeline processing steps"""
    PENDING = "pending"
    PROCESSING = "processing" 
    DONE = "done"
    ERROR = "error"
    SKIPPED = "skipped"

class TitleApprovalStatus(str, Enum):
    """Approval state for an AI-generated title"""
    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"

class ProcessingSteps(BaseModel):
    """Processing status for each pipeline step"""
    transcribe: ProcessingStatus = ProcessingStatus.PENDING
    sanitise: ProcessingStatus = ProcessingStatus.PENDING
    enhance: ProcessingStatus = ProcessingStatus.PENDING
    export: ProcessingStatus = ProcessingStatus.PENDING

class PipelineFile(BaseModel):
    """
    Main data model matching frontend PipelineFile interface
    Represents an audio file in the processing pipeline
    """
    id: str = Field(..., description="Unique identifier for the file")
    filename: str = Field(..., description="Original filename")
    path: str = Field(..., description="Full path to the file")
    size: int = Field(..., description="File size in bytes")
    
    # Processing metadata
    conversationMode: bool = Field(False, description="Whether this is a conversation or solo recording")
    steps: ProcessingSteps = Field(default_factory=ProcessingSteps, description="Status of each processing step")
    
    # File timestamps
    uploadedAt: datetime = Field(default_factory=datetime.now, description="When file was uploaded")
    lastModified: Optional[datetime] = Field(None, description="Last modification timestamp")
    lastActivityAt: Optional[datetime] = Field(None, description="Last processing activity timestamp")
    
    # Processing results
    transcript: Optional[str] = Field(None, description="Raw transcription text")
    sanitised: Optional[str] = Field(None, description="Sanitised text")
    exported: Optional[str] = Field(None, description="Final exported content")

    # Enhancement pipeline fields
    enhanced_title: Optional[str] = Field(None, description="Effective title used for compile/export (selected or edited)")
    title_suggested: Optional[str] = Field(None, description="The LLM-generated title, preserved so the review chooser can offer it as an alternative")
    title_approval_status: Optional[TitleApprovalStatus] = Field(None, description="Title approval status")
    enhanced_copyedit: Optional[str] = Field(None, description="Copy-edited text (applied)")
    enhanced_summary: Optional[str] = Field(None, description="One-sentence summary produced by enhancement")
    enhanced_tags: Optional[List[str]] = Field(None, description="Selected tags from whitelist for this file")
    tag_suggestions: Optional[Dict[str, List[str]]] = Field(None, description="Tag suggestions awaiting user approval: {'old': [...], 'new': [...]}" )

    # Ambiguous name occurrences recorded during name-linking (an alias that maps
    # to 2+ people). Carried as data and resolved at the review step instead of
    # blocking the pipeline with a 409. Shape mirrors the old 409 'occurrences'.
    ambiguous_names: Optional[List[Dict[str, Any]]] = Field(None, description="Unresolved ambiguous name occurrences for review-time disambiguation")

    # Transient: which enhancement step is currently streaming for this file.
    # Set by generate_enhancement_stream when a step starts, cleared when it
    # ends (or on cancel). Polled by the frontend so the Inspector can show
    # the active step even when the local SSE isn't attached (e.g. user
    # switched tabs mid-stream).
    enhance_step: Optional[str] = Field(None, description="Currently streaming enhance step: 'title' | 'copy_edit' | 'summary' | 'tags' | None")

    # Personal significance score (0.0–1.0) from LLM
    significance: Optional[float] = Field(None, description="Personal significance score (0.0-1.0) rated by LLM")

    @model_validator(mode='before')
    @classmethod
    def _migrate_confidence(cls, data):
        """Migrate old status.json files that used 'confidence' → 'significance'."""
        if isinstance(data, dict) and 'confidence' in data and 'significance' not in data:
            data['significance'] = data.pop('confidence')
        elif isinstance(data, dict) and 'confidence' in data:
            data.pop('confidence')
        return data

    # Source type: 'audio' for voice recordings, 'note' for Apple Notes ENEX imports
    source_type: Optional[str] = Field(None, description="Source type: 'audio' or 'note'")

    # Compiled markdown content — persisted in status.json as the single source of truth.
    # Written by compile_for_obsidian and _ingest_markdown_note; edited in-place via the Export tab.
    compiled_text: Optional[str] = Field(None, description="Compiled markdown ready for export (cached in status.json)")

    # Export preferences
    include_audio_in_export: Optional[bool] = Field(None, description="Whether to include original audio file in Obsidian export for this item")
    
    # Error handling
    error: Optional[str] = Field(None, description="Error message if processing failed")
    errorDetails: Optional[Dict[str, Any]] = Field(None, description="Detailed error information")
    
    # Processing metadata
    processingTime: Optional[Dict[str, float]] = Field(None, description="Time taken for each step")
    audioMetadata: Optional[Dict[str, Any]] = Field(None, description="Audio file metadata (duration, format, etc.)")
    
    # Progress tracking
    progress: Optional[int] = Field(None, description="Current progress percentage (0-100)")
    progressMessage: Optional[str] = Field(None, description="Current progress status message")
    
    def get_activity_age_seconds(self) -> Optional[int]:
        """Get the age of last activity in seconds"""
        if not self.lastActivityAt:
            return None
        return int((datetime.now() - self.lastActivityAt).total_seconds())
    
    def is_activity_stale(self, threshold_seconds: int = 120) -> bool:
        """Check if activity is stale (default: 2 minutes)"""
        age = self.get_activity_age_seconds()
        return age is not None and age > threshold_seconds

class UploadResponse(BaseModel):
    """Response for file upload operations"""
    success: bool
    files: List[PipelineFile]
    message: Optional[str] = None
    errors: Optional[List[str]] = None

class ProcessingRequest(BaseModel):
    """Request for processing operations"""
    conversationMode: Optional[bool] = None
    enhancementType: Optional[str] = None
    prompt: Optional[str] = None
    exportFormat: Optional[str] = None
    force: Optional[bool] = None  # force re-run even if step is already done

class ProcessingResponse(BaseModel):
    """Response for processing operations"""
    status: str
    message: str
    estimatedTime: Optional[str] = None
    file: Optional[PipelineFile] = None

class SystemResources(BaseModel):
    """System resource monitoring data"""
    cpuUsage: float = Field(..., description="CPU usage percentage")
    ramUsed: float = Field(..., description="RAM used in GB")
    ramTotal: float = Field(..., description="Total RAM in GB")
    coreTemp: Optional[float] = Field(None, description="CPU temperature in Celsius")
    diskUsed: Optional[float] = Field(None, description="Disk usage percentage")

class SystemStatus(BaseModel):
    """System processing status"""
    processing: bool = Field(..., description="Whether system is currently processing")
    currentFile: Optional[str] = Field(None, description="Currently processing file")
    currentStep: Optional[str] = Field(None, description="Current processing step")
    queueLength: int = Field(0, description="Number of files in processing queue")

class ConfigUpdate(BaseModel):
    """Configuration update request"""
    key: str = Field(..., description="Configuration key using dot notation")
    value: Any = Field(..., description="New configuration value")

class ConfigResponse(BaseModel):
    """Configuration response"""
    success: bool
    message: str
    config: Optional[Dict[str, Any]] = None
