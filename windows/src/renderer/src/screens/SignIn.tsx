import { useState } from 'react'
import * as cloud from '@/lib/cloud'

/** Sign in with the same Orbit account as on the Mac; your data comes down right after. */
export default function SignIn({ platform }: { platform: string }) {
  const [mode, setMode] = useState<'signIn' | 'signUp'>('signIn')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  const run = async (work: () => Promise<void>) => {
    setBusy(true)
    setMessage(null)
    try { await work() } catch (e) { setMessage((e as Error).message) } finally { setBusy(false) }
  }

  const submit = () => run(async () => {
    if (mode === 'signIn') await cloud.signIn(email.trim(), password)
    else if ((await cloud.signUp(email.trim(), password)) === 'checkEmail') {
      setMessage('Check your inbox to confirm your email, then sign in.')
      setMode('signIn')
    }
  })

  return (
    <div style={{ height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', WebkitAppRegion: 'drag' } as React.CSSProperties}>
      <div className="col" style={{ width: 400, gap: 18, WebkitAppRegion: 'no-drag' } as React.CSSProperties}>
        <div className="logo" style={{ fontSize: 44 }}>orbit<i /></div>
        <div>
          <h1 className="page-title" style={{ fontSize: 30 }}>{mode === 'signIn' ? 'Welcome back' : 'Create your account'}</h1>
          <p className="secondary" style={{ margin: '6px 0 0' }}>
            {mode === 'signIn'
              ? 'Sign in with the same account you use on your Mac and everything comes with you.'
              : 'Your tasks, money, journal, reading and dreams, synced between your computers.'}
          </p>
        </div>
        {!cloud.isConfigured() && <div className="card" style={{ background: 'var(--peach)', color: 'var(--sticker-ink)' }}>Sync isn't set up in this copy of Orbit.</div>}
        <button className="btn-soft" style={{ justifyContent: 'center', padding: '12px 16px', fontSize: 14 }} disabled={busy}
          onClick={() => run(() => cloud.signInWithGoogle())}>
          <GoogleG /> Continue with Google
        </button>
        <div className="row muted" style={{ fontSize: 12 }}><span style={{ flex: 1, height: 1, background: 'var(--line)' }} />or<span style={{ flex: 1, height: 1, background: 'var(--line)' }} /></div>
        <input className="field" placeholder="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoFocus />
        <input className="field" placeholder="Password" type="password" value={password} onChange={(e) => setPassword(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') submit() }} />
        <button className="btn-primary" disabled={busy || !email.includes('@') || password.length < 6} onClick={submit}>
          {busy ? 'One moment…' : mode === 'signIn' ? 'Sign in' : 'Create account'}
        </button>
        {message && <div style={{ fontSize: 13, color: message.startsWith('Check') ? 'var(--good)' : 'var(--critical)' }}>{message}</div>}
        <div className="row" style={{ fontSize: 13 }}>
          <button className="link" onClick={() => setMode(mode === 'signIn' ? 'signUp' : 'signIn')}>
            {mode === 'signIn' ? 'New here? Create an account' : 'Already have an account? Sign in'}
          </button>
          <span className="spacer" />
          {mode === 'signIn' && (
            <button className="link" disabled={!email.includes('@')}
              onClick={() => run(async () => { await cloud.resetPassword(email.trim()); setMessage('Check your inbox for a link to reset your password.') })}>
              Forgot password?
            </button>
          )}
        </div>
        {platform === 'darwin' && <p className="muted" style={{ fontSize: 11 }}>Preview build running on macOS.</p>}
      </div>
    </div>
  )
}

function GoogleG() {
  return (
    <svg width="16" height="16" viewBox="0 0 48 48" aria-hidden>
      <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34.1 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z" />
      <path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34.1 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" />
      <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.5 39.6 16.2 44 24 44z" />
      <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z" />
    </svg>
  )
}
