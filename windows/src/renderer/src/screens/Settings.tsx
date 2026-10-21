import { useEffect, useState } from 'react'
import { RefreshCw } from 'lucide-react'
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
        Ask, Gmail, GitHub, Apple Calendar and the Kindle/Apple Books imports run on the Mac app for now; what they add shows up here too.
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
