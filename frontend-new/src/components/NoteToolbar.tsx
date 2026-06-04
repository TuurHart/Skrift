import { useRef, useEffect, useCallback, useState } from 'react'
import { Play, Pause, RotateCcw, RotateCw } from 'lucide-react'

const SPEED_STEPS = [0.75, 1, 1.25, 1.5, 2] as const
const SKIP = 10 // seconds

interface NoteToolbarProps {
  src: string
  isPlaying: boolean
  currentTime: number
  seekTo?: { time: number; seq: number } | null
  onPlayPause: (v: boolean) => void
  onTimeUpdate: (t: number) => void
}

function fmt(s: number): string {
  if (!isFinite(s) || s < 0) s = 0
  const m = Math.floor(s / 60)
  const sec = String(Math.floor(s % 60)).padStart(2, '0')
  return `${m}:${sec}`
}

// Circular skip control with the seconds count centred inside the arrow.
function SkipButton({ dir, onClick }: { dir: 'back' | 'fwd'; onClick: () => void }) {
  const Icon = dir === 'back' ? RotateCcw : RotateCw
  return (
    <button
      onClick={onClick}
      className="relative w-8 h-8 rounded-lg bg-white/[0.05] text-text-secondary hover:text-text-primary hover:bg-white/[0.08] transition-colors flex items-center justify-center"
      title={dir === 'back' ? `Back ${SKIP}s` : `Forward ${SKIP}s`}
    >
      <Icon size={19} strokeWidth={1.75} />
      <span className="absolute inset-0 flex items-center justify-center text-[7px] font-bold tabular-nums pointer-events-none" style={{ paddingTop: 1 }}>{SKIP}</span>
    </button>
  )
}

export function NoteToolbar({ src, isPlaying, currentTime, seekTo, onPlayPause, onTimeUpdate }: NoteToolbarProps) {
  const audioRef = useRef<HTMLAudioElement>(null)
  const rafRef = useRef<number>(0)
  const durationRef = useRef<number>(0)
  const trackRef = useRef<HTMLDivElement>(null)
  const lastSeekSeq = useRef<number | undefined>(undefined)
  const [dragging, setDragging] = useState(false)
  const [, force] = useState(0) // re-render on metadata load so duration shows
  const [speed, setSpeed] = useState(() => {
    const saved = localStorage.getItem('skrift-playback-speed')
    return saved ? Number(saved) : 1
  })

  useEffect(() => { if (audioRef.current) audioRef.current.playbackRate = speed }, [speed])

  function cycleSpeed() {
    setSpeed(prev => {
      const idx = SPEED_STEPS.indexOf(prev as typeof SPEED_STEPS[number])
      const next = SPEED_STEPS[(idx + 1) % SPEED_STEPS.length]
      localStorage.setItem('skrift-playback-speed', String(next))
      return next
    })
  }

  // Sync element with isPlaying
  useEffect(() => {
    const el = audioRef.current
    if (!el) return
    if (isPlaying) el.play().catch(() => onPlayPause(false))
    else el.pause()
  }, [isPlaying, onPlayPause])

  // Smooth time updates while playing
  const tick = useCallback(() => {
    if (audioRef.current) onTimeUpdate(audioRef.current.currentTime)
    rafRef.current = requestAnimationFrame(tick)
  }, [onTimeUpdate])
  useEffect(() => {
    if (isPlaying) rafRef.current = requestAnimationFrame(tick)
    else cancelAnimationFrame(rafRef.current)
    return () => cancelAnimationFrame(rafRef.current)
  }, [isPlaying, tick])

  // External seek (karaoke word click)
  useEffect(() => {
    if (!seekTo || seekTo.seq === lastSeekSeq.current) return
    lastSeekSeq.current = seekTo.seq
    if (audioRef.current) { audioRef.current.currentTime = seekTo.time; onTimeUpdate(seekTo.time) }
  }, [seekTo, onTimeUpdate])

  // End + metadata
  useEffect(() => {
    const el = audioRef.current
    if (!el) return
    const onEnded = () => { onPlayPause(false); onTimeUpdate(0) }
    const onMeta = () => { durationRef.current = el.duration; force(n => n + 1) }
    el.addEventListener('ended', onEnded)
    el.addEventListener('loadedmetadata', onMeta)
    return () => { el.removeEventListener('ended', onEnded); el.removeEventListener('loadedmetadata', onMeta) }
  }, [onPlayPause, onTimeUpdate])

  function seekTime(t: number) {
    const dur = durationRef.current || 0
    const clamped = Math.max(0, Math.min(dur || t, t))
    if (audioRef.current) audioRef.current.currentTime = clamped
    onTimeUpdate(clamped)
  }
  function skip(delta: number) { seekTime(currentTime + delta) }

  function seekFromClientX(clientX: number) {
    const el = trackRef.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    const pct = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width))
    seekTime(pct * (durationRef.current || 0))
  }

  // Drag the scrubber
  useEffect(() => {
    if (!dragging) return
    const move = (e: PointerEvent) => seekFromClientX(e.clientX)
    const up = () => setDragging(false)
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
    return () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up) }
  }, [dragging]) // eslint-disable-line react-hooks/exhaustive-deps

  const duration = durationRef.current || 0
  const pct = duration > 0 ? Math.max(0, Math.min(1, currentTime / duration)) : 0

  return (
    <div className="flex items-center gap-4 px-10 py-2.5 border-b border-border/[0.06] bg-surface/40 flex-none">
      <audio ref={audioRef} src={src} preload="metadata" />

      {/* Transport */}
      <div className="flex items-center gap-1.5 flex-none">
        <SkipButton dir="back" onClick={() => skip(-SKIP)} />
        <button
          onClick={() => onPlayPause(!isPlaying)}
          className="w-9 h-9 rounded-full bg-accent flex items-center justify-center text-white hover:bg-accent/90 transition-colors"
        >
          {isPlaying ? <Pause size={14} fill="white" /> : <Play size={14} fill="white" className="ml-0.5" />}
        </button>
        <SkipButton dir="fwd" onClick={() => skip(SKIP)} />
      </div>

      {/* Scrubber */}
      <div className="flex items-center gap-3 flex-1 min-w-0">
        <span className="text-[11.5px] text-text-secondary font-mono tabular-nums flex-none">{fmt(currentTime)}</span>
        <div
          ref={trackRef}
          onPointerDown={(e) => { e.preventDefault(); setDragging(true); seekFromClientX(e.clientX) }}
          className="relative flex-1 h-4 flex items-center cursor-pointer group"
        >
          <div className="h-[5px] w-full rounded-full bg-border/[0.15] overflow-hidden">
            <div className="h-full rounded-full bg-accent" style={{ width: `${pct * 100}%` }} />
          </div>
          <div
            className="absolute w-3.5 h-3.5 rounded-full bg-white shadow -translate-x-1/2 opacity-0 group-hover:opacity-100 transition-opacity"
            style={{ left: `${pct * 100}%`, opacity: dragging ? 1 : undefined }}
          />
        </div>
        <span className="text-[11.5px] text-text-secondary font-mono tabular-nums flex-none">{fmt(duration)}</span>
      </div>

      {/* Speed */}
      <button
        onClick={cycleSpeed}
        className="flex-none px-2.5 py-1.5 text-[11.5px] font-mono font-semibold rounded-lg bg-white/[0.05] text-text-secondary hover:text-text-primary hover:bg-white/[0.08] transition-colors"
        title="Playback speed"
      >
        {speed}×
      </button>
    </div>
  )
}
