"""
Batch processing manager for sequential transcription and enhancement.
Handles batch lifecycle, state persistence, and consecutive failure tracking.
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any
from enum import Enum
from config.settings import settings

logger = logging.getLogger(__name__)


class BatchType(str, Enum):
    TRANSCRIBE = "transcribe"
    ENHANCE = "enhance"


class BatchStatus(str, Enum):
    RUNNING = "running"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    FAILED = "failed"


class FileStatus(str, Enum):
    WAITING = "waiting"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class BatchManager:
    """Manages sequential batch processing for transcription and enhancement."""
    
    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.state_file = self.data_dir / "batch_state.json"
        self.current_batch: Optional[Dict[str, Any]] = None
        self.processing_task: Optional[asyncio.Task] = None
        self._stream_clients: set = set()  # Connected SSE clients for live streaming

        self._load_state()
    
    def _load_state(self):
        """Load batch state from disk if it exists."""
        if self.state_file.exists():
            try:
                with open(self.state_file, 'r') as f:
                    self.current_batch = json.load(f)
                logger.info(f"Loaded existing batch state: {self.current_batch.get('batch_id')}")
            except Exception as e:
                logger.error(f"Failed to load batch state: {e}")
                self.current_batch = None
    
    def _save_state(self):
        """Persist current batch state to disk."""
        try:
            with open(self.state_file, 'w') as f:
                json.dump(self.current_batch, f, indent=2)
        except Exception as e:
            logger.error(f"Failed to save batch state: {e}")
    
    def _clear_state(self):
        """Clear batch state from disk."""
        try:
            if self.state_file.exists():
                self.state_file.unlink()
            self.current_batch = None
        except Exception as e:
            logger.error(f"Failed to clear batch state: {e}")
    
    def has_active_batch(self) -> bool:
        """Check if there's an active batch."""
        return (
            self.current_batch is not None 
            and self.current_batch.get("status") == BatchStatus.RUNNING
        )
    
    def get_current_batch(self) -> Optional[Dict[str, Any]]:
        """Get current batch state."""
        return self.current_batch
    
    def register_stream_client(self, queue: asyncio.Queue):
        """Register a new SSE client for batch streaming."""
        self._stream_clients.add(queue)
        logger.info(f"Stream client registered. Total clients: {len(self._stream_clients)}")
    
    def unregister_stream_client(self, queue: asyncio.Queue):
        """Unregister an SSE client."""
        self._stream_clients.discard(queue)
        logger.info(f"Stream client unregistered. Total clients: {len(self._stream_clients)}")
    
    async def broadcast(self, event_type: str, data: Any):
        """Broadcast an event to all connected SSE clients."""
        if not self._stream_clients:
            logger.debug(f"Skipping broadcast of '{event_type}': no SSE clients connected")
            return
        
        # Convert data to JSON if it's a dict
        if isinstance(data, dict):
            import json as _json
            data_str = _json.dumps(data)
        else:
            data_str = str(data)
        
        # Send to all clients (remove dead queues)
        dead_clients = set()
        for client_queue in self._stream_clients:
            try:
                # Non-blocking put with timeout
                await asyncio.wait_for(client_queue.put((event_type, data_str)), timeout=0.1)
            except asyncio.TimeoutError:
                logger.warning("Client queue full, skipping event")
            except Exception as e:
                logger.error(f"Failed to broadcast to client: {e}")
                dead_clients.add(client_queue)
        
        # Clean up dead clients
        for dead_client in dead_clients:
            self.unregister_stream_client(dead_client)
    
    async def start_transcribe_batch(
        self, 
        file_ids: List[str],
        file_service: Any,
        transcription_service: Any
    ) -> Dict[str, Any]:
        """
        Start a new transcription batch.
        
        Args:
            file_ids: List of file IDs to transcribe (will be sorted by creation date)
            file_service: FileService instance for file operations
            transcription_service: TranscriptionService instance
            
        Returns:
            Batch state dictionary
        """
        if self.has_active_batch():
            raise ValueError("A batch is already running. Cancel it first.")
        
        # Sort files by audio creation date (oldest first)
        sorted_file_ids = await self._sort_files_by_creation_date(file_ids, file_service)
        
        batch_id = f"batch_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        self.current_batch = {
            "batch_id": batch_id,
            "type": BatchType.TRANSCRIBE,
            "status": BatchStatus.RUNNING,
            "files": [
                {
                    "file_id": file_id,
                    "status": FileStatus.WAITING,
                    "error": None,
                    "started_at": None,
                    "completed_at": None
                }
                for file_id in sorted_file_ids
            ],
            "consecutive_failures": 0,
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat()
        }
        
        self._save_state()
        
        # Start processing in background
        self.processing_task = asyncio.create_task(
            self._process_batch(file_service, transcription_service)
        )
        
        logger.info(f"Started transcribe batch {batch_id} with {len(sorted_file_ids)} files")
        return self.current_batch
    
    async def _sort_files_by_creation_date(
        self, 
        file_ids: List[str], 
        file_service: Any
    ) -> List[str]:
        """Sort file IDs by audio creation date (oldest first)."""
        file_dates = []
        
        for file_id in file_ids:
            try:
                file_obj = file_service.get_file(file_id)
                if not file_obj:
                    continue
                
                # Try to get creation date from audioMetadata
                creation_date = None
                if file_obj.audioMetadata:
                    creation_date = file_obj.audioMetadata.get("creation_date")
                
                # Fallback to uploadedAt
                if not creation_date:
                    creation_date = file_obj.uploadedAt
                
                if creation_date:
                    # Ensure it's a string
                    if not isinstance(creation_date, str):
                        creation_date = creation_date.isoformat()
                    file_dates.append((file_id, creation_date))
                else:
                    # Fallback: use current time
                    file_dates.append((file_id, datetime.now().isoformat()))
            except Exception as e:
                logger.warning(f"Failed to get creation date for {file_id}: {e}")
                file_dates.append((file_id, datetime.now().isoformat()))
        
        # Sort by date (oldest first)
        file_dates.sort(key=lambda x: x[1])
        return [file_id for file_id, _ in file_dates]
    
    async def _process_batch(self, file_service: Any, transcription_service: Any):
        """Process all files in the batch sequentially using parakeet-mlx."""
        try:
            from services.transcription import process_transcription_thread
            from utils.status_tracker import status_tracker

            for file_entry in self.current_batch["files"]:
                # Check if batch was cancelled
                if self.current_batch["status"] == BatchStatus.CANCELLED:
                    logger.info("Batch was cancelled, stopping processing")
                    break

                # Check consecutive failure limit
                max_failures = int(settings.get('batch.max_consecutive_failures') or 3)
                if self.current_batch["consecutive_failures"] >= max_failures:
                    logger.error(f"Reached {max_failures} consecutive failures, stopping batch")
                    self.current_batch["status"] = BatchStatus.FAILED
                    self._save_state()
                    break

                file_id = file_entry["file_id"]

                # Skip if already processed
                if file_entry["status"] in [FileStatus.COMPLETED, FileStatus.SKIPPED]:
                    continue

                # Update status to processing
                file_entry["status"] = FileStatus.PROCESSING
                file_entry["started_at"] = datetime.now().isoformat()
                self.current_batch["updated_at"] = datetime.now().isoformat()
                self._save_state()

                logger.info(f"Processing file {file_id} in batch")

                try:
                    # Mark file as processing via status tracker
                    status_tracker.update_file_status(file_id, "transcribe", "processing")

                    # Run synchronous transcription in thread executor
                    loop = asyncio.get_event_loop()
                    await loop.run_in_executor(None, process_transcription_thread, file_id)

                    file_entry["status"] = FileStatus.COMPLETED
                    file_entry["completed_at"] = datetime.now().isoformat()
                    self.current_batch["consecutive_failures"] = 0
                    logger.info(f"File {file_id} transcribed successfully")

                except Exception as e:
                    logger.error(f"Failed to transcribe {file_id}: {e}")
                    file_entry["status"] = FileStatus.FAILED
                    file_entry["error"] = str(e)
                    file_entry["completed_at"] = datetime.now().isoformat()
                    self.current_batch["consecutive_failures"] += 1

                self.current_batch["updated_at"] = datetime.now().isoformat()
                self._save_state()

            # Mark batch as completed if not cancelled/failed
            if self.current_batch["status"] == BatchStatus.RUNNING:
                self.current_batch["status"] = BatchStatus.COMPLETED
                self.current_batch["updated_at"] = datetime.now().isoformat()
                self._save_state()
                logger.info(f"Batch {self.current_batch['batch_id']} completed")

        except Exception as e:
            logger.error(f"Batch processing failed: {e}")
            import traceback
            traceback.print_exc()
            self.current_batch["status"] = BatchStatus.FAILED
            self.current_batch["updated_at"] = datetime.now().isoformat()
            self._save_state()
    
    async def cancel_batch(self) -> Dict[str, Any]:
        """Cancel the current batch."""
        if not self.current_batch:
            raise ValueError("No active batch to cancel")
        
        if self.current_batch["status"] != BatchStatus.RUNNING:
            raise ValueError("Batch is not running")
        
        # Mark current file as failed (if any)
        current_file_id = self.current_batch.get("current_file_id")
        if current_file_id:
            for file_entry in self.current_batch["files"]:
                if file_entry["file_id"] == current_file_id:
                    if file_entry["status"] == FileStatus.PROCESSING:
                        file_entry["status"] = FileStatus.FAILED
                        file_entry["error"] = "Batch cancelled by user"
                        file_entry["completed_at"] = datetime.now().isoformat()
                        # Mark current step as failed
                        if file_entry.get("current_step"):
                            file_entry["steps"][file_entry["current_step"]] = "failed"
                        file_entry["current_step"] = None
                    break
        
        # Mark as cancelled
        self.current_batch["status"] = BatchStatus.CANCELLED
        self.current_batch["current_file_id"] = None
        self.current_batch["updated_at"] = datetime.now().isoformat()
        self._save_state()
        
        # Cancel processing task if running
        if self.processing_task and not self.processing_task.done():
            self.processing_task.cancel()
            try:
                await self.processing_task
            except asyncio.CancelledError:
                pass
        
        logger.info(f"Batch {self.current_batch['batch_id']} cancelled")
        return self.current_batch
    
    def _compute_batch_result(self) -> str:
        """
        Compute final batch result based on file completion status.
        
        Returns:
            'success': All files completed all steps (done or skipped)
            'partial_success': Some files completed, some failed
            'failed': All files failed or no files completed
        """
        if not self.current_batch or not self.current_batch.get("files"):
            return "failed"
        
        files = self.current_batch["files"]
        fully_completed_count = 0
        failed_count = 0
        
        for file_entry in files:
            steps = file_entry.get("steps", {})
            # A file is fully completed if all steps are done or skipped
            title_complete = steps.get("title") in ["done", "skipped"]
            copy_complete = steps.get("copy_edit") in ["done", "skipped"]
            summary_complete = steps.get("summary") in ["done", "skipped"]
            tags_complete = steps.get("tags") in ["done", "skipped"]
            
            if title_complete and copy_complete and summary_complete and tags_complete:
                fully_completed_count += 1
            else:
                # Check if any step failed
                if any(steps.get(step) == "failed" for step in ["title", "copy_edit", "summary", "tags"]):
                    failed_count += 1
        
        total_files = len(files)
        
        if fully_completed_count == total_files:
            return "success"
        elif fully_completed_count > 0:
            return "partial_success"
        else:
            return "failed"
    
    def get_batch_status(self, batch_id: str) -> Optional[Dict[str, Any]]:
        """Get status of a specific batch."""
        if self.current_batch and self.current_batch.get("batch_id") == batch_id:
            return self.current_batch
        return None
    
    async def start_enhance_batch(
        self,
        file_ids: List[str],
        file_service: Any
    ) -> Dict[str, Any]:
        """
        Start a new enhancement batch.
        
        Processes files sequentially through Title → Copy Edit → Summary → Tags pipeline.
        Skips already-completed steps. MLX model loads once and stays in memory.
        
        Args:
            file_ids: List of file IDs to enhance (will be sorted by creation date)
            file_service: Status tracker instance for file operations
            
        Returns:
            Batch state dictionary
        """
        if self.has_active_batch():
            raise ValueError("A batch is already running. Cancel it first.")
        
        # Sort files by audio creation date (oldest first)
        sorted_file_ids = await self._sort_files_by_creation_date(file_ids, file_service)
        
        batch_id = f"batch_enhance_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        self.current_batch = {
            "batch_id": batch_id,
            "type": BatchType.ENHANCE,
            "status": BatchStatus.RUNNING,
            "current_file_id": None,
            "files": [
                {
                    "file_id": file_id,
                    "status": FileStatus.WAITING,
                    "current_step": None,
                    "steps": {
                        "title": "waiting",
                        "copy_edit": "waiting",
                        "summary": "waiting",
                        "tags": "waiting"
                    },
                    "error": None,
                    "started_at": None,
                    "completed_at": None
                }
                for file_id in sorted_file_ids
            ],
            "consecutive_failures": 0,
            "mlx_model_loaded": False,
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat()
        }
        
        self._save_state()
        
        # Start processing in background
        self.processing_task = asyncio.create_task(
            self._process_enhance_batch(file_service)
        )
        
        logger.info(f"Started enhance batch {batch_id} with {len(sorted_file_ids)} files")
        return self.current_batch
    
    async def _process_enhance_batch(self, file_service: Any):
        """
        Process all files in the enhancement batch sequentially.
        
        For each file, runs Title → Copy Edit → Summary → Tags in order.
        Skips already-completed steps. Continues to next steps even if one fails.
        
        Note: MLX model will be loaded/used by each enhancement call. By calling
        functions sequentially without delays, any internal MLX caching stays hot.
        This exactly mirrors manual mode behavior.
        """
        try:
            # Verify MLX model is configured before starting
            from config.settings import settings
            
            mlx_cfg = settings.get('enhancement.mlx') or {}
            model_path = (mlx_cfg.get('model_path') or '').strip()
            if not model_path:
                logger.error("MLX model not selected")
                self.current_batch["status"] = BatchStatus.FAILED
                self.current_batch["error"] = "MLX model not selected. Configure in Settings > Enhancement."
                self._save_state()
                return
            from pathlib import Path as _Path
            if not _Path(model_path).exists():
                logger.error(f"Model folder not found: {model_path}")
                self.current_batch["status"] = BatchStatus.FAILED
                self.current_batch["error"] = f"Model folder not found: {_Path(model_path).name}. Check Settings > Enhancement."
                self._save_state()
                return

            logger.info(f"Starting batch enhancement with model: {model_path}")

            from utils.status_tracker import status_tracker

            # Process each file sequentially
            for file_entry in self.current_batch["files"]:
                # Check if batch was cancelled
                if self.current_batch["status"] == BatchStatus.CANCELLED:
                    logger.info("Batch was cancelled, stopping processing")
                    break
                
                # Check consecutive failure limit
                if self.current_batch["consecutive_failures"] >= int(settings.get('batch.max_consecutive_failures') or 3):
                    logger.error(f"Reached {settings.get('batch.max_consecutive_failures') or 3} consecutive failures, stopping batch")
                    self.current_batch["status"] = BatchStatus.FAILED
                    self._save_state()
                    break
                
                file_id = file_entry["file_id"]
                self.current_batch["current_file_id"] = file_id
                
                # Skip if all steps already completed
                if file_entry["status"] == FileStatus.COMPLETED:
                    continue
                
                # Mark file as processing
                file_entry["status"] = FileStatus.PROCESSING
                file_entry["started_at"] = datetime.now().isoformat()
                self.current_batch["updated_at"] = datetime.now().isoformat()
                self._save_state()
                
                logger.info(f"Processing file {file_id} in enhancement batch")

                # Mark enhance step as processing so frontend dots pulse
                status_tracker.update_file_status(file_id, "enhance", "processing")

                # Get current file state
                pf = file_service.get_file(file_id)
                if not pf:
                    logger.error(f"File {file_id} not found")
                    file_entry["status"] = FileStatus.FAILED
                    file_entry["error"] = "File not found"
                    self.current_batch["consecutive_failures"] += 1
                    self._save_state()
                    continue
                
                # Process each step (Title → Copy Edit → Summary → Tags)
                try:
                    await self._process_enhancement_steps(file_id, file_entry, pf)
                    
                    # Mark file as completed if we got here
                    file_entry["status"] = FileStatus.COMPLETED
                    file_entry["completed_at"] = datetime.now().isoformat()
                    file_entry["current_step"] = None
                    logger.info(f"File {file_id} enhancement completed")

                    # Auto-compile now that all steps are done
                    try:
                        from services.enhancement import auto_compile_if_complete
                        await auto_compile_if_complete(file_id)
                        logger.info(f"Auto-compiled {file_id} after batch enhancement")
                    except Exception as compile_err:
                        logger.warning(f"Auto-compile failed for {file_id}: {compile_err}")
                
                except Exception as e:
                    logger.error(f"Failed to enhance {file_id}: {e}")
                    file_entry["status"] = FileStatus.FAILED
                    if not file_entry.get("error"):
                        file_entry["error"] = str(e)
                    file_entry["completed_at"] = datetime.now().isoformat()
                    self.current_batch["consecutive_failures"] += 1
                    # Reset enhance step so dot stops pulsing on failure
                    status_tracker.update_file_status(file_id, "enhance", "pending")
                
                self.current_batch["updated_at"] = datetime.now().isoformat()
                self._save_state()
            
            # Mark batch as completed if not cancelled/failed
            if self.current_batch["status"] == BatchStatus.RUNNING:
                self.current_batch["status"] = BatchStatus.COMPLETED
                self.current_batch["current_file_id"] = None
                self.current_batch["result"] = self._compute_batch_result()
                self.current_batch["updated_at"] = datetime.now().isoformat()
                self._save_state()
                logger.info(f"Batch {self.current_batch['batch_id']} completed with result: {self.current_batch['result']}")
            
            # Unload MLX model from cache after batch completes
            try:
                from services.mlx_cache import get_model_cache
                cache = get_model_cache()
                cache.clear_cache(reason="batch completed")
                logger.info("✅ MLX model unloaded from cache after batch completion")
            except Exception as e:
                logger.warning(f"Failed to clear MLX cache after batch: {e}")
        
        except Exception as e:
            logger.error(f"Batch enhancement processing failed: {e}")
            import traceback
            traceback.print_exc()
            self.current_batch["status"] = BatchStatus.FAILED
            self.current_batch["error"] = str(e)
            self.current_batch["updated_at"] = datetime.now().isoformat()
            self._save_state()
        
        finally:
            # Always unload MLX model after batch ends (success, failure, or cancellation)
            try:
                from services.mlx_cache import get_model_cache
                cache = get_model_cache()
                cache.clear_cache(reason="batch ended")
                logger.info("✅ MLX model unloaded from cache (batch ended)")
            except Exception as e:
                logger.warning(f"Failed to clear MLX cache after batch: {e}")
    
    async def _process_enhancement_steps(
        self,
        file_id: str,
        file_entry: Dict[str, Any],
        pf: Any
    ):
        """
        Process enhancement steps for a single file.
        
        Calls the exact same endpoints as manual mode:
        - Title: streams via /api/process/enhance/stream with title prompt
        - Copy Edit: streams via /api/process/enhance/stream with copy_edit prompt
        - Summary: streams via /api/process/enhance/stream with summary prompt
        - Tags: calls /api/process/enhance/tags/generate
        
        Each step persists results to status.json exactly as manual mode does.
        """
        from services.enhancement import generate_enhancement_stream
        from config.settings import settings
        from utils.status_tracker import status_tracker
        import json as _json
        
        logger.debug(f"Status tracker initialized for file {file_id}")
        
        # Get sanitised text (required for all enhancement steps)
        input_text = pf.sanitised or ''
        if not input_text:
            raise ValueError("No sanitised text available for enhancement")
        
        # Get prompts from settings
        enh_cfg = settings.get('enhancement') or {}
        prompts = (enh_cfg.get('prompts') or {})
        title_prompt = prompts.get('title') or "Analyze the following transcript. If the speaker explicitly mentions a title or name for this content, extract and return that exact title. If no title is mentioned, generate an appropriate, descriptive title (10-30 words) that captures the main topic. Return ONLY the title itself, nothing else."
        copy_prompt = prompts.get('copy_edit') or "You are an assistant that enhances transcripts."
        summary_prompt = prompts.get('summary') or "Return exactly one sentence (20-30 words) summarizing the text. Output one sentence only."
        
        # Step 0: Title (streaming)
        if not (pf.enhanced_title or ''):
            file_entry["current_step"] = "title"
            file_entry["steps"]["title"] = "processing"
            self.current_batch["updated_at"] = datetime.now().isoformat()
            self._save_state()
            
            # Broadcast step start
            await self.broadcast("start", {"file_id": file_id, "step": "title"})
            logger.info(f"📡 Broadcasted 'start' event for Title. Active SSE clients: {len(self._stream_clients)}")
            
            try:
                logger.info(f"Running Title Generation for {file_id}")
                result_text = await self._run_enhancement_stream(
                    file_id, input_text, title_prompt, "title"
                )
                
                # Persist result using status tracker
                status_tracker.set_enhancement_title(file_id, result_text.strip())
                
                file_entry["steps"]["title"] = "done"
                self.current_batch["consecutive_failures"] = 0
                logger.info(f"Title Generation completed for {file_id}")
                
                # Broadcast step done
                await self.broadcast("done", {"file_id": file_id, "step": "title"})
                
                # Refresh pf from tracker so subsequent checks see updated state
                pf = status_tracker.get_file(file_id)
            
            except Exception as e:
                logger.error(f"Title Generation failed for {file_id}: {e}")
                file_entry["steps"]["title"] = "failed"
                file_entry["error"] = f"Title Generation failed: {e}"
                self.current_batch["consecutive_failures"] += 1
                
                # Broadcast error
                await self.broadcast("error", {"file_id": file_id, "step": "title", "error": str(e)})
            
            self._save_state()
        else:
            file_entry["steps"]["title"] = "done"
        
        # Step 1: Copy Edit (streaming)
        # Refresh pf to ensure we check the latest state
        pf = status_tracker.get_file(file_id)
        if not (pf.enhanced_copyedit or ''):
            file_entry["current_step"] = "copy_edit"
            file_entry["steps"]["copy_edit"] = "processing"
            self.current_batch["updated_at"] = datetime.now().isoformat()
            self._save_state()
            
            # Broadcast step start — include has_images so frontend knows the
            # marker-aware copy-edit (photo markers) runs for this file
            from services.enhancement import _get_image_manifest
            _has_imgs = _get_image_manifest(file_id) is not None
            await self.broadcast("start", {"file_id": file_id, "step": "copy_edit", "has_images": _has_imgs})
            logger.info(f"📡 Broadcasted 'start' event for Copy Edit (has_images={_has_imgs}). Active SSE clients: {len(self._stream_clients)}")
            
            try:
                logger.info(f"Running Copy Edit for {file_id}")
                result_text = await self._run_enhancement_stream(
                    file_id, input_text, copy_prompt, "copy_edit"
                )
                
                # Persist result using status tracker
                status_tracker.set_enhancement_fields(file_id, copyedit=result_text)
                
                file_entry["steps"]["copy_edit"] = "done"
                self.current_batch["consecutive_failures"] = 0
                logger.info(f"Copy Edit completed for {file_id}")
                
                # Broadcast step done
                await self.broadcast("done", {"file_id": file_id, "step": "copy_edit"})
                
                # Refresh pf from tracker so subsequent checks see updated state
                pf = status_tracker.get_file(file_id)
            
            except Exception as e:
                logger.error(f"Copy Edit failed for {file_id}: {e}")
                file_entry["steps"]["copy_edit"] = "failed"
                file_entry["error"] = f"Copy Edit failed: {e}"
                self.current_batch["consecutive_failures"] += 1
                
                # Broadcast error
                await self.broadcast("error", {"file_id": file_id, "step": "copy_edit", "error": str(e)})
            
            self._save_state()
        else:
            file_entry["steps"]["copy_edit"] = "done"
        
        # Step 2: Summary (streaming)
        # Refresh pf to ensure we check the latest state
        pf = status_tracker.get_file(file_id)
        if not (pf.enhanced_summary or ''):
            file_entry["current_step"] = "summary"
            file_entry["steps"]["summary"] = "processing"
            self.current_batch["updated_at"] = datetime.now().isoformat()
            self._save_state()
            
            # Broadcast step start
            await self.broadcast("start", {"file_id": file_id, "step": "summary"})
            logger.info(f"📡 Broadcasted 'start' event for Summary. Active SSE clients: {len(self._stream_clients)}")
            
            try:
                logger.info(f"Running Summary for {file_id}")
                result_text = await self._run_enhancement_stream(
                    file_id, input_text, summary_prompt, "summary"
                )
                
                # Persist result using status tracker
                status_tracker.set_enhancement_fields(file_id, summary=result_text.strip())
                
                file_entry["steps"]["summary"] = "done"
                self.current_batch["consecutive_failures"] = 0
                logger.info(f"Summary completed for {file_id}")
                
                # Broadcast step done
                await self.broadcast("done", {"file_id": file_id, "step": "summary"})
                
                # Refresh pf from tracker so subsequent checks see updated state
                pf = status_tracker.get_file(file_id)
            
            except Exception as e:
                logger.error(f"Summary failed for {file_id}: {e}")
                file_entry["steps"]["summary"] = "failed"
                if not file_entry.get("error"):
                    file_entry["error"] = f"Summary failed: {e}"
                self.current_batch["consecutive_failures"] += 1
                
                # Broadcast error
                await self.broadcast("error", {"file_id": file_id, "step": "summary", "error": str(e)})
            
            self._save_state()
        else:
            file_entry["steps"]["summary"] = "done"
        
        # Score importance (runs while batch continues to tags)
        try:
            from services.enhancement import score_importance_for_file
            await score_importance_for_file(file_id)
        except Exception as e:
            logger.warning(f"Importance scoring failed for {file_id}: {e}")

        # Step 3: Tags (non-streaming, direct call)
        # Refresh pf to ensure we check the latest state
        pf = status_tracker.get_file(file_id)
        
        # Skip if enhanced_tags already exists (user has manually approved) OR if tag_suggestions already exist (awaiting user approval)
        has_approved_tags = bool(pf.enhanced_tags and len(pf.enhanced_tags) > 0)
        tag_suggestions = pf.tag_suggestions or {}
        has_suggestions = bool(tag_suggestions and (tag_suggestions.get('old') or tag_suggestions.get('new')))
        
        if has_approved_tags:
            # User has already approved tags - mark as done and skip
            file_entry["steps"]["tags"] = "done"
            logger.info(f"Tags step skipped for {file_id}: enhanced_tags already approved by user")
        elif has_suggestions:
            # Tag suggestions already generated - mark as skipped (awaiting user approval)
            file_entry["steps"]["tags"] = "skipped"
            logger.info(f"Tags step skipped for {file_id}: tag_suggestions already exist (awaiting approval)")
        elif not has_approved_tags and not has_suggestions:
            file_entry["current_step"] = "tags"
            file_entry["steps"]["tags"] = "processing"
            self.current_batch["updated_at"] = datetime.now().isoformat()
            self._save_state()
            
            # Give UI time to poll and display Tags as "processing" before it completes
            await asyncio.sleep(0.6)
            
            # Broadcast step start
            await self.broadcast("start", {"file_id": file_id, "step": "tags"})
            
            try:
                logger.info(f"Running Tags for {file_id}")
                
                # Call the exact same endpoint as manual mode
                from services.enhancement import generate_tags_service
                result = await generate_tags_service(file_id)
                
                if result.get('success'):
                    file_entry["steps"]["tags"] = "done"
                    self.current_batch["consecutive_failures"] = 0
                    
                    # Broadcast tags result as tokens for live display
                    tags_text = "Old tags: " + ", ".join(result.get('old', [])) + "\n" + "New tags: " + ", ".join(result.get('new', []))
                    await self.broadcast("token", tags_text)
                    await self.broadcast("done", {"file_id": file_id, "step": "tags"})
                    
                    logger.info(f"Tags completed for {file_id}: {len(result.get('old', []))} old, {len(result.get('new', []))} new")
                else:
                    raise ValueError("Tag generation returned success=False")
            
            except Exception as e:
                logger.error(f"Tags failed for {file_id}: {e}")
                file_entry["steps"]["tags"] = "failed"
                if not file_entry.get("error"):
                    file_entry["error"] = f"Tags failed: {e}"
                self.current_batch["consecutive_failures"] += 1
                
                # Broadcast error
                await self.broadcast("error", {"file_id": file_id, "step": "tags", "error": str(e)})
            
            self._save_state()
        
        file_entry["current_step"] = None
    
    async def _run_enhancement_stream(self, file_id: str, input_text: str, prompt: str, step_name: str) -> str:
        """
        Run enhancement streaming (mimics manual mode EventSource consumption).
        
        Consumes SSE events from generate_enhancement_stream and returns final text.
        Also broadcasts tokens to batch SSE clients for live display.
        """
        from services.enhancement import generate_enhancement_stream, ACTIVE_ENHANCE_STREAMS
        
        logger.info(f"🎬 Starting enhancement stream for {file_id} ({step_name}). Active SSE clients: {len(self._stream_clients)}")
        accumulated_text = []
        generator = None
        token_count = 0
        
        try:
            # Create the streaming generator — pass step_name so the marker-aware
            # copy-edit activates for copy_edit on files with timestamped images
            generator = generate_enhancement_stream(file_id, input_text, prompt, step=step_name)

            # Consume the streaming generator
            async for sse_event in generator:
                # Parse SSE format: "event: <type>\ndata: <data>\n\n"
                lines = sse_event.strip().split('\n')
                event_type = None
                event_data = []

                for line in lines:
                    if line.startswith('event: '):
                        event_type = line[7:].strip()
                    elif line.startswith('data: '):
                        event_data.append(line[6:])

                data_text = '\n'.join(event_data)

                if event_type == 'token':
                    accumulated_text.append(data_text)
                    token_count += 1
                    # Broadcast token to batch SSE clients
                    await self.broadcast("token", data_text)
                    if token_count % 10 == 0:  # Log every 10th token to avoid spam
                        logger.debug(f"📡 Broadcasted token #{token_count} for {file_id} ({step_name})")
                elif event_type == 'stats':
                    # Forward token budget stats to batch clients
                    import json as _stats_json
                    try:
                        stats = _stats_json.loads(data_text)
                        stats["file_id"] = file_id
                        stats["step"] = step_name
                        await self.broadcast("stats", stats)
                    except Exception:
                        pass
                elif event_type == 'done':
                    # Final text is in the done event
                    if data_text:
                        return data_text
                    # Fallback to accumulated
                    return ''.join(accumulated_text)
                elif event_type == 'error':
                    raise RuntimeError(f"{step_name} stream error: {data_text}")
            
            # If we exit loop without done event, use accumulated
            final_text = ''.join(accumulated_text)
            logger.info(f"✅ Finished streaming {file_id} ({step_name}): {token_count} tokens, {len(final_text)} chars")
            return final_text
        
        except Exception as e:
            logger.error(f"Enhancement streaming failed for {file_id} ({step_name}): {e}")
            raise
        
        finally:
            # Explicitly close generator and ensure cleanup
            if generator is not None:
                try:
                    await generator.aclose()
                except Exception:
                    pass
            
            # Double-check cleanup happened
            if file_id in ACTIVE_ENHANCE_STREAMS:
                logger.warning(f"Cleaning up stale stream lock for {file_id} after {step_name}")
                ACTIVE_ENHANCE_STREAMS.discard(file_id)
            
            # Small delay to ensure cleanup completes
            await asyncio.sleep(0.1)
