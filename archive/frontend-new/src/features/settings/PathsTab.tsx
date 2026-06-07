import { useState } from 'react'
import { api } from '@/api'
import type { AppSettings } from '@/hooks/useSettings'

interface PathsTabProps {
  settings: AppSettings
  onUpdate: (patch: Partial<AppSettings>) => Promise<void>
}

function PathRow({ label, value, onSave }: { label: string; value: string; onSave: (v: string) => void }) {
  const [draft, setDraft] = useState(value)
  const [saving, setSaving] = useState(false)

  async function handleSave() {
    setSaving(true)
    try { onSave(draft) } finally { setSaving(false) }
  }

  return (
    <div className="space-y-1.5">
      <label className="text-[12px] font-medium text-text-secondary">{label}</label>
      <div className="flex gap-2">
        <input
          value={draft}
          onChange={e => setDraft(e.target.value)}
          placeholder="Click Browse or paste a path…"
          className="flex-1 h-8 px-3 text-[12px] font-mono bg-white/[0.04] border border-border/[0.15] rounded-lg text-text-primary outline-none focus:border-accent/50 transition-colors"
        />
        {window.electronAPI && (
          <button
            onClick={async () => {
              const p = await window.electronAPI!.openFolderDialog()
              if (p) setDraft(p)
            }}
            className="h-8 px-3 text-[12px] rounded-lg bg-white/[0.05] border border-border/[0.15] text-text-secondary hover:text-text-primary transition-colors"
          >
            Browse
          </button>
        )}
        <button
          onClick={() => void handleSave()}
          disabled={saving || draft === value}
          className="h-8 px-3.5 text-[12px] rounded-lg bg-accent text-white font-medium hover:bg-accent/90 transition-colors disabled:opacity-40"
        >
          Save
        </button>
      </div>
    </div>
  )
}

export function PathsTab({ settings, onUpdate }: PathsTabProps) {
  async function saveOutputPath(path: string) {
    await api.setOutputFolder(path)
    await onUpdate({ outputPath: path })
  }

  async function saveVaultPath(path: string) {
    await onUpdate({ vaultPath: path })
  }

  async function saveVaultAudioPath(path: string) {
    await onUpdate({ vaultAudioPath: path })
  }

  async function saveVaultAttachmentsPath(path: string) {
    await onUpdate({ vaultAttachmentsPath: path })
  }

  async function saveDepsPath(path: string) {
    await api.updateConfig('dependencies_folder', path)
    await onUpdate({ depsPath: path })
  }

  return (
    <div className="space-y-6 max-w-lg">
      <div>
        <div className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted mb-4">Local folders</div>
        <div className="space-y-4">
          <PathRow
            label="Audio output folder"
            value={settings.outputPath}
            onSave={p => void saveOutputPath(p)}
          />
          <PathRow
            label="Dependencies folder"
            value={settings.depsPath}
            onSave={p => void saveDepsPath(p)}
          />
        </div>
      </div>

      <div>
        <div className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted mb-1">Obsidian vault</div>
        <p className="text-[11px] text-text-muted mb-4">
          Where exported notes and media land inside your vault. Leave audio/attachments blank to use the notes folder.
        </p>
        <div className="space-y-4">
          <PathRow
            label="Obsidian vault folder"
            value={settings.vaultPath}
            onSave={p => void saveVaultPath(p)}
          />
          <PathRow
            label="Voice memos folder"
            value={settings.vaultAudioPath}
            onSave={p => void saveVaultAudioPath(p)}
          />
          <PathRow
            label="Images / attachments folder"
            value={settings.vaultAttachmentsPath}
            onSave={p => void saveVaultAttachmentsPath(p)}
          />
        </div>
      </div>

      <div className="pt-2 border-t border-border/[0.07]">
        <p className="text-[11px] text-text-muted leading-relaxed">
          Dependencies folder should contain <code className="text-accent/80">mlx-env/</code> and <code className="text-accent/80">models/</code> directories.
        </p>
      </div>
    </div>
  )
}
