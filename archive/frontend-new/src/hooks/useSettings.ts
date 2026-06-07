import { useState, useEffect, useCallback } from 'react'
import { api, DEFAULT_PROMPTS, type EnhancePrompt } from '@/api'

export interface VisibleProperties {
  date: boolean
  source: boolean
  duration: boolean
  author: boolean
  location: boolean
  tags: boolean
  summary: boolean
  significance: boolean
  [key: string]: boolean
}

export interface AppSettings {
  visibleProps: VisibleProperties
  customPropNames: string[]
  vaultPath: string
  vaultAudioPath: string
  vaultAttachmentsPath: string
  depsPath: string
  outputPath: string
  author: string
  enhancePrompts: EnhancePrompt[]
  theme: 'dark' | 'light'
}

const DEFAULTS: AppSettings = {
  visibleProps: {
    date: true, source: true, duration: true,
    author: false, location: false,
    tags: true, summary: true, significance: true,
  },
  customPropNames: [],
  vaultPath: '',
  vaultAudioPath: '',
  vaultAttachmentsPath: '',
  depsPath: '',
  outputPath: '',
  author: '',
  enhancePrompts: DEFAULT_PROMPTS,
  theme: 'dark',
}

export function useSettings() {
  // Backend default prompts (from settings.py DEFAULT_SETTINGS) — used for Reset
  const [defaultPrompts, setDefaultPrompts] = useState<EnhancePrompt[]>(DEFAULT_PROMPTS)

  const [settings, setSettingsState] = useState<AppSettings>(() => {
    // Hydrate from localStorage for fast startup
    const stored = localStorage.getItem('skrift.settings')
    if (stored) {
      try {
        const parsed = JSON.parse(stored) as Partial<AppSettings>
        // Reconcile saved prompts with current DEFAULT_PROMPTS:
        // keep valid saved ones (preserving user edits), add any new defaults
        if (parsed.enhancePrompts) {
          const savedById = new Map(parsed.enhancePrompts.map(p => [p.id, p]))
          parsed.enhancePrompts = DEFAULT_PROMPTS.map(dp => savedById.get(dp.id) ?? dp)
        }
        // Migrate old "confidence" visibility key → "significance"
        if (parsed.visibleProps && 'confidence' in parsed.visibleProps && !('significance' in parsed.visibleProps)) {
          (parsed.visibleProps as Record<string, boolean>).significance = (parsed.visibleProps as Record<string, boolean>).confidence
          delete (parsed.visibleProps as Record<string, boolean>).confidence
        }
        return { ...DEFAULTS, ...parsed }
      }
      catch { /* ignore */ }
    }
    return DEFAULTS
  })

  // Load from backend on mount — backend is the single source of truth
  useEffect(() => {
    async function load() {
      try {
        const { config } = await api.getConfig()
        const patch: Partial<AppSettings> = {}

        // Helper: backend returns nested dict, access safely
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const cfg = config as any

        // UI settings (stored in backend under ui.*)
        const uiVisProps = cfg?.ui?.visible_properties
        if (uiVisProps) {
          patch.visibleProps = { ...DEFAULTS.visibleProps, ...uiVisProps }
        }
        const uiCustomProps = cfg?.ui?.custom_props
        if (uiCustomProps) {
          patch.customPropNames = uiCustomProps as string[]
        }

        // Enhancement prompts — user overrides from user_settings.json
        const prompts = cfg?.enhancement?.prompts as Partial<Record<string, Partial<EnhancePrompt>>> | undefined
        if (prompts && Object.keys(prompts).length > 0) {
          // Merge user overrides with frontend prompt metadata (labels, colors, etc.)
          patch.enhancePrompts = DEFAULT_PROMPTS.map(p => {
            const val = prompts[p.id]
            if (!val) return p
            if (typeof val === 'string') return { ...p, instruction: val }
            return { ...p, ...val }
          })
        }

        // Paths — backend always has these, read from nested export.*
        if (cfg?.dependencies_folder !== undefined) {
          patch.depsPath = (cfg.dependencies_folder as string) ?? ''
        }
        const exp = cfg?.export
        if (exp?.note_folder !== undefined) {
          patch.vaultPath = (exp.note_folder as string) ?? ''
        }
        if (exp?.audio_folder !== undefined) {
          patch.vaultAudioPath = (exp.audio_folder as string) ?? ''
        }
        if (exp?.attachments_folder !== undefined) {
          patch.vaultAttachmentsPath = (exp.attachments_folder as string) ?? ''
        }
        if (exp?.author !== undefined) {
          patch.author = (exp.author as string) ?? ''
        }

        const [outFolder, defaultsRes] = await Promise.allSettled([
          api.getOutputFolder(),
          api.getConfigDefaults(),
        ])
        if (outFolder.status === 'fulfilled') patch.outputPath = outFolder.value.path

        // Backend defaults are the single source of truth for prompts.
        // Use them for the Reset button AND as the base when no user overrides exist.
        if (defaultsRes.status === 'fulfilled') {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const defPrompts = (defaultsRes.value.config as any)?.enhancement?.prompts as Record<string, string> | undefined
          if (defPrompts) {
            const backendDefaults = DEFAULT_PROMPTS.map(p => {
              const instr = defPrompts[p.id]
              return instr ? { ...p, instruction: instr } : p
            })
            setDefaultPrompts(backendDefaults)
            // If no user overrides, use backend defaults (not stale localStorage)
            if (!prompts || Object.keys(prompts).length === 0) {
              patch.enhancePrompts = backendDefaults
            }
          }
        }

        // theme from localStorage (purely visual, no backend equivalent)
        patch.theme = (localStorage.getItem('skrift.theme') as 'dark' | 'light') || 'dark'

        setSettingsState(prev => {
          const next = { ...prev, ...patch }
          localStorage.setItem('skrift.settings', JSON.stringify(next))
          return next
        })
      } catch { /* use defaults */ }
    }
    void load()
  }, [])

  const update = useCallback(async (patch: Partial<AppSettings>) => {
    setSettingsState(prev => {
      const next = { ...prev, ...patch }
      localStorage.setItem('skrift.settings', JSON.stringify(next))
      return next
    })

    // Persist relevant keys to backend
    try {
      if (patch.visibleProps !== undefined) {
        await api.updateConfig('ui.visible_properties', patch.visibleProps)
      }
      if (patch.customPropNames !== undefined) {
        await api.updateConfig('ui.custom_props', patch.customPropNames)
      }
      if (patch.enhancePrompts !== undefined) {
        const prompts: Record<string, Partial<EnhancePrompt>> = {}
        for (const p of patch.enhancePrompts) {
          prompts[p.id] = { instruction: p.instruction, label: p.label, desc: p.desc, tagColor: p.tagColor }
        }
        await api.updateConfig('enhancement.prompts', prompts)
      }
      if (patch.vaultPath !== undefined) {
        await api.updateConfig('export.note_folder', patch.vaultPath)
        // Also set as the tag whitelist scan path
        await api.updateConfig('enhancement.obsidian.vault_path', patch.vaultPath)
      }
      if (patch.vaultAudioPath !== undefined) {
        await api.updateConfig('export.audio_folder', patch.vaultAudioPath)
      }
      if (patch.vaultAttachmentsPath !== undefined) {
        await api.updateConfig('export.attachments_folder', patch.vaultAttachmentsPath)
      }
      if (patch.author !== undefined) {
        await api.updateConfig('export.author', patch.author)
      }
    } catch (err) { console.error('Settings save failed:', err) }
  }, [])

  function setTheme(theme: 'dark' | 'light') {
    localStorage.setItem('skrift.theme', theme)
    document.documentElement.classList.toggle('dark', theme === 'dark')
    document.documentElement.classList.toggle('light', theme !== 'dark')
    void update({ theme })
  }

  return { settings, update, setTheme, defaultPrompts }
}
