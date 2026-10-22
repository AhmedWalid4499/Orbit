// Weekly review and mood insights, ported from WeeklyReview.swift (Mac).
// The numbers are computed here; Claude only puts them into words (and may not add new claims).
import { store } from './store'
import { structured } from './ai'
import { moneyFmt } from './snapshot'
import { Task, Habit, Txn, Note, Book, ReadingSession, Bucket, CalEvent, FocusSession, AREAS, sessionMinutes } from './models'
import { focusMinutes } from './focus'
import { parse, startOfDay, startOfWeek, startOfMonth, addDays, dayKey, sameDay } from './dates'

export interface WeekStats {
  start: Date
  end: Date
  tasksDone: string[]
  overdue: number
  habits: { name: string; done: number; target: number }[]
  spent: number
  topCategories: [string, number][]
  monthSpent: number
  budget: number
  moods: { day: Date; mood: number }[]
  booksFinished: string[]
  readingMinutes: number
  focusMinutes: number
  events: number
  bucketDone: string[]
}

const short = (d: Date) => d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
export const weekLabel = (s: WeekStats): string => `${short(s.start)} – ${short(addDays(s.end, -1))}`

export function computeWeek(weekContaining: Date = new Date()): WeekStats {
  const start = startOfWeek(weekContaining), end = addDays(start, 7)
  const inWeek = (v: string | null | undefined): boolean => { const d = parse(v); return !!d && d >= start && d < end }
  const tasks = store.list<Task>('task'), habits = store.list<Habit>('habit'), txns = store.list<Txn>('transaction')
  const notes = store.list<Note>('note').filter((n) => n.data.isJournal)
  const books = store.list<Book>('book'), sessions = store.list<ReadingSession>('readingSession')
  const bucket = store.list<Bucket>('bucket'), events = store.list<CalEvent>('event')
  const today = startOfDay(new Date())

  const expenses = txns.filter((t) => t.data.amount < 0 && inWeek(t.data.date))
  const byCat = new Map<string, number>()
  for (const t of expenses) byCat.set(t.data.category, (byCat.get(t.data.category) ?? 0) - t.data.amount)
  const monthStart = startOfMonth(weekContaining)
  return {
    start, end,
    tasksDone: tasks.filter((t) => t.data.isDone && inWeek(t.data.completedAt)).map((t) => t.data.title),
    overdue: tasks.filter((t) => !t.data.isDone && t.data.due && parse(t.data.due)! < today).length,
    habits: habits.map((h) => ({
      name: h.data.name,
      done: Array.from({ length: 7 }, (_, i) => dayKey(addDays(start, i))).filter((k) => (h.data.doneDays ?? []).includes(k)).length,
      target: h.data.targetPerWeek,
    })),
    spent: -expenses.reduce((n, t) => n + t.data.amount, 0),
    topCategories: [...byCat].sort((a, b) => b[1] - a[1]).slice(0, 3),
    monthSpent: -txns.filter((t) => t.data.amount < 0 && (parse(t.data.date) ?? new Date(0)) >= monthStart).reduce((n, t) => n + t.data.amount, 0),
    budget: Number(store.setting<number>('monthlyBudget') ?? 2000) || 0,
    moods: notes.filter((n) => n.data.mood > 0 && inWeek(n.data.createdAt))
      .map((n) => ({ day: startOfDay(parse(n.data.createdAt)!), mood: n.data.mood }))
      .sort((a, b) => a.day.getTime() - b.day.getTime()),
    booksFinished: books.filter((b) => b.data.status === 'read' && inWeek(b.data.finishedAt)).map((b) => b.data.title),
    readingMinutes: Math.floor(sessions.filter((s) => inWeek(s.data.start)).reduce((n, s) => n + sessionMinutes(s.data), 0)),
    focusMinutes: Math.floor(store.list<FocusSession>('focusSession').filter((s) => inWeek(s.data.start)).reduce((n, s) => n + focusMinutes(s.data), 0)),
    events: events.filter((e) => inWeek(e.data.start)).length,
    bucketDone: bucket.filter((b) => b.data.isDone && inWeek(b.data.doneAt)).map((b) => b.data.title),
  }
}

export function weekAsText(s: WeekStats): string {
  const wd = (d: Date) => d.toLocaleDateString('en', { weekday: 'short' })
  return [
    `Week ${weekLabel(s)}.`,
    `Tasks completed (${s.tasksDone.length}): ${s.tasksDone.slice(0, 25).join('; ')}`,
    `Overdue now: ${s.overdue}`,
    `Habits: ${s.habits.length ? s.habits.map((h) => `${h.name} ${h.done}/${h.target}`).join(', ') : 'none'}`,
    `Spent this week: ${moneyFmt(s.spent)}; top: ${s.topCategories.map(([c, v]) => `${c} ${moneyFmt(v)}`).join(', ')}`,
    `Month so far: ${moneyFmt(s.monthSpent)} of ${moneyFmt(s.budget)} budget`,
    `Mood (1-5) by day: ${s.moods.length ? s.moods.map((m) => `${wd(m.day)} ${m.mood}`).join(', ') : 'not recorded'}`,
    `Focus time: ${s.focusMinutes} min`,
    `Reading: ${s.readingMinutes} min; finished: ${s.booksFinished.length ? s.booksFinished.join(', ') : 'none'}`,
    `Events: ${s.events}. Bucket list ticked off: ${s.bucketDone.length ? s.bucketDone.join(', ') : 'none'}`,
  ].join('\n')
}

// MARK: Reflection (Claude)

export interface Focus { title: string; area: string; why: string }
export interface WeeklyReflection { headline: string; wins: string[]; struggles: string[]; insight: string; focus: Focus[] }

const reviewKey = (week: Date) => `orbit.weeklyReview-${dayKey(startOfWeek(week))}`

export function cachedReflection(week: Date): WeeklyReflection | null {
  try { return JSON.parse(localStorage.getItem(reviewKey(week)) ?? 'null') } catch { return null }
}

const assistantName = () => (store.setting<string>('assistantName') ?? '').trim() || 'Ask'

const REFLECTION_SCHEMA = {
  type: 'object',
  properties: {
    headline: { type: 'string' },
    wins: { type: 'array', items: { type: 'string' } },
    struggles: { type: 'array', items: { type: 'string' } },
    insight: { type: 'string' },
    focus: {
      type: 'array',
      items: {
        type: 'object',
        properties: { title: { type: 'string' }, area: { type: 'string', enum: AREAS }, why: { type: 'string' } },
        required: ['title', 'area', 'why'], additionalProperties: false,
      },
    },
  },
  required: ['headline', 'wins', 'struggles', 'insight', 'focus'],
  additionalProperties: false,
}

export async function reflect(s: WeekStats): Promise<WeeklyReflection> {
  const system = `You are ${assistantName()}, writing the user's weekly review in their personal organizer. Use only the data given.
- headline: one warm sentence capturing the week.
- wins: up to 3 specific things that went well (name tasks, habits, books).
- struggles: up to 2 honest, kind observations about what slipped. Empty if nothing did.
- insight: one sentence connecting two things in the data (e.g. mood and habits), only if the data supports it.
- focus: exactly 3 concrete, small focus items for next week, each a doable task title (under 8 words), an area, and a short why.
Plain text, no markdown. Encouraging, never preachy.`
  const r = await structured<WeeklyReflection>(system, weekAsText(s), REFLECTION_SCHEMA, 'medium')
  localStorage.setItem(reviewKey(s.start), JSON.stringify(r))
  return r
}

// MARK: Mood insights

export interface MoodPoint { day: Date; mood: number }
export interface MoodFact { text: string; delta: number }
export interface LifePattern { title: string; detail: string }

/** Journal mood per day for the last `days` days. */
export function moodSeries(days = 90): MoodPoint[] {
  const since = addDays(startOfDay(new Date()), -days)
  const byDay = new Map<string, MoodPoint>()
  for (const n of store.list<Note>('note')) {
    const d = parse(n.data.createdAt)
    if (!n.data.isJournal || !(n.data.mood > 0) || !d || d < since) continue
    byDay.set(dayKey(d), { day: startOfDay(d), mood: n.data.mood })
  }
  return [...byDay.values()].sort((a, b) => a.day.getTime() - b.day.getTime())
}

/** Average mood per weekday (0 = Sunday). */
export function moodByWeekday(points: MoodPoint[]): { weekday: number; mood: number; count: number }[] {
  const g = new Map<number, number[]>()
  for (const p of points) g.set(p.day.getDay(), [...(g.get(p.day.getDay()) ?? []), p.mood])
  return [...g].map(([weekday, ms]) => ({ weekday, mood: ms.reduce((a, b) => a + b, 0) / ms.length, count: ms.length })).sort((a, b) => a.weekday - b.weekday)
}

/** Mood differences worth mentioning: habits done vs not, spending, busy days, reading. Needs 3+ days on each side. */
export function moodFacts(points: MoodPoint[]): MoodFact[] {
  if (points.length < 5) return []
  const out: MoodFact[] = []
  const avg = (xs: MoodPoint[]) => xs.reduce((n, p) => n + p.mood, 0) / Math.max(xs.length, 1)
  const compare = (label: string, yes: MoodPoint[], no: MoodPoint[], yesName: string, noName: string) => {
    if (yes.length < 3 || no.length < 3) return
    const d = avg(yes) - avg(no)
    if (Math.abs(d) < 0.3) return
    out.push({ text: `${label}: average mood ${avg(yes).toFixed(1)} on ${yesName} (${yes.length} days) vs ${avg(no).toFixed(1)} on ${noName} (${no.length} days).`, delta: Math.abs(d) })
  }

  for (const h of store.list<Habit>('habit')) {
    const done = (p: MoodPoint) => (h.data.doneDays ?? []).includes(dayKey(p.day))
    compare(`Habit “${h.data.name}”`, points.filter(done), points.filter((p) => !done(p)), 'days it was done', "days it wasn't")
  }
  const txns = store.list<Txn>('transaction').filter((t) => t.data.amount < 0)
  const spentByDay = new Map<string, number>()
  for (const t of txns) { const d = parse(t.data.date); if (d) spentByDay.set(dayKey(d), (spentByDay.get(dayKey(d)) ?? 0) - t.data.amount) }
  const spentOn = (p: MoodPoint) => spentByDay.get(dayKey(p.day)) ?? 0
  const spends = points.map(spentOn).sort((a, b) => a - b)
  const median = spends.length ? spends[Math.floor(spends.length / 2)] : 0
  if (median > 0) {
    compare('Spending', points.filter((p) => spentOn(p) > median), points.filter((p) => spentOn(p) <= median),
      `higher-spending days (over ${moneyFmt(median)})`, 'lower-spending days')
  }
  const foodDays = new Set(txns.filter((t) => t.data.category === 'Food').map((t) => parse(t.data.date)).filter((d): d is Date => !!d).map(dayKey))
  compare('Food spending', points.filter((p) => foodDays.has(dayKey(p.day))), points.filter((p) => !foodDays.has(dayKey(p.day))),
    'days with food purchases', 'days without')
  const events = store.list<CalEvent>('event')
  const eventCount = (d: Date) => events.filter((e) => { const s = parse(e.data.start); return !!s && sameDay(s, d) }).length
  compare('Busy days', points.filter((p) => eventCount(p.day) >= 3), points.filter((p) => eventCount(p.day) < 3), 'days with 3+ events', 'quieter days')
  const readDays = new Set(store.list<ReadingSession>('readingSession').map((s) => parse(s.data.start)).filter((d): d is Date => !!d).map(dayKey))
  compare('Reading', points.filter((p) => readDays.has(dayKey(p.day))), points.filter((p) => !readDays.has(dayKey(p.day))), 'days you read', "days you didn't")
  const doneByDay = new Map<string, number>()
  for (const t of store.list<Task>('task')) { const d = parse(t.data.completedAt); if (d) doneByDay.set(dayKey(d), (doneByDay.get(dayKey(d)) ?? 0) + 1) }
  const doneOn = (p: MoodPoint) => doneByDay.get(dayKey(p.day)) ?? 0
  compare('Getting things done', points.filter((p) => doneOn(p) >= 3), points.filter((p) => doneOn(p) < 3), 'days you finished 3+ tasks', 'other days')
  return out.sort((a, b) => b.delta - a.delta)
}

export function cachedPatterns(): LifePattern[] {
  try { return JSON.parse(localStorage.getItem('orbit.lifePatterns') ?? '[]') } catch { return [] }
}

/** Claude turns the measured patterns into plain-language insights (it may not add new claims). */
export async function explainFacts(facts: MoodFact[]): Promise<LifePattern[]> {
  const schema = {
    type: 'object',
    properties: { patterns: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, detail: { type: 'string' } }, required: ['title', 'detail'], additionalProperties: false } } },
    required: ['patterns'], additionalProperties: false,
  }
  const system = `You turn measured patterns from someone's own life data into up to 4 short insights for them.
Use ONLY the facts given; never invent numbers. Prefer the strongest and most useful ones; mention how many days the pattern is based on when it's small.
title: under 9 words, like "You're happier on gym days". detail: 1 sentence with the numbers and a gentle, practical suggestion.
These are correlations, not proof: don't claim causes.`
  const out = await structured<{ patterns: LifePattern[] }>(system, facts.map((f) => f.text).join('\n'), schema, 'low')
  localStorage.setItem('orbit.lifePatterns', JSON.stringify(out.patterns))
  return out.patterns
}

