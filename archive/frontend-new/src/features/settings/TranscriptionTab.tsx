import { useState, useEffect } from 'react'
import { cn } from '@/lib/utils'
import { api } from '@/api'

export function TranscriptionTab() {
  const [model, setModel] = useState<string>('')
  const [noiseFloor, setNoiseFloor] = useState(-20)
  const [highpass, setHighpass] = useState(80)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    api.getConfig()
      .then(({ config }) => {
        const raw = config as Record<string, unknown>
        const t = raw['transcription'] as Record<string, unknown> | undefined
        if (t?.parakeet_model && typeof t.parakeet_model === 'string') {
          setModel(t.parakeet_model)
        }
        if (t?.noise_reduction != null) setNoiseFloor(Number(t.noise_reduction))
        if (t?.highpass_freq != null) setHighpass(Number(t.highpass_freq))
      })
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  function saveNoise(val: number) {
    setNoiseFloor(val)
    void api.updateConfig('transcription.noise_reduction', val)
  }

  function saveHighpass(val: number) {
    setHighpass(val)
    void api.updateConfig('transcription.highpass_freq', val)
  }

  if (loading) return <div className="text-[12px] text-text-muted">Loading…</div>

  return (
    <div className="space-y-8 max-w-sm">
      {/* Engine */}
      <div>
        <div className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted mb-3">
          Engine
        </div>
        <div className="flex items-center gap-3 px-3 py-2.5 rounded-lg border border-accent/30 bg-accent/[0.08]">
          <div className="w-3.5 h-3.5 rounded-full border-2 border-accent bg-accent shrink-0" />
          <div className="flex-1 min-w-0">
            <div className="text-[13px] font-medium text-text-primary">Parakeet-MLX</div>
            <div className="text-[11px] text-text-muted">MLX-accelerated, 25 languages incl. Dutch &amp; English</div>
          </div>
        </div>
      </div>

      {/* Model */}
      {model && (
        <div>
          <div className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted mb-2">
            Model
          </div>
          <div className="text-[12px] text-text-secondary font-mono bg-white/[0.03] px-3 py-2 rounded-lg border border-border/[0.1]">
            {model}
          </div>
          <p className="text-[11px] text-text-muted mt-2">
            Model downloads automatically on first transcription (~1.2 GB).
          </p>
        </div>
      )}

      {/* Audio preprocessing */}
      <div>
        <div className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted mb-4">
          Audio preprocessing
        </div>
        <div className="space-y-5">
          {/* Noise reduction */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="text-[12px] font-medium text-text-secondary">Noise reduction</label>
              <span className={cn(
                'text-[11px] font-mono min-w-[4rem] text-right',
                noiseFloor === 0 ? 'text-text-muted' : 'text-text-secondary',
              )}>
                {noiseFloor === 0 ? 'Off' : `${noiseFloor} dB`}
              </span>
            </div>
            <input
              type="range"
              min={-40}
              max={0}
              step={5}
              value={noiseFloor}
              onChange={e => saveNoise(Number(e.target.value))}
              className="w-full accent-accent h-1 cursor-pointer"
            />
            <div className="flex justify-between text-[10px] text-text-muted mt-1">
              <span>Aggressive</span>
              <span>Off</span>
            </div>
            <p className="text-[10px] text-text-muted mt-1">
              Reduces background sounds (dogs, traffic, wind). Lower = stronger.
            </p>
          </div>

          {/* High-pass filter */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="text-[12px] font-medium text-text-secondary">High-pass filter</label>
              <span className={cn(
                'text-[11px] font-mono min-w-[4rem] text-right',
                highpass === 0 ? 'text-text-muted' : 'text-text-secondary',
              )}>
                {highpass === 0 ? 'Off' : `${highpass} Hz`}
              </span>
            </div>
            <input
              type="range"
              min={0}
              max={300}
              step={10}
              value={highpass}
              onChange={e => saveHighpass(Number(e.target.value))}
              className="w-full accent-accent h-1 cursor-pointer"
            />
            <div className="flex justify-between text-[10px] text-text-muted mt-1">
              <span>Off</span>
              <span>300 Hz</span>
            </div>
            <p className="text-[10px] text-text-muted mt-1">
              Cuts low-frequency rumble (AC, traffic hum). 80 Hz is a good default.
            </p>
          </div>
        </div>

        <p className="text-[11px] text-text-muted mt-4 pt-3 border-t border-border/[0.07]">
          Changes apply to new transcriptions. Use re-transcribe to reprocess existing files.
        </p>
      </div>
    </div>
  )
}
