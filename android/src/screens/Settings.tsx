// Settings on Android, laid out like the iPhone's PhoneSettings: your name and photo, your plan, then pages for
// Account & sync, AI, Connections, Notifications and General, and the version. Android's own pieces sit where the
// iPhone has the equivalent: bank texts (SMS) under Connections, "Hey Joshu" and memory under AI, updates under
// General, sign-out, key sync and account deletion under Account & sync.
import { useEffect, useState, ReactNode } from 'react'
import { RefreshCw, MessageSquareText, Download, UserRound, Link2, Bell, Settings as Gear, X, Trash2, KeyRound, ShieldCheck } from 'lucide-react'
import * as cloud from '@/lib/cloud'
import { store, useSetting, useStoreVersion } from '@/lib/store'
import { Modal, defaultCurrency } from '@/components/ui'
import { relativeTime } from '@/lib/dates'
import { useKeys, refreshKeys } from '@/lib/ai'
import { syncVault, vaultState, onVaultChange, forgetPassphrase } from '@/lib/vault'
import { useProfilePhoto, chooseProfilePhoto } from '@/lib/profileCard'
import { BANKS, chosenBanks, setChosenBanks, extraSenders, setExtraSenders } from '../bank'
import { smsEnabled, enableSms, disableSms, checkBankTexts, smsActivity, onSmsChange } from '../sms'
import { memories, setMemories } from './Assistant'
import { isNative, native } from '../native'
import DeleteAccount from '../components/DeleteAccount'
import { ConnectionsPage } from './Connections'
import { isPro, proUntil, refreshPro, onProChange } from '../pro'
import { Orb } from '../components/Orb'
import { wakeEnabled, setWakeEnabled } from '../voice'
import { secrets, clearSecrets } from '../secrets'
import { useNotify, setNotify, NotifySwitch, notificationsAllowed, requestNotifications } from '../reminders'
import { SheetNav, Group, Cell, Tile, ToggleCell, PickerCell, TextCell } from '../components/psKit'

const CURRENCIES = ['EGP', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'KWD', 'QAR', 'JPY', 'CAD', 'AUD', 'INR']
type Page = 'root' | 'account' | 'ai' | 'connections' | 'notifications' | 'general' | 'bank'
const TITLES: Record<Page, string> = {
  root: 'Settings', account: 'Account & sync', ai: 'AI', connections: 'Connections', notifications: 'Notifications', general: 'General', bank: 'Bank texts',
}
const PARENT: Partial<Record<Page, Page>> = { bank: 'connections' }

export default function Settings({ open, onClose, onSignIn }: { open: boolean; onClose: () => void; onSignIn: () => void }) {
  const [page, setPage] = useState<Page>('root')
  useEffect(() => { if (open) setPage('root') }, [open])
  return (
    <Modal open={open} onClose={onClose} width={560}>
      <div className="ps-root ps-grouped">
        <SheetNav title={TITLES[page]} onBack={page === 'root' ? undefined : () => setPage(PARENT[page] ?? 'root')} onDone={onClose} />
        <div className="ps-body" key={page}>
          {page === 'root' && <Root go={setPage} />}
          {page === 'account' && <AccountPage onClose={onClose} onSignIn={onSignIn} />}
          {page === 'ai' && <AIPage />}
          {page === 'connections' && <ConnectionsPage onBankTexts={() => setPage('bank')} />}
          {page === 'notifications' && <NotificationsPage />}
          {page === 'general' && <GeneralPage />}
          {page === 'bank' && <BankTextsPage />}
        </div>
      </div>
    </Modal>
  )
}

// MARK: Root

function Root({ go }: { go: (p: Page) => void }) {
  useStoreVersion()
  const userName = useSetting<string>('userName', '')
  const assistant = useSetting<string>('assistantName', 'Joshu') || 'Joshu'
  const photo = useProfilePhoto()
  const keys = useKeys()
  const session = cloud.getSession()
  const [version, setVersion] = useState('')
  useEffect(() => { window.orbit.config().then((c) => setVersion(c.version)) }, [])
  const initials = userName.split(' ').filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || 'Me'
  const row = (p: Page, title: string, icon: ReactNode, detail?: string) => <Cell onClick={() => go(p)} icon={icon} title={title} detail={detail} chevron />

  return (
    <>
      <Group>
        <div className="ps-me">
          <button className="ps-avatar" style={photo ? { backgroundImage: `url(${photo})` } : undefined} onClick={chooseProfilePhoto} aria-label="Choose a photo">
            {photo ? '' : initials}
          </button>
          <div className="col" style={{ gap: 4, flex: 1, minWidth: 0 }}>
            <input key={userName} className="ps-name-input" defaultValue={userName} placeholder="Your name"
              onBlur={(e) => { const v = e.target.value.trim(); if (v !== userName) store.setSetting('userName', v) }}
              onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} />
            <button className="ps-blue" style={{ alignSelf: 'flex-start' }} onClick={chooseProfilePhoto}>{photo ? 'Change photo' : 'Add a photo'}</button>
          </div>
        </div>
      </Group>
      <Group><ProRow /></Group>
      <Group icons>
        {row('account', 'Account & sync', <Tile color="var(--cyan)"><UserRound size={16} fill="currentColor" /></Tile>,
          store.isLocal ? 'On this phone only' : session?.email ?? 'Not signed in')}
        {row('ai', 'AI', <Orb size={30} />, keys.anthropic ? assistant : 'Joshu Pro')}
        {row('connections', 'Connections', <Tile color="var(--purple)"><Link2 size={16} /></Tile>)}
        {row('notifications', 'Notifications', <Tile color="var(--orange)"><Bell size={15} fill="currentColor" /></Tile>)}
        {row('general', 'General', <Tile color="#d1d1d6"><Gear size={16} /></Tile>)}
      </Group>
      <Group footer="Joshu on Android shares everything with Joshu on your iPhone and Mac through your Joshu account. Sign in with the same account on each.">
        <Cell title={<span style={{ fontWeight: 400 }}>Version</span>} detail={version} />
      </Group>
    </>
  )
}

/** Your plan (ProSettingsRow): Joshu Pro through your account, or your own Anthropic key. */
function ProRow({ full }: { full?: boolean }) {
  const [, tick] = useState(0)
  const [busy, setBusy] = useState(false)
  useEffect(() => onProChange(() => tick((n) => n + 1)), [])
  const assistant = useSetting<string>('assistantName', 'Joshu') || 'Joshu'
  const server = isPro(), own = !!secrets.get('anthropic-api-key'), on = server || own
  const until = proUntil()
  const check = async () => { setBusy(true); await refreshPro(); await refreshKeys(); setBusy(false) }
  return (
    <>
      <Cell top={full} icon={<Orb size={full ? 40 : 30} />} title={on ? 'Joshu Pro' : 'Joshu Free'}
        sub={on
          ? own && !server ? 'Using your own Anthropic key'
            : `${assistant} and all smart features are on${full && until < 4e12 ? ` until ${new Date(until).toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })}` : ''}`
          : 'Upgrade for your AI assistant, briefs, email summaries and more'}
        trailing={!on && !full ? <button className="ps-primary" disabled={busy} onClick={check}>{busy ? 'Checking…' : 'Check plan'}</button> : undefined} />
      {full && (
        <Cell title={<span className="ps-blue" style={{ fontSize: 15 }}>{busy ? 'Checking…' : 'Check my plan'}</span>} onClick={busy ? undefined : check}
          sub={on ? undefined : 'Pro is added to your Joshu account; once it is, it works here straight away. No API keys, nothing to set up.'} />
      )}
    </>
  )
}

// MARK: Account & sync

function AccountPage({ onClose, onSignIn }: { onClose: () => void; onSignIn: () => void }) {
  useStoreVersion()
  const session = cloud.getSession()
  const [signingOut, setSigningOut] = useState(false)

  if (store.isLocal || !session) {
    return (
      <Group footer="Sign in or create an account to sync with your other devices. What you've added here comes with you.">
        <Cell top title="On this phone only" sub="Your tasks, money, notes and the rest are kept on this phone and nowhere else." />
        <Cell onClick={onSignIn} title={<span className="ps-blue" style={{ fontSize: 16 }}>Sign in or create account</span>} />
      </Group>
    )
  }
  return (
    <>
      <Group title="Plan"><ProRow /></Group>
      <Group title="Joshu account">
        <Cell title={<span style={{ fontWeight: 400 }}>Signed in as</span>} detail={session.email} />
        <Cell title={<span style={{ fontWeight: 400, fontSize: 14 }} className="secondary">{store.syncing ? 'Syncing…' : store.status || 'Synced with your Joshu account'}</span>}
          sub={store.lastSync ? `Last synced ${relativeTime(store.lastSync)}` : undefined}
          trailing={<button className="ps-soft" onClick={() => store.sync()} disabled={store.syncing}><RefreshCw size={13} /> Sync Now</button>} />
        {signingOut
          ? <SignOutChoice onCancel={() => setSigningOut(false)} onDone={onClose} />
          : <button className="ps-cell" onClick={() => setSigningOut(true)}><span className="ps-cell-title ps-danger" style={{ fontWeight: 400 }}>Sign Out…</span></button>}
        <DeleteAccount onDone={onClose} />
      </Group>
      <KeySync />
      <Group>
        <Cell top title={<span style={{ fontSize: 13, fontWeight: 400 }} className="secondary">
          Your tasks, calendar events you made in Joshu, habits, money, notes and journal, books and bucket list sync to your account every few seconds. Sign in with the same account on another device to get everything there.</span>} />
      </Group>
    </>
  )
}

/** API keys and connections (KeySyncSection): end-to-end encrypted with your sync passphrase, shared with the Mac and iPhone. */
function KeySync() {
  const [vs, setVs] = useState(vaultState())
  const [pass, setPass] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  useEffect(() => { const off = onVaultChange(() => setVs(vaultState())); if (vaultState().state === 'idle') syncVault().catch(() => {}); return () => { off() } }, [])
  const unlock = async () => {
    setBusy(true); setMessage('')
    const r = await syncVault(pass.trim())
    setBusy(false)
    if (r.state === 'on') { setPass(''); setMessage('Your keys and sign-ins are here.') } else setMessage(r.message ?? '')
  }
  const st = vs.state
  return (
    <Group title="API keys and connections" footer="Your Anthropic key, GitHub token, Google sign-ins for Gmail and Calendar, and their settings arrive on every device you sign in to. They're stored encrypted in your account.">
      {st === 'on' && <Cell icon={<ShieldCheck size={18} className="ps-good" />} title={<span className="ps-good" style={{ fontSize: 15 }}>Synced with your Joshu account</span>}
        trailing={<button className="ps-soft" onClick={() => forgetPassphrase()}>Forget here</button>} />}
      {(st === 'needsPassphrase' || st === 'wrongPassphrase' || st === 'needsNewPassphrase') && (
        <div className="ps-cell col">
          <div className="row" style={{ gap: 10, alignItems: 'flex-start' }}>
            <KeyRound size={18} style={{ flex: 'none', marginTop: 2 }} />
            <span style={{ fontSize: 14 }}>{st === 'needsNewPassphrase'
              ? 'Bring your keys to your other devices, end-to-end encrypted. Choose a passphrase; you enter the same one on your Mac and iPhone.'
              : 'Your keys are synced from your Mac or iPhone. Enter your sync passphrase once to unlock them here.'}</span>
          </div>
          <input className="ps-field" type="password" placeholder={st === 'needsNewPassphrase' ? 'New sync passphrase' : 'Sync passphrase'} value={pass}
            onChange={(e) => setPass(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && pass.trim()) unlock() }} />
          {st === 'wrongPassphrase' && <span className="ps-bad" style={{ fontSize: 12 }}>That passphrase didn't work. Try again.</span>}
          <button className="ps-primary" style={{ alignSelf: 'flex-end' }} disabled={busy || pass.trim().length < (st === 'needsNewPassphrase' ? 6 : 1)} onClick={unlock}>
            {busy ? 'Unlocking…' : st === 'needsNewPassphrase' ? 'Turn on' : 'Unlock'}
          </button>
        </div>
      )}
      {st === 'idle' && <Cell title={<span className="secondary" style={{ fontSize: 14, fontWeight: 400 }}>Checking your account…</span>} />}
      {st === 'error' && <Cell title={<span className="ps-warn" style={{ fontSize: 13, fontWeight: 400 }}>{vs.message || "Couldn't reach your account."}</span>}
        trailing={<button className="ps-soft" onClick={() => syncVault()}>Retry</button>} />}
      {message && <Cell title={<span className="secondary" style={{ fontSize: 13, fontWeight: 400 }}>{message}</span>} />}
    </Group>
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
    <div className="ps-cell col">
      <strong style={{ fontSize: 15 }}>Sign out of Joshu?</strong>
      <span className="ps-cell-sub">
        Everything is saved to your account first, then removed from this phone, with your chats and connected accounts like Gmail.
        Sign in again and it all comes back. Keep a copy only on a phone that's just yours.
      </span>
      {error && <span className="ps-bad" style={{ fontSize: 13 }}>{error}</span>}
      <button className="ps-primary ps-wide" style={{ background: 'var(--critical)', color: '#fff' }} disabled={busy} onClick={() => go(false)}>
        {busy ? 'Saving to your account…' : 'Sign Out and Remove from This Phone'}
      </button>
      <button className="ps-soft ps-wide" disabled={busy} onClick={() => go(true)}>Sign Out and Keep a Copy Here</button>
      <button className="ps-soft ps-wide" disabled={busy} onClick={onCancel}>Cancel</button>
    </div>
  )
}

// MARK: AI

function AIPage() {
  const assistant = useSetting<string>('assistantName', 'Joshu') || 'Joshu'
  return (
    <>
      <Group><ProRow full /></Group>
      <Group title="Your assistant" footer="What you call your AI around Joshu: the tab, the orb, the journal and the morning brief.">
        <TextCell title="Name" value={assistant} placeholder="Joshu" onSave={(v) => store.setSetting('assistantName', v.trim() || 'Joshu')} />
      </Group>
      <MemoryGroup />
      <VoiceGroup />
      <OwnKeyGroup />
      <Group title="Privacy">
        <Cell top title={<span className="secondary" style={{ fontSize: 13, fontWeight: 400 }}>
          When you use {assistant}, Joshu sends Anthropic what it needs: what you ask or capture, and for the brief today's events, tasks, habits, this month's spending total and yesterday's journal entry.</span>} />
      </Group>
    </>
  )
}

/** Settings › AI › Memory (MemorySection), synced as "assistant.memory". */
function MemoryGroup() {
  useStoreVersion()
  const list = memories()
  const assistant = useSetting<string>('assistantName', 'Joshu') || 'Joshu'
  const [draft, setDraft] = useState('')
  const add = () => { if (draft.trim()) { setMemories([...list, draft]); setDraft('') } }
  return (
    <Group title="Memory" footer={`${assistant} remembers lasting things you tell it (preferences, routines, people) and uses them in every chat. It's kept with your settings and synced to your devices.`}>
      {list.length === 0 && <Cell title={<span className="secondary" style={{ fontSize: 13, fontWeight: 400 }}>Nothing yet. Tell {assistant} things like “I'm vegetarian” or “I go to the gym on Tuesdays” and it'll remember.</span>} />}
      {list.map((m) => (
        <Cell key={m} title={<span style={{ fontSize: 15, fontWeight: 400 }}>{m}</span>}
          trailing={<button className="ps-x" aria-label="Forget this" onClick={() => setMemories(list.filter((x) => x !== m))}><X size={15} /></button>} />
      ))}
      <label className="ps-cell">
        <input className="ps-input left" placeholder="Add something to remember" value={draft} onChange={(e) => setDraft(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && add()} />
        <button className="ps-blue" disabled={!draft.trim()} style={{ opacity: draft.trim() ? 1 : 0.4 }} onClick={add}>Add</button>
      </label>
      {list.length > 0 && <button className="ps-cell" onClick={() => setMemories([])}><span className="ps-cell-title ps-danger" style={{ fontWeight: 400 }}>Forget everything</span></button>}
    </Group>
  )
}

/** Settings › AI › Voice: read replies aloud, "Hey Joshu", and a preview of the voice. */
function VoiceGroup() {
  const name = useSetting<string>('assistantName', 'Joshu') || 'Joshu'
  const [wake, setWake] = useState(wakeEnabled())
  const [speaks, setSpeaks] = useState(() => localStorage.getItem('assistant.speakReplies') === 'on')
  const [playing, setPlaying] = useState(false)
  const preview = async () => {
    if (!isNative) return
    if (playing) { native.stopSpeaking().catch(() => {}); setPlaying(false); return }
    setPlaying(true)
    await native.speak({ text: "Hey! I had a look at your day. You've got two things this afternoon, so maybe grab lunch early? Let me know if you want me to move anything." }).catch(() => {})
    setPlaying(false)
  }
  return (
    <Group title="Voice" footer="Replies are read by your phone's voice. For a more natural one, pick a voice in Android Settings › Accessibility › Text-to-speech.">
      <ToggleCell title="Read replies aloud" on={speaks} onChange={(on) => { setSpeaks(on); localStorage.setItem('assistant.speakReplies', on ? 'on' : 'off') }} />
      <ToggleCell title={`Hands-free: answer when I say “Hey ${name}”`} on={wake} onChange={(on) => { setWake(on); setWakeEnabled(on) }}
        sub={`While Joshu is open it listens for “Hey ${name}”, then answers out loud. Listening happens on this phone; only your question goes to ${name}. Right after an answer you can just keep talking.`} />
      {isNative && <Cell onClick={preview} title={<span className="ps-blue" style={{ fontSize: 15 }}>{playing ? 'Stop' : 'Preview'}</span>} />}
    </Group>
  )
}

/** Your own Anthropic key, instead of Joshu Pro (advanced). */
function OwnKeyGroup() {
  const [own, setOwn] = useState(!!secrets.get('anthropic-api-key'))
  const [key, setKey] = useState('')
  const [busy, setBusy] = useState(false)
  const [status, setStatus] = useState('')
  const save = async () => {
    setBusy(true); setStatus('')
    await window.orbit.setSecret('anthropic-api-key', key.trim())
    setKey('')
    await refreshKeys()
    const t = await window.orbit.claudeTest()
    setStatus(t.message ?? (t.ok ? 'Connected.' : ''))
    setOwn(true)
    if (t.ok && vaultState().state === 'on') syncVault().catch(() => {})
    setBusy(false)
  }
  const test = async () => { setBusy(true); const t = await window.orbit.claudeTest(); setStatus(t.message ?? (t.ok ? 'Connected.' : '')); setBusy(false) }
  const remove = async () => { await window.orbit.setSecret('anthropic-api-key', ''); await refreshKeys(); setOwn(false); setStatus('') }
  return (
    <Group title="Your own Anthropic key (advanced)" footer="Optional: use your own key instead of Joshu's AI. The key stays encrypted on this phone, never in a file.">
      {own ? <>
        <Cell title={<span style={{ fontWeight: 400 }}>Anthropic API key</span>} detail={<span className="ps-good">Saved</span>} />
        <Cell title={<span className="ps-blue" style={{ fontSize: 15 }}>{busy ? 'Testing…' : 'Test connection'}</span>} onClick={busy ? undefined : test} />
        <button className="ps-cell" onClick={remove}><span className="ps-cell-title ps-danger" style={{ fontWeight: 400 }}>Remove key</span></button>
      </> : (
        <div className="ps-cell col">
          <input className="ps-field" type="password" placeholder="sk-ant-…" value={key} onChange={(e) => setKey(e.target.value)} />
          <div className="ps-btnrow" style={{ alignItems: 'center' }}>
            <button className="ps-blue" style={{ fontSize: 13 }} onClick={() => window.orbit.openExternal('https://console.anthropic.com/settings/keys')}>Get a key at console.anthropic.com</button>
            <span className="spacer" />
            <button className="ps-primary" disabled={busy || !key.trim()} onClick={save}>Save</button>
          </div>
        </div>
      )}
      {status && <Cell title={<span className="secondary" style={{ fontSize: 13, fontWeight: 400 }}>{status}</span>} />}
    </Group>
  )
}

// MARK: Notifications

const hours = (from: number, to: number) => Array.from({ length: to - from }, (_, i) => ({ value: from + i, label: `${from + i}:00` }))

function NotifyToggle({ k, title }: { k: NotifySwitch; title: string }) {
  const on: boolean = useNotify(k)
  return <ToggleCell title={title} on={on} onChange={(v) => setNotify(k, v)} />
}

function NotificationsPage() {
  const [allowed, setAllowed] = useState<boolean | null>(null)
  const [asked, setAsked] = useState(false)
  const [chime, setChime] = useState(() => localStorage.getItem('launchSound') !== 'false')
  useEffect(() => { notificationsAllowed().then(setAllowed) }, [])
  const morning = useNotify('notify.morningHour'), habit = useNotify('notify.habitHour'), journal = useNotify('notify.journalHour'), lead = useNotify('notify.eventLead')
  return (
    <>
      {allowed === false && (
        <Group footer={asked ? 'If nothing happened, turn them on in Android Settings › Apps › Joshu › Notifications.' : undefined}>
          <Cell icon={<Bell size={18} />} title={<span style={{ fontWeight: 400 }}>Notifications are off for Joshu.</span>} />
          <Cell onClick={async () => { setAsked(true); setAllowed(await requestNotifications()) }} title={<span className="ps-blue" style={{ fontSize: 15 }}>Allow notifications</span>} />
        </Group>
      )}
      <Group title="Remind me about">
        <NotifyToggle k="notify.tasks" title="Tasks due today and overdue tasks" />
        <NotifyToggle k="notify.events" title="Events about to start" />
        <NotifyToggle k="notify.bills" title="Bills coming up and due today" />
        <NotifyToggle k="notify.weeklyMoney" title="Your week in money, Sunday evening" />
        <NotifyToggle k="notify.habits" title="Habits not done yet, in the evening" />
        <NotifyToggle k="notify.journal" title="Journal check-in at night" />
        <NotifyToggle k="notify.review" title="Weekly review on Sunday evening" />
        <NotifyToggle k="notify.subscriptions" title="Free trials ending and yearly renewals" />
        <NotifyToggle k="notify.evening" title="Evening nudge to plan tomorrow" />
        <NotifyToggle k="notify.trips" title="Trips: packing and flights" />
        <NotifyToggle k="notify.budgets" title="Spending reaching a budget (80% and 100%)" />
        <NotifyToggle k="notify.bigCharges" title="Unusually large charges" />
      </Group>
      <Group title="Times" footer="Joshu schedules your reminders ahead, so they arrive even when it's closed. Opening it keeps them up to date.">
        <PickerCell title="Morning summary" value={morning} options={hours(5, 13)} onChange={(v) => setNotify('notify.morningHour', v)} />
        <PickerCell title="Habit nudge" value={habit} options={hours(16, 23)} onChange={(v) => setNotify('notify.habitHour', v)} />
        <PickerCell title="Journal check-in" value={journal} options={hours(18, 24)} onChange={(v) => setNotify('notify.journalHour', v)} />
        <PickerCell title="Before events" value={lead} options={[5, 10, 15, 30].map((m) => ({ value: m, label: `${m} min` }))} onChange={(v) => setNotify('notify.eventLead', v)} />
      </Group>
      <Group>
        <ToggleCell title="Play a little chime when Joshu opens" on={chime} onChange={(on) => { setChime(on); localStorage.setItem('launchSound', on ? 'true' : 'false') }} />
      </Group>
    </>
  )
}

// MARK: General

function GeneralPage() {
  useStoreVersion()
  const userName = useSetting<string>('userName', '')
  const currency = useSetting<string>('currencyCode', defaultCurrency())
  const budget = useSetting<number>('monthlyBudget', 2000)
  const goal = useSetting<number>('readingGoal', 24)
  const city = useSetting<string>('weatherCity', '')
  return (
    <>
      <Group>
        <TextCell title="Your name" value={userName} placeholder="Your name" onSave={(v) => store.setSetting('userName', v.trim())} />
        <TextCell title="Monthly budget" value={String(budget)} inputMode="decimal" onSave={(v) => store.setSetting('monthlyBudget', Number(v) || 0)} />
        <PickerCell title="Currency" value={currency} options={[...new Set([currency, ...CURRENCIES])].map((c) => ({ value: c, label: c }))} onChange={(v) => store.setSetting('currencyCode', v)} />
        <TextCell title="Weather city" value={city} placeholder="Cairo" onSave={(v) => store.setSetting('weatherCity', v.trim())} />
        <TextCell title="Books per year" value={String(goal)} inputMode="numeric" onSave={(v) => store.setSetting('readingGoal', Math.max(1, Number(v) || 24))} />
      </Group>
      <UpdatesGroup />
      <DeleteAllData />
    </>
  )
}

/** Updates from the latest release (the Mac's Updates panel; the iPhone has none). */
function UpdatesGroup() {
  const [version, setVersion] = useState('')
  const [update, setUpdate] = useState<{ state: string; version?: string; message?: string }>({ state: 'idle' })
  useEffect(() => {
    window.orbit.config().then((c) => setVersion(c.version))
    window.orbit.onUpdate(setUpdate)
  }, [])
  return (
    <Group title="Updates">
      <Cell top icon={<Tile color="var(--lime)"><Download size={15} /></Tile>} title={`Joshu ${version}`}
        sub={update.state === 'checking' ? 'Checking…'
          : update.state === 'none' ? "You're on the latest version."
          : update.state === 'ready' ? `Joshu ${update.version} is out. Download it, then open the file to install over this one (your data stays).`
          : update.state === 'error' ? `Couldn't check: ${update.message}`
          : 'Joshu looks for a new version each time it opens.'}
        trailing={update.state === 'ready'
          ? <button className="ps-primary" onClick={() => window.orbit.installUpdate()}>Download</button>
          : <button className="ps-soft" onClick={() => window.orbit.checkForUpdates()}>Check</button>} />
    </Group>
  )
}

const DATA_KINDS = ['task', 'event', 'habit', 'transaction', 'note', 'book', 'bookCategory', 'bucket', 'readingSession', 'highlight', 'subscription',
  'document', 'focusSession', 'dayPlan', 'trip', 'booking', 'bill', 'account', 'ideaProject', 'idea', 'chat', 'goal']

/** General › Delete all data (DataReset.clearAll): everything in Joshu, here and in your account. */
function DeleteAllData() {
  const [confirming, setConfirming] = useState(false)
  const [done, setDone] = useState(false)
  const clear = () => {
    for (const kind of DATA_KINDS) for (const r of store.list(kind)) store.remove(r.id)
    store.setSetting('assistant.memory', null)
    setConfirming(false); setDone(true)
  }
  return (
    <Group footer={done ? 'Everything was deleted.' : undefined}>
      <Cell top icon={<Tile color="var(--critical)" ink="#fff"><Trash2 size={15} /></Tile>} title="Delete all data"
        sub="Removes everything in Joshu, here and in your account."
        trailing={!confirming && <button className="ps-soft ps-danger" onClick={() => setConfirming(true)}>Delete…</button>} />
      {confirming && (
        <div className="ps-cell col">
          <strong style={{ fontSize: 15 }}>Delete everything in Joshu?</strong>
          <span className="ps-cell-sub">Tasks, events, habits, transactions, notes, books and bucket list stored in Joshu will be removed, including from your Joshu account if you're signed in. Your Google Calendar and Gmail are not touched.</span>
          <button className="ps-primary ps-wide" style={{ background: 'var(--critical)', color: '#fff' }} onClick={clear}>Delete all data</button>
          <button className="ps-soft ps-wide" onClick={() => setConfirming(false)}>Cancel</button>
        </div>
      )}
    </Group>
  )
}

// MARK: Bank texts (Connections › Bank texts)

/** Joshu reads your bank's SMS on this phone and logs each payment (the iPhone needs a Shortcuts automation for this). */
function BankTextsPage() {
  const [, tick] = useState(0)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [extra, setExtra] = useState('')
  useEffect(() => onSmsChange(() => tick((n) => n + 1)), [])
  const on = smsEnabled()
  const chosen = chosenBanks()
  const activity = smsActivity().slice(0, 5)
  const refresh = () => tick((n) => n + 1)

  const toggle = async (want: boolean) => {
    setMessage('')
    if (!want) { disableSms(); return }
    setBusy(true)
    const ok = await enableSms(3)
    setBusy(false)
    if (!ok) setMessage(isNative ? 'Joshu needs permission to read SMS. Allow it when Android asks (or in Android Settings › Apps › Joshu › Permissions).' : 'Works in the Android app.')
  }

  return (
    <>
      <Group footer="Joshu reads new texts from your banks each time you open it. OTP codes and declined payments are skipped. Texts stay on this phone; only what's logged syncs.">
        <ToggleCell icon={<Tile color="var(--lime)"><MessageSquareText size={15} /></Tile>} title="Log payments from bank texts" on={on} disabled={busy} onChange={toggle}
          sub="Card payments, transfers and salary, straight into Money." />
        {on && <Cell onClick={busy ? undefined : async () => { setBusy(true); const n = await checkBankTexts(); setBusy(false); setMessage(n ? `Logged ${n} new payment${n > 1 ? 's' : ''}.` : 'Nothing new.') }}
          title={<span className="ps-blue" style={{ fontSize: 15 }}>{busy ? 'Checking…' : 'Check now'}</span>} />}
        {message && <Cell title={<span className="secondary" style={{ fontSize: 13, fontWeight: 400 }}>{message}</span>} />}
      </Group>
      <Group title="Your banks" footer={chosen.length ? undefined : 'With none picked, Joshu reads texts from all the banks it knows.'}>
        {BANKS.map((b) => (
          <ToggleCell key={b.id} title={b.name} on={chosen.includes(b.id)}
            onChange={(v) => { setChosenBanks(v ? [...chosen, b.id] : chosen.filter((x) => x !== b.id)); refresh() }} />
        ))}
        {extraSenders().map((s) => (
          <Cell key={s} title={<span style={{ fontWeight: 400 }}>{s}</span>}
            trailing={<button className="ps-x" aria-label={`Remove ${s}`} onClick={() => { setExtraSenders(extraSenders().filter((x) => x !== s)); refresh() }}><X size={15} /></button>} />
        ))}
        <label className="ps-cell">
          <input className="ps-input left" placeholder="Another sender name" value={extra} onChange={(e) => setExtra(e.target.value)} />
          <button className="ps-blue" disabled={!extra.trim()} style={{ opacity: extra.trim() ? 1 : 0.4 }}
            onClick={() => { setExtraSenders([...extraSenders(), extra.trim()]); setExtra(''); refresh() }}>Add</button>
        </label>
      </Group>
      {activity.length > 0 && (
        <Group title="Recent">
          {activity.map((a) => (
            <Cell key={a.t + a.text} top title={<span style={{ fontSize: 14 }}>{a.result}</span>}
              sub={<span className="clamp1">{a.sender ? `${a.sender}: ` : ''}{a.text}</span>} />
          ))}
        </Group>
      )}
    </>
  )
}
