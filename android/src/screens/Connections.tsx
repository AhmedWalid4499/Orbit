// Settings › Connections (the iPhone's PhoneConnections + OtherConnections): Google (Gmail and Calendar), GitHub,
// bank texts (Android's own: read from your bank's SMS), reading (Goodreads shelves and updates), the AI key, and
// what connects on the iPhone or Mac. Google sign-ins and the GitHub token can also arrive from your account's
// key sync, so this mostly shows what's connected.
import { useEffect, useState, ReactNode } from 'react'
import { Plus, ArrowUpRight, Hourglass, MessageSquareText, Apple, HeartPulse, Youtube, Linkedin, CalendarDays, Github, Sparkles } from 'lucide-react'
import { Modal } from '@/components/ui'
import { useKeys, refreshKeys } from '@/lib/ai'
import { store, useSetting } from '@/lib/store'
import { emailExpensesEnabled, setEmailExpensesEnabled, startEmailExpensesTimer } from '@/lib/emailExpenses'
import { setExternalEvents } from '@/lib/externalEvents'
import { syncVault, vaultState, onVaultChange } from '@/lib/vault'
import * as cloud from '@/lib/cloud'
import { secrets, loadSecrets } from '../secrets'
import { refreshGoogleCalendar } from '../gcal'
import { smsEnabled, onSmsChange } from '../sms'
import { isPro } from '../pro'
import { loadGitHub, clearGitHubCache, cleanUsername } from '../lib/github'
import GoodreadsSettings, { GoodreadsLogo } from '../components/GoodreadsSettings'
import { Group, Cell, Tile, ToggleCell, SheetNav } from '../components/psKit'

/** Same name as the Mac's @AppStorage("googleCalendarEnabled"); on unless turned off. */
const GCAL_KEY = 'googleCalendarEnabled'
export const googleCalendarEnabled = (): boolean => { try { return localStorage.getItem(GCAL_KEY) !== 'false' } catch { return true } }
function setGoogleCalendarEnabled(on: boolean): void {
  try { localStorage.setItem(GCAL_KEY, on ? 'true' : 'false') } catch { /* ignore */ }
  if (on) refreshGoogleCalendar(true)
  else setExternalEvents([])
}

/** Connections on its own (kept for anything that opens it directly). Settings shows `ConnectionsPage` as a page. */
export default function Connections({ open, onClose, onBankTexts }: { open: boolean; onClose: () => void; onBankTexts?: () => void }) {
  return (
    <Modal open={open} onClose={onClose} width={560}>
      <div className="ps-root ps-grouped">
        <SheetNav title="Connections" onDone={onClose} />
        <div className="ps-body"><ConnectionsPage onBankTexts={onBankTexts} /></div>
      </div>
    </Modal>
  )
}

export function ConnectionsPage({ onBankTexts }: { onBankTexts?: () => void }) {
  const [vs, setVs] = useState(vaultState())
  useEffect(() => { const off = onVaultChange(() => setVs(vaultState())); return () => { off() } }, [])
  const waiting = !!cloud.getSession() && vs.state === 'needsPassphrase'
  return (
    <>
      {waiting && (
        <Group>
          <Cell icon={<Hourglass size={18} className="ps-chev" />} title={<span style={{ fontSize: 14, fontWeight: 400 }}>
            Waiting for your sign-ins. Unlock your keys in Settings › Account & sync (or open Joshu on your Mac once) and they'll appear here.</span>} />
        </Group>
      )}
      <GoogleSection />
      <GitHubSection />
      <Group title="Bank texts" footer="On Android, Joshu reads your bank's text messages on this phone. On iPhone a Shortcuts automation does the same job.">
        <BankTextsRow onOpen={onBankTexts} />
      </Group>
      <ReadingSection />
      <AISection />
      <Group title="On iPhone and Mac" icons footer="These connect in Joshu on your iPhone or Mac. What they add to your account shows here too.">
        <Cell icon={<Tile color="var(--cyan)" large><Apple size={16} /></Tile>} title="Apple Calendar & Reminders" sub="Events and reminders added there come here through your account." />
        <Cell icon={<Tile color="var(--pink)" large><HeartPulse size={16} /></Tile>} title="Health" sub="Steps, sleep and workouts, on iPhone." />
        <Cell icon={<Tile color="#FF0033" ink="#fff" large><Youtube size={16} /></Tile>} title="YouTube" sub="Your channel's subscribers and latest videos." />
        <Cell icon={<Tile color="#0A66C2" ink="#fff" large><Linkedin size={16} /></Tile>} title="LinkedIn" sub="Your profile. Job alerts from LinkedIn's emails show under More › Jobs here." />
        <Cell icon={<Tile color="#0078D4" ink="#fff" large><CalendarDays size={16} /></Tile>} title="Outlook calendar" sub="Shows next to your other calendars." />
      </Group>
    </>
  )
}

// MARK: Google

/** Gmail's envelope, in its colours. */
function GmailLogo({ size = 32 }: { size?: number }) {
  return (
    <span className="ps-tile lg" style={{ width: size, height: size, background: '#fff', boxShadow: 'inset 0 0 0 1px rgba(0,0,0,0.08)' }}>
      <svg viewBox="0 0 48 36" width={size * 0.62} height={size * 0.47}>
        <path fill="#4285F4" d="M3 36h8V16.6L0 8.5V33a3 3 0 0 0 3 3z" />
        <path fill="#34A853" d="M37 36h8a3 3 0 0 0 3-3V8.5l-11 8.1z" />
        <path fill="#FBBC04" d="M37 2.6v14L48 8.5V4.1c0-3.7-4.2-5.8-7.2-3.6z" />
        <path fill="#EA4335" d="M11 16.6v-14l13 9.7 13-9.7v14l-13 9.7z" />
        <path fill="#C5221F" d="M0 4.1v4.4l11 8.1v-14L7.2.5C4.2-1.7 0 .4 0 4.1z" />
      </svg>
    </span>
  )
}

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

  return (
    <Group title="Google" icons footer={keys.gmail.length > 0
      ? 'Inbox summaries send the sender, subject and a short preview of the last two days of mail (no promotions or social) to Anthropic. Expense import also sends the text of emails that look like receipts.'
      : !keys.googleClient ? 'Google sign-in arrives with your keys from your Joshu account (Account & sync). Once it is here you can add Gmail accounts.' : undefined}>
      {keys.gmail.length === 0 ? (
        <Cell top icon={<GmailLogo />} title="Gmail" sub="Connect Gmail and your assistant summarises your inbox on Today. Accounts you added on your Mac come here on their own." />
      ) : keys.gmail.map((email) => (
        <Cell key={email} icon={<GmailLogo />} title={<span className="clamp1">{email}</span>} sub={<span className="ps-good">Connected</span>}
          trailing={<button className="ps-soft ps-danger" aria-label={`Remove ${email}`} onClick={() => remove(email)}>Remove</button>} />
      ))}
      {keys.googleClient && (
        <Cell onClick={busy ? undefined : add} icon={<span className="ps-tile lg" style={{ color: '#0a84ff' }}><Plus size={20} /></span>}
          title={<span className="ps-blue" style={{ fontSize: 16 }}>{busy ? 'Waiting for Google…' : keys.gmail.length ? 'Add another Gmail account' : 'Add Gmail account'}</span>} />
      )}
      {keys.gmail.length > 0 && <>
        <ToggleCell title="Show Google Calendar events" on={calendar} onChange={(on) => { setGoogleCalendarEnabled(on); setCalendar(on) }} />
        <ToggleCell title="Add receipts from email to Money" on={expenses} onChange={(on) => { setEmailExpensesEnabled(on); setExpenses(on); if (on) startEmailExpensesTimer() }} />
      </>}
      {keys.gmail.length > 0 && (
        <Cell top title={<span style={{ fontSize: 15 }}>Inbox summary</span>}
          sub={keys.anthropic ? 'Your assistant reads the last two days of mail when you open Today and lists who is waiting on you, bills, deliveries and alerts.'
            : 'With Joshu Pro, your assistant summarises your inbox: who is waiting on you, bills, deliveries and alerts.'} />
      )}
      {error && <Cell title={<span className="ps-bad" style={{ fontSize: 13, fontWeight: 400 }}>{error}</span>} />}
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
      syncVault().catch(() => {})
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
  const logo = <Tile color="var(--inverse)" ink="var(--on-inverse)" large><Github size={16} /></Tile>
  return (
    <Group title="GitHub" icons>
      {user ? (
        <Cell icon={logo} title={`@${user}`} sub={hasToken ? 'Private repos and contributions included' : 'Public data only'}
          trailing={<button className="ps-soft" onClick={disconnect}>Disconnect</button>} />
      ) : (
        <>
          <Cell top icon={logo} title="Connect GitHub" sub="Your projects, pull requests, issues and activity, next to the rest of your day." />
          <div className="ps-cell col">
            <input className="ps-field" placeholder="GitHub username" autoCapitalize="none" autoCorrect="off" value={draftUser} onChange={(e) => setDraftUser(e.target.value)} />
            <input className="ps-field" type="password" placeholder="Paste your token (ghp_…), optional" value={draftToken} onChange={(e) => setDraftToken(e.target.value)} />
            <span className="ps-cell-sub">With just your username, Joshu shows your public work. To include private repos and your contribution graph, give it a token.
              It's kept encrypted on this phone and only used to read your GitHub data.</span>
            <div className="ps-btnrow">
              <button className="ps-soft" onClick={() => window.orbit.openExternal('https://github.com/settings/tokens/new?description=Joshu&scopes=repo,read:user')}>
                <ArrowUpRight size={14} /> Make a token
              </button>
              <span className="spacer" />
              <button className="ps-primary" disabled={!cleanUsername(draftUser) || busy} onClick={connect}>
                {busy ? 'Connecting…' : draftToken.trim() ? 'Connect' : 'Skip, public only'}
              </button>
            </div>
            {error && <span className="ps-bad" style={{ fontSize: 12 }}>{error}</span>}
          </div>
        </>
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
    <Cell icon={<Tile color="var(--lime)" large><MessageSquareText size={16} /></Tile>} title="Bank texts"
      sub={on ? <span className="ps-good">Logging payments from your bank's texts</span> : "Log card payments, transfers and salary from your bank's text messages"}
      trailing={onOpen && <button className={on ? 'ps-soft' : 'ps-primary'} onClick={onOpen}>{on ? 'Options' : 'Set up'}</button>} />
  )
}

// MARK: Reading

function ReadingSection() {
  const profile = useSetting<string>('goodreadsUser', '')
  const [draft, setDraft] = useState('')
  const [adding, setAdding] = useState(false)
  const [confirm, setConfirm] = useState(false)
  return (
    <Group title="Reading" icons footer="Apple Books and Kindle are imported by Joshu on your Mac, and the books then appear here on their own.">
      <Cell icon={<GoodreadsLogo size={32} />} title="Goodreads shelves"
        sub={profile ? <span className="ps-good">Shelves sync from your profile</span> : 'Not connected'}
        trailing={profile
          ? confirm
            ? <button className="ps-soft ps-danger" onClick={() => { store.setSetting('goodreadsUser', ''); setConfirm(false) }}>Disconnect?</button>
            : <button className="ps-soft" onClick={() => setConfirm(true)}>Disconnect</button>
          : <button className="ps-primary" onClick={() => setAdding(!adding)}>Connect</button>} />
      {!profile && adding && (
        <div className="ps-cell col">
          <input className="ps-field" placeholder="Profile link or user ID" autoCapitalize="none" autoCorrect="off" value={draft} onChange={(e) => setDraft(e.target.value)} />
          <span className="ps-cell-sub">Your public Goodreads shelves come into Reading. Joshu on your Mac or iPhone fetches them.</span>
          <button className="ps-primary" style={{ alignSelf: 'flex-end' }} disabled={!/\d/.test(draft)}
            onClick={() => { store.setSetting('goodreadsUser', draft.trim()); setDraft(''); setAdding(false) }}>Connect</button>
        </div>
      )}
      <div className="ps-cell col" style={{ padding: 0 }}><GoodreadsSettings plain /></div>
    </Group>
  )
}

// MARK: AI

function AISection() {
  const keys = useKeys()
  const own = !!secrets.get('anthropic-api-key')
  const [confirm, setConfirm] = useState(false)
  const remove = async () => {
    await window.orbit.setSecret('anthropic-api-key', '')
    await refreshKeys()
    setConfirm(false)
  }
  return (
    <Group title="AI" icons footer={own ? "Removing your key deletes it from this phone. Add it again in Settings › AI." : undefined}>
      <Cell icon={<Tile color="#D97757" ink="#fff" large><Sparkles size={16} /></Tile>} title="Claude"
        sub={own ? <span className="ps-good">Your own Anthropic key powers the assistant</span>
          : isPro() ? <span className="ps-good">Through Joshu Pro, nothing to set up</span>
          : keys.anthropic ? <span className="ps-good">Connected</span> : 'Not connected'}
        trailing={own && (confirm
          ? <button className="ps-soft ps-danger" onClick={remove}>Remove key?</button>
          : <button className="ps-soft" onClick={() => setConfirm(true)}>Disconnect</button>)} />
    </Group>
  )
}

export function Footnote({ children }: { children: ReactNode }) {
  return <span className="muted" style={{ fontSize: 12 }}>{children}</span>
}
