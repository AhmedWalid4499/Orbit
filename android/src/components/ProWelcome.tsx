// "Welcome to Joshu Pro" (ProWelcome.swift): shown once per account, the first time Pro is on (from the iPhone or
// added to the account): what's now unlocked, and a name for the assistant.
// <ProWelcomeHost onOpenAssistant={…} /> watches the plan and shows it by itself; <ProWelcome /> is the page.
import { useEffect, useState } from 'react'
import { Sparkles, Sun, Mail, TrendingUp, AudioLines, Briefcase } from 'lucide-react'
import { store } from '@/lib/store'
import { getSession } from '@/lib/cloud'
import { Orb } from './Orb'
import { isPro, onProChange } from '../pro'
import '../screens/Assistant.css'

const welcomeKey = () => `pro.welcomed.${getSession()?.userID ?? 'device'}`
export const proWelcomeDue = (): boolean => { try { return isPro() && localStorage.getItem(welcomeKey()) !== 'true' } catch { return false } }
export const markProWelcomed = (): void => { try { localStorage.setItem(welcomeKey(), 'true') } catch { /* private mode */ } }

const UNLOCKED = [
  { icon: <Sparkles size={15} strokeWidth={2.6} />, title: 'Your own assistant', text: 'Ask, plan, write and code, by voice or text', tint: 'var(--lime)' },
  { icon: <Sun size={15} strokeWidth={2.6} />, title: 'Morning brief', text: 'What matters today, ready when you wake up', tint: 'var(--peach)' },
  { icon: <Mail size={15} strokeWidth={2.6} />, title: 'Email summaries', text: 'What needs a reply, and what can wait', tint: 'var(--pink)' },
  { icon: <TrendingUp size={15} strokeWidth={2.6} />, title: 'Money coach', text: 'Where your money goes, and how to keep more', tint: 'var(--mint)' },
  { icon: <AudioLines size={15} strokeWidth={2.6} />, title: 'Hands-free', text: 'Just say “Hey” and its name', tint: 'var(--cyan)' },
  { icon: <Briefcase size={15} strokeWidth={2.6} />, title: 'LinkedIn job alerts', text: 'Every alert, laid out job by job', tint: 'var(--pa-lavender)' },
]

export default function ProWelcome({ onDone, onOpenAssistant }: { onDone: () => void; onOpenAssistant?: () => void }) {
  const [name, setName] = useState(() => (store.setting<string>('assistantName') ?? '').trim() || 'Joshu')
  const trimmed = name.trim() || 'Joshu'
  const finish = (open: boolean) => {
    store.setSetting('assistantName', trimmed)
    markProWelcomed()
    onDone()
    if (open && onOpenAssistant) setTimeout(onOpenAssistant, 400)
  }
  return (
    <div className="pa-welcome" role="dialog" aria-label="Welcome to Joshu Pro">
      <div className="pa-welcome-bg">
        <i style={{ width: '70vw', height: '70vw', left: '-20vw', top: '-15vh', background: 'color-mix(in srgb, var(--lime) 50%, transparent)', filter: 'blur(90px)' }} />
        <i style={{ width: '60vw', height: '60vw', right: '-25vw', top: '20vh', background: 'color-mix(in srgb, var(--purple) 35%, transparent)', filter: 'blur(100px)' }} />
        <i style={{ width: '50vw', height: '50vw', left: '25vw', bottom: '-10vh', background: 'color-mix(in srgb, var(--cyan) 30%, transparent)', filter: 'blur(90px)' }} />
      </div>
      <div className="pa-welcome-in">
        <div className="pa-welcome-orb"><Orb size={104} busy /></div>
        <div className="pa-rise">
          <h1>Welcome to Joshu Pro</h1>
          <p className="pa-welcome-lead">Your assistant is ready. Everything below is now on, on your phone and your other devices.</p>
        </div>
        <div className="pa-unlocked">
          {UNLOCKED.map((u, i) => (
            <div key={u.title} className="pa-rise" style={{ animationDelay: `${0.25 + i * 0.06}s`, ['--pa-tint' as string]: u.tint }}>
              <span className="ic">{u.icon}</span>
              <strong>{u.title}</strong>
              <span>{u.text}</span>
            </div>
          ))}
        </div>
        <div className="pa-name">
          <label htmlFor="pa-name">What would you like to call your assistant?</label>
          <input id="pa-name" value={name} placeholder="Joshu" enterKeyHint="go" onChange={(e) => setName(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') finish(true) }} />
          <small>You can change it any time in Settings.</small>
        </div>
        <div className="pa-welcome-actions">
          <button className="pa-primary" onClick={() => finish(true)}>Say hello to {trimmed}</button>
          <button className="pa-link" onClick={() => finish(false)}>Maybe later</button>
        </div>
      </div>
    </div>
  )
}

/** Shows the welcome by itself the first time Pro turns on for this account. */
export function ProWelcomeHost({ onOpenAssistant }: { onOpenAssistant?: () => void }) {
  const [show, setShow] = useState(proWelcomeDue())
  useEffect(() => onProChange(() => { if (proWelcomeDue()) setShow(true) }), [])
  return show ? <ProWelcome onDone={() => setShow(false)} onOpenAssistant={onOpenAssistant} /> : null
}
