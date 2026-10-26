import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@/theme.css'
import './mobile.css'
import { StatusBar, Style } from '@capacitor/status-bar'
import { installBridge } from './bridge'
import { isNative } from './native'
import App from './App'

installBridge()
// Phones open the calendar on one day (the week view is too narrow); you can still switch.
if (!localStorage.getItem('orbit.calendarMode')) localStorage.setItem('orbit.calendarMode', 'day')

// Status bar follows the app's light or dark look.
if (isNative) {
  const paint = (dark: boolean) => {
    StatusBar.setStyle({ style: dark ? Style.Dark : Style.Light }).catch(() => {})
    StatusBar.setBackgroundColor({ color: dark ? '#111113' : '#ffffff' }).catch(() => {})
  }
  const mq = matchMedia('(prefers-color-scheme: dark)')
  paint(mq.matches)
  mq.addEventListener('change', (e) => paint(e.matches))
}
createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>)
