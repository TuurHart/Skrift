import { useState } from 'react'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { AppSettings } from '@/hooks/useSettings'
import type { EnhancePrompt } from '@/api'
import { PathsTab } from './settings/PathsTab'
import { EnhancementTab } from './settings/EnhancementTab'
import { NamesTab } from './settings/NamesTab'
import { AppearanceTab } from './settings/AppearanceTab'
import { TranscriptionTab } from './settings/TranscriptionTab'
import { MobileTab } from './settings/MobileTab'

type Tab = 'paths' | 'transcription' | 'enhancement' | 'names' | 'appearance' | 'mobile'

const TABS: { id: Tab; label: string }[] = [
  { id: 'paths', label: 'Paths' },
  { id: 'transcription', label: 'Transcription' },
  { id: 'enhancement', label: 'Enhancement' },
  { id: 'names', label: 'Names' },
  { id: 'appearance', label: 'Appearance' },
  { id: 'mobile', label: 'Mobile' },
]

interface SettingsProps {
  settings: AppSettings
  onUpdate: (patch: Partial<AppSettings>) => Promise<void>
  setTheme: (t: 'dark' | 'light') => void
  defaultPrompts: EnhancePrompt[]
  onClose: () => void
  initialTab?: Tab
}

export function Settings({ settings, onUpdate, setTheme, defaultPrompts, onClose, initialTab }: SettingsProps) {
  const [tab, setTab] = useState<Tab>(initialTab ?? 'paths')

  return (
    <div
      className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-[250] animate-fade-in"
      onClick={e => { if (e.target === e.currentTarget) onClose() }}
    >
      <div
        className="bg-surface border border-border/[0.12] rounded-2xl w-[760px] max-h-[85vh] flex flex-col shadow-2xl overflow-hidden animate-modal-in"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="px-6 py-4 border-b border-border/[0.07] flex items-center justify-between shrink-0">
          <span className="text-[16px] font-semibold">Settings</span>
          <button onClick={onClose} className="text-text-muted hover:text-text-primary transition-colors p-1">
            <X size={16} />
          </button>
        </div>

        <div className="flex flex-1 min-h-0">
          {/* Sidebar nav */}
          <nav className="w-[160px] border-r border-border/[0.07] p-3 shrink-0">
            {TABS.map(t => (
              <button
                key={t.id}
                onClick={() => setTab(t.id)}
                className={cn(
                  'w-full text-left px-3 py-2 rounded-lg text-[13px] transition-colors',
                  tab === t.id
                    ? 'bg-accent/10 text-accent font-medium'
                    : 'text-text-secondary hover:text-text-primary hover:bg-white/[0.03]',
                )}
              >
                {t.label}
              </button>
            ))}
          </nav>

          {/* Content */}
          <div className="flex-1 overflow-y-auto p-6">
            {tab === 'paths' && (
              <PathsTab settings={settings} onUpdate={onUpdate} />
            )}
            {tab === 'transcription' && (
              <TranscriptionTab />
            )}
            {tab === 'enhancement' && (
              <EnhancementTab settings={settings} onUpdate={onUpdate} defaultPrompts={defaultPrompts} />
            )}
            {tab === 'names' && (
              <NamesTab />
            )}
            {tab === 'appearance' && (
              <AppearanceTab settings={settings} onUpdate={onUpdate} setTheme={setTheme} />
            )}
            {tab === 'mobile' && (
              <MobileTab />
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
