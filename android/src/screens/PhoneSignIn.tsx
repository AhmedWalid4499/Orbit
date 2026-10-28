// Sign in or create a Joshu account, as on the Mac and iPhone (AuthPanel.swift): Create account / Sign in, email and
// password, then the standard "Sign in with Google" button. Used inside Welcome; opens in create-account mode.
import { useState } from 'react'
import { AlertTriangle, Mail } from 'lucide-react'
import * as cloud from '@/lib/cloud'
import '../onboarding.css'

export default function PhoneSignIn({ startCreating = true, onSignedIn }: { startCreating?: boolean; onSignedIn?: () => void }) {
  const [creating, setCreating] = useState(startCreating)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [working, setWorking] = useState(false)
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null)
  const ok = email.includes('@') && password.length >= 6

  const show = (text: string, error = false) => setMessage({ text, error })
  const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e))

  const submit = async () => {
    if (working || !ok) return
    setWorking(true); setMessage(null)
    const e = email.trim()
    try {
      if (creating) {
        if ((await cloud.signUp(e, password)) === 'checkEmail') {
          show(`Almost done: open the email we sent to ${e}, tap the link, then sign in here.`)
          setCreating(false)
        } else { setPassword(''); onSignedIn?.() }
      } else {
        await cloud.signIn(e, password)
        setPassword(''); onSignedIn?.()
      }
    } catch (err) { show(errorText(err), true) } finally { setWorking(false) }
  }

  const google = async () => {
    setWorking(true); setMessage(null)
    try { await cloud.signInWithGoogle(); if (cloud.getSession()) onSignedIn?.() }
    catch (err) { if (!/cancel/i.test(errorText(err))) show(errorText(err), true) }
    finally { setWorking(false) }
  }

  const forgot = async () => {
    try { await cloud.resetPassword(email.trim()); show(`Check ${email.trim()} for a link to reset your password.`) }
    catch (err) { show(errorText(err), true) }
  }

  return (
    <div className="po-auth">
      <div className="po-seg" role="tablist">
        <button role="tab" className={creating ? 'on' : ''} aria-selected={creating} onClick={() => { setCreating(true); setMessage(null) }}>Create account</button>
        <button role="tab" className={!creating ? 'on' : ''} aria-selected={!creating} onClick={() => { setCreating(false); setMessage(null) }}>Sign in</button>
      </div>

      <div className="col" style={{ gap: 10 }}>
        <input className="po-field" type="email" inputMode="email" autoCapitalize="off" autoCorrect="off" autoComplete="username" placeholder="Email"
          value={email} onChange={(e) => setEmail(e.target.value)} />
        <input className="po-field" type="password" autoComplete={creating ? 'new-password' : 'current-password'}
          placeholder={creating ? 'Password (at least 6 characters)' : 'Password'}
          value={password} onChange={(e) => setPassword(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') submit() }} />
      </div>

      <button className="btn-primary po-primary" style={{ height: 46, fontSize: 15, gap: 8 }} disabled={working || !ok} onClick={submit}>
        {working && <span className="po-spin" />}{creating ? 'Create account' : 'Sign in'}
      </button>

      {!creating && (
        <button className="link" style={{ alignSelf: 'flex-start', fontSize: 12 }} disabled={!email.includes('@')} onClick={forgot}>Forgot password?</button>
      )}

      <div className="po-or">or</div>

      <button className="po-google" disabled={working} onClick={google}>
        <GoogleG /> Sign in with Google {working && <span className="po-spin" />}
      </button>

      {!cloud.isConfigured() && <div className="po-msg" style={{ color: 'var(--orange)' }}><AlertTriangle size={14} style={{ flex: 'none' }} />Sync isn't set up in this copy of Joshu.</div>}
      {message && (
        <div className="po-msg" style={{ color: message.error ? 'var(--orange)' : 'var(--ink2)' }}>
          {message.error ? <AlertTriangle size={14} style={{ flex: 'none', marginTop: 1 }} /> : <Mail size={14} style={{ flex: 'none', marginTop: 1 }} />}
          <span>{message.text}</span>
        </div>
      )}
      <p className="po-foot-note">Your account keeps your data in sync between your devices and backs it up. Only you can see it.</p>
    </div>
  )
}

/** Google's four-colour "G". */
function GoogleG() {
  return (
    <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden>
      <path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.6 5.4 2.7 13.3l7.9 6.1C12.5 13.6 17.8 9.5 24 9.5z" />
      <path fill="#4285F4" d="M46.1 24.6c0-1.6-.1-3.1-.4-4.6H24v9h12.4c-.5 2.9-2.2 5.3-4.6 6.9l7.5 5.8c4.4-4 6.8-10 6.8-17.1z" />
      <path fill="#FBBC05" d="M10.5 28.6c-.5-1.4-.8-3-.8-4.6s.3-3.1.8-4.6l-7.9-6.1C1 16.6 0 20.2 0 24s1 7.4 2.7 10.7l7.8-6.1z" />
      <path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.5-5.8c-2.1 1.4-4.8 2.3-8.4 2.3-6.2 0-11.5-4.2-13.4-9.9l-7.9 6.1C6.6 42.6 14.6 48 24 48z" />
    </svg>
  )
}
