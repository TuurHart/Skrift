"""
Configuration settings for Audio Transcription Pipeline
Manages paths, processing options, and system settings
"""

import os
from pathlib import Path
from typing import Dict, Any

# Base paths
HOME_DIR = Path.home()
BACKEND_DIR = Path(__file__).parent.parent

# Default folder paths (configurable via frontend settings)
DEFAULT_SETTINGS = {
    "input_folder": str(HOME_DIR / "Documents" / "Voice Transcription Pipeline Audio Input"),
    "output_folder": str(HOME_DIR / "Documents" / "Voice Transcription Pipeline Audio Output"),
    
    # Processing settings
    "transcription": {
        "parakeet_model": "mlx-community/parakeet-tdt-0.6b-v3",
        # Audio preprocessing (applied before transcription)
        "noise_reduction": -20,  # afftdn noise floor in dB (-10 = aggressive, -30 = gentle, 0 = off)
        "highpass_freq": 80,     # High-pass filter cutoff in Hz (removes rumble; 0 = off)
    },

    # Audio processing
    "audio": {
        "supported_input_formats": [".m4a", ".wav", ".mp3", ".mp4", ".mov", ".opus", ".md"],
        "sample_rate": 16000,
    },
    
    # Text processing - Sanitisation settings (Name linking only)
    "sanitisation": {
        # Alias matching behavior
        "whole_word": True,

        # Name linking
        "linking": {
            "mode": "first",  # "first" | "all"
            "avoid_inside_links": True,
            "preserve_possessive": True,
            "format": {
                "style": "wiki",        # "wiki" | "wiki_with_path"
                "base_path": "People"   # used when style == wiki_with_path
            },
            "alias_priority": "longest"  # "longest" | "shortest"
        }
    },
    
    # AI Enhancement (MLX local)
    "enhancement": {
        "enabled": True,
        "mlx": {
            "models_dir": str(BACKEND_DIR / "resources" / "models" / "mlx"),
            "model_path": None,  # e.g., /path/to/model.mlx or safetensors supported by mlx-lm
            "max_tokens": 512,
            "temperature": 0.7,
            "top_p": 0.95,
            "top_k": 50,
            "repetition_penalty": 1.0,
            "timeout_seconds": 45,
            # Advanced controls
            "use_chat_template": True,
            "dynamic_tokens": True,
            "dynamic_ratio": 1.2,
            "min_tokens": 256
        },
        # Persisted text prompts for enhancement actions
        "prompts": {
            "copy_edit": "Clean up this transcript. The author may switch between English and Dutch mid-sentence — this is intentional, keep it exactly as-is.\n\nDo:\n- Remove filler words (um, uh, like, you know, so basically, I mean, yeah so).\n- Fix spelling and grammar.\n- Add punctuation and paragraph breaks at natural pauses.\n- When the speaker immediately rephrases the same thought (e.g. saying a sentence then saying it again slightly differently), collapse into the final version.\n- Remove false starts and repeated words from thinking out loud.\n\nDo not:\n- Rephrase, rewrite, or restructure sentences.\n- Translate anything between languages.\n- Add formality — it should still sound like the person speaking.\n- Add any preamble, heading, or explanation.\n\nOutput only the cleaned text.",
            "summary": "Summarize this in 1–3 sentences (30–60 words) as personal notes — the kind of thing you'd jot in a journal, not a report.\n\n- Use implied first person via present participles: \"reflecting on…\", \"trying to figure out…\", \"collaborating with…\". Avoid \"The speaker\", \"They\", \"He/She\".\n- Drop articles where natural (\"importance of X\" not \"the importance of X\").\n- Capture the main point and any decision or action item. If multiple topics, mention each briefly.\n- Use proper spelling and capitalization. Keep names capitalized.\n- IMPORTANT: Write the summary in the SAME language as the input text — if the text is in English, the summary MUST be in English.\n\nOutput only the summary.",
            "importance": "Rate the personal significance of this text from 0.0 to 1.0.\nHigh (0.7–1.0): life decisions, personal realizations, meaningful experiences, important plans, relationship insights.\nMedium (0.3–0.7): useful ideas, project updates, learning notes, opinions.\nLow (0.0–0.3): routine tasks, weather, small talk, logistics.\nReturn ONLY a number between 0.0 and 1.0.",
            "title": "Generate a short, descriptive title for this text (5–15 words). If the speaker explicitly names the topic, use their words. Match the primary language of the text. Return ONLY the title, nothing else."
        },
        # Read-only integration with Obsidian vault for tag whitelist
        "obsidian": {
            # User-provided path to an Obsidian vault (read-only). Leave empty to disable.
            "vault_path": "",
            # Where the backend stores the cached tag whitelist (writable location)
            "tags_whitelist_path": str(HOME_DIR / "Library" / "Application Support" / "Skrift" / "tags_whitelist.json"),
            # Max tags to select for transcripts (legacy UI cap)
            "tags_cap": 10
        },
        # Tag generation knobs (whitelist-based)
        "tags": {
            "max_old": 10,
            "max_new": 5,
            "selection_criteria": ""  # Optional free-text hint injected into the tag prompt
        },
        # Deterministic, vault-derived tag matching (no LLM).
        "tagging": {
            # Derivation (rule A): a vault tag is "matchable" if its lemma actually
            # appears in the bodies of the notes that carry it, often enough.
            "match_min_ratio": 0.3,       # min (notes-with-lemma / notes-carrying-tag)
            "match_min_carriers": 2,      # min number of notes that must carry the tag
            # Matching (rule B): a matchable tag becomes a candidate if its lemma
            # appears in the transcript at least this many times.
            "match_min_occurrences": 2,
        }
    },
    
    # Export options
    "export": {
        "default_format": "markdown",
        "supported_formats": ["markdown", "docx", "txt"],
        "include_metadata": True,
        "author": "",        # Written to YAML frontmatter 'author:' field
        # Obsidian integration: where compiled notes and audio are copied to inside the vault
        "note_folder": "",         # e.g. /path/to/ObsidianVault/Notes
        "audio_folder": "",        # e.g. /path/to/ObsidianVault/Audio
        "attachments_folder": "",  # e.g. /path/to/ObsidianVault/Attachments (defaults to note_folder if empty)
    },
    
    # System monitoring
    "system": {
        "monitor_resources": True,
        "log_processing_time": True,
        "max_concurrent_files": 1,  # Sequential processing only
    },

    # Server
    "server": {
        "port": 8000,
        "cors_origins": [
            "http://localhost:3000",
            "http://127.0.0.1:3000",
            "file://",
            "capacitor://localhost",
            "ionic://localhost",
        ],
    },

    # Batch processing
    "batch": {
        "max_consecutive_failures": 3,     # Abort batch after this many back-to-back failures
    },
}

class Settings:
    """Settings manager with file persistence"""
    
    def __init__(self):
        # Prefer a writable location for user settings (app bundle is read-only).
        # If the writable copy doesn't exist yet, seed from the clean template
        # (never from user_settings.json which may contain developer paths).
        import shutil
        writable_dir = Path.home() / "Library" / "Application Support" / "Skrift"
        writable_settings = writable_dir / "user_settings.json"
        template_settings = BACKEND_DIR / "config" / "user_settings.template.json"
        bundled_settings = BACKEND_DIR / "config" / "user_settings.json"

        if writable_settings.exists():
            self.settings_file = writable_settings
        elif template_settings.exists():
            # First launch (packaged app): seed from clean template
            writable_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(template_settings, writable_settings)
            self.settings_file = writable_settings
        elif bundled_settings.exists():
            # Dev mode: use existing user_settings.json directly
            self.settings_file = bundled_settings
        else:
            # No config at all: use writable location, will be created on first save
            writable_dir.mkdir(parents=True, exist_ok=True)
            self.settings_file = writable_settings

        self._settings = DEFAULT_SETTINGS.copy()
        self.load_settings()
    
    def load_settings(self):
        """Load settings from file if it exists"""
        print(f"[Settings] Reading from: {self.settings_file}")
        if self.settings_file.exists():
            import json
            try:
                with open(self.settings_file, 'r') as f:
                    user_settings = json.load(f)
                    self._update_nested_dict(self._settings, user_settings)
            except Exception as e:
                print(f"Warning: Could not load settings file: {e}")
                print("Using default settings")

        # Validate model path exists on disk
        model_path = self.get('enhancement.mlx.model_path')
        if model_path and not Path(model_path).exists():
            print(f"[Settings] WARNING: MLX model not found at: {model_path}")
            print(f"[Settings] Re-select a model in Settings → Enhancement")
    
    def save_settings(self):
        """Save current settings to file"""
        import json
        self.settings_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.settings_file, 'w') as f:
            json.dump(self._settings, f, indent=2)
    
    def get(self, key: str, default=None):
        """Get setting value using dot notation (e.g., 'transcription.solo_model')"""
        keys = key.split('.')
        value = self._settings
        for k in keys:
            if isinstance(value, dict) and k in value:
                value = value[k]
            else:
                return default
        return value
    
    def set(self, key: str, value: Any):
        """Set setting value using dot notation"""
        keys = key.split('.')
        setting = self._settings
        for k in keys[:-1]:
            if k not in setting:
                setting[k] = {}
            setting = setting[k]
        setting[keys[-1]] = value
        self.save_settings()
    
    def get_all(self) -> Dict[str, Any]:
        """Get all settings"""
        return self._settings.copy()
    
    def _update_nested_dict(self, base_dict: dict, update_dict: dict):
        """Recursively update nested dictionary"""
        for key, value in update_dict.items():
            if key in base_dict and isinstance(base_dict[key], dict) and isinstance(value, dict):
                self._update_nested_dict(base_dict[key], value)
            else:
                base_dict[key] = value

# Global settings instance
settings = Settings()


def get_names_path() -> Path:
    """Resolve names.json path: dependencies_folder/config/names.json (portable).

    Falls back to ~/Library/Application Support/Skrift/names.json.
    Seeds from bundled backend/config/names.json on first access.
    """
    import shutil
    bundled = BACKEND_DIR / "config" / "names.json"
    app_support = HOME_DIR / "Library" / "Application Support" / "Skrift" / "names.json"

    dep_folder = settings.get('dependencies_folder')
    dest = Path(dep_folder) / "config" / "names.json" if dep_folder else app_support

    if dest.exists():
        return dest
    # Migrate from old App Support location
    if app_support.exists() and dest != app_support:
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(app_support, dest)
        return dest
    # Seed from bundled copy
    if bundled.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(bundled, dest)
        return dest
    return dest  # created on first save


def get_dependency_paths() -> dict:
    """Return core dependency locations derived from dependencies_folder.

    Keys:
      - parakeet: Path to models/parakeet (HuggingFace cache for parakeet-mlx)
      - mlx_models: Path to models/mlx
      - mlx_venv: Path to mlx-env
    """
    dep_base = Path(settings.get('dependencies_folder', str(BACKEND_DIR.parent / 'Skrift_dependencies')))
    return {
        'parakeet': dep_base / 'models' / 'parakeet',
        'mlx_models': dep_base / 'models' / 'mlx',
        'mlx_venv': dep_base / 'mlx-env',
    }


def get_mlx_models_path() -> Path:
    """Preferred MLX models directory resolved from dependencies_folder."""
    paths = get_dependency_paths()
    path = paths['mlx_models']
    path.mkdir(parents=True, exist_ok=True)
    return path


def get_mlx_venv_path() -> Path:
    """Preferred MLX virtualenv path resolved from dependencies_folder."""
    paths = get_dependency_paths()
    return paths['mlx_venv']

def get_input_folder() -> Path:
    """Get configured input folder path"""
    folder = Path(settings.get("input_folder"))
    folder.mkdir(parents=True, exist_ok=True)
    return folder

def get_output_folder() -> Path:
    """Get configured output folder path"""
    folder = Path(settings.get("output_folder"))
    folder.mkdir(parents=True, exist_ok=True)
    return folder

def get_file_output_folder(filename: str, file_id: str = None) -> Path:
    """Get output folder for a specific file.

    When file_id is provided (new uploads) the folder is named
    ``<file_id>_<stem>`` so two files with the same filename never collide.
    Legacy folders created without a file_id continue to use just ``<stem>``.
    """
    base_name = Path(filename).stem
    folder_name = f"{file_id}_{base_name}" if file_id else base_name
    file_folder = get_output_folder() / folder_name
    file_folder.mkdir(parents=True, exist_ok=True)
    return file_folder

def get_parakeet_cache_path() -> Path:
    """HuggingFace cache directory for parakeet-mlx model weights."""
    paths = get_dependency_paths()
    path = paths['parakeet']
    path.mkdir(parents=True, exist_ok=True)
    return path
