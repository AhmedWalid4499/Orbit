import { useEffect, useState, ReactNode } from 'react'
import { Sun, Calendar, ListChecks, Flame, Mountain, CreditCard, BookOpenText, Library, Settings as Gear } from 'lucide-react'
import * as cloud from '@/lib/cloud'
import { store, useSetting } from '@/lib/store'
import { demoRecords } from '@/lib/demo'
import { syncVault } from '@/lib/vault'

/** Open with ?demo to preview with sample data (used for screenshots; nothing is synced). */
const DEMO = new URLSearchParams(location.search).has('demo')
import SignIn from '@/screens/SignIn'
import SettingsModal from '@/screens/Settings'
import Today from '@/screens/Today'
import CalendarScreen from '@/screens/Calendar'
import Tasks from '@/screens/Tasks'
import Habits from '@/screens/Habits'
import Bucket from '@/screens/Bucket'
import Money from '@/screens/Money'
import Notes from '@/screens/Notes'
import Reading from '@/screens/Reading'

export type Tab = 'today' | 'calendar' | 'tasks' | 'habits' | 'bucket' | 'money' | 'notes' | 'reading'

/** Lets any screen switch tabs (e.g. "Open calendar" on Today). */
export interface Nav { go: (t: Tab) => void; openJournal: () => void }

export default function App() {
  const [ready, setReady] = useState(false)
  const [signedIn, setSignedIn] = useState(!!cloud.getSession())
  const [platform, setPlatform] = useState('win32')

  useEffect(() => {
    if (DEMO) {
      store.startDemo(demoRecords(), { userName: 'Yuto', monthlyBudget: 2000, currencyCode: 'EGP', readingGoal: 24 }).then(() => { setReady(true); setSignedIn(true) })
      return
    }
    window.orbit.config().then((c) => {
      cloud.configure(c.supabase)
      setPlatform(c.platform)
      setReady(true)
    })
    window.orbit.onAuthCallback((url) => { cloud.handleCallback(url) })
    return cloud.onSessionChange(() => setSignedIn(!!cloud.getSession()))
  }, [])

  useEffect(() => {
    if (!ready || DEMO) return
    if (signedIn) store.start().then(() => syncVault()) // unlock keys synced from the Mac, if the passphrase is saved here
    else store.stop()
  }, [ready, signedIn])

  if (!ready) return null
  return signedIn ? <Shell platform={platform} /> : <SignIn platform={platform} />
}

const TABS: { id: Tab; title: string; icon: ReactNode }[][] = [
  [{ id: 'today', title: 'Today', icon: <Sun size={16} /> }],
  [
    { id: 'calendar', title: 'Calendar', icon: <Calendar size={16} /> },
    { id: 'tasks', title: 'Tasks', icon: <ListChecks size={16} /> },
    { id: 'habits', title: 'Habits', icon: <Flame size={16} /> },
    { id: 'bucket', title: 'Bucket list', icon: <Mountain size={16} /> },
  ],
  [
    { id: 'money', title: 'Money', icon: <CreditCard size={16} /> },
    { id: 'notes', title: 'Journal & Notes', icon: <BookOpenText size={16} /> },
    { id: 'reading', title: 'Reading', icon: <Library size={16} /> },
  ],
]

function Shell({ platform }: { platform: string }) {
  const [tab, setTab] = useState<Tab>('today')
  const [settings, setSettings] = useState(false)
  const [journalRequest, setJournalRequest] = useState(0)
  const userName = useSetting<string>('userName', '')
  const first = userName.split(' ')[0]
  const initials = userName.split(' ').slice(0, 2).map((w) => w[0]).join('').toUpperCase() || 'Me'
  const nav: Nav = { go: setTab, openJournal: () => { setJournalRequest((n) => n + 1); setTab('notes') } }

  // Ctrl/Cmd + 1…8 switches tabs, like ⌘1…⌘9 on the Mac.
  useEffect(() => {
    const flat = TABS.flat()
    const onKey = (e: KeyboardEvent) => {
      if (!(e.ctrlKey || e.metaKey)) return
      const n = Number(e.key)
      if (n >= 1 && n <= flat.length) { setTab(flat[n - 1].id); e.preventDefault() }
      if (e.key === ',') { setSettings(true); e.preventDefault() }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <div className="topbar" style={{ paddingLeft: platform === 'darwin' ? 96 : 32, paddingRight: platform === 'win32' ? 150 : 32 }}>
        <div className="logo">orbit<i /></div>
        <nav className="dock">
          {TABS.map((group, gi) => (
            <span key={gi} className="row" style={{ gap: 4 }}>
              {gi > 0 && <span className="sep" />}
              {group.map((t) => (
                <button key={t.id} className={tab === t.id ? 'on' : ''} onClick={() => setTab(t.id)}
                  title={t.id === 'reading' && first ? `${first}'s Reading` : t.title}>
                  {t.icon}
                  {tab === t.id && <span>{t.id === 'reading' && first ? `${first}'s Reading` : t.title}</span>}
                </button>
              ))}
            </span>
          ))}
        </nav>
        <span className="spacer" />
        <div className="row">
          <button className="icon-btn" title="Settings (Ctrl+,)" onClick={() => setSettings(true)}><Gear size={17} /></button>
          <button className="avatar" title="Account & settings" onClick={() => setSettings(true)}>{initials}</button>
        </div>
      </div>
      <main style={{ flex: 1, minHeight: 0 }}>
        {tab === 'today' && <Today nav={nav} />}
        {tab === 'calendar' && <CalendarScreen />}
        {tab === 'tasks' && <Tasks />}
        {tab === 'habits' && <Habits />}
        {tab === 'bucket' && <Bucket />}
        {tab === 'money' && <Money />}
        {tab === 'notes' && <Notes openJournalRequest={journalRequest} />}
        {tab === 'reading' && <Reading />}
      </main>
      <SettingsModal open={settings} onClose={() => setSettings(false)} />
    </div>
  )
}
