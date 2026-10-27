// Settings on Android: the Windows app's account, AI and email sections, plus bank texts (SMS),
// what the assistant remembers, and updates from the GitHub release.
import { useEffect, useState } from 'react'
import { RefreshCw, MessageSquareText, Trash2, Download, Link2 } from 'lucide-react'
import * as cloud from '@/lib/cloud'
import { store, useSetting, useStoreVersion } from '@/lib/store'
import { Modal, defaultCurrency } from '@/components/ui'
import { relativeTime } from '@/lib/dates'
import { AISection, EmailSection, Section, Field } from '@/screens/Settings'
import { BANKS, chosenBanks, setChosenBanks, extraSenders, setExtraSenders } from '../bank'
import { smsEnabled, enableSms, disableSms, checkBankTexts, smsActivity, onSmsChange } from '../sms'
import { memories, setMemories } from './Assistant'
import { isNative } from '../native'
import DeleteAccount from '../components/DeleteAccount'
import Connections from './Connections'
import { isPro, proUntil, refreshPro, onProChange } from '../pro'
import { refreshKeys } from '@/lib/ai'
import { Orb } from '../components/Orb'
import { wakeEnabled, setWakeEnabled } from '../voice'
import { secrets, clearSecrets } from '../secrets'
import { syncVault } from '@/lib/vault'

const CURRENCIES = ['EGP', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'KWD', 'QAR', 'JPY', 'CAD', 'AUD', 'INR']

export default function Settings({ open, onClose, onSignIn }: { open: boolean; onClose: () => void; onSignIn: () => void }) {
  useStoreVersion()
  const session = cloud.getSession()
  const userName = useSetting<string>('userName', '')
  const assistant = useSetting<string>('assistantName', 'Joshu')
  const currency = useSetting<string>('currencyCode', defaultCurrency())
  const budget = useSetting<number>('monthlyBudget', 2000)
  const goal = useSetting<number>('readingGoal', 24)
  const city = useSetting<string>('weatherCity', '')
  const [version, setVersion] = useState('')
  const [update, setUpdate] = useState<{ state: string; version?: string; message?: string }>({ state: 'idle' })
  const [signingOut, setSigningOut] = useState(false)
  const [connections, setConnections] = useState(false)

  useEffect(() => {
    window.orbit.config().then((c) => setVersion(c.version))
    window.orbit.onUpdate(setUpdate)
  }, [])

  return (
    <Modal open={open} onClose={onClose} width={560}>
      <h2 className="page-title" style={{ fontSize: 28, marginBottom: 18 }}>Settings</h2>

      <Section title="Account">
        {store.isLocal ? <>
          <div className="col" style={{ gap: 2 }}>
            <strong>On this phone only</strong>
            <span className="muted" style={{ fontSize: 12 }}>Sign in or create an account to sync with your other devices. What you've added here comes with you.</span>
          </div>
          <button className="btn-primary" style={{ alignSelf: 'flex-start' }} onClick={onSignIn}>Sign in or create account</button>
        </> : <>
          <div className="col" style={{ gap: 2 }}>
            <strong className="clamp1">{session?.email}</strong>
            <span className="muted" style={{ fontSize: 12 }}>
              {store.syncing ? 'Syncing…' : store.status || 'Synced with your Joshu account'}
              {store.lastSync && ` · ${relativeTime(store.lastSync)}`}
            </span>
          </div>
          <div className="row">
            <button className="btn-soft" onClick={() => store.sync()} disabled={store.syncing}><RefreshCw size={13} /> Sync now</button>
            <button className="btn-soft" onClick={() => setSigningOut(true)}>Sign out</button>
          </div>
          <DeleteAccount onDone={onClose} />
        </>}
      </Section>

      <Section title="Connections">
        <span className="secondary" style={{ fontSize: 13 }}>Gmail and Google Calendar, GitHub, bank texts and Goodreads.</span>
        <button className="btn-soft" style={{ alignSelf: 'flex-start' }} onClick={() => setConnections(true)}><Link2 size={13} /> Open Connections</button>
      </Section>
      <Connections open={connections} onClose={() => setConnections(false)}
        onBankTexts={() => { setConnections(false); setTimeout(() => document.getElementById('bank-texts')?.scrollIntoView({ behavior: 'smooth' }), 250) }} />

      {signingOut && <SignOutChoice onCancel={() => setSigningOut(false)} onDone={onClose} />}

      <Section title="You">
        <Field label="Your name"><input key={userName} className="field" defaultValue={userName} onBlur={(e) => store.setSetting('userName', e.target.value.trim())} /></Field>
        <Field label="Call your AI"><input key={assistant} className="field" defaultValue={assistant} onBlur={(e) => store.setSetting('assistantName', e.target.value.trim() || 'Joshu')} /></Field>
        <Field label="Weather city"><input key={city} className="field" defaultValue={city} placeholder="Cairo" onBlur={(e) => store.setSetting('weatherCity', e.target.value.trim())} /></Field>
      </Section>

      <ProSection />
      <details className="advanced">
        <summary>Your own Anthropic key and synced keys</summary>
        <AISection />
      </details>
      <VoiceSection />
      <MemorySection />
      <BankTextsSection />
      <EmailSection />

      <Section title="Money & reading">
        <Field label="Currency">
          <select className="field" value={currency} onChange={(e) => store.setSetting('currencyCode', e.target.value)}>
            {[...new Set([currency, ...CURRENCIES])].map((c) => <option key={c}>{c}</option>)}
          </select>
        </Field>
        <Field label="Monthly budget"><input key={budget} className="field" type="number" inputMode="decimal" defaultValue={budget} onBlur={(e) => store.setSetting('monthlyBudget', Number(e.target.value) || 0)} /></Field>
        <Field label="Books per year"><input key={goal} className="field" type="number" inputMode="numeric" defaultValue={goal} onBlur={(e) => store.setSetting('readingGoal', Math.max(1, Number(e.target.value) || 24))} /></Field>
      </Section>

      <Section title="Updates">
        <div className="col" style={{ gap: 2 }}>
          <strong>Joshu {version}</strong>
          <span className="muted" style={{ fontSize: 12 }}>
            {update.state === 'checking' && 'Checking…'}
            {update.state === 'none' && "You're on the latest version."}
            {update.state === 'ready' && `Joshu ${update.version} is out. Download it, then open the file to install over this one (your data stays).`}
            {update.state === 'error' && `Couldn't check: ${update.message}`}
            {update.state === 'idle' && 'Joshu looks for a new version each time it opens.'}
          </span>
        </div>
        {update.state === 'ready'
          ? <button className="btn-primary" onClick={() => window.orbit.installUpdate()}><Download size={14} /> Download update</button>
          : <button className="btn-soft" style={{ alignSelf: 'flex-start' }} onClick={() => window.orbit.checkForUpdates()}>Check for updates</button>}
      </Section>
    </Modal>
  )
}

function MemorySection() {
  useStoreVersion()
  const list = memories()
  const [draft, setDraft] = useState('')
  return (
    <Section title="What your AI remembers">
      {list.length === 0 && <span className="muted" style={{ fontSize: 13 }}>Nothing yet. Tell it about yourself in a chat ("I'm vegetarian") and it remembers, on every device.</span>}
      {list.map((m) => (
        <div key={m} className="row" style={{ gap: 8 }}>
          <span style={{ flex: 1, fontSize: 13 }}>{m}</span>
          <button className="icon-btn" style={{ width: 32, height: 32 }} aria-label="Forget" onClick={() => setMemories(list.filter((x) => x !== m))}><Trash2 size={13} /></button>
        </div>
      ))}
      <div className="row">
        <input className="field" placeholder="Add something to remember" value={draft} onChange={(e) => setDraft(e.target.value)} />
        <button className="btn-soft" disabled={!draft.trim()} onClick={() => { setMemories([...list, draft]); setDraft('') }}>Add</button>
      </div>
    </Section>
  )
}

/** Bank texts: Joshu reads your bank's SMS on this phone and logs each payment (the iPhone needs a Shortcuts automation for this). */
function BankTextsSection() {
  const [, tick] = useState(0)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [extra, setExtra] = useState('')
  const [picking, setPicking] = useState(false)
  useEffect(() => onSmsChange(() => tick((n) => n + 1)), [])
  const on = smsEnabled()
  const chosen = chosenBanks()
  const activity = smsActivity().slice(0, 5)

  const toggle = async () => {
    setMessage('')
    if (on) { disableSms(); return }
    setBusy(true)
    const ok = await enableSms(3)
    setBusy(false)
    if (!ok) setMessage(isNative ? 'Joshu needs permission to read SMS. Allow it when Android asks (or in Android Settings › Apps › Joshu › Permissions).' : 'Works in the Android app.')
  }

  return (
    <div id="bank-texts"><Section title="Bank texts">
      <div className="row" style={{ alignItems: 'flex-start' }}>
        <MessageSquareText size={18} style={{ flex: 'none', marginTop: 2 }} />
        <span style={{ flex: 1, fontSize: 13 }} className="secondary">
          Log card payments, transfers and salary from your bank's text messages automatically. Joshu reads new texts from your banks each time you open it; OTP codes and declined payments are skipped.
        </span>
      </div>
      <div className="row">
        <button className={on ? 'btn-soft' : 'btn-primary'} disabled={busy} onClick={toggle}>{on ? 'Turn off' : busy ? 'Turning on…' : 'Turn on'}</button>
        {on && <button className="btn-soft" disabled={busy} onClick={async () => { setBusy(true); const n = await checkBankTexts(); setBusy(false); setMessage(n ? `Logged ${n} new payment${n > 1 ? 's' : ''}.` : 'Nothing new.') }}>
          <RefreshCw size={13} /> Check now</button>}
      </div>
      {message && <span style={{ fontSize: 12 }} className="secondary">{message}</span>}
      <button className="link" style={{ alignSelf: 'flex-start', fontSize: 13 }} onClick={() => setPicking(!picking)}>
        {chosen.length ? `Your banks: ${BANKS.filter((b) => chosen.includes(b.id)).map((b) => b.name.replace(/ \(.*\)/, '')).join(', ')}` : 'All banks (tap to pick yours)'}
      </button>
      {picking && (
        <div className="col" style={{ gap: 4 }}>
          {BANKS.map((b) => (
            <label key={b.id} className="row" style={{ minHeight: 36, fontSize: 13 }}>
              <input type="checkbox" checked={chosen.includes(b.id)}
                onChange={(e) => { setChosenBanks(e.target.checked ? [...chosen, b.id] : chosen.filter((x) => x !== b.id)); tick((n) => n + 1) }} />
              {b.name}
            </label>
          ))}
          <div className="row">
            <input className="field" placeholder="Another sender name" value={extra} onChange={(e) => setExtra(e.target.value)} />
            <button className="btn-soft" disabled={!extra.trim()} onClick={() => { setExtraSenders([...extraSenders(), extra.trim()]); setExtra(''); tick((n) => n + 1) }}>Add</button>
          </div>
          {extraSenders().map((s) => (
            <div key={s} className="row" style={{ fontSize: 13 }}>{s}<span className="spacer" />
              <button className="link" onClick={() => { setExtraSenders(extraSenders().filter((x) => x !== s)); tick((n) => n + 1) }}>Remove</button></div>
          ))}
        </div>
      )}
      {activity.length > 0 && (
        <div className="col" style={{ gap: 6 }}>
          <span className="muted" style={{ fontSize: 11, fontWeight: 600 }}>RECENT</span>
          {activity.map((a) => (
            <div key={a.t + a.text} style={{ fontSize: 12 }}>
              <strong>{a.result}</strong>
              <div className="muted clamp1">{a.sender ? `${a.sender}: ` : ''}{a.text}</div>
            </div>
          ))}
        </div>
      )}
    </Section></div>
  )
}

/** Signing out, as on the Mac and iPhone (1.40): everything is saved to your account first, then removed from
 *  this phone (data, chats, keys and connected accounts) unless you keep a copy. Sign in again and it all comes back. */
function SignOutChoice({ onCancel, onDone }: { onCancel: () => void; onDone: () => void }) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const go = async (keep: boolean) => {
    setBusy(true); setError('')
    const session = cloud.getSession()
    await store.sync()
    if (store.unsent > 0) {
      setBusy(false)
      setError("Some changes couldn't be saved to your account, so nothing was removed and you're still signed in. Check your connection and try again, or keep a copy on this phone.")
      if (!keep) return
    }
    if (secrets.get('sync-passphrase')) {
      const v = await syncVault()
      if (v.state !== 'on' && !keep) {
        setBusy(false)
        setError("Your keys and connected accounts couldn't be saved to your account, so nothing was removed and you're still signed in. Try again, or keep a copy on this phone.")
        return
      }
    }
    if (!keep && session) {
      for (const k of Object.keys(localStorage)) {
        if (k === `orbit.cache.${session.userID}` || k.startsWith('orbit.ask.') || k.startsWith('orbit.github') || k.startsWith('orbit.linkedin') || k === 'orbit.gcal'
          || k.startsWith('bankSMS.') || k === 'orbit.profilePhoto') localStorage.removeItem(k)
      }
      await clearSecrets()
    }
    cloud.signOut()
    onDone()
  }
  return (
    <div className="card col" style={{ gap: 10, marginBottom: 18, background: 'var(--blush)' }}>
      <strong>Sign out of Joshu?</strong>
      <span className="secondary" style={{ fontSize: 13 }}>
        Everything is saved to your account first, then removed from this phone, with your chats and connected accounts like Gmail.
        Sign in again and it all comes back. Keep a copy only on a phone that's just yours.
      </span>
      {error && <span style={{ fontSize: 13, color: 'var(--critical)' }}>{error}</span>}
      <button className="btn-primary" disabled={busy} onClick={() => go(false)}>{busy ? 'Saving…' : 'Sign out'}</button>
      <button className="btn-soft" disabled={busy} onClick={() => go(true)}>Sign out and keep a copy here</button>
      <button className="link" disabled={busy} onClick={onCancel}>Cancel</button>
    </div>
  )
}

/** Joshu Pro: the AI through Joshu's server, given to your account (no key to add). */
function ProSection() {
  const [, tick] = useState(0)
  const [busy, setBusy] = useState(false)
  useEffect(() => onProChange(() => tick((n) => n + 1)), [])
  const on = isPro()
  const own = !!secrets.get('anthropic-api-key')
  const until = proUntil()
  return (
    <Section title="Joshu Pro">
      <div className="row" style={{ gap: 12, alignItems: 'flex-start' }}>
        <Orb size={40} />
        <div className="col" style={{ gap: 4, flex: 1 }}>
          <strong>{on ? "You're on Pro. Thanks for supporting Joshu." : own ? 'Using your own Anthropic key.' : 'Your AI assistant needs Joshu Pro.'}</strong>
          <span className="secondary" style={{ fontSize: 13 }}>
            {on ? `Your assistant, morning brief, email summaries and money coach are on${until < 4e12 ? ` until ${new Date(until).toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })}` : ''}. No API keys, nothing to set up.`
              : 'Everything in Joshu, plus your AI assistant and the smart features that save you time. Pro is added to your Joshu account; once it is, it works here straight away.'}
          </span>
        </div>
      </div>
      <button className="btn-soft" style={{ alignSelf: 'flex-start' }} disabled={busy}
        onClick={async () => { setBusy(true); await refreshPro(); await refreshKeys(); setBusy(false) }}>
        <RefreshCw size={13} /> {busy ? 'Checking…' : 'Check my plan'}
      </button>
    </Section>
  )
}

/** "Hey Joshu" while the app is open (Settings › AI › Voice on the Mac). */
function VoiceSection() {
  const [on, setOn] = useState(wakeEnabled())
  const name = useSetting<string>('assistantName', 'Joshu') || 'Joshu'
  return (
    <Section title="Voice">
      <label className="row" style={{ alignItems: 'flex-start', gap: 12 }}>
        <input type="checkbox" checked={on} style={{ marginTop: 3 }} onChange={(e) => { setOn(e.target.checked); setWakeEnabled(e.target.checked) }} />
        <span className="col" style={{ gap: 2 }}>
          <strong>Listen for “Hey {name}”</strong>
          <span className="secondary" style={{ fontSize: 13 }}>While Joshu is open, say “Hey {name}” and just talk. It answers out loud and keeps listening until you say “stop” or “bye”. Listening happens on this phone.</span>
        </span>
      </label>
    </Section>
  )
}
