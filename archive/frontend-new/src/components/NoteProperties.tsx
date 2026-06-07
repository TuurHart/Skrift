import { useState, useRef, useEffect } from 'react'
import { cn } from '@/lib/utils'
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

function TagEditor({ tags, suggestions, onChange }: { tags: string[]; suggestions: string[]; onChange: (next: string[]) => void }) {
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

      {/* One-tap suggestions from the auto-run (vault matches + spoken #hashtags) */}
      {suggestions.map(s => (
        <button
          key={s}
          onClick={() => onChange([...tags, s])}
          className="text-[11px] text-text-secondary bg-white/[0.03] border border-dashed border-border/[0.2] px-2.5 py-[3px] rounded-full hover:text-accent hover:border-accent/40 hover:bg-accent/[0.06] transition-colors"
          title="Add suggested tag"
        >
          + #{s}
        </button>
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

// ── Two-title chooser ───────────────────────────────────────

function cleanFilename(name: string): string {
  return name.replace(/\.[^./\\]+$/, '').trim()
}

// Shown only when the LLM produced a suggestion (title_suggested) that differs
// from the recording's own name — then the user picks between them. The active
// card is editable so a custom title is still possible without losing either
// candidate (the suggestion stays stored in title_suggested).
function TitleChooser({ file, onTitleSave }: { file: PipelineFile; onTitleSave: (t: string) => void }) {
  const suggested = (file.title_suggested ?? '').trim()
  const original = cleanFilename(file.filename)
  const [draft, setDraft] = useState(file.enhanced_title ?? '')
  const [active, setActive] = useState<'suggested' | 'original'>(
    (file.enhanced_title ?? '').trim() === original ? 'original' : 'suggested',
  )
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Reset only when switching files — don't fight the user's live edits.
  useEffect(() => {
    setDraft(file.enhanced_title ?? '')
    setActive((file.enhanced_title ?? '').trim() === original ? 'original' : 'suggested')
  }, [file.id]) // eslint-disable-line react-hooks/exhaustive-deps

  function onEdit(v: string) {
    setDraft(v)
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => { if (v !== file.enhanced_title) onTitleSave(v) }, 700)
  }
  function pick(kind: 'suggested' | 'original', text: string) {
    setActive(kind); setDraft(text)
    if (timer.current) clearTimeout(timer.current)
    if (text !== file.enhanced_title) onTitleSave(text)
  }

  const cards: Array<{ kind: 'suggested' | 'original'; label: string; icon: string; value: string }> = [
    { kind: 'suggested', label: 'Suggested', icon: '✦', value: suggested },
    { kind: 'original', label: 'From recording', icon: '🎙', value: original },
  ]

  return (
    <div className="mb-3.5">
      <div className="text-[10px] uppercase tracking-[0.07em] text-text-muted mb-1.5">Title — pick one</div>
      <div className="flex gap-2 items-stretch">
        {cards.map(c => {
          const isActive = active === c.kind
          return (
            <div
              key={c.kind}
              onClick={() => { if (!isActive) pick(c.kind, c.value) }}
              className={cn(
                'flex-1 min-w-0 rounded-lg border px-3 py-2 relative transition-colors',
                isActive ? 'border-accent/55 bg-accent/[0.08]' : 'border-border/[0.1] hover:border-border/[0.25] cursor-pointer',
              )}
            >
              <div className={cn('text-[10px] mb-1 flex items-center gap-1.5', isActive ? 'text-accent' : 'text-text-muted')}>
                <span>{c.icon}</span>{c.label}
              </div>
              {isActive ? (
                <input
                  value={draft}
                  onChange={e => onEdit(e.target.value)}
                  className="w-full text-[16px] font-bold leading-tight tracking-tight bg-transparent outline-none text-text-primary"
                />
              ) : (
                <div className="text-[16px] font-bold leading-tight tracking-tight text-text-secondary line-clamp-2">{c.value || '—'}</div>
              )}
              <span
                className={cn('absolute top-2.5 right-3 w-3.5 h-3.5 rounded-full border-2', isActive ? 'border-accent' : 'border-border/[0.2]')}
                style={isActive ? { background: 'radial-gradient(circle, rgb(var(--color-accent)) 0 4px, transparent 5px)' } : undefined}
              />
            </div>
          )
        })}
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

  // Applied tags + auto-run suggestions (deduped, minus already-applied)
  const appliedTags = file.enhanced_tags ?? []
  const tagSuggestions = [...(file.tag_suggestions?.old ?? []), ...(file.tag_suggestions?.new ?? [])]
    .filter((t, i, a) => a.indexOf(t) === i)
    .filter(t => !appliedTags.includes(t))

  // Offer the chooser only when the LLM suggestion exists and differs from the
  // recording's own name; otherwise a single editable title.
  const suggested = (file.title_suggested ?? '').trim()
  const original = cleanFilename(file.filename)
  const showChooser = transcribed && !!suggested && !!original && suggested !== original

  return (
    <div className="mb-7">
      {/* Title */}
      {!transcribed ? (
        <h1 className="text-[26px] font-bold tracking-tight mb-3.5 text-text-muted leading-tight">{file.filename}</h1>
      ) : showChooser ? (
        <TitleChooser file={file} onTitleSave={onTitleSave} />
      ) : (
        <input
          value={titleDraft}
          placeholder={file.filename}
          onChange={e => handleTitleChange(e.target.value)}
          className="w-full text-[26px] font-bold tracking-tight bg-transparent border-none outline-none mb-3.5 leading-tight"
          style={{ color: titleDraft ? 'rgb(var(--color-text-primary))' : 'rgb(var(--color-text-muted))' }}
        />
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

      {/* Tags + one-tap suggestions */}
      <TagEditor tags={appliedTags} suggestions={tagSuggestions} onChange={onTagsChange} />
    </div>
  )
}
