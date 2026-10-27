import { useEffect, useMemo, useState } from 'react'
import { Timer, Moon, TrendingUp, Sun, Flame, CreditCard, Library, Check, Plus, MessagesSquare, Mountain, Sparkles, RefreshCw, Mail, ArrowUpRight, AlertCircle } from 'lucide-react'
import type { Nav } from '@/App'
import { store, useRecords, useSetting, Rec } from '@/lib/store'
import { FocusSession, DayPlan, Task, CalEvent, Habit, Txn, Note, Book, Bucket, AREA_COLOR, areaOf, bucketKind, MOOD_FACES, MOOD_WORDS, AREAS, Area } from '@/lib/models'
import { iso, parse, startOfDay, addDays, isToday, sameDay, dayKey, startOfWeek, startOfMonth, fmtTime, fmtDay, daysBetween, relativeTime } from '@/lib/dates'
import { fetchWeather, describe, Weather } from '@/lib/weather'
import { Card, SectionHeader, StatTile, EmptyHint, AreaPill, useMoney } from '@/components/ui'
import { TaskRow } from '@/components/TaskRow'
import { BookCover } from '@/screens/Reading'
import { structured, useKeys, useAssistantName } from '@/lib/ai'
import { useBrief } from '@/lib/brief'
import { useInbox, mailLink, MailItem, Digest } from '@/lib/inbox'
import { openFocus, focusToday } from '@/lib/focus'
import { planFor, todayKey } from '@/lib/dayPlan'
import { TopThreeCard, PlanTomorrowCard } from '@/screens/PlanTomorrow'

/** The dashboard: everything for today on one screen, no scrolling. */
export default function Today({ nav }: { nav: Nav }) {
  const tasks = useRecords<Task>('task')
  const events = useRecords<CalEvent>('event')
  const habits = useRecords<Habit>('habit')
  const txns = useRecords<Txn>('transaction')
  const notes = useRecords<Note>('note')
  const books = useRecords<Book>('book')
  const dreams = useRecords<Bucket>('bucket')
  const focus = useRecords<FocusSession>('focusSession')
  const plans = useRecords<DayPlan>('dayPlan')
  const todayPlan = planFor(todayKey(), plans)
  const userName = useSetting<string>('userName', '')
  const budget = useSetting<number>('monthlyBudget', 2000)
  const goal = useSetting<number>('readingGoal', 24)
  const money = useMoney()
  const keys = useKeys()
  const hasMail = keys.gmail.length > 0
  const inbox = useInbox(keys.gmail, keys.anthropic)
  const today = startOfDay(new Date())
  const tomorrow = addDays(today, 1)

  const dueToday = useMemo(() => tasks
    .filter((t) => !t.data.isDone && t.data.due && parse(t.data.due)! < tomorrow)
    .sort((a, b) => b.data.priority - a.data.priority || (parse(a.data.due)!.getTime() - parse(b.data.due)!.getTime())), [tasks])
  const agenda = events.filter((e) => sameDay(parse(e.data.start)!, today)).sort((a, b) => a.data.start.localeCompare(b.data.start))
  const tomorrowEvents = events.filter((e) => sameDay(parse(e.data.start)!, tomorrow)).sort((a, b) => a.data.start.localeCompare(b.data.start))
  const spent = -txns.filter((t) => t.data.amount < 0 && parse(t.data.date)! >= startOfMonth(today)).reduce((s, t) => s + t.data.amount, 0)
  const year = today.getFullYear()
  const readThisYear = books.filter((b) => b.data.status === 'read' && parse(b.data.finishedAt)?.getFullYear() === year).length
  const doneThisWeek = tasks.filter((t) => t.data.isDone && (parse(t.data.completedAt) ?? new Date(0)) >= startOfWeek(today)).length
  const journal = notes.find((n) => n.data.isJournal && isToday(parse(n.data.createdAt) ?? new Date(0)))
  const reading = books.find((b) => b.data.status === 'reading')

  const hour = new Date().getHours()
  const greeting = `${hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening'}${userName ? `, ${userName.split(' ')[0]}` : ''}.`
  const next = agenda.find((e) => parse(e.data.start)! > new Date())
  const overdue = tasks.filter((t) => !t.data.isDone && t.data.due && parse(t.data.due)! < today).length

  return (
    <div style={{ height: '100%', padding: '4px 32px 22px', display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div className="row" style={{ gap: 20 }}>
        <div style={{ minWidth: 0 }}>
          <h1 className="page-title" style={{ fontSize: 32 }}>{fmtDay(today)}</h1>
          <div className="row" style={{ gap: 10, minWidth: 0 }}>
            <div className="secondary clamp1" style={{ fontSize: 13, minWidth: 0 }}>
              {greeting} {next ? `Next up: ${next.data.title} ${relativeTime(parse(next.data.start)!)}.` : 'Nothing else on the calendar today.'}
              {overdue > 0 && ` ${overdue} overdue.`}
            </div>
            <button className="row" style={{ gap: 5, fontSize: 12, fontWeight: 600, flex: 'none' }} title="Your week, mood and patterns" onClick={nav.openReview}>
              <TrendingUp size={13} />Week in review
            </button>
            <button className="row" style={{ gap: 5, fontSize: 12, fontWeight: 600, flex: 'none' }} title="Leftovers, tomorrow's calendar and your top 3" onClick={nav.openPlan}>
              <Moon size={13} />Plan tomorrow
            </button>
            <button className="row" style={{ gap: 5, fontSize: 12, fontWeight: 600, flex: 'none' }} title="Start a focus timer" onClick={() => openFocus(null)}>
              <Timer size={13} />Focus{focusToday(focus) > 0 && <span className="muted" style={{ fontWeight: 500 }}> · Focus today: {focusToday(focus)} min</span>}
            </button>
          </div>
        </div>
        <span className="spacer" />
        <ClockWeather />
        <QuickAdd />
      </div>

      <div className="row" style={{ gap: 12 }}>
        <StatTile value={String(dueToday.length)} label="Due today" icon={<Sun size={12} />} color="var(--peach)" onClick={() => nav.go('tasks')} />
        <StatTile value={`${habits.filter((h) => h.data.doneDays.includes(dayKey(today))).length}/${habits.length}`} label="Habits today"
          icon={<Flame size={12} />} color="var(--lime)" onClick={() => nav.go('habits')} />
        <StatTile value={money(spent)} label="Spent this month" icon={<CreditCard size={12} />} color="var(--cyan)" onClick={() => nav.go('money')} />
        <StatTile value={`${readThisYear}/${goal}`} label="Books this year" icon={<Library size={12} />} color="var(--purple)" onClick={() => nav.go('reading')} />
        {hasMail
          ? <StatTile value={String(inbox.digest?.needsReply.length ?? 0)} label="Emails to answer" icon={<Mail size={12} />} color="var(--pink)" />
          : <StatTile value={String(dreams.filter((d) => !d.data.isDone).length)} label="Dreams to do" icon={<Mountain size={12} />} color="var(--pink)" onClick={() => nav.go('bucket')} />}
        <StatTile value={String(doneThisWeek)} label="Done this week" icon={<Check size={12} />} color="var(--orange)" onClick={() => nav.go('tasks')} />
      </div>

      <div className="row" style={{ flex: 1, minHeight: 0, alignItems: 'stretch', gap: 14 }}>
        {/* Column 1: brief and agenda */}
        <div className="col" style={{ flex: 1, minWidth: 0, gap: 14 }}>
        <BriefCard hasKey={keys.anthropic} />
        <Card className="col" style={{ flex: 1, minHeight: 150 }} padding={16}>
          <SectionHeader title="Agenda" trailing="Calendar" onTrailing={() => nav.go('calendar')} />
          <div className="scroll col" style={{ gap: 8, flex: 1 }}>
            {agenda.length === 0 && <EmptyHint text="Nothing scheduled today." />}
            {agenda.map((e) => <AgendaRow key={e.id} e={e} />)}
            {tomorrowEvents.length > 0 && <div className="muted" style={{ fontSize: 11, fontWeight: 600, marginTop: 6 }}>Tomorrow</div>}
            {tomorrowEvents.slice(0, 4).map((e) => <AgendaRow key={e.id} e={e} dim />)}
          </div>
        </Card>
        </div>

        {/* Column 2: tasks, habits, looking forward */}
        <div className="col" style={{ flex: 1, minWidth: 0, minHeight: 0, gap: 14 }}>
          {todayPlan && todayPlan.data.top.length > 0 && <TopThreeCard plan={todayPlan} onPlan={nav.openPlan} />}
          <Card className="col" padding={16} style={{ flex: '1.4 1 0', minHeight: 150 }}>
            <SectionHeader title="Due today" trailing="All tasks" onTrailing={() => nav.go('tasks')} />
            <AddTaskInline />
            <div className="scroll col" style={{ gap: 6, flex: 1 }}>
              {dueToday.length === 0 && <EmptyHint text="Nothing due. Nice." />}
              {dueToday.map((t) => <TaskRow key={t.id} rec={t} showDue={parse(t.data.due)! < today} />)}
            </div>
          </Card>
          <Card className="col" padding={14}>
            <SectionHeader title="Habits" trailing={habits.length ? 'View all' : 'Add habit'} onTrailing={() => nav.go('habits')} />
            {habits.length === 0 ? <EmptyHint text="Build a streak: add your first habit." /> : (
              <div className="row scroll" style={{ gap: 8, overflowX: 'auto' }}>
                {habits.map((h) => <HabitChip key={h.id} h={h} />)}
              </div>
            )}
          </Card>
          {hour >= 17 ? <PlanTomorrowCard onPlan={nav.openPlan} /> : !(todayPlan && todayPlan.data.top.length > 0) && (
            <Card className="col" style={{ flex: '1 1 0', minHeight: 64, overflow: 'hidden' }} padding={14}>
              <SectionHeader title="Looking forward to" trailing="Bucket list" onTrailing={() => nav.go('bucket')} />
              <LookingForward dreams={dreams} />
            </Card>
          )}
        </div>

        {/* Column 3: reading, money, mood */}
        <div className="col" style={{ width: 390, gap: 14 }}>
          {hasMail ? <InboxCard accounts={keys.gmail} inbox={inbox} /> : (
            <Card className="col" style={{ flex: 1, minHeight: 0 }} padding={16}>
              <SectionHeader title="This week" />
              <WeekGlance tasks={tasks} events={events} />
            </Card>
          )}
          <button className="card row" style={{ padding: 12, textAlign: 'left' }} onClick={() => nav.go('reading')}>
            {reading ? (
              <>
                <div style={{ width: 40, height: 60, flex: 'none' }}><BookCover book={reading.data} /></div>
                <div className="col" style={{ gap: 4, flex: 1, minWidth: 0 }}>
                  <span className="muted" style={{ fontSize: 10, fontWeight: 600 }}>Reading</span>
                  <strong className="clamp1" style={{ fontSize: 13 }}>{reading.data.title}</strong>
                  <div style={{ height: 5, background: 'var(--line)', borderRadius: 3 }}>
                    <div style={{ height: 5, width: `${Math.max(4, reading.data.progress * 100)}%`, background: 'var(--ink)', borderRadius: 3 }} />
                  </div>
                  <span className="secondary" style={{ fontSize: 10 }}>{Math.round(reading.data.progress * 100)}% · {readThisYear} of {goal} books this year</span>
                </div>
              </>
            ) : (
              <div className="col" style={{ gap: 2 }}>
                <strong style={{ fontSize: 13 }}>{readThisYear} of {goal} books this year</strong>
                <span className="secondary" style={{ fontSize: 11 }}>Nothing on the go. Pick your next read.</span>
              </div>
            )}
          </button>
          <div className="row" style={{ gap: 14, alignItems: 'stretch' }}>
            <button className="card col" style={{ flex: 1, background: 'var(--lime)', color: 'var(--sticker-ink)', padding: 14, gap: 6, textAlign: 'left' }} onClick={() => nav.go('money')}>
              <span style={{ fontSize: 11, fontWeight: 600 }}>Left to spend</span>
              <span className="display clamp1" style={{ fontSize: 22 }}>{money(Math.max(budget - spent, 0))}</span>
              <div style={{ height: 6, background: 'rgba(0,0,0,0.12)', borderRadius: 3 }}>
                <div style={{ height: 6, width: `${Math.min(100, budget > 0 ? (spent / budget) * 100 : 0)}%`, background: '#111', borderRadius: 3 }} />
              </div>
              <span style={{ fontSize: 10, opacity: 0.7 }}>of {money(budget)}</span>
            </button>
            <MoodCard journal={journal} onOpen={nav.openJournal} />
          </div>
        </div>
      </div>
    </div>
  )
}

export function AgendaRow({ e, dim }: { e: Rec<CalEvent>; dim?: boolean }) {
  const start = parse(e.data.start)!, end = parse(e.data.end)!
  const now = new Date()
  return (
    <div className="row inner" style={{ padding: 10, gap: 12, opacity: end < now || dim ? 0.5 : 1 }}>
      <div style={{ width: 60, textAlign: 'right', flex: 'none' }}>
        <div style={{ fontSize: 12, fontWeight: 600 }}>{fmtTime(start)}</div>
        <div className="muted" style={{ fontSize: 10 }}>{fmtTime(end)}</div>
      </div>
      <span style={{ width: 4, height: 30, borderRadius: 2, background: AREA_COLOR[areaOf(e.data.area)], flex: 'none' }} />
      <span className="clamp1" style={{ flex: 1, fontWeight: 500, fontSize: 13 }}>{e.data.title}</span>
      <AreaPill area={areaOf(e.data.area)} compact />
      {start <= now && end > now && <span className="pill compact" style={{ background: 'var(--critical)', color: '#fff', fontWeight: 700 }}>Now</span>}
    </div>
  )
}

export function HabitChip({ h }: { h: Rec<Habit> }) {
  const key = dayKey(new Date())
  const done = h.data.doneDays.includes(key)
  const color = AREA_COLOR[areaOf(h.data.area)]
  const toggle = () => store.update<Habit>(h.id, { doneDays: done ? h.data.doneDays.filter((d) => d !== key) : [...h.data.doneDays, key] })
  return (
    <button onClick={toggle} className="row" style={{
      gap: 8, padding: '8px 12px', borderRadius: 999, flex: 'none', fontSize: 12, fontWeight: 600,
      background: done ? color : 'var(--canvas)', color: done ? 'var(--sticker-ink)' : 'var(--ink)', boxShadow: done ? 'none' : `inset 0 0 0 1.5px ${color}`,
    }}>
      {done && <Check size={12} strokeWidth={3} />}{h.data.name}
    </button>
  )
}

export function LookingForward({ dreams }: { dreams: Rec<Bucket>[] }) {
  const today = startOfDay(new Date())
  const open = dreams.filter((d) => !d.data.isDone)
  const upcoming = open.filter((d) => d.data.targetDate && parse(d.data.targetDate)! >= today).sort((a, b) => a.data.targetDate!.localeCompare(b.data.targetDate!))
  const someday = open.filter((d) => !d.data.targetDate).sort((a, b) => b.data.excitement - a.data.excitement)
  if (!open.length) return <EmptyHint text="Add things you want to do in life to your bucket list." />
  return (
    <div className="scroll col" style={{ gap: 8 }}>
      {upcoming.slice(0, 4).map((d) => {
        const n = daysBetween(today, parse(d.data.targetDate)!)
        return (
          <div key={d.id} className="row" style={{ gap: 12 }}>
            <span className="display" style={{ width: 46, textAlign: 'center', padding: '6px 0', borderRadius: 10, background: bucketKind(d.data.kind).color, color: 'var(--sticker-ink)', fontSize: 16 }}>{n === 0 ? '🎉' : `${n}d`}</span>
            <div style={{ minWidth: 0 }}>
              <div className="clamp1" style={{ fontWeight: 600, fontSize: 13 }}>{d.data.title}</div>
              <div className="muted" style={{ fontSize: 10 }}>{fmtDay(parse(d.data.targetDate)!, { weekday: 'short', day: 'numeric', month: 'short' })}</div>
            </div>
          </div>
        )
      })}
      {someday.slice(0, Math.max(0, 3 - upcoming.length)).map((d) => (
        <div key={d.id} className="row" style={{ gap: 12 }}>
          <span style={{ width: 46, height: 30, borderRadius: 10, background: bucketKind(d.data.kind).color, opacity: 0.7 }} />
          <div style={{ minWidth: 0 }}>
            <div className="clamp1" style={{ fontWeight: 600, fontSize: 13 }}>{d.data.title}</div>
            <div className="muted" style={{ fontSize: 10 }}>Someday</div>
          </div>
        </div>
      ))}
    </div>
  )
}

/** Seven days at a glance: events and tasks due per day. */
function WeekGlance({ tasks, events }: { tasks: Rec<Task>[]; events: Rec<CalEvent>[] }) {
  const today = startOfDay(new Date())
  const days = Array.from({ length: 7 }, (_, i) => addDays(today, i))
  return (
    <div className="scroll col" style={{ gap: 6 }}>
      {days.map((d) => {
        const ev = events.filter((e) => sameDay(parse(e.data.start)!, d))
        const due = tasks.filter((t) => !t.data.isDone && t.data.due && sameDay(parse(t.data.due)!, d))
        return (
          <div key={d.toISOString()} className="row inner" style={{ padding: '8px 10px', gap: 10 }}>
            <span style={{ width: 44, fontWeight: 600, fontSize: 12 }}>{i18nDay(d)}</span>
            <div className="row" style={{ gap: 4, flex: 1, minWidth: 0, flexWrap: 'wrap' }}>
              {ev.length === 0 && due.length === 0 && <span className="muted" style={{ fontSize: 11 }}>Free</span>}
              {ev.slice(0, 3).map((e) => <span key={e.id} className="pill compact clamp1" style={{ background: AREA_COLOR[areaOf(e.data.area)], maxWidth: 120 }}>{e.data.title}</span>)}
              {due.length > 0 && <span className="muted" style={{ fontSize: 11 }}>{due.length} task{due.length === 1 ? '' : 's'}</span>}
            </div>
          </div>
        )
      })}
    </div>
  )
}
const i18nDay = (d: Date): string => (isToday(d) ? 'Today' : d.toLocaleDateString(undefined, { weekday: 'short' }))

export function MoodCard({ journal, onOpen }: { journal?: Rec<Note>; onOpen: () => void }) {
  const setMood = (m: number) => {
    const value = journal?.data.mood === m ? 0 : m
    if (journal) store.update<Note>(journal.id, { mood: value, moodSetByUser: value !== 0 })
    else {
      const now = iso(new Date())
      store.create<Note>('note', {
        title: fmtDay(new Date(), { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }), body: '',
        createdAt: now, updatedAt: now, isJournal: true, pinned: false, mood: value, moodSetByUser: value !== 0,
      })
    }
  }
  return (
    <div className="card col" style={{ flex: 1, background: 'var(--blush)', padding: 14, gap: 8 }}>
      <span style={{ fontSize: 11, fontWeight: 600 }}>How's today?</span>
      <div className="row" style={{ gap: 2 }}>
        {[1, 2, 3, 4, 5].map((m) => (
          <button key={m} title={MOOD_WORDS[m]} onClick={() => setMood(m)} style={{
            width: 30, height: 30, borderRadius: '50%', fontSize: 17, background: journal?.data.mood === m ? 'var(--lime)' : 'transparent',
            opacity: !journal?.data.mood || journal.data.mood === m ? 1 : 0.4,
          }}>{MOOD_FACES[m]}</button>
        ))}
      </div>
      <button className="row link" style={{ gap: 6, fontWeight: 600, color: 'var(--ink)' }} onClick={onOpen}><MessagesSquare size={13} /> Journal</button>
    </div>
  )
}

export function ClockWeather() {
  const city = useSetting<string>('weatherCity', '')
  const [now, setNow] = useState(new Date())
  const [weather, setWeather] = useState<Weather | null>(null)
  const [error, setError] = useState('')
  useEffect(() => { const t = setInterval(() => setNow(new Date()), 15_000); return () => clearInterval(t) }, [])
  useEffect(() => {
    let alive = true
    const load = () => fetchWeather(city).then((w) => { if (alive) { setWeather(w); setError('') } }).catch((e) => alive && setError(e.message))
    load()
    const t = setInterval(load, 30 * 60_000)
    return () => { alive = false; clearInterval(t) }
  }, [city])
  const d = weather ? describe(weather.code, weather.isDay) : null
  return (
    <div className="row" style={{ background: 'var(--card)', borderRadius: 999, padding: '8px 18px', gap: 14, flex: 'none' }}>
      <div>
        <div className="display" style={{ fontSize: 24, lineHeight: 1 }}>{fmtTime(now)}</div>
        <div className="muted" style={{ fontSize: 10 }}>{Intl.DateTimeFormat().resolvedOptions().timeZone.split('/').pop()?.replace(/_/g, ' ')}</div>
      </div>
      <span style={{ width: 1, height: 32, background: 'var(--line)' }} />
      {weather && d ? (
        <div className="row" style={{ gap: 8 }} title={`Feels like ${Math.round(weather.feels)}°`}>
          <span style={{ fontSize: 24 }}>{d.emoji}</span>
          <div>
            <div style={{ fontWeight: 600, fontSize: 13 }}>{Math.round(weather.temp)}° {d.label}</div>
            <div className="muted" style={{ fontSize: 10 }}>H {Math.round(weather.high)}°  L {Math.round(weather.low)}° · {weather.place}</div>
          </div>
        </div>
      ) : <span className="muted" style={{ fontSize: 11, maxWidth: 150 }}>{error || 'Loading weather…'}</span>}
    </div>
  )
}

/** Quick add for the header. With an Anthropic key, Claude sorts the text into tasks, events, money and notes
 *  (several at once works too); without one, or if Claude can't be reached, the offline parser makes a task. */
export function QuickAdd() {
  const keys = useKeys()
  const name = useAssistantName()
  const [text, setText] = useState('')
  const [saved, setSaved] = useState('')
  const [busy, setBusy] = useState(false)
  const show = (msg: string) => { setSaved(msg); setTimeout(() => setSaved(''), 4000) }

  const offline = (raw: string, note = '') => {
    const t = parseQuick(raw)
    if (!t.title) return
    store.create<Task>('task', { title: t.title, notes: '', area: t.area, due: t.due ? iso(t.due) : null, priority: t.priority, isDone: false, completedAt: null, createdAt: iso(new Date()), repeat: 'none' })
    show(`Saved “${t.title}”${t.due ? ` for ${fmtDay(t.due, { weekday: 'short', day: 'numeric', month: 'short' })}` : ''}${note}`)
  }

  const submit = async () => {
    const raw = text.trim()
    if (!raw || busy) return
    if (!keys.anthropic) { offline(raw); setText(''); return }
    setBusy(true)
    try {
      const items = await smartParse(raw)
      if (!items.length) throw new Error('nothing parsed')
      setText('')
      show(`Saved — ${items.map(saveCaptured).join('  |  ')}`)
    } catch {
      setText('')
      offline(raw, ' (offline parser)')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="col" style={{ gap: 4, alignItems: 'flex-end', flex: '0 1 420px', minWidth: 260 }}>
      <div className="row" style={{ background: 'var(--card)', borderRadius: 999, padding: '11px 16px', width: '100%' }}>
        {keys.anthropic ? <Sparkles size={15} className="muted" /> : <Plus size={15} className="muted" />}
        <input className="plain" disabled={busy}
          placeholder={keys.anthropic ? 'Add anything: “gym tomorrow 7am, pay rent friday, $12 lunch”' : 'Add a task: “pay rent friday #money !!”'} value={text}
          onChange={(e) => setText(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') submit() }} />
      </div>
      {busy && <span className="secondary" style={{ fontSize: 11, fontWeight: 500 }}>{name} is sorting this…</span>}
      {!busy && saved && <span className="clamp1" style={{ fontSize: 11, fontWeight: 500, color: 'var(--good)', maxWidth: 420 }}>{saved}</span>}
    </div>
  )
}

// MARK: Smart capture (same prompt and schema as the Mac's AIAssistant.smartParse)

interface Captured { kind: string; title: string; area: Area; date: string; has_time: boolean; duration_minutes: number; amount: number; category: string; priority: number }
const MONEY_CATS = ['Food', 'Transport', 'Bills', 'Shopping', 'Health', 'Fun', 'Subscriptions', 'Income', 'General']

export async function smartParse(text: string): Promise<Captured[]> {
  const now = new Date()
  const pad = (n: number) => String(n).padStart(2, '0')
  const local = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`
  const currency = store.setting<string>('currencyCode') ?? 'USD'
  const system = `You turn a quick note typed into a personal organizer into structured items.
Current local time: ${local} (${now.toLocaleDateString('en', { weekday: 'long' })}), time zone ${Intl.DateTimeFormat().resolvedOptions().timeZone}.
Currency: ${currency}.

Rules:
- Split the input into separate items only when it clearly contains several things ("dentist thu 3pm and buy milk" = 2 items). Otherwise return exactly one item.
- kind: "event" when there is a specific time of day; "task" for things to do (with or without a date); "expense"/"income" when money changes hands; "note" for information to keep; "journal" for reflections about the user's own day or feelings.
- title: short and clean, sentence case, without the date, time, amount, tags or priority marks.
- area: the best fit among ${AREAS.join(', ')}. A #tag in the text wins.
- date: local time as yyyy-MM-ddTHH:mm, resolving relative words ("tomorrow", "next fri") from the current time. Use 00:00 when there is a day but no time. Empty string when there is no date.
- has_time: true only if a time of day was given or clearly implied ("lunch with Sam tomorrow" implies 12:30).
- duration_minutes: for events, the stated or a sensible duration (default 60); otherwise 0.
- amount: positive number for expense/income, otherwise 0.
- category: money category for expense/income; "General" otherwise.
- priority: 0-3. "!" marks = that many; words like "urgent" or "asap" = 3; otherwise 0.`
  const schema = {
    type: 'object',
    properties: {
      items: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            kind: { type: 'string', enum: ['task', 'event', 'expense', 'income', 'note', 'journal'] },
            title: { type: 'string' }, area: { type: 'string', enum: AREAS }, date: { type: 'string' }, has_time: { type: 'boolean' },
            duration_minutes: { type: 'integer' }, amount: { type: 'number' }, category: { type: 'string', enum: MONEY_CATS }, priority: { type: 'integer' },
          },
          required: ['kind', 'title', 'area', 'date', 'has_time', 'duration_minutes', 'amount', 'category', 'priority'],
          additionalProperties: false,
        },
      },
    },
    required: ['items'], additionalProperties: false,
  }
  const out = await structured<{ items: Captured[] }>(system, text, schema, 'low', 4000)
  return out.items.filter((i) => i.title.trim() || i.amount > 0)
}

function localDate(s: string): Date | null {
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?/)
  return m ? new Date(+m[1], +m[2] - 1, +m[3], +(m[4] ?? 0), +(m[5] ?? 0)) : null
}

/** Saves one captured item with every field the Mac expects; returns a short summary. */
export function saveCaptured(i: Captured): string {
  const nowIso = iso(new Date())
  const area = areaOf(i.area)
  let date = i.date ? localDate(i.date) : null
  if (date && !i.has_time) date = startOfDay(date)
  const when = date ? ` · ${fmtDay(date, { weekday: 'short', day: 'numeric', month: 'short' })}${i.has_time ? ` ${fmtTime(date)}` : ''}` : ''
  switch (i.kind) {
    case 'event': {
      if (!date || !i.has_time) break // no time of day: keep it as a task
      const end = new Date(date.getTime() + Math.max(5, i.duration_minutes || 60) * 60_000)
      store.create<CalEvent>('event', { title: i.title, start: iso(date), end: iso(end), area, location: '', notes: '' })
      return `Event “${i.title}”${when}`
    }
    case 'expense':
    case 'income': {
      const income = i.kind === 'income'
      store.create<Txn>('transaction', {
        title: i.title || i.category, amount: income ? Math.abs(i.amount) : -Math.abs(i.amount), category: income ? 'Income' : i.category,
        date: nowIso, isRecurring: false, source: '', sourceID: '', originalAmount: 0, originalCurrency: '',
      })
      return `${income ? 'Income' : 'Expense'} “${i.title}”`
    }
    case 'note':
      store.create<Note>('note', { title: i.title || 'Untitled', body: '', createdAt: nowIso, updatedAt: nowIso, isJournal: false, pinned: false, mood: 0, moodSetByUser: false })
      return `Note “${i.title}”`
    case 'journal': {
      const today = store.list<Note>('note').find((n) => n.data.isJournal && isToday(parse(n.data.createdAt) ?? new Date(0)))
      if (today) store.update<Note>(today.id, { body: today.data.body ? `${today.data.body}\n${i.title}` : i.title, updatedAt: nowIso })
      else store.create<Note>('note', { title: fmtDay(new Date(), { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }), body: i.title, createdAt: nowIso, updatedAt: nowIso, isJournal: true, pinned: false, mood: 0, moodSetByUser: false })
      return 'Added to today’s journal'
    }
  }
  store.create<Task>('task', { title: i.title, notes: '', area, due: date ? iso(date) : null, priority: Math.max(0, Math.min(3, i.priority)), isDone: false, completedAt: null, createdAt: nowIso, repeat: 'none' })
  return `Task “${i.title}”${when}`
}

// MARK: Morning brief

export function BriefCard({ hasKey }: { hasKey: boolean }) {
  const name = useAssistantName()
  const { brief, loading, error, refresh } = useBrief(hasKey)
  if (!hasKey) {
    return (
      <div className="row" style={{ padding: 14, borderRadius: 'var(--radius)', border: '1.5px dashed var(--line)', gap: 12 }}>
        <span style={{ width: 36, height: 36, borderRadius: '50%', background: 'var(--lime)', color: 'var(--sticker-ink)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}><Sparkles size={16} /></span>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontWeight: 600, fontSize: 14 }}>Get a morning brief from {name}</div>
          <div className="secondary" style={{ fontSize: 12 }}>Add your Anthropic API key, or unlock the keys synced from your Mac, in Settings › AI.</div>
        </div>
      </div>
    )
  }
  const ink = '#f4f4f5'
  return (
    <div className="col" style={{ background: '#141416', color: ink, borderRadius: 22, padding: 18, gap: 10, flex: 'none' }}>
      <div className="row" style={{ gap: 8 }}>
        <Sparkles size={14} color="var(--lime)" />
        <span style={{ fontSize: 12, fontWeight: 600, opacity: 0.7 }}>Morning brief</span>
        <span className="spacer" />
        {brief && !loading && <span style={{ fontSize: 11, opacity: 0.5 }}>Updated {fmtTime(new Date(brief.generatedAt))}</span>}
        <button onClick={refresh} disabled={loading} title="Regenerate" style={{ width: 28, height: 28, borderRadius: '50%', background: 'rgba(255,255,255,0.1)', color: ink, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
          <RefreshCw size={12} />
        </button>
      </div>
      {loading && !brief && <div className="display" style={{ fontSize: 18, fontWeight: 500 }}>{name} is reading your day…</div>}
      {error && !brief && <div className="row" style={{ fontSize: 13, gap: 6 }}><AlertCircle size={14} /> {error}</div>}
      {brief && (
        <>
          <div className="display clamp2" style={{ fontSize: 21 }}>{brief.headline}</div>
          <div style={{ fontSize: 13, opacity: 0.85, lineHeight: 1.45, display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden' }} title={brief.summary}>{brief.summary}</div>
          {brief.focus.slice(0, 3).map((f, i) => (
            <div key={i} className="row" style={{ gap: 10, alignItems: 'flex-start' }}>
              <span className="display" style={{ width: 22, height: 22, borderRadius: '50%', flex: 'none', fontSize: 13, color: 'var(--sticker-ink)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', background: ['var(--lime)', 'var(--pink)', 'var(--cyan)'][i] }}>{i + 1}</span>
              <span className="clamp2" style={{ fontSize: 13, fontWeight: 500 }}>{f}</span>
            </div>
          ))}
          {brief.heads_up && (
            <div className="row" style={{ gap: 8, padding: 10, borderRadius: 12, background: 'rgba(255,255,255,0.07)', fontSize: 12 }}>
              <AlertCircle size={13} color="var(--orange)" style={{ flex: 'none' }} />
              <span className="clamp1" title={brief.heads_up}>{brief.heads_up}</span>
            </div>
          )}
        </>
      )}
    </div>
  )
}

// MARK: Inbox

export function InboxCard({ accounts, inbox }: { accounts: string[]; inbox: { digest: Digest | null; loading: boolean; error: string; refresh: () => void } }) {
  const name = useAssistantName()
  const keys = useKeys()
  const d = inbox.digest
  const multi = accounts.length > 1
  return (
    <Card className="col" style={{ flex: 1, minHeight: 0 }} padding={16}>
      <div className="row">
        <h3 className="section-title">Inbox</h3>
        {multi && <span className="muted" style={{ fontSize: 11 }}>{accounts.length} accounts</span>}
        <span className="spacer" />
        <button className="link" onClick={inbox.refresh} disabled={inbox.loading} title="Refresh inbox summary">
          <RefreshCw size={13} className={inbox.loading ? 'spin' : ''} />
        </button>
      </div>
      <div className="scroll col" style={{ gap: 8, flex: 1 }}>
        {inbox.error && <div className="row" style={{ fontSize: 11, color: 'var(--orange)', gap: 6 }}><AlertCircle size={12} />{inbox.error}</div>}
        {!keys.anthropic && <EmptyHint text={`Add your Anthropic API key so ${name} can summarise your inbox.`} />}
        {inbox.loading && !d && <EmptyHint text={`${name} is reading your inbox…`} />}
        {d && (
          <>
            <div className="secondary" style={{ fontSize: 12 }}>{d.overview}</div>
            {d.needsReply.length > 0 && <div className="muted" style={{ fontSize: 11, fontWeight: 600 }}>Needs a reply</div>}
            {d.needsReply.map((i) => <MailRow key={i.messageID} item={i} tint="var(--pink)" multi={multi} />)}
            {d.important.length > 0 && <div className="muted" style={{ fontSize: 11, fontWeight: 600 }}>Worth knowing</div>}
            {d.important.map((i) => <MailRow key={i.messageID} item={i} tint="var(--cyan)" multi={multi} />)}
            <div className="muted" style={{ fontSize: 10 }}>{d.scanned} emails scanned · {d.otherCount} routine · updated {relativeTime(new Date(d.generatedAt))}</div>
          </>
        )}
      </div>
    </Card>
  )
}

function MailRow({ item, tint, multi }: { item: MailItem; tint: string; multi: boolean }) {
  return (
    <button className="row inner" title={item.subject} onClick={() => window.orbit.openExternal(mailLink(item))}
      style={{ alignItems: 'flex-start', gap: 10, padding: 8, textAlign: 'left', width: '100%' }}>
      <span style={{ width: 8, height: 8, borderRadius: '50%', background: tint, marginTop: 5, flex: 'none' }} />
      <div style={{ minWidth: 0, flex: 1 }}>
        <div className="row" style={{ gap: 6 }}>
          <strong className="clamp1" style={{ fontSize: 12 }}>{item.from}</strong>
          {multi && <span className="muted" style={{ fontSize: 9, fontWeight: 600, padding: '1px 5px', borderRadius: 999, border: '1px solid var(--line)' }}>{item.account.split('@')[0]}</span>}
        </div>
        <div className="secondary clamp2" style={{ fontSize: 12 }}>{item.note}</div>
      </div>
      <ArrowUpRight size={11} className="muted" style={{ flex: 'none' }} />
    </button>
  )
}

export function AddTaskInline() {
  const [text, setText] = useState('')
  const add = () => {
    const t = parseQuick(text)
    if (!t.title) return
    store.create<Task>('task', { title: t.title, notes: '', area: t.area, due: iso(t.due ?? startOfDay(new Date())), priority: t.priority, isDone: false, completedAt: null, createdAt: iso(new Date()), repeat: 'none' })
    setText('')
  }
  return (
    <div className="row inner" style={{ padding: '8px 12px' }}>
      <Plus size={14} className="muted" />
      <input className="plain" style={{ fontSize: 13 }} placeholder="Add a task for today" value={text}
        onChange={(e) => setText(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') add() }} />
    </div>
  )
}

/** Small offline parser: #area, ! priority, today / tomorrow / weekday names. */
export function parseQuick(raw: string): { title: string; area: Area; priority: number; due: Date | null } {
  let text = raw.trim()
  let area: Area = 'personal'
  let priority = 0
  let due: Date | null = null
  const tag = text.match(/#(\w+)/)
  if (tag) {
    const a = AREAS.find((x) => x.startsWith(tag[1].toLowerCase()))
    if (a) { area = a; text = text.replace(tag[0], '') }
  }
  const bang = text.match(/(^|\s)(!{1,3})(?=\s|$)/)
  if (bang) { priority = bang[2].length; text = text.replace(bang[0], ' ') }
  const today = startOfDay(new Date())
  const words: [RegExp, () => Date][] = [
    [/\btoday\b/i, () => today],
    [/\btomorrow\b/i, () => addDays(today, 1)],
    [/\bnext week\b/i, () => addDays(today, 7)],
  ]
  for (const [re, f] of words) if (re.test(text)) { due = f(); text = text.replace(re, ''); break }
  if (!due) {
    const names = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']
    const m = text.match(/\b(sun|mon|tue|wed|thu|fri|sat)[a-z]*\b/i)
    if (m) {
      const target = names.indexOf(m[1].toLowerCase())
      due = addDays(today, ((target - today.getDay() + 7) % 7) || 7)
      text = text.replace(m[0], '')
    }
  }
  const title = text.replace(/\s+(on|by|at)\s*$/i, '').replace(/\s+/g, ' ').trim()
  return { title, area, priority, due }
}
