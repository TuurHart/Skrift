import { useState, useEffect, useRef, useCallback } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Settings } from 'lucide-react'
import { cn } from '@/lib/utils'
import { api, API_BASE } from '@/api'
import { useFiles, useCurrentBatch, FILES_KEY, CURRENT_BATCH_KEY } from '@/hooks/useFiles'
import type { PipelineFile } from '@/types/pipeline'
import { StepDots } from '@/components/StepDots'
import { SystemStatus } from '@/components/SystemStatus'
import { formatDuration } from '@/lib/format'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogFooter, DialogTitle, DialogDescription } from '@/components/ui/dialog'

// ── Types ──────────────────────────────────────────────────

const FILTERS = ['All', 'Needs Work', 'Complete'] as const
type Filter = (typeof FILTERS)[number]

// ── Helpers ────────────────────────────────────────────────

function formatDate(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleDateString('en-GB', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  })
}

function isComplete(file: PipelineFile): boolean {
  const { transcribe, sanitise, enhance, export: exp } = file.steps
  return (
    transcribe === 'done' &&
    sanitise === 'done' &&
    enhance === 'done' &&
    exp === 'done'
  )
}

// ── Props ──────────────────────────────────────────────────

interface SidebarProps {
  selectedId: string | null
  onSelectFile: (id: string | null) => void
  onSettingsOpen?: () => void
}


// ── Component ──────────────────────────────────────────────

export function Sidebar({ selectedId, onSelectFile, onSettingsOpen }: SidebarProps) {
  const { data: files = [] } = useFiles()
  const { data: currentBatch } = useCurrentBatch()
  const qc = useQueryClient()
  const [filter, setFilter] = useState<Filter>('All')
  const [multiSelect, setMultiSelect] = useState(false)
  const [checked, setChecked] = useState<Set<string>>(new Set())
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null)
  const [uploading, setUploading] = useState(false)
  const [batchError, setBatchError] = useState<string | null>(null)
  const [batchProgress, setBatchProgress] = useState<{
    ids: string[]
    step: 'transcribe' | 'enhance'
    label: string
    batchId?: string
  } | null>(null)
  const [cancelling, setCancelling] = useState(false)
  const [batchCurrentFile, setBatchCurrentFile] = useState<{ fileId: string; step: string } | null>(null)
  const batchEsRef = useRef<EventSource | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  // ── Data loading & polling ──────────────────────────────

  // Files + current-batch come from the shared queries (which poll only while
  // work is in flight). These just nudge a refetch after an action.
  const loadFiles = useCallback(() => qc.invalidateQueries({ queryKey: FILES_KEY }), [qc])
  const syncCurrentBatch = useCallback(() => qc.invalidateQueries({ queryKey: CURRENT_BATCH_KEY }), [qc])

  // Restore the progress panel from the backend's current batch — covers a
  // sidebar remount while a run is going, or local state lagging behind.
  useEffect(() => {
    const b = currentBatch?.batch
    if (!currentBatch?.active || !b) return
    const fileIds = b.files.map(f => f.file_id)
    const stepKey = (b.type === 'enhance' || b.type === 'run') ? 'enhance' : 'transcribe'
    const label = b.type === 'run' ? 'Processing' : (stepKey === 'enhance' ? 'Enhancing' : 'Transcribing')
    setBatchProgress(prev => (prev?.batchId === b.batch_id ? prev : { ids: fileIds, step: stepKey, label, batchId: b.batch_id }))
  }, [currentBatch])

  // Close the run SSE on unmount.
  useEffect(() => () => { batchEsRef.current?.close(); batchEsRef.current = null }, [])

  // ── Prune stale checked IDs when files list changes ────
  useEffect(() => {
    if (checked.size === 0) return
    const validIds = new Set(files.map(f => f.id))
    const stale = Array.from(checked).filter(id => !validIds.has(id))
    if (stale.length > 0) setChecked(prev => { const n = new Set(prev); stale.forEach(id => n.delete(id)); return n })
  }, [files])

  // ── Batch progress derived from polled files ───────────
  const batchDone = batchProgress
    ? files.filter(f => {
        if (!batchProgress.ids.includes(f.id)) return false
        if (batchProgress.step === 'enhance') {
          // Count as done when LLM has run all steps — tag approval is a separate user action
          return !!(f.enhanced_title && f.enhanced_copyedit && f.enhanced_summary)
        }
        return f.steps[batchProgress.step] === 'done'
      }).length
    : 0
  const batchTotal = batchProgress?.ids.length ?? 0

  useEffect(() => {
    if (batchProgress && batchDone === batchTotal) {
      const t = setTimeout(() => {
        setBatchProgress(null)
        setBatchCurrentFile(null)
        batchEsRef.current?.close()
        batchEsRef.current = null
      }, 2000)
      return () => clearTimeout(t)
    }
  }, [batchProgress, batchDone, batchTotal])

  // ── Filtering & sorting ────────────────────────────────

  const sorted = [...files].sort((a, b) => {
    const da = a.lastModified ?? a.uploadedAt
    const db = b.lastModified ?? b.uploadedAt
    return new Date(db).getTime() - new Date(da).getTime()
  })

  const filtered = sorted.filter(f => {
    if (filter === 'Complete') return isComplete(f)
    if (filter === 'Needs Work') return !isComplete(f)
    return true
  })

  // ── Batch select ───────────────────────────────────────

  const lastCheckedIndex = useRef<number | null>(null)

  function toggleCheck(id: string, shiftKey = false) {
    const currentIndex = filtered.findIndex(f => f.id === id)

    if (shiftKey && lastCheckedIndex.current !== null && currentIndex !== -1) {
      // Range select: select everything between last clicked and current
      const start = Math.min(lastCheckedIndex.current, currentIndex)
      const end = Math.max(lastCheckedIndex.current, currentIndex)
      setChecked(prev => {
        const next = new Set(prev)
        for (let i = start; i <= end; i++) {
          next.add(filtered[i].id)
        }
        return next
      })
    } else {
      setChecked(prev => {
        const next = new Set(prev)
        if (next.has(id)) next.delete(id)
        else next.add(id)
        return next
      })
    }

    if (currentIndex !== -1) lastCheckedIndex.current = currentIndex
  }

  function exitMultiSelect() {
    setMultiSelect(false)
    setChecked(new Set())
  }

  // ── Delete ─────────────────────────────────────────────

  async function handleDelete(id: string) {
    try {
      await api.deleteFile(id)
      setDeleteConfirmId(null)
      // If we deleted the selected file, pick the next one or clear selection
      if (selectedId === id) {
        const remaining = files.filter(f => f.id !== id)
        if (remaining.length > 0) onSelectFile(remaining[0].id)
        else onSelectFile(null)
      }
      await loadFiles()
    } catch (err) {
      console.error('Delete failed:', err)
    }
  }

  async function handleDeleteChecked() {
    const ids = Array.from(checked)
    for (const id of ids) {
      try {
        await api.deleteFile(id)
      } catch (err) {
        console.error('Delete failed for', id, err)
      }
    }
    exitMultiSelect()
    await loadFiles()
  }

  // ── Upload ─────────────────────────────────────────────

  async function handleFileInputChange(e: React.ChangeEvent<HTMLInputElement>) {
    if (!e.target.files || e.target.files.length === 0) return
    const filesToUpload = Array.from(e.target.files)
    // Reset so re-selecting the same file works next time
    e.target.value = ''

    setUploading(true)
    try {
      const result = await api.uploadFiles(filesToUpload)
      await loadFiles()
      if (result.files.length > 0) {
        onSelectFile(result.files[0].id)
      }
    } catch (err) {
      console.error('Upload failed:', err)
    } finally {
      setUploading(false)
    }
  }

  async function onUploadClick() {
    if (window.electronAPI?.openUploadDialog) {
      const picked = await window.electronAPI.openUploadDialog()
      if (!picked) return
      const { files: filePaths, folders } = picked
      if (filePaths.length === 0 && folders.length === 0) return
      setUploading(true)
      try {
        // Convert file paths to File-like objects via fetch for non-Electron path
        // In Electron we pass paths directly via folderPaths; for plain files use the
        // hidden input fallback (openUploadDialog covers all cases via IPC).
        // Since Electron gives us paths (not File objects), send all as folder/path uploads.
        // Plain audio/md file paths are sent as single-item "folder" paths that the
        // backend handles as direct file paths when they're not directories.
        // Instead: re-fetch the files as Blobs so we can pass them as File objects.
        const fileObjects: File[] = []
        for (const fp of filePaths) {
          try {
            const res = await fetch(`file://${fp}`)
            const blob = await res.blob()
            const name = fp.split('/').pop() ?? fp
            fileObjects.push(new File([blob], name))
          } catch { /* skip unreadable */ }
        }
        const result = await api.uploadFiles(fileObjects, false, folders)
        await loadFiles()
        if (result.files.length > 0) onSelectFile(result.files[0].id)
      } catch (err) {
        console.error('Upload failed:', err)
      } finally {
        setUploading(false)
      }
    } else {
      fileInputRef.current?.click()
    }
  }

  // ── Drag & drop ────────────────────────────────────────

  const [dragOver, setDragOver] = useState(false)

  function onDragOver(e: React.DragEvent) {
    if (e.dataTransfer.types.includes('Files')) {
      e.preventDefault()
      setDragOver(true)
    }
  }

  function onDragLeave(e: React.DragEvent) {
    // Only clear if leaving the sidebar itself (not a child)
    if (!e.currentTarget.contains(e.relatedTarget as Node)) {
      setDragOver(false)
    }
  }

  async function onDrop(e: React.DragEvent) {
    e.preventDefault()
    setDragOver(false)

    const audioFiles: File[] = []
    const folderPaths: string[] = []

    const droppedFiles = Array.from(e.dataTransfer.files)

    const SUPPORTED = /\.(m4a|wav|mp3|mp4|mov|md)$/i

    // Try to get native file paths (Electron populates File.path)
    const allPaths = droppedFiles
      .map(f => (f as File & { path?: string }).path)
      .filter((p): p is string => !!p && p.length > 0)

    if (allPaths.length > 0 && window.electronAPI?.classifyPaths) {
      // Have native paths — classify into files vs folders
      const { files: filePaths, folders } = await window.electronAPI.classifyPaths(allPaths)
      folderPaths.push(...folders)

      for (const fp of filePaths) {
        if (SUPPORTED.test(fp)) {
          const f = droppedFiles.find(df => (df as File & { path?: string }).path === fp)
          if (f) audioFiles.push(f)
        }
      }
    } else {
      // Fallback: use webkitGetAsEntry for folder detection + File objects for uploads
      const items = Array.from(e.dataTransfer.items)
      items.forEach((item) => {
        const entry = item.webkitGetAsEntry?.()
        const file = item.getAsFile()
        if (!file) return
        if (entry?.isDirectory) {
          const electronPath = (file as File & { path?: string }).path
          if (electronPath) {
            folderPaths.push(electronPath)
          } else {
            // Folder path unavailable in dev mode — open native picker as fallback
            console.info('[Drop] folder detected, opening native picker for path access')
            window.electronAPI?.openUploadDialog?.().then((picked: { files: string[]; folders: string[] } | null) => {
              if (!picked || (picked.files.length === 0 && picked.folders.length === 0)) return
              const fallbackAudio: File[] = []
              const fallbackFolders = [...picked.folders]
              // Upload via the same path as the + button
              api.uploadFiles(fallbackAudio, false, fallbackFolders).then(() => loadFiles())
            })
            return // early return — the dialog will handle the upload
          }
        } else if (SUPPORTED.test(file.name)) {
          audioFiles.push(file)
        }
      })
    }

    if (audioFiles.length === 0 && folderPaths.length === 0) return
    setUploading(true)
    try {
      const result = await api.uploadFiles(audioFiles, false, folderPaths)
      await loadFiles()
      if (result.files.length > 0) onSelectFile(result.files[0].id)
    } catch (err) {
      console.error('Upload failed:', err)
    } finally {
      setUploading(false)
    }
  }

  // ── Render ─────────────────────────────────────────────

  const deleteTarget = files.find(f => f.id === deleteConfirmId)

  return (
    <aside
      className={cn(
        'w-[280px] min-w-[280px] h-full flex flex-col bg-surface border-r border-border/[0.07] relative transition-colors',
        dragOver && 'bg-accent/[0.08]',
      )}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={e => void onDrop(e)}
    >
      {dragOver && (
        <div className="absolute inset-2 z-10 rounded-xl border-2 border-dashed border-accent/50 pointer-events-none flex items-center justify-center">
          <span className="text-[12px] text-accent font-medium">Drop to upload</span>
        </div>
      )}

      {/* ── Header ── */}
      <div className="px-4 pt-4 pb-3 border-b border-border/[0.07]" style={{ WebkitAppRegion: 'drag' } as React.CSSProperties}>

        {/* Logo row */}
        <div className="flex items-center justify-between mb-3">
          <img src="./app-icon.png" alt="Skrift" className="w-6 h-6 select-none" draggable={false} />

          <div className="flex items-center gap-1" style={{ WebkitAppRegion: 'no-drag' } as React.CSSProperties}>
            <SystemStatus />

            <button
              onClick={() => {
                setMultiSelect(v => !v)
                setChecked(new Set())
              }}
              className={cn(
                'px-2 py-[5px] text-xs rounded-md transition-colors',
                multiSelect
                  ? 'bg-accent/15 text-accent'
                  : 'bg-white/[0.05] hover:bg-white/[0.08] text-text-secondary',
              )}
            >
              {multiSelect ? 'Cancel' : 'Select'}
            </button>

            <button
              onClick={onSettingsOpen}
              className="p-[5px] rounded-md bg-white/[0.05] hover:bg-white/[0.08] text-text-secondary transition-colors"
              aria-label="Settings"
            >
              <Settings size={13} />
            </button>

            <button
              onClick={() => void onUploadClick()}
              disabled={uploading}
              className="px-[10px] py-[5px] text-xs font-medium rounded-md bg-accent text-white hover:bg-accent/90 hover:shadow-md hover:shadow-accent/20 active:scale-[0.98] transition-all duration-150 disabled:opacity-60"
            >
              {uploading ? '…' : '+ Upload'}
            </button>
          </div>
        </div>

        {/* Filter chips */}
        <div className="flex gap-1" style={{ WebkitAppRegion: 'no-drag' } as React.CSSProperties}>
          {FILTERS.map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={cn(
                'px-[10px] py-1 text-xs rounded-md transition-colors',
                filter === f
                  ? 'bg-accent/15 border border-accent/20 text-accent'
                  : 'border border-transparent text-text-secondary hover:text-text-primary hover:bg-white/[0.05]',
              )}
            >
              {f}
            </button>
          ))}
        </div>
      </div>

      {/* ── Note list ── */}
      <div className="flex-1 overflow-y-auto p-[6px]">
        {filtered.length === 0 && (
          <div className="text-center py-8 px-4">
            <div className="text-text-muted text-[13px]">No notes yet</div>
            <div className="text-text-muted/60 text-[11px] mt-1">Drop files here or click Upload</div>
          </div>
        )}

        {filtered.map(file => {
          const isSelected = !multiSelect && selectedId === file.id
          const isChecked = checked.has(file.id)
          const sc = file.audioMetadata?.shared_content
          const displayName = file.enhanced_title
            ?? (sc?.type === 'url' ? (sc.urlTitle || (() => { try { return new URL(sc.url || '').hostname } catch { return sc.url } })() || file.filename)
              : sc?.type === 'text' ? ((sc.text || '').slice(0, 40).replace(/\n/g, ' ') || 'Text capture')
              : sc?.type === 'image' ? 'Image capture'
              : sc?.type === 'file' ? (sc.fileName?.replace(/\.[^.]+$/, '') || 'File')
              : file.filename)
          const duration = formatDuration(file.audioMetadata?.duration)

          return (
            <div
              key={file.id}
              onClick={(e) => {
                if (multiSelect) toggleCheck(file.id, e.shiftKey)
                else onSelectFile(file.id)
              }}
              className={cn(
                'group/note relative px-3 py-[10px] rounded-lg cursor-pointer mb-1',
                'border transition-colors',
                isSelected
                  ? 'bg-accent/15 border-accent/20 shadow-sm shadow-accent/10'
                  : 'bg-white/[0.02] border-transparent hover:bg-white/[0.05] hover:shadow-sm',
              )}
            >
              <div className="flex items-start gap-2">
                {/* Batch checkbox */}
                {multiSelect && (
                  <div
                    onClick={e => { e.stopPropagation(); toggleCheck(file.id, e.shiftKey) }}
                    className={cn(
                      'mt-0.5 w-4 h-4 rounded border-2 shrink-0 flex items-center justify-center transition-colors cursor-pointer',
                      isChecked
                        ? 'bg-accent border-accent'
                        : 'border-border/[0.3] hover:border-border/[0.5]',
                    )}
                  >
                    {isChecked && (
                      <svg viewBox="0 0 12 12" className="w-2.5 h-2.5 text-white" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M2 6l3 3 5-5" />
                      </svg>
                    )}
                  </div>
                )}

                <div className="flex-1 min-w-0">
                  {/* Title row */}
                  <div className="flex items-start gap-1 mb-1">
                    <span className="flex-1 text-[13px] font-medium truncate leading-tight">
                      {displayName}
                    </span>

                    {/* Delete button — visible on hover */}
                    {!multiSelect && (
                      <button
                        className="opacity-0 group-hover/note:opacity-100 shrink-0 text-text-muted hover:text-destructive transition-all text-[11px] px-1 py-px -mt-px"
                        onClick={e => {
                          e.stopPropagation()
                          setDeleteConfirmId(file.id)
                        }}
                        aria-label="Delete note"
                        title="Delete note"
                      >
                        🗑
                      </button>
                    )}
                  </div>

                  {/* Meta row */}
                  <div className="flex items-center justify-between">
                    <span className="text-[12px] text-text-muted leading-none">
                      {formatDate(file.uploadedAt)}
                      {duration && ` · ${duration}`}
                    </span>
                    <StepDots steps={file.steps} />
                  </div>
                </div>
              </div>
            </div>
          )
        })}
      </div>

      {/* ── Batch error (visible regardless of selection state) ── */}
      {batchError && !batchProgress && (
        <div className="px-3 py-2 border-t border-border/[0.07] bg-destructive/[0.08] flex items-start justify-between gap-2">
          <div className="text-xs text-destructive leading-snug">{batchError}</div>
          <button
            onClick={() => setBatchError(null)}
            className="text-[10px] text-text-muted hover:text-text-primary px-1"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* ── Batch progress bar ── */}
      {batchProgress && (() => {
        const stepLabels: Record<string, string> = {
          title: 'Generating title',
          copy_edit: 'Editing',
          copyedit: 'Editing',
          summary: 'Summarizing',
          tags: 'Choosing tags',
          transcribe: 'Transcribing',
        }
        const currentFilename = batchCurrentFile
          ? files.find(f => f.id === batchCurrentFile.fileId)?.filename
          : undefined
        const currentStepLabel = batchCurrentFile
          ? stepLabels[batchCurrentFile.step] ?? batchCurrentFile.step.replace('_', ' ')
          : undefined
        const pct = batchTotal > 0 ? (batchDone / batchTotal) * 100 : 0
        const canCancel = !!batchProgress.batchId && batchDone < batchTotal
        return (
          <div className="px-4 py-3 border-t border-border/[0.07] bg-accent/[0.10]">
            <div className="flex items-baseline justify-between mb-2 gap-2">
              <span className="text-sm text-accent font-medium truncate">
                {batchProgress.label} {batchDone} of {batchTotal}
              </span>
              <div className="flex items-center gap-2 shrink-0">
                <span className="text-xs text-text-secondary tabular-nums">
                  {Math.round(pct)}%
                </span>
                {canCancel && (
                  <button
                    onClick={async () => {
                      if (!batchProgress.batchId || cancelling) return
                      setCancelling(true)
                      try {
                        await api.cancelBatch(batchProgress.batchId)
                        setBatchProgress(null)
                        setBatchCurrentFile(null)
                        batchEsRef.current?.close()
                        batchEsRef.current = null
                      } catch (err: unknown) {
                        setBatchError(`Cancel failed: ${err instanceof Error ? err.message : String(err)}`)
                      } finally {
                        setCancelling(false)
                      }
                    }}
                    disabled={cancelling}
                    className="text-[10px] px-2 py-0.5 rounded bg-white/[0.08] hover:bg-white/[0.14] text-text-secondary hover:text-text-primary disabled:opacity-50 transition-colors"
                  >
                    {cancelling ? 'Cancelling…' : 'Cancel'}
                  </button>
                )}
              </div>
            </div>
            {currentStepLabel && (
              <div className="text-xs text-text-secondary mb-2 truncate">
                {currentStepLabel}
                {currentFilename && (
                  <span className="text-text-muted"> · {currentFilename}</span>
                )}
              </div>
            )}
            <div className="h-1.5 rounded-full bg-border/30 overflow-hidden">
              <div
                className="h-full bg-accent rounded-full transition-all duration-500"
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>
        )
      })()}

      {/* ── Quick-select bar ── */}
      {multiSelect && (
        <div className="px-3 py-2 border-t border-border/[0.07] flex gap-1 flex-wrap">
          <button
            onClick={() => {
              const ids = filtered.filter(f => f.steps.transcribe !== 'done').map(f => f.id)
              setChecked(new Set(ids))
            }}
            className="px-2 py-1 text-[10px] rounded-md bg-white/[0.05] border border-border/[0.12] text-text-secondary hover:text-text-primary transition-colors"
          >
            Not transcribed
          </button>
          <button
            onClick={() => {
              const ids = filtered.filter(f => f.steps.transcribe === 'done' && !(f.enhanced_title && f.enhanced_copyedit && f.enhanced_summary)).map(f => f.id)
              setChecked(new Set(ids))
            }}
            className="px-2 py-1 text-[10px] rounded-md bg-white/[0.05] border border-border/[0.12] text-text-secondary hover:text-text-primary transition-colors"
          >
            Not enhanced
          </button>
          <button
            onClick={() => setChecked(new Set(filtered.map(f => f.id)))}
            className="px-2 py-1 text-[10px] rounded-md bg-white/[0.05] border border-border/[0.12] text-text-secondary hover:text-text-primary transition-colors"
          >
            All
          </button>
          {checked.size > 0 && (
            <button
              onClick={() => setChecked(new Set())}
              className="px-2 py-1 text-[10px] rounded-md bg-white/[0.05] border border-border/[0.12] text-text-muted hover:text-text-primary transition-colors"
            >
              Clear
            </button>
          )}
        </div>
      )}

      {/* ── Batch action bar ── */}
      {multiSelect && checked.size > 0 && (
        <div className="p-3 border-t border-border/[0.07] bg-accent/[0.08]">
          <div className="text-xs text-accent font-medium mb-2">
            {checked.size} selected
          </div>
          {batchError && (
            <div className="text-xs text-destructive mb-2 leading-snug">{batchError}</div>
          )}
          <div className="flex gap-1 flex-wrap">
            <button
              onClick={async () => {
                const ids = Array.from(checked)
                exitMultiSelect()
                setBatchError(null)
                // One Process action runs the whole pipeline to Ready for Review.
                setBatchProgress({ ids, step: 'enhance', label: 'Processing' })
                // Subscribe to the run's SSE so the progress panel can show the
                // current step + filename (transcribe → enhance steps).
                batchEsRef.current?.close()
                const es = new EventSource(`${API_BASE}/api/batch/enhance/stream`)
                batchEsRef.current = es
                es.addEventListener('start', (e) => {
                  try {
                    const d = JSON.parse(e.data)
                    if (d.file_id) setBatchCurrentFile({ fileId: d.file_id, step: d.step || '' })
                  } catch { /* ignore */ }
                })
                es.addEventListener('done', () => setBatchCurrentFile(null))
                try {
                  const resp = await api.startRun(ids)
                  setBatchProgress(prev => prev && { ...prev, batchId: resp.batch?.batch_id })
                  await loadFiles()
                  void syncCurrentBatch()
                } catch (err: unknown) {
                  const msg = err instanceof Error ? err.message : String(err)
                  if (msg.includes('already processed')) {
                    setBatchError('All selected files are already processed (Ready for review).')
                  } else if (msg.includes('already running')) {
                    setBatchError('Another run is still going. Cancel it from the progress panel below, then try again.')
                    void syncCurrentBatch()
                  } else {
                    setBatchError(msg)
                  }
                  setBatchProgress(null)
                  es.close()
                  batchEsRef.current = null
                }
              }}
              className="px-[10px] py-[5px] text-xs rounded-md bg-accent text-white font-medium hover:bg-accent/90 transition-colors"
            >
              Process
            </button>
            <button
              onClick={() => void handleDeleteChecked()}
              className="px-[10px] py-[5px] text-xs rounded-md bg-destructive text-white font-medium hover:opacity-90 transition-opacity"
            >
              Delete
            </button>
          </div>
        </div>
      )}

      {/* ── Hidden file input ── */}
      <input
        ref={fileInputRef}
        type="file"
        multiple
        accept=".m4a,.wav,.mp3,.md"
        className="hidden"
        onChange={e => void handleFileInputChange(e)}
      />

      {/* ── Delete confirmation modal ── */}
      <Dialog open={!!deleteConfirmId} onOpenChange={(o) => { if (!o) setDeleteConfirmId(null) }}>
        <DialogContent className="max-w-xs">
          <DialogHeader>
            <DialogTitle>Delete note?</DialogTitle>
            <DialogDescription>
              <span className="font-medium text-text-primary">
                {deleteTarget?.enhanced_title ?? deleteTarget?.filename}
              </span>{' '}
              will be permanently deleted.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setDeleteConfirmId(null)}>Cancel</Button>
            <Button variant="destructive" onClick={() => deleteConfirmId && void handleDelete(deleteConfirmId)}>Delete</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </aside>
  )
}
