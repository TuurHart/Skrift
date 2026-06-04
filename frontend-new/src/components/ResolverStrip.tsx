import { useState, useMemo } from 'react'
import { cn } from '@/lib/utils'
import type { AmbiguousOccurrence, NameCandidate } from '@/types/pipeline'

const PLAIN = '__plain__'

interface ResolverStripProps {
  occurrences: AmbiguousOccurrence[]
  onResolve: (decisions: Array<{ alias: string; canonical: string; short: string }>) => void
}

interface AliasGroup {
  alias: string
  key: string
  candidates: NameCandidate[]
  count: number
  before: string
  after: string
}

export function ResolverStrip({ occurrences, onResolve }: ResolverStripProps) {
  const groups = useMemo<AliasGroup[]>(() => {
    const by = new Map<string, AliasGroup>()
    for (const occ of occurrences) {
      const key = occ.alias.toLowerCase()
      const g = by.get(key)
      if (g) { g.count++ }
      else by.set(key, { alias: occ.alias, key, candidates: occ.candidates, count: 1, before: occ.context_before, after: occ.context_after })
    }
    return [...by.values()]
  }, [occurrences])

  // key → chosen candidate canonical, or PLAIN
  const [choices, setChoices] = useState<Record<string, string>>({})
  const [submitting, setSubmitting] = useState(false)

  const allDecided = groups.every(g => choices[g.key] !== undefined)

  function submit() {
    const decisions = groups
      .map(g => {
        const choice = choices[g.key]
        if (!choice || choice === PLAIN) return null
        const c = g.candidates.find(c => c.canonical === choice)
        return c ? { alias: g.alias, canonical: c.canonical, short: c.short } : null
      })
      .filter((d): d is { alias: string; canonical: string; short: string } => d !== null)
    setSubmitting(true)
    onResolve(decisions) // parent clears ambiguous_names on success, unmounting this strip
  }

  return (
    <div className="mb-6 rounded-xl border border-step-sanitise/30 bg-step-sanitise/[0.07] p-4">
      <div className="flex items-center gap-2 mb-3">
        <span className="text-[11px] font-semibold uppercase tracking-[0.06em] text-step-sanitise">
          {groups.length} {groups.length === 1 ? 'name needs' : 'names need'} resolving
        </span>
      </div>

      <div className="space-y-3">
        {groups.map(g => (
          <div key={g.key}>
            <div className="text-[12px] text-text-secondary mb-1.5 leading-relaxed">
              …{g.before}<span className="font-semibold text-text-primary">{g.alias}</span>{g.after}…
              {g.count > 1 && <span className="text-text-muted"> · {g.count}×</span>}
            </div>
            <div className="flex flex-wrap gap-1.5">
              {g.candidates.map(c => {
                const sel = choices[g.key] === c.canonical
                const label = c.canonical.replace(/^\[\[|\]\]$/g, '')
                return (
                  <button
                    key={c.canonical}
                    onClick={() => setChoices(prev => ({ ...prev, [g.key]: c.canonical }))}
                    className={cn(
                      'text-[12px] px-2.5 py-1 rounded-md border transition-colors',
                      sel
                        ? 'bg-accent/20 border-accent/50 text-accent font-medium'
                        : 'bg-white/[0.04] border-border/[0.15] text-text-secondary hover:text-text-primary hover:border-border/[0.3]',
                    )}
                  >
                    {label}
                  </button>
                )
              })}
              <button
                onClick={() => setChoices(prev => ({ ...prev, [g.key]: PLAIN }))}
                className={cn(
                  'text-[12px] px-2.5 py-1 rounded-md border transition-colors',
                  choices[g.key] === PLAIN
                    ? 'bg-white/[0.1] border-border/[0.3] text-text-primary'
                    : 'bg-transparent border-dashed border-border/[0.2] text-text-muted hover:text-text-secondary',
                )}
              >
                Leave as plain text
              </button>
            </div>
          </div>
        ))}
      </div>

      <button
        onClick={submit}
        disabled={!allDecided || submitting}
        className="mt-3.5 text-[12px] font-medium px-3.5 py-1.5 rounded-md bg-accent text-white hover:bg-accent/90 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
      >
        {submitting ? 'Applying…' : allDecided ? 'Apply names' : 'Pick each name to continue'}
      </button>
    </div>
  )
}
