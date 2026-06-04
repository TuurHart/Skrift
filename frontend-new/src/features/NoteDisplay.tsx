import type { PipelineFile } from '@/types/pipeline'
import type { AppSettings } from '@/hooks/useSettings'
import { PipelineBreadcrumb } from '@/components/PipelineBreadcrumb'
import { NoteProperties } from '@/components/NoteProperties'
import { NoteBody, getBestText } from '@/components/NoteBody'
import { KaraokeText } from '@/components/KaraokeText'
import { NoteToolbar } from '@/components/NoteToolbar'
import { NoteActions } from '@/components/NoteActions'
import { api } from '@/api'

// ── Helpers ─────────────────────────────────────────────────

interface Token {
  text: string
  start: number
  end: number
}

function formatBreadcrumbDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })
}

// ── Sub-states ──────────────────────────────────────────────

function Spinner() {
  return (
    <div className="flex items-center justify-center flex-1">
      <div className="w-5 h-5 rounded-full border-2 border-accent border-t-transparent animate-spin" />
    </div>
  )
}

function EmptyState() {
  return (
    <div className="flex flex-col items-center justify-center flex-1 text-text-muted gap-1">
      <span className="text-3xl select-none opacity-20">&#10022;</span>
      <p className="text-[14px] text-text-muted/80">Select a note to get started</p>
      <p className="text-[12px] text-text-muted/50">Your transcriptions will appear here</p>
    </div>
  )
}

// ── Component ───────────────────────────────────────────────

interface NoteDisplayProps {
  file: PipelineFile | null
  loading: boolean
  settings: AppSettings
  isPlaying: boolean
  currentTime: number
  tokens: Token[]
  seekTo?: { time: number; seq: number } | null
  runningEnhanceFile?: PipelineFile | null
  onPlayPause: (v: boolean) => void
  onTimeUpdate: (t: number) => void
  onTranscribe?: () => void
  onBodySave: (text: string, field: 'copyedit' | 'sanitised' | 'transcript') => void
  onTitleSave: (title: string) => void
  onTagsChange: (tags: string[]) => void
  onSignificanceSave: (value: number) => void
  onFileUpdate: (f: PipelineFile) => void
  onSelectFile?: (id: string) => void
  onSeek?: (time: number) => void
}

export function NoteDisplay({
  file,
  loading,
  settings,
  isPlaying,
  currentTime,
  tokens,
  seekTo,
  runningEnhanceFile,
  onPlayPause,
  onTimeUpdate,
  onTranscribe,
  onBodySave,
  onTitleSave,
  onTagsChange,
  onSignificanceSave,
  onFileUpdate,
  onSelectFile,
  onSeek,
}: NoteDisplayProps) {
  if (loading && !file) return <Spinner />
  if (!file) return <EmptyState />

  const karaokeActive = isPlaying && tokens.length > 0 && file.steps.transcribe === 'done'
  const bestText = getBestText(file) ?? ''
  const isAppleNote = file.source_type === 'note'
  const transcribeDone = file.steps.transcribe === 'done'
  const transcribeSkipped = file.steps.transcribe === 'skipped'
  const isCapture = file.source_type === 'capture'
  const hasAudio = !!file.audioMetadata?.duration
  const showTransport = transcribeDone && !isAppleNote && (!isCapture || hasAudio)
  // The action bar appears once there's something to review/export.
  const showActionBar = transcribeDone || transcribeSkipped || isAppleNote

  return (
    <div className="flex flex-col flex-1 min-w-0 min-h-0">
      <PipelineBreadcrumb
        steps={file.steps}
        date={formatBreadcrumbDate(file.uploadedAt)}
      />

      {/* Toolbar bar — pinned above the scroll area: audio transport (left) + actions (right) */}
      {showActionBar && (
        <div className="flex items-center gap-4 px-10 py-2.5 border-b border-border/[0.06] bg-surface/40 flex-none">
          {showTransport ? (
            <NoteToolbar
              src={api.getAudioUrl(file.id, 'processed')}
              isPlaying={isPlaying}
              currentTime={currentTime}
              seekTo={seekTo}
              onPlayPause={onPlayPause}
              onTimeUpdate={onTimeUpdate}
            />
          ) : (
            <div className="flex-1" />
          )}
          <NoteActions
            file={file}
            settings={settings}
            onFileUpdate={onFileUpdate}
            runningEnhanceFile={runningEnhanceFile}
            onSelectFile={onSelectFile}
          />
        </div>
      )}

      <div className="flex flex-col flex-1 min-h-0">
        {/* Note content area — scrollable */}
        <div className="overflow-y-auto relative flex-1">
          <div className="px-10 py-7">
            <NoteProperties
              file={file}
              author={settings.author || undefined}
              onTitleSave={onTitleSave}
              onTagsChange={onTagsChange}
              onSignificanceSave={onSignificanceSave}
            />

            {/* Photo from mobile capture */}
            {file.audioMetadata?.phone_photo && (
              <div className="mb-5">
                <img
                  src={`file://${file.audioMetadata.phone_photo}`}
                  alt="Capture photo"
                  className="w-full rounded-lg object-cover max-h-64"
                />
              </div>
            )}

            {/* Summary */}
            {file.enhanced_summary && (
              <div className="px-3.5 py-2.5 rounded-lg bg-white/[0.02] border border-border/[0.07] text-[13px] leading-relaxed text-text-secondary italic mb-5">
                {file.enhanced_summary}
              </div>
            )}

            {/* Shared content from capture items */}
            {(() => {
              const sc = file.audioMetadata?.shared_content
              if (!sc) return null
              return (
                <div className="mb-5">
                  {/* Shared URL */}
                  {sc.type === 'url' && sc.url && (
                    <a
                      href={sc.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="block px-4 py-3 rounded-lg bg-white/[0.03] border border-border/[0.1] hover:bg-white/[0.05] transition-colors no-underline"
                    >
                      <div className="text-[13px] font-medium text-text-primary mb-1">{sc.urlTitle || sc.url}</div>
                      <div className="text-[11px] text-accent">{(() => { try { return new URL(sc.url).hostname.replace(/^www\./, '') } catch { return sc.url } })()}</div>
                      {sc.urlDescription && (
                        <div className="text-[12px] text-text-muted mt-1.5 line-clamp-2">{sc.urlDescription}</div>
                      )}
                    </a>
                  )}

                  {/* Shared image */}
                  {sc.type === 'image' && file.audioMetadata?.shared_attachment && (
                    <img
                      src={`file://${file.audioMetadata.shared_attachment}`}
                      alt="Shared image"
                      className="w-full rounded-lg object-contain max-h-96"
                    />
                  )}

                  {/* Shared text */}
                  {sc.type === 'text' && sc.text && (
                    <div className="px-4 py-3 rounded-lg border-l-2 border-accent/40 bg-white/[0.02] text-[13px] text-text-secondary leading-relaxed whitespace-pre-wrap">
                      {sc.text}
                    </div>
                  )}

                  {/* Shared file/PDF */}
                  {sc.type === 'file' && file.audioMetadata?.shared_attachment && (
                    <a
                      href={`file://${file.audioMetadata.shared_attachment}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="flex items-center gap-3 px-4 py-3 rounded-lg bg-white/[0.03] border border-border/[0.1] hover:bg-white/[0.05] transition-colors no-underline"
                    >
                      <span className="text-xl">📄</span>
                      <div>
                        <div className="text-[13px] text-text-primary">{sc.fileName || 'File'}</div>
                        <div className="text-[11px] text-text-muted">Click to open</div>
                      </div>
                    </a>
                  )}
                </div>
              )
            })()}

            {/* NoteBody stays mounted to preserve edits; hidden during karaoke */}
            <div className={karaokeActive ? 'hidden' : undefined}>
              <NoteBody
                file={file}
                onTranscribe={onTranscribe}
                onBodySave={onBodySave}
              />
            </div>

            {/* Karaoke highlight on the body text — only while audio is playing.
                Same text + typography as the editor, so no reflow on play. */}
            {karaokeActive && (
              <KaraokeText
                text={bestText}
                tokens={tokens}
                currentTime={currentTime}
                onSeek={onSeek}
              />
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
