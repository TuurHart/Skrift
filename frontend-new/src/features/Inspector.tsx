import { useState, useEffect, useRef, useCallback } from 'react'
import { cn } from '@/lib/utils'
import { api } from '@/api'
import { useSSE } from '@/hooks/useSSE'
import type { PipelineFile } from '@/types/pipeline'
import type { AppSettings } from '@/hooks/useSettings'
import { DisambiguationModal } from '@/components/DisambiguationModal'
import { TagSuggestions } from '@/components/TagSuggestions'
import type { Ambiguity } from '@/api'

// ── Section wrapper ────────────────────────────────────────

function Section({ title, done, disabled, children }: { title: string; done: boolean; disabled?: boolean; children: React.ReactNode }) {
  return (
    <div className={cn('px-4 py-3 border-b border-border/[0.1]', disabled && 'opacity-40 pointer-events-none')}>
      <div className="flex items-center gap-1.5 mb-2">
        <div className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: done ? 'rgb(var(--color-check-green))' : 'rgba(128,128,128,0.3)' }} />
        <span className={cn('text-[11px] font-semibold uppercase tracking-[0.05em]', done ? 'text-text-primary' : 'text-text-muted')}>{title}</span>
      </div>
      {children}
    </div>
  )
}

function Btn({ label, onClick, loading, disabled, small, full, danger }: { label: string; onClick?: () => void; loading?: boolean; disabled?: boolean; small?: boolean; full?: boolean; danger?: boolean }) {
  return (
    <button
      onClick={onClick}
      disabled={loading || disabled}
      className={cn(
        'rounded-md font-medium transition-all duration-150 disabled:opacity-60 active:scale-[0.98]',
        small ? 'px-2 py-1 text-[11px]' : 'px-3 py-1.5 text-[12px]',
        full && 'w-full',
        danger ? 'bg-destructive text-white hover:opacity-90' : 'bg-accent text-white hover:bg-accent/90 hover:shadow-md hover:shadow-accent/20',
      )}
    >
      {loading ? <span className="inline-block w-3 h-3 border-2 border-white border-t-transparent rounded-full animate-spin" /> : label}
    </button>
  )
}

function StreamText({ text, streaming }: { text: string; streaming: boolean }) {
  return (
    <div className="text-[12px] text-text-secondary leading-relaxed max-h-[3.6em] overflow-hidden">
      {text || <span className="text-text-muted italic">Generating…</span>}
      {streaming && <span className="opacity-40 animate-pulse">{'\u258D'}</span>}
    </div>
  )
}

// ── Sub-step (for Enhancement) ─────────────────────────────

function SubStep({ label, done, children }: { label: string; done: boolean; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-1.5">
        <span className={cn('text-[11px] font-medium', done ? 'text-check-green' : 'text-text-muted')}>
          {done ? '\u2713 ' : ''}{label}
        </span>
      </div>
      {children}
    </div>
  )
}

// Format enhancement errors with actionable hints
function formatEnhanceError(err: string): string {
  const lower = err.toLowerCase()
  if (lower.includes('model') || lower.includes('mlx') || lower.includes('outside') || lower.includes('not found') || lower.includes('connection failed') || lower.includes('failed to fetch'))
    return 'Model error — check Settings → Enhancement'
  return err
}

// ── Inspector ──────────────────────────────────────────────

interface InspectorProps {
  file: PipelineFile
  settings: AppSettings
  onFileUpdate: (f: PipelineFile) => void
  exportPreviewActive: boolean
  onToggleExportPreview: () => void
  /** Whichever file is currently mid-enhancement, or null. Polled in App. */
  runningEnhanceFile?: PipelineFile | null
  /** Lets the locked-state banner jump to the file actually running. */
  onSelectFile?: (id: string) => void
}

export function Inspector({ file, settings, onFileUpdate, exportPreviewActive, onToggleExportPreview, runningEnhanceFile, onSelectFile }: InspectorProps) {
  // Three-way enhancement state derived from the polled running file:
  //   - this file is running       → show progress, allow cancel
  //   - some other file is running → lock controls, show banner
  //   - nothing running             → normal idle controls
  const isThisRunning = !!runningEnhanceFile && runningEnhanceFile.id === file.id
  const isOtherRunning = !!runningEnhanceFile && runningEnhanceFile.id !== file.id
  // Transcription polling
  const [polling, setPolling] = useState(false)
  const [stale, setStale] = useState(false)
  const pollingRef = useRef(false)

  // Cleanup
  const [sanitising, setSanitising] = useState(false)
  const [sanitiseError, setSanitiseError] = useState<string | null>(null)
  const [disambigData, setDisambigData] = useState<{ ambiguities: Ambiguity[]; sessionId: string } | null>(null)
  const [ramWarning, setRamWarning] = useState<{
    required_gb: number; available_gb: number; model_name: string;
    fallback_model: string; fallback_name: string | null;
    pendingStep: string; pendingPrompt: string;
  } | null>(null)

  // Enhancement SSE — one stream at a time
  const titleSSE = useSSE()
  const copyeditSSE = useSSE()
  const summarySSE = useSSE()

  // Selected enhancement model — fetch once so the running banner can name it.
  // Stored on the component (not a hook into settings) since settings doesn't
  // currently track the selected model.
  const [modelName, setModelName] = useState<string | null>(null)
  useEffect(() => {
    let cancelled = false
    api.getModels()
      .then(r => {
        if (cancelled) return
        const sel = r.models.find(m => m.selected)
        setModelName(sel?.name ?? null)
      })
      .catch(() => { /* model list unavailable — banner just hides the name */ })
    return () => { cancelled = true }
  }, [])

  const [generatingTags, setGeneratingTags] = useState(false)
  const [applyingTags, setApplyingTags] = useState(false)
  const [pendingTags, setPendingTags] = useState<string[]>([])
  const [localTagSuggestions, setLocalTagSuggestions] = useState<{ old: string[]; new: string[] } | null>(null)
  const [customTagInput, setCustomTagInput] = useState('')

  // Reset + seed tag suggestions when switching files or when suggestions arrive
  const prevFileId = useRef(file.id)
  useEffect(() => {
    if (prevFileId.current !== file.id) {
      prevFileId.current = file.id
      setPendingTags([])
    }
    // Always sync local state from the current file's tag_suggestions
    if (file.tag_suggestions &&
        (file.tag_suggestions.old?.length || file.tag_suggestions.new?.length)) {
      setLocalTagSuggestions({
        old: file.tag_suggestions.old ?? [],
        new: file.tag_suggestions.new ?? [],
      })
    } else {
      setLocalTagSuggestions(null)
    }
  }, [file.id, file.tag_suggestions])

  // Export
  const [exporting, setExporting] = useState(false)

  // ── Transcription ──────────────────────────────────────

  const startPolling = useCallback(() => {
    pollingRef.current = true
    setPolling(true)
    setStale(false)
  }, [])

  useEffect(() => {
    if (file.steps.transcribe === 'processing' && !pollingRef.current) {
      startPolling()
    }
  }, [file.steps.transcribe, startPolling])

  useEffect(() => {
    if (!polling) return
    let cancelled = false
    const iv = setInterval(async () => {
      if (cancelled) return
      try {
        const updated = await api.getFileStatus(file.id)
        if (cancelled) return
        onFileUpdate(updated)
        if (updated.steps.transcribe === 'done' || updated.steps.transcribe === 'error') {
          setPolling(false)
          pollingRef.current = false
        }
        // Stale check
        if (updated.lastActivityAt) {
          const age = (Date.now() - new Date(updated.lastActivityAt).getTime()) / 1000
          setStale(age > 120)
        }
      } catch { /* keep polling */ }
    }, 3000)
    return () => { cancelled = true; clearInterval(iv) }
  }, [polling, file.id, onFileUpdate])

  async function handleTranscribe() {
    try {
      await api.startTranscription(file.id)
      startPolling()
    } catch (err) { console.error('Transcribe failed:', err) }
  }

  async function handleCancelTranscription() {
    try {
      await api.cancelProcessing(file.id)
      setPolling(false)
      pollingRef.current = false
      const updated = await api.getFile(file.id)
      onFileUpdate(updated)
    } catch { /* ignore */ }
  }

  async function handleRedoTranscription() {
    try {
      await api.startTranscription(file.id, false, true) // force=true resets all downstream
      // Reload immediately so NoteBody shows the cleared state
      const updated = await api.getFile(file.id)
      onFileUpdate(updated)
      startPolling()
    } catch { /* ignore */ }
  }

  // ── Cleanup ────────────────────────────────────────────

  async function handleCleanUp() {
    setSanitising(true)
    setSanitiseError(null)
    try {
      const res = await api.startSanitise(file.id)
      if (res.status === 'done') {
        if (res.file) onFileUpdate(res.file)
        else {
          // file missing from response — reload manually
          const updated = await api.getFile(file.id)
          onFileUpdate(updated)
        }
      } else if (res.status === 'needs_disambiguation' && res.ambiguities && res.session_id) {
        setDisambigData({ ambiguities: res.ambiguities, sessionId: res.session_id })
      } else if (res.status === 'already_processing') {
        setSanitiseError('Already running \u2014 please wait')
      }
    } catch (err) {
      console.error('Sanitise failed:', err)
      setSanitiseError(err instanceof Error ? err.message : 'Cleanup failed')
    } finally {
      setSanitising(false)
    }
  }

  async function handleDisambigResolve(decisions: Parameters<typeof api.resolveSanitise>[2]) {
    if (!disambigData) return
    try {
      const res = await api.resolveSanitise(file.id, disambigData.sessionId, decisions)
      onFileUpdate(res.file)
    } finally { setDisambigData(null) }
  }

  async function handleDisambigCancel() {
    setDisambigData(null)
    await api.cancelSanitise(file.id).catch(() => {})
    const updated = await api.getFile(file.id)
    onFileUpdate(updated)
  }

  // ── Enhancement ────────────────────────────────────────

  function getPrompt(id: string) {
    return settings.enhancePrompts.find(p => p.id === id)?.instruction ?? ''
  }

  // RAM warning handler — shows dialog when model is too large for available memory
  function makeRamHandler(step: string, prompt: string) {
    return (data: { required_gb: number; available_gb: number; model_name: string; fallback_model: string; fallback_name: string | null }) => {
      setRamWarning({ ...data, pendingStep: step, pendingPrompt: prompt })
    }
  }

  function runTitleStream(modelOverride?: string) {
    titleSSE.start(
      (cbs) => api.startEnhanceStream(file.id, getPrompt('title'),
        { ...cbs, onInsufficientRam: makeRamHandler('title', getPrompt('title')) },
        'title', modelOverride),
      async (text) => {
        try {
          const updated = await api.setTitle(file.id, text.trim())
          onFileUpdate(updated)
        } catch { /* ignore */ }
      },
    )
  }

  function runCopyeditStream(modelOverride?: string) {
    copyeditSSE.start(
      (cbs) => api.startEnhanceStream(file.id, getPrompt('copy_edit'),
        { ...cbs, onInsufficientRam: makeRamHandler('copy_edit', getPrompt('copy_edit')) },
        'copy_edit', modelOverride),
      async (text) => {
        try {
          await api.setCopyedit(file.id, text)
          const updated = await api.getFile(file.id)
          onFileUpdate(updated)
        } catch { /* ignore */ }
      },
    )
  }

  function runSummaryStream(modelOverride?: string) {
    summarySSE.start(
      (cbs) => api.startEnhanceStream(file.id, getPrompt('summary'),
        { ...cbs, onInsufficientRam: makeRamHandler('summary', getPrompt('summary')) },
        undefined, modelOverride),
      async (text) => {
        try {
          await api.setSummary(file.id, text)
          const updated = await api.getFile(file.id)
          onFileUpdate(updated)
        } catch { /* ignore */ }
      },
    )
  }

  async function handleEnhanceAll() {
    // Sequential: title -> copyedit -> summary -> tags
    // Each step passes its name so the backend routes to the right model
    await new Promise<void>((resolve) => {
      titleSSE.start(
        (cbs) => api.startEnhanceStream(file.id, getPrompt('title'),
          { ...cbs, onInsufficientRam: makeRamHandler('title', getPrompt('title')) },
          'title'),
        async (text) => {
          try { await api.setTitle(file.id, text.trim()) } catch { /* ignore */ }
          resolve()
        },
      )
    })
    const updated1 = await api.getFile(file.id)
    onFileUpdate(updated1)

    await new Promise<void>((resolve) => {
      copyeditSSE.start(
        (cbs) => api.startEnhanceStream(file.id, getPrompt('copy_edit'),
          { ...cbs, onInsufficientRam: makeRamHandler('copy_edit', getPrompt('copy_edit')) },
          'copy_edit'),
        async (text) => {
          try { await api.setCopyedit(file.id, text) } catch { /* ignore */ }
          resolve()
        },
      )
    })

    await new Promise<void>((resolve) => {
      summarySSE.start(
        (cbs) => api.startEnhanceStream(file.id, getPrompt('summary'),
          { ...cbs, onInsufficientRam: makeRamHandler('summary', getPrompt('summary')) },
          'summary'),
        async (text) => {
          try { await api.setSummary(file.id, text) } catch { /* ignore */ }
          resolve()
        },
      )
    })

    const updated2 = await api.getFile(file.id)
    onFileUpdate(updated2)

    // Tags
    await handleGenerateTags()
  }

  async function handleGenerateTags() {
    setGeneratingTags(true)
    try {
      const res = await api.generateTags(file.id)
      setLocalTagSuggestions({ old: res.old, new: res.new })
      setPendingTags([]) // start with nothing selected — user picks what they want
    } finally { setGeneratingTags(false) }
  }

  function handleToggleTag(tag: string) {
    setPendingTags(prev =>
      prev.includes(tag) ? prev.filter(t => t !== tag) : [...prev, tag]
    )
  }

  async function handleApplyTags() {
    setApplyingTags(true)
    try {
      const updated = await api.setTags(file.id, pendingTags)
      onFileUpdate(updated)
      setLocalTagSuggestions(null)
    } catch { /* ignore */ }
    finally { setApplyingTags(false) }
  }

  async function handleAddCustomTag() {
    const tag = customTagInput.trim().toLowerCase().replace(/[^a-z0-9_\-/]/g, '_')
    if (!tag || (file.enhanced_tags ?? []).includes(tag)) { setCustomTagInput(''); return }
    const newTags = [...(file.enhanced_tags ?? []), tag]
    try {
      const updated = await api.setTags(file.id, newTags)
      onFileUpdate(updated)
      setCustomTagInput('')
    } catch { /* ignore */ }
  }

  // Sync pending tags only when switching to a different file
  useEffect(() => {
    setPendingTags(file.enhanced_tags ?? [])
  }, [file.id])

  // ── Export ─────────────────────────────────────────────

  async function handleExportDirect() {
    setExporting(true)
    try {
      const compiled = await api.getCompiledMarkdown(file.id)
      await api.exportToVault(file.id, compiled.content, {
        export_to_vault: true,
        vault_path: settings.vaultPath || undefined,
        include_audio: file.include_audio_in_export ?? false,
      })
      const updated = await api.getFile(file.id)
      onFileUpdate(updated)
    } catch (err) { console.error('Export failed:', err) }
    finally { setExporting(false) }
  }

  // ── Derived state ──────────────────────────────────────

  const isAppleNote = file.source_type === 'note'
  const isCapture = file.source_type === 'capture'
  const transcribeSkipped = file.steps.transcribe === 'skipped'
  const transcribeDone = file.steps.transcribe === 'done'
  const transcribeProcessing = file.steps.transcribe === 'processing' || polling
  const transcribeError = file.steps.transcribe === 'error'

  const sanitiseDone = file.steps.sanitise === 'done'

  const enhanceDone = file.steps.enhance === 'done'
  const canExport = enhanceDone || file.compiled_text != null

  // Lock controls when this file is mid-stream OR when *any other* file is.
  // The latter is RAM safety: only one MLX session at a time.
  const anyEnhancing = titleSSE.streaming || copyeditSSE.streaming || summarySSE.streaming || generatingTags || isOtherRunning

  const tagSuggestions = localTagSuggestions

  // ── Render ─────────────────────────────────────────────

  return (
    <aside className="w-[280px] min-w-[280px] h-full flex flex-col bg-surface border-l border-border/[0.1] overflow-y-auto">
      {/* Header */}
      <div className="px-4 py-3 border-b border-border/[0.1]">
        <span className="text-[11px] font-semibold uppercase tracking-[0.05em] text-text-muted">Inspector</span>
      </div>

      {/* ── Transcription ── */}
      <Section title="Transcription" done={transcribeDone || transcribeSkipped}>
        {isCapture && transcribeSkipped ? (
          <div className="text-[12px] text-text-secondary flex items-center gap-1.5">
            <span className="text-check-green">{'\u2713'}</span> No audio — text annotation only
          </div>
        ) : isCapture && transcribeDone && !file.audioMetadata?.duration ? (
          <div className="text-[12px] text-text-secondary flex items-center gap-1.5">
            <span className="text-check-green">{'\u2713'}</span> Text annotation
          </div>
        ) : isAppleNote ? (
          <div className="text-[12px] text-text-secondary flex items-center gap-1.5">
            <span className="text-check-green">{'\u2713'}</span> Imported from Apple Notes
          </div>
        ) : transcribeProcessing ? (
          <div className="space-y-2">
            <div className="text-[12px] text-text-secondary flex items-center gap-2">
              <span className="inline-block w-3 h-3 border-2 border-accent border-t-transparent rounded-full animate-spin" />
              {file.progressMessage ?? 'Transcribing\u2026'}
              {file.progress != null && <span className="text-text-muted ml-auto">{file.progress}%</span>}
            </div>
            {stale && <div className="text-[11px] text-step-enhance">{'\u26A0'} Transcription may be stuck</div>}
            <Btn label="Cancel" onClick={() => void handleCancelTranscription()} small />
          </div>
        ) : transcribeError ? (
          <div className="space-y-2">
            <div className="text-[12px] text-destructive">{file.error ?? 'Transcription failed'}</div>
            <Btn label="Retry" onClick={() => void handleTranscribe()} small />
          </div>
        ) : transcribeDone ? (
          <div className="text-[12px] text-text-secondary flex items-center gap-1.5">
            <span className="text-check-green">{'\u2713'}</span> Transcribed
            <button onClick={() => void handleRedoTranscription()} className="ml-auto text-[11px] px-2 py-0.5 rounded bg-white/[0.05] border border-border/[0.15] text-text-muted hover:text-text-secondary transition-all duration-150 active:scale-[0.98]">Redo</button>
          </div>
        ) : (
          <Btn label="Transcribe" onClick={() => void handleTranscribe()} />
        )}
      </Section>

      {/* ── Cleanup ── */}
      <Section title="Cleanup" done={sanitiseDone} disabled={!transcribeDone && !isAppleNote && !transcribeSkipped}>
        {sanitiseDone ? (
          <div className="text-[12px] text-text-secondary flex items-center gap-1.5">
            <span className="text-check-green">{'\u2713'}</span> Cleanup complete
            <button onClick={() => void handleCleanUp()} className="ml-auto text-[11px] px-2 py-0.5 rounded bg-white/[0.05] border border-border/[0.15] text-text-muted hover:text-text-secondary transition-all duration-150 active:scale-[0.98]">Redo</button>
          </div>
        ) : file.steps.sanitise === 'error' ? (
          <div className="space-y-2">
            <div className="text-[12px] text-destructive">{file.error ?? 'Cleanup failed'}</div>
            <Btn label="Retry" onClick={() => void handleCleanUp()} small />
          </div>
        ) : (
          <div className="space-y-2">
            <div className="text-[12px] text-text-secondary">Link names and fix formatting</div>
            <Btn label={sanitising ? '' : 'Clean Up'} loading={sanitising} onClick={() => void handleCleanUp()} />
            {sanitiseError && <div className="text-[11px] text-destructive">{sanitiseError}</div>}
          </div>
        )}
      </Section>

      {/* ── Locked-while-other-file-enhances banner ── */}
      {isOtherRunning && runningEnhanceFile && (
        <div className="mx-3 mt-3 mb-1 px-3 py-2 rounded-md bg-step-enhance/[0.10] border border-step-enhance/[0.25]">
          <div className="text-[11px] uppercase tracking-wider text-step-enhance/80 font-semibold mb-1">
            Locked
          </div>
          <div className="text-[12px] text-text-secondary leading-snug">
            Enhancing{' '}
            <button
              onClick={() => onSelectFile?.(runningEnhanceFile.id)}
              className="text-accent hover:underline truncate max-w-full"
            >
              {runningEnhanceFile.enhanced_title || runningEnhanceFile.filename}
            </button>
            . Enhancement actions on this file are paused until that finishes — only one model runs at a time.
          </div>
        </div>
      )}

      {/* ── Enhancement ── */}
      <Section title="Enhancement" done={enhanceDone} disabled={!sanitiseDone}>
        {(() => {
          const hasTitle = !!file.enhanced_title
          const hasCopyedit = !!file.enhanced_copyedit
          const hasSummary = !!file.enhanced_summary
          const hasTags = (file.enhanced_tags?.length ?? 0) > 0
          const stepsComplete = [hasTitle, hasCopyedit, hasSummary, hasTags].filter(Boolean).length
          const allDone = stepsComplete === 4
          const noneStarted = stepsComplete === 0 && !anyEnhancing && !tagSuggestions

          // Currently streaming — show live progress
          const currentStep = titleSSE.streaming ? 'title' : copyeditSSE.streaming ? 'copy_edit' : summarySSE.streaming ? 'summary' : generatingTags ? 'tags' : null

          const handleCancelEnhance = async () => {
            titleSSE.stop?.()
            copyeditSSE.stop?.()
            summarySSE.stop?.()
            try { await api.cancelEnhance(file.id) } catch { /* best-effort */ }
          }

          if (isThisRunning && !currentStep) {
            return (
              <div className="space-y-2">
                <div className="flex items-center gap-2 text-[12px] text-text-secondary">
                  <span className="w-3 h-3 border-2 border-accent border-t-transparent rounded-full animate-spin inline-block" />
                  Enhancing in background…
                </div>
                {modelName && <div className="text-[10px] text-text-muted">via {modelName}</div>}
                <Btn label="Cancel" small danger onClick={() => void handleCancelEnhance()} />
              </div>
            )
          }

          return (
            <div className="space-y-2">
              {/* Primary button: Enhance / Re-enhance / streaming indicator */}
              {currentStep ? (
                <div className="space-y-2">
                  <div className="flex items-center gap-2 text-[12px] text-text-secondary">
                    <span className="w-3 h-3 border-2 border-accent border-t-transparent rounded-full animate-spin inline-block" />
                    {/* Show detailed status from SSE if available, otherwise generic step name */}
                    {currentStep === 'title' && (titleSSE.status || 'Generating title\u2026')}
                    {currentStep === 'copy_edit' && (copyeditSSE.status || 'Editing text\u2026')}
                    {currentStep === 'summary' && (summarySSE.status || 'Writing summary\u2026')}
                    {currentStep === 'tags' && 'Suggesting tags\u2026'}
                  </div>
                  <StreamText
                    text={currentStep === 'title' ? titleSSE.text : currentStep === 'copy_edit' ? copyeditSSE.text.slice(-120) : currentStep === 'summary' ? summarySSE.text : ''}
                    streaming
                  />
                  <Btn
                    label="Cancel"
                    small
                    danger
                    onClick={() => void handleCancelEnhance()}
                  />
                </div>
              ) : noneStarted ? (
                <div className="space-y-1">
                  <Btn label="Enhance" full onClick={() => void handleEnhanceAll()} />
                  {modelName && <div className="text-[10px] text-text-muted text-center">via {modelName}</div>}
                </div>
              ) : allDone && !tagSuggestions ? (
                <div className="text-[12px] text-text-secondary flex items-center gap-1.5">
                  <span className="text-check-green">{'\u2713'}</span> All steps complete
                  <button onClick={() => void handleEnhanceAll()} className="ml-auto text-[11px] px-2 py-0.5 rounded bg-white/[0.05] border border-border/[0.15] text-text-muted hover:text-text-secondary transition-all duration-150 active:scale-[0.98]">Redo all</button>
                </div>
              ) : !tagSuggestions ? (
                <Btn label="Continue Enhancing" full onClick={() => void handleEnhanceAll()} />
              ) : null}

              {/* Error display */}
              {(titleSSE.error || copyeditSSE.error || summarySSE.error) && !currentStep && (
                <div className="text-[11px] text-destructive">{formatEnhanceError(titleSSE.error || copyeditSSE.error || summarySSE.error || '')}</div>
              )}

              {/* Step results — collapsible, shown after at least one step is done */}
              {stepsComplete > 0 && !currentStep && (
                <details className="group">
                  <summary className="text-[11px] text-text-muted cursor-pointer hover:text-text-secondary select-none flex items-center gap-1">
                    <span className="transition-transform group-open:rotate-90">{'\u25B6'}</span>
                    {stepsComplete}/4 steps
                  </summary>
                  <div className="mt-2 space-y-2.5 pl-1">
                    {/* Title */}
                    <SubStep label="Title" done={hasTitle}>
                      {hasTitle ? (
                        <div className="flex items-center gap-2">
                          <span className="text-[12px] text-text-secondary truncate flex-1">{file.enhanced_title}</span>
                          <Btn label="Redo" onClick={runTitleStream} small disabled={anyEnhancing} />
                        </div>
                      ) : (
                        <Btn label="Generate" onClick={runTitleStream} small disabled={anyEnhancing} />
                      )}
                    </SubStep>

                    {/* Copy Edit */}
                    <SubStep label="Copy Edit" done={hasCopyedit}>
                      {hasCopyedit ? (
                        <div className="flex items-center gap-2">
                          <span className="text-[12px] text-text-secondary flex-1">Applied {'\u2713'}</span>
                          <Btn label="Redo" onClick={runCopyeditStream} small disabled={anyEnhancing} />
                        </div>
                      ) : (
                        <Btn label="Edit" onClick={runCopyeditStream} small disabled={anyEnhancing} />
                      )}
                    </SubStep>

                    {/* Summary */}
                    <SubStep label="Summary" done={hasSummary}>
                      {hasSummary ? (
                        <div className="flex items-center gap-2">
                          <span className="text-[12px] text-text-secondary flex-1 line-clamp-2">{file.enhanced_summary}</span>
                          <Btn label="Redo" onClick={runSummaryStream} small disabled={anyEnhancing} />
                        </div>
                      ) : (
                        <Btn label="Generate" onClick={runSummaryStream} small disabled={anyEnhancing} />
                      )}
                    </SubStep>

                    {/* Significance */}
                    {file.significance != null && (
                      <SubStep label="Significance" done>
                        <div className="flex items-center gap-2">
                          <div className="flex-1 h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
                            <div
                              className="h-full rounded-full transition-all"
                              style={{
                                width: `${Math.round(Number(file.significance) * 100)}%`,
                                backgroundColor: Number(file.significance) > 0.7 ? '#f59e0b' : Number(file.significance) > 0.3 ? '#60a5fa' : '#6b7280',
                              }}
                            />
                          </div>
                          <span className="text-[11px] text-text-muted tabular-nums">{Number(file.significance).toFixed(1)}</span>
                        </div>
                      </SubStep>
                    )}

                    {/* Tags */}
                    <SubStep label="Tags" done={hasTags}>
                      {hasTags ? (
                        <div className="space-y-2">
                          <div className="flex flex-wrap gap-1">
                            {(file.enhanced_tags ?? []).map(t => (
                              <span key={t} className="text-[11px] px-2 py-[2px] rounded-full bg-accent/15 text-accent">#{t}</span>
                            ))}
                          </div>
                          <div className="flex gap-1.5">
                            <input
                              value={customTagInput}
                              onChange={e => setCustomTagInput(e.target.value)}
                              onKeyDown={e => { if (e.key === 'Enter') void handleAddCustomTag() }}
                              placeholder="Add tag\u2026"
                              className="flex-1 text-[11px] px-2 py-1 rounded-md bg-white/[0.04] border border-border/[0.15] text-text-secondary outline-none focus:border-accent/30 placeholder:text-text-muted"
                            />
                            <Btn label="Add" onClick={() => void handleAddCustomTag()} small />
                          </div>
                          <Btn label="Redo" onClick={() => void handleGenerateTags()} small />
                        </div>
                      ) : (
                        <Btn label="Suggest Tags" onClick={() => void handleGenerateTags()} small disabled={anyEnhancing} />
                      )}
                    </SubStep>
                  </div>
                </details>
              )}

              {/* Tag suggestions — always visible when pending (need user action) */}
              {tagSuggestions && !currentStep && (
                <div className="space-y-2">
                  <TagSuggestions
                    oldTags={tagSuggestions.old ?? []}
                    newTags={tagSuggestions.new ?? []}
                    accepted={pendingTags}
                    onToggle={handleToggleTag}
                  />
                  <Btn label={applyingTags ? '' : `Apply ${pendingTags.length} tag${pendingTags.length !== 1 ? 's' : ''}`} loading={applyingTags} onClick={() => void handleApplyTags()} small full />
                </div>
              )}
            </div>
          )
        })()}
      </Section>

      {/* ── Export ── */}
      <Section title="Export" done={file.steps.export === 'done'} disabled={!canExport}>
        <div className="space-y-2">
          {file.steps.export === 'done' && (
            <div className="text-[12px] text-text-secondary flex items-center gap-1.5">
              <span className="text-check-green">{'\u2713'}</span> Exported to vault
            </div>
          )}
          {file.steps.export !== 'done' && (
            <div className="text-[12px] text-text-secondary">Export to Obsidian vault</div>
          )}
          <div className="flex gap-2">
            <Btn label={exportPreviewActive ? 'Back to note' : 'Preview'} onClick={onToggleExportPreview} small />
            <Btn label={exporting ? '' : file.steps.export === 'done' ? 'Re-export' : 'Export'} loading={exporting} onClick={() => void handleExportDirect()} small />
          </div>
        </div>
      </Section>

      {/* ── Modals ── */}
      {disambigData && (
        <DisambiguationModal
          ambiguities={disambigData.ambiguities}
          sessionId={disambigData.sessionId}
          onResolve={(decisions) => void handleDisambigResolve(decisions)}
          onCancel={() => void handleDisambigCancel()}
        />
      )}

      {/* RAM Warning Modal */}
      {ramWarning && (
        <div className="fixed inset-0 z-[200] flex items-center justify-center bg-black/50 animate-modal-in">
          <div className="bg-surface border border-border/30 rounded-xl p-6 max-w-sm mx-4 shadow-2xl">
            <h3 className="text-[16px] font-semibold text-text-primary mb-2">Not enough memory</h3>
            <p className="text-[13px] text-text-secondary mb-4 leading-relaxed">
              <span className="font-medium text-text-primary">{ramWarning.model_name}</span> needs
              ~{ramWarning.required_gb}GB but only {ramWarning.available_gb}GB is available.
            </p>
            <div className="flex flex-col gap-2">
              {ramWarning.fallback_model && (
                <button
                  onClick={() => {
                    const fallback = ramWarning.fallback_model
                    const step = ramWarning.pendingStep
                    setRamWarning(null)
                    // Retry with lighter model
                    if (step === 'title') runTitleStream(fallback)
                    else if (step === 'copy_edit') runCopyeditStream(fallback)
                    else if (step === 'summary') runSummaryStream(fallback)
                  }}
                  className="w-full px-4 py-2.5 rounded-lg bg-accent text-white text-[14px] font-medium hover:bg-accent/90 transition-colors"
                >
                  Use lighter model{ramWarning.fallback_name ? ` (${ramWarning.fallback_name})` : ''}
                </button>
              )}
              <button
                onClick={() => setRamWarning(null)}
                className="w-full px-4 py-2.5 rounded-lg bg-white/[0.05] text-text-primary text-[14px] font-medium hover:bg-white/[0.08] transition-colors"
              >
                I'll close apps, try again
              </button>
            </div>
          </div>
        </div>
      )}
    </aside>
  )
}
