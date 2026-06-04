import { useState, useRef, useEffect } from 'react'
import { formatDuration } from '@/lib/format'
import { api } from '@/api'
import { Slider } from '@/components/ui/slider'
import { Command, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem } from '@/components/ui/command'
import type { PipelineFile } from '@/types/pipeline'

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
}
function sourceLabel(t: string | null) {
  if (t === 'audio') return 'Voice memo'
  if (t === 'note') return 'Apple Note'
  if (t === 'capture') return 'Capture'
  return '—'
}

// Normalise a free-typed tag the same way the backend would accept it.
function normaliseTag(raw: string): string {
  return raw.trim().toLowerCase().replace(/^#/, '').replace(/[^a-z0-9_\-/]/g, '_')
}

// ── Significance ────────────────────────────────────────────

function significanceLabel(v: number): string {
  if (v >= 0.67) return 'Significant'
  if (v >= 0.34) return 'Useful'
  return 'Passing'
}
function significanceColor(v: number): string {
  if (v >= 0.67) return '#f59e0b'
  if (v >= 0.34) return '#60a5fa'
  return '#6b7280'
}

function SignificanceSlider({ value, onSave }: { value: number | null; onSave: (v: number) => void }) {
  const [local, setLocal] = useState<number>(value ?? 0)
  useEffect(() => { setLocal(value ?? 0) }, [value])

  return (
    <div className="mb-3.5">
      <div className="flex items-center justify-between mb-2">
        <span className="text-[11px] text-text-muted">significance</span>
        <span className="text-[11px] font-semibold tabular-nums" style={{ color: significanceColor(local) }}>
          {local.toFixed(1)} · {significanceLabel(local)}
        </span>
      </div>
      <Slider
        value={[Math.round(local * 100)]}
        min={0}
        max={100}
        step={5}
        onValueChange={(v) => setLocal(v[0] / 100)}
        onValueCommit={(v) => onSave(v[0] / 100)}
      />
      <div className="flex justify-between text-[9.5px] text-text-muted mt-1.5 select-none">
        <span>passing</span><span>useful</span><span>significant</span>
      </div>
    </div>
  )
}

// ── Tags ────────────────────────────────────────────────────

function TagEditor({ tags, onChange }: { tags: string[]; onChange: (next: string[]) => void }) {
  const [adding, setAdding] = useState(false)
  const [query, setQuery] = useState('')
  const [whitelist, setWhitelist] = useState<string[]>([])
  const popRef = useRef<HTMLDivElement>(null)

  // Cached vault tag-name list for autocomplete. This reads the app's own cached
  // whitelist — it never scans the vault here (refresh lives in Settings).
  useEffect(() => {
    let cancelled = false
    api.getTagWhitelist()
      .then(r => { if (!cancelled) setWhitelist(r.tags ?? []) })
      .catch(() => { /* no whitelist yet — free-form add still works */ })
    return () => { cancelled = true }
  }, [])

  // Close the popover on outside click
  useEffect(() => {
    if (!adding) return
    function onDown(e: MouseEvent) {
      if (popRef.current && !popRef.current.contains(e.target as Node)) {
        setAdding(false); setQuery('')
      }
    }
    document.addEventListener('mousedown', onDown)
    return () => document.removeEventListener('mousedown', onDown)
  }, [adding])

  function addTag(raw: string) {
    const tag = normaliseTag(raw)
    if (!tag || tags.includes(tag)) { setQuery(''); setAdding(false); return }
    onChange([...tags, tag])
    setQuery(''); setAdding(false)
  }

  const q = normaliseTag(query)
  const candidates = whitelist
    .filter(t => !tags.includes(t))
    .filter(t => !q || t.includes(q))
    .slice(0, 8)
  const showCreate = q.length > 0 && !whitelist.includes(q) && !tags.includes(q)

  return (
    <div className="flex flex-wrap gap-1.5 items-center">
      {tags.map(tag => (
        <span key={tag} className="inline-flex items-center gap-1 px-2.5 py-[3px] rounded-full text-[11px] font-medium bg-accent/15 text-accent">
          #{tag}
          <button onClick={() => onChange(tags.filter(t => t !== tag))} className="opacity-50 hover:opacity-100 text-[9px] leading-none transition-opacity" aria-label={`Remove ${tag}`}>&times;</button>
        </span>
      ))}

      <div className="relative" ref={popRef}>
        <button
          onClick={() => setAdding(v => !v)}
          className="text-[11px] text-text-secondary bg-white/[0.04] border border-dashed border-border/[0.2] px-2.5 py-[3px] rounded-full hover:text-text-primary hover:border-border/[0.35] transition-colors"
        >
          + add tag
        </button>

        {adding && (
          <div className="absolute top-7 left-0 z-20 w-56 rounded-lg border border-border/[0.12] bg-surface shadow-xl shadow-black/40 animate-modal-in">
            <Command shouldFilter={false}>
              <CommandInput
                placeholder="Search or create tag…"
                value={query}
                onValueChange={setQuery}
                autoFocus
                onKeyDown={(e) => { if (e.key === 'Enter' && showCreate) { e.preventDefault(); addTag(query) } }}
              />
              <CommandList>
                {candidates.length === 0 && !showCreate && <CommandEmpty>No matching tags</CommandEmpty>}
                {candidates.length > 0 && (
                  <CommandGroup>
                    {candidates.map(t => (
                      <CommandItem key={t} value={t} onSelect={() => addTag(t)}>#{t}</CommandItem>
                    ))}
                  </CommandGroup>
                )}
                {showCreate && (
                  <CommandGroup>
                    <CommandItem value={`__create_${q}`} onSelect={() => addTag(query)}>
                      <span className="text-text-muted">Create</span> #{q}
                    </CommandItem>
                  </CommandGroup>
                )}
              </CommandList>
            </Command>
          </div>
        )}
      </div>
    </div>
  )
}

// ── Properties block ────────────────────────────────────────

interface NotePropertiesProps {
  file: PipelineFile
  author?: string
  onTitleSave: (title: string) => void
  onTagsChange: (tags: string[]) => void
  onSignificanceSave: (value: number) => void
}

export function NoteProperties({ file, author, onTitleSave, onTagsChange, onSignificanceSave }: NotePropertiesProps) {
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
    ? `${meta.phone_weather.conditions}, ${meta.phone_weather.temperature}${meta.phone_weather.temperatureUnit ?? '°C'}`
    : ''
  const pressureStr = meta?.phone_pressure?.hPa != null
    ? `${meta.phone_pressure.hPa} hPa${meta.phone_pressure.trend ? ` · ${meta.phone_pressure.trend}` : ''}`
    : ''
  const daylightStr = meta?.phone_daylight?.sunrise && meta?.phone_daylight?.sunset
    ? `${meta.phone_daylight.sunrise} – ${meta.phone_daylight.sunset}${meta.phone_daylight.hoursOfLight != null ? ` (${meta.phone_daylight.hoursOfLight}h)` : ''}`
    : ''

  const rows: Array<{ key: string; label: string; value: string }> = [
    { key: 'date', label: 'date', value: formatDate(file.uploadedAt) },
    { key: 'author', label: 'author', value: author ?? '' },
    { key: 'source', label: 'source', value: sourceLabel(file.source_type) },
    { key: 'duration', label: 'duration', value: formatDuration(meta?.duration) },
    { key: 'location', label: 'location', value: meta?.phone_location?.placeName ?? '' },
    { key: 'weather', label: 'weather', value: weatherStr },
    { key: 'pressure', label: 'pressure', value: pressureStr },
    { key: 'daylight', label: 'daylight', value: daylightStr },
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
            <div key={r.key} className="contents">
              <span className="text-[11px] text-text-muted leading-[19px] capitalize">{r.label}</span>
              <span className="text-[11px] leading-[19px] text-text-secondary">{r.value}</span>
            </div>
          ))}
        </div>
      )}

      {/* Significance slider */}
      <SignificanceSlider value={file.significance} onSave={onSignificanceSave} />

      {/* Tags */}
      <TagEditor tags={file.enhanced_tags ?? []} onChange={onTagsChange} />
    </div>
  )
}
