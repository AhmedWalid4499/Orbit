// Settings on Android: the Windows app's account, AI and email sections, plus bank texts (SMS),
// what the assistant remembers, and updates from the GitHub release.
import { useEffect, useState } from 'react'
import { RefreshCw, MessageSquareText, Trash2, Download } from 'lucide-react'
import * as cloud from '@/lib/cloud'
import { store, useSetting, useStoreVersion } from '@/lib/store'
import { Modal, defaultCurrency } from '@/components/ui'
import { relativeTime } from '@/lib/dates'
import { AISection, EmailSection, Section, Field } from '@/screens/Settings'
import { BANKS, chosenBanks, setChosenBanks, extraSenders, setExtraSenders } from '../bank'
import { smsEnabled, enableSms, disableSms, checkBankTexts, smsActivity, onSmsChange } from '../sms'
import { memories, setMemories } from './Assistant'
import { isNative } from '../native'

const CURRENCIES = ['EGP', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'KWD', 'QAR', 'JPY', 'CAD', 'AUD', 'INR']

export default function Settings({ open, onClose }: { open: boolean; onClose: () => void }) {
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

  useEffect(() => {
    window.orbit.config().then((c) => setVersion(c.version))
    window.orbit.onUpdate(setUpdate)
  }, [])

  return (
    <Modal open={open} onClose={onClose} width={560}>
      <h2 className="page-title" style={{ fontSize: 28, marginBottom: 18 }}>Settings</h2>

      <Section title="Account">
        <div className="col" style={{ gap: 2 }}>
          <strong className="clamp1">{session?.email}</strong>
          <span className="muted" style={{ fontSize: 12 }}>
            {store.syncing ? 'Syncing…' : store.status || 'Synced with your Joshu account'}
            {store.lastSync && ` · ${relativeTime(store.lastSync)}`}
          </span>
        </div>
        <div className="row">
          <button className="btn-soft" onClick={() => store.sync()} disabled={store.syncing}><RefreshCw size={13} /> Sync now</button>
          <button className="btn-soft" onClick={() => { if (confirm('Sign out of Joshu on this phone?')) { cloud.signOut(); onClose() } }}>Sign out</button>
        </div>
      </Section>

      <Section title="You">
        <Field label="Your name"><input key={userName} className="field" defaultValue={userName} onBlur={(e) => store.setSetting('userName', e.target.value.trim())} /></Field>
        <Field label="Call your AI"><input key={assistant} className="field" defaultValue={assistant} onBlur={(e) => store.setSetting('assistantName', e.target.value.trim() || 'Joshu')} /></Field>
        <Field label="Weather city"><input key={city} className="field" defaultValue={city} placeholder="Cairo" onBlur={(e) => store.setSetting('weatherCity', e.target.value.trim())} /></Field>
      </Section>

      <AISection />
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
    <Section title="Bank texts">
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
    </Section>
  )
}
