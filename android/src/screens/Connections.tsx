// Connections (the iPhone's PhoneConnections): Google (Gmail and Calendar), GitHub, bank texts and Goodreads.
// Google sign-ins and the GitHub token can also arrive from your account's key sync, so this mostly shows what's
// connected. Apple-only connections (Calendar, Reminders, Health, Wallet) are listed as living on iPhone and Mac.
import { useEffect, useState, ReactNode } from 'react'
import { Mail, Code2, MessageSquareText, Plus, Check, Trash2, ArrowUpRight, Apple } from 'lucide-react'
import { Modal, Card } from '@/components/ui'
import { useKeys, refreshKeys } from '@/lib/ai'
import { emailExpensesEnabled, setEmailExpensesEnabled, startEmailExpensesTimer } from '@/lib/emailExpenses'
import { setExternalEvents } from '@/lib/externalEvents'
import { secrets, loadSecrets } from '../secrets'
import { syncVault } from '@/lib/vault'
import { refreshGoogleCalendar } from '../gcal'
import { smsEnabled, onSmsChange } from '../sms'
import { loadGitHub, clearGitHubCache, cleanUsername } from '../lib/github'
import GoodreadsSettings from '../components/GoodreadsSettings'

/** Same name as the Mac's @AppStorage("googleCalendarEnabled"); on unless turned off. */
const GCAL_KEY = 'googleCalendarEnabled'
export const googleCalendarEnabled = (): boolean => { try { return localStorage.getItem(GCAL_KEY) !== 'false' } catch { return true } }
function setGoogleCalendarEnabled(on: boolean): void {
  try { localStorage.setItem(GCAL_KEY, on ? 'true' : 'false') } catch { /* ignore */ }
  if (on) refreshGoogleCalendar(true)
  else setExternalEvents([])
}

export default function Connections({ open, onClose, onBankTexts }: { open: boolean; onClose: () => void; onBankTexts?: () => void }) {
  return (
    <Modal open={open} onClose={onClose} width={560}>
      <h2 className="page-title" style={{ fontSize: 28, marginBottom: 18 }}>Connections</h2>
      <GoogleSection />
      <GitHubSection />
      <Group title="Bank texts"><BankTextsRow onOpen={onBankTexts} /></Group>
      <Group title="Reading">
        <GoodreadsSettings />
        <Footnote>Apple Books and Kindle are imported by Joshu on your Mac, and the books then appear here on their own.</Footnote>
      </Group>
      <Group title="On iPhone and Mac" footer="Apple Calendar, Reminders, Health and Wallet connect in Joshu on your iPhone or Mac. What they add to your account shows here too.">
        {['Apple Calendar', 'Apple Reminders', 'Health', 'Wallet'].map((name) => (
          <Row key={name} icon={<Apple size={15} />} tint="var(--card-hover)" title={name} detail="On iPhone and Mac" />
        ))}
      </Group>
    </Modal>
  )
}

// MARK: Google

function GoogleSection() {
  const keys = useKeys()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [calendar, setCalendar] = useState(googleCalendarEnabled())
  const [expenses, setExpenses] = useState(emailExpensesEnabled())

  const add = async () => {
    setBusy(true); setError('')
    const r = await window.orbit.googleSignIn()
    await refreshKeys()
    if (r.ok) {
      syncVault().catch(() => {}) // so your other devices get this sign-in too
      startEmailExpensesTimer()
      if (googleCalendarEnabled()) refreshGoogleCalendar(true)
    } else setError(r.error ?? 'Google sign-in failed.')
    setBusy(false)
  }
  const remove = async (email: string) => {
    await window.orbit.googleRemove(email)
    await refreshKeys()
    refreshGoogleCalendar(true)
  }
  const addButton = keys.googleClient && (
    <button className="btn-soft" style={{ alignSelf: 'flex-start' }} disabled={busy} onClick={add}>
      <Plus size={13} /> {busy ? 'Waiting for Google…' : keys.gmail.length ? 'Add another Gmail account' : 'Add Gmail account'}
    </button>
  )

  return (
    <Group title="Google">
      {keys.gmail.length === 0 ? (
        <Row icon={<Mail size={15} />} tint="var(--pink)" title="Gmail"
          detail="Connect Gmail and your assistant summarises your inbox on Today. Accounts you added on your Mac come here on their own." />
      ) : keys.gmail.map((email) => (
        <Row key={email} icon={<Mail size={15} />} tint="var(--pink)" title={email}
          detail={<span className="row" style={{ gap: 4, color: 'var(--good)' }}><Check size={12} /> Connected</span>}
          trailing={<button className="btn-soft" aria-label={`Remove ${email}`} onClick={() => remove(email)}><Trash2 size={12} /> Remove</button>} />
      ))}
      {addButton}
      {!keys.googleClient && (
        <Footnote>Google sign-in arrives with your keys from your Joshu account (Settings › AI). Once it's here you can add Gmail accounts.</Footnote>
      )}
      {keys.gmail.length > 0 && <>
        <Toggle label="Show Google Calendar events" on={calendar} onChange={(on) => { setGoogleCalendarEnabled(on); setCalendar(on) }} />
        <Toggle label="Add receipts from email to Money" on={expenses} onChange={(on) => { setEmailExpensesEnabled(on); setExpenses(on); if (on) startEmailExpensesTimer() }} />
      </>}
      {error && <span style={{ fontSize: 12, color: 'var(--critical)' }}>{error}</span>}
    </Group>
  )
}

// MARK: GitHub

function GitHubSection() {
  const [ready, setReady] = useState(false)
  const [user, setUser] = useState('')
  const [hasToken, setHasToken] = useState(false)
  const [draftUser, setDraftUser] = useState('')
  const [draftToken, setDraftToken] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    loadSecrets().then(() => { setUser(secrets.get('github-user') ?? ''); setHasToken(!!secrets.get('github-token')); setReady(true) })
  }, [])

  const connect = async () => {
    const u = cleanUsername(draftUser), t = draftToken.trim()
    if (!u) return
    setBusy(true); setError('')
    try {
      const d = await loadGitHub(u, t || undefined)
      await window.orbit.setSecret('github-user', d.profile.login || u)
      await window.orbit.setSecret('github-token', t)
      setUser(d.profile.login || u); setHasToken(!!t); setDraftUser(''); setDraftToken('')
    } catch (e: any) { setError(e?.message ?? String(e)) }
    setBusy(false)
  }
  const disconnect = async () => {
    await window.orbit.setSecret('github-user', '')
    await window.orbit.setSecret('github-token', '')
    clearGitHubCache()
    setUser(''); setHasToken(false)
  }

  if (!ready) return null
  return (
    <Group title="GitHub">
      {user ? (
        <Row icon={<Code2 size={15} />} tint="var(--inverse)" ink="var(--on-inverse)" title={`@${user}`}
          detail={hasToken ? 'Private repos and contributions included' : 'Public data only'}
          trailing={<button className="btn-soft" onClick={disconnect}>Disconnect</button>} />
      ) : (
        <div className="col" style={{ gap: 10 }}>
          <Row icon={<Code2 size={15} />} tint="var(--inverse)" ink="var(--on-inverse)" title="Connect GitHub"
            detail="Your projects, pull requests, issues and activity, next to the rest of your day." />
          <input className="field" style={{ background: 'var(--canvas)' }} placeholder="GitHub username" autoCapitalize="none" autoCorrect="off"
            value={draftUser} onChange={(e) => setDraftUser(e.target.value)} />
          <input className="field" style={{ background: 'var(--canvas)' }} type="password" placeholder="Paste your token (ghp_…), optional"
            value={draftToken} onChange={(e) => setDraftToken(e.target.value)} />
          <Footnote>With just your username, Joshu shows your public work. To include private repos and your contribution graph, give it a token.
            It's kept encrypted on this phone and only used to read your GitHub data.</Footnote>
          <div className="row" style={{ gap: 8 }}>
            <button className="btn-soft" onClick={() => window.orbit.openExternal('https://github.com/settings/tokens/new?description=Joshu&scopes=repo,read:user')}>
              <ArrowUpRight size={13} /> Open GitHub
            </button>
            <span className="spacer" />
            <button className="btn-primary" disabled={!cleanUsername(draftUser) || busy} onClick={connect}>
              {busy ? 'Connecting…' : draftToken.trim() ? 'Connect' : 'Skip, public only'}
            </button>
          </div>
          {error && <span style={{ fontSize: 12, color: 'var(--critical)' }}>{error}</span>}
        </div>
      )}
    </Group>
  )
}

// MARK: Bank texts

function BankTextsRow({ onOpen }: { onOpen?: () => void }) {
  const [, tick] = useState(0)
  useEffect(() => onSmsChange(() => tick((n) => n + 1)), [])
  const on = smsEnabled()
  return (
    <Row icon={<MessageSquareText size={15} />} tint="var(--lime)" title="Bank texts"
      detail={on ? <span style={{ color: 'var(--good)' }}>Logging card payments from your bank's texts</span> : 'Log card payments, transfers and salary from your bank\'s text messages'}
      trailing={onOpen && <button className={on ? 'btn-soft' : 'btn-primary'} onClick={onOpen}>{on ? 'Options' : 'Set up'}</button>} />
  )
}

// MARK: Pieces

function Group({ title, footer, children }: { title: string; footer?: string; children: ReactNode }) {
  return (
    <div className="col" style={{ gap: 6, marginBottom: 18 }}>
      <span className="muted" style={{ fontSize: 12, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.4, paddingLeft: 4 }}>{title}</span>
      <Card padding={14}><div className="col" style={{ gap: 12 }}>{children}</div></Card>
      {footer && <span className="muted" style={{ fontSize: 12, paddingLeft: 4 }}>{footer}</span>}
    </div>
  )
}

function Row({ icon, tint, ink = 'var(--sticker-ink)', title, detail, trailing }: {
  icon: ReactNode; tint: string; ink?: string; title: string; detail?: ReactNode; trailing?: ReactNode
}) {
  return (
    <div className="row" style={{ gap: 12, alignItems: 'center', minWidth: 0 }}>
      <span style={{ width: 32, height: 32, borderRadius: 9, background: tint, color: ink, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>{icon}</span>
      <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
        <strong className="clamp1" style={{ fontSize: 15, fontWeight: 500 }}>{title}</strong>
        {detail && <span className="secondary" style={{ fontSize: 12 }}>{detail}</span>}
      </div>
      {trailing}
    </div>
  )
}

function Toggle({ label, on, onChange }: { label: string; on: boolean; onChange: (on: boolean) => void }) {
  return (
    <label className="row" style={{ gap: 10, fontSize: 14, minHeight: 32 }}>
      <span style={{ flex: 1 }}>{label}</span>
      <input type="checkbox" checked={on} onChange={(e) => onChange(e.target.checked)} />
    </label>
  )
}

function Footnote({ children }: { children: ReactNode }) {
  return <span className="muted" style={{ fontSize: 12 }}>{children}</span>
}
