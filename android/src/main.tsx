import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@/theme.css'
import './mobile.css'
import { installBridge } from './bridge'
import App from './App'

installBridge()
createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>)
