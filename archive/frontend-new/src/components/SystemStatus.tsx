import { useEffect, useState } from 'react'
import { cn } from '@/lib/utils'
import { api } from '@/api'
import type { SystemHealth } from '@/types/pipeline'

interface StatusDotProps {
  ok: boolean | null
  label: string
}

function StatusDot({ ok, label }: StatusDotProps) {
  const statusText =
    ok === null ? 'checking…' : ok ? 'ok' : 'unavailable'

  return (
    <div className="relative group/dot">
      <div
        className={cn(
          'w-1.5 h-1.5 rounded-full transition-colors duration-300',
          ok === null && 'bg-gray-600',
          ok === true && 'bg-check-green',
          ok === false && 'bg-destructive',
        )}
      />
      {/* Tooltip */}
      <div
        className={cn(
          'absolute bottom-full left-1/2 -translate-x-1/2 mb-2',
          'px-2 py-1 rounded-md text-[10px] whitespace-nowrap',
          'bg-surface border border-border/[0.15] text-text-secondary shadow-lg',
          'opacity-0 group-hover/dot:opacity-100 transition-opacity duration-150',
          'pointer-events-none z-50',
        )}
      >
        {label}: {statusText}
      </div>
    </div>
  )
}

export function SystemStatus() {
  const [health, setHealth] = useState<SystemHealth | null>(null)
  const [backendOk, setBackendOk] = useState<boolean | null>(null)

  useEffect(() => {
    async function check() {
      try {
        const h = await api.getSystemHealth()
        setHealth(h)
        setBackendOk(true)
      } catch {
        setBackendOk(false)
        setHealth(null)
      }
    }

    void check()
    const iv = setInterval(() => void check(), 15_000)
    return () => clearInterval(iv)
  }, [])

  const parakeetOk = health?.transcription_modules?.parakeet?.available === true

  return (
    <div className="flex gap-[3px] items-center mr-0.5">
      <StatusDot ok={backendOk} label="Backend" />
      <StatusDot ok={backendOk === false ? false : parakeetOk || null} label="Parakeet" />
    </div>
  )
}
