// Insights (the Mac's InsightsDashboard): this week against last, and the trends behind it, across tasks, focus,
// reading, money, habits and mood. Charts are plain SVG/divs.
import { ReactNode } from 'react'
import { CreditCard, CircleCheck, Timer, Repeat, Smile, CalendarDays, Sparkles } from 'lucide-react'
import { useRecords, useSetting } from '@/lib/store'
import { Task, Txn, Habit, Note, Book, ReadingSession, FocusSession, AREA_COLOR, areaOf, MOOD_FACES, sessionMinutes } from '@/lib/models'
import { parse, startOfDay, startOfWeek, startOfMonth, addDays, addMonths, dayKey } from '@/lib/dates'
import { focusMinutes } from '@/lib/focus'
import { moodSeries, moodByWeekday, moodFacts, cachedPatterns, MoodPoint } from '@/lib/review'
import { Card, EmptyHint, useMoney } from '@/components/ui'

const between = (s: string | null | undefined, from: Date, to: Date) => { const d = parse(s); return !!d && d >= from && d < to }

export default function Insights() {
  const tasks = useRecords<Task>('task').map((r) => r.data)
  const txns = useRecords<Txn>('transaction').map((r) => r.data)
  const habits = useRecords<Habit>('habit').map((r) => r.data).sort((a, b) => (a.createdAt ?? '').localeCompare(b.createdAt ?? ''))
  const focus = useRecords<FocusSession>('focusSession').map((r) => r.data)
  const reading = useRecords<ReadingSession>('readingSession').map((r) => r.data)
  const books = useRecords<Book>('book').map((r) => r.data)
  useRecords<Note>('note') // re-render when the journal changes
  const budget = Number(useSetting<number>('monthlyBudget', 2000)) || 0
  const money = useMoney()

  const today = startOfDay(new Date())
  const weekStart = startOfWeek(new Date()), lastWeek = addDays(weekStart, -7)
  const mood = moodSeries()

  const tasksDone = (from: Date, to: Date) => tasks.filter((t) => t.isDone && between(t.completedAt, from, to)).length
  const focusMin = (from: Date, to: Date) => Math.floor(focus.filter((s) => between(s.start, from, to)).reduce((n, s) => n + focusMinutes(s), 0))
  const readMin = (from: Date, to: Date) => Math.floor(reading.filter((s) => between(s.start, from, to)).reduce((n, s) => n + sessionMinutes(s), 0))
  const spent = (from: Date, to: Date) => -txns.filter((t) => t.amount < 0 && between(t.date, from, to)).reduce((n, t) => n + t.amount, 0)
  const habitDone = (h: Habit, d: Date) => (h.doneDays ?? []).includes(dayKey(d))
  const last30 = Array.from({ length: 30 }, (_, i) => addDays(today, -i))

  // Tiles
  const recentMood = mood.filter((p) => p.day >= addDays(today, -30))
  const avgMood = recentMood.length ? recentMood.reduce((n, p) => n + p.mood, 0) / recentMood.length : null
  const habitTarget = habits.reduce((n, h) => n + (h.targetPerWeek || 7) * 30 / 7, 0)
  const habitRate = habits.length && habitTarget > 0
    ? Math.min(100, Math.floor(habits.reduce((n, h) => n + last30.filter((d) => habitDone(h, d)).length, 0) / habitTarget * 100)) : null
  const weekEnd = addDays(weekStart, 7)
  const [fNow, fLast] = [focusMin(weekStart, weekEnd), focusMin(lastWeek, weekStart)]
  const [rNow, rLast] = [readMin(weekStart, weekEnd), readMin(lastWeek, weekStart)]
  const [sNow, sLast] = [spent(weekStart, weekEnd), spent(lastWeek, weekStart)]
  const [tNow, tLast] = [tasksDone(weekStart, weekEnd), tasksDone(lastWeek, weekStart)]

  // Spending by month (last 6)
  const months = Array.from({ length: 6 }, (_, i) => addMonths(startOfMonth(new Date()), i - 5))
  const monthBars = months.map((m) => {
    const y = spent(m, addMonths(m, 1))
    return { label: m.toLocaleDateString(undefined, { month: 'short' }), value: y, color: budget > 0 && y > budget ? 'var(--orange)' : 'var(--cyan)' }
  })

  // Categories this month
  const byCat = new Map<string, number>()
  for (const t of txns) if (t.amount < 0 && between(t.date, startOfMonth(new Date()), addMonths(startOfMonth(new Date()), 1))) byCat.set(t.category || 'General', (byCat.get(t.category || 'General') ?? 0) - t.amount)
  const CAT_COLORS = ['var(--pink)', 'var(--cyan)', 'var(--lime)', 'var(--orange)', 'var(--purple)', 'var(--mint)']
  const cats = [...byCat].sort((a, b) => b[1] - a[1]).slice(0, 6).map(([cat, total], i) => ({ cat, total, color: CAT_COLORS[i] }))

  // Tasks per week (last 8)
  const weekBars = Array.from({ length: 8 }, (_, i) => addDays(weekStart, -7 * (7 - i))).map((w, i) => ({
    label: i % 2 === 0 ? w.toLocaleDateString(undefined, { day: 'numeric', month: 'short' }) : '',
    value: tasksDone(w, addDays(w, 7)), color: i === 7 ? 'var(--pink)' : 'var(--ink)', opacity: i === 7 ? 1 : 0.75,
  }))

  // Focus and reading per day (last 14)
  const days14 = Array.from({ length: 14 }, (_, i) => addDays(today, i - 13))
  const timeBars = days14.map((d, i) => ({
    label: i % 3 === 1 ? d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' }) : '',
    parts: [{ value: focusMin(d, addDays(d, 1)), color: 'var(--orange)' }, { value: readMin(d, addDays(d, 1)), color: 'var(--purple)' }],
  }))

  // Books finished this year
  const yearStart = new Date(new Date().getFullYear(), 0, 1)
  const bookBars = Array.from({ length: 12 }, (_, i) => addMonths(yearStart, i)).map((m) => ({
    label: m.toLocaleDateString(undefined, { month: 'narrow' }),
    value: books.filter((b) => b.status === 'read' && between(b.finishedAt, m, addMonths(m, 1))).length, color: 'var(--purple)',
  }))
  const booksTotal = bookBars.reduce((n, b) => n + b.value, 0)

  const patterns = cachedPatterns()
  const facts = patterns.length ? [] : moodFacts(mood)

  return (
    <div className="page">
      <div className="col" style={{ gap: 16, paddingBottom: 32 }}>
        <div>
          <h1 className="page-title">Insights</h1>
          <div className="secondary" style={{ fontSize: 13, marginTop: 4 }}>This week compared with last, and the trends behind it.</div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <Tile value={String(tNow)} label="Tasks done" delta={delta(tNow, tLast)} color="var(--pink)" />
          <Tile value={`${fNow} min`} label="Focused" delta={delta(fNow, fLast)} color="var(--orange)" />
          <Tile value={`${rNow} min`} label="Reading" delta={delta(rNow, rLast)} color="var(--purple)" />
          <Tile value={money(sNow)} label="Spent" delta={delta(sNow, sLast, true)} color="var(--cyan)" />
          <Tile value={avgMood === null ? '—' : `${MOOD_FACES[Math.round(avgMood)]} ${avgMood.toFixed(1)}`} label="Mood, 30 days" color="var(--peach)" />
          <Tile value={habitRate === null ? '—' : `${habitRate}%`} label="Habits kept, 30 days" color="var(--lime)" />
        </div>

        <ChartCard title="Spending by month" subtitle={`Last 6 months, against your ${money(budget)} budget`}>
          <Bars bars={monthBars} height={170} rule={budget > 0 ? budget : undefined} format={money} />
        </ChartCard>

        <ChartCard title="Where the money went" subtitle="This month, by category">
          {cats.length === 0 ? <EmptyHint icon={<CreditCard size={14} />} text="No spending this month yet." /> : (
            <div className="row" style={{ gap: 16 }}>
              <Donut slices={cats.map((c) => ({ value: c.total, color: c.color }))} />
              <div className="col" style={{ gap: 6, flex: 1, minWidth: 0 }}>
                {cats.map((c) => (
                  <div key={c.cat} className="row" style={{ gap: 6, fontSize: 12 }}>
                    <span style={{ width: 8, height: 8, borderRadius: '50%', background: c.color, flex: 'none' }} />
                    <span className="clamp1">{c.cat}</span>
                    <span className="spacer" />
                    <span style={{ fontWeight: 600, whiteSpace: 'nowrap' }}>{money(c.total)}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </ChartCard>

        <ChartCard title="Tasks done" subtitle="Per week, last 8 weeks">
          {weekBars.every((b) => b.value === 0) ? <EmptyHint icon={<CircleCheck size={14} />} text="Tick off tasks and your weekly count shows here." />
            : <Bars bars={weekBars} height={160} />}
        </ChartCard>

        <ChartCard title="Focus and reading" subtitle="Minutes per day, last 2 weeks">
          {timeBars.every((b) => b.parts.every((p) => p.value === 0)) ? <EmptyHint icon={<Timer size={14} />} text="Start a focus block or a reading session to see your time here." /> : <>
            <div className="row" style={{ gap: 14, fontSize: 11 }}>
              <Legend color="var(--orange)" label="Focus" /><Legend color="var(--purple)" label="Reading" />
            </div>
            <Stacked bars={timeBars} height={170} />
          </>}
        </ChartCard>

        <ChartCard title="Habits kept" subtitle="Last 30 days, against each habit's weekly target">
          {habits.length === 0 ? <EmptyHint icon={<Repeat size={14} />} text="Add a habit to see how well you keep it." /> : (
            <div className="col" style={{ gap: 9 }}>
              {habits.map((h) => {
                const rate = Math.min(1, last30.filter((d) => habitDone(h, d)).length / Math.max((h.targetPerWeek || 7) * 30 / 7, 1))
                return (
                  <div key={h.name} className="col" style={{ gap: 4 }}>
                    <div className="row" style={{ fontSize: 13 }}>
                      <span className="clamp1" style={{ fontWeight: 500 }}>{h.name}</span><span className="spacer" />
                      <span style={{ fontSize: 12, fontWeight: 600 }}>{Math.floor(rate * 100)}%</span>
                    </div>
                    <div style={{ height: 8, borderRadius: 4, background: 'var(--line)' }}>
                      <div style={{ height: 8, borderRadius: 4, width: `max(6px, ${rate * 100}%)`, background: AREA_COLOR[areaOf(h.area)] }} />
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </ChartCard>

        <ChartCard title="Mood" subtitle="Last 90 days, from your journal">
          {mood.length < 3 ? <EmptyHint icon={<Smile size={14} />} text="Rate your mood in the journal for a few days to see it here." /> : <MoodLine points={mood} />}
        </ChartCard>

        <ChartCard title="Best days" subtitle="Average mood by day of the week">
          <MoodWeekdays points={mood} />
        </ChartCard>

        <ChartCard title="Books finished" subtitle={`${booksTotal} this year`}>
          <Bars bars={bookBars} height={130} />
        </ChartCard>

        <ChartCard title="Patterns" subtitle="Things that go together in your data (not causes)">
          {patterns.length > 0 ? patterns.slice(0, 4).map((p, i) => (
            <div key={i} className="col" style={{ gap: 2 }}>
              <div style={{ fontSize: 13, fontWeight: 600 }}>{p.title}</div>
              <div className="secondary" style={{ fontSize: 12 }}>{p.detail}</div>
            </div>
          )) : facts.length === 0 ? <EmptyHint icon={<Sparkles size={14} />} text="Patterns show up once there are a few weeks of mood, habits and spending." />
            : facts.slice(0, 4).map((f, i) => (
              <div key={i} className="row" style={{ alignItems: 'flex-start', gap: 8, fontSize: 12 }}>
                <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--ink3)', marginTop: 6, flex: 'none' }} />{f.text}
              </div>
            ))}
        </ChartCard>
      </div>
    </div>
  )
}

/** "↑ 20% vs last week", and whether that's good. */
function delta(now: number, before: number, lowerIsBetter = false): [string, boolean] | null {
  if (before <= 0) return now > 0 ? ['New this week', true] : null
  const change = (now - before) / before
  if (Math.abs(change) < 0.05) return ['Same as last week', true]
  return [`${change > 0 ? '↑' : '↓'} ${Math.floor(Math.abs(change) * 100)}% vs last week`, lowerIsBetter ? change < 0 : change > 0]
}

function Tile({ value, label, delta, color }: { value: string; label: string; delta?: [string, boolean] | null; color: string }) {
  return (
    <div style={{ background: color, color: 'var(--sticker-ink)', borderRadius: 18, padding: 14, minWidth: 0 }}>
      <div className="display clamp1" style={{ fontSize: 22 }}>{value}</div>
      <div className="clamp1" style={{ fontSize: 12, fontWeight: 600, opacity: 0.8 }}>{label}</div>
      <div className="clamp1" style={{ fontSize: 11, fontWeight: 600, minHeight: 15, color: delta ? (delta[1] ? '#14532D' : '#7F1D1D') : 'transparent' }}>{delta?.[0] ?? ' '}</div>
    </div>
  )
}

function ChartCard({ title, subtitle, children }: { title: string; subtitle: string; children: ReactNode }) {
  return (
    <Card padding={16}>
      <div className="col" style={{ gap: 10 }}>
        <div>
          <div className="display" style={{ fontSize: 19 }}>{title}</div>
          <div className="muted" style={{ fontSize: 11 }}>{subtitle}</div>
        </div>
        {children}
      </div>
    </Card>
  )
}

const Legend = ({ color, label }: { color: string; label: string }) => (
  <span className="row" style={{ gap: 5 }}><span style={{ width: 8, height: 8, borderRadius: 2, background: color }} />{label}</span>
)

/** Nice round top for an axis. */
function niceMax(v: number): number {
  if (v <= 0) return 1
  const p = Math.pow(10, Math.floor(Math.log10(v)))
  return [1, 2, 2.5, 5, 10].map((m) => m * p).find((m) => m >= v)!
}

const compact = (v: number) => new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 1 }).format(v)

interface Bar { label: string; value: number; color: string; opacity?: number }

/** Vertical bars with a light grid, labels under each bar and an optional dashed rule (e.g. budget). */
function Bars({ bars, height, rule, format }: { bars: Bar[]; height: number; rule?: number; format?: (v: number) => string }) {
  return <Stacked height={height} rule={rule} format={format}
    bars={bars.map((b) => ({ label: b.label, parts: [{ value: b.value, color: b.color, opacity: b.opacity }] }))} />
}

function Stacked({ bars, height, rule, format }: {
  bars: { label: string; parts: { value: number; color: string; opacity?: number }[] }[]; height: number; rule?: number; format?: (v: number) => string
}) {
  const top = niceMax(Math.max(rule ?? 0, ...bars.map((b) => b.parts.reduce((n, p) => n + p.value, 0))))
  const plot = height - 18
  const y = (v: number) => plot - (v / top) * plot
  return (
    <div className="row" style={{ alignItems: 'stretch', gap: 6 }}>
      <div className="muted" style={{ position: 'relative', width: 28, height: plot, fontSize: 10, flex: 'none' }}>
        {[0, 0.5, 1].map((f) => <span key={f} style={{ position: 'absolute', right: 0, top: y(top * f) - 6 }}>{compact(top * f)}</span>)}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ position: 'relative', height: plot }}>
          {[0, 0.5, 1].map((f) => <div key={f} style={{ position: 'absolute', left: 0, right: 0, top: y(top * f), borderTop: '1px solid var(--line)' }} />)}
          {rule !== undefined && (
            <div title={format?.(rule)} style={{ position: 'absolute', left: 0, right: 0, top: y(rule), borderTop: '1.5px dashed var(--ink3)', zIndex: 1 }} />
          )}
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'flex-end', gap: 4 }}>
            {bars.map((b, i) => (
              <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column-reverse', alignItems: 'center', height: '100%' }}>
                {b.parts.map((p, j) => p.value > 0 && (
                  <div key={j} title={format ? format(p.value) : String(Math.round(p.value))} style={{
                    width: '62%', height: `${(p.value / top) * 100}%`, background: p.color, opacity: p.opacity ?? 1,
                    borderRadius: j === b.parts.length - 1 || b.parts.slice(j + 1).every((q) => q.value <= 0) ? '4px 4px 0 0' : 0,
                  }} />
                ))}
              </div>
            ))}
          </div>
        </div>
        <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
          {bars.map((b, i) => <span key={i} className="muted" style={{ flex: 1, fontSize: 10, textAlign: 'center', whiteSpace: 'nowrap', overflow: 'visible' }}>{b.label}</span>)}
        </div>
      </div>
    </div>
  )
}

function Donut({ slices, size = 120 }: { slices: { value: number; color: string }[]; size?: number }) {
  const total = slices.reduce((n, s) => n + s.value, 0) || 1
  const r = size / 2 - 10, c = 2 * Math.PI * r, gap = slices.length > 1 ? 2 : 0
  let offset = 0
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ flex: 'none', transform: 'rotate(-90deg)' }}>
      {slices.map((s, i) => {
        const len = (s.value / total) * c
        const el = <circle key={i} cx={size / 2} cy={size / 2} r={r} fill="none" stroke={s.color} strokeWidth={18}
          strokeDasharray={`${Math.max(0, len - gap)} ${c}`} strokeDashoffset={-offset} />
        offset += len
        return el
      })}
    </svg>
  )
}

/** Mood over the last 90 days: an area under a line, scale 1–5. */
function MoodLine({ points }: { points: MoodPoint[] }) {
  const W = 320, H = 150, left = 26, start = addDays(startOfDay(new Date()), -90).getTime(), span = Date.now() - start
  const x = (d: Date) => left + ((d.getTime() - start) / span) * (W - left - 4)
  const y = (m: number) => 6 + (5 - m) / 4 * (H - 12)
  const line = points.map((p, i) => `${i ? 'L' : 'M'}${x(p.day).toFixed(1)},${y(p.mood).toFixed(1)}`).join(' ')
  const area = `${line} L${x(points[points.length - 1].day).toFixed(1)},${y(1)} L${x(points[0].day).toFixed(1)},${y(1)} Z`
  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto', display: 'block' }}>
      <defs>
        <linearGradient id="moodFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="var(--purple)" stopOpacity="0.35" /><stop offset="1" stopColor="var(--purple)" stopOpacity="0.02" />
        </linearGradient>
      </defs>
      {[1, 3, 5].map((m) => <g key={m}>
        <line x1={left} x2={W} y1={y(m)} y2={y(m)} stroke="var(--line)" />
        <text x={0} y={y(m) + 4} fontSize="11">{MOOD_FACES[m]}</text>
      </g>)}
      <path d={area} fill="url(#moodFill)" />
      <path d={line} fill="none" stroke="var(--ink)" strokeWidth="1.5" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  )
}

function MoodWeekdays({ points }: { points: MoodPoint[] }) {
  const data = moodByWeekday(points)
  if (!data.length) return <EmptyHint icon={<CalendarDays size={14} />} text="Appears after a couple of weeks of mood check-ins." />
  const best = data.reduce((a, b) => (b.mood > a.mood ? b : a)).weekday
  const sunday = new Date(2024, 0, 7) // a Sunday, for weekday names
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8, height: 140 }}>
      {data.map((d) => (
        <div key={d.weekday} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, height: '100%', justifyContent: 'flex-end' }}>
          <div style={{ width: '55%', height: `${(d.mood / 5) * 110}px`, borderRadius: '5px 5px 0 0', background: d.weekday === best ? 'var(--lime)' : 'var(--ink)', opacity: d.weekday === best ? 1 : 0.7 }} />
          <span className="muted" style={{ fontSize: 11 }}>{addDays(sunday, d.weekday).toLocaleDateString(undefined, { weekday: 'narrow' })}</span>
        </div>
      ))}
    </div>
  )
}
