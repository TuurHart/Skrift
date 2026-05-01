import type { PipelineFile, UploadResponse, SystemHealth } from './types/pipeline'

export const API_BASE = 'http://localhost:8000'

async function fetchJSON<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: options?.body instanceof FormData
      ? undefined
      : { 'Content-Type': 'application/json' },
    ...options,
  })
  if (!res.ok) {
    const text = await res.text().catch(() => '')
    const err = new Error(`${res.status}: ${text}`) as Error & { status: number; body: string }
    err.status = res.status
    err.body = text
    throw err
  }
  return res.json() as Promise<T>
}

// ── Types ──────────────────────────────────────────────────

export interface Ambiguity {
  alias: string
  occurrences: Array<{ offset: number; context: string }>
  candidates: Array<{ id: string; canonical: string; aliases: string[] }>
}

export interface SanitiseResponse {
  status: 'done' | 'needs_disambiguation' | 'already_processing'
  message?: string
  file?: PipelineFile
  ambiguities?: Ambiguity[]
  session_id?: string
}

// The backend returns flat per-occurrence objects; transform to the grouped
// Ambiguity[] that DisambiguationModal expects.
interface _BackendOccurrence {
  alias: string
  offset: number
  length: number
  context_before: string
  context_after: string
  candidates: Array<{ id: string; canonical: string; short: string }>
}

function groupOccurrences(flat: _BackendOccurrence[]): Ambiguity[] {
  const map = new Map<string, Ambiguity>()
  for (const occ of flat) {
    const key = occ.alias.toLowerCase()
    if (!map.has(key)) {
      map.set(key, {
        alias: occ.alias,
        occurrences: [],
        candidates: occ.candidates.map(c => ({ id: c.id, canonical: c.canonical, aliases: [] })),
      })
    }
    map.get(key)?.occurrences.push({
      offset: occ.offset,
      context: occ.context_before + occ.alias + occ.context_after,
    })
  }
  return Array.from(map.values())
}

export interface TagSuggestionResponse {
  success: boolean
  old: string[]
  new: string[]
  raw: string
}

export interface CompiledMarkdown {
  path: string
  title: string
  content: string
  enhanced_title: string
}

export interface Person {
  canonical: string
  aliases: string[]
  short: string
}

export interface MlxModel {
  name: string
  path: string
  size: string
  selected: boolean
  params?: string
  quant?: string
}

export interface DepsValidation {
  valid: boolean
  has_venv: boolean
  has_mlx_models: boolean
  mlx_model_names: string[]
  has_parakeet: boolean
  issues: string[]
  auto_selected_model?: string
}

export interface DepsZip {
  path: string
  name: string
  size_mb: number
}

export interface EnhancePrompt {
  id: string
  label: string
  tag: string
  tagColor: string
  desc: string
  instruction: string
}

export const DEFAULT_PROMPTS: EnhancePrompt[] = [
  { id: 'title', label: 'Generate Title', tag: 'title', tagColor: '#7c6bf5', desc: 'Extract or generate a title', instruction: 'Generate a short, descriptive title for this text (5\u201315 words). If the speaker explicitly names the topic, use their words. Match the primary language of the text. Return ONLY the title, nothing else.' },
  { id: 'copy_edit', label: 'Copy Edit', tag: 'copy-edit', tagColor: '#6366f1', desc: 'Fix spelling, grammar, readability', instruction: 'Clean up this transcript. The author may switch between English and Dutch mid-sentence \u2014 this is intentional, keep it exactly as-is.\n\nDo:\n- Remove filler words (um, uh, like, you know, so basically, I mean, yeah so).\n- Fix spelling and grammar.\n- Add punctuation and paragraph breaks at natural pauses.\n- Preserve [[double bracket links]] exactly.\n- When the speaker immediately rephrases the same thought (e.g. saying a sentence then saying it again slightly differently), collapse into the final version.\n- Remove false starts and repeated words from thinking out loud.\n\nDo not:\n- Rephrase, rewrite, or restructure sentences.\n- Translate anything between languages.\n- Add formality \u2014 it should still sound like the person speaking.\n- Add any preamble, heading, or explanation.\n\nOutput only the cleaned text.' },
  { id: 'summary', label: 'Summary', tag: 'summary', tagColor: '#a855f7', desc: '1\u20133 sentence summary', instruction: 'Summarize this in 1\u20133 sentences (30\u201360 words). Capture the main point and any decision or action item. If there are multiple topics, mention each briefly. Write in third person. Match the primary language of the text. Output only the summary.' },
]

// ── API ────────────────────────────────────────────────────

export const api = {
  // Files
  async getFiles(): Promise<PipelineFile[]> {
    return fetchJSON<PipelineFile[]>('/api/files')
  },
  async getFile(fileId: string): Promise<PipelineFile> {
    return fetchJSON<PipelineFile>(`/api/files/${fileId}`)
  },
  async getFileStatus(fileId: string): Promise<PipelineFile> {
    return fetchJSON<PipelineFile>(`/api/files/${fileId}/status`)
  },
  /** Poll until transcription finishes (done or error). Resolves with final status.
   *  Pass an AbortSignal to cancel polling when no longer needed. */
  async waitForTranscription(fileId: string, intervalMs = 2000, signal?: AbortSignal): Promise<PipelineFile> {
    // eslint-disable-next-line no-constant-condition
    while (true) {
      if (signal?.aborted) throw new DOMException('Polling aborted', 'AbortError')
      await new Promise(r => setTimeout(r, intervalMs))
      if (signal?.aborted) throw new DOMException('Polling aborted', 'AbortError')
      const f = await this.getFileStatus(fileId)
      if (f.steps.transcribe === 'done' || f.steps.transcribe === 'error') return f
    }
  },
  async uploadFiles(files: File[], conversationMode = false, folderPaths: string[] = []): Promise<UploadResponse> {
    const form = new FormData()
    for (const f of files) form.append('files', f)
    form.append('conversationMode', String(conversationMode))
    if (folderPaths.length > 0) {
      form.append('note_folder_paths', JSON.stringify(folderPaths))
    }
    const res = await fetch(`${API_BASE}/api/files/upload`, { method: 'POST', body: form })
    if (!res.ok) throw new Error(`${res.status}: ${await res.text().catch(() => '')}`)
    return res.json() as Promise<UploadResponse>
  },
  async deleteFile(fileId: string): Promise<void> {
    await fetchJSON<unknown>(`/api/files/${fileId}`, { method: 'DELETE' })
  },
  async updateTranscript(fileId: string, transcript: string): Promise<void> {
    await fetchJSON<unknown>(`/api/files/${fileId}/transcript`, {
      method: 'PUT', body: JSON.stringify({ transcript }),
    })
  },
  async updateSanitised(fileId: string, sanitised: string): Promise<void> {
    await fetchJSON<unknown>(`/api/files/${fileId}/sanitised`, {
      method: 'PUT', body: JSON.stringify({ sanitised }),
    })
  },
  async cancelSanitise(fileId: string): Promise<void> {
    await fetchJSON<unknown>(`/api/files/${fileId}/sanitise/cancel`, { method: 'POST' })
  },

  // Processing
  async startTranscription(fileId: string, conversationMode = false, force = false): Promise<{ status: string; file?: PipelineFile }> {
    return fetchJSON<{ status: string; file?: PipelineFile }>(`/api/process/transcribe/${fileId}`, {
      method: 'POST', body: JSON.stringify({ conversationMode, force }),
    })
  },
  async cancelProcessing(fileId: string): Promise<void> {
    await fetchJSON<unknown>(`/api/process/${fileId}/cancel`, { method: 'POST' })
  },
  async startSanitise(fileId: string): Promise<SanitiseResponse> {
    const res = await fetch(`${API_BASE}/api/process/sanitise/${fileId}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    })
    // 409 = needs_disambiguation — treat as a valid response, not an error
    if (res.ok || res.status === 409) {
      const data = await res.json()
      // Backend returns flat 'occurrences' array; normalise to grouped Ambiguity[]
      if (data.status === 'needs_disambiguation' && Array.isArray(data.occurrences)) {
        return {
          status: 'needs_disambiguation',
          session_id: data.session_id as string,
          ambiguities: groupOccurrences(data.occurrences as _BackendOccurrence[]),
        }
      }
      return data as SanitiseResponse
    }
    const text = await res.text().catch(() => '')
    const err = new Error(`${res.status}: ${text}`) as Error & { status: number; body: string }
    err.status = res.status
    err.body = text
    throw err
  },
  async resolveSanitise(fileId: string, sessionId: string, decisions: Array<{ alias: string; offset: number; person_id: string; apply_to_remaining?: boolean }>): Promise<{ status: string; file: PipelineFile }> {
    return fetchJSON<{ status: string; file: PipelineFile }>(`/api/process/sanitise/${fileId}/resolve`, {
      method: 'POST', body: JSON.stringify({ session_id: sessionId, decisions }),
    })
  },
  async setTitle(fileId: string, title: string): Promise<PipelineFile> {
    const res = await fetchJSON<{ success: boolean; file: PipelineFile }>(`/api/process/enhance/title/${fileId}`, {
      method: 'POST', body: JSON.stringify({ title }),
    })
    return res.file
  },
  async setCopyedit(fileId: string, text: string): Promise<void> {
    await fetchJSON<unknown>(`/api/process/enhance/copyedit/${fileId}`, {
      method: 'POST', body: JSON.stringify({ text }),
    })
  },
  async setSummary(fileId: string, summary: string): Promise<void> {
    await fetchJSON<unknown>(`/api/process/enhance/summary/${fileId}`, {
      method: 'POST', body: JSON.stringify({ summary }),
    })
  },
  async generateTags(fileId: string): Promise<TagSuggestionResponse> {
    return fetchJSON<TagSuggestionResponse>(`/api/process/enhance/tags/generate/${fileId}`, { method: 'POST' })
  },
  async setTags(fileId: string, tags: string[]): Promise<PipelineFile> {
    const res = await fetchJSON<{ success: boolean; tags: string[]; file: PipelineFile }>(`/api/process/enhance/tags/${fileId}`, {
      method: 'POST', body: JSON.stringify({ tags }),
    })
    return res.file
  },
  async triggerCompile(fileId: string): Promise<void> {
    await fetchJSON<unknown>(`/api/process/enhance/compile/${fileId}`, { method: 'POST' })
  },
  async getEnhanceInput(fileId: string): Promise<{ source: string; length: number; input_text: string }> {
    return fetchJSON<{ source: string; length: number; input_text: string }>(`/api/process/enhance/input/${fileId}`)
  },

  // Enhancement streaming — returns a cleanup fn; calls callbacks as tokens arrive
  startEnhanceStream(
    fileId: string,
    prompt: string,
    callbacks: {
      onToken: (t: string) => void;
      onDone: (full: string) => void;
      onError: (msg: string) => void;
      onStatus?: (message: string) => void;
      onInsufficientRam?: (data: { required_gb: number; available_gb: number; model_name: string; fallback_model: string; fallback_name: string | null }) => void;
    },
    step?: string,
    modelOverride?: string,
  ): () => void {
    const stepParam = step ? `&step=${encodeURIComponent(step)}` : ''
    const modelParam = modelOverride ? `&model_override=${encodeURIComponent(modelOverride)}` : ''
    const url = `${API_BASE}/api/process/enhance/stream/${fileId}?prompt=${encodeURIComponent(prompt)}${stepParam}${modelParam}`
    const es = new EventSource(url)
    let accumulated = ''

    es.addEventListener('token', (e) => {
      accumulated += (e as MessageEvent).data
      callbacks.onToken((e as MessageEvent).data)
    })
    es.addEventListener('done', (e) => {
      es.close()
      // Server may reassemble final text (e.g. copy-edit reinserts image markers)
      const serverFinal = (e as MessageEvent).data
      callbacks.onDone(serverFinal || accumulated)
    })
    es.addEventListener('status', (e) => {
      callbacks.onStatus?.((e as MessageEvent).data)
    })
    es.addEventListener('insufficient_ram', (e) => {
      es.close()
      try {
        const data = JSON.parse((e as MessageEvent).data)
        if (callbacks.onInsufficientRam) {
          callbacks.onInsufficientRam(data)
        } else {
          callbacks.onError(`Not enough memory for ${data.model_name} (needs ~${data.required_gb}GB, ${data.available_gb}GB available)`)
        }
      } catch { callbacks.onError('Insufficient memory for model') }
    })
    es.addEventListener('error', (e) => {
      es.close()
      const raw = (e as MessageEvent).data
      if (raw) {
        // Backend sends plain text error messages, not JSON
        callbacks.onError(raw)
      } else {
        callbacks.onError('Enhancement failed')
      }
    })
    es.onerror = () => { es.close(); callbacks.onError('Connection failed') }

    return () => es.close()
  },

  // Chat — ask AI about the note (SSE stream, same pattern as enhancement)
  startChatStream(
    fileId: string,
    message: string,
    callbacks: { onToken: (t: string) => void; onDone: (full: string) => void; onError: (msg: string) => void },
  ): () => void {
    const url = `${API_BASE}/api/chat/stream/${fileId}?message=${encodeURIComponent(message)}`
    const es = new EventSource(url)
    let accumulated = ''

    es.addEventListener('token', (e) => {
      accumulated += (e as MessageEvent).data
      callbacks.onToken((e as MessageEvent).data)
    })
    es.addEventListener('done', () => {
      es.close()
      callbacks.onDone(accumulated)
    })
    es.addEventListener('error', (e) => {
      es.close()
      try { callbacks.onError(JSON.parse((e as MessageEvent).data).message) }
      catch { callbacks.onError('Chat failed') }
    })
    es.onerror = () => { es.close(); callbacks.onError('Connection failed') }

    return () => es.close()
  },

  // Export
  async getCompiledMarkdown(fileId: string): Promise<CompiledMarkdown> {
    return fetchJSON<CompiledMarkdown>(`/api/process/export/compiled/${fileId}`)
  },
  async saveCompiledEdits(fileId: string, content: string): Promise<void> {
    await fetchJSON<unknown>(`/api/process/export/compiled/${fileId}`, {
      method: 'PUT', body: JSON.stringify({ content }),
    })
  },
  async exportToVault(fileId: string, content: string, options: { export_to_vault: boolean; vault_path?: string; include_audio?: boolean }): Promise<{ success: boolean; vault_exported_path?: string }> {
    return fetchJSON<{ success: boolean; vault_exported_path?: string }>(`/api/process/export/compiled/${fileId}`, {
      method: 'POST', body: JSON.stringify({ content, ...options }),
    })
  },

  // Batch
  async startTranscribeBatch(fileIds: string[]): Promise<{ batch_id: string; status: string }> {
    return fetchJSON<{ batch_id: string; status: string }>('/api/batch/transcribe/start', {
      method: 'POST', body: JSON.stringify({ file_ids: fileIds }),
    })
  },
  async startEnhanceBatch(fileIds: string[]): Promise<{ batch_id: string; status: string }> {
    return fetchJSON<{ batch_id: string; status: string }>('/api/batch/enhance/start', {
      method: 'POST', body: JSON.stringify({ file_ids: fileIds }),
    })
  },

  // Audio
  getAudioUrl(fileId: string, which: 'original' | 'processed' = 'processed'): string {
    return `${API_BASE}/api/files/${fileId}/audio/${which}`
  },
  async getTimeline(fileId: string): Promise<{ tokens: Array<{ text: string; start: number; end: number }> }> {
    return fetchJSON<{ tokens: Array<{ text: string; start: number; end: number }> }>(`/api/files/${fileId}/timeline`)
  },

  // System
  async getSystemHealth(): Promise<SystemHealth> {
    return fetchJSON<SystemHealth>('/api/system/health')
  },

  // Config
  async getConfig(): Promise<{ config: Record<string, unknown> }> {
    return fetchJSON<{ config: Record<string, unknown> }>('/api/config')
  },
  async updateConfig(key: string, value: unknown): Promise<void> {
    await fetchJSON<unknown>('/api/config/update', {
      method: 'POST', body: JSON.stringify({ key, value }),
    })
  },
  async resetConfig(): Promise<void> {
    await fetchJSON<unknown>('/api/config/reset', { method: 'POST' })
  },
  async getConfigDefaults(): Promise<{ config: Record<string, unknown> }> {
    return fetchJSON<{ config: Record<string, unknown> }>('/api/config/defaults')
  },
  // Dependency folder detection & validation
  async detectDeps(): Promise<{ found: boolean; path: string | null; components: DepsValidation | null; zips: DepsZip[] }> {
    return fetchJSON('/api/config/deps/detect')
  },
  async validateDeps(path: string): Promise<DepsValidation> {
    return fetchJSON(`/api/config/deps/validate?path=${encodeURIComponent(path)}`)
  },
  async extractDepsZip(zipPath: string): Promise<{ success: boolean; path: string; components: DepsValidation }> {
    return fetchJSON('/api/config/deps/extract', { method: 'POST', body: JSON.stringify({ zip_path: zipPath }) })
  },
  async applyDeps(path: string): Promise<{ success: boolean; path: string; components: DepsValidation }> {
    return fetchJSON('/api/config/deps/apply', { method: 'POST', body: JSON.stringify({ path }) })
  },
  async getNames(): Promise<{ people: Person[] }> {
    return fetchJSON<{ people: Person[] }>('/api/config/names')
  },
  async updateNames(people: Person[]): Promise<void> {
    await fetchJSON<unknown>('/api/config/names', {
      method: 'POST', body: JSON.stringify({ people }),
    })
  },
  async getSanitisationConfig(): Promise<Record<string, unknown>> {
    return fetchJSON<Record<string, unknown>>('/api/config/sanitisation')
  },
  async getOutputFolder(): Promise<{ path: string }> {
    return fetchJSON<{ path: string }>('/api/config/folders/output')
  },
  async setOutputFolder(path: string): Promise<void> {
    await fetchJSON<unknown>('/api/config/folders/output', {
      method: 'POST', body: JSON.stringify({ path }),
    })
  },

  // Enhancement models
  async getModels(): Promise<{ models: MlxModel[]; selected: string | null }> {
    return fetchJSON<{ models: MlxModel[]; selected: string | null }>('/api/process/enhance/models')
  },
  async selectModel(path: string): Promise<void> {
    const form = new FormData()
    form.append('path', path)
    const res = await fetch(`${API_BASE}/api/process/enhance/models/select`, { method: 'POST', body: form })
    if (!res.ok) throw new Error(`${res.status}`)
  },
  async testModel(): Promise<{ sample: string; elapsed_seconds: number }> {
    return fetchJSON<{ sample: string; elapsed_seconds: number }>('/api/process/enhance/test', { method: 'POST' })
  },
  async getChatTemplate(): Promise<{ template: string | null; override: string | null; source: string }> {
    return fetchJSON<{ template: string | null; override: string | null; source: string }>('/api/process/enhance/models/selected/chat-template')
  },
  async saveChatTemplate(template: string | null): Promise<void> {
    await fetchJSON<unknown>('/api/process/enhance/chat-template', {
      method: 'POST', body: JSON.stringify({ template }),
    })
  },
  async getTagWhitelist(): Promise<{ version: string; count: number; tags: string[] }> {
    return fetchJSON<{ version: string; count: number; tags: string[] }>('/api/process/enhance/tags/whitelist')
  },
  async refreshTagWhitelist(): Promise<{ success: boolean; count: number }> {
    return fetchJSON<{ success: boolean; count: number }>('/api/process/enhance/tags/whitelist/refresh', { method: 'POST' })
  },
}
