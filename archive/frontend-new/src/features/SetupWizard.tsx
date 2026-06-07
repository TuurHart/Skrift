import { useState, useEffect, useCallback } from 'react'
import { api, type DepsValidation, type DepsZip } from '@/api'
import { cn } from '@/lib/utils'
import { Check, X, FolderOpen, Loader2, ChevronRight, Archive } from 'lucide-react'

interface SetupWizardProps {
  onComplete: () => void
}

type Step = 'deps' | 'ready'
type DepsMode = 'detecting' | 'zip' | 'folder' | 'extracting' | 'done'

function CheckItem({ ok, label }: { ok: boolean; label: string }) {
  return (
    <div className="flex items-center gap-2.5 text-[13px]">
      {ok
        ? <Check size={14} className="text-green-400 shrink-0" />
        : <X size={14} className="text-red-400/60 shrink-0" />}
      <span className={ok ? 'text-text-primary' : 'text-text-muted'}>{label}</span>
    </div>
  )
}

function PathField({ label, value, onChange, placeholder }: { label: string; value: string; onChange: (v: string) => void; placeholder: string }) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-[11px] text-text-muted w-[120px] shrink-0 text-right">{label}</span>
      <input
        type="text"
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        className="flex-1 h-8 px-2.5 text-[12px] bg-white/[0.04] border border-border/[0.15] rounded-lg text-text-primary placeholder:text-text-muted/30 outline-none focus:border-accent/50 transition-colors font-mono"
      />
      <button
        onClick={async () => {
          const p = await window.electronAPI?.openFolderDialog()
          if (p) onChange(p)
        }}
        className="h-8 w-8 flex items-center justify-center bg-white/[0.06] hover:bg-white/[0.1] border border-border/[0.15] rounded-lg text-text-secondary transition-colors shrink-0"
      >
        <FolderOpen size={12} />
      </button>
    </div>
  )
}

export function SetupWizard({ onComplete }: SetupWizardProps) {
  const [step, setStep] = useState<Step>('deps')
  const [mode, setMode] = useState<DepsMode>('detecting')
  const [depsPath, setDepsPath] = useState('')
  const [validation, setValidation] = useState<DepsValidation | null>(null)
  const [zips, setZips] = useState<DepsZip[]>([])
  const [selectedZip, setSelectedZip] = useState<string>('')
  const [applying, setApplying] = useState(false)
  const [error, setError] = useState('')
  const [extractProgress, setExtractProgress] = useState('')
  // Step 2 fields
  const [author, setAuthor] = useState('')
  const [vaultPath, setVaultPath] = useState('')
  const [vaultAudioPath, setVaultAudioPath] = useState('')
  const [vaultAttachmentsPath, setVaultAttachmentsPath] = useState('')

  // Auto-detect on mount
  useEffect(() => {
    let cancelled = false
    api.detectDeps()
      .then(result => {
        if (cancelled) return
        if (result.found && result.path && result.components?.valid) {
          // Found a valid extracted folder
          setDepsPath(result.path)
          setValidation(result.components)
          setMode('done')
        } else if (result.zips && result.zips.length > 0) {
          // Found zip files
          setZips(result.zips)
          setSelectedZip(result.zips[0].path)
          setMode('zip')
          // Also store incomplete folder if found
          if (result.found && result.path) {
            setDepsPath(result.path)
            setValidation(result.components)
          }
        } else if (result.found && result.path) {
          // Found incomplete folder
          setDepsPath(result.path)
          setValidation(result.components)
          setMode('folder')
        } else {
          // Nothing found
          setMode('folder')
        }
      })
      .catch(() => { if (!cancelled) setMode('folder') })
    return () => { cancelled = true }
  }, [])

  const browseZip = useCallback(async () => {
    const files = await window.electronAPI?.openFileDialog({ accept: ['zip'], multiple: false })
    if (!files?.length) return
    setSelectedZip(files[0])
    setZips(prev => {
      const existing = prev.find(z => z.path === files[0])
      if (existing) return prev
      return [...prev, { path: files[0], name: files[0].split('/').pop() || 'archive.zip', size_mb: 0 }]
    })
    setMode('zip')
    setError('')
  }, [])

  const browseFolder = useCallback(async () => {
    const p = await window.electronAPI?.openFolderDialog()
    if (!p) return
    setDepsPath(p)
    setError('')
    try {
      const result = await api.validateDeps(p)
      setValidation(result)
      if (result.valid) setMode('done')
      else setMode('folder')
    } catch {
      setValidation(null)
    }
  }, [])

  const extractZip = useCallback(async () => {
    if (!selectedZip) return
    setMode('extracting')
    setExtractProgress('Extracting models... this may take a minute.')
    setError('')
    try {
      const result = await api.extractDepsZip(selectedZip)
      setDepsPath(result.path)
      setValidation(result.components)
      if (result.components.valid) {
        setMode('done')
      } else {
        setMode('folder')
        setError('Extracted but some components are missing.')
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Extraction failed')
      setMode('zip')
    } finally {
      setExtractProgress('')
    }
  }, [selectedZip])

  const applyAndContinue = useCallback(async () => {
    if (!depsPath) return
    setApplying(true)
    setError('')
    try {
      const result = await api.applyDeps(depsPath)
      setValidation(result.components)
      setStep('ready')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to apply')
    } finally {
      setApplying(false)
    }
  }, [depsPath])

  const finish = useCallback(async () => {
    try {
      if (author) await api.updateConfig('export.author', author)
      if (vaultPath) {
        await api.updateConfig('export.note_folder', vaultPath)
        await api.updateConfig('enhancement.obsidian.vault_path', vaultPath)
      }
      if (vaultAudioPath) await api.updateConfig('export.audio_folder', vaultAudioPath)
      if (vaultAttachmentsPath) await api.updateConfig('export.attachments_folder', vaultAttachmentsPath)
    } catch { /* non-critical */ }
    onComplete()
  }, [author, vaultPath, vaultAudioPath, vaultAttachmentsPath, onComplete])

  return (
    <div className="fixed inset-0 bg-black/80 backdrop-blur-md flex items-center justify-center z-[300] animate-fade-in">
      <div className="bg-surface border border-border/[0.12] rounded-2xl w-[520px] shadow-2xl overflow-hidden animate-modal-in">
        {/* Header */}
        <div className="px-8 pt-8 pb-2">
          <div className="text-[22px] font-semibold text-text-primary">Welcome to Skrift</div>
          <div className="text-[13px] text-text-secondary mt-1">
            Let's get everything set up. This only takes a moment.
          </div>
        </div>

        {/* Step indicator */}
        <div className="px-8 py-3 flex items-center gap-2 text-[11px] text-text-muted">
          <span className={cn('px-2 py-0.5 rounded-full', step === 'deps' ? 'bg-accent/15 text-accent font-medium' : 'bg-white/[0.06] text-text-muted')}>
            1. Dependencies
          </span>
          <ChevronRight size={12} className="text-text-muted/40" />
          <span className={cn('px-2 py-0.5 rounded-full', step === 'ready' ? 'bg-accent/15 text-accent font-medium' : 'bg-white/[0.06] text-text-muted')}>
            2. Ready
          </span>
        </div>

        <div className="px-8 pb-8">
          {/* ── Step 1: Dependencies ── */}
          {step === 'deps' && (
            <div className="space-y-4">
              {/* Detecting */}
              {mode === 'detecting' && (
                <div className="flex items-center gap-2 text-[13px] text-text-muted py-6">
                  <Loader2 size={14} className="animate-spin" />
                  Looking for dependencies...
                </div>
              )}

              {/* Extracting */}
              {mode === 'extracting' && (
                <div className="py-6 space-y-3">
                  <div className="flex items-center gap-2 text-[13px] text-text-primary">
                    <Loader2 size={14} className="animate-spin text-accent" />
                    {extractProgress || 'Extracting...'}
                  </div>
                  <div className="text-[11px] text-text-muted">
                    Unpacking models to ~/Skrift_dependencies
                  </div>
                </div>
              )}

              {/* Zip found */}
              {mode === 'zip' && (
                <>
                  <div className="text-[13px] text-text-secondary">
                    {zips.length > 0
                      ? 'Found a Skrift dependencies archive. Click to set up:'
                      : 'Select your Skrift dependencies zip file:'}
                  </div>

                  {/* Zip list */}
                  <div className="space-y-1.5">
                    {zips.map(z => (
                      <button
                        key={z.path}
                        onClick={() => setSelectedZip(z.path)}
                        className={cn(
                          'w-full flex items-center gap-3 p-3 rounded-lg text-left transition-colors',
                          selectedZip === z.path
                            ? 'bg-accent/10 border border-accent/30'
                            : 'bg-white/[0.03] border border-border/[0.08] hover:bg-white/[0.05]',
                        )}
                      >
                        <Archive size={16} className="text-accent shrink-0" />
                        <div className="min-w-0">
                          <div className="text-[13px] text-text-primary truncate">{z.name}</div>
                          {z.size_mb > 0 && (
                            <div className="text-[11px] text-text-muted">{z.size_mb > 1000 ? `${(z.size_mb / 1000).toFixed(1)} GB` : `${z.size_mb} MB`}</div>
                          )}
                        </div>
                      </button>
                    ))}
                  </div>

                  <div className="flex gap-2">
                    <button
                      onClick={extractZip}
                      disabled={!selectedZip}
                      className={cn(
                        'flex-1 h-10 rounded-lg text-[13px] font-medium transition-all',
                        selectedZip
                          ? 'bg-accent hover:bg-accent/90 text-white cursor-pointer'
                          : 'bg-white/[0.06] text-text-muted/50 cursor-not-allowed',
                      )}
                    >
                      Set up
                    </button>
                    <button
                      onClick={browseZip}
                      className="h-10 px-4 text-[12px] font-medium bg-white/[0.06] hover:bg-white/[0.1] border border-border/[0.15] rounded-lg text-text-secondary transition-colors"
                    >
                      Other zip...
                    </button>
                  </div>

                  <button
                    onClick={() => setMode('folder')}
                    className="text-[11px] text-text-muted hover:text-text-secondary transition-colors"
                  >
                    Or select an already-extracted folder →
                  </button>
                </>
              )}

              {/* Folder mode (manual or fallback) */}
              {mode === 'folder' && (
                <>
                  <div className="text-[13px] text-text-secondary">
                    Select your Skrift dependencies folder, or pick a zip file to extract.
                  </div>

                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={depsPath}
                      onChange={e => { setDepsPath(e.target.value); setValidation(null) }}
                      placeholder="~/Skrift_dependencies"
                      className="flex-1 h-9 px-3 text-[13px] bg-white/[0.04] border border-border/[0.15] rounded-lg text-text-primary placeholder:text-text-muted/40 outline-none focus:border-accent/50 transition-colors font-mono"
                    />
                    <button
                      onClick={browseFolder}
                      className="h-9 px-3 flex items-center gap-1.5 text-[12px] font-medium bg-white/[0.06] hover:bg-white/[0.1] border border-border/[0.15] rounded-lg text-text-secondary transition-colors"
                    >
                      <FolderOpen size={14} />
                    </button>
                    <button
                      onClick={browseZip}
                      className="h-9 px-3 flex items-center gap-1.5 text-[12px] font-medium bg-white/[0.06] hover:bg-white/[0.1] border border-border/[0.15] rounded-lg text-text-secondary transition-colors"
                    >
                      <Archive size={14} />
                    </button>
                  </div>

                  {validation && (
                    <div className="space-y-2 bg-white/[0.02] rounded-lg p-3 border border-border/[0.08]">
                      <CheckItem ok={validation.has_mlx_models} label={validation.mlx_model_names.length ? `MLX model: ${validation.mlx_model_names.join(', ')}` : 'MLX models'} />
                      <CheckItem ok={validation.has_parakeet} label="Parakeet transcription model" />
                      {validation.has_venv && <CheckItem ok={true} label="Python environment" />}
                    </div>
                  )}
                </>
              )}

              {/* Done detecting / extracted — show results */}
              {mode === 'done' && (
                <>
                  <div className="text-[13px] text-text-secondary">
                    Dependencies ready:
                  </div>
                  <div className="space-y-2 bg-white/[0.02] rounded-lg p-3 border border-border/[0.08]">
                    <CheckItem ok={true} label={validation?.mlx_model_names?.length ? `MLX model: ${validation.mlx_model_names.join(', ')}` : 'MLX models'} />
                    <CheckItem ok={true} label="Parakeet transcription model" />
                    {validation?.has_venv && <CheckItem ok={true} label="Python environment" />}
                    <div className="text-[11px] text-text-muted mt-1 font-mono truncate">
                      {depsPath.replace(/^\/Users\/[^/]+/, '~')}
                    </div>
                  </div>
                </>
              )}

              {error && <div className="text-[12px] text-red-400">{error}</div>}

              {/* Continue button (folder/done modes) */}
              {(mode === 'done' || (mode === 'folder' && validation?.valid)) && (
                <button
                  onClick={applyAndContinue}
                  disabled={applying}
                  className="w-full h-10 rounded-lg text-[13px] font-medium bg-accent hover:bg-accent/90 text-white transition-all cursor-pointer"
                >
                  {applying ? (
                    <span className="flex items-center justify-center gap-2">
                      <Loader2 size={14} className="animate-spin" /> Applying...
                    </span>
                  ) : 'Continue'}
                </button>
              )}
            </div>
          )}

          {/* ── Step 2: Ready ── */}
          {step === 'ready' && (
            <div className="space-y-5">
              <div className="space-y-2 bg-white/[0.02] rounded-lg p-3 border border-border/[0.08]">
                <CheckItem ok={true} label={`Dependencies: ${depsPath.replace(/^\/Users\/[^/]+/, '~')}`} />
                {validation?.mlx_model_names?.[0] && (
                  <CheckItem ok={true} label={`Enhancement model: ${validation.mlx_model_names[0]}`} />
                )}
                <CheckItem ok={true} label="Parakeet transcription: ready" />
              </div>

              {/* Author */}
              <div>
                <div className="text-[12px] font-medium text-text-secondary mb-1.5">Author name</div>
                <input
                  type="text"
                  value={author}
                  onChange={e => setAuthor(e.target.value)}
                  placeholder="Your name (added to exported notes)"
                  className="w-full h-9 px-3 text-[13px] bg-white/[0.04] border border-border/[0.15] rounded-lg text-text-primary placeholder:text-text-muted/40 outline-none focus:border-accent/50 transition-colors"
                />
              </div>

              {/* Obsidian vault paths */}
              <div>
                <div className="text-[12px] font-medium text-text-secondary mb-1">
                  Obsidian vault <span className="text-text-muted/60">(optional — configure later in Settings)</span>
                </div>
                <p className="text-[11px] text-text-muted mb-3">
                  Where exported notes and media go. Leave audio/attachments blank to use the notes folder.
                </p>
                <div className="space-y-2.5">
                  <PathField label="Notes folder" value={vaultPath} onChange={setVaultPath} placeholder="/path/to/vault/Notes" />
                  <PathField label="Voice memos folder" value={vaultAudioPath} onChange={setVaultAudioPath} placeholder="/path/to/vault/Audio" />
                  <PathField label="Images / attachments" value={vaultAttachmentsPath} onChange={setVaultAttachmentsPath} placeholder="/path/to/vault/Attachments" />
                </div>
              </div>

              <button
                onClick={finish}
                className="w-full h-10 rounded-lg text-[13px] font-medium bg-accent hover:bg-accent/90 text-white transition-all cursor-pointer"
              >
                Start using Skrift
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
