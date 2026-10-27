// Welcome to Joshu (the Mac and iPhone's SignedOutWelcome): what you see when you're signed out, with creating an
// account, signing in, or carrying on without one. Choosing to carry on is remembered, so the app opens straight
// into your data (kept on this phone only, see store.startLocal()) until you sign in.
import { RefreshCw, Sparkles, Lock } from 'lucide-react'
import type { ReactNode, CSSProperties } from 'react'

/** Set when you choose "Use Joshu without an account"; cleared when you sign in or delete your account. */
export const WITHOUT_ACCOUNT_KEY = 'auth.withoutAccount'

export function usesJoshuWithoutAccount(): boolean {
  try { return localStorage.getItem(WITHOUT_ACCOUNT_KEY) === '1' } catch { return false }
}

export function setUsesJoshuWithoutAccount(on: boolean): void {
  try { if (on) localStorage.setItem(WITHOUT_ACCOUNT_KEY, '1'); else localStorage.removeItem(WITHOUT_ACCOUNT_KEY) } catch { /* private storage */ }
}

const POINTS: { icon: ReactNode; text: string; tint: string }[] = [
  { icon: <RefreshCw size={13} strokeWidth={2.6} />, text: 'Your tasks, money, books and ideas on your phone, Mac and iPhone, always in sync', tint: 'var(--lime)' },
  { icon: <Sparkles size={13} strokeWidth={2.6} />, text: 'An assistant you name yourself, that knows your day and gets things done', tint: 'var(--pink)' },
  { icon: <Lock size={13} strokeWidth={2.6} />, text: 'Backed up to your account, and only you can see it', tint: 'var(--cyan)' },
]

export default function Welcome({ onSignIn, onCreateAccount, onCarryOn }: { onSignIn: () => void; onCreateAccount: () => void; onCarryOn: () => void }) {
  const carryOn = () => { setUsesJoshuWithoutAccount(true); onCarryOn() }
  return (
    <div style={{ position: 'fixed', inset: 0, background: 'var(--canvas)', overflow: 'hidden' }}>
      {/* Soft blobs in the orb's colours behind everything */}
      <div aria-hidden style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
        <span style={{ ...blob, width: '70vw', height: '70vw', left: '-30vw', top: '-12vh', background: 'var(--lime)', opacity: 0.5 }} />
        <span style={{ ...blob, width: '60vw', height: '60vw', right: '-22vw', top: '42vh', background: 'var(--cyan)', opacity: 0.32 }} />
        <span style={{ ...blob, width: '45vw', height: '45vw', left: '20vw', bottom: '-8vh', background: 'var(--pink)', opacity: 0.28 }} />
      </div>

      <div style={{ position: 'relative', height: '100%', overflowY: 'auto', padding: 'calc(env(safe-area-inset-top) + 36px) 24px calc(env(safe-area-inset-bottom) + 28px)' }}>
        <div className="col" style={{ gap: 28, maxWidth: 440, margin: '0 auto', minHeight: '100%', justifyContent: 'center' }}>
          <div className="col" style={{ gap: 22 }}>
            <div className="logo" style={{ fontSize: 46 }}>joshu<i /></div>
            <div className="col" style={{ gap: 10 }}>
              <h1 className="page-title" style={{ fontSize: 34 }}>Welcome to Joshu</h1>
              <span className="secondary" style={{ fontSize: 16, lineHeight: 1.4 }}>
                Your whole life, in one calm place. Create an account or sign in to bring everything back.
              </span>
            </div>
            <div className="col" style={{ gap: 12 }}>
              {POINTS.map((p) => (
                <div key={p.text} className="row" style={{ gap: 12, alignItems: 'flex-start' }}>
                  <span style={{ width: 28, height: 28, borderRadius: '50%', background: p.tint, color: 'var(--sticker-ink)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
                    {p.icon}
                  </span>
                  <span style={{ fontSize: 15, lineHeight: 1.35, paddingTop: 4 }}>{p.text}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="col" style={{ gap: 14 }}>
            <div className="col" style={{ gap: 10, padding: 20, borderRadius: 24, background: 'color-mix(in srgb, var(--canvas) 92%, transparent)', border: '1px solid var(--line)', boxShadow: '0 10px 24px rgba(0,0,0,0.08)' }}>
              <button className="btn-primary" style={{ height: 48, fontSize: 15 }} onClick={onCreateAccount}>Create account</button>
              <button className="btn-soft" style={{ height: 48, fontSize: 15, justifyContent: 'center' }} onClick={onSignIn}>Sign in</button>
            </div>
            <button className="link" style={{ fontSize: 14, minHeight: 40, alignSelf: 'center' }} onClick={carryOn}>Use Joshu without an account</button>
          </div>
        </div>
      </div>
    </div>
  )
}

const blob: CSSProperties = { position: 'absolute', borderRadius: '50%', filter: 'blur(70px)' }
