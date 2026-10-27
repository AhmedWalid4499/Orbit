// Today › Your day (DaySummaryCard.swift + DaySummary.swift): the assistant's live summary of where your day stands,
// rewritten when your data changes (at most every 20 minutes unless forced). Compact, as on the iPhone. Cached like the Mac.
import { useEffect, useMemo, useSyncExternalStore } from 'react'
import { Sunset, RefreshCw, Lightbulb, AlertTriangle, CreditCard, BookOpen, ListChecks, CalendarDays, Flame, Timer, Smile, Plane, MapPin, Sparkles } from 'lucide-react'
import { store, useRecords } from '@/lib/store'
import { Task, Txn, Habit, Book, ReadingSession, FocusSession, CalEvent, Note, Trip, Bucket } from '@/lib/models'
import { parse, startOfDay, addDays, startOfWeek, startOfMonth, dayKey, isToday, daysBetween, fmtTime } from '@/lib/dates'
import { structured, useKeys, useAssistantName } from '@/lib/ai'
import { daySnapshot, moneyFmt } from '@/lib/snapshot'
import { minutesSince, readingStreak } from '@/lib/readingTimer'
import { minutesFocusedSince } from '@/lib/focus'
import { useExternalEvents, externalEvents } from '@/lib/externalEvents'
import { defaultCurrency } from '@/components/ui'

interface Tile { kind: string; title: string; value: string; detail: string }
interface DaySummary { line: string; tiles: Tile[]; nudge: string; day: string; fingerprint: string; generatedAt: string }

// MARK: Store (DaySummaryStore), shared by every card on screen

const CACHE = 'daySummaryCache'
let state: { summary: DaySummary | null; loading: boolean; error: string } = { summary: load(), loading: false, error: '' }
const subs = new Set<() => void>()
const set = (patch: Partial<typeof state>) => { state = { ...state, ...patch }; subs.forEach((f) => f()) }

function load(): DaySummary | null {
  try { return JSON.parse(localStorage.getItem(CACHE) ?? 'null') } catch { return null }
}

/** Rewrites the summary when something changed since the last one (or when forced). */
async function refreshIfNeeded(assistant: string, force = false): Promise<void> {
  if (state.loading) return
  const print = fingerprint()
  const s = state.summary
  if (!force && s && s.day === dayKey(new Date())) {
    if (s.fingerprint === print) return
    if (Date.now() - (parse(s.generatedAt)?.getTime() ?? 0) < 20 * 60_000) return
  }
  set({ loading: true, error: '' })
  const name = (store.setting<string>('userName') ?? '').split(' ')[0] || 'the user'
  const time = new Date().toLocaleTimeString('en', { hour: 'numeric', minute: '2-digit' })
  const system = `You write the "Your day" panel on the Today screen of ${name}'s life-organizer app. It's a live picture of their day so far, rewritten every time something changes, so describe where things stand right now (it's ${time}).
Use only the data given; never invent numbers, books, events or places. Sound like a friend glancing at their day, not a report.
- line: one short, human sentence on how the day is going (max 16 words). No greeting like "Good morning".
- tiles: 4 to 6, the most useful right now, in this order of preference when they have something to say: money (what they've spent today, with the biggest merchant, and how the month is pacing), reading (the book they're on and how far, minutes read today), tasks (done vs left today, the next important one), calendar (what's next and when), habits (what's left today), focus (minutes today), mood (from today's journal), trips (an upcoming trip), places (a Go to place worth trying). Skip a tile when there's nothing meaningful.
  title: 1-3 words. value: the key fact, short (max 22 characters, e.g. "EGP 350 today", "62% · Atomic Habits", "3 of 5 done"). detail: one short line of context or a tip (max 60 characters).
- nudge: one gentle, specific suggestion for the next few hours, or "" if nothing stands out.
Plain text only. Use the home currency ${store.setting<string>('currencyCode') ?? defaultCurrency()}.`
  const schema = {
    type: 'object',
    properties: {
      line: { type: 'string' },
      tiles: { type: 'array', items: {
        type: 'object',
        properties: {
          kind: { type: 'string', enum: ['money', 'reading', 'tasks', 'calendar', 'habits', 'focus', 'mood', 'trips', 'places', 'other'] },
          title: { type: 'string' }, value: { type: 'string' }, detail: { type: 'string' },
        },
        required: ['kind', 'title', 'value', 'detail'], additionalProperties: false,
      } },
      nudge: { type: 'string' },
    },
    required: ['line', 'tiles', 'nudge'], additionalProperties: false,
  }
  try {
    const r = await structured<{ line: string; tiles: Tile[]; nudge: string }>(system, daySnapshot() + '\n' + extra(), schema, 'low', 3000)
    const summary: DaySummary = { ...r, day: dayKey(new Date()), fingerprint: print, generatedAt: new Date().toISOString() }
    try { localStorage.setItem(CACHE, JSON.stringify(summary)) } catch { /* private mode */ }
    set({ summary, loading: false })
  } catch (e) {
    set({ loading: false, error: e instanceof Error ? e.message : String(e) })
  }
}

/** The book you're reading now: status "reading", most recently read first (BookLibrary.currentlyReading). */
function currentlyReading(): Book[] {
  const sessions = store.list<ReadingSession>('readingSession')
  const lastRead = (id: string) => Math.max(0, ...sessions.filter((s) => s.data.bookUUID === id).map((s) => parse(s.data.start)?.getTime() ?? 0))
  return store.list<Book>('book').filter((b) => b.data.status === 'reading')
    .sort((a, b) => lastRead(b.id) - lastRead(a.id) || (parse(b.data.startedAt)?.getTime() ?? 0) - (parse(a.data.startedAt)?.getTime() ?? 0))
    .map((b) => b.data)
}

/** What the summary depends on; when it changes, the summary is rewritten. */
function fingerprint(): string {
  const today = startOfDay(new Date()), tomorrow = addDays(today, 1), now = new Date()
  const txns = store.list<Txn>('transaction').filter((t) => (parse(t.data.date) ?? new Date(0)) >= today)
  const tasks = store.list<Task>('task')
  const habits = store.list<Habit>('habit')
  const events = [
    ...store.list<CalEvent>('event').map((e) => parse(e.data.start)).filter((d): d is Date => !!d && d >= today && d < tomorrow),
    ...externalEvents(today, tomorrow).map((g) => g.start),
  ]
  return 'v2|' + [
    `${txns.length}:${Math.trunc(txns.reduce((s, t) => s + t.data.amount, 0))}`,
    `${tasks.filter((t) => t.data.isDone).length}/${tasks.length}`,
    `${habits.filter((h) => h.data.doneDays.includes(dayKey(today))).length}`,
    currentlyReading().map((b) => `${b.title}${Math.round(b.progress * 100)}`).join(','),
    `${minutesSince(store.list<ReadingSession>('readingSession'), today)}`,
    `${minutesFocusedSince(store.list<FocusSession>('focusSession'), today)}`,
    `${events.length}`,
    `${events.filter((d) => d > now).length}`, // the next event changes as the day goes on
  ].join('|')
}

/** Data the day snapshot doesn't carry: today's spending, reading, focus, mood, trips and places. */
function extra(): string {
  const now = new Date(), today = startOfDay(now), tomorrow = addDays(today, 1)
  const lines: string[] = []
  const txns = store.list<Txn>('transaction').map((t) => ({ ...t.data, d: parse(t.data.date) ?? new Date(0) }))
  const spent = txns.filter((t) => t.d >= today && t.d < tomorrow && t.amount < 0)
  lines.push(`\nSpent today: ${moneyFmt(-spent.reduce((s, t) => s + t.amount, 0))} in ${spent.length} payments`)
  lines.push(...spent.sort((a, b) => a.amount - b.amount).slice(0, 6).map((t) => `- ${t.title}: ${moneyFmt(-t.amount)} [${t.category}]`))
  const budgets = Object.entries(store.setting<Record<string, number>>('categoryBudgets') ?? {}).filter(([, v]) => Number(v) > 0)
  if (budgets.length) {
    const month = txns.filter((t) => t.amount < 0 && t.d >= startOfMonth(now))
    lines.push('Category budgets this month: ' + budgets.map(([c, limit]) =>
      `${c} ${moneyFmt(-month.filter((t) => t.category === c).reduce((s, t) => s + t.amount, 0))} of ${moneyFmt(limit)}`).join('; '))
  }

  const sessions = store.list<ReadingSession>('readingSession')
  const books = currentlyReading()
  if (books[0]) {
    const b = books[0]
    lines.push(`\nThe book they're reading now (use this one for the reading tile): ${b.title} by ${b.author}, ${Math.round(b.progress * 100)}%${b.pageCount > 0 ? ` of ${b.pageCount} pages` : ''}`)
    if (books.length > 1) lines.push('Also on the Currently reading shelf: ' + books.slice(1, 4).map((x) => x.title).join(', '))
  } else {
    lines.push('\nReading now: (nothing)')
  }
  lines.push(`Minutes read today: ${minutesSince(sessions, today)}; this week: ${minutesSince(sessions, startOfWeek(now))}; streak ${readingStreak(sessions)} days`)
  lines.push(`\nFocus today: ${minutesFocusedSince(store.list<FocusSession>('focusSession'), today)} minutes`)

  const google = externalEvents(today, tomorrow)
  if (google.length) {
    lines.push('\nAlso on Google Calendar today:', ...google.map((g) => `- ${g.allDay ? 'All day' : `${fmtTime(g.start)}-${fmtTime(g.end)}`} ${g.title}`))
  }

  const journal = store.list<Note>('note').find((n) => n.data.isJournal && isToday(parse(n.data.createdAt) ?? new Date(0)))
  if (journal) lines.push(`\nToday's journal${journal.data.mood > 0 ? ` (mood ${journal.data.mood}/5)` : ''}: ${(journal.data.body ?? '').slice(0, 300)}`)

  const trip = store.list<Trip>('trip').map((t) => ({ ...t.data, s: parse(t.data.start) }))
    .filter((t): t is Trip & { s: Date } => !!t.s && t.s >= today).sort((a, b) => a.s.getTime() - b.s.getTime())[0]
  if (trip) lines.push(`\nNext trip: ${trip.title} in ${daysBetween(today, trip.s)} days`)
  // Go to places are bucket items of kind "place" (the Mac keeps their category under `place`).
  const places = store.list<Bucket & { place?: { category?: string } }>('bucket').filter((b) => (b.data.kind as string) === 'place' && !b.data.isDone)
  if (places.length) lines.push('\nGo to places saved: ' + places.slice(0, 5).map((p) => `${p.data.title}${p.data.place?.category ? ` (${p.data.place.category})` : ''}`).join(', '))
  return lines.join('\n')
}

// MARK: Card

const STYLE: Record<string, [typeof Sparkles, string]> = {
  money: [CreditCard, 'var(--peach)'], reading: [BookOpen, 'var(--purple)'], tasks: [ListChecks, 'var(--lime)'],
  calendar: [CalendarDays, 'var(--cyan)'], habits: [Flame, 'var(--orange)'], focus: [Timer, 'var(--mint)'],
  mood: [Smile, 'var(--pink)'], trips: [Plane, 'var(--cyan)'], places: [MapPin, 'var(--mint)'],
}

export default function DaySummaryCard() {
  const keys = useKeys()
  const name = useAssistantName()
  const { summary, loading, error } = useSyncExternalStore((f) => { subs.add(f); return () => { subs.delete(f) } }, () => state)
  // Watching these makes the card re-check whenever any of them changes.
  const txns = useRecords<Txn>('transaction'), tasks = useRecords<Task>('task')
  const sessions = useRecords<ReadingSession>('readingSession'), focus = useRecords<FocusSession>('focusSession')
  const changeKey = useMemo(() => `${txns.length}-${tasks.filter((t) => t.data.isDone).length}-${sessions.length}-${focus.length}-${keys.anthropic}`,
    [txns, tasks, sessions, focus, keys.anthropic])
  useExternalEvents()

  useEffect(() => {
    if (!keys.anthropic) return
    const t = setTimeout(() => refreshIfNeeded(name), 2000) // let a burst of edits settle
    return () => clearTimeout(t)
  }, [changeKey]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!keys.anthropic) return
    // The day moves on even when nothing is edited: look again every 20 minutes.
    const t = setInterval(() => refreshIfNeeded(name), 20 * 60_000)
    return () => clearInterval(t)
  }, [keys.anthropic, name])

  if (!keys.anthropic) return null
  const current = summary && summary.day === dayKey(new Date()) ? summary : null

  return (
    <div className="card col" style={{ padding: 16, gap: 12, borderRadius: 22, flex: 'none' }}>
      <div className="row" style={{ gap: 8 }}>
        <Sunset size={15} color="var(--orange)" />
        <span className="secondary" style={{ fontSize: 12, fontWeight: 600 }}>Your day</span>
        <span className="spacer" />
        {!loading && current && <span className="muted" style={{ fontSize: 11 }}>Updated {fmtTime(new Date(current.generatedAt))}</span>}
        <button onClick={() => refreshIfNeeded(name, true)} disabled={loading} title="Update now" aria-label="Update now"
          style={{ width: 30, height: 30, borderRadius: '50%', background: 'var(--canvas)', color: 'var(--ink)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
          <RefreshCw size={12} strokeWidth={2.5} style={loading ? { animation: 'orb-spin 1s linear infinite' } : undefined} />
        </button>
      </div>
      {current ? (
        <>
          <div className="display" style={{ fontSize: 18, lineHeight: 1.25 }}>{current.line}</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            {current.tiles.slice(0, 6).map((t, i) => <TileView key={i} t={t} />)}
          </div>
          {current.nudge && (
            <div className="row" style={{ gap: 6, fontSize: 12, fontWeight: 500, alignItems: 'flex-start' }}>
              <Lightbulb size={13} style={{ flex: 'none', marginTop: 1 }} />{current.nudge}
            </div>
          )}
        </>
      ) : loading ? (
        <div className="display secondary" style={{ fontSize: 18, fontWeight: 400 }}>{name} is looking at your day…</div>
      ) : error ? (
        <div className="row" style={{ gap: 6, fontSize: 12, color: 'var(--orange)', alignItems: 'flex-start' }}>
          <AlertTriangle size={13} style={{ flex: 'none', marginTop: 1 }} />{error}
        </div>
      ) : null}
    </div>
  )
}

function TileView({ t }: { t: Tile }) {
  const [Icon, color] = STYLE[t.kind] ?? [Sparkles, '#e9dfc9']
  return (
    <div className="col" style={{ gap: 4, padding: 11, minHeight: 74, minWidth: 0, borderRadius: 14, background: color, color: 'var(--sticker-ink)' }}>
      <span className="row clamp1" style={{ gap: 4, fontSize: 11, fontWeight: 600, opacity: 0.75 }}><Icon size={11} style={{ flex: 'none' }} />{t.title}</span>
      <span className="clamp1" style={{ fontSize: 15, fontWeight: 700 }}>{t.value}</span>
      <span className="clamp2" style={{ fontSize: 11, opacity: 0.75 }}>{t.detail}</span>
    </div>
  )
}
