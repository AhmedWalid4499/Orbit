// Joshu Pro, as the Mac and iPhone show it (ProSheet in ProView.swift): what you get and the small print. Android
// has no in-app purchase, so instead of the two plans it explains that Pro comes with your Joshu account (bought
// on iPhone, or added to your account) and offers "Check my plan".
import { useEffect, useState } from 'react'
import { Sparkles, Sun, Mail, TrendingUp, Briefcase, Inbox, RefreshCw } from 'lucide-react'
import { Modal } from '@/components/ui'
import { refreshKeys, useAssistantName } from '@/lib/ai'
import { getSession } from '@/lib/cloud'
import { Orb } from './Orb'
import { isPro, proUntil, refreshPro, onProChange } from '../pro'
import '../screens/Assistant.css'

export const PRO_FEATURES = [
  { text: 'Your own AI assistant, named by you: ask anything, plan, write, code, by voice or text', icon: <Sparkles size={14} strokeWidth={2.6} />, tint: 'var(--lime)' },
  { text: 'Morning brief and a summary of your day', icon: <Sun size={14} strokeWidth={2.6} />, tint: 'var(--peach)' },
  { text: 'Email summaries: what needs a reply, what matters', icon: <Mail size={14} strokeWidth={2.6} />, tint: 'var(--pink)' },
  { text: 'Money coach and smart money insights', icon: <TrendingUp size={14} strokeWidth={2.6} />, tint: 'var(--mint)' },
  { text: 'LinkedIn job alerts, read from your email', icon: <Briefcase size={14} strokeWidth={2.6} />, tint: 'var(--cyan)' },
  { text: 'Connect as many email accounts as you like', icon: <Inbox size={14} strokeWidth={2.6} />, tint: 'var(--pa-lavender)' },
]

export function usePro(): boolean {
  const [on, setOn] = useState(isPro())
  useEffect(() => onProChange(() => setOn(isPro())), [])
  return on
}

export default function ProSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const pro = usePro()
  const name = useAssistantName()
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const signedIn = !!getSession()

  useEffect(() => { if (open) { setMessage(''); refreshPro() } }, [open])

  const check = async () => {
    setBusy(true); setMessage('')
    const on = await refreshPro()
    await refreshKeys()
    setBusy(false)
    setMessage(on ? `Pro is on. ${name} is ready.` : "Pro isn't on this account yet. If you just got it, give it a minute and check again.")
  }
  const until = proUntil()
  const link = (url: string) => () => window.orbit.openExternal(url)

  return (
    <Modal open={open} onClose={onClose}>
      <div className="pa-pro">
        <div>
          <div className="pa-pro-title"><Orb size={44} /><h2>Joshu Pro</h2></div>
          <p className="pa-pro-lead">{pro ? "You're on Pro. Thanks for supporting Joshu." : 'Everything in Joshu, plus your AI assistant and the smart features that save you time. No API keys, nothing to set up.'}</p>
        </div>
        <div className="pa-features">
          {PRO_FEATURES.map((f) => (
            <div key={f.text} className="pa-feature" style={{ ['--pa-tint' as string]: f.tint }}><span className="ic">{f.icon}</span>{f.text}</div>
          ))}
        </div>
        <div className="pa-plan">
          {pro ? <>
            <strong>Pro is on for your account</strong>
            <p>{until && until < 4102444800000 ? `Your plan runs until ${new Date(until).toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })}.` : 'It works on every device you sign in to.'}</p>
          </> : <>
            <strong>Pro comes with your Joshu account</strong>
            <p>{signedIn
              ? "There's nothing to buy on Android: once Pro is on your Joshu account (from Joshu on iPhone, or added for you), it turns on here too. Tap Check my plan after you get it."
              : 'Sign in to your Joshu account first (Settings › Account). Once Pro is on your account, from Joshu on iPhone or added for you, it turns on here too.'}</p>
          </>}
          {signedIn && (
            <button className="pa-primary" disabled={busy} onClick={check}><RefreshCw size={15} className={busy ? 'spin' : ''} />{busy ? 'Checking…' : 'Check my plan'}</button>
          )}
          {message && <div className="msg">{message}</div>}
        </div>
        <div className="pa-small">
          <div>Free keeps everything else: tasks, calendar, habits, money, reading, ideas, notes, sync across your devices, and one email account.</div>
          <div className="muted">The assistant's use is fair-use limited.</div>
          <div className="pa-links">
            <button onClick={link('https://ahmedwalid4499.github.io/Orbit/terms/')}>Terms of Use</button>
            <button onClick={link('https://ahmedwalid4499.github.io/Orbit/privacy/')}>Privacy</button>
          </div>
        </div>
      </div>
    </Modal>
  )
}
