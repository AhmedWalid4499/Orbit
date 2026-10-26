// Joshu for Android: the phone layout around the Windows app's screens (bottom tabs like the iPhone's
// PhoneRoot: Today, Tasks, Money, the assistant and More), plus the Android-only pieces.
import { useEffect, useState, ReactNode } from 'react'
import { App as CapApp } from '@capacitor/app'
import { Sun, ListChecks, CreditCard, Sparkles, LayoutGrid, ChevronLeft, Settings as Gear } from 'lucide-react'
import * as cloud from '@/lib/cloud'
import { store, useSetting } from '@/lib/store'
import { demoRecords, demoProfileCard } from '@/lib/demo'
import { syncVault } from '@/lib/vault'
import { startEmailExpensesTimer } from '@/lib/emailExpenses'
import { onOpenAsk } from '@/lib/askBus'
import { useAssistantName } from '@/lib/ai'
import { ReadingTimerPill, FinishedReading } from '@/components/ReadingTimer'
import { FocusPill, FocusStartSheet, FocusDoneDialog } from '@/components/Focus'
import Splash from '@/components/Splash'
import { PlanTomorrowSheet } from '@/screens/PlanTomorrow'
import { useProfilePhoto } from '@/lib/profileCard'
import SignIn from '@/screens/SignIn'
import Today from '@/screens/Today'
import CalendarScreen from '@/screens/Calendar'
import Tasks from '@/screens/Tasks'
import Habits from '@/screens/Habits'
import Bucket from '@/screens/Bucket'
import Money from '@/screens/Money'
import Notes from '@/screens/Notes'
import Reading from '@/screens/Reading'
import Documents from '@/screens/Documents'
import Review from '@/screens/Review'
import MyCard from '@/screens/MyCard'
import type { Tab as SharedTab, Nav } from '@/App'
import { isNative } from './native'
import { checkForUpdates } from './bridge'
import { checkBankTexts } from './sms'
import { scheduleReminders } from './reminders'
import Assistant from './screens/Assistant'
import More, { MoreTab, MORE_TITLES } from './screens/More'
import Settings from './screens/Settings'
import Ideas from './screens/Ideas'
import Goals from './screens/Goals'
import GitHub from './screens/GitHub'
import Jobs from './screens/Jobs'
import Insights from './screens/Insights'
import Bills from './screens/Bills'

const DEMO = new URLSearchParams(location.search).has('demo')

type Main = 'today' | 'tasks' | 'money' | 'assistant' | 'more'

export default function App() {
  const [ready, setReady] = useState(false)
  const [signedIn, setSignedIn] = useState(!!cloud.getSession())
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

  useEffect(() => {
    if (!ready || DEMO) return
    if (signedIn) {
      store.start().then(() => syncVault()).then(() => { startEmailExpensesTimer(); checkBankTexts(); scheduleReminders() })
      if (isNative) checkForUpdates(true)
    } else store.stop()
  }, [ready, signedIn])

  // Coming back to the app: sync, pick up new bank texts, refresh reminders.
  useEffect(() => {
    if (!isNative || DEMO) return
    const h = CapApp.addListener('resume', () => {
      if (!cloud.getSession()) return
      store.sync().then(() => { checkBankTexts(); scheduleReminders() })
    })
    return () => { h.then((x) => x.remove()) }
  }, [])

  return (
    <>
      {ready && (signedIn ? <Shell /> : <div className="signin-wrap"><SignIn platform="android" /></div>)}
      {splash && <Splash onDone={() => setSplash(false)} />}
    </>
  )
}

function Shell() {
  const [main, setMain] = useState<Main>('today')
  const [page, setPage] = useState<MoreTab | null>(null)
  const [settings, setSettings] = useState(false)
  const [review, setReview] = useState(false)
  const [plan, setPlan] = useState(false)
  const [card, setCard] = useState(false)
  const [journalRequest, setJournalRequest] = useState(0)
  const [seed, setSeed] = useState<string | undefined>()
  const assistant = useAssistantName()
  const userName = useSetting<string>('userName', '')
  const photo = useProfilePhoto()
  const initials = userName.split(' ').slice(0, 2).map((w) => w[0]).join('').toUpperCase() || 'Me'

  const open = (t: SharedTab | MoreTab) => {
    if (t === 'today' || t === 'tasks' || t === 'money') { setPage(null); setMain(t) } else { setMain('more'); setPage(t as MoreTab) }
  }
  const nav: Nav = { go: open, openJournal: () => { setJournalRequest((n) => n + 1); open('notes') }, openReview: () => setReview(true), openPlan: () => setPlan(true) }
  useEffect(() => onOpenAsk((s) => { setSeed(s); setMain('assistant') }), [])

  // Android back button: close the open sheet or page before leaving the app.
  useEffect(() => {
    if (!isNative) return
    const h = CapApp.addListener('backButton', () => {
      if (settings) setSettings(false)
      else if (review) setReview(false)
      else if (plan) setPlan(false)
      else if (card) setCard(false)
      else if (document.querySelector('.backdrop')) document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))
      else if (page) setPage(null)
      else if (main !== 'today') setMain('today')
      else CapApp.minimizeApp()
    })
    return () => { h.then((x) => x.remove()) }
  }, [settings, review, plan, card, page, main])

  const title = main === 'more' && page ? MORE_TITLES[page] : null

  return (
    <div className="phone">
      <header className="phone-bar">
        {title
          ? <button className="row back" onClick={() => setPage(null)}><ChevronLeft size={20} /> More</button>
          : <div className="logo">joshu<i /></div>}
        <span className="spacer" />
        <FocusPill />
        <ReadingTimerPill onOpen={() => open('reading')} />
        <button className="icon-btn" aria-label="Settings" onClick={() => setSettings(true)}><Gear size={17} /></button>
        <button className="avatar" aria-label="My card" onClick={() => setCard(true)}
          style={photo ? { background: `center / cover url(${photo})` } : undefined}>{photo ? '' : initials}</button>
      </header>
      <main className="phone-main">
        {main === 'today' && <Today nav={nav} />}
        {main === 'tasks' && <Tasks />}
        {main === 'money' && <Money />}
        {main === 'assistant' && <Assistant seed={seed} onSeedUsed={() => setSeed(undefined)} />}
        {main === 'more' && !page && <More onOpen={(t) => setPage(t)} onSettings={() => setSettings(true)} onCard={() => setCard(true)} onReview={() => setReview(true)} onPlan={() => setPlan(true)} />}
        {main === 'more' && page === 'calendar' && <CalendarScreen />}
        {main === 'more' && page === 'habits' && <Habits />}
        {main === 'more' && page === 'bucket' && <Bucket />}
        {main === 'more' && page === 'notes' && <Notes openJournalRequest={journalRequest} />}
        {main === 'more' && page === 'reading' && <Reading />}
        {main === 'more' && page === 'documents' && <Documents />}
        {main === 'more' && page === 'ideas' && <Ideas />}
        {main === 'more' && page === 'goals' && <Goals />}
        {main === 'more' && page === 'bills' && <Bills />}
        {main === 'more' && page === 'github' && <GitHub />}
        {main === 'more' && page === 'jobs' && <Jobs />}
        {main === 'more' && page === 'insights' && <Insights />}
      </main>
      <nav className="tabbar">
        <TabButton on={main === 'today'} icon={<Sun size={21} />} label="Today" onClick={() => { setMain('today'); setPage(null) }} />
        <TabButton on={main === 'tasks'} icon={<ListChecks size={21} />} label="Tasks" onClick={() => setMain('tasks')} />
        <TabButton on={main === 'money'} icon={<CreditCard size={21} />} label="Money" onClick={() => setMain('money')} />
        <TabButton on={main === 'assistant'} icon={<Sparkles size={21} />} label={assistant} onClick={() => setMain('assistant')} />
        <TabButton on={main === 'more'} icon={<LayoutGrid size={21} />} label="More" onClick={() => { if (main === 'more') setPage(null); setMain('more') }} />
      </nav>
      <Settings open={settings} onClose={() => setSettings(false)} />
      <Review open={review} onClose={() => setReview(false)} />
      <MyCard open={card} onClose={() => setCard(false)} />
      <FinishedReading />
      <PlanTomorrowSheet open={plan} onClose={() => setPlan(false)} />
      <FocusStartSheet />
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
