import { contextBridge, ipcRenderer } from 'electron'

/** The small set of things the Orbit window may ask of the desktop. */
const api = {
  config: (): Promise<{ supabase: { url: string; key: string }; version: string; platform: string; canUpdate: boolean }> =>
    ipcRenderer.invoke('config'),
  openExternal: (url: string): Promise<void> => ipcRenderer.invoke('open-external', url),
  onAuthCallback: (fn: (url: string) => void): void => { ipcRenderer.on('auth-callback', (_e, url: string) => fn(url)) },
  checkForUpdates: (): Promise<void> => ipcRenderer.invoke('check-updates'),
  installUpdate: (): Promise<void> => ipcRenderer.invoke('install-update'),
  onUpdate: (fn: (s: { state: string; version?: string; progress?: number; message?: string }) => void): void => {
    ipcRenderer.on('update-status', (_e, s) => fn(s))
  },

  // Claude (runs in the desktop process; the key never reaches the page)
  claudeTurn: (req: unknown): Promise<any> => ipcRenderer.invoke('claude-turn', req),
  claudeStructured: (req: unknown): Promise<{ ok: boolean; data?: any; error?: string }> => ipcRenderer.invoke('claude-structured', req),
  claudeTest: (): Promise<{ ok: boolean; message?: string }> => ipcRenderer.invoke('claude-test'),
  onClaudeDelta: (fn: (d: { id: string; text: string }) => void): (() => void) => {
    const h = (_e: unknown, d: { id: string; text: string }) => fn(d)
    ipcRenderer.on('claude-delta', h)
    return () => ipcRenderer.removeListener('claude-delta', h)
  },

  // Keys, sign-ins and the encrypted vault shared with the Mac
  secretsStatus: (): Promise<{ anthropic: boolean; googleClient: boolean; passphrase: boolean; gmail: string[] }> => ipcRenderer.invoke('secrets-status'),
  setSecret: (name: string, value: string): Promise<boolean> => ipcRenderer.invoke('secret-set', name, value),
  vaultSync: (req: unknown): Promise<{ state: string; message?: string }> => ipcRenderer.invoke('vault-sync', req),
  vaultForget: (): Promise<void> => ipcRenderer.invoke('vault-forget'),

  // Google / Gmail
  googleSignIn: (hint?: string): Promise<{ ok: boolean; email?: string; error?: string }> => ipcRenderer.invoke('google-sign-in', hint),
  googleGet: (email: string, url: string): Promise<{ ok: boolean; status: number; data?: any; error?: string }> => ipcRenderer.invoke('google-get', email, url),
  googleRemove: (email: string): Promise<void> => ipcRenderer.invoke('google-remove', email),
}

contextBridge.exposeInMainWorld('orbit', api)
export type OrbitBridge = typeof api
