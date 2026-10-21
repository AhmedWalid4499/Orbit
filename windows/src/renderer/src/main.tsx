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
  }
}

createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>)
