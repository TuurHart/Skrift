import type { ProcessingSteps } from '@/types/pipeline'

const STEPS: Array<{
  key: keyof ProcessingSteps
  label: string
  color: string
}> = [
  { key: 'transcribe', label: 'Transcribed', color: '#60a5fa' },
  { key: 'sanitise', label: 'Cleaned Up', color: '#a78bfa' },
  { key: 'enhance', label: 'Enhanced', color: '#f59e0b' },
  { key: 'export', label: 'Exported', color: '#34d399' },
]

interface PipelineBreadcrumbProps {
  steps: ProcessingSteps
  date: string
}

export function PipelineBreadcrumb({ steps, date }: PipelineBreadcrumbProps) {
  return (
    <div className="flex items-center justify-between px-6 py-[10px] border-b border-border/[0.07] bg-surface shrink-0">
      <div className="flex items-center gap-3">
        {STEPS.map(({ key, label, color }, i) => {
          const done = steps[key] === 'done'
          const processing = steps[key] === 'processing'

          return (
            <div key={key} className="flex items-center gap-3">
              <div className="flex items-center gap-1.5">
                <div
                  className="w-2 h-2 rounded-full transition-colors"
                  style={{
                    background: done
                      ? color
                      : processing
                        ? `${color}55`
                        : 'rgba(128,128,128,0.2)',
                  }}
                />
                <span
                  className="text-[11px] transition-colors"
                  style={{ color: done ? 'rgb(var(--color-text-primary))' : 'rgb(var(--color-text-muted))' }}
                >
                  {label}
                </span>
              </div>
              {i < STEPS.length - 1 && (
                <span className="text-[10px] text-text-muted">›</span>
              )}
            </div>
          )
        })}
      </div>

      <span className="text-[11px] text-text-muted shrink-0 ml-4">{date}</span>
    </div>
  )
}
