// What you see when you're signed out, as on the iPhone. The very first time (PhoneWelcome): Joshu on your phone, with
// signing in or creating an account right there. After that, e.g. once you've signed out (SignedOutWelcome): Welcome to
// Joshu, the same panel, and carrying on without an account. Choosing to carry on is remembered, so the app opens
// straight into your data (kept on this phone only, see store.startLocal()) until you sign in.
import { RefreshCw, Sparkles, Lock } from 'lucide-react'
import type { ReactNode } from 'react'
import { Orb } from '../components/Orb'
import PhoneSignIn from './PhoneSignIn'
import '../onboarding.css'

/** Set when you choose "Use Joshu without an account"; cleared when you sign in or delete your account. */
export const WITHOUT_ACCOUNT_KEY = 'auth.withoutAccount'
/** Set once you've signed in or chosen to carry on, so later visits show the signed-out welcome instead. */
const ONBOARDED_KEY = 'phoneOnboarded'

export function usesJoshuWithoutAccount(): boolean {
  try { return localStorage.getItem(WITHOUT_ACCOUNT_KEY) === '1' } catch { return false }
}

export function setUsesJoshuWithoutAccount(on: boolean): void {
  try { if (on) localStorage.setItem(WITHOUT_ACCOUNT_KEY, '1'); else localStorage.removeItem(WITHOUT_ACCOUNT_KEY) } catch { /* private storage */ }
}

/** Also true on a phone that has had Joshu data before (e.g. signed out after using it before this key existed). */
const onboarded = (): boolean => {
  try { return localStorage.getItem(ONBOARDED_KEY) === '1' || Object.keys(localStorage).some((k) => k.startsWith('orbit.cache.')) } catch { return true }
}
const markOnboarded = (): void => { try { localStorage.setItem(ONBOARDED_KEY, '1') } catch { /* private storage */ } }

const POINTS: { icon: ReactNode; text: string; tint: string }[] = [
  { icon: <RefreshCw size={12} strokeWidth={2.8} />, text: 'Your tasks, money, books and ideas on your phone and computer, always in sync', tint: 'var(--lime)' },
  { icon: <Sparkles size={12} strokeWidth={2.8} />, text: 'An assistant you name yourself, that knows your day and gets things done', tint: 'var(--pink)' },
  { icon: <Lock size={12} strokeWidth={2.8} />, text: 'Backed up to your account, and only you can see it', tint: 'var(--cyan)' },
]

/**
 * `onSignIn` / `onCreateAccount` are no longer needed (signing in happens right here; the app notices through
 * cloud.onSessionChange) and are kept only so older wiring still compiles.
 */
export default function Welcome({ onCarryOn }: { onSignIn?: () => void; onCreateAccount?: () => void; onCarryOn: () => void }) {
  const first = !onboarded()
  const carryOn = () => { markOnboarded(); setUsesJoshuWithoutAccount(true); onCarryOn() }
  return first ? <FirstLaunch onCarryOn={carryOn} /> : <SignedOut onCarryOn={carryOn} />
}

/** The iPhone's PhoneWelcome: the first launch on this phone. */
function FirstLaunch({ onCarryOn }: { onCarryOn: () => void }) {
  return (
    <div className="po-screen">
      <div className="po-welcome-scroll" style={{ paddingTop: 'calc(env(safe-area-inset-top) + 24px)' }}>
        <div className="col" style={{ gap: 22, maxWidth: 440, margin: '0 auto' }}>
          <Orb size={72} style={{ marginTop: 40 }} />
          <div className="col" style={{ gap: 8 }}>
            <h1 className="page-title" style={{ fontSize: 34 }}>Joshu on your phone</h1>
            <span className="secondary" style={{ fontSize: 15, lineHeight: 1.4 }}>
              Sign in with the account you use on your other devices and everything comes across: tasks, calendar, habits, money, notes, books, trips and your assistant.
            </span>
          </div>
          <PhoneSignIn onSignedIn={markOnboarded} />
          <button className="po-link" style={{ fontSize: 14, alignSelf: 'flex-start' }} onClick={onCarryOn}>Use Joshu without an account</button>
        </div>
      </div>
    </div>
  )
}

/** The Mac and iPhone's SignedOutWelcome. */
function SignedOut({ onCarryOn }: { onCarryOn: () => void }) {
  return (
    <div className="po-screen" style={{ animation: 'fade 0.4s ease-out' }}>
      {/* Soft blobs in the orb's colours behind everything */}
      <div className="po-blobs" aria-hidden>
        <span className="po-blob" style={{ width: '70vw', height: '70vw', left: '-30vw', top: '-12vh', background: 'var(--lime)', opacity: 0.55 }} />
        <span className="po-blob" style={{ width: '60vw', height: '60vw', right: '-22vw', top: '42vh', background: 'var(--cyan)', opacity: 0.35 }} />
        <span className="po-blob" style={{ width: '45vw', height: '45vw', left: '20vw', bottom: '-8vh', background: 'var(--pink)', opacity: 0.3 }} />
      </div>

      <div className="po-welcome-scroll">
        <div className="po-welcome-col">
          <div className="col" style={{ gap: 22 }}>
            <div className="po-wordmark" style={{ fontSize: 46, letterSpacing: -1.5 }}>joshu<Orb size={14} spark={false} /></div>
            <div className="col" style={{ gap: 10 }}>
              <h1 className="page-title" style={{ fontSize: 34 }}>Welcome to Joshu</h1>
              <span className="secondary" style={{ fontSize: 16, lineHeight: 1.4 }}>
                Your whole life, in one calm place. Create an account or sign in to bring everything back.
              </span>
            </div>
            <div className="col" style={{ gap: 12 }}>
              {POINTS.map((p) => (
                <div key={p.text} className="row" style={{ gap: 12, alignItems: 'flex-start' }}>
                  <span className="po-dot" style={{ background: p.tint }}>{p.icon}</span>
                  <span style={{ fontSize: 15, lineHeight: 1.35, paddingTop: 4 }}>{p.text}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="col" style={{ gap: 14 }}>
            <div className="po-auth-card"><PhoneSignIn onSignedIn={markOnboarded} /></div>
            <button className="po-link" style={{ fontSize: 14, alignSelf: 'center' }} onClick={onCarryOn}>Use Joshu without an account</button>
          </div>
        </div>
      </div>
    </div>
  )
}
