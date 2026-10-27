// Today, laid out exactly like the iPhone's PhoneToday: greeting and weather, three action chips, the capture field,
// four small numbers, the morning brief, Up next (your top 3, what's due, what's next), habit chips, the check-in,
// the evening summary, and how's today with a few small chips.
import { useEffect, useMemo, useState } from 'react'
import { Moon, CheckCircle2, Timer, TrendingUp, Plus, Hourglass, Mic, BookOpen, Mail, MessagesSquare, Mountain, Check } from 'lucide-react'
import type { Nav } from '@/App'
import { store, useRecords, useSetting } from '@/lib/store'
import { FocusSession, DayPlan, Task, Habit, Txn, Note, Book, Bucket, AREA_COLOR, areaOf, MOOD_FACES, MOOD_WORDS, bucketKind } from '@/lib/models'
import { iso, parse, startOfDay, addDays, isToday, dayKey, fmtDay, daysBetween } from '@/lib/dates'
import { fetchWeather, describe, Weather } from '@/lib/weather'
import { useMoney } from '@/components/ui'
import { useKeys } from '@/lib/ai'
import { useInbox } from '@/lib/inbox'
import { openFocus, focusToday } from '@/lib/focus'
import { planFor, todayKey } from '@/lib/dayPlan'
import { BriefCard, smartParse, saveCaptured, parseQuick } from '@/screens/Today'
import { currentPeriod, spent as periodSpent } from '../lib/budgetPeriod'
import UpNext from '../components/UpNext'
import CheckInCard from '../components/CheckInCard'
import DaySummaryCard from '../components/DaySummaryCard'
import { Orb } from '../components/Orb'
import { native, isNative } from '../native'

export default function Today({ nav }: { nav: Nav }) {
  const tasks = useRecords<Task>('task')
  const habits = useRecords<Habit>('habit')
  const txns = useRecords<Txn>('transaction')
  const notes = useRecords<Note>('note')
  const books = useRecords<Book>('book')
  const dreams = useRecords<Bucket>('bucket')
  const focus = useRecords<FocusSession>('focusSession')
  const plans = useRecords<DayPlan>('dayPlan')
  const userName = useSetting<string>('userName', '')
  const budget = useSetting<number>('monthlyBudget', 2000)
  const goal = useSetting<number>('readingGoal', 24)
  const money = useMoney()
  const keys = useKeys()
  const inbox = useInbox(keys.gmail, keys.anthropic)
  const today = startOfDay(new Date())
  const tomorrow = addDays(today, 1)
  const hour = new Date().getHours()
  const evening = hour >= 17
  const plannedTomorrow = plans.some((p) => p.data.day === dayKey(tomorrow) && p.data.top.length > 0)
  const minutes = focusToday(focus)

  const due = useMemo(() => tasks.filter((t) => !t.data.isDone && t.data.due && parse(t.data.due)! < tomorrow).length, [tasks])
  const spent = periodSpent(txns.map((t) => t.data), currentPeriod(new Date()))
  const readThisYear = books.filter((b) => b.data.status === 'read' && parse(b.data.finishedAt)?.getFullYear() === today.getFullYear()).length
  const first = userName.split(' ')[0]
  const greeting = `${hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening'}${first ? `, ${first}` : ''}`

  return (
    <div className="page col ptd" style={{ gap: 14 }}>
      <div className="row" style={{ gap: 10 }}>
        <div className="col" style={{ gap: 1, minWidth: 0, flex: 1 }}>
          <div className="clamp1" style={{ fontSize: 17, fontWeight: 650 }}>{greeting}</div>
          <div className="secondary" style={{ fontSize: 13 }}>{fmtDay(today, { weekday: 'long', day: 'numeric', month: 'long' })}</div>
        </div>
        <WeatherChip />
      </div>

      <div className="ptd-chips">
        <button className={evening && !plannedTomorrow ? 'lime' : ''} onClick={nav.openPlan}>
          {plannedTomorrow ? <CheckCircle2 size={15} /> : <Moon size={15} />}{plannedTomorrow ? 'Tomorrow planned' : 'Plan tomorrow'}
        </button>
        <button onClick={() => openFocus(null)}><Timer size={15} />{minutes > 0 ? `Focus · ${minutes} min` : 'Focus'}</button>
        <button onClick={nav.openReview}><TrendingUp size={15} />Week in review</button>
      </div>

      <Capture />

      <div className="ptd-glance">
        <Mini value={String(due)} label="Due" color="var(--peach)" onClick={() => nav.go('tasks')} />
        <Mini value={`${habits.filter((h) => h.data.doneDays.includes(dayKey(today))).length}/${habits.length}`} label="Habits" color="var(--lime)" onClick={() => nav.go('habits' as any)} />
        <Mini value={money(Math.max(budget - spent, 0))} label="Left" color="var(--cyan)" onClick={() => nav.go('money')} />
        <Mini value={`${readThisYear}/${goal}`} label="Books" color="var(--purple)" onClick={() => nav.go('reading')} />
      </div>

      {keys.anthropic && <BriefCard hasKey />}
      <UpNext onTasks={() => nav.go('tasks')} onCalendar={() => nav.go('calendar')} plan={planFor(todayKey(), plans)} />

      {habits.length > 0 && (
        <div className="ptd-scroll">
          {habits.map((h) => {
            const done = h.data.doneDays.includes(dayKey(today))
            const color = AREA_COLOR[areaOf(h.data.area)]
            const streak = streakOf(h.data.doneDays)
            return (
              <button key={h.id} className="ptd-habit" style={done ? { background: color, borderColor: color, color: 'var(--sticker-ink)' } : { borderColor: color }}
                onClick={() => store.update<Habit>(h.id, { doneDays: done ? h.data.doneDays.filter((d) => d !== dayKey(today)) : [...h.data.doneDays, dayKey(today)] })}>
                {done && <Check size={12} strokeWidth={3} />}{h.data.name}{streak > 1 && <small>{streak}🔥</small>}
              </button>
            )
          })}
        </div>
      )}

      <CheckInCard onOpenJournal={nav.openJournal} />
      {evening && <DaySummaryCard />}
      <AlsoToday notes={notes} books={books} dreams={dreams} today={today} emails={inbox.digest?.needsReply.length ?? 0} nav={nav} />
    </div>
  )
}

/** Consecutive days up to today (or yesterday, if today isn't ticked yet). */
function streakOf(days: string[]): number {
  const set = new Set(days)
  let d = startOfDay(new Date())
  if (!set.has(dayKey(d))) d = addDays(d, -1)
  let n = 0
  while (set.has(dayKey(d))) { n++; d = addDays(d, -1) }
  return n
}

function Mini({ value, label, color, onClick }: { value: string; label: string; color: string; onClick: () => void }) {
  // Shrinks to fit like the iPhone's minimumScaleFactor.
  const size = value.length > 9 ? 13 : value.length > 7 ? 15 : 18
  return (
    <button className="ptd-mini" style={{ background: color }} onClick={onClick}>
      <span className="display clamp1" style={{ fontSize: size }}>{value}</span>
      <span>{label}</span>
    </button>
  )
}

/** The weather in a small chip (the iPhone's WeatherChip). */
function WeatherChip() {
  const city = useSetting<string>('weatherCity', '')
  const [w, setW] = useState<Weather | null>(null)
  useEffect(() => {
    let alive = true
    const load = () => fetchWeather(city).then((x) => alive && setW(x)).catch(() => {})
    load()
    const t = setInterval(load, 30 * 60_000)
    return () => { alive = false; clearInterval(t) }
  }, [city])
  if (!w) return null
  const d = describe(w.code, w.isDay)
  return (
    <div className="ptd-weather">
      <span style={{ fontSize: 24 }}>{d.emoji}</span>
      <div>
        <div style={{ fontWeight: 650, fontSize: 16, lineHeight: 1.1 }}>{Math.round(w.temp)}°</div>
        <div className="muted" style={{ fontSize: 11 }}>H {Math.round(w.high)}°  L {Math.round(w.low)}°</div>
      </div>
    </div>
  )
}

/** "Add a task, event, expense or note…" with a mic, as on the iPhone (CaptureEngine: Claude with Pro, else a task). */
function Capture() {
  const keys = useKeys()
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [listening, setListening] = useState(false)
  const [result, setResult] = useState('')
  const run = async (raw: string) => {
    const t = raw.trim()
    if (!t || busy) return
    setBusy(true)
    let summary = ''
    try {
      if (!keys.anthropic) throw new Error('offline')
      const items = await smartParse(t)
      if (!items.length) throw new Error('nothing')
      summary = items.map(saveCaptured).join(', ')
    } catch {
      const q = parseQuick(t)
      if (q.title) {
        store.create<Task>('task', { title: q.title, notes: '', area: q.area, due: q.due ? iso(q.due) : null, priority: q.priority, isDone: false,
          completedAt: null, createdAt: iso(new Date()), repeat: 'none', remindAt: null, place: { name: '', lat: 0, lon: 0, onLeave: false } } as any)
        summary = `Task “${q.title}”`
      }
    }
    setText(''); setBusy(false)
    if (summary) { setResult(`Saved: ${summary}`); setTimeout(() => setResult(''), 4000) }
  }
  const listen = async () => {
    if (!isNative || listening) return
    setListening(true)
    const h = await native.addListener('partial', (d) => setText(d.text))
    try { const { text: heard } = await native.listen({}); if (heard.trim()) await run(heard) } catch { /* nothing heard */ } finally { h.remove(); setListening(false) }
  }
  return (
    <div className="col" style={{ gap: 4 }}>
      <div className="ptd-capture">
        {keys.anthropic ? <Orb size={22} busy={busy} spark /> : busy ? <Hourglass size={18} className="secondary" /> : <Plus size={20} className="secondary" />}
        <input className="plain" disabled={busy} value={text} onChange={(e) => setText(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') run(text) }}
          placeholder={listening ? 'Listening…' : keys.anthropic ? 'Add anything: “gym tomorrow 7am”' : 'Add a task, event, expense or note…'} />
        <button className={`ptd-mic ${listening ? 'live' : ''}`} aria-label="Speak" onClick={listen}><Mic size={17} /></button>
      </div>
      {result && <div className="clamp2" style={{ fontSize: 12, fontWeight: 500, color: 'var(--good)', paddingLeft: 12 }}>{result}</div>}
    </div>
  )
}

/** How's today (mood) and small chips: what you're reading, the next dream, emails to answer, the journal. */
function AlsoToday({ notes, books, dreams, today, emails, nav }: { notes: any[]; books: any[]; dreams: any[]; today: Date; emails: number; nav: Nav }) {
  const entry = notes.find((n) => n.data.isJournal && isToday(parse(n.data.createdAt) ?? new Date(0)))
  const reading = books.find((b) => b.data.status === 'reading')
  const upcoming = dreams.filter((d) => !d.data.isDone && d.data.kind !== 'place' && (parse(d.data.targetDate) ?? new Date(0)) >= today)
    .sort((a, b) => parse(a.data.targetDate)!.getTime() - parse(b.data.targetDate)!.getTime())[0]
  const setMood = (m: number) => {
    const value = entry?.data.mood === m ? 0 : m
    if (entry) store.update<Note>(entry.id, { mood: value, moodSetByUser: value !== 0 })
    else {
      const now = iso(new Date())
      store.create<Note>('note', { title: fmtDay(new Date(), { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }), body: '',
        createdAt: now, updatedAt: now, isJournal: true, pinned: false, mood: value, moodSetByUser: value !== 0 })
    }
  }
  return (
    <div className="col" style={{ gap: 10 }}>
      <div className="ptd-mood">
        <span style={{ fontSize: 13, fontWeight: 650, flex: 1 }}>How's today?</span>
        {[1, 2, 3, 4, 5].map((m) => (
          <button key={m} aria-label={MOOD_WORDS[m]} onClick={() => setMood(m)}
            style={{ background: entry?.data.mood === m ? 'var(--lime)' : 'transparent', opacity: !entry?.data.mood || entry.data.mood === m ? 1 : 0.4 }}>{MOOD_FACES[m]}</button>
        ))}
      </div>
      <div className="ptd-scroll">
        {reading && <SmallChip icon={<BookOpen size={11} strokeWidth={3} />} color="var(--purple)" text={`${reading.data.title} · ${Math.round(reading.data.progress * 100)}%`} onClick={() => nav.go('reading')} />}
        {upcoming && <SmallChip icon={<Mountain size={11} strokeWidth={3} />} color={bucketKind(upcoming.data.kind).color}
          text={`${upcoming.data.title} · ${(() => { const n = daysBetween(today, parse(upcoming.data.targetDate)!); return n === 0 ? 'today' : `${n}d` })()}`} onClick={() => nav.go('bucket')} />}
        {emails > 0 && <SmallChip icon={<Mail size={11} strokeWidth={3} />} color="var(--pink)" text={`${emails} email${emails === 1 ? '' : 's'} to answer`} onClick={() => nav.go('today')} />}
        <SmallChip icon={<MessagesSquare size={11} strokeWidth={3} />} color="var(--peach)" text="Journal" onClick={nav.openJournal} />
      </div>
    </div>
  )
}

function SmallChip({ icon, color, text, onClick }: { icon: React.ReactNode; color: string; text: string; onClick: () => void }) {
  return <button className="ptd-small" onClick={onClick}><span style={{ background: color }}>{icon}</span>{text}</button>
}
