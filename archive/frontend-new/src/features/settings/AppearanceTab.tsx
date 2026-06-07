import { cn } from '@/lib/utils'
import type { AppSettings } from '@/hooks/useSettings'

interface AppearanceTabProps {
  settings: AppSettings
  onUpdate: (patch: Partial<AppSettings>) => Promise<void>
  setTheme: (t: 'dark' | 'light') => void
}

export function AppearanceTab({ settings, onUpdate, setTheme }: AppearanceTabProps) {
  return (
    <div className="space-y-8 max-w-sm">
      {/* Theme */}
      <div>
        <div className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted mb-3">Theme</div>
        <div className="flex gap-2">
          {(['dark', 'light'] as const).map(t => (
            <button
              key={t}
              onClick={() => setTheme(t)}
              className={cn(
                'flex-1 h-16 rounded-xl border text-sm font-medium capitalize transition-all',
                settings.theme === t
                  ? 'border-accent/50 bg-accent/10 text-accent'
                  : 'border-border/[0.15] bg-white/[0.03] text-text-secondary hover:text-text-primary',
              )}
            >
              {t === 'dark' ? '\uD83C\uDF19 ' : '\u2600\uFE0F '}{t}
            </button>
          ))}
        </div>
      </div>

      {/* Author name */}
      <div>
        <div className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted mb-3">Author</div>
        <input
          type="text"
          value={settings.author ?? ''}
          onChange={e => void onUpdate({ author: e.target.value })}
          placeholder="Your name"
          className="w-full px-2.5 py-1.5 text-[12px] bg-white/[0.04] border border-border/[0.15] rounded-md text-text-primary placeholder:text-text-muted/50 focus:border-accent/40 outline-none"
        />
        <p className="text-[10px] text-text-muted mt-1.5">Shown as the author on your notes</p>
      </div>
    </div>
  )
}
