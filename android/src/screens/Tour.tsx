// The welcome tour, as on the iPhone (TourView.swift): eight pages, each showing a real screen of the app (sample data)
// on a phone with the laptop beside it, cards popping out around them, and drifting blobs of the page's colours behind.
// Shown the first time Joshu opens (and again for a brand-new account); Next / swipe to move on, Skip to finish.
import { useEffect, useRef, useState, ReactNode } from 'react'
import {
  ChevronLeft, ArrowRight, ArrowRightCircle, Sun, RefreshCw, Lock, CheckCircle2, Flame, Calendar, Sparkles, Sunrise, Lightbulb, CreditCard,
  BookOpen, MessageSquare, UtensilsCrossed, FileSearch, Mic, MapPin, CloudSun, Bell, Moon, AlarmClock, Mail, Receipt, BellRing, MessageCircle,
  AlertTriangle, Timer, Library, Download, Highlighter, Mountain, Map, Landmark, MonitorSmartphone, Zap, Hand,
} from 'lucide-react'
import { useAssistantName } from '@/lib/ai'
import '../onboarding.css'

const SEEN_KEY = 'tourSeen'
/** Whether the tour has been seen on this phone (cleared again for a brand-new account, see SetupFlow.checkFreshAccount). */
export const tourSeen = (): boolean => { try { return localStorage.getItem(SEEN_KEY) === '1' } catch { return true } }
export function setTourSeen(seen: boolean): void {
  try { if (seen) localStorage.setItem(SEEN_KEY, '1'); else localStorage.removeItem(SEEN_KEY) } catch { /* private storage */ }
}

interface Sticker { icon: ReactNode; text: string; color: string; x: number; y: number }
interface Page { eyebrow: string; title: string; points: [ReactNode, string][]; image: string; color: string; accent: string; stickers: Sticker[] }

const I = 12, S = 2.6
const pages = (ai: string): Page[] => [
  { eyebrow: 'Welcome to Joshu', title: 'Your whole life, in one calm place', image: 'today', color: 'var(--lime)', accent: 'var(--cyan)',
    points: [[<Sun size={I} strokeWidth={S} />, 'Events, tasks, habits, money and reading on one screen'],
      [<RefreshCw size={I} strokeWidth={S} />, 'Always in sync between your phone and your other devices'],
      [<Lock size={I} strokeWidth={S} />, 'Your data and keys stay yours']],
    stickers: [{ icon: <CheckCircle2 size={I} strokeWidth={S} />, text: '3 of 5 done', color: 'var(--lime)', x: -0.08, y: 0.22 },
      { icon: <Flame size={I} strokeWidth={S} />, text: '9-day streak', color: 'var(--orange)', x: 1.06, y: 0.42 },
      { icon: <Calendar size={I} strokeWidth={S} />, text: 'Gym · 7:00 PM', color: 'var(--cyan)', x: -0.04, y: 0.78 }] },
  { eyebrow: 'Your day', title: 'An AI summary that keeps up with you', image: 'day', color: 'var(--orange)', accent: 'var(--pink)',
    points: [[<Sparkles size={I} strokeWidth={S} />, 'A morning brief with what matters today'],
      [<Sunrise size={I} strokeWidth={S} />, '“Your day” rewrites itself as you spend, read and tick things off'],
      [<Lightbulb size={I} strokeWidth={S} />, 'A gentle nudge for the next few hours']],
    stickers: [{ icon: <CreditCard size={I} strokeWidth={S} />, text: 'EGP 350 today', color: 'var(--peach)', x: 1.05, y: 0.25 },
      { icon: <BookOpen size={I} strokeWidth={S} />, text: '42% · Atomic Habits', color: 'var(--purple)', x: -0.06, y: 0.62 }] },
  { eyebrow: `Meet ${ai}`, title: 'An assistant that actually does things', image: 'assistant', color: 'var(--pink)', accent: 'var(--purple)',
    points: [[<MessageSquare size={I} strokeWidth={S} />, 'Chat or talk: it adds tasks, events, notes and expenses'],
      [<UtensilsCrossed size={I} strokeWidth={S} />, '“I\'m hungry”: places nearby, with prices and reviews'],
      [<FileSearch size={I} strokeWidth={S} />, 'What to wear, quick maths, and reviews of your documents']],
    stickers: [{ icon: <Mic size={I} strokeWidth={S} />, text: '“Move the gym to 8”', color: 'var(--lime)', x: -0.08, y: 0.2 },
      { icon: <MapPin size={I} strokeWidth={S} />, text: 'Zooba · 2 min away', color: 'var(--mint)', x: 1.06, y: 0.55 },
      { icon: <CloudSun size={I} strokeWidth={S} />, text: 'T-shirt + light jacket', color: 'var(--cyan)', x: -0.05, y: 0.85 }] },
  { eyebrow: 'Plan', title: 'Tasks, calendar and reminders that find you', image: 'calendar', color: 'var(--cyan)', accent: 'var(--lime)',
    points: [[<Calendar size={I} strokeWidth={S} />, 'Your Google calendars next to your tasks'],
      [<Bell size={I} strokeWidth={S} />, 'Reminders for tasks, events and bills, right on time'],
      [<Moon size={I} strokeWidth={S} />, 'Plan tomorrow in a minute each evening']],
    stickers: [{ icon: <Bell size={I} strokeWidth={S} />, text: 'Pay rent · tomorrow', color: 'var(--lime)', x: -0.08, y: 0.3 },
      { icon: <AlarmClock size={I} strokeWidth={S} />, text: 'Call mom · 6:00 PM', color: 'var(--peach)', x: 1.05, y: 0.7 }] },
  { eyebrow: 'Money', title: 'Every pound, logged for you', image: 'money', color: 'var(--peach)', accent: 'var(--orange)',
    points: [[<Mail size={I} strokeWidth={S} />, 'Receipts from email and bank texts land in Money by themselves'],
      [<Receipt size={I} strokeWidth={S} />, 'Bills and subscriptions, with a reminder before they\'re due'],
      [<BellRing size={I} strokeWidth={S} />, 'Budgets per category, with alerts before you overspend']],
    stickers: [{ icon: <MessageCircle size={I} strokeWidth={S} />, text: 'CIB · EGP 220 logged', color: 'var(--cyan)', x: -0.08, y: 0.25 },
      { icon: <AlertTriangle size={I} strokeWidth={S} />, text: '80% of Food budget', color: 'var(--orange)', x: 1.05, y: 0.48 },
      { icon: <CreditCard size={I} strokeWidth={S} />, text: 'Card · Starbucks', color: 'var(--lime)', x: -0.04, y: 0.8 }] },
  { eyebrow: 'Reading', title: 'Your library, reading time and streaks', image: 'reading', color: 'var(--purple)', accent: 'var(--pink)',
    points: [[<BookOpen size={I} strokeWidth={S} />, 'Currently reading, with progress and a timer'],
      [<Download size={I} strokeWidth={S} />, 'From Goodreads, Apple Books and Kindle'],
      [<Highlighter size={I} strokeWidth={S} />, 'Your highlights, all in one place']],
    stickers: [{ icon: <Timer size={I} strokeWidth={S} />, text: '15 min today', color: 'var(--orange)', x: 1.05, y: 0.3 },
      { icon: <Library size={I} strokeWidth={S} />, text: '3 of 24 this year', color: 'var(--pink)', x: -0.06, y: 0.7 }] },
  { eyebrow: 'Dreams and places', title: 'A bucket list, and a map of places to go', image: 'goto', color: 'var(--mint)', accent: 'var(--cyan)',
    points: [[<Mountain size={I} strokeWidth={S} />, 'Dreams you want to make happen, with trips around them'],
      [<MapPin size={I} strokeWidth={S} />, 'Save restaurants, shops and museums to Go to'],
      [<Map size={I} strokeWidth={S} />, 'Saved once, with you on every device']],
    stickers: [{ icon: <UtensilsCrossed size={I} strokeWidth={S} />, text: 'Zooba · Food', color: 'var(--orange)', x: -0.08, y: 0.35 },
      { icon: <Landmark size={I} strokeWidth={S} />, text: 'Grand Egyptian Museum', color: 'var(--cyan)', x: 1.06, y: 0.62 }] },
  { eyebrow: 'Everywhere', title: 'On your phone and computer, always in sync', image: 'insights', color: 'var(--lime)', accent: 'var(--purple)',
    points: [[<MonitorSmartphone size={I} strokeWidth={S} />, 'Start on one, finish on the other'],
      [<Zap size={I} strokeWidth={S} />, `Quick add and “Hey ${ai}” for adding things fast`],
      [<Hand size={I} strokeWidth={S} />, 'Let\'s set it up: it takes a minute']],
    stickers: [{ icon: <RefreshCw size={I} strokeWidth={S} />, text: 'Synced just now', color: 'var(--lime)', x: 0.5, y: -0.06 }] },
]

export default function Tour({ onDone }: { onDone: () => void }) {
  const ai = useAssistantName()
  const all = pages(ai)
  const [index, setIndex] = useState(0)
  // The page whose screen and text are showing, and whose cards are out (so a new page starts hidden on its first frame).
  const [revealedAt, setRevealedAt] = useState(-1)
  const [zoomedAt, setZoomedAt] = useState(-1)
  const revealed = revealedAt === index, zoomed = zoomedAt === index
  const touch = useRef<{ x: number; y: number } | null>(null)
  const page = all[index]
  const last = index === all.length - 1

  // Shows the page: the screen fades in, then the text and the cards.
  useEffect(() => {
    const a = setTimeout(() => setRevealedAt(index), 80)
    const b = setTimeout(() => setZoomedAt(index), 530)
    return () => { clearTimeout(a); clearTimeout(b) }
  }, [index])

  const finish = () => { setTourSeen(true); onDone() }
  const go = (i: number) => {
    if (i < 0) return
    if (i >= all.length) { finish(); return }
    setIndex(i)
  }

  // Android back goes to the previous page (the app's own back handler isn't active here).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight' || e.key === ' ') go(index + 1)
      else if (e.key === 'ArrowLeft' || e.key === 'Escape') go(index - 1)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })

  return (
    <div className="po-screen po-tour">
      <div className="po-blobs" aria-hidden>
        <span className="po-blob b1" style={{ backgroundColor: page.color }} />
        <span className="po-blob b2" style={{ backgroundColor: page.accent }} />
        <span className="po-blob b3" style={{ backgroundColor: page.color }} />
      </div>

      <div className="po-tour-head">
        <div className="po-bars">
          {all.map((_, i) => <span key={i} onClick={() => go(i)}><i style={{ transform: `scaleX(${i <= index ? 1 : 0})` }} /></span>)}
        </div>
        <div className="po-tour-nav">
          <button className="po-back" aria-label="Back" style={{ opacity: index > 0 ? 1 : 0 }} disabled={index === 0} onClick={() => go(index - 1)}>
            <ChevronLeft size={18} strokeWidth={3} />
          </button>
          <span className="count">{String(index + 1).padStart(2, '0')} / {String(all.length).padStart(2, '0')}</span>
          {!last && <button className="skip" onClick={finish}>Skip</button>}
        </div>
      </div>

      <div className="po-tour-body"
        onTouchStart={(e) => { touch.current = { x: e.touches[0].clientX, y: e.touches[0].clientY } }}
        onTouchEnd={(e) => {
          const t = touch.current; touch.current = null
          if (!t) return
          const dx = e.changedTouches[0].clientX - t.x, dy = e.changedTouches[0].clientY - t.y
          if (Math.abs(dx) < 40 || Math.abs(dx) < Math.abs(dy)) return
          go(dx < 0 ? index + 1 : index - 1)
        }}>
        <div key={`stage-${index}`} className={`po-stage ${revealed ? '' : 'hidden'}`}>
          <div className="po-phone-slot">
            <div className="po-phone">
              <div className="screen"><img src={`tour/phone-${page.image}.jpg`} alt="" draggable={false} /><span className="glare" /></div>
              <span className="cam" />
            </div>
          </div>
          <div className="po-mac-slot">
            <div className="po-mac">
              <div className="lid"><img src={`tour/mac-${page.image}.jpg`} alt="" draggable={false} /><span className="notch" /></div>
              <div className="hinge" /><div className="base" />
            </div>
          </div>
          {/* Cards over the devices' edges, kept on screen. */}
          {page.stickers.map((s, i) => (
            <span key={s.text} className={`po-sticker ${zoomed ? 'shown' : ''}`}
              style={{ left: `${Math.min(0.76, Math.max(0.24, s.x)) * 100}%`, top: `${s.y * 100}%`, background: s.color, transitionDelay: zoomed ? `${(0.9 + i * 0.35) * 0.4}s` : '0s' }}>
              <span className="ic">{s.icon}</span>{s.text}
            </span>
          ))}
        </div>

        <div key={`text-${index}`} className={`po-tour-text ${revealed ? '' : 'po-hide'}`}>
          <span className="po-eyebrow" style={{ background: page.color }}>{page.eyebrow}</span>
          <h1 className="po-tour-title">{page.title}</h1>
          <div className="po-points">
            {page.points.map(([icon, text], i) => (
              <div key={text} className="po-point" style={{ transitionDelay: `${0.35 + i * 0.14}s` }}>
                <span className="po-dot" style={{ background: page.color }}>{icon}</span>
                <span>{text}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="po-tour-foot">
          <button className="btn-primary po-primary" onClick={() => (last ? finish() : go(index + 1))}>
            {last ? 'Get started' : 'Next'}{last ? <ArrowRightCircle size={18} /> : <ArrowRight size={18} />}
          </button>
        </div>
      </div>
    </div>
  )
}
