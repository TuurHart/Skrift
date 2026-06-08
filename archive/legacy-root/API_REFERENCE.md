# Skrift API Reference

> Every endpoint documented with method, path, request, response, errors, and SSE behavior.
> Each section is self-contained and copy-pasteable into a frontend task brief.

**Base URL**: `http://localhost:8000`
**API Docs (Swagger)**: `http://localhost:8000/docs`
**CORS**: Electron (`file://`), Vite dev server (`http://localhost:3000`)

---

## Summary Table

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | Root ping |
| `GET` | `/health` | Lightweight health check |
| `GET` | `/api/system/health` | Full system health with modules + file stats |
| `GET` | `/api/system/resources` | Live CPU / RAM / temp / disk |
| `GET` | `/api/system/status` | Current processing queue status |
| `POST` | `/api/files/upload` | Upload audio files or Apple Notes folders |
| `GET` | `/api/files` | List all pipeline files |
| `GET` | `/api/files/{file_id}` | Get single file |
| `DELETE` | `/api/files/{file_id}` | Delete file + all data |
| `GET` | `/api/files/{file_id}/status` | Poll file status |
| `PUT` | `/api/files/{file_id}/transcript` | Edit transcript text |
| `PUT` | `/api/files/{file_id}/sanitised` | Edit sanitised text |
| `POST` | `/api/files/{file_id}/sanitise/cancel` | Reset sanitise step to pending |
| `POST` | `/api/files/{file_id}/reset` | Full pipeline reset (preserves transcript) |
| `POST` | `/api/files/{file_id}/title/approve` | Mark AI title accepted |
| `POST` | `/api/files/{file_id}/title/decline` | Mark AI title declined |
| `GET` | `/api/files/{file_id}/content/{content_type}` | Get text content by type |
| `GET` | `/api/files/{file_id}/audio/{which}` | Stream audio (byte-range aware) |
| `GET` | `/api/files/{file_id}/srt` | Get SRT subtitle file |
| `GET` | `/api/files/{file_id}/word_timings` | Per-word timing JSON |
| `GET` | `/api/files/{file_id}/timeline` | Word-level timeline tokens |
| `POST` | `/api/process/transcribe/{file_id}` | Start transcription |
| `GET` | `/api/process/{file_id}/status` | Get processing status |
| `POST` | `/api/process/{file_id}/cancel` | Cancel / reset all processing steps |
| `POST` | `/api/process/sanitise/{file_id}` | Run sanitisation |
| `POST` | `/api/process/sanitise/{file_id}/resolve` | Resolve alias disambiguation |
| `POST` | `/api/process/enhance/test` | Test selected MLX model |
| `POST` | `/api/process/enhance/chat-template` | Save/clear chat template override |
| `GET` | `/api/process/enhance/models/selected/chat-template` | Get chat template for selected model |
| `GET` | `/api/process/enhance/models` | List MLX models |
| `POST` | `/api/process/enhance/models/upload` | Upload model file |
| `POST` | `/api/process/enhance/models/select` | Select active model |
| `DELETE` | `/api/process/enhance/models/{filename}` | Delete model file |
| `GET` | `/api/process/enhance/stream/{file_id}` | SSE — stream enhancement tokens |
| `GET` | `/api/process/enhance/input/{file_id}` | Preview LLM input text |
| `POST` | `/api/process/enhance/{file_id}` | Non-streaming enhancement |
| `POST` | `/api/process/enhance/title/{file_id}` | Set enhanced title |
| `POST` | `/api/process/enhance/copyedit/{file_id}` | Set copy-edited body |
| `POST` | `/api/process/enhance/summary/{file_id}` | Set summary |
| `POST` | `/api/process/enhance/tags/{file_id}` | Set approved tags |
| `GET` | `/api/process/enhance/tags/whitelist` | Get tag whitelist |
| `POST` | `/api/process/enhance/tags/whitelist/refresh` | Rebuild tag whitelist from vault |
| `POST` | `/api/process/enhance/tags/generate/{file_id}` | Generate tag suggestions via MLX |
| `POST` | `/api/process/enhance/compile/{file_id}` | Compile Obsidian markdown |
| `GET` | `/api/process/export/compiled/{file_id}` | Get compiled markdown |
| `PUT` | `/api/process/export/compiled/{file_id}` | Save edits to status.json only |
| `POST` | `/api/process/export/compiled/{file_id}` | Save + optionally export to vault |
| `POST` | `/api/batch/transcribe/start` | Start transcription batch |
| `POST` | `/api/batch/enhance/start` | Start enhancement batch |
| `GET` | `/api/batch/current` | Get active batch |
| `GET` | `/api/batch/{batch_id}/status` | Get specific batch status |
| `POST` | `/api/batch/{batch_id}/cancel` | Cancel active batch |
| `DELETE` | `/api/batch/{batch_id}` | Delete completed/cancelled/failed batch |
| `GET` | `/api/batch/enhance/stream` | SSE — stream batch enhancement output |
| `GET` | `/api/config` | Get all config |
| `POST` | `/api/config/update` | Update single config key |
| `POST` | `/api/config/reset` | Reset config to defaults |
| `GET` | `/api/config/{key}` | Get single config key |
| `GET` | `/api/config/folders/input` | Get input folder |
| `GET` | `/api/config/folders/output` | Get output folder |
| `POST` | `/api/config/folders/input` | Set input folder |
| `POST` | `/api/config/folders/output` | Set output folder |
| `GET` | `/api/config/sanitisation` | Get sanitisation settings |
| `POST` | `/api/config/sanitisation` | Update sanitisation settings |
| `GET` | `/api/config/names` | Get people/aliases mapping |
| `POST` | `/api/config/names` | Update people/aliases mapping |
| `GET` | `/api/config/transcription/modules` | Get transcription module availability |

---

## Table of Contents

1. [Health & System](#health--system)
2. [File Management](#file-management)
3. [Processing: Status & Cancel](#processing-status--cancel)
4. [Transcription](#transcription)
5. [Sanitisation](#sanitisation)
6. [Enhancement](#enhancement)
7. [Export](#export)
8. [Batch Processing](#batch-processing)
9. [Configuration](#configuration)
10. [Data Model: PipelineFile](#data-model-pipelinefile)
11. [Error Handling](#error-handling)

---

## Health & System

---

### `GET /`

Root ping — confirms server is running.

**Response 200**:
```json
{ "message": "Audio Transcription Pipeline API", "status": "running", "version": "1.0.0" }
```

---

### `GET /health`

Lightweight health check. Returns basic status + backend path info. Does **not** include resource metrics or transcription module checks.

**Response 200**:
```json
{
  "status": "healthy",
  "backend_path": "/path/to/backend",
  "python_version": "3.11.0 ...",
  "available_endpoints": ["/api/files/*", "/api/process/*", "..."]
}
```

---

### `GET /api/system/health`

Full health check with resource metrics, transcription module availability, and file statistics.

**Response 200**:
```json
{
  "status": "healthy",
  "timestamp": 1710333845.123,
  "uptime_hours": 2.5,
  "resources": {
    "cpuUsage": 45.2,
    "ramUsed": 8.5,
    "ramTotal": 24.0,
    "coreTemp": 65.5,
    "diskUsed": 35.0
  },
  "processing": {
    "processing": false,
    "currentFile": null,
    "currentStep": null,
    "queueLength": 0
  },
  "transcription_modules": {
    "parakeet": {
      "available": true,
      "engine": "parakeet-mlx"
    }
  },
  "file_statistics": {
    "total_files": 5,
    "processing_files": 0,
    "completed_files": 3,
    "error_files": 0
  },
  "python_version": "3.11.0",
  "platform": "posix"
}
```

**Error response** (if health check itself throws):
```json
{ "status": "error", "message": "...", "timestamp": null }
```

---

### `GET /api/system/resources`

Current system resource usage.

**Response 200**:
```json
{
  "cpuUsage": 45.2,
  "ramUsed": 8.5,
  "ramTotal": 24.0,
  "coreTemp": 65.5,
  "diskUsed": 35.0
}
```

`coreTemp` and `diskUsed` are `null` when unavailable. Falls back to zeroed defaults on any psutil error.

---

### `GET /api/system/status`

Current processing queue status.

**Response 200**:
```json
{
  "processing": true,
  "currentFile": "Voice Memo.m4a",
  "currentStep": "transcribing",
  "queueLength": 2
}
```

`currentStep` values: `"transcribing"` | `"sanitizing"` | `"enhancing"` | `"exporting"` | `null`

---

## File Management

---

### `POST /api/files/upload`

Upload audio files or Apple Notes export folders. Accepts either or both in a single request.

**Request**: `multipart/form-data`

| Field | Type | Required | Description |
|---|---|---|---|
| `files` | `File[]` | No | Audio files (`.m4a`, `.wav`, `.mp3`) or `.md` Apple Notes files |
| `conversationMode` | `boolean` | No | Default `false`. Applies to audio uploads only. |
| `note_folder_paths` | `string` | No | JSON-encoded array of absolute folder paths (for Electron folder drops of Apple Notes exports) |

Supported audio formats are configured via `audio.supported_input_formats` (default: `.m4a`, `.wav`, `.mp3`). `.md` files are always accepted and treated as Apple Notes imports.

For `note_folder_paths`, each folder must contain at least one `.md` file. An `Attachments/` sub-folder is copied automatically if present.

**Response 200**:
```json
{
  "success": true,
  "files": [ /* array of PipelineFile */ ],
  "message": "Successfully uploaded 2 file(s)",
  "errors": ["Unsupported file format: notes.txt (.txt)"]
}
```

`errors` is `null` when empty. If **all** uploads fail, returns `400` instead.

**Errors**: `400` no files provided / all uploads failed · `500` server error per file (reported in `errors` array)

---

### `GET /api/files`

List all pipeline files.

**Response 200**: Array of `PipelineFile` objects (see [Data Model](#data-model-pipelinefile)).

---

### `GET /api/files/{file_id}`

Get a single pipeline file by ID.

**Response 200**: `PipelineFile`

**Errors**: `404` not found

---

### `DELETE /api/files/{file_id}`

Delete a file and all associated data (folder, audio, status.json, outputs).

**Response 200**:
```json
{ "success": true, "message": "Successfully deleted Voice Memo.m4a" }
```

**Errors**: `404` not found · `500` deletion failed

---

### `GET /api/files/{file_id}/status`

Get current state. Poll this to track async operations (transcription, enhancement).

**Response 200**: Full `PipelineFile` object.

**Errors**: `404` not found

---

### `PUT /api/files/{file_id}/transcript`

Manually edit transcript text.

**Request**:
```json
{ "transcript": "Updated transcript text..." }
```

**Response 200**:
```json
{ "success": true, "message": "Successfully updated transcript for Voice Memo.m4a", "file": { /* PipelineFile */ } }
```

**Errors**: `400` missing `transcript` field · `404` not found · `500` save failed

---

### `PUT /api/files/{file_id}/sanitised`

Update sanitised text without touching the original transcript.

**Request**:
```json
{ "sanitised": "Sanitised text with [[Name]] links..." }
```

**Response 200**:
```json
{ "success": true, "message": "Successfully updated sanitised text for Voice Memo.m4a", "file": { /* PipelineFile */ } }
```

**Errors**: `400` missing `sanitised` field · `404` not found · `500` save failed

---

### `POST /api/files/{file_id}/sanitise/cancel`

Reset the sanitise step to `pending` and clear sanitised text. Does not affect other steps. Use when the user dismisses the disambiguation modal.

**Response 200**:
```json
{ "success": true, "message": "Sanitise step reset to pending" }
```

**Errors**: `404` not found · `500` reset failed

---

### `POST /api/files/{file_id}/reset`

Full pipeline reset. Clears all downstream content (sanitised, enhanced fields, tags, compiled text, exported). Preserves transcript if transcription was already done and marks `steps.transcribe` as `done` again.

**Response 200**:
```json
{ "success": true, "message": "Successfully reset Voice Memo.m4a", "file": { /* PipelineFile */ } }
```

**Errors**: `404` not found · `500` reset failed

---

### `POST /api/files/{file_id}/title/approve`

Mark AI-generated title as accepted. Sets `title_approval_status` to `"accepted"` and immediately triggers a recompile so `compiled_text` in `status.json` reflects the approved title.

**Response 200**:
```json
{ "success": true, "message": "Title approved", "title": "My Meeting Notes" }
```

**Errors**: `404` not found · `400` no AI-generated title available

---

### `POST /api/files/{file_id}/title/decline`

Mark AI-generated title as declined. Sets `title_approval_status` to `"declined"`.

**Response 200**:
```json
{ "success": true, "message": "Title declined" }
```

**Errors**: `404` not found · `400` no AI-generated title available

---

### `GET /api/files/{file_id}/content/{content_type}`

Get text content for a file.

**Path param** `content_type`: `transcript` | `sanitised` | `exported` | `wts`

- `wts` — serves the raw `.wts` file produced by Whisper (path from `audioMetadata.wts_path` or `<stem>.wts` fallback)

**Response 200**:
```json
{ "content": "Full text...", "type": "transcript" }
```

**Errors**: `400` invalid content type · `404` file not found or content not yet available · `500` read failed

---

### `GET /api/files/{file_id}/audio/{which}`

Stream audio. Supports byte-range requests for scrubbing.

**Path param** `which`: `original` | `processed`

- `original` — the uploaded `.m4a` / `.wav` / `.mp3`
- `processed` — `processed.wav` or `*_processed.wav` artifact (produced by transcription preprocessing)

**Response 200/206**: Binary audio stream. Respects `Range: bytes=start-end` header. Returns `206 Partial Content` for range requests.

Headers always include `Accept-Ranges: bytes`, `Cache-Control: no-store`.

**Errors**: `400` invalid `which` value · `404` file or audio not found

---

### `GET /api/files/{file_id}/srt`

Return on-disk SRT subtitle file (written by Whisper CLI `-osrt` flag). No synthesis is performed.

**Response 200**: `text/plain` SRT content.

**Errors**: `404` file not found or no SRT available · `500` read failed

---

### `GET /api/files/{file_id}/word_timings`

Per-word timing JSON for the transcript editor. Returns `word_timings.json` from disk if present; otherwise synthesizes it from the timeline and writes it to disk for future calls.

**Response 200**:
```json
{
  "version": "1",
  "audio": { "processed_wav": "processed.wav", "duration_sec": 134.5 },
  "dtw_model": null,
  "segments": [
    {
      "idx": 0,
      "start": 0.1,
      "end": 134.0,
      "words": [
        { "token_id": 0, "word": "Hello", "start": 0.1, "end": 0.5 }
      ]
    }
  ]
}
```

**Errors**: `404` file not found / no tokens available / synthesis yielded nothing · `500` read or parse failed

---

### `GET /api/files/{file_id}/timeline`

Word-level timeline. Reads from `word_timings.json` (path from `audioMetadata.word_timings_path` or `word_timings.json` fallback) and normalises to a flat token list.

**Response 200**:
```json
{
  "src": "word_timings",
  "tokens": [
    { "text": "Hello", "start": 0.1, "end": 0.5 },
    { "text": "world", "start": 0.6, "end": 1.0 }
  ]
}
```

**Errors**: `404` file not found / no timing file / no tokens found · `500` parse failed

---

## Processing: Status & Cancel

These generic endpoints live under `/api/process` and apply across all pipeline steps.

---

### `GET /api/process/{file_id}/status`

Get current processing status. Identical to `GET /api/files/{file_id}/status` — use either for polling.

**Response 200**: Full `PipelineFile` object.

**Errors**: `404` not found

---

### `POST /api/process/{file_id}/cancel`

Cancel any ongoing processing. Resets all `processing` or `error` steps back to `pending`. Attempts to kill a running Whisper subprocess. Detects stuck processes (no activity for 5+ minutes) and notes it in the response message. Clears `error`, `errorDetails`, `progress`, `progressMessage`, and `lastActivityAt`.

**Response 200**:
```json
{ "success": true, "message": "Cancelled transcription, sanitisation", "file": { /* PipelineFile */ } }
```

**Errors**: `404` not found

---

## Transcription

---

### `POST /api/process/transcribe/{file_id}`

Start transcription. Runs asynchronously in a background thread — poll `/api/files/{file_id}/status` for progress.

**Important**: Conversation mode (speaker diarization) is not currently supported. Passing `conversationMode: true` returns `400` immediately and resets the step to `pending`.

**Request** (optional body):
```json
{ "conversationMode": false }
```

If omitted, the file's `conversationMode` setting is used.

**Response 200** (started):
```json
{
  "status": "started",
  "message": "Solo transcription started",
  "estimatedTime": "5-15 minutes",
  "file": { /* PipelineFile */ }
}
```

**Response 200** (already running):
```json
{ "status": "already_processing", "message": "Transcription already in progress", "file": { /* PipelineFile */ } }
```

**Response 200** (already done):
```json
{ "status": "already_done", "message": "Transcription already completed", "file": { /* PipelineFile */ } }
```

**Errors**: `400` conversation mode requested (not supported) · `404` not found · `500` failed to start

---

## Sanitisation

---

### `POST /api/process/sanitise/{file_id}`

Run name-linking sanitisation on the transcript. Links the **first mention** of each known alias to `[[Canonical Name]]` (case-insensitive, whole-word, possessives preserved). Removes filler words per config.

**Request**: No body.

**Response 200** (success):
```json
{ "status": "done", "message": "Sanitise completed", "file": { /* PipelineFile */ } }
```

**Response 200** (already processing):
```json
{ "status": "already_processing", "message": "Sanitise already in progress", "file": { /* PipelineFile */ } }
```

**⚠️ Response 409** (disambiguation required — must handle in frontend):
```json
{
  "status": "needs_disambiguation",
  "ambiguities": [
    {
      "alias": "Alex",
      "occurrences": [
        { "offset": 145, "context": "...talked to Alex about..." }
      ],
      "candidates": [
        { "id": "[[Alex Johnson]]", "canonical": "[[Alex Johnson]]", "aliases": ["Alex", "AJ"] },
        { "id": "[[Alexandra Smith]]", "canonical": "[[Alexandra Smith]]", "aliases": ["Alex", "Lex"] }
      ]
    }
  ],
  "session_id": "sess_abc123"
}
```

When a 409 is received, show a disambiguation modal. The user picks which candidate each ambiguous alias refers to, then POST to `/api/process/sanitise/{file_id}/resolve`.

**Errors**: `400` transcription not complete or no transcript · `404` not found · `500` sanitisation failed

---

### `POST /api/process/sanitise/{file_id}/resolve`

Resolve alias disambiguation after a 409. Applies user decisions and completes sanitisation.

**Request**:
```json
{
  "session_id": "sess_abc123",
  "decisions": [
    {
      "alias": "Alex",
      "offset": 145,
      "person_id": "[[Alex Johnson]]",
      "apply_to_remaining": true
    }
  ]
}
```

`person_id` must match a `candidate.id` from the 409 response. `apply_to_remaining: true` applies the same mapping to all remaining occurrences of that alias.

**Response 200**:
```json
{ "status": "done", "message": "Sanitise completed", "file": { /* PipelineFile */ } }
```

**Errors**: `400` transcription not complete / no transcript · `404` not found · `500` resolution failed

---

## Enhancement

Enhancement uses a local MLX model invoked through the `mlx-env` venv. Steps are gated in order: **Title → Copy Edit → Summary → Tags**. Each setter auto-compiles when all four parts are present.

---

### `POST /api/process/enhance/test`

Validate the currently selected MLX model with a short test generation.

**Request**: No body.

**Response 200**:
```json
{
  "success": true,
  "model_path": "/path/to/model",
  "output": "Sample generated text...",
  "tokens_generated": 45,
  "elapsed_seconds": 2.3
}
```

**Errors**: `400` no model selected · `500` MLX not available or generation failed

---

### `POST /api/process/enhance/chat-template`

Save or clear a custom Jinja2 chat template override for the currently selected model. The override is keyed by the model's absolute path and stored in `enhancement.mlx.chat_template_overrides`.

**Request**:
```json
{ "template": "{% for message in messages %}{{ message.content }}{% endfor %}" }
```

Pass `null` to clear the override for the current model:
```json
{ "template": null }
```

**Response 200**: `{ "success": true }`

**Response 200** (no model selected): `{ "success": false, "error": "No model selected" }`

---

### `GET /api/process/enhance/models/selected/chat-template`

Get the chat template for the currently selected model, including any saved override.

**Response 200**:
```json
{
  "template": "{% for message in messages %}{{ message.content }}{% endfor %}",
  "override": null,
  "source": "tokenizer"
}
```

`source`: `"none"` (no template anywhere) | `"tokenizer"` (from `tokenizer_config.json`) | `"override"` (user-saved override takes effect)

When `source` is `"override"`, the `override` field contains the active template and `template` contains the underlying tokenizer value (or `null`).

---

### `GET /api/process/enhance/models`

List all MLX models in the configured models directory.

**Response 200**:
```json
{
  "models": [
    {
      "name": "llama-3.2-3b-instruct",
      "path": "/path/to/Skrift_dependencies/models/mlx/llama-3.2-3b-instruct",
      "size": 3500000000,
      "selected": true
    }
  ],
  "selected": "/path/to/Skrift_dependencies/models/mlx/llama-3.2-3b-instruct"
}
```

`size` is total bytes (recursing into model directories). `selected` is `null` when no model is active.

---

### `POST /api/process/enhance/models/upload`

Upload a new MLX model file to the models directory.

**Request**: `multipart/form-data` · `file`: model file (`.safetensors`, `.bin`, etc.)

**Response 200**:
```json
{ "success": true, "path": "/path/to/models/model.safetensors", "name": "model.safetensors" }
```

---

### `POST /api/process/enhance/models/select`

Select which MLX model to use for enhancement. Only paths inside the app's configured models directory are accepted.

**Request**: `multipart/form-data` · `path`: full absolute path to the model (file or directory)

**Response 200**:
```json
{ "success": true, "selected": "/path/to/model" }
```

**Errors**: `400` path not found or outside the models directory

---

### `DELETE /api/process/enhance/models/{filename}`

Delete a model file or directory by name. If it was the currently selected model, the selection is cleared.

**Response 200**: `{ "success": true }`

**Errors**: `404` not found · `500` deletion failed

---

### `GET /api/process/enhance/stream/{file_id}`

Stream enhancement output for a file via SSE. Uses `sanitised` text if available, otherwise falls back to `transcript`. Persists the full result to `status.json` after generation completes.

Returns `409` if a stream is already active for this file.

**Query params**:

| Param | Type | Required | Description |
|---|---|---|---|
| `prompt` | `string` | No | Custom instruction appended to the system prompt |

**Response 200**: `text/event-stream`

**SSE Events**:

| Event | Data shape | Notes |
|---|---|---|
| `start` | `{"status": "generating", "step": "enhancement"}` | Generation begins |
| `token` | Raw text string (not JSON) | One or more characters per event |
| `done` | `{"status": "done", "tokens": 145, "elapsed_ms": 3200}` | Generation complete |
| `error` | `{"status": "error", "message": "MLX failed: ..."}` | Generation error |
| `heartbeat` | `.` (literal dot) | Sent every 2 s of inactivity to keep connection alive |

**Errors**: `400` no text available · `404` not found · `409` stream already active for this file

---

### `GET /api/process/enhance/input/{file_id}`

Preview exactly the text that would be sent to the LLM. Source selection mirrors the streaming endpoint.

**Response 200**:
```json
{ "source": "sanitised", "length": 2456, "input_text": "Full text here..." }
```

`source`: `"sanitised"` (preferred) | `"transcript"`

**Errors**: `404` not found

---

### `POST /api/process/enhance/{file_id}`

Non-streaming (synchronous) enhancement. Marks the `enhance` step as `processing`, calls the MLX model, then saves the result and marks `done`.

**Request** (optional):
```json
{ "enhancementType": "polish", "prompt": "Custom instructions..." }
```

**Response 200**:
```json
{ "status": "done", "message": "Enhancement (polish) completed", "file": { /* PipelineFile */ } }
```

**Errors**: `400` sanitisation not complete / no input text / MLX error · `404` not found · `500` failed

---

### `POST /api/process/enhance/title/{file_id}`

Set the enhanced title. Auto-compiles if all four parts (title, copyedit, summary, tags) are now present.

**Request**: `{ "title": "My Meeting Notes" }`

**Response 200**: `{ "success": true, "file": { /* PipelineFile */ } }`

**Errors**: `400` missing or empty `title` · `404` not found

---

### `POST /api/process/enhance/copyedit/{file_id}`

Set the copy-edited body text. Auto-compiles if all four parts are present.

**Request**: `{ "text": "Polished and edited text..." }`

**Response 200**: `{ "success": true, "file": { /* PipelineFile */ } }`

**Errors**: `400` missing or empty `text` · `404` not found

---

### `POST /api/process/enhance/summary/{file_id}`

Set the one-sentence summary. Auto-compiles if all four parts are present.

**Request**: `{ "summary": "A concise summary." }`

**Response 200**: `{ "success": true, "file": { /* PipelineFile */ } }`

**Errors**: `404` not found

---

### `POST /api/process/enhance/tags/{file_id}`

Set approved tags. Tags are stripped and deduplicated. Auto-compiles if all four parts are present.

**Request**: `{ "tags": ["project", "meeting", "action-items"] }`

**Response 200**:
```json
{ "success": true, "tags": ["project", "meeting", "action-items"], "file": { /* PipelineFile */ } }
```

**Errors**: `400` `tags` is not a list · `404` not found

---

### `GET /api/process/enhance/tags/whitelist`

Return the cached tag whitelist. Does **not** rescan the vault — use `/refresh` for that.

**Response 200**:
```json
{ "version": 1, "count": 127, "tags": ["action-items", "decision", "meeting"] }
```

**Errors**: `500` whitelist load failed

---

### `POST /api/process/enhance/tags/whitelist/refresh`

Scan the configured Obsidian vault and rebuild the tag whitelist. Reads YAML frontmatter `tags:` fields only. Excludes numeric-only tags. Writes result to `enhancement.obsidian.tags_whitelist_path`.

**Request**: No body.

**Response 200**:
```json
{ "success": true, "count": 147, "path": "/path/to/vault/.tags.json", "scanned_files": 523 }
```

**Errors**: `400` vault path not configured or not found · `500` write failed

---

### `POST /api/process/enhance/tags/generate/{file_id}`

Generate tag suggestions using the active MLX model. Results are stored in `tag_suggestions` on the `PipelineFile`. The user then selects from suggestions and POSTs to `POST /api/process/enhance/tags/{file_id}` to persist the final selection.

**Request**: No body (body is accepted but currently unused).

**Response 200**:
```json
{
  "success": true,
  "old": ["meeting", "decision"],
  "new": ["q1-planning", "revenue-forecast"],
  "raw": "[Raw model output with OLD_TAGS/NEW_TAGS sections]",
  "whitelist_count": 147,
  "used_max_old": 10,
  "used_max_new": 5
}
```

`old` — tags from the whitelist that fit the content.
`new` — suggested tags not in the whitelist.

**Errors**: `400` no text available / empty whitelist / no model selected · `404` file not found · `500` generation failed

---

### `POST /api/process/enhance/compile/{file_id}`

Manually trigger compilation of the final Obsidian-ready markdown. Also called automatically by setter endpoints when all four enhancement parts are present.

Writes `compiled.md` to the file's output folder and saves `compiled_text` to `status.json`.

**Compiled output format**:
```markdown
---
title: My Meeting Notes
date: 2025-03-12
lastTouched:
firstMentioned:
author: Tiuri
source: Voice-memo
location:
tags:
  - meeting
  - decision
confidence:
summary: A concise summary.
---

Polished and edited body text...
```

**Response 200**:
```json
{ "success": true, "compiled_path": "/path/to/output/compiled.md" }
```

**Errors**: `404` file not found · `500` compilation failed

---

## Export

---

### `GET /api/process/export/compiled/{file_id}`

Get the current compiled markdown content.

Resolution order for the active `.md` file in the output folder:
1. `compiled.md` if present
2. If exactly one `*.md` exists, use it
3. Otherwise use the most recently modified `*.md`

**Response 200**:
```json
{
  "path": "/path/to/compiled.md",
  "title": "My Meeting Notes",
  "content": "Full markdown with frontmatter...",
  "enhanced_title": "My Meeting Notes"
}
```

`enhanced_title` comes from `status.json` (may differ from the YAML frontmatter title if not yet compiled).

**Errors**: `404` no `.md` file found · `500` read failed

---

### `PUT /api/process/export/compiled/{file_id}`

Save compiled text edits to `status.json` (`compiled_text` field) **only** — does not write any file to disk. Used for debounced auto-save while the user is editing.

**Request**: `{ "content": "Updated markdown..." }`

**Response 200**: `{ "success": true }`

**Errors**: `404` not found

---

### `POST /api/process/export/compiled/{file_id}`

Save compiled markdown and optionally export to Obsidian vault.

**Request**:
```json
{
  "content": "Updated markdown...",
  "export_to_vault": true,
  "vault_path": "/path/to/vault",
  "include_audio": true
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `content` | `string` | Yes | Full markdown content to save |
| `export_to_vault` | `boolean` | No | Default `false`. If `true`, rename + copy to vault. |
| `vault_path` | `string` | No | Override vault destination. Falls back to `export.note_folder` setting. |
| `include_audio` | `boolean` | No | Default `false`. Copy original audio to `export.audio_folder` and insert Obsidian embed. |

**Behaviour**:
- **Plain save** (`export_to_vault: false`) — writes to the active `.md` file (resolved by same logic as GET).
- **Save + export** (`export_to_vault: true`) — renames the active `.md` to `<YAML title>.md`, deletes any other `.md` siblings to prevent duplicates, then copies to vault.
- **With audio** (`include_audio: true`) — copies the original audio file to the configured `export.audio_folder` and prepends an Obsidian `![[filename.m4a]]` embed to the exported note.

`compiled_text` in `status.json` is always synced to the saved content on success.

**Response 200** (plain save):
```json
{ "success": true, "path": "/path/to/output/compiled.md" }
```

**Response 200** (vault export):
```json
{
  "success": true,
  "exported_path": "/path/to/output/My Meeting Notes.md",
  "vault_exported_path": "/path/to/vault/My Meeting Notes.md",
  "audio_exported_path": "/path/to/vault/audio/Voice Memo.m4a",
  "audio_filename": "Voice Memo.m4a"
}
```

`audio_exported_path` and `audio_filename` are omitted when `include_audio` is `false` or audio copy was skipped.

**Errors**: `400` missing/invalid content or title · `404` not found · `500` export failed

---

## Batch Processing

Only one batch can be active at a time. Batches are persisted to `backend/data/batch_state.json`.

---

### `POST /api/batch/transcribe/start`

Start a transcription batch. Only files that have not yet been transcribed (`steps.transcribe != "done"`) are included; already-transcribed files in the request are silently skipped. Files are processed sequentially.

**Request**:
```json
{ "file_ids": ["550e8400-...", "660e8400-..."] }
```

**Response 200**:
```json
{
  "success": true,
  "message": "Batch started with 5 files",
  "batch": {
    "batch_id": "batch_550e8400e29b41d4a716446655440000",
    "status": "running",
    "type": "transcribe",
    "progress": { "total": 5, "completed": 0, "failed": 0, "current": 0, "percentage": 0 },
    "files": [
      { "file_id": "550e8400-...", "status": "pending", "error": null }
    ],
    "consecutive_failures": 0,
    "created_at": "2025-03-12T10:30:00Z",
    "updated_at": "2025-03-12T10:30:00Z"
  }
}
```

**Errors**: `400` no file IDs / all files already transcribed · `404` file not found · `409` a batch is already running · `500` start failed

---

### `POST /api/batch/enhance/start`

Start an enhancement batch. Files run through the Title → Copy Edit → Summary → Tags pipeline, skipping already-completed steps. A file is eligible if it has transcription done, has content to enhance (`sanitised` or `transcript`), and has at least one incomplete enhancement step.

**Request**:
```json
{ "file_ids": ["550e8400-...", "..."] }
```

**Eligibility check** (per file — returns `400` if check fails for any file):
- `steps.transcribe` must be `"done"`
- `sanitised` or `transcript` must be non-empty
- At least one of `enhanced_title`, `enhanced_copyedit`, `enhanced_summary`, or tags (either `tag_suggestions` or `enhanced_tags`) must be missing/empty

**Response 200**: Same structure as transcription batch response.

**Errors**: `400` no file IDs / file not transcribed / no content / all steps complete · `404` not found · `409` batch already running · `500` failed

---

### `GET /api/batch/current`

Get the currently active (or most recently completed) batch.

**Response 200** (active):
```json
{
  "active": true,
  "batch": {
    "batch_id": "batch_550e8400...",
    "status": "running",
    "type": "transcribe",
    "progress": { "total": 5, "completed": 2, "failed": 0, "current": 2, "percentage": 40 },
    "files": [ /* per-file statuses */ ],
    "current_file_id": "770e8400-...",
    "consecutive_failures": 0,
    "created_at": "2025-03-12T10:30:00Z",
    "updated_at": "2025-03-12T10:35:00Z"
  }
}
```

`active` is `true` only when `status == "running"`.

**Response 200** (none): `{ "active": false, "batch": null }`

---

### `GET /api/batch/{batch_id}/status`

Get status of a specific batch by ID. Only the single persisted batch is tracked; returns `404` if the ID doesn't match.

**Response 200**:
```json
{
  "batch_id": "batch_550e8400...",
  "status": "running",
  "type": "transcribe",
  "progress": { "total": 5, "completed": 2, "failed": 0, "current": 2, "percentage": 40 },
  "files": [ /* per-file statuses */ ],
  "consecutive_failures": 0,
  "created_at": "2025-03-12T10:30:00Z",
  "updated_at": "2025-03-12T10:35:00Z"
}
```

Per-file status values: `"pending"` | `"completed"` | `"skipped"` | `"failed"`

**Errors**: `404` not found

---

### `POST /api/batch/{batch_id}/cancel`

Cancel an active batch. Stops queuing new files but does not interrupt the file currently being processed.

**Response 200**:
```json
{ "success": true, "message": "Batch cancelled successfully", "batch_id": "...", "status": "cancelled" }
```

**Errors**: `400` batch is not running · `404` not found · `500` cancellation failed

---

### `DELETE /api/batch/{batch_id}`

Delete a batch record. Only allowed for completed, cancelled, or failed batches. Running batches must be cancelled first.

**Response 200**:
```json
{ "success": true, "message": "Batch deleted successfully", "batch_id": "..." }
```

**Errors**: `400` batch is running · `404` not found · `500` deletion failed

---

### `GET /api/batch/enhance/stream`

Stream live enhancement batch output via SSE. Each connected client gets its own queue (max 100 events). Heartbeats fire every 2 s of inactivity. Clients are auto-cleaned on disconnect.

**Response 200**: `text/event-stream`

**SSE Events**:

| Event | Data shape | Notes |
|---|---|---|
| `connected` | `{}` | Sent immediately on connection |
| `start` | `{"file_id": "550e8400...", "step": "title"}` | A step begins for a file |
| `token` | Raw text string (not JSON) | LLM output chunk |
| `done` | `{"file_id": "550e8400...", "step": "title"}` | Step completed successfully |
| `error` | `{"file_id": "550e8400...", "step": "title", "error": "MLX timeout"}` | Step failed |
| `heartbeat` | `.` (literal dot) | Keep-alive, every 2 s of inactivity |

---

## Configuration

---

### `GET /api/config`

Get all configuration settings.

**Response 200**:
```json
{
  "success": true,
  "message": "Configuration retrieved successfully",
  "config": {
    "transcription": {
      "solo_model": "base.en",
      "conversation_model": "base",
      "use_metal_acceleration": true,
      "use_coreml": false,
      "use_vad": true
    },
    "sanitisation": {
      "remove_filler_words": true,
      "link_names": true
    },
    "enhancement": {
      "mlx": {
        "model_path": "/path/to/model",
        "temperature": 0.6,
        "timeout_seconds": 40,
        "chat_template_overrides": {}
      },
      "obsidian": {
        "vault_path": "/path/to/vault",
        "tags_whitelist_path": "/path/to/vault/.tags.json"
      },
      "tags": { "max_old": 10, "max_new": 5 }
    },
    "export": {
      "author": "Tiuri",
      "note_folder": "/path/to/vault/Notes",
      "audio_folder": "/path/to/vault/audio"
    },
    "dependencies_folder": "/path/to/Skrift_dependencies",
    "input_folder": "/path/to/input",
    "output_folder": "/path/to/output"
  }
}
```

**Errors**: `500` failed to load config

---

### `POST /api/config/update`

Update a single config value using dot-notation.

**Request**: `{ "key": "enhancement.mlx.temperature", "value": 0.8 }`

**Response 200**:
```json
{ "success": true, "message": "Successfully updated enhancement.mlx.temperature", "config": { "enhancement.mlx.temperature": 0.8 } }
```

**Errors**: `500` update failed

---

### `POST /api/config/reset`

Reset all configuration to defaults by deleting `user_settings.json` and reloading.

**Response 200**: `{ "success": true, "message": "Configuration reset to defaults", "config": { /* full default config */ } }`

**Errors**: `500` reset failed

---

### `GET /api/config/{key}`

Get a specific config value by dot-notation key. Example: `GET /api/config/transcription.solo_model`

**Note**: This route is a catch-all and must be declared **after** all other `/api/config/*` routes — it will match any path segment not covered by a more specific route.

**Response 200**: `{ "key": "transcription.solo_model", "value": "base.en" }`

**Errors**: `404` key not found · `500` lookup failed

---

### `GET /api/config/folders/input`

Get the current input folder path and its accessibility.

**Response 200**: `{ "path": "/path/to/input", "exists": true, "writable": true }`

**Errors**: `500` failed

---

### `GET /api/config/folders/output`

Get the current output folder path.

**Response 200**: `{ "path": "/Users/.../Voice Transcription Pipeline Audio Output", "exists": true, "writable": true }`

**Errors**: `500` failed

---

### `POST /api/config/folders/input`

Set the input folder path. Creates the folder if it does not exist.

**Request**: `{ "path": "/new/input/path" }`

**Response 200**: `{ "success": true, "message": "Input folder updated to /new/input/path", "config": { "input_folder": "/new/input/path" } }`

**Errors**: `400` path required / cannot create folder · `500` save failed

---

### `POST /api/config/folders/output`

Set the output folder path. Creates the folder if it does not exist.

**Request**: `{ "path": "/new/output/path" }`

**Response 200**: `{ "success": true, "message": "Output folder updated to /new/output/path", "config": { "output_folder": "/new/output/path" } }`

**Errors**: `400` path required / cannot create folder · `500` save failed

---

### `GET /api/config/sanitisation`

Get sanitisation settings. Returns the full `sanitisation` config object including filler word lists.

**Response 200** (example):
```json
{ "remove_filler_words": true, "link_names": true, "filler_words": ["uh", "um", "like", "you know"] }
```

**Errors**: `500` failed

---

### `POST /api/config/sanitisation`

Deep-merge a partial sanitisation settings object into the current config.

**Request**: `{ "remove_filler_words": false }`

**Response 200**: `{ "success": true, "message": "Sanitisation settings updated", "sanitisation": { /* merged result */ } }`

**Errors**: `500` failed

---

### `GET /api/config/names`

Get the people/aliases mapping used by sanitisation.

**Response 200**:
```json
{
  "people": [
    { "canonical": "[[Sebastiaan Paap]]", "aliases": ["Seb", "SP"], "short": "Seb" },
    { "canonical": "[[John Smith]]", "aliases": ["John", "JS"], "short": "John" }
  ]
}
```

Returns `{ "people": [] }` if no `names.json` exists.

**Errors**: `500` failed to load

---

### `POST /api/config/names`

Update the people/aliases mapping. The server normalises `canonical` to `[[Name]]` format, strips empty entries, and sorts alphabetically by canonical name (ignoring brackets).

**Request**:
```json
{
  "people": [
    { "canonical": "Sebastiaan Paap", "aliases": ["Seb", "SP"], "short": "Seb" }
  ]
}
```

**Response 200**:
```json
{
  "success": true,
  "message": "Names mapping saved",
  "data": {
    "people": [
      { "canonical": "[[Sebastiaan Paap]]", "aliases": ["Seb", "SP"], "short": "Seb" }
    ]
  }
}
```

**Errors**: `500` failed to save

---

### `GET /api/config/transcription/modules`

Get availability information for the Solo and Conversation transcription modules.

**Response 200**:
```json
{
  "modules": {
    "parakeet": {
      "available": true,
      "engine": "parakeet-mlx"
    }
  },
  "settings": {
    "parakeet_model": "mlx-community/parakeet-tdt-0.6b-v3"
  }
}
```

**Errors**: `500` failed

---

## Data Model: PipelineFile

Full structure returned by all file and processing endpoints.

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "filename": "Voice Memo.m4a",
  "path": "/Users/.../Voice Memo/original.m4a",
  "size": 2048000,
  "conversationMode": false,
  "steps": {
    "transcribe": "done",
    "sanitise": "done",
    "enhance": "processing",
    "export": "pending"
  },
  "uploadedAt": "2025-03-12T10:30:00Z",
  "lastModified": "2025-03-12T10:35:00Z",
  "lastActivityAt": "2025-03-12T10:34:30Z",
  "transcript": "Full raw transcript text...",
  "sanitised": "Sanitised text with [[Name]] links...",
  "exported": null,
  "enhanced_title": "My Meeting Notes",
  "title_approval_status": "accepted",
  "enhanced_copyedit": "Polished text...",
  "enhanced_summary": "A concise summary.",
  "enhanced_tags": ["meeting", "project"],
  "tag_suggestions": {
    "old": ["decision", "action-items"],
    "new": ["q1-planning"]
  },
  "source_type": "audio",
  "compiled_text": "Full markdown with frontmatter...",
  "include_audio_in_export": true,
  "error": null,
  "errorDetails": null,
  "processingTime": {
    "transcribe": 125.5,
    "sanitise": 0.2,
    "enhance": 3.4
  },
  "audioMetadata": {
    "original_format": ".m4a",
    "uploaded_size": 2048000,
    "duration": "00:02:14",
    "duration_seconds": 134,
    "conversation_mode": false,
    "note_title": null,
    "attachments": [],
    "json_path": null,
    "word_timings_path": "/path/to/output/word_timings.json",
    "processed_wav_path": "/path/to/output/processed.wav",
    "wts_path": null
  },
  "progress": 75,
  "progressMessage": "Enhancement in progress..."
}
```

**`steps.*` values**: `"pending"` | `"processing"` | `"done"` | `"error"` | `"skipped"`

**`title_approval_status` values**: `null` | `"pending"` | `"accepted"` | `"declined"`

**`source_type` values**: `"audio"` | `"note"` | `null`

**`audioMetadata` notes**:
- `duration` — `"HH:MM:SS"` string extracted via ffprobe at upload time
- `duration_seconds` — float equivalent
- `note_title` — populated for Apple Notes imports (`.md` source)
- `attachments` — array of `{ filename, mime }` for Apple Notes with attachments
- `word_timings_path`, `processed_wav_path`, `wts_path` — absolute paths written after transcription

---

## Error Handling

All error responses use the standard FastAPI shape:

```json
{ "detail": "Error message describing what went wrong" }
```

| Status | Meaning |
|---|---|
| `200` | Success |
| `206` | Partial content (byte-range audio streaming) |
| `400` | Invalid input, missing required fields, precondition not met |
| `404` | Resource not found |
| `409` | Conflict — disambiguation needed, stream already active, or batch already running |
| `500` | Server-side failure |

In `DEBUG=1` mode, `500` responses also include `type` (exception class name) and `path` (request URL).

---

## Timeouts & Limits

| Operation | Default |
|---|---|
| Solo transcription | 5–15 min (estimated) |
| Conversation transcription | Not supported |
| Enhancement (MLX) | 40 s (configurable via `enhancement.mlx.timeout_seconds`) |
| SSE heartbeat interval | 2 s |
| SSE batch queue size | 100 events per client |
| Audio duration extraction (ffprobe) | 10 s subprocess timeout |
| Stuck process detection (cancel) | 5 min of inactivity |
