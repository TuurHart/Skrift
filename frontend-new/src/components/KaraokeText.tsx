import { useRef, useEffect, useMemo } from 'react'

interface Token {
  text: string
  start: number
  end: number
}

interface KaraokeTextProps {
  /** The note body (copy-edited text) — same text the editor shows, so swapping
   *  editor ↔ karaoke doesn't reflow or change wording (fixes the jump bug). */
  text: string
  /** Transcript word timings used only to drive the highlight + click-to-seek. */
  tokens: Token[]
  currentTime: number
  onSeek?: (time: number) => void
}

export function KaraokeText({ text, tokens, currentTime, onSeek }: KaraokeTextProps) {
  const activeRef = useRef<HTMLSpanElement>(null)

  // Keep the active word in view as audio plays.
  useEffect(() => {
    activeRef.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  })

  // Split into words + whitespace so spacing and line breaks match the editor exactly.
  const parts = useMemo(() => text.split(/(\s+)/), [text])

  // Approximate each body word's start time by proportional alignment to the
  // transcript timings. Copy-edit is minimal, so positions line up within a few
  // seconds — good enough for click-to-seek and a moving highlight.
  const { wordStarts, wordCount } = useMemo(() => {
    let n = 0
    for (const p of parts) if (/\S/.test(p)) n++
    const T = tokens.length
    const starts: number[] = []
    for (let k = 0; k < n; k++) {
      starts.push(T > 0 ? tokens[Math.min(T - 1, Math.round((k * T) / Math.max(1, n)))].start : 0)
    }
    return { wordStarts: starts, wordCount: n }
  }, [parts, tokens])

  // Active word = the last one whose start time has passed.
  let activeK = -1
  for (let k = 0; k < wordCount; k++) {
    if (wordStarts[k] <= currentTime) activeK = k
    else break
  }

  let wc = -1
  return (
    <div className="text-[15px] leading-[1.75] text-text-primary" style={{ whiteSpace: 'pre-wrap' }}>
      {parts.map((p, i) => {
        if (!/\S/.test(p)) return <span key={i}>{p}</span> // whitespace + newlines preserved
        wc += 1
        const k = wc
        const active = k === activeK
        const past = k < activeK
        return (
          <span
            key={i}
            ref={active ? activeRef : undefined}
            onClick={() => onSeek?.(wordStarts[k] ?? 0)}
            style={{
              // No padding — it would change word widths and reflow vs the editor.
              color: active || past ? 'rgb(var(--color-text-primary))' : 'rgba(var(--color-text-primary) / 0.35)',
              background: active ? 'rgb(var(--color-accent) / 0.25)' : 'transparent',
              borderRadius: active ? '2px' : '0',
              cursor: onSeek ? 'pointer' : 'default',
              transition: 'color 0.08s, background 0.08s',
            }}
          >
            {p}
          </span>
        )
      })}
    </div>
  )
}
