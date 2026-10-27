// Settings › Connections › Goodreads: sign in so Joshu can update your progress and post reviews
// (GoodreadsSyncRow in GoodreadsSync.swift on the Mac and iPhone).
import { useState } from 'react'
import { signIn, signOut, setAutoProgress, useGoodreads } from '../lib/goodreads'

/** Goodreads' "g" on its cream tile. */
export function GoodreadsLogo({ size = 28 }: { size?: number }) {
  return (
    <span style={{
      width: size, height: size, borderRadius: size * 0.24, background: '#F4F1EA', color: '#382110', flex: 'none',
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', boxShadow: 'inset 0 0 0 1px rgba(0,0,0,0.08)',
      fontFamily: 'Georgia, "Times New Roman", serif', fontWeight: 700, fontSize: size * 0.7, lineHeight: 1, paddingBottom: size * 0.12,
    }}>g</span>
  )
}

export default function GoodreadsSettings() {
  const gr = useGoodreads()
  const [working, setWorking] = useState(false)

  const start = async () => {
    setWorking(true)
    try { await signIn() } finally { setWorking(false) }
  }

  return (
    <div className="card col" style={{ gap: 10, padding: 14 }}>
      <div className="row" style={{ gap: 12, alignItems: 'center' }}>
        <GoodreadsLogo />
        <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
          <strong style={{ fontSize: 15 }}>Goodreads updates</strong>
          <span className="secondary" style={{ fontSize: 12 }}>
            {gr.signedIn ? 'Joshu sends your progress and reviews to Goodreads.' : 'Sign in once so Joshu can update your progress and post your reviews.'}
          </span>
        </div>
        {gr.signedIn
          ? <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => void signOut()}>Sign out</button>
          : <button className="btn-primary" disabled={working} onClick={start}>{working ? 'Signing in…' : 'Sign in'}</button>}
      </div>
      {gr.signedIn && (
        <label className="row" style={{ gap: 10, fontSize: 13, minHeight: 36 }}>
          <span style={{ flex: 1 }}>Send my progress automatically</span>
          <input type="checkbox" checked={gr.autoProgress} onChange={(e) => setAutoProgress(e.target.checked)}
            style={{ width: 20, height: 20, accentColor: 'var(--ink)' }} />
        </label>
      )}
      {gr.busy && <span className="muted" style={{ fontSize: 12 }}>Talking to Goodreads…</span>}
      {gr.status && <span className="secondary" style={{ fontSize: 12 }}>{gr.status}</span>}
    </div>
  )
}
