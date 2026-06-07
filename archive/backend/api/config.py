"""
Configuration management API endpoints
Handles settings and preferences management
"""

from fastapi import APIRouter, HTTPException
from models import ConfigUpdate, ConfigResponse
from config.settings import settings, get_names_path
from pathlib import Path
import json
import os

router = APIRouter()

@router.get("/")
async def get_all_config():
    """
    Get all configuration settings
    Returns complete configuration object
    """
    try:
        config = settings.get_all()
        return ConfigResponse(
            success=True,
            message="Configuration retrieved successfully",
            config=config
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get configuration: {str(e)}")


@router.post("/update")
async def update_config(config_update: ConfigUpdate):
    """
    Update a configuration value using dot notation
    Body: {"key": "transcription.solo_model", "value": "base.en"}
    """
    try:
        # Validate key exists in current config (optional - you might want to allow new keys)
        current_value = settings.get(config_update.key)
        
        # Update the value
        settings.set(config_update.key, config_update.value)

        # When model changes, clear stale caches
        if config_update.key == 'enhancement.mlx.model_path':
            # Clear chat template overrides keyed by old model path
            settings.set('enhancement.mlx.chat_template_overrides', {})
            # Clear cached model so next enhancement loads the new one
            try:
                from services.mlx_cache import MLXModelCache
                MLXModelCache.get_instance().clear_cache()
            except Exception:
                pass  # Cache may not be initialized yet

        return ConfigResponse(
            success=True,
            message=f"Successfully updated {config_update.key}",
            config={config_update.key: config_update.value}
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update configuration: {str(e)}")

@router.get("/defaults")
async def get_default_config():
    """
    Get the hardcoded default settings (from settings.py DEFAULT_SETTINGS).
    Used by the frontend to power "Reset to default" buttons.
    """
    from config.settings import DEFAULT_SETTINGS
    return ConfigResponse(
        success=True,
        message="Default configuration retrieved",
        config=DEFAULT_SETTINGS
    )

# ── Dependency folder detection & validation ─────────────────

def _validate_deps_folder(folder: Path) -> dict:
    """Check what's inside a dependencies folder.
    The venv (mlx-env/) is created automatically by start_backend.sh —
    it's not expected to be in the zip/distribution."""
    has_venv = (folder / "mlx-env" / "bin" / "python3").exists()
    mlx_dir = folder / "models" / "mlx"
    mlx_model_names = []
    if mlx_dir.exists():
        mlx_model_names = [
            d.name for d in sorted(mlx_dir.iterdir())
            if d.is_dir() and (d / "config.json").exists()
        ]
    parakeet_dir = folder / "models" / "parakeet"
    has_parakeet = False
    if parakeet_dir.exists():
        # Check for HF cache structure or direct model files
        for f in parakeet_dir.rglob("model.safetensors"):
            has_parakeet = True
            break
    issues = []
    if not mlx_model_names:
        issues.append("No MLX models found in models/mlx/")
    if not has_parakeet:
        issues.append("Parakeet model not found in models/parakeet/")
    # Models are the hard requirement; venv is created automatically
    valid = len(mlx_model_names) > 0 and has_parakeet
    return {
        "valid": valid,
        "has_venv": has_venv,
        "has_mlx_models": len(mlx_model_names) > 0,
        "mlx_model_names": mlx_model_names,
        "has_parakeet": has_parakeet,
        "issues": issues,
    }


def _find_zip_files() -> list[dict]:
    """Scan common download locations for Skrift dependency zips."""
    home = Path.home()
    search_dirs = [home / "Downloads", home / "Desktop"]
    zips = []
    for d in search_dirs:
        if not d.exists():
            continue
        for f in d.iterdir():
            if f.suffix == '.zip' and 'skrift' in f.name.lower():
                zips.append({"path": str(f), "name": f.name, "size_mb": round(f.stat().st_size / 1e6, 1)})
    return sorted(zips, key=lambda z: z["name"])


@router.get("/deps/detect")
async def detect_deps_folder():
    """Scan common locations for a valid dependencies folder or zip."""
    home = Path.home()
    candidates = [
        home / "Skrift_dependencies",
        home / "Desktop" / "Skrift-Distribution" / "Skrift_dependencies",
        home / "Desktop" / "Skrift_dependencies",
        home / "Downloads" / "Skrift_dependencies",
        home / "Downloads" / "Skrift-Distribution" / "Skrift_dependencies",
    ]
    # Check for existing extracted folder first
    for candidate in candidates:
        if candidate.exists() and candidate.is_dir():
            result = _validate_deps_folder(candidate)
            if result["valid"]:
                return {"found": True, "path": str(candidate), "components": result, "zips": []}
    # Check incomplete folders
    for candidate in candidates:
        if candidate.exists() and candidate.is_dir():
            result = _validate_deps_folder(candidate)
            return {"found": True, "path": str(candidate), "components": result, "zips": _find_zip_files()}
    # No folder found — check for zip files
    zips = _find_zip_files()
    return {"found": False, "path": None, "components": None, "zips": zips}


@router.post("/deps/extract")
async def extract_deps_zip(body: dict):
    """Extract a dependencies zip to ~/Skrift_dependencies and validate."""
    import zipfile, shutil
    zip_path = Path(body.get("zip_path", ""))
    if not zip_path.exists() or zip_path.suffix != '.zip':
        raise HTTPException(status_code=400, detail="Invalid zip file")

    dest = Path.home() / "Skrift_dependencies"
    dest.mkdir(parents=True, exist_ok=True)

    try:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            # Check if zip has a top-level folder (e.g. Skrift_dependencies/)
            top_dirs = {n.split('/')[0] for n in zf.namelist() if '/' in n}
            has_wrapper = len(top_dirs) == 1

            if has_wrapper:
                # Extract to temp, then move contents up
                import tempfile
                with tempfile.TemporaryDirectory() as tmp:
                    zf.extractall(tmp)
                    wrapper = Path(tmp) / top_dirs.pop()
                    if wrapper.is_dir():
                        for item in wrapper.iterdir():
                            target = dest / item.name
                            if target.exists():
                                if target.is_dir():
                                    shutil.rmtree(target)
                                else:
                                    target.unlink()
                            shutil.move(str(item), str(target))
            else:
                zf.extractall(dest)
    except zipfile.BadZipFile:
        raise HTTPException(status_code=400, detail="Corrupt or invalid zip file")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Extraction failed: {e}")

    result = _validate_deps_folder(dest)
    return {"success": True, "path": str(dest), "components": result}


@router.get("/deps/validate")
async def validate_deps_folder(path: str):
    """Validate a specific folder as a dependencies folder."""
    folder = Path(path)
    if not folder.exists() or not folder.is_dir():
        return {"valid": False, "issues": ["Folder does not exist"], "has_venv": False,
                "has_mlx_models": False, "mlx_model_names": [], "has_parakeet": False}
    return _validate_deps_folder(folder)


@router.post("/deps/apply")
async def apply_deps_folder(body: dict):
    """Save a dependencies folder path and auto-select the MLX model."""
    folder = Path(body.get("path", ""))
    if not folder.exists() or not folder.is_dir():
        raise HTTPException(status_code=400, detail="Folder does not exist")
    result = _validate_deps_folder(folder)
    # Save the path
    settings.set("dependencies_folder", str(folder))
    # Auto-select first MLX model if none is set
    current_model = (settings.get("enhancement.mlx.model_path") or "").strip()
    if (not current_model or not Path(current_model).exists()) and result["mlx_model_names"]:
        model_path = str(folder / "models" / "mlx" / result["mlx_model_names"][0])
        settings.set("enhancement.mlx.model_path", model_path)
        result["auto_selected_model"] = result["mlx_model_names"][0]
    return {"success": True, "path": str(folder), "components": result}


@router.post("/reset")
async def reset_config():
    """
    Reset configuration to default values
    This will overwrite all user settings
    """
    try:
        # Clear the settings file to force reload of defaults
        if settings.settings_file.exists():
            settings.settings_file.unlink()
        
        # Reload settings (will use defaults)
        settings.load_settings()
        
        return ConfigResponse(
            success=True,
            message="Configuration reset to defaults",
            config=settings.get_all()
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to reset configuration: {str(e)}")

@router.get("/folders/input")
async def get_input_folder():
    """
    Get current input folder path
    """
    try:
        from config.settings import get_input_folder
        folder = get_input_folder()
        
        return {
            "path": str(folder),
            "exists": folder.exists(),
            "writable": folder.exists() and os.access(folder, os.W_OK)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get input folder: {str(e)}")

@router.get("/folders/output")
async def get_output_folder():
    """
    Get current output folder path
    """
    try:
        from config.settings import get_output_folder
        folder = get_output_folder()
        
        return {
            "path": str(folder),
            "exists": folder.exists(),
            "writable": folder.exists() and os.access(folder, os.W_OK)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get output folder: {str(e)}")

@router.post("/folders/input")
async def set_input_folder(folder_path: dict):
    """
    Set input folder path
    Body: {"path": "/path/to/input/folder"}
    """
    try:
        import os
        from pathlib import Path
        
        new_path = folder_path.get("path")
        if not new_path:
            raise HTTPException(status_code=400, detail="Path is required")
        
        # Validate path
        path_obj = Path(new_path)
        if not path_obj.exists():
            # Try to create the folder
            try:
                path_obj.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                raise HTTPException(status_code=400, detail=f"Cannot create folder: {str(e)}")
        
        # Update settings
        settings.set("input_folder", str(path_obj))
        
        return ConfigResponse(
            success=True,
            message=f"Input folder updated to {new_path}",
            config={"input_folder": str(path_obj)}
        )
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to set input folder: {str(e)}")

@router.post("/folders/output")
async def set_output_folder(folder_path: dict):
    """
    Set output folder path
    Body: {"path": "/path/to/output/folder"}
    """
    try:
        import os
        from pathlib import Path
        
        new_path = folder_path.get("path")
        if not new_path:
            raise HTTPException(status_code=400, detail="Path is required")
        
        # Validate path
        path_obj = Path(new_path)
        if not path_obj.exists():
            # Try to create the folder
            try:
                path_obj.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                raise HTTPException(status_code=400, detail=f"Cannot create folder: {str(e)}")
        
        # Update settings
        settings.set("output_folder", str(path_obj))
        
        return ConfigResponse(
            success=True,
            message=f"Output folder updated to {new_path}",
            config={"output_folder": str(path_obj)}
        )
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to set output folder: {str(e)}")

@router.get("/sanitisation")
async def get_sanitisation_settings():
    try:
        return settings.get("sanitisation")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get sanitisation settings: {str(e)}")

@router.post("/sanitisation")
async def update_sanitisation_settings(payload: dict):
    try:
        # Merge shallowly into existing structure
        current = settings.get("sanitisation") or {}
        def merge(a, b):
            for k, v in b.items():
                if isinstance(v, dict) and isinstance(a.get(k), dict):
                    merge(a[k], v)
                else:
                    a[k] = v
            return a
        updated = merge(current, payload)
        settings.set("sanitisation", updated)
        return { "success": True, "message": "Sanitisation settings updated", "sanitisation": updated }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update sanitisation settings: {str(e)}")

@router.get("/names")
async def get_names_mapping():
    """
    Get the names mapping used by sanitise.
    Simplified schema:
    { "people": [ { "canonical": "[[Name]]", "aliases": [..] } ] }
    """
    try:
        from utils import names_store
        data = names_store.read_names()
        # Hide tombstones from the desktop UI.
        live = [p for p in data.get('people', []) if not p.get('deleted')]
        return { 'people': live }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to load names mapping: {str(e)}")

@router.post("/names")
async def update_names_mapping(payload: dict):
    """
    Update the names mapping. Expects simplified schema { "people": [ { "canonical", "aliases" } ] }.
    The server sorts people alphabetically by canonical (ignoring brackets) and ensures canonical is [[Name]].
    """
    try:
        people = payload.get('people', []) or []
        from utils import names_store
        # Smart bump: only entries that actually changed get a new lastModifiedAt;
        # entries removed from `people` are turned into tombstones automatically.
        result = names_store.write_with_smart_bumps(people)
        # Strip tombstones from the response so the desktop UI doesn't render them.
        live = [p for p in result.get('people', []) if not p.get('deleted')]
        return { 'success': True, 'message': 'Names mapping saved', 'data': { 'people': live } }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save names mapping: {str(e)}")

@router.get("/transcription/modules")
async def get_transcription_modules():
    """Get information about the transcription engine (Parakeet-MLX)."""
    try:
        import importlib
        parakeet_available = importlib.util.find_spec("parakeet_mlx") is not None
        return {
            "modules": {
                "parakeet": {
                    "available": parakeet_available,
                    "engine": "parakeet-mlx",
                }
            },
            "settings": {
                "parakeet_model": settings.get("transcription.parakeet_model"),
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get transcription modules: {str(e)}")

@router.get("/{key}")
async def get_config_value(key: str):
    """
    Get a specific configuration value using dot notation
    Example: GET /api/config/transcription.solo_model
    """
    try:
        value = settings.get(key)
        if value is None:
            raise HTTPException(status_code=404, detail=f"Configuration key '{key}' not found")
        
        return {
            "key": key,
            "value": value
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get configuration value: {str(e)}")
