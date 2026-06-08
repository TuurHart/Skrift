# Skrift Backend Map

> **PARTIALLY OUTDATED:** This document predates the migration from whisper.cpp to parakeet-mlx
> and from rnnoise to ffmpeg afftdn. References to whisper, rnnoise, solo_model, conversation_model,
> and whisper-server are stale. See CLAUDE.md for the current architecture.

> Comprehensive documentation of the entire `backend/` directory.
> Covers every file, function, class, API endpoint, import, and external dependency.

---

## Directory Structure

```
backend/
├── main.py                         FastAPI entry point, CORS, router registration
├── models.py                       Pydantic models (PipelineFile, enums, request/response)
├── requirements.txt                Python dependencies
├── test_batch_transcription.py     Integration tests
├── start_backend.sh                Shell start/stop/restart script
│
├── api/
│   ├── files.py                    File upload, list, delete, audio streaming, content retrieval
│   ├── transcribe.py               Whisper transcription trigger + debug SSE stream
│   ├── sanitise.py                 Name linking, disambiguation
│   ├── enhance.py                  MLX enhancement, tags, compile, model management
│   ├── export.py                   Compiled markdown retrieval + vault export
│   ├── batch.py                    Batch transcription and enhancement jobs
│   ├── system.py                   Resource monitoring, health check
│   ├── config.py                   Settings read/write, names mapping
│   └── processing.py               Generic processing router (currently minimal)
│
├── services/
│   ├── transcription.py            Whisper.cpp subprocess management + word timings
│   ├── sanitisation.py             Name linking and disambiguation logic
│   ├── enhancement.py              MLX streaming enhancement + bracket preservation
│   ├── export.py                   Markdown compilation and vault export
│   ├── batch_manager.py            Batch job queue, state persistence, SSE broadcast
│   ├── mlx_runner.py               MLX inference wrapper (chat templates, dynamic tokens)
│   ├── mlx_cache.py                Thread-safe singleton MLX model cache
│   └── apple_notes_importer.py     Apple Notes .md export parser
│
├── config/
│   ├── settings.py                 Settings manager with dot-notation access
│   ├── user_settings.json          User overrides (persisted)
│   ├── user_settings.json.backup   Backup of previous settings
│   └── names.json                  People/canonical name mappings
│
├── utils/
│   ├── status_tracker.py           File state manager (status.json as source of truth)
│   └── __init__.py                 Empty package marker
│
└── data/
    └── batch_state.json            Batch lifecycle state (crash-safe persistence)
```

---

## `main.py`

**Purpose:** FastAPI application entry point.

### Functions / Setup
| Name | Description |
|------|-------------|
| App init | Creates FastAPI app with title/description/version |
| CORS middleware | Allows `localhost:3000`, `127.0.0.1:3000`, `file://`, `capacitor://localhost`, `ionic://localhost` |
| Dependency logging | Prints resolved paths for whisper, mlx_models, mlx_venv at startup |
| Router registration | Mounts 9 routers (see below) |
| `GET /` | Root status endpoint |
| `GET /health` | Detailed health check: system info + endpoint list |
| Exception handler | Catches all unhandled 500s; returns full detail only when `DEBUG=1`, otherwise `"Internal server error"` |
| `main()` | Runs uvicorn on `127.0.0.1:8000`; `reload` enabled only when `DEBUG=1` |

### Router Prefixes
| Router | Prefix |
|--------|--------|
| files_router | `/api/files` |
| processing_router | `/api/process` |
| transcribe_router | `/api/process/transcribe` |
| sanitise_router | `/api/process/sanitise` |
| enhance_router | `/api/process/enhance` |
| export_router | `/api/process/export` |
| batch_router | `/api/batch` |
| system_router | `/api/system` |
| config_router | `/api/config` |

### Imports From
`api.files`, `api.transcribe`, `api.sanitise`, `api.enhance`, `api.export`, `api.batch`, `api.system`, `api.config`, `config.settings.get_dependency_paths`

### Imported By
Nothing (entry point).

---

## `models.py`

**Purpose:** All Pydantic data models used across the API.

### Enums
| Name | Values |
|------|--------|
| `ProcessingStatus` | `PENDING`, `PROCESSING`, `DONE`, `ERROR`, `SKIPPED` |

### Classes
| Class | Fields | Description |
|-------|--------|-------------|
| `ProcessingSteps` | `transcribe, sanitise, enhance, export` (all `ProcessingStatus`) | Per-step status |
| `PipelineFile` | See below | Core file model |
| `UploadResponse` | `success, files, message, errors` | Upload result |
| `ProcessingRequest` | `conversationMode, enhancementType, prompt, exportFormat` | Processing op request |
| `ProcessingResponse` | `status, message, estimatedTime, file` | Processing result |
| `SystemResources` | `cpuUsage, ramUsed, ramTotal, coreTemp, diskUsed` | Resource snapshot |
| `SystemStatus` | `processing, currentFile, currentStep, queueLength` | Processing state |
| `ConfigUpdate` | `key, value` | Config mutation |
| `ConfigResponse` | `success, message, config` | Config result |

### `PipelineFile` Fields
| Field | Type | Notes |
|-------|------|-------|
| `id` | str | UUID |
| `filename` | str | Original filename |
| `path` | str | Full path to audio file |
| `size` | int | Bytes |
| `conversationMode` | bool | Solo vs conversation mode |
| `steps` | ProcessingSteps | Per-step status |
| `uploadedAt` | datetime | Upload time |
| `lastModified` | datetime? | Last file modification |
| `lastActivityAt` | datetime? | Last processing heartbeat |
| `transcript` | str? | Raw Whisper output |
| `sanitised` | str? | After name linking |
| `enhanced` | str? | **Legacy field, deprecated** |
| `exported` | str? | Final exported text |
| `enhanced_title` | str? | AI-generated title |
| `title_approval_status` | str? | `"pending"/"accepted"/"declined"` |
| `enhanced_copyedit` | str? | Copy-edited text |
| `enhanced_summary` | str? | One-sentence summary |
| `enhanced_tags` | List[str]? | Approved tags |
| `tag_suggestions` | Dict? | `{old: [...], new: [...]}` |
| `source_type` | str? | `"audio"` or `"note"` |
| `compiled_text` | str? | Compiled markdown |
| `include_audio_in_export` | bool? | Export preference |
| `error` | str? | Error message |
| `errorDetails` | Dict? | Error metadata |
| `processingTime` | Dict[str, float]? | Time per step |
| `audioMetadata` | Dict? | Duration, format, etc. |
| `progress` | int? | 0–100 |
| `progressMessage` | str? | Progress description |

### `PipelineFile` Methods
| Method | Description |
|--------|-------------|
| `get_activity_age_seconds()` | Age of `lastActivityAt` in seconds |
| `is_activity_stale(threshold_seconds=120)` | True if activity older than threshold |

### Imports From
`typing`, `enum`, `datetime`, `pydantic`

### Imported By
Almost every file in `api/` and `services/`.

---

## `config/settings.py`

**Purpose:** Configuration management with persistent user overrides.

### Global Variables
| Name | Value |
|------|-------|
| `HOME_DIR` | `Path.home()` |
| `BACKEND_DIR` | Path of this file's parent |
| `DEFAULT_SETTINGS` | Massive nested dict of all defaults |
| `settings` | `Settings()` singleton |

### `Settings` Class
| Method | Description |
|--------|-------------|
| `__init__()` | Loads `config/user_settings.json`, merges with defaults |
| `load_settings()` | Reads JSON file, deep-merges into defaults |
| `save_settings()` | Writes current settings to JSON |
| `get(key, default=None)` | Dot-notation getter (`"transcription.solo_model"`) |
| `set(key, value)` | Dot-notation setter, auto-creates intermediate dicts, saves |
| `get_all()` | Returns copy of entire settings dict |
| `_update_nested_dict(base, update)` | Recursive dict merge helper |

### Module-Level Functions
| Function | Description |
|----------|-------------|
| `get_dependency_paths()` | Returns `{whisper, mlx_models, mlx_venv}` paths relative to `dependencies_folder` |
| `get_whisper_path_dynamic()` | Returns active whisper path, creates if needed |
| `get_mlx_models_path()` | Returns MLX models dir, creates if needed |
| `get_mlx_venv_path()` | Returns MLX venv path |
| `get_input_folder()` | Returns input folder, creates if needed |
| `get_output_folder()` | Returns output folder, creates if needed |
| `get_file_output_folder(filename, file_id=None)` | Returns per-file output folder: `{file_id}_{stem}/` or `{stem}/` (legacy) |
| `get_transcription_modules_path()` | **DEPRECATED** legacy symlink path |
| `get_whisper_path()` | **DEPRECATED** legacy symlink path |
| `get_solo_transcription_path()` | **DEPRECATED** |
| `get_conversation_transcription_path()` | **DEPRECATED** |

### Key Default Settings
| Key | Default |
|-----|---------|
| `input_folder` | `~/Documents/Voice Transcription Pipeline Audio Input` |
| `output_folder` | `~/Documents/Voice Transcription Pipeline Audio Output` |
| `transcription.solo_model` | `"base.en"` |
| `audio.supported_input_formats` | `[".m4a", ".wav", ".mp3", ".mp4", ".mov", ".md"]` |
| `enhancement.mlx.max_tokens` | `512` |
| `enhancement.mlx.timeout_seconds` | `45` |
| `enhancement.mlx.dynamic_tokens` | `True` |
| `export.author` | `""` (written to YAML frontmatter `author:` field) |
| `system.max_concurrent_files` | `1` |

### Imports From
`os`, `pathlib`, `typing`, `json`

### Imported By
`utils/status_tracker.py`, `api/files.py`, `api/enhance.py`, `api/config.py`, `api/system.py`, `services/transcription.py`, `services/sanitisation.py`, `services/enhancement.py`, `services/export.py`, `services/mlx_runner.py`, `main.py`

---

## `config/user_settings.json`

**Purpose:** Persisted user overrides merged on top of `DEFAULT_SETTINGS`.

### Notable User Overrides
| Key | Value |
|-----|-------|
| `enhancement.mlx.model_path` | `/Users/tiurihartog/.../Qwen3.5-9B-MLX-4bit` |
| `enhancement.mlx.max_tokens` | `20992` (vs default 512) |
| `enhancement.mlx.timeout_seconds` | `1800` (30 min, vs default 45s) |
| `enhancement.mlx.chat_template_overrides` | Inline Jinja2 template for Qwen3.5 (~77 lines) |
| `enhancement.prompts.title` | Custom title generation prompt (not in DEFAULT_SETTINGS) |
| `obsidian.vault_path` | `/Users/tiurihartog/Hackerman/Obsidian_LLM_Test_Vault` |
| `export.note_folder` | `/Users/tiurihartog/Downloads` |
| `export.audio_folder` | `/Users/tiurihartog/Downloads` |
| `dependencies_folder` | `/Users/tiurihartog/Hackerman/Skrift_dependencies` |
| `sanitisation.remove_filler_words` | `true` |
| `tags.max_old` | `15` (vs default 10) |
| `tags.max_new` | `7` (vs default 5) |

---

## `config/names.json`

**Purpose:** Canonical name mappings for the sanitisation step.

Schema:
```json
{ "people": [{ "canonical": "[[Full Name]]", "aliases": ["Nick", "Nicholas"], "short": "Nick" }] }
```

---

## `utils/status_tracker.py`

**Purpose:** Manages all file processing state. Reads/writes `status.json` per file. Single source of truth.

### `StatusTracker` Class
| Method | Description |
|--------|-------------|
| `__init__()` | Initializes `_files` dict + per-file `_locks` dict, calls `load_existing_files()` |
| `load_existing_files()` | Scans output folder for `status.json` files, validates audio paths, backfills `compiled_text` from `compiled.md` if missing |
| `create_file(filename, path, size, conversation_mode, file_id)` | Creates PipelineFile, saves immediately |
| `get_file(file_id)` | Returns PipelineFile from memory |
| `get_all_files()` | Returns all PipelineFiles |
| `update_file_status(file_id, step, status, error, result_content)` | Updates step status; cascades invalidation when transcript changes (resets sanitise/enhance/export + clears downstream fields) |
| `clear_error(file_id)` | Clears error and errorDetails |
| `add_processing_time(file_id, step, time_seconds)` | Appends to processingTime dict |
| `add_audio_metadata(file_id, metadata)` | Merges into audioMetadata |
| `set_enhancement_fields(file_id, working, copyedit, summary, tags)` | Sets enhanced_copyedit/summary/tags; `working` is back-compat alias for copyedit |
| `set_enhancement_title(file_id, title)` | Sets title, resets approval_status to "pending" |
| `delete_file(file_id)` | Removes status.json and memory entry |
| `save_file_status(file_id)` | Serializes PipelineFile to status.json under a per-file `threading.Lock` (prevents torn writes under batch load) |
| `get_processing_queue()` | Files with any PROCESSING step |
| `get_files_by_status(step, status)` | Filter by step+status |
| `update_file_progress(file_id, step, progress, status_message)` | Updates progress % + message |
| `update_last_activity(file_id, message)` | Updates lastActivityAt heartbeat |

### Global Instance
`status_tracker = StatusTracker()` — singleton

### Cascade Invalidation (triggered on new transcript)
Defined in `_TRANSCRIPT_DERIVED_FIELDS` constant — add new fields there to auto-include them in invalidation.
Current fields cleared: `sanitised`, `enhanced_copyedit`, `enhanced_summary`, `enhanced_title`, `enhanced_tags`, `tag_suggestions`, `exported`, `compiled_text`, `title_approval_status`
Steps reset to PENDING: `sanitise`, `enhance`, `export`

### Imports From
`json`, `uuid`, `threading`, `collections`, `datetime`, `pathlib`, `typing`, `models`, `config.settings`

### Imported By
`api/files.py`, `api/transcribe.py`, `api/sanitise.py`, `api/enhance.py`, `api/export.py`, `api/batch.py`, `api/system.py`, `services/transcription.py`, `services/sanitisation.py`, `services/enhancement.py`, `services/export.py`, `services/batch_manager.py`

---

## `api/files.py`

**Purpose:** File management — upload, list, delete, content retrieval, audio streaming.

### Functions
| Function | Description |
|----------|-------------|
| `_ingest_markdown_note(...)` | Parses Apple Notes .md export; marks transcribe DONE, generates compiled.md with YAML frontmatter |
| `upload_files(...)` | Multipart upload handler for audio + .md files |
| `get_files()` | Returns all pipeline files |
| `get_file(file_id)` | Returns single file |
| `delete_file(file_id)` | Deletes folder + removes from tracker |
| `get_file_status(file_id)` | Returns current status |
| `approve_title(file_id)` | Sets title_approval_status = "accepted" |
| `decline_title(file_id)` | Sets title_approval_status = "declined" |
| `get_file_content(file_id, content_type)` | Returns transcript/sanitised/enhanced/exported/wts |
| `get_file_audio(file_id, which)` | Streams audio with HTTP 206 range support |
| `get_file_srt(file_id)` | Returns SRT subtitles (**deprecated**) |
| `get_file_word_timings(file_id)` | Returns or synthesizes word_timings.json |
| `get_file_timeline(file_id)` | Parses Whisper JSON for token timings (multiple format support) |
| `update_transcript(file_id, body)` | Manual transcript edit |
| `update_sanitised(file_id, body)` | Manual sanitised text edit |
| `cancel_sanitise(file_id)` | Resets sanitise step to PENDING |
| `reset_file(file_id)` | Clears all downstream steps, preserves transcript |

### API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/files/upload` | Upload audio/note files |
| GET | `/api/files/` | List all files |
| GET | `/api/files/{file_id}` | Get file details |
| DELETE | `/api/files/{file_id}` | Delete file |
| GET | `/api/files/{file_id}/status` | Get file status |
| POST | `/api/files/{file_id}/title/approve` | Approve AI title |
| POST | `/api/files/{file_id}/title/decline` | Decline AI title |
| GET | `/api/files/{file_id}/content/{content_type}` | Get content |
| GET | `/api/files/{file_id}/audio/{which}` | Stream audio (range support) |
| GET | `/api/files/{file_id}/srt` | Get SRT (**deprecated**) |
| GET | `/api/files/{file_id}/word_timings` | Get/synthesize word timings |
| GET | `/api/files/{file_id}/timeline` | Parse Whisper JSON timeline |
| PUT | `/api/files/{file_id}/transcript` | Update transcript |
| PUT | `/api/files/{file_id}/sanitised` | Update sanitised text |
| POST | `/api/files/{file_id}/sanitise/cancel` | Reset sanitise step |
| POST | `/api/files/{file_id}/reset` | Full reset (preserve transcript) |

### External Dependencies
- `ffprobe` (duration extraction)
- `services.apple_notes_importer.parse_markdown_note`

### Imports From
`os`, `shutil`, `pathlib`, `fastapi`, `models`, `utils.status_tracker`, `config.settings`, `services.apple_notes_importer`, `subprocess`, `json`, `uuid`, `datetime`

### Imported By
`services/batch_manager.py` (as `file_service` parameter)

---

## `api/transcribe.py`

**Purpose:** Transcription trigger and debug stream.

### Functions
| Function | Description |
|----------|-------------|
| `start_transcription(file_id, request)` | Returns HTTP 400 immediately if conversation mode is requested; otherwise starts Whisper transcription in background thread |
| `stream_transcription(file_id)` | SSE debug helper — streams live Whisper CLI output (does NOT update pipeline status) |

### API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/process/transcribe/{file_id}` | Start transcription |
| GET | `/api/process/transcribe/stream/{file_id}` | SSE stream debug output |

### Imports From
`threading`, `fastapi`, `models`, `utils.status_tracker`, `services.transcription`

### Imported By
Nothing directly (called via HTTP).

---

## `api/sanitise.py`

**Purpose:** Name linking and disambiguation.

### Functions
| Function | Description |
|----------|-------------|
| `start_sanitise(file_id, request)` | Runs sanitisation; returns 409 if alias is ambiguous |
| `resolve_sanitise(file_id, body)` | Applies user disambiguation decisions |

### API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/process/sanitise/{file_id}` | Start sanitisation |
| POST | `/api/process/sanitise/{file_id}/resolve` | Resolve ambiguous aliases |

### Key Behavior
Returns HTTP **409** (not an error) with `{ status: 'needs_disambiguation', occurrences: [...] }` when alias maps to multiple people. Frontend handles this by showing a disambiguation modal.

### Imports From
`json`, `fastapi`, `models`, `utils.status_tracker`, `services.sanitisation`

---

## `api/enhance.py`

**Purpose:** MLX text enhancement, tag management, model management, compilation to Obsidian markdown.

### Functions
| Function | Description |
|----------|-------------|
| `test_enhance_model()` | Validates selected MLX model loads and generates sample |
| `save_chat_template_override()` | Save or clear per-model chat template override |
| `start_enhancement(file_id)` | Starts non-streaming enhancement |
| `get_enhance_input(file_id)` | Returns text being sent to LLM |
| `enhance_stream(file_id)` | SSE streaming enhancement; rejects with 409 if stream already active |
| `get_enhance_plan(file_id)` | Debug: returns final assembled prompt string |
| `_auto_compile_if_complete(file_id)` | Thin wrapper → `services.enhancement.auto_compile_if_complete` |
| `set_enhance_title(file_id)` | Set title field, trigger auto-compile |
| `set_enhance_copyedit(file_id)` | Set copy edit field, trigger auto-compile |
| `set_enhance_summary(file_id)` | Set summary field, trigger auto-compile |
| `set_enhance_tags(file_id)` | Set tags array, trigger auto-compile |
| `get_tag_whitelist()` | Thin wrapper → `services.enhancement.load_tag_whitelist` |
| `refresh_tag_whitelist()` | Scans Obsidian vault frontmatter, rebuilds whitelist |
| `generate_tags(file_id)` | Thin wrapper → `services.enhancement.generate_tags_service` |
| `_compile_file(file_id)` | Thin wrapper → `services.enhancement.compile_file` |
| `compile_for_obsidian(file_id)` | Explicit compile endpoint |
| `list_enhance_models()` | List available MLX models with sizes |
| `upload_enhance_model()` | Upload new MLX model file |
| `delete_enhance_model(filename)` | Delete model; clears selection if active |
| `select_enhance_model()` | Select model (restricted to app's models_dir) |
| `get_selected_chat_template()` | Get chat template for selected model + overrides |

### API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/process/enhance/test` | Test model |
| POST | `/api/process/enhance/chat-template` | Save/clear chat template |
| POST | `/api/process/enhance/{file_id}` | Start enhancement |
| GET | `/api/process/enhance/input/{file_id}` | Get LLM input |
| GET | `/api/process/enhance/stream/{file_id}` | SSE stream enhancement |
| GET | `/api/process/enhance/plan/{file_id}` | Debug: show prompt |
| POST | `/api/process/enhance/title/{file_id}` | Set title |
| POST | `/api/process/enhance/copyedit/{file_id}` | Set copy edit |
| POST | `/api/process/enhance/working/{file_id}` | Back-compat alias for copyedit |
| POST | `/api/process/enhance/summary/{file_id}` | Set summary |
| POST | `/api/process/enhance/tags/{file_id}` | Set tags |
| GET | `/api/process/enhance/tags/whitelist` | Get tag whitelist |
| POST | `/api/process/enhance/tags/whitelist/refresh` | Rebuild whitelist from vault |
| POST | `/api/process/enhance/tags/generate/{file_id}` | Generate tags |
| POST | `/api/process/enhance/compile/{file_id}` | Compile markdown |
| GET | `/api/process/enhance/models/selected/chat-template` | Get chat template |
| GET | `/api/process/enhance/models` | List models |
| POST | `/api/process/enhance/models/upload` | Upload model |
| DELETE | `/api/process/enhance/models/{filename}` | Delete model |
| POST | `/api/process/enhance/models/select` | Select model |

### External Dependencies
- `ffprobe` (date extraction from audio) — now used in `services/enhancement.py`
- `services.enhancement` (streaming, non-streaming, compile, tag generation, whitelist)
- Obsidian vault (regex frontmatter scan for tags)

### Imports From
`fastapi`, `pathlib`, `json`, `os`, `re`, `utils.status_tracker`, `services.enhancement`, `config.settings`, `models`

### Imported By
Nothing directly (all business logic moved to `services/enhancement.py`)

---

## `api/export.py`

**Purpose:** Compiled markdown retrieval and vault export.

### Functions
| Function | Description |
|----------|-------------|
| `get_compiled_markdown(file_id)` | Retrieves active .md file: prefers `compiled.md`, then single .md, then newest |
| `put_compiled_text(file_id, body)` | Saves edits to status.json only (no disk write) |
| `save_compiled_markdown(file_id, body)` | Save + optional rename + export to vault + copy audio |
| `start_export(file_id, request)` | **Legacy endpoint** — marks export PROCESSING only; no actual export logic |

### API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/process/export/compiled/{file_id}` | Get compiled markdown |
| PUT | `/api/process/export/compiled/{file_id}` | Save edits to status.json |
| POST | `/api/process/export/compiled/{file_id}` | Save + export to vault |
| POST | `/api/process/export/{file_id}` | **Legacy**: mark export PROCESSING |

### Imports From
`datetime`, `fastapi`, `models`, `utils.status_tracker`, `services.export`

---

## `api/batch.py`

**Purpose:** Batch transcription and enhancement jobs.

### Classes
| Class | Description |
|-------|-------------|
| `StartBatchRequest` | `file_ids: List[str], mode: str` |
| `CancelBatchRequest` | `batch_id: str` |

### Functions
| Function | Description |
|----------|-------------|
| `start_transcribe_batch(request)` | Start batch transcription (sequential, oldest first) |
| `get_batch_status(batch_id)` | Get status of specific batch |
| `cancel_batch(batch_id, request)` | Cancel active batch (current file completes first) |
| `get_current_batch()` | Get currently active batch |
| `start_enhance_batch(request)` | Start batch enhancement (skips completed steps) |
| `delete_batch(batch_id)` | Delete completed batch |
| `stream_batch_enhance()` | SSE stream live batch enhancement progress |

### API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/batch/transcribe/start` | Start transcription batch |
| GET | `/api/batch/{batch_id}/status` | Get batch status |
| POST | `/api/batch/{batch_id}/cancel` | Cancel batch |
| GET | `/api/batch/current` | Get current active batch |
| POST | `/api/batch/enhance/start` | Start enhancement batch |
| DELETE | `/api/batch/{batch_id}` | Delete batch |
| GET | `/api/batch/enhance/stream` | SSE stream |

### External Dependencies
- `services.batch_manager.BatchManager` singleton
- `BATCH_DATA_DIR = backend/data/`

### Imports From
`fastapi`, `typing`, `pydantic`, `asyncio`, `services.batch_manager`, `utils.status_tracker`, `pathlib`, `logging`

---

## `api/system.py`

**Purpose:** Resource monitoring and health checks.

### Functions
| Function | Description |
|----------|-------------|
| `get_system_resources()` | CPU, RAM, disk, optional CPU temperature |
| `get_system_status()` | Current processing status + queue length |
| `health_check()` | Comprehensive health: resources + components + file stats + Python version |

### API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/system/resources` | CPU/RAM/disk/temp |
| GET | `/api/system/status` | Processing status |
| GET | `/api/system/health` | Full health check |

### External Dependencies
- `psutil` (CPU, RAM, disk, temperature)

### Imports From
`psutil`, `os`, `fastapi`, `models`, `utils.status_tracker`, `config.settings`

---

## `api/config.py`

**Purpose:** Settings and configuration management, names mapping.

### Functions
| Function | Description |
|----------|-------------|
| `get_all_config()` | Return complete configuration |
| `update_config(body)` | Update single key via dot notation |
| `reset_config()` | Delete settings file, reload defaults |
| `get_input_folder()` | Get input folder path |
| `set_input_folder(body)` | Set + create input folder |
| `get_output_folder()` | Get output folder path |
| `set_output_folder(body)` | Set + create output folder |
| `get_sanitisation_settings()` | Get sanitisation config block |
| `update_sanitisation_settings(body)` | Update sanitisation config block |
| `get_names_mapping()` | Get names.json (sorted alphabetically) |
| `update_names_mapping(body)` | Write names.json (auto-sorts, normalizes canonical format) |
| `get_transcription_modules()` | Available transcription module info |
| `get_config_value(key)` | Get single value by dot notation |

### API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/config/` | All config |
| POST | `/api/config/update` | Update key |
| POST | `/api/config/reset` | Reset defaults |
| GET | `/api/config/folders/input` | Get input folder |
| POST | `/api/config/folders/input` | Set input folder |
| GET | `/api/config/folders/output` | Get output folder |
| POST | `/api/config/folders/output` | Set output folder |
| GET | `/api/config/sanitisation` | Get sanitisation config |
| POST | `/api/config/sanitisation` | Update sanitisation config |
| GET | `/api/config/names` | Get names |
| POST | `/api/config/names` | Update names |
| GET | `/api/config/transcription/modules` | Transcription module info |
| GET | `/api/config/{key}` | Single config value |

### Imports From
`fastapi`, `models`, `config.settings`, `pathlib`, `json`, `os`

---

## `services/transcription.py`

**Purpose:** Whisper.cpp subprocess management, word-level timing extraction, heartbeat progress.

### Global State
| Variable | Description |
|----------|-------------|
| `_ACTIVE_TRANSCRIBE_PROCS: dict[str, subprocess.Popen]` | Running transcription processes by file_id |
| `_ACTIVE_TRANSCRIBE_LOCK: threading.Lock` | Thread-safe access to the above |

### Functions
| Function | Description |
|----------|-------------|
| `cancel_transcription_process(file_id)` | Kills in-flight transcription subprocess; returns True if killed |
| `_compute_dynamic_timeout_seconds(file_id)` | Computes timeout from audio duration; minimum 600s (10 min) |
| `run_solo_transcription(audio_path, output_dir, file_id)` | Core function: runs `./transcribe.sh`, parses output, builds `word_timings.json`, cleans temp files; returns transcript text |
| `run_conversation_transcription(audio_path, output_dir)` | **NOT IMPLEMENTED** — placeholder; returns error message |
| `process_transcription_thread(file_id, conversation_mode)` | Thread function: starts heartbeat thread every 10s, calls solo transcription, persists results to status_tracker |
| `generate_transcription_stream(file_id)` | **Debug only** — async SSE stream of live Whisper CLI output via pseudo-TTY; does not persist anything |

### External Dependencies
- **Whisper.cpp CLI:** `./transcribe.sh <input.m4a> <output_dir>` at `{deps}/whisper/Transcription/`
- Produces: `.txt`, `.json`, `.wts`, `.srt`, `*_processed.wav`

### Imports From
`pathlib`, `models`, `utils.status_tracker`, `config.settings`, `subprocess`, `shutil`, `time`, `threading`, `asyncio`, `os`, `pty`, `logging`, `json`, `re`

### Imported By
`api/transcribe.py`, `services/batch_manager.py`

---

## `services/sanitisation.py`

**Purpose:** Name linking and disambiguation logic.

### Functions
| Function | Description |
|----------|-------------|
| `process_sanitisation(file_id, text)` | Links aliases to `[[Canonical Name]]`; returns `done` or `needs_disambiguation` with occurrence list |
| `resolve_name_disambiguation(file_id, text, decisions)` | Applies user's disambiguation choices; returns final sanitised text |

### Internal Helpers
`to_link(canon)`, `not_inside_link(s, start)`, `sort_key(entry)`

### Key Logic
- Whole-word, case-insensitive regex per alias
- `mode='first'`: first mention → full link, rest → short name
- `mode='all'`: all mentions → full link
- Avoids re-linking text already inside `[[...]]`
- Preserves possessives (`'s`, `'s`)
- Link format: `wiki` (`[[Name]]`) or `wiki_with_path` (`[[People/Name|Name]]`)

### External Dependencies
- `backend/config/names.json`

### Imports From
`json`, `re`, `pathlib`, `models`, `utils.status_tracker`, `config.settings`

### Imported By
`api/sanitise.py`

---

## `services/enhancement.py`

**Purpose:** MLX streaming enhancement, bracket preservation, per-file concurrency guard. Also owns compile and tag generation business logic (moved from `api/enhance.py` — 3.1).

### Global State
`ACTIVE_ENHANCE_STREAMS: set[str]` — Tracks files with active streams (prevents concurrent enhancement per file).

### Functions
| Function | Description |
|----------|-------------|
| `_schedule_idle_cache_clear()` | Waits 10s then clears MLX cache if idle (manual mode only) |
| `preserve_brackets(source, output)` | Re-inserts `[[...]]` tokens from source that the LLM dropped |
| `test_model()` | Validates model loads and generates; returns metrics dict |
| `generate_enhancement(file_id, text, prompt, preset)` | Synchronous (non-streaming) enhancement |
| `generate_enhancement_stream(file_id, input_text, prompt)` | Async generator yielding SSE events: `start`, `plan`, `stats`, `token`, `done`, `error` |
| `_all_enhancement_parts_present(pf)` | Returns True when title+copyedit+summary+tags are all non-empty |
| `compile_file(file_id)` | Core compile: assembles YAML frontmatter + body → `compiled.md`; reads `export.author` from settings |
| `auto_compile_if_complete(file_id)` | Silently calls `compile_file` if all 4 parts present; never raises |
| `load_tag_whitelist()` | Reads whitelist JSON from disk; raises `ValueError` on failure |
| `generate_tags_service(file_id)` | MLX tag suggestion: old (from whitelist) + new; persists suggestions to status.json |

### SSE Events from `generate_enhancement_stream`
| Event | Data |
|-------|------|
| `start` | `{}` |
| `plan` | `{used_chat_template, effective_max_tokens, prompt_preview}` |
| `stats` | `{input_length, effective_max_tokens}` |
| `token` | Partial text chunk |
| `done` | Final complete text |
| `error` | Error message |

### External Dependencies
- `services.mlx_runner` (generate, stream, plan)
- `ffprobe` (date extraction in `compile_file`)

### Imports From
`time`, `asyncio`, `threading`, `re`, `subprocess`, `json`, `os`, `datetime`, `re`, `logging`, `pathlib`, `config.settings`, `services.mlx_runner`, `utils.status_tracker`

### Imported By
`api/enhance.py`, `services/batch_manager.py`

---

## `services/export.py`

**Purpose:** Markdown compilation and vault export.

### Functions
| Function | Description |
|----------|-------------|
| `_resolve_attachment_markers(markdown, file_folder, vault_folder)` | Converts Apple Notes image refs to Obsidian embeds `![[file.jpg]]`; copies attachment files |
| `get_compiled_markdown(file_id)` | Resolves active .md file (compiled.md → single .md → newest .md); extracts YAML title |
| `_inject_audio_embed(markdown, audio_filename)` | Inserts `![[file.m4a]]` after YAML frontmatter; checks for duplicates |
| `_normalize_frontmatter_spacing(markdown)` | Ensures 2 blank lines between YAML block and body |
| `save_compiled_markdown(file_id, content, export_to_vault, vault_path, include_audio)` | Core export: rename to YAML title, copy to vault, copy audio, resolve attachments |

### External Dependencies
- Filesystem (Path, shutil)
- `export.note_folder`, `export.audio_folder` from settings

### Imports From
`re`, `shutil`, `pathlib`, `models`, `utils.status_tracker`, `config.settings`

### Imported By
`api/export.py`

---

## `services/batch_manager.py`

**Purpose:** Sequential batch processing for transcription and enhancement. State persistence, SSE broadcast, consecutive-failure tracking.

### Enums
| Enum | Values |
|------|--------|
| `BatchType` | `TRANSCRIBE`, `ENHANCE` |
| `BatchStatus` | `RUNNING`, `COMPLETED`, `CANCELLED`, `FAILED` |
| `FileStatus` | `WAITING`, `PROCESSING`, `COMPLETED`, `FAILED`, `SKIPPED` |

### `BatchManager` Class
| Method | Description |
|--------|-------------|
| `__init__(data_dir)` | Loads persisted state, initializes SSE client set |
| `_load_state()` | Loads `batch_state.json`, resumes interrupted RUNNING batch |
| `_save_state()` | Persists to `batch_state.json` after every state change |
| `has_active_batch()` | True if current batch status is RUNNING |
| `start_transcribe_batch(file_ids, file_service)` | Creates batch, starts `_process_batch()` as asyncio task |
| `_process_batch(file_service, transcription_service)` | Sequential transcription: starts Whisper server once, processes all files, stops after 3 consecutive failures |
| `start_enhance_batch(file_ids, file_service)` | Creates enhancement batch, starts `_process_enhance_batch()` |
| `_process_enhance_batch(file_service)` | Sequential enhancement: Title → Copy Edit → Summary → Tags per file; auto-compiles; clears MLX cache on completion |
| `_process_enhancement_steps(file_id, file_entry, pf)` | 4-step enhancement for single file; skips already-done steps |
| `_run_enhancement_stream(file_id, input_text, prompt, step_name)` | Consumes `generate_enhancement_stream()`, broadcasts tokens to all SSE clients |
| `cancel_batch()` | Cancels asyncio task, marks batch CANCELLED |
| `get_batch_status(batch_id)` | Returns batch state dict |
| `_compute_batch_result()` | Computes `success`/`partial_success`/`failed` based on file outcomes |
| `_sort_files_by_creation_date(file_ids, file_service)` | Sorts by `audioMetadata.creation_date` or `uploadedAt` fallback |
| `register_stream_client(client_id)` | Adds SSE client queue |
| `unregister_stream_client(client_id)` | Removes SSE client queue |
| `broadcast(event_type, data)` | Sends SSE event to all connected clients |
| `_start_whisper_server()` | Spawns `whisper-server` subprocess on port 8090 |
| `_stop_whisper_server()` | Terminates Whisper server, cleans temp dir |
| `_transcribe_via_server(file_id, file_service)` | Sends audio to Whisper server, polls `/status` until complete |

### Hardcoded Constants
| Constant | Value |
|----------|-------|
| Whisper server port | `8090` |
| Consecutive failure limit | `3` |
| SSE heartbeat timeout | `2.0s` |

### External Dependencies
- Whisper server subprocess (port 8090)
- `services.enhancement.generate_enhancement_stream`
- `services.enhancement.generate_tags_service` (was `api.enhance.generate_tags` — inverted dependency fixed in 3.1)
- `services.enhancement.auto_compile_if_complete` (was `api.enhance._auto_compile_if_complete` — fixed in 3.1)

### Imports From
`asyncio`, `json`, `logging`, `os`, `subprocess`, `time`, `shutil`, `datetime`, `pathlib`, `typing`, `enum`

### Imported By
`api/batch.py`

### Global Instance
`get_batch_manager()` returns singleton; data dir: `backend/data/`

---

## `services/mlx_runner.py`

**Purpose:** MLX inference wrapper: chat templates, dynamic token budgeting, VLM detection, API compatibility.

### Classes
`MLXNotAvailable` — Custom exception for graceful fallback when MLX is not installed.

### Functions
| Function | Description |
|----------|-------------|
| `_filter_generate_kwargs(generate_func, kwargs)` | Introspects function signature; drops unsupported kwargs; handles `temp`/`temperature` aliasing across mlx-lm versions |
| `_load_tokenizer(model_path)` | Lazy-loads HuggingFace tokenizer; extracts `chat_template` attribute |
| `_build_prompt(prompt, input_text, model_path)` | Builds final prompt with or without chat template; returns `(final_prompt, used_chat, template_name, tokenizer)` |
| `_effective_max_tokens(input_text, cap, tokenizer)` | Dynamic budget: `min(cap, max(min_tokens, input_tokens × ratio))` |
| `stream_with_mlx(prompt, input_text, model_path, max_tokens, temperature)` | Streaming generator yielding text chunks; switches between text model and VLM API |
| `generate_with_mlx(prompt, input_text, model_path, max_tokens, temperature, timeout_seconds)` | Synchronous generation; soft timeout check post-generation |
| `plan_generation(prompt, input_text, model_path, max_tokens, temperature)` | Debug helper: returns plan metrics without generating anything |

### External Dependencies
- `mlx-lm` (`generate`, `stream_generate`)
- `mlx-vlm` (`generate`, `stream_generate`) — fallback for vision models
- `transformers.AutoTokenizer` (chat templates)
- `services.mlx_cache` (model singleton)

### Imports From
`time`, `inspect`, `pathlib`, `typing`, `config.settings`, `services.mlx_cache`

### Imported By
`services/enhancement.py`, `api/enhance.py`

---

## `services/mlx_cache.py`

**Purpose:** Thread-safe singleton MLX model cache to avoid repeated loads during a session.

### `MLXModelCache` Class
| Method | Description |
|--------|-------------|
| `get_instance()` | Singleton factory (double-checked locking) |
| `get_model(model_path)` | Thread-safe cache lookup; loads if miss or path changed; updates `_last_used` |
| `is_vlm()` | True if cached model is a vision-capable model |
| `_is_cache_valid(model_path)` | Checks path match + model/tokenizer non-None |
| `_load_model(model_path)` | Loads model: tries `mlx_lm.load` first, falls back to `mlx_vlm.load` on failure |
| `_clear_cache_internal()` | Sets all fields to None, forces `gc.collect()` |
| `clear_cache(reason)` | Logs reason, clears cache |
| `get_cache_info()` | Returns `{cached, model_path, last_used, idle_seconds}` |
| `should_clear_idle_cache(idle_timeout)` | True if model has been idle longer than timeout |

### External Dependencies
- `mlx-lm` (`load`)
- `mlx-vlm` (`load`) — fallback

### Imports From
`time`, `logging`, `pathlib`, `typing`, `threading`

### Imported By
`services/mlx_runner.py`

---

## `services/apple_notes_importer.py`

**Purpose:** Parses Apple Notes .md exports, renames attachments with collision-resistant names, updates markdown refs.

### Functions
| Function | Description |
|----------|-------------|
| `parse_markdown_note(md_path)` | Extracts title from `# heading` or filename; renames attachments to `{title} - {n}{ext}`; updates refs in .md; re-saves file; returns `{title, text, attachments}` |
| `_guess_mime(ext)` | Maps file extension to MIME type; fallback `application/octet-stream` |

### External Dependencies
- Filesystem (Path operations)
- `urllib.parse` (URL decode)

### Imports From
`re`, `pathlib`, `urllib.parse`

### Imported By
`api/files.py`

---

## Complete API Endpoint Index

| Method | Full Path | File | Description |
|--------|-----------|------|-------------|
| POST | `/api/files/upload` | files.py | Upload audio/notes |
| GET | `/api/files/` | files.py | List all files |
| GET | `/api/files/{file_id}` | files.py | Get file |
| DELETE | `/api/files/{file_id}` | files.py | Delete file |
| GET | `/api/files/{file_id}/status` | files.py | Get status |
| POST | `/api/files/{file_id}/title/approve` | files.py | Approve title |
| POST | `/api/files/{file_id}/title/decline` | files.py | Decline title |
| GET | `/api/files/{file_id}/content/{type}` | files.py | Get content |
| GET | `/api/files/{file_id}/audio/{which}` | files.py | Stream audio |
| GET | `/api/files/{file_id}/srt` | files.py | SRT subtitles (deprecated) |
| GET | `/api/files/{file_id}/word_timings` | files.py | Word timings |
| GET | `/api/files/{file_id}/timeline` | files.py | Token timeline |
| PUT | `/api/files/{file_id}/transcript` | files.py | Edit transcript |
| PUT | `/api/files/{file_id}/sanitised` | files.py | Edit sanitised |
| POST | `/api/files/{file_id}/sanitise/cancel` | files.py | Reset sanitise |
| POST | `/api/files/{file_id}/reset` | files.py | Reset all steps |
| POST | `/api/process/transcribe/{file_id}` | transcribe.py | Start transcription |
| GET | `/api/process/transcribe/stream/{file_id}` | transcribe.py | Debug SSE stream |
| POST | `/api/process/sanitise/{file_id}` | sanitise.py | Start sanitisation |
| POST | `/api/process/sanitise/{file_id}/resolve` | sanitise.py | Resolve disambiguation |
| POST | `/api/process/enhance/test` | enhance.py | Test model |
| POST | `/api/process/enhance/chat-template` | enhance.py | Save template override |
| POST | `/api/process/enhance/{file_id}` | enhance.py | Start enhancement |
| GET | `/api/process/enhance/input/{file_id}` | enhance.py | Get LLM input |
| GET | `/api/process/enhance/stream/{file_id}` | enhance.py | SSE stream enhancement |
| GET | `/api/process/enhance/plan/{file_id}` | enhance.py | Debug: show prompt |
| POST | `/api/process/enhance/title/{file_id}` | enhance.py | Set title |
| POST | `/api/process/enhance/copyedit/{file_id}` | enhance.py | Set copy edit |
| POST | `/api/process/enhance/working/{file_id}` | enhance.py | Alias for copyedit (deprecated) |
| POST | `/api/process/enhance/summary/{file_id}` | enhance.py | Set summary |
| POST | `/api/process/enhance/tags/{file_id}` | enhance.py | Set tags |
| GET | `/api/process/enhance/tags/whitelist` | enhance.py | Get tag whitelist |
| POST | `/api/process/enhance/tags/whitelist/refresh` | enhance.py | Rebuild whitelist from vault |
| POST | `/api/process/enhance/tags/generate/{file_id}` | enhance.py | Generate tags |
| POST | `/api/process/enhance/compile/{file_id}` | enhance.py | Compile markdown |
| GET | `/api/process/enhance/models/selected/chat-template` | enhance.py | Get model chat template |
| GET | `/api/process/enhance/models` | enhance.py | List models |
| POST | `/api/process/enhance/models/upload` | enhance.py | Upload model |
| DELETE | `/api/process/enhance/models/{filename}` | enhance.py | Delete model |
| POST | `/api/process/enhance/models/select` | enhance.py | Select model |
| GET | `/api/process/export/compiled/{file_id}` | export.py | Get compiled markdown |
| PUT | `/api/process/export/compiled/{file_id}` | export.py | Save edits to status.json |
| POST | `/api/process/export/compiled/{file_id}` | export.py | Save + export to vault |
| POST | `/api/process/export/{file_id}` | export.py | Legacy (NOOP — marks PROCESSING only) |
| POST | `/api/batch/transcribe/start` | batch.py | Start batch transcription |
| GET | `/api/batch/{batch_id}/status` | batch.py | Batch status |
| POST | `/api/batch/{batch_id}/cancel` | batch.py | Cancel batch |
| GET | `/api/batch/current` | batch.py | Current batch |
| POST | `/api/batch/enhance/start` | batch.py | Start batch enhancement |
| DELETE | `/api/batch/{batch_id}` | batch.py | Delete batch |
| GET | `/api/batch/enhance/stream` | batch.py | SSE batch stream |
| GET | `/api/system/resources` | system.py | Resources |
| GET | `/api/system/status` | system.py | Status |
| GET | `/api/system/health` | system.py | Health check |
| GET | `/api/config/` | config.py | All config |
| POST | `/api/config/update` | config.py | Update key |
| POST | `/api/config/reset` | config.py | Reset defaults |
| GET | `/api/config/folders/input` | config.py | Input folder |
| POST | `/api/config/folders/input` | config.py | Set input folder |
| GET | `/api/config/folders/output` | config.py | Output folder |
| POST | `/api/config/folders/output` | config.py | Set output folder |
| GET | `/api/config/sanitisation` | config.py | Sanitisation config |
| POST | `/api/config/sanitisation` | config.py | Update sanitisation |
| GET | `/api/config/names` | config.py | Names mapping |
| POST | `/api/config/names` | config.py | Update names |
| GET | `/api/config/transcription/modules` | config.py | Transcription modules |
| GET | `/api/config/{key}` | config.py | Single config value |

---

## Observations

### Dead Code / Unused
| Item | Location | Notes |
|------|----------|-------|
| `enhanced` field on `PipelineFile` | `models.py` | Marked deprecated; dropped on save but still loaded from old status.json files |
| `run_conversation_transcription()` | `services/transcription.py` | Not implemented; calling it returns an error ("coming soon") |
| `POST /api/process/export/{file_id}` | `api/export.py` | "Legacy" endpoint that only marks PROCESSING, never actually exports anything |
| `GET /api/files/{file_id}/srt` | `api/files.py` | Marked deprecated; word_timings is now the preferred path |
| `POST /api/process/enhance/working/{file_id}` | `api/enhance.py` | Back-compat alias for `/copyedit/`; safe to remove once frontend is updated |
| ~~`get_transcription_modules_path()`, `get_whisper_path()`, `get_solo_transcription_path()`, `get_conversation_transcription_path()`~~ | ~~`config/settings.py`~~ | ~~All marked DEPRECATED; still exported from the module~~ — **INCORRECT**: actively called by `batch_manager.py` (production whisper path resolution), `system.py`, and `config.py` |
| `include_timestamps` export setting | `config/settings.py` | Marked "For future implementation"; never used anywhere in the codebase |
| ~~`source_type` field~~ | ~~`models.py`~~ | ~~Defined on PipelineFile; no code reads it to change behaviour~~ — **INCORRECT**: set in `files.py:34,219`; read in `enhance.py:531` to gate note-specific behaviour |
| ~~`ProcessingRequest.enhancementType`~~ | ~~`models.py`~~ | ~~Defined but no consumer found~~ — **INCORRECT**: consumed in `enhance.py:91` as `preset` |
| ~~`quote` import~~ | ~~`services/apple_notes_importer.py`~~ | ~~`from urllib.parse import quote, unquote` — `quote` is never called~~ — **INCORRECT**: called on line 67 inside attachment ref replacement |

### Orphaned / Nothing Calls Them
| Item | Location | Notes |
|------|----------|-------|
| `generate_transcription_stream()` | `services/transcription.py` | Only reachable via debug SSE endpoint; no production caller |
| ~~`plan_generation()`~~ | ~~`services/mlx_runner.py`~~ | ~~Called only by the debug `/enhance/plan/` endpoint~~ — **INCORRECT**: called in production at `services/enhancement.py:114,284` for all enhancement runs |
| `get_enhance_plan()` endpoint | `api/enhance.py` | Debug-only; likely never called from the frontend |
| `stream_transcription()` endpoint | `api/transcribe.py` | Debug SSE endpoint; no frontend call |
| `get_cache_info()` | `services/mlx_cache.py` | No endpoint exposes this; debug use only |

### Inconsistencies / Artifacts
| Issue | Location | Notes |
|-------|----------|-------|
| **Hardcoded author `"Tiuri"`** | `api/files.py`, `api/enhance.py` | ✅ Fixed (3.3) — now reads `settings.get('export.author')` |
| **`psutil.boot_time()` used as timestamp** | `api/system.py` | ✅ Fixed (1.4) |
| **Estimated time hardcoded** | `api/transcribe.py` | ✅ Fixed (4.8) |
| **Cascade invalidation uses hardcoded field list** | `utils/status_tracker.py` | ✅ Fixed (3.7) — `_TRANSCRIPT_DERIVED_FIELDS` constant |
| **Bare `except: pass`** | `utils/status_tracker.py` | ✅ Fixed (1.5) |
| **Cosmetic key reordering on save** | `utils/status_tracker.py` | ✅ Fixed (4.6) |
| **Multiple Whisper JSON format parsers** | `api/files.py` (`get_file_timeline`) | ✅ Fixed (4.7) |
| **`title_approval_status` as bare string** | `models.py` | ✅ Fixed (4.1) |
| **VLM detection via exception message string** | `services/mlx_cache.py` | ✅ Fixed (4.5) |
| **Tag generation padding heuristic** | `services/enhancement.py` | ✅ Fixed (4.12) |
| **`batch_manager` imports from `api.enhance`** | `services/batch_manager.py` | ✅ Fixed (3.1) |
| **`.md` listed in audio supported formats** | `config/settings.py` | Cosmetic; intentional for Apple Notes support — no action |
| **Timeout enforcement is post-generation** | `services/mlx_runner.py` | ✅ Fixed (4.11) |
| **`enhancement.prompts.title` missing from DEFAULT_SETTINGS** | `config/settings.py` / `user_settings.json` | ✅ Fixed (1.6) |

### Hardcoded Values That Should Be Settings
| Value | Location | Suggested Setting |
|-------|----------|-------------------|
| `127.0.0.1:8000` | `main.py` | ✅ Fixed (4.9) |
| CORS origins list | `main.py` | ✅ Fixed (4.10) |
| Author `"Tiuri"` | `api/files.py`, `api/enhance.py` | ✅ Fixed (3.3) |
| Whisper server port `8090` | `services/batch_manager.py` | ✅ Fixed (4.2) |
| Consecutive failure limit `3` | `services/batch_manager.py` | ✅ Fixed (4.3) |

### Broken / Half-Finished
| Item | Location | Notes |
|------|----------|-------|
| **`run_conversation_transcription()`** | `services/transcription.py` | ✅ Removed (1.8) |
| **`POST /api/process/export/{file_id}` (legacy)** | `api/export.py` | ✅ Removed (2.2) |
| **No concurrent-access locking on status.json** | `utils/status_tracker.py` | ✅ Fixed (3.2) — per-file `threading.Lock` |
| **SSE broadcast error handling missing** | `services/batch_manager.py` | ✅ Already done (4.4) |
| **`reload=True` in production** | `main.py` | ✅ Fixed (3.5) — gated behind `DEBUG=1` |
| **Exception handler exposes stack traces** | `main.py` | ✅ Fixed (3.6) — gated behind `DEBUG=1` |
| **Conversation mode** | Multiple files | ✅ Fixed (3.4) — API returns 400 immediately |

---

## Cleanup Plan

> Verified against live code. Items in the Observations tables marked **INCORRECT** were confirmed wrong by grep and have been struck through.

### Done ✅
| # | What | Where |
|---|------|--------|
| 1.4 | `psutil.boot_time()` → `time.time()` for health timestamp; fix broken `psutil.time.time()` call | `api/system.py` |
| 1.5 | Bare `except:` → `except Exception:` | `utils/status_tracker.py` |
| 1.6 | Add `enhancement.prompts.title` to `DEFAULT_SETTINGS` | `config/settings.py` |
| 1.7 | Remove `include_timestamps` from `DEFAULT_SETTINGS` | `config/settings.py` |
| 1.8 | Remove `run_conversation_transcription()` stub | `services/transcription.py` |
| 1.9 | Remove `get_cache_info()` | `services/mlx_cache.py` |
| 2.1 | Remove `POST /api/process/enhance/working/{file_id}` alias | `api/enhance.py` |
| 2.2 | Remove `POST /api/process/export/{file_id}` legacy NOOP + unused imports | `api/export.py` |
| 2.3 | Remove `GET /api/process/enhance/plan/{file_id}` debug endpoint | `api/enhance.py` |
| 2.4 | Remove `GET /api/process/transcribe/stream/{file_id}` + `generate_transcription_stream()` + `asyncio`/`pty`/`os` imports | `api/transcribe.py`, `services/transcription.py` |
| 2.5 | Remove `enhanced` field from `PipelineFile` + all 4 references | `models.py`, `api/files.py`, `utils/status_tracker.py` |

> **Keep:** `GET /api/files/{file_id}/srt` — still called by `SanitiseTab.tsx:201` in the current frontend.

---

### Tier 3 — Structural ✅ All done

| # | What | Where | Status |
|---|------|--------|--------|
| 3.1 | Move shared logic out of `api/enhance.py` into `services/` | `services/enhancement.py` | ✅ `compile_file`, `auto_compile_if_complete`, `load_tag_whitelist`, `generate_tags_service`, `_all_enhancement_parts_present` moved; batch_manager now imports from services |
| 3.2 | Add file locking to `status.json` reads/writes | `utils/status_tracker.py` | ✅ Per-file `threading.Lock` in `_locks` dict; `save_file_status` acquires lock before write |
| 3.3 | Move hardcoded author `"Tiuri"` to a setting (`export.author`) | `api/files.py`, `services/enhancement.py` | ✅ `export.author` added to defaults (empty string); both compile paths read it |
| 3.4 | Gate conversation mode at API boundary | `api/transcribe.py` | ✅ Returns HTTP 400 before thread is spawned; service-layer check removed |
| 3.5 | Make `reload=True` conditional on a `DEBUG` env flag | `main.py` | ✅ `reload=_debug_mode`; `DEBUG=1` env var enables it |
| 3.6 | Gate stack trace exposure behind env flag | `main.py` | ✅ Exception handler returns full detail only when `DEBUG=1` |
| 3.7 | Replace hardcoded cascade invalidation field list | `utils/status_tracker.py` | ✅ `_TRANSCRIPT_DERIVED_FIELDS` tuple + loop; add fields there to include in cascade |

---

### Tier 4 — Low-priority cleanup

| # | Status | What | Where | Note |
|---|--------|------|--------|------|
| 4.1 | ✅ Done | Convert `title_approval_status` bare string to an Enum | `models.py` | `TitleApprovalStatus` enum added; `api/files.py` and `utils/status_tracker.py` updated to use it |
| 4.2 | ✅ Done | Move hardcoded Whisper server port `8090` to setting | `services/batch_manager.py` | `batch.whisper_server_port` added to DEFAULT_SETTINGS |
| 4.3 | ✅ Done | Move hardcoded consecutive failure limit `3` to setting | `services/batch_manager.py` | `batch.max_consecutive_failures` added to DEFAULT_SETTINGS |
| 4.4 | ✅ Done | Add error handling to `broadcast()` | `services/batch_manager.py` | Was already implemented — logs warning on timeout, removes dead clients on exception |
| 4.5 | ✅ Done | Replace VLM detection via exception message string | `services/mlx_cache.py` | String check removed; any text-only load failure now falls back to VLM loader unconditionally |
| 4.6 | ✅ Done | Remove cosmetic key reordering in `save_file_status` | `utils/status_tracker.py` | Removed `desired_order` block; JSON dumped directly |
| 4.7 | ✅ Done | Normalise the two Whisper JSON output formats (A + B) | `api/files.py` (`get_file_timeline`) | Dual-parser replaced; endpoint now reads `word_timings.json` (already normalised by transcription service) |
| 4.8 | ✅ Done | Remove dead estimated-time string for conversation mode | `api/transcribe.py` | Dead branch removed; solo always returns `"5-15 minutes"` |
| 4.9 | ✅ Done | Make server port configurable | `main.py` | `server.port` added to DEFAULT_SETTINGS (default `8000`); `main.py` reads it at startup |
| 4.10 | ✅ Done | Make CORS origins configurable | `main.py` | `server.cors_origins` added to DEFAULT_SETTINGS; `main.py` reads it with hardcoded list as fallback |
| 4.11 | ✅ Done | Fix post-generation timeout enforcement | `services/mlx_runner.py` | Generation runs in a daemon thread; `thread.join(timeout)` enforces the deadline at the boundary — caller gets `TimeoutError` promptly |
| 4.12 | ✅ Done | Remove tag generation padding heuristic | `services/enhancement.py` | Keyword-scan padding removed; model now returns however many tags it found (up to `max_old`) |

