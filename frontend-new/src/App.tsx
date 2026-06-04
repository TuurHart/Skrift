import { useState, useEffect, useCallback, useRef } from 'react'
import { api } from '@/api'
import { useSettings } from '@/hooks/useSettings'
import { useFiles, useFilesCache } from '@/hooks/useFiles'
import type { PipelineFile } from '@/types/pipeline'
import { extractYamlTitle, injectEmbedLines } from '@/components/ExportPreview'
import { Sidebar } from './features/Sidebar'
import { NoteDisplay } from './features/NoteDisplay'
import { Inspector } from './features/Inspector'
import { Settings } from './features/Settings'
import { SetupWizard } from './features/SetupWizard'
import { FindBar } from '@/components/FindBar'
import { Toaster } from '@/components/ui/sonner'

interface Token {
  text: string
  start: number
  end: number
}

export default function App() {
  // ── Selection + file state (one query is the single source of truth) ──
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const { data: files = [], isLoading: filesLoading } = useFiles()
  const { replaceFile, patchFile, invalidateFiles } = useFilesCache()
  const file = selectedId ? (files.find(f => f.id === selectedId) ?? null) : null
  const fileLoading = filesLoading && !!selectedId && !file

  // ── Audio / karaoke state (lifted so NoteDisplay can karaoke-sync) ──
  const [isPlaying, setIsPlaying] = useState(false)
  const [currentTime, setCurrentTime] = useState(0)
  const [tokens, setTokens] = useState<Token[]>([])
  const [seekTo, setSeekTo] = useState<{ time: number; seq: number } | null>(null)
  const seekSeqRef = useRef(0)

  // ── Export preview state (inline in NoteDisplay) ────────────
  const [exportPreviewContent, setExportPreviewContent] = useState<string | null>(null)

  const handleToggleExportPreview = useCallback(async () => {
    if (exportPreviewContent) {
      setExportPreviewContent(null)
      return
    }
    if (!file) return
    try {
      const compiled = await api.getCompiledMarkdown(file.id)
      let md = compiled.content
      const title = extractYamlTitle(md)
      const includeAudio = file.include_audio_in_export ?? false
      const hasPhoto = !!file.audioMetadata?.phone_photo
      if (title && (includeAudio || hasPhoto)) {
        md = injectEmbedLines(md, title, hasPhoto, includeAudio)
      }
      setExportPreviewContent(md)
    } catch (err) { console.error('Failed to load export preview:', err) }
  }, [file, exportPreviewContent])

  const handleSeek = useCallback((time: number) => {
    seekSeqRef.current += 1
    setSeekTo({ time, seq: seekSeqRef.current })
    setIsPlaying(true) // start playback on word click
  }, [])

  // ── Settings ───────────────────────────────────────────────
  const { settings, update: updateSettings, setTheme, defaultPrompts } = useSettings()
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [showWizard, setShowWizard] = useState(false)

  // Cmd+, from Electron menu also opens settings
  useEffect(() => {
    const cleanup = window.electronAPI?.onMenuPreferences(() => setSettingsOpen(true))
    return cleanup
  }, [])

  // First-launch detection: check if backend is reachable and deps configured
  useEffect(() => {
    let cancelled = false
    async function checkSetup() {
      try {
        const h = await api.getSystemHealth()
        if (cancelled) return
        const parakeetOk = h?.transcription_modules?.parakeet?.available === true
        if (!parakeetOk) {
          setShowWizard(true)
          return
        }
        // Also check if dependencies folder is actually configured
        const { config } = await api.getConfig()
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const depsFolder = ((config as any)?.dependencies_folder as string | undefined)
        if (!depsFolder) {
          setShowWizard(true)
        }
      } catch {
        // Backend not reachable — likely first launch or deps missing
        if (!cancelled) {
          setShowWizard(true)
        }
      }
    }
    void checkSetup()
    return () => { cancelled = true }
  }, [])

  // ── Reset audio / karaoke / preview state when the selected note changes ──
  useEffect(() => {
    setTokens([])
    setIsPlaying(false)
    setCurrentTime(0)
    setSeekTo(null)
    setExportPreviewContent(null)
  }, [selectedId])

  // Which file (if any) is mid-enhancement — derived from the one query. The
  // Inspector uses it for running / locked-because-other / idle states (only
  // one MLX run at a time).
  const runningEnhanceFile = files.find(f => f.steps.enhance === 'processing') ?? null

  // ── Load word timings when transcription is done ───────────
  useEffect(() => {
    if (!file || file.steps.transcribe !== 'done' || file.source_type === 'note') return
    let cancelled = false
    api.getTimeline(file.id)
      .then(r => { if (!cancelled) setTokens(r.tokens) })
      .catch(() => { /* no timings available */ })
    return () => { cancelled = true }
  }, [file?.id, file?.steps.transcribe])

  // ── File update callback (Inspector hands back a full server object) ──
  const handleFileUpdate = useCallback((updated: PipelineFile) => {
    replaceFile(updated)
  }, [replaceFile])

  // ── Body save ──────────────────────────────────────────────
  const handleBodySave = useCallback(async (text: string, field: 'copyedit' | 'sanitised' | 'transcript') => {
    if (!file) return
    const id = file.id
    // Optimistically write the edit into the cache so an in-flight refetch
    // can't revert it; then persist and re-sync derived fields.
    patchFile(id, field === 'copyedit' ? { enhanced_copyedit: text } : field === 'sanitised' ? { sanitised: text } : { transcript: text })
    try {
      if (field === 'copyedit') await api.setCopyedit(id, text)
      else if (field === 'sanitised') await api.updateSanitised(id, text)
      else await api.updateTranscript(id, text)
      invalidateFiles()
    } catch (err) { console.error('Body save failed:', err) }
  }, [file, patchFile, invalidateFiles])

  // ── Title save ─────────────────────────────────────────────
  const handleTitleSave = useCallback(async (title: string) => {
    if (!file) return
    try {
      const updated = await api.setTitle(file.id, title)
      replaceFile(updated)
    } catch (err) { console.error('Title save failed:', err) }
  }, [file, replaceFile])

  // ── Tag remove ─────────────────────────────────────────────
  const handleTagRemove = useCallback(async (tag: string) => {
    if (!file) return
    const updated_tags = (file.enhanced_tags ?? []).filter(t => t !== tag)
    try {
      const updated = await api.setTags(file.id, updated_tags)
      replaceFile(updated)
    } catch (err) { console.error('Tag remove failed:', err) }
  }, [file, replaceFile])

  // ── Transcribe trigger (from NoteBody placeholder) ─────────
  const handleTranscribe = useCallback(async () => {
    if (!file) return
    try {
      await api.startTranscription(file.id)
      invalidateFiles() // refetch picks up 'processing' → live polling kicks in
    } catch (err) { console.error('Transcription start failed:', err) }
  }, [file, invalidateFiles])

  return (
    <div className="flex h-screen overflow-hidden bg-bg text-text-primary font-sans">
      <FindBar />
      <Sidebar
        selectedId={selectedId}
        onSelectFile={setSelectedId}
        onSettingsOpen={() => setSettingsOpen(true)}
      />

      <NoteDisplay
        file={file}
        loading={fileLoading}
        settings={settings}
        isPlaying={isPlaying}
        currentTime={currentTime}
        tokens={tokens}
        seekTo={seekTo}
        exportPreviewContent={exportPreviewContent}
        onPlayPause={setIsPlaying}
        onTimeUpdate={setCurrentTime}
        onTranscribe={file ? handleTranscribe : undefined}
        onBodySave={handleBodySave}
        onTitleSave={handleTitleSave}
        onTagRemove={handleTagRemove}
        onSeek={handleSeek}
      />

      {file && (
        <Inspector
          file={file}
          settings={settings}
          onFileUpdate={handleFileUpdate}
          exportPreviewActive={!!exportPreviewContent}
          onToggleExportPreview={handleToggleExportPreview}
          runningEnhanceFile={runningEnhanceFile}
          onSelectFile={setSelectedId}
        />
      )}

      {showWizard && (
        <SetupWizard onComplete={() => setShowWizard(false)} />
      )}

      {settingsOpen && (
        <Settings
          settings={settings}
          onUpdate={updateSettings}
          setTheme={setTheme}
          defaultPrompts={defaultPrompts}
          onClose={() => setSettingsOpen(false)}
        />
      )}

      <Toaster />
    </div>
  )
}
