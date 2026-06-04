import { useState, useEffect } from 'react'
import { cn } from '@/lib/utils'
import { api } from '@/api'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogTitle, DialogDescription } from '@/components/ui/dialog'
import type { Person } from '@/api'

interface AddNameModalProps {
  selectedText: string
  onClose: () => void
}

type Tab = 'new' | 'existing'

export function AddNameModal({ selectedText, onClose }: AddNameModalProps) {
  const [tab, setTab] = useState<Tab>('new')
  const [people, setPeople] = useState<Person[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // New name fields
  const [fullName, setFullName] = useState('')
  const [shortName, setShortName] = useState('')

  // Existing name selection
  const [selectedPersonIdx, setSelectedPersonIdx] = useState<number | null>(null)

  useEffect(() => {
    api.getNames()
      .then(r => {
        setPeople(r.people)
        setLoading(false)
      })
      .catch(() => { setLoading(false); setError('Could not load names') })
  }, [])

  // Auto-derive short name from full name
  useEffect(() => {
    if (fullName.trim()) {
      setShortName(fullName.trim().split(' ')[0])
    }
  }, [fullName])

  async function handleSaveNew() {
    const name = fullName.trim()
    const alias = selectedText.trim()
    if (!name || !alias) return
    const canonical = name.startsWith('[[') ? name : `[[${name}]]`
    const short = shortName.trim() || name.split(' ')[0]
    const newPerson: Person = { canonical, aliases: [alias], short }
    setSaving(true)
    setError(null)
    try {
      await api.updateNames([...people, newPerson])
      onClose()
    } catch {
      setError('Failed to save')
    } finally {
      setSaving(false)
    }
  }

  async function handleAddAlias() {
    if (selectedPersonIdx === null) return
    const alias = selectedText.trim()
    if (!alias) return
    const updated = people.map((p, i) => {
      if (i !== selectedPersonIdx) return p
      const aliases = [...(p.aliases ?? []), alias]
      return { ...p, aliases }
    })
    setSaving(true)
    setError(null)
    try {
      await api.updateNames(updated)
      onClose()
    } catch {
      setError('Failed to save')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent hideClose className="w-[420px] max-w-[420px] p-0 overflow-hidden">
        {/* Header */}
        <div className="px-5 py-4 border-b border-border/[0.07]">
          <DialogTitle className="text-[15px] font-semibold mb-0.5">Add name</DialogTitle>
          <DialogDescription className="text-[12px] text-text-secondary">
            Selected: <span className="font-medium text-accent">"{selectedText}"</span>
          </DialogDescription>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-border/[0.07]">
          {(['new', 'existing'] as Tab[]).map(t => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={cn(
                'flex-1 py-2.5 text-[12px] font-medium transition-colors',
                tab === t
                  ? 'text-text-primary border-b-2 border-accent'
                  : 'text-text-muted hover:text-text-secondary',
              )}
            >
              {t === 'new' ? 'New name' : 'Add to existing'}
            </button>
          ))}
        </div>

        {/* Body */}
        <div className="p-5">
          {loading ? (
            <div className="flex items-center justify-center py-6">
              <div className="w-4 h-4 border-2 border-accent border-t-transparent rounded-full animate-spin" />
            </div>
          ) : tab === 'new' ? (
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-text-muted uppercase tracking-wide block mb-1">Full name</label>
                <input
                  autoFocus
                  type="text"
                  placeholder="e.g. Henry Williams"
                  value={fullName}
                  onChange={e => setFullName(e.target.value)}
                  onKeyDown={e => { if (e.key === 'Enter') void handleSaveNew() }}
                  className="w-full px-3 py-2 rounded-lg bg-white/[0.05] border border-border/[0.15] text-[13px] text-text-primary placeholder:text-text-muted outline-none focus:border-accent/50 transition-colors"
                />
              </div>
              <div>
                <label className="text-[11px] text-text-muted uppercase tracking-wide block mb-1">Short / first name</label>
                <input
                  type="text"
                  value={shortName}
                  onChange={e => setShortName(e.target.value)}
                  className="w-full px-3 py-2 rounded-lg bg-white/[0.05] border border-border/[0.15] text-[13px] text-text-primary placeholder:text-text-muted outline-none focus:border-accent/50 transition-colors"
                />
              </div>
              <div>
                <label className="text-[11px] text-text-muted uppercase tracking-wide block mb-1">Alias (from selection)</label>
                <div className="px-3 py-2 rounded-lg bg-white/[0.03] border border-border/[0.08] text-[13px] text-text-secondary">
                  {selectedText}
                </div>
              </div>
            </div>
          ) : (
            <div className="space-y-2 max-h-[240px] overflow-y-auto">
              {people.length === 0 ? (
                <p className="text-[13px] text-text-muted text-center py-4">No names configured yet</p>
              ) : people.map((p, i) => {
                const label = p.canonical.replace(/\[\[|\]\]/g, '')
                const alreadyAlias = (p.aliases ?? []).map(a => a.toLowerCase()).includes(selectedText.trim().toLowerCase())
                return (
                  <button
                    key={i}
                    onClick={() => !alreadyAlias && setSelectedPersonIdx(i)}
                    disabled={alreadyAlias}
                    className={cn(
                      'w-full text-left px-3 py-2.5 rounded-lg border transition-colors',
                      alreadyAlias
                        ? 'opacity-40 cursor-not-allowed bg-white/[0.02] border-border/[0.07]'
                        : selectedPersonIdx === i
                          ? 'bg-accent/15 border-accent/40 text-text-primary'
                          : 'bg-white/[0.03] border-border/[0.1] hover:border-border/[0.25] text-text-secondary hover:text-text-primary',
                    )}
                  >
                    <div className="text-[13px] font-medium">{label}</div>
                    <div className="text-[11px] text-text-muted mt-0.5">
                      {alreadyAlias
                        ? 'Already an alias'
                        : (p.aliases ?? []).length > 0
                          ? `Aliases: ${p.aliases.join(', ')}`
                          : 'No aliases yet'}
                    </div>
                  </button>
                )
              })}
            </div>
          )}

          {error && <div className="mt-3 text-[11px] text-destructive">{error}</div>}
        </div>

        {/* Footer */}
        <div className="px-5 py-3.5 border-t border-border/[0.07] flex items-center justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button
            onClick={() => void (tab === 'new' ? handleSaveNew() : handleAddAlias())}
            disabled={saving || (tab === 'new' ? !fullName.trim() : selectedPersonIdx === null)}
          >
            {saving && <span className="w-3 h-3 border-2 border-white border-t-transparent rounded-full animate-spin inline-block" />}
            {tab === 'new' ? 'Create name' : 'Add alias'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
