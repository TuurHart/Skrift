"""
MLX Model Cache Manager

Singleton cache for MLX models to avoid repeated loads during batch processing.
Keeps model and tokenizer in memory between calls, dramatically speeding up
sequential enhancement operations.

Usage:
    cache = MLXModelCache.get_instance()
    model, tokenizer = cache.get_model(model_path)
    cache.clear_cache()  # Optional: free memory when done
"""

import time
import logging
from pathlib import Path
from typing import Optional, Tuple, Any
from threading import Lock

logger = logging.getLogger(__name__)


class MLXModelCache:
    """
    Thread-safe singleton cache for MLX models.
    
    Caches the model and tokenizer to avoid repeated loads during batch
    processing. Automatically invalidates cache when model path changes.
    """
    
    _instance: Optional['MLXModelCache'] = None
    _lock = Lock()
    
    def __init__(self):
        """Private constructor - use get_instance() instead."""
        self._model: Optional[Any] = None
        self._tokenizer: Optional[Any] = None
        self._current_path: Optional[str] = None
        self._last_used: Optional[float] = None
        self._load_lock = Lock()  # Prevent concurrent loads
        logger.info("MLXModelCache initialized")
    
    @classmethod
    def get_instance(cls) -> 'MLXModelCache':
        """Get or create the singleton cache instance."""
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = cls()
        return cls._instance
    
    def get_model(self, model_path: str) -> Tuple[Any, Any]:
        """
        Get cached model or load if not cached.

        Args:
            model_path: Path to the MLX model directory

        Returns:
            Tuple of (model, tokenizer_or_processor)
        """
        model_path = str(Path(model_path).resolve())  # Normalize path

        with self._load_lock:
            # Check if cache is valid
            if self._is_cache_valid(model_path):
                logger.debug(f"Using cached model: {model_path}")
                self._last_used = time.time()
                return self._model, self._tokenizer

            # Cache miss or invalid - load model
            logger.info(f"Loading MLX model: {model_path}")
            self._load_model(model_path)
            return self._model, self._tokenizer

    def _is_cache_valid(self, model_path: str) -> bool:
        """Check if cached model is valid for the requested path."""
        return (
            self._model is not None and
            self._tokenizer is not None and
            self._current_path == model_path
        )
    
    def _load_model(self, model_path: str):
        """
        Load model and tokenizer from disk.

        Args:
            model_path: Path to the MLX model directory

        Raises:
            RuntimeError: If MLX is not available or loading fails
        """
        start_time = time.time()

        try:
            # Import MLX (lazy import to avoid startup overhead)
            try:
                import mlx
                from mlx_lm import load
            except ImportError as e:
                raise RuntimeError(f"MLX not available: {e}")

            # Validate path
            p = Path(model_path)
            if not p.exists():
                raise RuntimeError(f"Model path does not exist: {model_path}")

            # Clear old model if present (helps with memory)
            if self._model is not None:
                logger.info(f"Unloading previous model: {self._current_path}")
                self._clear_cache_internal()

            logger.info(f"Loading model from {model_path}...")
            self._model, self._tokenizer = load(str(p))
            self._current_path = model_path
            self._last_used = time.time()

            elapsed = time.time() - start_time
            logger.info(f"✅ Model loaded successfully in {elapsed:.2f}s: {model_path}")
        
        except Exception as e:
            logger.error(f"❌ Failed to load model from {model_path}: {e}")
            self._clear_cache_internal()
            raise RuntimeError(f"Failed to load MLX model: {e}")
    
    def _clear_cache_internal(self):
        """Internal cache clear without logging (used during reload)."""
        self._model = None
        self._tokenizer = None
        self._current_path = None
        self._last_used = None

        # Force garbage collection to free memory, then release Metal buffers.
        # Without mx.metal.clear_cache(), the Metal allocator holds onto GPU
        # memory even after Python objects are freed, causing psutil to report
        # artificially low available RAM.
        try:
            import gc
            gc.collect()
        except Exception:
            pass
        try:
            import mlx.core as mx
            if hasattr(mx, 'clear_cache'):
                mx.clear_cache()
            elif hasattr(mx, 'metal') and hasattr(mx.metal, 'clear_cache'):
                mx.metal.clear_cache()
        except Exception:
            pass
    
    def clear_cache(self, reason: str = "manual"):
        """
        Explicitly clear the model cache and free memory.
        
        Args:
            reason: Reason for clearing (for logging)
        """
        with self._load_lock:
            if self._model is None:
                logger.debug("Cache already empty, nothing to clear")
                return
            
            logger.info(f"Clearing MLX model cache (reason: {reason})")
            self._clear_cache_internal()
            logger.info("✅ Model cache cleared")
    
    def should_clear_idle_cache(self, idle_timeout_seconds: int = 10) -> bool:
        """
        Check if cache should be cleared due to inactivity.
        
        Args:
            idle_timeout_seconds: Timeout in seconds (default: 10 seconds)
            
        Returns:
            True if cache is idle and should be cleared
        """
        if self._model is None or self._last_used is None:
            return False
        
        idle_time = time.time() - self._last_used
        return idle_time > idle_timeout_seconds


# Convenience function for easy access
def get_model_cache() -> MLXModelCache:
    """Get the singleton MLX model cache instance."""
    return MLXModelCache.get_instance()
