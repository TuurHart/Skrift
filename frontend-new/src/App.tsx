import { useState, useEffect, useCallback, useRef } from 'react'
import { Group, Panel, Separator } from 'react-resizable-panels'
import { api } from '@/api'
import { useSettings } from '@/hooks/useSettings'
import { useFiles, useFilesCache } from '@/hooks/useFiles'
import type { PipelineFile } from '@/types/pipeline'
import { Sidebar } from './features/Sidebar'
import { NoteDisplay } from './features/NoteDisplay'
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

  // ── Reset audio / karaoke state when the selected note changes ──
  useEffect(() => {
    setTokens([])
    setIsPlaying(false)
    setCurrentTime(0)
    setSeekTo(null)
  }, [selectedId])

  // Which file (if any) is mid-enhancement — derived from the one query. The
  // toolbar actions use it for running / locked-because-other / idle states
  // (only one MLX run at a time).
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

  // ── File update callback (actions hand back a full server object) ──
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

  // ── Tags change (add / remove from the properties block) ───
  const handleTagsChange = useCallback(async (tags: string[]) => {
    if (!file) return
    const id = file.id
    patchFile(id, { enhanced_tags: tags }) // optimistic so the chip updates instantly
    try {
      const updated = await api.setTags(id, tags)
      replaceFile(updated)
    } catch (err) { console.error('Tags change failed:', err) }
  }, [file, patchFile, replaceFile])

  // ── Significance save (review slider) ──────────────────────
  const handleSignificanceSave = useCallback(async (value: number) => {
    if (!file) return
    const id = file.id
    patchFile(id, { significance: value })
    try {
      const updated = await api.setSignificance(id, value)
      replaceFile(updated)
    } catch (err) { console.error('Significance save failed:', err) }
  }, [file, patchFile, replaceFile])

  // ── Resolve ambiguous names (review-time resolver strip) ───
  const handleResolveNames = useCallback(async (decisions: Array<{ alias: string; canonical: string; short: string }>) => {
    if (!file) return
    try {
      const updated = await api.resolveNames(file.id, decisions)
      replaceFile(updated)
    } catch (err) { console.error('Resolve names failed:', err) }
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
      <Group orientation="horizontal" className="flex-1 min-w-0 min-h-0">
      <Panel defaultSize="22%" minSize="15%" maxSize="34%" className="h-full w-full flex min-w-0">
      <Sidebar
        selectedId={selectedId}
        onSelectFile={setSelectedId}
        onSettingsOpen={() => setSettingsOpen(true)}
      />
      </Panel>
      <Separator className="w-px bg-border/[0.1] hover:bg-accent/50 transition-colors cursor-col-resize" />
      <Panel className="h-full w-full flex min-w-0">

      <NoteDisplay
        file={file}
        loading={fileLoading}
        settings={settings}
        isPlaying={isPlaying}
        currentTime={currentTime}
        tokens={tokens}
        seekTo={seekTo}
        runningEnhanceFile={runningEnhanceFile}
        onPlayPause={setIsPlaying}
        onTimeUpdate={setCurrentTime}
        onTranscribe={file ? handleTranscribe : undefined}
        onBodySave={handleBodySave}
        onTitleSave={handleTitleSave}
        onTagsChange={handleTagsChange}
        onSignificanceSave={handleSignificanceSave}
        onResolveNames={handleResolveNames}
        onFileUpdate={handleFileUpdate}
        onSelectFile={setSelectedId}
        onSeek={handleSeek}
      />
      </Panel>
      </Group>

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
