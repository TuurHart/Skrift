interface ElectronFileDialogOptions {
  accept?: string[]
  multiple?: boolean
}

interface ElectronAPI {
  openFileDialog: (options?: ElectronFileDialogOptions) => Promise<string[] | null>
  openFolderDialog: () => Promise<string | null>
  openUploadDialog: () => Promise<{ files: string[]; folders: string[] } | null>
  classifyPaths: (paths: string[]) => Promise<{ files: string[]; folders: string[] }>
  getSystemInfo: () => Promise<{
    appVersion: string
    platform: string
    electronVersion: string
    nodeVersion: string
  }>
  getSystemTheme: () => Promise<'dark' | 'light'>
  onMenuPreferences: (cb: () => void) => () => void
  // Find in page
  onToggleFind: (cb: () => void) => () => void
  onFindNext: (cb: () => void) => () => void
  onCloseFind: (cb: () => void) => () => void
  findInPage: (text: string, options?: { forward?: boolean; findNext?: boolean }) => Promise<void>
  stopFindInPage: (action?: string) => Promise<void>
  onFoundInPage: (cb: (result: { active: number; total: number }) => void) => () => void
}

declare global {
  interface Window {
    electronAPI?: ElectronAPI
    electronAPIError?: string
  }
}

export {}
