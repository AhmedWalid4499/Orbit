// Today on a phone (the iPhone's PhoneToday): the Windows dashboard's cards, one column, scrolling.
import { useMemo } from 'react'
import { Timer, Moon, TrendingUp } from 'lucide-react'
import type { Nav } from '@/App'
import { useRecords, useSetting } from '@/lib/store'
import { FocusSession, DayPlan, Task, CalEvent, Habit, Txn, Note, Book, Bucket } from '@/lib/models'
import { parse, startOfDay, addDays, isToday, sameDay, dayKey, startOfMonth, fmtDay, fmtTime, relativeTime } from '@/lib/dates'
import { useExternalEvents, externalEvents, ExternalEvent } from '@/lib/externalEvents'
import { Card, SectionHeader, EmptyHint, useMoney } from '@/components/ui'
import { TaskRow } from '@/components/TaskRow'
import { BookCover } from '@/screens/Reading'
import { useKeys } from '@/lib/ai'
import { useInbox } from '@/lib/inbox'
import { openFocus, focusToday } from '@/lib/focus'
import { planFor, todayKey } from '@/lib/dayPlan'
import { TopThreeCard, PlanTomorrowCard } from '@/screens/PlanTomorrow'
import UpNext from '../components/UpNext'
import CheckInCard from '../components/CheckInCard'
import DaySummaryCard from '../components/DaySummaryCard'
import { AgendaRow, HabitChip, LookingForward, MoodCard, ClockWeather, QuickAdd, BriefCard, InboxCard, AddTaskInline } from '@/screens/Today'

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
  const inbox = useInbox(keys.gmail, keys.anthropic)
  const today = startOfDay(new Date())
  const tomorrow = addDays(today, 1)

  const dueToday = useMemo(() => tasks
    .filter((t) => !t.data.isDone && t.data.due && parse(t.data.due)! < tomorrow)
    .sort((a, b) => b.data.priority - a.data.priority || (parse(a.data.due)!.getTime() - parse(b.data.due)!.getTime())), [tasks])
  const agenda = events.filter((e) => sameDay(parse(e.data.start)!, today)).sort((a, b) => a.data.start.localeCompare(b.data.start))
  const tomorrowEvents = events.filter((e) => sameDay(parse(e.data.start)!, tomorrow)).sort((a, b) => a.data.start.localeCompare(b.data.start))
  const spent = -txns.filter((t) => t.data.amount < 0 && parse(t.data.date)! >= startOfMonth(today)).reduce((s, t) => s + t.data.amount, 0)
  const readThisYear = books.filter((b) => b.data.status === 'read' && parse(b.data.finishedAt)?.getFullYear() === today.getFullYear()).length
  const journal = notes.find((n) => n.data.isJournal && isToday(parse(n.data.createdAt) ?? new Date(0)))
  const reading = books.find((b) => b.data.status === 'reading')
  const hour = new Date().getHours()
  const greeting = `${hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening'}${userName ? `, ${userName.split(' ')[0]}` : ''}.`
  const next = agenda.find((e) => parse(e.data.start)! > new Date())
  const overdue = tasks.filter((t) => !t.data.isDone && t.data.due && parse(t.data.due)! < today).length
  const minutes = focusToday(focus)
  useExternalEvents()
  const google = externalEvents(today, tomorrow)

  return (
    <div className="page col phone-today" style={{ gap: 14 }}>
      {/* Like the iPhone: greeting and date, the weather, actions, quick add, then four small numbers */}
      <div className="col" style={{ gap: 2 }}>
        <div style={{ fontSize: 17, fontWeight: 700 }}>{greeting.replace(/\.$/, '')}</div>
        <div className="secondary" style={{ fontSize: 13 }}>
          {fmtDay(today)}{next ? ` · Next: ${next.data.title} ${relativeTime(parse(next.data.start)!)}` : ''}{overdue > 0 && ` · ${overdue} overdue`}
        </div>
      </div>
      <div className="today-clock"><ClockWeather /></div>
      <div className="row today-actions">
        <button onClick={nav.openReview}><TrendingUp size={14} />Week</button>
        <button onClick={nav.openPlan}><Moon size={14} />Plan tomorrow</button>
        <button onClick={() => openFocus(null)}><Timer size={14} />Focus{minutes > 0 && ` · ${minutes}m`}</button>
      </div>
      <div className="today-clock"><QuickAdd /></div>

      <div className="today-glance">
        <Mini value={String(dueToday.length)} label="Due" color="var(--peach)" onClick={() => nav.go('tasks')} />
        <Mini value={`${habits.filter((h) => h.data.doneDays.includes(dayKey(today))).length}/${habits.length}`} label="Habits" color="var(--lime)" onClick={() => nav.go('habits')} />
        <Mini value={new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 1 }).format(Math.max(budget - spent, 0))} label="Left" color="var(--cyan)" onClick={() => nav.go('money')} />
        <Mini value={`${readThisYear}/${goal}`} label="Books" color="var(--purple)" onClick={() => nav.go('reading')} />
      </div>

      <BriefCard hasKey={keys.anthropic} />
      {todayPlan && todayPlan.data.top.length > 0 && <TopThreeCard plan={todayPlan} onPlan={nav.openPlan} />}

      <UpNext onTasks={() => nav.go('tasks')} onCalendar={() => nav.go('calendar')} />

      <Card className="col" padding={14}>
        <SectionHeader title="Habits" trailing={habits.length ? 'View all' : 'Add habit'} onTrailing={() => nav.go('habits')} />
        {habits.length === 0 ? <EmptyHint text="Build a streak: add your first habit." /> : (
          <div className="row" style={{ gap: 8, overflowX: 'auto' }}>{habits.map((h) => <HabitChip key={h.id} h={h} />)}</div>
        )}
      </Card>

      <CheckInCard onOpenJournal={nav.openJournal} />
      {hour >= 17 && <DaySummaryCard />}

      <div className="row" style={{ gap: 12, alignItems: 'stretch' }}>
        <button className="card col" style={{ flex: 1, minWidth: 0, background: 'var(--lime)', color: 'var(--sticker-ink)', padding: 14, gap: 6, textAlign: 'left' }} onClick={() => nav.go('money')}>
          <span style={{ fontSize: 11, fontWeight: 600 }}>Left to spend</span>
          <span className="display clamp1" style={{ fontSize: 20 }}>{money(Math.max(budget - spent, 0))}</span>
          <div style={{ height: 6, background: 'rgba(0,0,0,0.12)', borderRadius: 3 }}>
            <div style={{ height: 6, width: `${Math.min(100, budget > 0 ? (spent / budget) * 100 : 0)}%`, background: '#111', borderRadius: 3 }} />
          </div>
          <span style={{ fontSize: 10, opacity: 0.7 }}>of {money(budget)}</span>
        </button>
        <MoodCard journal={journal} onOpen={nav.openJournal} />
      </div>

      <button className="card row" style={{ padding: 12, textAlign: 'left' }} onClick={() => nav.go('reading')}>
        {reading ? (
          <>
            <div style={{ width: 40, height: 60, flex: 'none' }}><BookCover book={reading.data} /></div>
            <div className="col" style={{ gap: 4, flex: 1, minWidth: 0 }}>
              <span className="muted" style={{ fontSize: 10, fontWeight: 600 }}>Reading</span>
              <strong className="clamp1" style={{ fontSize: 14 }}>{reading.data.title}</strong>
              <div style={{ height: 5, background: 'var(--line)', borderRadius: 3 }}>
                <div style={{ height: 5, width: `${Math.max(4, reading.data.progress * 100)}%`, background: 'var(--ink)', borderRadius: 3 }} />
              </div>
              <span className="secondary" style={{ fontSize: 11 }}>{Math.round(reading.data.progress * 100)}% · {readThisYear} of {goal} books this year</span>
            </div>
          </>
        ) : <strong style={{ fontSize: 14 }}>{readThisYear} of {goal} books this year</strong>}
      </button>

      {keys.gmail.length > 0 && <InboxCard accounts={keys.gmail} inbox={inbox} />}
      {hour >= 17 ? <PlanTomorrowCard onPlan={nav.openPlan} /> : (
        <Card className="col" padding={14}>
          <SectionHeader title="Looking forward to" trailing="Bucket list" onTrailing={() => nav.go('bucket')} />
          <LookingForward dreams={dreams} />
        </Card>
      )}
    </div>
  )
}

function Mini({ value, label, color, onClick }: { value: string; label: string; color: string; onClick: () => void }) {
  return (
    <button className="mini" style={{ background: color }} onClick={onClick}>
      <span className="display clamp1">{value}</span>
      <span>{label}</span>
    </button>
  )
}

/** A Google Calendar event in the agenda, coloured like its calendar. */
function GoogleRow({ g }: { g: ExternalEvent }) {
  const now = new Date()
  return (
    <div className="row inner" style={{ padding: 10, gap: 12, opacity: g.end < now ? 0.5 : 1 }}>
      <div style={{ width: 60, textAlign: 'right', flex: 'none', fontSize: 12, fontWeight: 600 }}>
        {g.allDay ? 'All day' : <>{fmtTime(g.start)}<div className="muted" style={{ fontSize: 10, fontWeight: 400 }}>{fmtTime(g.end)}</div></>}
      </div>
      <span style={{ width: 4, height: 30, borderRadius: 2, background: g.color, flex: 'none' }} />
      <span className="clamp1" style={{ flex: 1, fontWeight: 500, fontSize: 13 }}>{g.title}</span>
      <span className="muted clamp1" style={{ fontSize: 11, maxWidth: 90 }}>{g.calendar}</span>
    </div>
  )
}
