import { useState, useEffect, useRef, useCallback } from 'react'
import { X, ChevronUp, ChevronDown } from 'lucide-react'

export function FindBar() {
  const [visible, setVisible] = useState(false)
  const [query, setQuery] = useState('')
  const [matchInfo, setMatchInfo] = useState<{ active: number; total: number } | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const doFind = useCallback((text: string, forward = true) => {
    if (!text.trim()) {
      window.electronAPI?.stopFindInPage('clearSelection')
      setMatchInfo(null)
      return
    }
    window.electronAPI?.findInPage(text, { forward, findNext: false })
  }, [])

  const findNext = useCallback((forward = true) => {
    if (!query.trim()) return
    window.electronAPI?.findInPage(query, { forward, findNext: true })
  }, [query])

  const close = useCallback(() => {
    setVisible(false)
    setQuery('')
    setMatchInfo(null)
    window.electronAPI?.stopFindInPage('clearSelection')
  }, [])

  // Listen for found-in-page results from Electron
  useEffect(() => {
    const cleanup = window.electronAPI?.onFoundInPage((result: { active: number; total: number }) => {
      setMatchInfo(result)
    })
    return cleanup
  }, [])

  // Toggle find bar via Cmd+F
  useEffect(() => {
    const cleanup = window.electronAPI?.onToggleFind(() => {
      setVisible(v => {
        if (!v) {
          setTimeout(() => inputRef.current?.focus(), 50)
          return true
        }
        // Already visible — focus the input
        inputRef.current?.focus()
        inputRef.current?.select()
        return true
      })
    })
    return cleanup
  }, [])

  // Find next via Cmd+G
  useEffect(() => {
    const cleanup = window.electronAPI?.onFindNext(() => findNext(true))
    return cleanup
  }, [findNext])

  // Close via Escape
  useEffect(() => {
    const cleanup = window.electronAPI?.onCloseFind(() => {
      if (visible) close()
    })
    return cleanup
  }, [visible, close])

  // Also handle Escape key directly on the input
  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Escape') {
      close()
    } else if (e.key === 'Enter') {
      e.preventDefault()
      findNext(!e.shiftKey) // Shift+Enter = find previous
    }
  }

  function handleChange(text: string) {
    setQuery(text)
    doFind(text)
  }

  if (!visible) return null

  return (
    <div className="fixed top-0 right-[280px] z-[200] flex items-center gap-1.5 bg-surface border border-border/[0.15] rounded-b-lg px-3 py-2 shadow-lg">
      <input
        ref={inputRef}
        type="text"
        value={query}
        onChange={e => handleChange(e.target.value)}
        onKeyDown={handleKeyDown}
        placeholder="Find in page..."
        className="w-48 bg-white/[0.05] border border-border/[0.1] rounded px-2 py-1 text-[12px] text-text-primary placeholder:text-text-muted/50 outline-none focus:border-accent/40"
        autoFocus
      />
      {matchInfo && query && (
        <span className="text-[10px] text-text-muted font-mono">
          {matchInfo.total > 0 ? `${matchInfo.active}/${matchInfo.total}` : 'No matches'}
        </span>
      )}
      <button
        onClick={() => findNext(false)}
        className="p-1 text-text-muted hover:text-text-secondary transition-colors"
        title="Previous (Shift+Enter)"
      >
        <ChevronUp size={13} />
      </button>
      <button
        onClick={() => findNext(true)}
        className="p-1 text-text-muted hover:text-text-secondary transition-colors"
        title="Next (Enter)"
      >
        <ChevronDown size={13} />
      </button>
      <button
        onClick={close}
        className="p-1 text-text-muted hover:text-text-secondary transition-colors"
        title="Close (Esc)"
      >
        <X size={13} />
      </button>
    </div>
  )
}
