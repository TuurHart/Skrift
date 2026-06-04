import { useState, useRef, useEffect } from 'react'
import { cn } from '@/lib/utils'
import { formatDuration } from '@/lib/format'
import type { PipelineFile } from '@/types/pipeline'

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
}
function sourceLabel(t: string | null) {
  if (t === 'audio') return 'Voice memo'
  if (t === 'note') return 'Apple Note'
  return '—'
}

interface InlinePropProps {
  label: string
  value: string
  editable: boolean
  onSave?: (v: string) => void
}

function InlineProp({ label, value, editable, onSave }: InlinePropProps) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(value)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => { setDraft(value) }, [value])
  useEffect(() => { if (editing) inputRef.current?.focus() }, [editing])

  function commit() {
    setEditing(false)
    if (draft !== value) onSave?.(draft)
  }

  return (
    <>
      <span className="text-[11px] text-text-muted leading-[18px] capitalize">{label}</span>
      {editing ? (
        <input
          ref={inputRef}
          value={draft}
          onChange={e => setDraft(e.target.value)}
          onBlur={commit}
          onKeyDown={e => { if (e.key === 'Enter') commit(); if (e.key === 'Escape') { setDraft(value); setEditing(false) } }}
          className="text-[12px] bg-white/[0.04] border border-accent/40 rounded px-1.5 py-[2px] text-text-primary outline-none"
        />
      ) : (
        <span
          onClick={() => editable && setEditing(true)}
          className={cn(
            'text-[11px] leading-[18px] px-1 rounded border border-transparent transition-colors',
            value ? 'text-text-secondary' : 'text-text-muted',
            editable && 'hover:border-border/[0.15] cursor-text',
          )}
        >
          {value || '—'}
        </span>
      )}
    </>
  )
}

interface NotePropertiesProps {
  file: PipelineFile
  author?: string
  onTitleSave: (title: string) => void
  onTagRemove: (tag: string) => void
}

export function NoteProperties({ file, author, onTitleSave, onTagRemove }: NotePropertiesProps) {
  const transcribed = file.steps.transcribe === 'done'
  const [titleDraft, setTitleDraft] = useState(file.enhanced_title ?? '')
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => { setTitleDraft(file.enhanced_title ?? '') }, [file.id, file.enhanced_title])

  function handleTitleChange(v: string) {
    setTitleDraft(v)
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current)
    saveTimerRef.current = setTimeout(() => { if (v !== file.enhanced_title) onTitleSave(v) }, 800)
  }

  // Build metadata rows — always show all that have a value
  const meta = file.audioMetadata
  const weatherStr = meta?.phone_weather?.conditions != null && meta?.phone_weather?.temperature != null
    ? `${meta.phone_weather.conditions}, ${meta.phone_weather.temperature}${meta.phone_weather.temperatureUnit ?? '\u00B0C'}`
    : ''
  const pressureStr = meta?.phone_pressure?.hPa != null
    ? `${meta.phone_pressure.hPa} hPa${meta.phone_pressure.trend ? ` \u00B7 ${meta.phone_pressure.trend}` : ''}`
    : ''
  const daylightStr = meta?.phone_daylight?.sunrise && meta?.phone_daylight?.sunset
    ? `${meta.phone_daylight.sunrise} \u2013 ${meta.phone_daylight.sunset}${meta.phone_daylight.hoursOfLight != null ? ` (${meta.phone_daylight.hoursOfLight}h)` : ''}`
    : ''

  const rows: Array<{ key: string; label: string; value: string; editable: boolean }> = [
    { key: 'date', label: 'date', value: formatDate(file.uploadedAt), editable: false },
    { key: 'author', label: 'author', value: author ?? '', editable: false },
    { key: 'source', label: 'source', value: sourceLabel(file.source_type), editable: false },
    { key: 'duration', label: 'duration', value: formatDuration(meta?.duration), editable: false },
    { key: 'location', label: 'location', value: meta?.phone_location?.placeName ?? '', editable: false },
    { key: 'weather', label: 'weather', value: weatherStr, editable: false },
    { key: 'pressure', label: 'pressure', value: pressureStr, editable: false },
    { key: 'daylight', label: 'daylight', value: daylightStr, editable: false },
    { key: 'significance', label: 'significance', value: file.significance != null ? `${file.significance}` : '', editable: false },
  ].filter(r => r.value)

  return (
    <div className="mb-7">
      {/* Title */}
      {transcribed ? (
        <input
          value={titleDraft}
          placeholder={file.filename}
          onChange={e => handleTitleChange(e.target.value)}
          className="w-full text-[26px] font-bold tracking-tight bg-transparent border-none outline-none mb-3.5 leading-tight"
          style={{ color: titleDraft ? 'rgb(var(--color-text-primary))' : 'rgb(var(--color-text-muted))' }}
        />
      ) : (
        <h1 className="text-[26px] font-bold tracking-tight mb-3.5 text-text-muted leading-tight">{file.filename}</h1>
      )}

      {/* Metadata grid */}
      {rows.length > 0 && (
        <div className="grid mb-3.5" style={{ gridTemplateColumns: '90px 1fr', rowGap: 0, columnGap: 8 }}>
          {rows.map(r => (
            <InlineProp key={r.key} label={r.label} value={r.value} editable={r.editable} />
          ))}
        </div>
      )}

      {/* Tags */}
      {file.enhanced_tags && file.enhanced_tags.length > 0 && (
        <div className="flex flex-wrap gap-1.5 mb-3.5">
          {file.enhanced_tags.map(tag => (
            <span key={tag} className="inline-flex items-center gap-1 px-2.5 py-[3px] rounded-full text-[11px] font-medium bg-accent/15 text-accent">
              #{tag}
              <button onClick={() => onTagRemove(tag)} className="opacity-50 hover:opacity-100 text-[9px] leading-none transition-opacity">&times;</button>
            </span>
          ))}
        </div>
      )}
    </div>
  )
}
