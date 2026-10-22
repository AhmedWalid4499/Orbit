import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './theme.css'
import App from './App'

// Outside Electron (a plain browser preview) there's no desktop bridge: provide a harmless stand-in.
if (!(window as any).orbit) {
  ;(window as any).orbit = {
    config: async () => ({ supabase: { url: '', key: '' }, version: 'preview', platform: 'browser', canUpdate: false }),
    openExternal: async (url: string) => { window.open(url, '_blank') },
    onAuthCallback: () => {}, checkForUpdates: async () => {}, installUpdate: async () => {}, onUpdate: () => {},
    claudeTurn: async () => ({ ok: false, error: 'Claude runs in the desktop app (preview).' }),
    claudeStructured: async () => ({ ok: false, error: 'Claude runs in the desktop app (preview).' }),
    claudeTest: async () => ({ ok: false, message: 'Preview' }),
    onClaudeDelta: () => () => {},
    secretsStatus: async () => ({ anthropic: true, googleClient: true, passphrase: true, gmail: ['you@gmail.com'] }),
    setSecret: async () => true, vaultSync: async () => ({ state: 'on' }), vaultForget: async () => {},
    googleSignIn: async () => ({ ok: false, error: 'Preview' }), googleGet: async () => ({ ok: false, status: 0, error: 'Preview' }), googleRemove: async () => {},
  }
}

createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>)
