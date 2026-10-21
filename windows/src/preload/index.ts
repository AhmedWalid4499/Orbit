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
}

contextBridge.exposeInMainWorld('orbit', api)
export type OrbitBridge = typeof api
