import { useState, useEffect } from 'react'
import { Plus, Trash2, ChevronDown, ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import { api, type Person } from '@/api'

function emptyPerson(): Person {
  return { canonical: '', aliases: [], short: '' }
}

function PersonEditor({
  person,
  onChange,
  onDelete,
}: {
  person: Person
  onChange: (p: Person) => void
  onDelete: () => void
}) {
  const [expanded, setExpanded] = useState(false)
  const [aliasInput, setAliasInput] = useState('')

  const display = person.canonical.replace(/\[\[|\]\]/g, '') || 'New Person'

  function addAlias() {
    const v = aliasInput.trim()
    if (!v) return
    onChange({ ...person, aliases: [...person.aliases, v] })
    setAliasInput('')
  }

  function removeAlias(a: string) {
    onChange({ ...person, aliases: person.aliases.filter(x => x !== a) })
  }

  return (
    <div className="border border-border/[0.1] rounded-lg overflow-hidden">
      <div
        className="flex items-center gap-2.5 px-3.5 py-2.5 cursor-pointer hover:bg-white/[0.02] transition-colors"
        onClick={() => setExpanded(e => !e)}
      >
        {expanded ? <ChevronDown size={13} className="text-text-muted shrink-0" /> : <ChevronRight size={13} className="text-text-muted shrink-0" />}
        <span className="flex-1 text-[13px] font-medium text-text-primary truncate">{display}</span>
        {person.aliases.length > 0 && (
          <span className="text-[10px] text-text-muted">{person.aliases.length} alias{person.aliases.length !== 1 ? 'es' : ''}</span>
        )}
        <button
          onClick={e => { e.stopPropagation(); onDelete() }}
          className="opacity-40 hover:opacity-100 hover:text-destructive transition-all p-0.5"
        >
          <Trash2 size={13} />
        </button>
      </div>

      {expanded && (
        <div className="px-3.5 pb-3.5 pt-1.5 space-y-3 border-t border-border/[0.07] bg-white/[0.01]">
          <div className="space-y-1">
            <label className="text-[10px] text-text-muted uppercase tracking-[0.05em]">Canonical (with [[wikilinks]])</label>
            <input
              value={person.canonical}
              onChange={e => onChange({ ...person, canonical: e.target.value })}
              placeholder="[[Full Name]]"
              className="w-full h-7 px-2.5 text-[12px] font-mono bg-white/[0.04] border border-border/[0.15] rounded text-text-primary outline-none focus:border-accent/50 transition-colors"
            />
          </div>

          <div className="space-y-1">
            <label className="text-[10px] text-text-muted uppercase tracking-[0.05em]">Short name</label>
            <input
              value={person.short}
              onChange={e => onChange({ ...person, short: e.target.value })}
              placeholder="Nick"
              className="w-full h-7 px-2.5 text-[12px] bg-white/[0.04] border border-border/[0.15] rounded text-text-primary outline-none focus:border-accent/50 transition-colors"
            />
          </div>

          <div className="space-y-1">
            <label className="text-[10px] text-text-muted uppercase tracking-[0.05em]">Aliases</label>
            <div className="flex flex-wrap gap-1 mb-1.5">
              {person.aliases.map(a => (
                <span key={a} className="inline-flex items-center gap-1 px-2 py-[2px] rounded-full text-[11px] bg-white/[0.05] border border-border/[0.12] text-text-secondary">
                  {a}
                  <button onClick={() => removeAlias(a)} className="opacity-50 hover:opacity-100 text-[10px] transition-opacity">×</button>
                </span>
              ))}
            </div>
            <div className="flex gap-1.5">
              <input
                value={aliasInput}
                onChange={e => setAliasInput(e.target.value)}
                onKeyDown={e => { if (e.key === 'Enter') addAlias() }}
                placeholder="Add alias…"
                className="flex-1 h-7 px-2.5 text-[12px] bg-white/[0.04] border border-border/[0.15] rounded text-text-primary outline-none focus:border-accent/50 transition-colors"
              />
              <button
                onClick={addAlias}
                disabled={!aliasInput.trim()}
                className="h-7 px-2.5 text-[12px] rounded bg-white/[0.05] border border-border/[0.15] text-text-secondary hover:text-text-primary transition-colors disabled:opacity-40"
              >
                Add
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export function NamesTab() {
  const [people, setPeople] = useState<Person[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [query, setQuery] = useState('')

  useEffect(() => {
    api.getNames()
      .then(r => setPeople(r.people))
      .catch(() => {/* use empty */})
      .finally(() => setLoading(false))
  }, [])

  // Filter for display only — full `people` list is what we save.
  const filtered = query.trim()
    ? people
        .map((p, originalIndex) => ({ p, originalIndex }))
        .filter(({ p }) => {
          const q = query.trim().toLowerCase()
          if (p.canonical.toLowerCase().includes(q)) return true
          if (p.aliases.some(a => a.toLowerCase().includes(q))) return true
          if (p.short && p.short.toLowerCase().includes(q)) return true
          return false
        })
    : people.map((p, originalIndex) => ({ p, originalIndex }))

  function updatePerson(i: number, p: Person) {
    setPeople(prev => prev.map((x, j) => j === i ? p : x))
    setSaved(false)
  }

  function deletePerson(i: number) {
    setPeople(prev => prev.filter((_, j) => j !== i))
    setSaved(false)
  }

  function addPerson() {
    setPeople(prev => [...prev, emptyPerson()])
    setSaved(false)
  }

  async function handleSave() {
    setSaving(true)
    try {
      await api.updateNames(people)
      setSaved(true)
    } catch (err) {
      console.error('Failed to save names:', err)
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-32">
        <div className="w-5 h-5 rounded-full border-2 border-accent border-t-transparent animate-spin" />
      </div>
    )
  }

  return (
    <div className="space-y-4 max-w-lg">
      <div className="flex items-center justify-between">
        <div className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted">
          People ({people.length})
        </div>
        <button
          onClick={addPerson}
          className="flex items-center gap-1.5 h-7 px-3 text-[12px] rounded-lg bg-white/[0.05] border border-border/[0.15] text-text-secondary hover:text-text-primary transition-colors"
        >
          <Plus size={12} />
          Add person
        </button>
      </div>

      {people.length > 5 && (
        <input
          type="text"
          value={query}
          onChange={e => setQuery(e.target.value)}
          placeholder="Search names or aliases…"
          className="w-full h-8 px-3 text-[13px] rounded-lg bg-white/[0.04] border border-border/[0.1] text-text-primary placeholder:text-text-muted focus:outline-none focus:border-accent/40"
        />
      )}

      <div className="space-y-2">
        {people.length === 0 && (
          <div className="py-8 text-center text-[13px] text-text-muted">
            No people configured yet.
          </div>
        )}
        {filtered.length === 0 && people.length > 0 && (
          <div className="py-6 text-center text-[13px] text-text-muted">
            No matches for "{query}".
          </div>
        )}
        {filtered.map(({ p, originalIndex }) => (
          <PersonEditor
            key={originalIndex}
            person={p}
            onChange={updated => updatePerson(originalIndex, updated)}
            onDelete={() => deletePerson(originalIndex)}
          />
        ))}
      </div>

      <button
        onClick={() => void handleSave()}
        disabled={saving}
        className={cn(
          'h-8 px-5 text-[13px] rounded-lg font-medium transition-colors',
          saved
            ? 'bg-check-green/15 border border-check-green/30 text-check-green'
            : 'bg-accent text-white hover:bg-accent/90',
          saving && 'opacity-60',
        )}
      >
        {saving ? 'Saving…' : saved ? 'Saved ✓' : 'Save names'}
      </button>
    </div>
  )
}
