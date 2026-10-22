import { useEffect, useState } from 'react'
import { RefreshCw, Check, KeyRound, Mail, Trash2 } from 'lucide-react'
import { useKeys, refreshKeys } from '@/lib/ai'
import { syncVault, vaultState, onVaultChange, forgetPassphrase } from '@/lib/vault'
import { emailExpensesEnabled, setEmailExpensesEnabled, startEmailExpensesTimer } from '@/lib/emailExpenses'
import * as cloud from '@/lib/cloud'
import { store, useSetting, useStoreVersion } from '@/lib/store'
import { Modal, defaultCurrency } from '@/components/ui'
import { relativeTime } from '@/lib/dates'

const CURRENCIES = ['USD', 'EUR', 'GBP', 'EGP', 'AED', 'SAR', 'KWD', 'QAR', 'JPY', 'CAD', 'AUD', 'INR']

export default function SettingsModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  useStoreVersion()
  const session = cloud.getSession()
  const userName = useSetting<string>('userName', '')
  const assistant = useSetting<string>('assistantName', 'Ask')
  const currency = useSetting<string>('currencyCode', defaultCurrency())
  const budget = useSetting<number>('monthlyBudget', 2000)
  const goal = useSetting<number>('readingGoal', 24)
  const city = useSetting<string>('weatherCity', '')
  const [version, setVersion] = useState('')
  const [update, setUpdate] = useState<{ state: string; version?: string; progress?: number; message?: string }>({ state: 'idle' })

  useEffect(() => {
    window.orbit.config().then((c) => setVersion(c.version))
    window.orbit.onUpdate(setUpdate)
  }, [])

  return (
    <Modal open={open} onClose={onClose} width={560}>
      <h2 className="page-title" style={{ fontSize: 28, marginBottom: 18 }}>Settings</h2>

      <Section title="Account">
        <div className="row">
          <div className="col" style={{ gap: 2 }}>
            <strong>{session?.email}</strong>
            <span className="muted" style={{ fontSize: 12 }}>
              {store.syncing ? 'Syncing…' : store.status || 'Synced with your Orbit account'}
              {store.lastSync && ` · ${relativeTime(store.lastSync)}`}
            </span>
          </div>
          <span className="spacer" />
          <button className="btn-soft" onClick={() => store.sync()} disabled={store.syncing}><RefreshCw size={13} /> Sync now</button>
          <button className="btn-soft" onClick={() => { cloud.signOut(); onClose() }}>Sign out</button>
        </div>
      </Section>

      <Section title="You">
        <Field label="Your name"><input key={userName} className="field" defaultValue={userName} onBlur={(e) => store.setSetting('userName', e.target.value.trim())} /></Field>
        <Field label="Call your AI"><input key={assistant} className="field" defaultValue={assistant} onBlur={(e) => store.setSetting('assistantName', e.target.value.trim() || 'Ask')} /></Field>
        <Field label="Weather city"><input key={city} className="field" defaultValue={city} placeholder={Intl.DateTimeFormat().resolvedOptions().timeZone.split('/').pop()?.replace(/_/g, ' ')}
          onBlur={(e) => store.setSetting('weatherCity', e.target.value.trim())} /></Field>
      </Section>

      <AISection />
      <EmailSection />

      <Section title="Money & reading">
        <Field label="Currency">
          <select className="field" value={currency} onChange={(e) => store.setSetting('currencyCode', e.target.value)}>
            {[...new Set([currency, ...CURRENCIES])].map((c) => <option key={c}>{c}</option>)}
          </select>
        </Field>
        <Field label="Monthly budget"><input key={budget} className="field" type="number" defaultValue={budget} onBlur={(e) => store.setSetting('monthlyBudget', Number(e.target.value) || 0)} /></Field>
        <Field label="Books per year"><input key={goal} className="field" type="number" defaultValue={goal} onBlur={(e) => store.setSetting('readingGoal', Math.max(1, Number(e.target.value) || 24))} /></Field>
      </Section>

      <Section title="Updates">
        <div className="row">
          <div className="col" style={{ gap: 2 }}>
            <strong>Orbit {version}</strong>
            <span className="muted" style={{ fontSize: 12 }}>
              {update.state === 'checking' && 'Checking…'}
              {update.state === 'none' && (update.message ?? "You're on the latest version.")}
              {update.state === 'available' && `Downloading ${update.version}…`}
              {update.state === 'downloading' && `Downloading… ${Math.round((update.progress ?? 0) * 100)}%`}
              {update.state === 'ready' && `Orbit ${update.version} is ready to install.`}
              {update.state === 'error' && `Couldn't check: ${update.message}`}
              {update.state === 'idle' && 'Orbit checks for updates by itself every few hours.'}
            </span>
          </div>
          <span className="spacer" />
          {update.state === 'ready'
            ? <button className="btn-primary" onClick={() => window.orbit.installUpdate()}>Restart & update</button>
            : <button className="btn-soft" onClick={() => window.orbit.checkForUpdates()}>Check for updates</button>}
        </div>
      </Section>

      <p className="muted" style={{ fontSize: 11 }}>
        Ask, the journal check-in, email and the money coach now work on Windows too. GitHub, Apple Calendar and the Kindle/Apple Books
        imports stay on the Mac; what they add shows up here.
      </p>
    </Modal>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={{ marginBottom: 18 }}>
      <div className="muted" style={{ fontSize: 12, fontWeight: 600, marginBottom: 8 }}>{title}</div>
      <div className="card col" style={{ gap: 12 }}>{children}</div>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="row" style={{ gap: 14 }}>
      <span className="secondary" style={{ width: 120, fontSize: 13 }}>{label}</span>
      <span style={{ flex: 1 }}>{children}</span>
    </label>
  )
}

// MARK: AI (Anthropic key, directly or unlocked from the Mac's encrypted key sync)

function AISection() {
  const keys = useKeys()
  const [vs, setVs] = useState(vaultState())
  const [pass, setPass] = useState('')
  const [apiKey, setApiKey] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  useEffect(() => { const off = onVaultChange(() => setVs(vaultState())); return () => { off() } }, [])

  const unlock = async () => {
    setBusy(true); setMessage('')
    const r = await syncVault(pass.trim())
    setBusy(false)
    if (r.state === 'on') { setPass(''); setMessage('Keys unlocked from your Mac.') } else setMessage(r.message ?? '')
  }
  const saveKey = async () => {
    setBusy(true); setMessage('')
    await window.orbit.setSecret('anthropic-api-key', apiKey.trim())
    setApiKey('')
    await refreshKeys()
    const t = await window.orbit.claudeTest()
    setMessage(t.message ?? '')
    if (t.ok && vs.state === 'on') await syncVault()
    setBusy(false)
  }
  const test = async () => { setBusy(true); const t = await window.orbit.claudeTest(); setMessage(t.message ?? ''); setBusy(false) }

  return (
    <Section title="AI">
      <div className="row">
        <KeyRound size={16} />
        <div className="col" style={{ gap: 2 }}>
          <strong>Anthropic API key</strong>
          <span className="muted" style={{ fontSize: 12 }}>
            {keys.anthropic ? 'Saved on this PC (encrypted by Windows).' : 'Not set: Ask, the morning brief and email summaries need it.'}
          </span>
        </div>
        <span className="spacer" />
        {keys.anthropic && <span className="row" style={{ gap: 4, color: 'var(--good)', fontSize: 12 }}><Check size={13} />Ready</span>}
        {keys.anthropic && <button className="btn-soft" disabled={busy} onClick={test}>Test connection</button>}
      </div>

      {(vs.state === 'needsPassphrase' || vs.state === 'wrongPassphrase') && (
        <div className="col" style={{ gap: 6 }}>
          <span style={{ fontSize: 13 }}>Your keys are synced from your Mac. Enter your sync passphrase once to unlock them here.</span>
          <div className="row">
            <input className="field" type="password" placeholder="Sync passphrase" value={pass} onChange={(e) => setPass(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && pass.trim()) unlock() }} />
            <button className="btn-primary" disabled={busy || !pass.trim()} onClick={unlock}>Unlock</button>
          </div>
        </div>
      )}
      {vs.state === 'needsNewPassphrase' && (
        <div className="col" style={{ gap: 6 }}>
          <span style={{ fontSize: 13 }}>
            Sync your keys between devices, end-to-end encrypted. Choose a passphrase; you'll enter the same one on your Mac
            (Settings › Account › Sync API keys and connections).
          </span>
          <div className="row">
            <input className="field" type="password" placeholder="New sync passphrase" value={pass} onChange={(e) => setPass(e.target.value)} />
            <button className="btn-soft" disabled={busy || pass.trim().length < 6} onClick={unlock}>Turn on</button>
          </div>
        </div>
      )}
      {vs.state === 'on' && (
        <div className="row muted" style={{ fontSize: 12 }}>
          <Check size={12} />Keys and sign-ins sync with your Mac (encrypted).
          <span className="spacer" />
          <button className="link" onClick={() => forgetPassphrase()}>Forget passphrase on this PC</button>
        </div>
      )}
      {vs.state === 'error' && vs.message && <span style={{ fontSize: 12, color: 'var(--critical)' }}>{vs.message}</span>}

      <div className="row">
        <input className="field" type="password" placeholder={keys.anthropic ? 'Replace API key (sk-ant-…)' : 'Or paste an Anthropic API key (sk-ant-…)'}
          value={apiKey} onChange={(e) => setApiKey(e.target.value)} />
        <button className="btn-soft" disabled={busy || !apiKey.trim()} onClick={saveKey}>Save</button>
      </div>
      <button className="link" style={{ alignSelf: 'flex-start' }} onClick={() => window.orbit.openExternal('https://console.anthropic.com/settings/keys')}>
        Get a key at console.anthropic.com
      </button>
      {message && <span style={{ fontSize: 12 }}>{message}</span>}
    </Section>
  )
}

// MARK: Email (Gmail accounts and receipts → Money)

function EmailSection() {
  const keys = useKeys()
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [clientID, setClientID] = useState('')
  const [clientSecret, setClientSecret] = useState('')
  const [expenses, setExpenses] = useState(emailExpensesEnabled())

  const add = async () => {
    setBusy(true); setMessage('Waiting for Google in your browser…')
    const r = await window.orbit.googleSignIn()
    await refreshKeys()
    if (r.ok) {
      setMessage(`Connected ${r.email}.`)
      if (vaultState().state === 'on') await syncVault() // so the Mac gets this sign-in too
      startEmailExpensesTimer()
    } else setMessage(r.error ?? 'Google sign-in failed.')
    setBusy(false)
  }
  const remove = async (email: string) => { await window.orbit.googleRemove(email); await refreshKeys() }
  const saveClient = async () => {
    await window.orbit.setSecret('google-client-id', clientID.trim())
    await window.orbit.setSecret('google-client-secret', clientSecret.trim())
    setClientID(''); setClientSecret('')
    await refreshKeys()
  }

  return (
    <Section title="Email">
      {keys.gmail.map((email) => (
        <div key={email} className="row">
          <Mail size={15} />
          <strong style={{ fontSize: 13 }}>{email}</strong>
          <span className="row" style={{ gap: 4, color: 'var(--good)', fontSize: 12 }}><Check size={12} />Connected</span>
          <span className="spacer" />
          <button className="btn-soft" onClick={() => remove(email)}><Trash2 size={12} />Remove</button>
        </div>
      ))}
      {keys.googleClient ? (
        <div className="row">
          <button className="btn-primary" disabled={busy} onClick={add}>{busy ? 'Waiting for Google…' : 'Add Gmail account…'}</button>
          <span className="muted" style={{ fontSize: 12 }}>Sign in once per account; Orbit keeps a read-only token, encrypted on this PC.</span>
        </div>
      ) : (
        <div className="col" style={{ gap: 6 }}>
          <span className="muted" style={{ fontSize: 12 }}>
            Unlocking your keys from the Mac (AI section above) fills these in. Or paste the Google OAuth client (Desktop app) from your Google Cloud project:
          </span>
          <input className="field" placeholder="Client ID" value={clientID} onChange={(e) => setClientID(e.target.value)} />
          <input className="field" type="password" placeholder="Client secret" value={clientSecret} onChange={(e) => setClientSecret(e.target.value)} />
          <button className="btn-soft" style={{ alignSelf: 'flex-end' }} disabled={!clientID.trim() || !clientSecret.trim()} onClick={saveClient}>Save</button>
        </div>
      )}
      {message && <span style={{ fontSize: 12 }}>{message}</span>}
      <label className="row" style={{ fontSize: 13 }}>
        <input type="checkbox" checked={expenses} onChange={(e) => { setEmailExpensesEnabled(e.target.checked); setExpenses(e.target.checked) }} />
        Add payments and receipts from email to Money
      </label>
      <span className="muted" style={{ fontSize: 11 }}>
        Inbox summaries send the sender, subject and a short preview of recent mail to Anthropic; expense import also sends the text of emails that look like receipts or payments.
      </span>
    </Section>
  )
}
