// Money › Auto-log card payments on Android, the counterpart of PhoneBankSetup.swift on the iPhone. The iPhone needs two
// Shortcuts automations; on Android Joshu reads new texts from your banks itself (sms.ts), so this sheet is the switch,
// the banks to listen to, what came in lately, and a box to try a bank message.
import { useEffect, useState } from 'react'
import { Landmark, MessageSquare, CircleCheck, CircleAlert, CircleMinus, RefreshCw, Check, Search } from 'lucide-react'
import { useRecords, useSetting } from '@/lib/store'
import { Txn } from '@/lib/models'
import { relativeTime } from '@/lib/dates'
import { useKeys } from '@/lib/ai'
import { Modal, defaultCurrency } from '@/components/ui'
import { BANKS, chosenBanks, setChosenBanks, extraSenders, setExtraSenders, read, logMessage, Parsed } from '../bank'
import { smsEnabled, enableSms, disableSms, checkBankTexts, smsActivity, onSmsChange } from '../sms'
import { isNative } from '../native'

export default function PhoneBankSetup({ open, onClose }: { open: boolean; onClose: () => void }) {
  const txns = useRecords<Txn>('transaction')
  const keys = useKeys()
  const currency = useSetting<string>('currencyCode', defaultCurrency())
  const [, tick] = useState(0)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [picking, setPicking] = useState(false)
  const [sample, setSample] = useState('')
  const [preview, setPreview] = useState<Parsed | null>(null)
  const [checked, setChecked] = useState(false)
  const [reading, setReading] = useState(false)
  const [result, setResult] = useState('')
  useEffect(() => onSmsChange(() => tick((n) => n + 1)), [])

  const on = smsEnabled()
  const logged = txns.filter((t) => t.data.source === 'sms' || t.data.source === 'wallet')
  const chosen = chosenBanks()
  const extra = extraSenders()
  const names = [...BANKS.filter((b) => chosen.includes(b.id)).map((b) => b.name), ...extra]
  const entries = smsActivity()
  const last = entries.find((e) => e.sender)

  const toggle = async () => {
    setMessage('')
    if (on) { disableSms(); return }
    setBusy(true)
    const ok = await enableSms(3)
    setBusy(false)
    if (!ok) setMessage(isNative ? 'Joshu needs permission to read SMS. Allow it when Android asks (or in Android Settings › Apps › Joshu › Permissions).' : 'Works in the Android app.')
  }
  const checkNow = async () => {
    setBusy(true)
    const n = await checkBankTexts()
    setBusy(false)
    setMessage(n ? `Logged ${n} new payment${n > 1 ? 's' : ''}.` : 'Nothing new.')
  }

  return (
    <Modal open={open} onClose={onClose}>
      <div className="col pm-sheet">
        <h2 className="display pm-sheet-title">Auto-log card payments</h2>
        <div className="secondary" style={{ fontSize: 14 }}>
          Card and wallet spending never reaches your inbox. On Android, Joshu reads the texts your banks send and logs each payment as it
          happens. OTP codes, declined payments and texts from anyone else are skipped.
        </div>

        {logged.length > 0 && (
          <div className="row" style={{ gap: 6, fontSize: 13, fontWeight: 600, color: 'var(--good)' }}>
            <CircleCheck size={15} />{logged.length} payment{logged.length === 1 ? '' : 's'} logged this way so far
          </div>
        )}

        <div className="pm-panel col" style={{ gap: 12 }}>
          <div className="display" style={{ fontSize: 20 }}>Status</div>
          <div className="row" style={{ gap: 10, alignItems: 'flex-start' }}>
            <span style={{ color: on && last ? 'var(--good)' : 'var(--orange)', flex: 'none', marginTop: 1 }}>{on && last ? <CircleCheck size={16} /> : <CircleAlert size={16} />}</span>
            <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
              <span style={{ fontSize: 14, fontWeight: 600 }}>Bank texts</span>
              <span className="secondary" style={{ fontSize: 12 }}>
                {!on ? 'Off. Turn it on and allow Joshu to read SMS when Android asks.'
                  : last ? `Last one reached Joshu ${relativeTime(new Date(last.t))}.`
                  : 'On. Nothing from your banks yet: Joshu reads new texts each time you open it.'}
              </span>
            </div>
          </div>
          <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
            <button className={on ? 'btn-soft' : 'btn-primary'} disabled={busy} onClick={toggle}>{on ? 'Turn off' : busy ? 'Turning on…' : 'Turn on'}</button>
            {on && <button className="btn-soft" disabled={busy} onClick={checkNow}><RefreshCw size={13} />Check now</button>}
          </div>
          {message && <span className="secondary" style={{ fontSize: 12 }}>{message}</span>}
        </div>

        <div className="pm-panel col" style={{ gap: 12 }}>
          <div className="row" style={{ gap: 10 }}>
            <span className="pm-tile-icon" style={{ background: 'var(--peach)' }}><Landmark size={14} /></span>
            <span className="display" style={{ fontSize: 20 }}>Your banks</span>
            <span className="spacer" />
            <button className="btn-soft" onClick={() => setPicking(true)}>{names.length ? 'Edit' : 'Choose'}</button>
          </div>
          {names.length ? (
            <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
              {names.map((n) => <span key={n} className="pm-chip">{n}</span>)}
            </div>
          ) : (
            <span className="secondary" style={{ fontSize: 13 }}>Pick the banks and wallets that text you, so Joshu only reads their messages.</span>
          )}
        </div>

        <div className="col" style={{ gap: 10 }}>
          <div className="row">
            <span className="display" style={{ fontSize: 20 }}>Recent activity</span>
            <span className="spacer" />
            <button className="secondary" aria-label="Refresh" onClick={() => tick((n) => n + 1)}><RefreshCw size={15} /></button>
          </div>
          {!entries.length && (
            <span className="secondary" style={{ fontSize: 13 }}>
              Nothing has come in from your bank texts yet. Each text Joshu reads appears here with what it did with it.
            </span>
          )}
          {entries.slice(0, 8).map((e) => (
            <div key={e.t + e.text} className="row" style={{ gap: 10, alignItems: 'flex-start' }}>
              <span className="pm-dot-icon" style={{ background: 'var(--cyan)' }}><MessageSquare size={12} /></span>
              <div className="col" style={{ gap: 2, minWidth: 0 }}>
                <span style={{ fontSize: 13, fontWeight: 500 }}>{e.result}</span>
                <span className="muted" style={{ fontSize: 11 }}>{relativeTime(new Date(e.t))}{e.sender ? ` · from ${e.sender}` : ''}</span>
                {e.text && <span className="secondary clamp2" style={{ fontSize: 11 }}>“{e.text}”</span>}
              </div>
            </div>
          ))}
        </div>

        <div className="col" style={{ gap: 10 }}>
          <span className="display" style={{ fontSize: 20 }}>Try a message</span>
          <span className="secondary" style={{ fontSize: 13 }}>Paste a text from your bank to see what Joshu reads.</span>
          <textarea className="field" rows={3} placeholder="e.g. Your card ending 1234 was charged EGP 350.00 at CARREFOUR MAADI" value={sample}
            onChange={(e) => { setSample(e.target.value); setChecked(false); setPreview(null); setResult('') }} />
          <div className="row">
            <button className="btn-soft" disabled={reading || !sample.trim()}
              onClick={async () => { setReading(true); setPreview(await read(sample, keys.anthropic)); setChecked(true); setReading(false) }}>
              {reading ? 'Reading…' : 'Check'}
            </button>
            <span className="spacer" />
            {preview && preview.kind !== 'not_payment' && preview.amount > 0 && !result && (
              <button className="btn-primary" onClick={async () => setResult(await logMessage(sample, '', new Date(), keys.anthropic))}>Log it</button>
            )}
          </div>
          {checked && (preview && preview.kind !== 'not_payment' && preview.amount > 0 ? (
            <span className="row" style={{ gap: 6, fontSize: 13, fontWeight: 500, color: 'var(--good)', alignItems: 'flex-start' }}>
              <CircleCheck size={15} style={{ flex: 'none', marginTop: 1 }} />
              {preview.kind === 'expense' ? 'Spent' : preview.kind === 'refund' ? 'Refund' : 'Money in'}: {preview.amount.toLocaleString(undefined, { maximumFractionDigits: 2 })} {preview.currency || currency}
              {preview.merchant ? ` · ${preview.merchant}` : ''} · {preview.category}
            </span>
          ) : (
            <span className="row secondary" style={{ gap: 6, fontSize: 13 }}><CircleMinus size={15} />Not a payment, so it would be ignored.</span>
          ))}
          {result && <span style={{ fontSize: 13, fontWeight: 500 }}>{result}</span>}
        </div>

        <span className="muted" style={{ fontSize: 12 }}>
          A text and an email receipt for the same purchase are logged once. Wrong one? Delete it from Money like any other expense.
        </span>
        <button className="btn-primary" style={{ minHeight: 44 }} onClick={onClose}>Done</button>
      </div>
      {picking && <BankPicker onClose={() => { setPicking(false); tick((n) => n + 1) }} />}
    </Modal>
  )
}

/** Pick your banks and wallets; their usual text senders come with them. */
function BankPicker({ onClose }: { onClose: () => void }) {
  const [chosen, setChosen] = useState(chosenBanks())
  const [extra, setExtra] = useState(extraSenders())
  const [query, setQuery] = useState('')
  const [sender, setSender] = useState('')
  const toggle = (id: string) => {
    const next = chosen.includes(id) ? chosen.filter((x) => x !== id) : [...chosen, id]
    setChosen(next); setChosenBanks(next)
  }
  const saveExtra = (v: string[]) => { setExtra(v); setExtraSenders(v) }
  const q = query.trim().toLowerCase()
  return (
    <Modal open onClose={onClose}>
      <div className="col pm-sheet">
        <div className="row">
          <h2 className="display pm-sheet-title">Your banks</h2>
          <span className="spacer" />
          <button className="btn-primary" onClick={onClose}>Done</button>
        </div>
        <div className="pm-search"><Search size={15} className="muted" />
          <input className="plain" placeholder="Search banks" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        <div className="pm-list">
          {BANKS.filter((b) => !q || b.name.toLowerCase().includes(q)).map((b) => (
            <button key={b.id} className="pm-list-row" onClick={() => toggle(b.id)}>
              <span style={{ flex: 1, textAlign: 'left' }}>{b.name}</span>
              {chosen.includes(b.id) && <Check size={16} style={{ color: 'var(--good)' }} />}
            </button>
          ))}
        </div>
        <span className="muted pm-caps">Other senders</span>
        <div className="pm-list">
          {extra.map((s) => (
            <div key={s} className="pm-list-row">
              <span style={{ flex: 1 }}>{s}</span>
              <button className="link" onClick={() => saveExtra(extra.filter((x) => x !== s))}>Remove</button>
            </div>
          ))}
          <div className="pm-list-row">
            <input className="plain" placeholder="Sender name, e.g. CIB" autoCapitalize="off" value={sender} onChange={(e) => setSender(e.target.value)} />
            <button className="link" disabled={!sender.trim()}
              onClick={() => { const s = sender.trim(); if (s && !extra.includes(s)) saveExtra([...extra, s]); setSender('') }}>Add</button>
          </div>
        </div>
        <span className="muted" style={{ fontSize: 12 }}>If your bank's texts arrive under a different name, add it exactly as it appears in Messages.</span>
      </div>
    </Modal>
  )
}
