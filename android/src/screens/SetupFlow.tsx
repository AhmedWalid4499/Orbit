// Setting up a new account, one question at a time, as on the Mac and iPhone (SetupFlow.swift, v1.42): what to call
// you, your preferences, what to connect, and what to call your assistant. Shown once, right after a brand-new
// account signs in (see checkFreshAccount below).
import { useEffect, useState, ReactNode } from 'react'
import {
  Banknote, PieChart, CloudSun, Library, Minus, Plus, Sparkles, LineChart, Calendar, ListChecks, Flame, Mountain, CreditCard, BookOpenText,
  Lightbulb, Code2, Briefcase, Mail, MessageSquareText, CheckCircle2,
} from 'lucide-react'
import { store, useSetting, type SettingKey } from '@/lib/store'
import { useKeys, refreshKeys } from '@/lib/ai'
import { syncVault } from '@/lib/vault'
import { defaultCurrency } from '@/components/ui'
import { Orb } from '../components/Orb'
import { isPro, onProChange } from '../pro'
import { enableSms, smsEnabled, onSmsChange } from '../sms'
import { refreshGoogleCalendar } from '../gcal'
import { isNative } from '../native'
import { setTourSeen } from './Tour'
import '../onboarding.css'

// MARK: When to show it

const KEY = 'setupNeeded'
const subs = new Set<() => void>()
/** Called when the tour or setup should show again (a brand-new account) or setup is finished. */
export const onOnboardingChange = (f: () => void): (() => void) => { subs.add(f); return () => { subs.delete(f) } }
const emit = () => subs.forEach((f) => f())

/** Set when a brand-new account signs in; cleared when the setup is finished. */
export const setupNeeded = (): boolean => { try { return localStorage.getItem(KEY) === '1' } catch { return false } }

/**
 * Call right before store.start() after signing in, and call what it returns once store.start() has finished (before
 * store.adoptLocal()). A brand-new account (nothing on this phone for it, and its first sync brought nothing down) gets
 * the welcome tour and the quick setup, even on a phone that has seen them before, as on the Mac (CloudSync.firstSync).
 */
export function checkFreshAccount(userID: string): () => void {
  let cached = true
  try { cached = !!localStorage.getItem(`orbit.cache.${userID}`) } catch { /* private storage */ }
  return () => {
    // "Up to date" = the first sync worked and moved nothing either way.
    if (cached || store.status !== 'Up to date') return
    setTourSeen(false)
    try { localStorage.setItem(KEY, '1') } catch { /* private storage */ }
    emit()
  }
}

// MARK: The flow

const STEPS = ['You', 'Preferences', 'Connect', 'Assistant']
const CURRENCIES = ['USD', 'EUR', 'GBP', 'EGP', 'AED', 'SAR', 'KWD', 'QAR', 'JPY', 'CAD', 'AUD', 'INR']
const HIDDEN = 'hiddenTabs' as SettingKey // synced on the Mac; see the note in the report

const defaultCity = (): string => Intl.DateTimeFormat().resolvedOptions().timeZone.split('/').pop()?.replace(/_/g, ' ') || 'London'

export default function SetupFlow({ onDone, onSeePro, startAt = 0 }: { onDone: () => void; onSeePro?: () => void; startAt?: number }) {
  const [step, setStep] = useState(startAt)
  const [forward, setForward] = useState(true)
  const userName = useSetting<string>('userName', '')
  const assistantName = useSetting<string>('assistantName', 'Joshu')
  const [name, setName] = useState(userName)
  const [aiName, setAiName] = useState(assistantName)

  const trimmed = name.trim()
  const aiNameOrDefault = aiName.trim() || 'Joshu'

  const go = (i: number) => {
    if (step === 0 && trimmed) store.setSetting('userName', trimmed)
    setForward(i > step)
    setStep(Math.max(0, Math.min(STEPS.length - 1, i)))
  }
  const finish = () => {
    if (trimmed) store.setSetting('userName', trimmed)
    store.setSetting('assistantName', aiNameOrDefault)
    try { localStorage.removeItem(KEY) } catch { /* private storage */ }
    emit()
    onDone()
  }

  // Android back: the previous step.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape' && step > 0) go(step - 1) }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })

  const last = step === STEPS.length - 1
  return (
    <div className="po-screen">
      <div className="po-setup-head">
        <div className="po-bars">{STEPS.map((s, i) => <span key={s}><i style={{ transform: `scaleX(${i <= step ? 1 : 0})` }} /></span>)}</div>
        <span className="label">Step {step + 1} of {STEPS.length} · {STEPS[step]}</span>
      </div>

      <div className="po-setup-body">
        <div key={step} className={`po-setup-step ${forward ? 'fwd' : 'back'}`}>
          {step === 0 && <NameStep name={name} setName={setName} onSubmit={() => { if (trimmed) go(1) }} />}
          {step === 1 && <PreferencesStep />}
          {step === 2 && <ConnectStep />}
          {step === 3 && <AssistantStep aiName={aiName} setAiName={setAiName} aiNameOrDefault={aiNameOrDefault} onSubmit={finish}
            onSeePro={onSeePro && (() => { finish(); setTimeout(onSeePro, 500) })} />}
        </div>
      </div>

      <div className="po-setup-foot">
        {step > 0 && <button className="po-link" style={{ fontSize: 14 }} onClick={() => go(step - 1)}>Back</button>}
        <button className="btn-primary" disabled={step === 0 && !trimmed} onClick={() => (last ? finish() : go(step + 1))}>
          {last ? 'Start using Joshu' : 'Continue'}
        </button>
      </div>
    </div>
  )
}

function Title({ text, detail }: { text: string; detail: string }) {
  return <div className="po-setup-title"><h1>{text}</h1><p>{detail}</p></div>
}

// MARK: Steps

function NameStep({ name, setName, onSubmit }: { name: string; setName: (s: string) => void; onSubmit: () => void }) {
  return (
    <>
      <div className="po-wordmark">joshu<Orb size={13} spark={false} /></div>
      <Title text="What should we call you?" detail="Joshu greets you by name and uses it in your morning brief." />
      <input className="po-big-field" autoFocus placeholder="Your name" autoCapitalize="words" value={name}
        onChange={(e) => setName(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') onSubmit() }} />
    </>
  )
}

function PreferencesStep() {
  const currency = useSetting<string>('currencyCode', defaultCurrency())
  const budget = useSetting<number>('monthlyBudget', 2000)
  const city = useSetting<string>('weatherCity', '')
  const goal = useSetting<number>('readingGoal', 24)
  const assistant = useSetting<string>('assistantName', 'Joshu') || 'Joshu'
  const [budgetText, setBudgetText] = useState(String(budget))
  const [cityText, setCityText] = useState(city)
  const [hidden, setHidden] = useState<Set<string>>(() => readHidden())
  const currencies = CURRENCIES.includes(currency) ? CURRENCIES : [currency, ...CURRENCIES]

  const toggle = (t: string, on: boolean) => {
    const next = new Set(hidden)
    if (on) next.add(t); else next.delete(t)
    setHidden(next)
    const value = [...next].filter((x) => x !== 'today').sort().join(',')
    store.setSetting(HIDDEN, value)
    try { localStorage.setItem('hiddenTabs', value) } catch { /* private storage */ }
  }

  return (
    <>
      <Title text="A few preferences" detail="So money, weather and reading look right from day one. You can change any of these in Settings." />
      <div className="po-prefs">
        <PrefRow label="Currency" icon={<Banknote size={12} strokeWidth={2.8} />} tint="var(--mint)">
          <select value={currency} onChange={(e) => store.setSetting('currencyCode', e.target.value)}>
            {currencies.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </PrefRow>
        <PrefRow label="Monthly budget" icon={<PieChart size={12} strokeWidth={2.8} />} tint="var(--peach)">
          <input inputMode="decimal" placeholder="2000" value={budgetText}
            onChange={(e) => {
              setBudgetText(e.target.value)
              const v = Number(e.target.value.replace(/[^\d.]/g, ''))
              if (e.target.value.trim() && isFinite(v)) store.setSetting('monthlyBudget', v)
            }} />
        </PrefRow>
        <PrefRow label="Weather city" icon={<CloudSun size={12} strokeWidth={2.8} />} tint="var(--cyan)">
          <input className="city" placeholder={defaultCity()} value={cityText}
            onChange={(e) => setCityText(e.target.value)} onBlur={() => store.setSetting('weatherCity', cityText.trim())} />
        </PrefRow>
        <PrefRow label="Books a year" icon={<Library size={12} strokeWidth={2.8} />} tint="var(--purple)">
          <span className="po-stepper">
            <span>{goal}</span>
            <div>
              <button aria-label="Fewer" disabled={goal <= 1} onClick={() => store.setSetting('readingGoal', Math.max(1, goal - 1))}><Minus size={15} /></button>
              <button aria-label="More" disabled={goal >= 200} onClick={() => store.setSetting('readingGoal', Math.min(200, goal + 1))}><Plus size={15} /></button>
            </div>
          </span>
        </PrefRow>
      </div>

      <div className="col" style={{ gap: 10 }}>
        <span style={{ fontSize: 14, fontWeight: 600 }}>What will you use?</span>
        <div className="po-chips">
          {TABS.map((t) => {
            const on = !hidden.has(t.id)
            return (
              <button key={t.id} className={`po-chip ${on ? 'on' : ''}`} onClick={() => toggle(t.id, on)}>
                {t.icon}{t.id === 'assistant' ? assistant : t.title}
              </button>
            )
          })}
        </div>
        <span style={{ fontSize: 12, color: 'var(--ink3)' }}>Tap to hide what you won't use. Everything stays one tap away in Settings.</span>
      </div>
    </>
  )
}

function ConnectStep() {
  const keys = useKeys()
  const [, bump] = useState(0)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  useEffect(() => onSmsChange(() => bump((n) => n + 1)), [])

  const google = async () => {
    setBusy('google'); setError('')
    const r = await window.orbit.googleSignIn()
    await refreshKeys()
    if (r.ok) { syncVault().catch(() => {}); refreshGoogleCalendar(true) } else if (r.error && !/cancel/i.test(r.error)) setError(r.error)
    setBusy('')
  }
  const sms = async () => {
    setBusy('sms'); setError('')
    if (!isNative) setError('Reading bank texts works in the Android app.')
    else if (!(await enableSms())) setError('Joshu needs permission to read your texts. You can turn this on later in Settings › Money.')
    setBusy('')
  }

  return (
    <>
      <Title text="Bring in your day" detail="Connect what you already use, and Joshu fills itself in. Skip anything and connect it later in Settings." />
      <div className="col" style={{ gap: 10 }}>
        {keys.googleClient && (
          <ConnectRow icon={<Mail size={16} strokeWidth={2.6} />} tint="var(--pink)" title="Gmail & Google Calendar"
            detail={keys.gmail.length ? keys.gmail.join(', ') : 'Receipts, bookings and what needs a reply'}
            done={keys.gmail.length > 0} busy={busy === 'google'} onConnect={google} />
        )}
        <ConnectRow icon={<MessageSquareText size={16} strokeWidth={2.6} />} tint="var(--cyan)" title="Bank texts"
          detail="Card payments from your bank's texts land in Money by themselves" done={smsEnabled()} busy={busy === 'sms'} onConnect={sms} />
      </div>
      {error && <span style={{ fontSize: 13, color: 'var(--orange)' }}>{error}</span>}
    </>
  )
}

function AssistantStep({ aiName, setAiName, aiNameOrDefault, onSubmit, onSeePro }: {
  aiName: string; setAiName: (s: string) => void; aiNameOrDefault: string; onSubmit: () => void; onSeePro?: () => void
}) {
  const [pro, setPro] = useState(isPro())
  useEffect(() => onProChange(() => setPro(isPro())), [])
  return (
    <>
      <div style={{ display: 'flex', justifyContent: 'center' }}><Orb size={84} busy /></div>
      <Title text="Name your assistant" detail="It plans with you, writes, searches and gets things done. Call it anything you like." />
      <input className="po-big-field" placeholder="Joshu" value={aiName} onChange={(e) => setAiName(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter') onSubmit() }} />
      {!pro && (
        <div className="po-pro-card">
          <span className="po-dot" style={{ width: 30, height: 30, background: 'var(--lime)' }}><Sparkles size={13} strokeWidth={2.8} /></span>
          <div className="col" style={{ gap: 4, minWidth: 0 }}>
            <span style={{ fontSize: 14, fontWeight: 600 }}>Your assistant comes with Joshu Pro</span>
            <span className="secondary" style={{ fontSize: 13, lineHeight: 1.35 }}>Everything else in Joshu is free. Upgrade whenever you like and {aiNameOrDefault} will be ready.</span>
            {onSeePro && <button className="link" style={{ alignSelf: 'flex-start', fontSize: 13, fontWeight: 600, color: 'var(--ink)', paddingTop: 2 }} onClick={onSeePro}>See Joshu Pro</button>}
          </div>
        </div>
      )}
    </>
  )
}

// MARK: Pieces

const TABS: { id: string; title: string; icon: ReactNode }[] = [
  { id: 'assistant', title: 'Assistant', icon: <Sparkles size={13} /> },
  { id: 'insights', title: 'Insights', icon: <LineChart size={13} /> },
  { id: 'calendar', title: 'Calendar', icon: <Calendar size={13} /> },
  { id: 'tasks', title: 'Tasks', icon: <ListChecks size={13} /> },
  { id: 'habits', title: 'Habits', icon: <Flame size={13} /> },
  { id: 'bucket', title: 'Bucket list', icon: <Mountain size={13} /> },
  { id: 'money', title: 'Money', icon: <CreditCard size={13} /> },
  { id: 'notes', title: 'Journal & Notes', icon: <BookOpenText size={13} /> },
  { id: 'ideas', title: 'Ideas', icon: <Lightbulb size={13} /> },
  { id: 'reading', title: 'Reading', icon: <Library size={13} /> },
  { id: 'github', title: 'GitHub', icon: <Code2 size={13} /> },
  { id: 'linkedin', title: 'LinkedIn', icon: <Briefcase size={13} /> },
]

function readHidden(): Set<string> {
  let raw = store.setting<string>(HIDDEN)
  if (raw == null) try { raw = localStorage.getItem('hiddenTabs') ?? '' } catch { raw = '' }
  return new Set((raw ?? '').split(',').filter(Boolean))
}

function PrefRow({ label, icon, tint, children }: { label: string; icon: ReactNode; tint: string; children: ReactNode }) {
  return (
    <div className="po-pref">
      <span className="po-dot" style={{ background: tint }}>{icon}</span>
      <span className="name">{label}</span>
      {children}
    </div>
  )
}

function ConnectRow({ icon, tint, title, detail, done, busy, onConnect }: {
  icon: ReactNode; tint: string; title: string; detail: string; done: boolean; busy: boolean; onConnect: () => void
}) {
  return (
    <div className="po-connect">
      <span className="tile" style={{ background: tint }}>{icon}</span>
      <span className="what"><b>{title}</b><span>{detail}</span></span>
      {done
        ? <CheckCircle2 size={24} aria-label="Connected" style={{ color: 'var(--good)', flex: 'none' }} />
        : <button className="btn-soft" disabled={busy} onClick={onConnect}>{busy ? <span className="po-spin" /> : 'Connect'}</button>}
    </div>
  )
}
