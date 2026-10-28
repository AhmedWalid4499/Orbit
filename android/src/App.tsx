// Joshu for Android: the phone layout around the Windows app's screens (bottom tabs like the iPhone's
// PhoneRoot: Today, Tasks, Money, the assistant and More), plus the Android-only pieces.
import { useEffect, useState, ReactNode } from 'react'
import { App as CapApp } from '@capacitor/app'
import { Sun, ListChecks, CreditCard, LayoutGrid, ChevronLeft, Settings as Gear, Plus, Sparkles, IdCard, TrendingUp, Search as SearchIcon } from 'lucide-react'
import * as cloud from '@/lib/cloud'
import { store, useSetting } from '@/lib/store'
import { demoRecords, demoProfileCard } from '@/lib/demo'
import { syncVault } from '@/lib/vault'
import { startEmailExpensesTimer } from '@/lib/emailExpenses'
import { onOpenAsk } from '@/lib/askBus'
import { useAssistantName } from '@/lib/ai'
import { ReadingTimerPill, FinishedReading } from '@/components/ReadingTimer'
import { FocusPill, FocusStartSheet, FocusDoneDialog } from '@/components/Focus'
import Splash from './components/Splash'
import { Orb } from './components/Orb'
import SearchSheet from './components/Search'
import { Modal } from '@/components/ui'
import { QuickAdd } from '@/screens/Today'
import { useProfilePhoto } from '@/lib/profileCard'
import SignIn from '@/screens/SignIn'
import Today from './screens/Today'
import PhoneTasks from './screens/PhoneTasks'
import Welcome, { usesJoshuWithoutAccount, setUsesJoshuWithoutAccount } from './screens/Welcome'
import Tour, { tourSeen } from './screens/Tour'
import SetupFlow, { setupNeeded, checkFreshAccount, onOnboardingChange } from './screens/SetupFlow'
import CaptureSheet from './components/CaptureSheet'
import { ProWelcomeHost } from './components/ProWelcome'
import PhoneReading from './screens/PhoneReading'
import PhoneDocuments from './screens/PhoneDocuments'
import type { Tab as SharedTab, Nav } from '@/App'
import { isNative } from './native'
import { checkForUpdates } from './bridge'
import { checkBankTexts } from './sms'
import { scheduleReminders } from './reminders'
import { refreshGoogleCalendar } from './gcal'
import { refreshPro } from './pro'
import { checkSpendingAlerts } from './spendingAlerts'
import { onVoiceStart, startWake } from './voice'
import VoiceOrb from './components/VoiceOrb'
import { LocalNotifications } from '@capacitor/local-notifications'
import Assistant from './screens/Assistant'
import { MoreTab } from './screens/More'
import PhoneMore from './screens/PhoneMore'
import PhoneCard from './screens/PhoneCard'
import PhoneReview from './screens/PhoneReview'
import PhonePlan from './screens/PhonePlan'
import PhoneCalendar from './screens/PhoneCalendar'
import PhoneHabits from './screens/PhoneHabits'
import PhoneNotes from './screens/PhoneNotes'
import PhoneBucket from './screens/PhoneBucket'
import Settings from './screens/Settings'
import Ideas from './screens/Ideas'
import Goals from './screens/Goals'
import GitHub from './screens/GitHub'
import Jobs from './screens/Jobs'
import Insights from './screens/Insights'
import Bills from './screens/Bills'
import PhoneMoney from './screens/PhoneMoney'
import Accounts from './screens/Accounts'

const DEMO = new URLSearchParams(location.search).has('demo')

type Main = 'today' | 'tasks' | 'money' | 'assistant' | 'more'

export default function App() {
  const [ready, setReady] = useState(false)
  const [signedIn, setSignedIn] = useState(!!cloud.getSession())
  // Joshu without an account (v1.40.1): data stays on this phone until you sign in.
  const [local, setLocal] = useState(usesJoshuWithoutAccount())
  // First launch: the tour, then (for a brand-new account) the step-by-step setup, as on the iPhone.
  const [tour, setTour] = useState(() => !DEMO && !tourSeen())
  const [setup, setSetup] = useState(() => !DEMO && setupNeeded())
  const [splash, setSplash] = useState(() => !(DEMO && new URLSearchParams(location.search).has('nosplash')))

  useEffect(() => {
    if (DEMO) {
      store.startDemo(demoRecords(), { userName: 'Yuto', monthlyBudget: 20000, currencyCode: 'EGP', readingGoal: 24, profileCard: demoProfileCard, assistantName: 'Joshu' })
        .then(() => { setReady(true); setSignedIn(true) })
      return
    }
    window.orbit.config().then((c) => { cloud.configure(c.supabase); setReady(true) })
    window.orbit.onAuthCallback((url) => { cloud.handleCallback(url) })
    return cloud.onSessionChange(() => setSignedIn(!!cloud.getSession()))
  }, [])

  useEffect(() => onOnboardingChange(() => { setTour(!DEMO && !tourSeen()); setSetup(!DEMO && setupNeeded()) }), [])

  useEffect(() => {
    if (!ready || DEMO) return
    if (signedIn) {
      setUsesJoshuWithoutAccount(false); setLocal(false)
      const fresh = checkFreshAccount(cloud.getSession()!.userID)
      store.start().then(() => { fresh() }).then(() => store.adoptLocal()).then(() => refreshPro()).then(() => syncVault()).then(() => { startEmailExpensesTimer(); checkBankTexts().then(() => checkSpendingAlerts()); scheduleReminders(); refreshGoogleCalendar() })
      if (isNative) checkForUpdates(true)
    } else if (local) store.startLocal()
    else store.stop()
  }, [ready, signedIn, local])

  // Android back button in the tour and setup goes back a page (they listen for Escape).
  useEffect(() => {
    if (!isNative || !(tour || setup)) return
    const h = CapApp.addListener('backButton', () => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })))
    return () => { h.then((x) => x.remove()) }
  }, [tour, setup])

  // Coming back to the app: sync, pick up new bank texts, refresh reminders.
  useEffect(() => {
    if (!isNative || DEMO) return
    const h = CapApp.addListener('resume', () => {
      if (!cloud.getSession()) return
      refreshPro(); store.sync().then(() => { checkBankTexts().then(() => checkSpendingAlerts()); scheduleReminders(); refreshGoogleCalendar() })
    })
    return () => { h.then((x) => x.remove()) }
  }, [])

  return (
    <>
      {ready && (tour ? <Tour onDone={() => setTour(false)} />
        : signedIn || local
          ? (signedIn && setup
            ? <SetupFlow onDone={() => setSetup(false)} onSeePro={() => { localStorage.setItem('open.pro', '1'); setSetup(false) }} />
            : <Shell onSignIn={() => { setUsesJoshuWithoutAccount(false); setLocal(false) }} />)
          : <Welcome onCarryOn={() => setLocal(true)} />)}
      {splash && <Splash onDone={() => setSplash(false)} />}
    </>
  )
}

function Shell({ onSignIn }: { onSignIn: () => void }) {
  const [main, setMain] = useState<Main>('today')
  const [page, setPage] = useState<MoreTab | null>(null)
  const [settings, setSettings] = useState(false)
  const [review, setReview] = useState(false)
  const [plan, setPlan] = useState(false)
  const [card, setCard] = useState(false)
  const [journalRequest, setJournalRequest] = useState(0)
  const [seed, setSeed] = useState<string | undefined>()
  const [adding, setAdding] = useState(false)
  const [searching, setSearching] = useState(false)
  const assistant = useAssistantName()
  const userName = useSetting<string>('userName', '')
  const photo = useProfilePhoto()
  const initials = userName.split(' ').slice(0, 2).map((w) => w[0]).join('').toUpperCase() || 'Me'

  const open = (t: SharedTab | MoreTab) => {
    if (t === 'today' || t === 'tasks' || t === 'money') { setPage(null); setMain(t) } else { setMain('more'); setPage(t as MoreTab) }
  }
  const nav: Nav = { go: open, openJournal: () => { setJournalRequest((n) => n + 1); open('notes') }, openReview: () => setReview(true), openPlan: () => setPlan(true) }
  useEffect(() => onOpenAsk((s) => { setSeed(s); setMain('assistant') }), [])
  // "See Joshu Pro" at the end of setup lands in Settings.
  useEffect(() => { if (localStorage.getItem('open.pro')) { localStorage.removeItem('open.pro'); setSettings(true) } }, [])
  // "Hey Joshu": the assistant answers, so it's opened under the orb.
  useEffect(() => { onVoiceStart(() => { setPage(null); setMain('assistant') }); startWake() }, [])
  // Tapping a notification opens its section (spending alerts → Money).
  useEffect(() => {
    if (!isNative) return
    const h = LocalNotifications.addListener('localNotificationActionPerformed', (a) => {
      const route = a.notification.extra?.route
      if (route === 'money' || route === 'tasks' || route === 'today') { setPage(null); setMain(route) }
      else if (route === 'plan') setPlan(true)
      else if (route === 'review') setReview(true)
      else if (route === 'journal') nav.openJournal()
      else if (route === 'calendar' || route === 'habits' || route === 'bucket') open(route)
    })
    return () => { h.then((x) => x.remove()) }
  }, [])

  // Android back button: close the open sheet or page before leaving the app.
  useEffect(() => {
    if (!isNative) return
    const h = CapApp.addListener('backButton', () => {
      if (settings) setSettings(false)
      else if (adding) setAdding(false)
      else if (searching) setSearching(false)
      else if (review) setReview(false)
      else if (plan) setPlan(false)
      else if (card) setCard(false)
      else if (document.querySelector('.backdrop')) document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))
      else if (page) setPage(null)
      else if (main !== 'today') setMain('today')
      else CapApp.minimizeApp()
    })
    return () => { h.then((x) => x.remove()) }
  }, [settings, adding, searching, review, plan, card, page, main])

  return (
    <div className="phone">
      {/* The iPhone's bar: the large title (or back on More pages) and one capsule with quick add, the orb and your
          avatar menu; running timers in a strip below. The assistant has its own header. */}
      {main !== 'assistant' && <header className="phone-bar">
        {page
          ? <button className="bar-back" aria-label="Back to More" onClick={() => setPage(null)}><ChevronLeft size={22} /></button>
          : <h1 className="bar-title">{main === 'today' ? 'Today' : main === 'tasks' ? 'Tasks' : main === 'money' ? 'Money' : 'More'}</h1>}
        <span className="spacer" />
        <div className="bar-tools">
          <button aria-label="Quick add" onClick={() => setAdding(true)}><Plus size={22} /></button>
          <button aria-label={assistant} onClick={() => setMain('assistant')}><Orb size={30} /></button>
          <ProfileMenu initials={initials} photo={photo} onCard={() => setCard(true)} onReview={() => setReview(true)}
            onSearch={() => setSearching(true)} onSettings={() => setSettings(true)} />
        </div>
      </header>}
      <div className="timer-strip"><FocusPill /><ReadingTimerPill onOpen={() => open('reading')} /></div>
      <main className="phone-main">
        {main === 'today' && <Today nav={nav} />}
        {main === 'tasks' && <PhoneTasks />}
        {main === 'money' && <PhoneMoney />}
        {main === 'assistant' && <Assistant seed={seed} onSeedUsed={() => setSeed(undefined)} />}
        {main === 'more' && !page && <PhoneMore onOpen={(t) => setPage(t)} onCard={() => setCard(true)} onReview={() => setReview(true)} onPlan={() => setPlan(true)} onSearch={() => setSearching(true)} onSettings={() => setSettings(true)} />}
        {main === 'more' && page === 'calendar' && <PhoneCalendar />}
        {main === 'more' && page === 'habits' && <PhoneHabits />}
        {main === 'more' && page === 'bucket' && <PhoneBucket />}
        {main === 'more' && page === 'notes' && <PhoneNotes openJournalRequest={journalRequest} />}
        {main === 'more' && page === 'reading' && <PhoneReading />}
        {main === 'more' && page === 'documents' && <PhoneDocuments />}
        {main === 'more' && page === 'ideas' && <Ideas />}
        {main === 'more' && page === 'goals' && <Goals />}
        {main === 'more' && page === 'bills' && <Bills />}
        {main === 'more' && page === 'accounts' && <Accounts />}
        {main === 'more' && page === 'github' && <GitHub />}
        {main === 'more' && page === 'jobs' && <Jobs />}
        {main === 'more' && page === 'insights' && <Insights />}
      </main>
      <nav className="tabbar">
        <TabButton on={main === 'today'} icon={<Sun size={24} strokeWidth={2.4} />} label="Today" onClick={() => { setMain('today'); setPage(null) }} />
        <TabButton on={main === 'tasks'} icon={<ListChecks size={24} strokeWidth={2.2} />} label="Tasks" onClick={() => setMain('tasks')} />
        <TabButton on={main === 'money'} icon={<CreditCard size={24} fill="currentColor" stroke="var(--canvas)" strokeWidth={1.6} />} label="Money" onClick={() => setMain('money')} />
        <TabButton on={main === 'assistant'} icon={<Sparkles size={24} fill="currentColor" strokeWidth={1.2} />} label={assistant} onClick={() => setMain('assistant')} />
        <TabButton on={main === 'more'} icon={<LayoutGrid size={24} fill="currentColor" strokeWidth={1.4} />} label="More" onClick={() => { if (main === 'more') setPage(null); setMain('more') }} />
      </nav>
      <Settings open={settings} onClose={() => setSettings(false)} onSignIn={() => { setSettings(false); onSignIn() }} />
      <SearchSheet open={searching} onClose={() => setSearching(false)} onGo={(d) => open(d)} />
      <CaptureSheet open={adding} onClose={() => setAdding(false)} />
      <PhoneReview open={review} onClose={() => setReview(false)} onGetPro={() => { setReview(false); setSettings(true) }} />
      <PhoneCard open={card} onClose={() => setCard(false)} />
      <FinishedReading />
      <PhonePlan open={plan} onClose={() => setPlan(false)} />
      <FocusStartSheet />
      <VoiceOrb />
      <ProWelcomeHost onOpenAssistant={() => { setPage(null); setMain('assistant') }} />
      <FocusDoneDialog />
    </div>
  )
}

function TabButton({ on, icon, label, onClick }: { on: boolean; icon: ReactNode; label: string; onClick: () => void }) {
  return (
    <button className={on ? 'on' : ''} onClick={onClick}>
      <span className="tab-icon">{icon}</span>
      <span className="clamp1">{label}</span>
    </button>
  )
}

/** Your avatar: My Card, Week in review, Search and Settings, like the iPhone's profile menu. */
function ProfileMenu({ initials, photo, onCard, onReview, onSearch, onSettings }: {
  initials: string; photo: string | null; onCard: () => void; onReview: () => void; onSearch: () => void; onSettings: () => void
}) {
  const [open, setOpen] = useState(false)
  useEffect(() => {
    if (!open) return
    const close = () => setOpen(false)
    window.addEventListener('pointerdown', close)
    return () => window.removeEventListener('pointerdown', close)
  }, [open])
  const item = (icon: ReactNode, label: string, fn: () => void) => (
    <button onPointerDown={(e) => e.stopPropagation()} onClick={() => { setOpen(false); fn() }}>{icon}{label}</button>
  )
  return (
    <div style={{ position: 'relative' }}>
      <button className="avatar" aria-label="Profile and settings" onPointerDown={(e) => e.stopPropagation()} onClick={() => setOpen(!open)}
        style={photo ? { background: `center / cover url(${photo})` } : undefined}>{photo ? '' : initials}</button>
      {open && (
        <div className="pop-menu" onPointerDown={(e) => e.stopPropagation()}>
          {item(<IdCard size={16} />, 'My Card', onCard)}
          {item(<TrendingUp size={16} />, 'Week in review', onReview)}
          {item(<SearchIcon size={16} />, 'Search', onSearch)}
          {item(<Gear size={16} />, 'Settings', onSettings)}
        </div>
      )}
    </div>
  )
}
