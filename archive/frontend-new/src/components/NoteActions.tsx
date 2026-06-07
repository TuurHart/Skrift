import { useState, useEffect, useRef } from 'react'
import { MoreHorizontal } from 'lucide-react'
import { toast } from 'sonner'
import { api } from '@/api'
import { useSSE } from '@/hooks/useSSE'
import { cn } from '@/lib/utils'
import type { PipelineFile } from '@/types/pipeline'
import type { AppSettings } from '@/hooks/useSettings'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'

interface NoteActionsProps {
  file: PipelineFile
  settings: AppSettings
  onFileUpdate: (f: PipelineFile) => void
  /** Whichever file is mid-enhancement, or null — only one MLX run at a time. */
  runningEnhanceFile?: PipelineFile | null
  onSelectFile?: (id: string) => void
}

type RamWarning = {
  required_gb: number; available_gb: number; model_name: string
  fallback_model: string; fallback_name: string | null
  pendingStep: string
}

export function NoteActions({ file, settings, onFileUpdate, runningEnhanceFile, onSelectFile }: NoteActionsProps) {
  const titleSSE = useSSE()
  const copyeditSSE = useSSE()
  const summarySSE = useSSE()
  const [exporting, setExporting] = useState(false)
  const [ramWarning, setRamWarning] = useState<RamWarning | null>(null)
  const [menuOpen, setMenuOpen] = useState(false)
  const menuRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!menuOpen) return
    function onDown(e: MouseEvent) { if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false) }
    document.addEventListener('mousedown', onDown)
    return () => document.removeEventListener('mousedown', onDown)
  }, [menuOpen])

  // ── Derived state ──
  const isAppleNote = file.source_type === 'note'
  const transcribeSkipped = file.steps.transcribe === 'skipped'
  const transcribeDone = file.steps.transcribe === 'done'
  const transcribeProcessing = file.steps.transcribe === 'processing'
  const enhanceDone = file.steps.enhance === 'done'
  const exported = file.steps.export === 'done'
  const canExport = enhanceDone || file.compiled_text != null

  const isThisRunning = !!runningEnhanceFile && runningEnhanceFile.id === file.id
  const isOtherRunning = !!runningEnhanceFile && runningEnhanceFile.id !== file.id
  const streaming = titleSSE.streaming || copyeditSSE.streaming || summarySSE.streaming
  const busy = isThisRunning || streaming || transcribeProcessing

  function getPrompt(id: string) {
    return settings.enhancePrompts.find(p => p.id === id)?.instruction ?? ''
  }
  function ramHandler(step: string) {
    return (data: Omit<RamWarning, 'pendingStep'>) => setRamWarning({ ...data, pendingStep: step })
  }

  // ── Handlers ──
  async function handleProcess() {
    try { await api.startRun([file.id]) } catch (err) { toast.error(`Process failed: ${err instanceof Error ? err.message : String(err)}`) }
  }

  async function handleExport() {
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
      toast.success('Exported to Obsidian')
    } catch (err) { toast.error(`Export failed: ${err instanceof Error ? err.message : String(err)}`) }
    finally { setExporting(false) }
  }

  async function handleRedoTranscription() {
    setMenuOpen(false)
    try { await api.startTranscription(file.id, false, true); onFileUpdate(await api.getFile(file.id)) }
    catch { toast.error('Could not re-transcribe') }
  }

  async function handleCancel() {
    titleSSE.stop?.(); copyeditSSE.stop?.(); summarySSE.stop?.()
    try {
      if (transcribeProcessing) await api.cancelProcessing(file.id)
      else await api.cancelEnhance(file.id)
      onFileUpdate(await api.getFile(file.id))
    } catch { /* best-effort */ }
  }

  function runTitleStream(modelOverride?: string) {
    setMenuOpen(false)
    titleSSE.start(
      (cbs) => api.startEnhanceStream(file.id, getPrompt('title'), { ...cbs, onInsufficientRam: ramHandler('title') }, 'title', modelOverride),
      async (text) => { try { onFileUpdate(await api.setTitle(file.id, text.trim(), true)) } catch { /* ignore */ } },
    )
  }
  function runCopyeditStream(modelOverride?: string) {
    setMenuOpen(false)
    copyeditSSE.start(
      (cbs) => api.startEnhanceStream(file.id, getPrompt('copy_edit'), { ...cbs, onInsufficientRam: ramHandler('copy_edit') }, 'copy_edit', modelOverride),
      async (text) => { try { await api.setCopyedit(file.id, text); onFileUpdate(await api.getFile(file.id)) } catch { /* ignore */ } },
    )
  }
  function runSummaryStream(modelOverride?: string) {
    setMenuOpen(false)
    summarySSE.start(
      (cbs) => api.startEnhanceStream(file.id, getPrompt('summary'), { ...cbs, onInsufficientRam: ramHandler('summary') }, undefined, modelOverride),
      async (text) => { try { await api.setSummary(file.id, text); onFileUpdate(await api.getFile(file.id)) } catch { /* ignore */ } },
    )
  }

  // ── Contextual primary ──
  // Process until the auto-steps are done, then Export, then Re-export.
  const primary: { label: string; run: () => void } = !enhanceDone
    ? { label: 'Process', run: () => void handleProcess() }
    : !exported
      ? { label: 'Export to Obsidian', run: () => void handleExport() }
      : { label: 'Re-export', run: () => void handleExport() }

  const runningLabel = transcribeProcessing ? 'Transcribing…' : (titleSSE.status || copyeditSSE.status || summarySSE.status || 'Processing…')

  // ── ⋯ menu items (contextual) ──
  const hasParts = !!file.enhanced_title && !!file.enhanced_copyedit && !!file.enhanced_summary
  const menuItems: Array<{ label: string; onClick: () => void; disabled?: boolean }> = []
  if (transcribeDone && !isAppleNote) menuItems.push({ label: 'Re-transcribe', onClick: () => void handleRedoTranscription() })
  if (hasParts) {
    menuItems.push({ label: 'Redo title', onClick: () => runTitleStream(), disabled: isOtherRunning })
    menuItems.push({ label: 'Redo copy-edit', onClick: () => runCopyeditStream(), disabled: isOtherRunning })
    menuItems.push({ label: 'Redo summary', onClick: () => runSummaryStream(), disabled: isOtherRunning })
  }
  if (exported) menuItems.push({ label: 'Re-export', onClick: () => void handleExport() })

  // Nothing to act on yet (untranscribed audio uses the body placeholder)
  if (!transcribeDone && !transcribeSkipped && !isAppleNote) return null

  return (
    <div className="flex items-center gap-2 flex-none">
      {busy ? (
        <>
          <span className="flex items-center gap-2 text-[12px] text-text-secondary">
            <span className="w-3.5 h-3.5 border-2 border-accent border-t-transparent rounded-full animate-spin inline-block" />
            {runningLabel}
          </span>
          <Button variant="secondary" size="sm" onClick={() => void handleCancel()}>Cancel</Button>
        </>
      ) : (
        <Button
          onClick={() => { if (isOtherRunning) { toast.info('Another note is processing — only one runs at a time', runningEnhanceFile && onSelectFile ? { action: { label: 'View', onClick: () => onSelectFile(runningEnhanceFile.id) } } : undefined); return } primary.run() }}
          disabled={primary.label !== 'Process' && !canExport}
          className={cn(isOtherRunning && 'opacity-50')}
        >
          {exporting ? <span className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin inline-block" /> : primary.label}
        </Button>
      )}

      {/* ⋯ overflow */}
      {menuItems.length > 0 && (
        <div className="relative" ref={menuRef}>
          <button
            onClick={() => setMenuOpen(v => !v)}
            className="w-9 h-9 rounded-lg bg-white/[0.05] text-text-secondary hover:text-text-primary hover:bg-white/[0.08] transition-colors flex items-center justify-center"
            aria-label="More actions"
          >
            <MoreHorizontal size={16} />
          </button>
          {menuOpen && (
            <div className="absolute top-11 right-0 z-30 w-48 rounded-lg border border-border/[0.12] bg-surface shadow-xl shadow-black/40 p-1.5 animate-modal-in">
              {menuItems.map((it, i) => (
                <button
                  key={i}
                  onClick={() => { if (!it.disabled) it.onClick() }}
                  disabled={it.disabled}
                  className={cn(
                    'w-full text-left text-[12px] px-2.5 py-2 rounded-md transition-colors',
                    it.disabled ? 'text-text-muted/50 cursor-not-allowed' : 'text-text-secondary hover:bg-accent/12 hover:text-accent',
                  )}
                >
                  {it.label}
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      {/* RAM warning */}
      <Dialog open={!!ramWarning} onOpenChange={(o) => { if (!o) setRamWarning(null) }}>
        <DialogContent className="max-w-sm">
          {ramWarning && (
            <>
              <DialogHeader>
                <DialogTitle>Not enough memory</DialogTitle>
                <DialogDescription>
                  <span className="font-medium text-text-primary">{ramWarning.model_name}</span> needs
                  ~{ramWarning.required_gb}GB but only {ramWarning.available_gb}GB is available.
                </DialogDescription>
              </DialogHeader>
              <div className="flex flex-col gap-2 mt-2">
                {ramWarning.fallback_model && (
                  <Button
                    size="lg"
                    className="w-full"
                    onClick={() => {
                      const fallback = ramWarning.fallback_model
                      const step = ramWarning.pendingStep
                      setRamWarning(null)
                      if (step === 'title') runTitleStream(fallback)
                      else if (step === 'copy_edit') runCopyeditStream(fallback)
                      else if (step === 'summary') runSummaryStream(fallback)
                    }}
                  >
                    Use lighter model{ramWarning.fallback_name ? ` (${ramWarning.fallback_name})` : ''}
                  </Button>
                )}
                <Button variant="secondary" size="lg" className="w-full" onClick={() => setRamWarning(null)}>
                  I'll close apps, try again
                </Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
