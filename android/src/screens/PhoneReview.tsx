// Week in review on Android: the iPhone's ReviewView (ReviewView.swift + WeeklyReview.swift), with the numbers
// from @/lib/review. "This week": six tiles, the mood strip, the assistant's take (Joshu Pro) with next week's
// focus, and what you finished, your habits and money. "Insights": mood over 90 days, by weekday, and patterns.
import { useEffect, useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight, RefreshCw, CircleCheck, Undo2, AlertTriangle, X, Plus, Check } from 'lucide-react'
import { Modal, useMoney } from '@/components/ui'
import { store, useStoreVersion } from '@/lib/store'
import { Task, Note, MOOD_FACES, MOOD_WORDS, areaOf } from '@/lib/models'
import { iso, startOfWeek, addDays, sameDay, isToday, fmtDay } from '@/lib/dates'
import { useKeys, useAssistantName } from '@/lib/ai'
import { openAsk } from '@/lib/askBus'
import {
  computeWeek, weekLabel, weekAsText, WeekStats, WeeklyReflection, Focus, cachedReflection, reflect,
  moodSeries, moodByWeekday, moodFacts, MoodPoint, MoodFact, LifePattern, cachedPatterns, explainFacts,
} from '@/lib/review'
import { Orb } from '../components/Orb'
import '../screens/phoneSheets.css'

type Section = 'week' | 'insights'
const NUM_COLORS = ['var(--lime)', 'var(--pink)', 'var(--cyan)']

/** `onGetPro`: where "Get Pro" goes (Settings); without it the button is left out. */
export default function PhoneReview({ open, onClose, startOnInsights, onGetPro }: { open: boolean; onClose: () => void; startOnInsights?: boolean; onGetPro?: () => void }) {
  const [section, setSection] = useState<Section>(startOnInsights ? 'insights' : 'week')
  useEffect(() => { if (open) setSection(startOnInsights ? 'insights' : 'week') }, [open])
  if (!open) return null
  return (
    <Modal open onClose={onClose} width={640}>
      <div className="ps-root">
        <div className="ps-rv-head">
          <h2 className="ps-rv-title">{section === 'week' ? 'Week in review' : 'Mood & life insights'}</h2>
          <div className="ps-rv-seg">
            <button className={section === 'week' ? 'on' : ''} onClick={() => setSection('week')}>This week</button>
            <button className={section === 'insights' ? 'on' : ''} onClick={() => setSection('insights')}>Insights</button>
          </div>
          <button className="ps-x-btn" aria-label="Close" onClick={onClose}><X size={20} strokeWidth={2.6} /></button>
        </div>
        <div className="ps-body">
          {section === 'week' ? <WeekView onClose={onClose} onGetPro={onGetPro} /> : <Insights />}
        </div>
      </div>
    </Modal>
  )
}

// MARK: This week

let reflecting: string | null = null

function WeekView({ onClose, onGetPro }: { onClose: () => void; onGetPro?: () => void }) {
  const v = useStoreVersion()
  const money = useMoney()
  const keys = useKeys()
  const assistant = useAssistantName()
  const [week, setWeek] = useState(() => startOfWeek(new Date()))
  const s = useMemo(() => computeWeek(week), [week, v])
  const [reflection, setReflection] = useState<WeeklyReflection | null>(() => cachedReflection(week))
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [added, setAdded] = useState<Set<string>>(new Set())
  const [saved, setSaved] = useState(false)

  const run = (force: boolean) => {
    const key = iso(s.start)
    if (reflecting === key) return
    if (!force && cachedReflection(week)) return
    reflecting = key
    setLoading(true); setError('')
    reflect(s).then((r) => { if (iso(startOfWeek(week)) === key) setReflection(r) })
      .catch((e) => setError((e as Error).message))
      .finally(() => { reflecting = null; setLoading(false) })
  }
  useEffect(() => {
    setReflection(cachedReflection(week)); setAdded(new Set()); setSaved(false); setError('')
    if (keys.anthropic) run(false)
  }, [week, keys.anthropic])

  const habitTarget = s.habits.reduce((n, h) => n + h.target, 0)
  const habitPct = s.habits.length ? Math.round((s.habits.reduce((n, h) => n + Math.min(h.done, h.target), 0) / Math.max(1, habitTarget)) * 100) : null
  const avgMood = s.moods.length ? s.moods.reduce((n, m) => n + m.mood, 0) / s.moods.length : null

  const addFocus = (f: Focus) => {
    store.create<Task>('task', {
      title: f.title, notes: f.why, area: areaOf(f.area), due: iso(addDays(startOfWeek(new Date()), 7)), priority: 2, isDone: false,
      completedAt: null, createdAt: iso(new Date()), repeat: 'none',
    })
    setAdded((a) => new Set(a).add(f.title))
  }
  const saveToJournal = (r: WeeklyReflection) => {
    const body = [r.headline, '', ...r.wins.map((w) => `• ${w}`), ...r.struggles.map((w) => `• ${w}`), '', r.insight, '', 'Next week:',
      ...r.focus.map((f) => `• ${f.title}: ${f.why}`)].join('\n')
    const now = iso(new Date())
    store.create<Note>('note', { title: `Week in review · ${weekLabel(s)}`, body, createdAt: now, updatedAt: now, isJournal: false, pinned: false, mood: 0, moodSetByUser: false })
    setSaved(true)
  }

  return (
    <>
      <div className="ps-weeknav">
        <button aria-label="Previous week" onClick={() => setWeek(addDays(week, -7))}><ChevronLeft size={22} /></button>
        <span>{weekLabel(s)}</span>
        <button aria-label="Next week" disabled={week >= startOfWeek(new Date())} onClick={() => setWeek(addDays(week, 7))}><ChevronRight size={22} /></button>
      </div>

      <div className="ps-tiles">
        <Stat value={String(s.tasksDone.length)} label="Tasks done" color="var(--pink)" />
        <Stat value={habitPct === null ? '—' : `${habitPct}%`} label="Habits kept" color="var(--lime)" />
        <Stat value={money(s.spent)} label="Spent this week" color="var(--cyan)" />
        <Stat value={avgMood === null ? '—' : `${MOOD_FACES[Math.round(avgMood)]} ${avgMood.toFixed(1)}`} label="Average mood" color="var(--peach)" />
        <Stat value={`${s.readingMinutes} min`} label={s.booksFinished.length ? `Read · ${s.booksFinished.length} finished` : 'Reading'} color="var(--purple)" />
        <Stat value={`${s.focusMinutes} min`} label="Focused" color="var(--orange)" />
      </div>

      <div className="ps-moods">
        {Array.from({ length: 7 }, (_, i) => addDays(s.start, i)).map((day) => {
          const m = s.moods.find((x) => sameDay(x.day, day))?.mood
          return (
            <div key={day.toISOString()} className={`ps-mood${isToday(day) ? ' today' : ''}`}>
              <span className="ps-mood-face">{m ? MOOD_FACES[m] : '·'}</span>
              <span className="ps-mood-day">{day.toLocaleDateString(undefined, { weekday: 'short' })}</span>
            </div>
          )
        })}
      </div>

      {keys.anthropic ? (
        <div className="ps-take">
          <div className="ps-take-head">
            <Orb size={22} busy={loading} />
            <span className="dim">{assistant}'s take</span>
            <span className="spacer" />
            <button aria-label="Write it again" disabled={loading} onClick={() => run(true)} style={{ color: '#f4f4f5', opacity: loading ? 0.4 : 1 }}><RefreshCw size={15} /></button>
          </div>
          {reflection ? (
            <>
              <h3>{reflection.headline}</h3>
              {reflection.wins.map((w) => <div key={w} className="ps-take-line"><CircleCheck size={15} fill="#f4f4f5" color="#141416" style={{ flex: 'none', marginTop: 1 }} />{w}</div>)}
              {reflection.struggles.map((w) => <div key={w} className="ps-take-line" style={{ opacity: 0.85 }}><Undo2 size={15} style={{ flex: 'none', marginTop: 1 }} />{w}</div>)}
              {reflection.insight && <div className="ps-take-insight">{reflection.insight}</div>}
              <div style={{ fontSize: 12, fontWeight: 600, opacity: 0.7, marginTop: 4 }}>Focus for next week</div>
              <div className="col" style={{ gap: 8 }}>
                {reflection.focus.map((f, i) => {
                  const done = added.has(f.title)
                  return (
                    <div key={f.title} className="ps-focus">
                      <span className="ps-num" style={{ background: NUM_COLORS[i % 3] }}>{i + 1}</span>
                      <div className="col" style={{ gap: 3, flex: 1, minWidth: 0 }}>
                        <strong style={{ fontSize: 14 }}>{f.title}</strong>
                        <span style={{ fontSize: 12, opacity: 0.7 }}>{f.why}</span>
                      </div>
                      <button className={`ps-focus-add${done ? ' done' : ''}`} disabled={done} aria-label={done ? 'Added to next week' : "Add to next week's tasks"} onClick={() => addFocus(f)}>
                        {done ? <Check size={14} strokeWidth={3} /> : <Plus size={14} strokeWidth={3} />}
                      </button>
                    </div>
                  )
                })}
              </div>
              <div className="ps-take-foot">
                <button onClick={() => { onClose(); openAsk(`Let's talk about my week (${weekLabel(s)}). Here's how it went:\n${weekAsText(s)}`) }}>Talk it through with {assistant}</button>
                <button disabled={saved} onClick={() => saveToJournal(reflection)}>{saved ? 'Saved to notes ✓' : 'Save review to journal'}</button>
              </div>
            </>
          ) : error ? (
            <div className="ps-take-line"><AlertTriangle size={15} style={{ flex: 'none' }} />{error}</div>
          ) : (
            <div style={{ fontFamily: 'var(--display)', fontSize: 18 }}>{assistant} is looking back at your week…</div>
          )}
        </div>
      ) : (
        <div className="ps-upsell">
          <Orb size={44} />
          <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
            <span className="ps-upsell-t">Your week, reviewed</span>
            <span className="ps-upsell-d">{assistant} writes your review and suggests next week's focus. Part of Joshu Pro.</span>
          </div>
          {onGetPro && <button className="ps-primary" onClick={onGetPro}>Get Pro</button>}
        </div>
      )}

      <ListCard title="Finished" items={[...s.tasksDone, ...s.booksFinished.map((b) => `📖 ${b}`), ...s.bucketDone.map((b) => `⛰ ${b}`)]} empty="Nothing ticked off this week." />
      <ListCard title="Habits" items={s.habits.map((h) => `${h.name}: ${h.done} of ${h.target}`)} empty="No habits yet." />
      <ListCard title="Money" items={[`Month: ${money(s.monthSpent)} of ${money(s.budget)}`, ...s.topCategories.map(([c, n]) => `${c}: ${money(n)}`)]} empty="" />
    </>
  )
}

function Stat({ value, label, color }: { value: string; label: string; color: string }) {
  return (
    <div className="ps-stat" style={{ background: color }}>
      <span className="ps-stat-v" style={{ fontSize: value.length > 10 ? 18 : 22 }}>{value}</span>
      <span className="ps-stat-l">{label}</span>
    </div>
  )
}

function ListCard({ title, items, empty }: { title: string; items: string[]; empty: string }) {
  return (
    <div className="ps-list">
      <h4>{title}</h4>
      {items.length === 0 && empty && <span className="muted" style={{ fontSize: 13 }}>{empty}</span>}
      {items.slice(0, 8).map((t, i) => <div key={i} className="ps-list-item">• {t}</div>)}
      {items.length > 8 && <span className="muted" style={{ fontSize: 12 }}>+{items.length - 8} more</span>}
    </div>
  )
}

// MARK: Insights

let explaining = false

function Insights() {
  const v = useStoreVersion()
  const keys = useKeys()
  const assistant = useAssistantName()
  const points = useMemo(() => moodSeries(), [v])
  const facts = useMemo(() => moodFacts(points), [points])
  const [patterns, setPatterns] = useState<LifePattern[]>(cachedPatterns)
  const [loading, setLoading] = useState(false)
  const explain = () => {
    if (explaining || !facts.length) return
    explaining = true; setLoading(true)
    explainFacts(facts).then(setPatterns).catch(() => {}).finally(() => { explaining = false; setLoading(false) })
  }
  useEffect(() => { if (keys.anthropic && patterns.length === 0) explain() }, [keys.anthropic])

  if (points.length < 5) {
    return (
      <div className="ps-empty">
        <span style={{ fontSize: 44 }}>🙂</span>
        <span className="secondary" style={{ fontSize: 14 }}>Rate your mood in the journal (or let {assistant} pick it up in your check-ins) for a few days, and patterns start showing here.</span>
        <strong style={{ fontSize: 12 }}>{points.length} of 5 days so far</strong>
      </div>
    )
  }
  return (
    <>
      <MoodChart points={points} />
      <WeekdayChart points={points} />
      <div className="ps-chart-card blush">
        <div className="row">
          <h4>Patterns</h4>
          <span className="spacer" />
          {loading && <span className="muted" style={{ fontSize: 11 }}>Thinking…</span>}
          {keys.anthropic && <button aria-label="Refresh" disabled={loading || !facts.length} onClick={explain}><RefreshCw size={15} /></button>}
        </div>
        <PatternList facts={facts} patterns={patterns} />
        <span className="muted" style={{ fontSize: 10 }}>Patterns are correlations from your own data, not causes.</span>
      </div>
    </>
  )
}

function PatternList({ facts, patterns }: { facts: MoodFact[]; patterns: LifePattern[] }) {
  if (!facts.length) return <span className="secondary" style={{ fontSize: 12 }}>No clear patterns yet. They appear once there are a few days on both sides (e.g. gym days and rest days).</span>
  if (patterns.length) {
    return <>{patterns.map((p) => (
      <div key={p.title} className="ps-pattern">
        <strong style={{ fontSize: 14 }}>{p.title}</strong>
        <span className="secondary" style={{ fontSize: 12 }}>{p.detail}</span>
      </div>
    ))}</>
  }
  return <>{facts.slice(0, 5).map((f) => <div key={f.text} style={{ fontSize: 12 }}>• {f.text}</div>)}</>
}

function MoodChart({ points }: { points: MoodPoint[] }) {
  const [sel, setSel] = useState<number | null>(null)
  const W = 360, H = 200, left = 26, right = 6, top = 10, bottom = 22
  const end = new Date(), start = addDays(end, -90)
  const span = end.getTime() - start.getTime()
  const x = (d: Date) => left + ((d.getTime() - start.getTime()) / span) * (W - left - right)
  const y = (m: number) => top + ((5 - m) / 4) * (H - top - bottom)
  let path = ''
  points.forEach((p, i) => {
    const px = x(p.day), py = y(p.mood)
    if (i === 0) { path += `M${px},${py}`; return }
    const prev = points[i - 1], qx = x(prev.day), qy = y(prev.mood), mx = (qx + px) / 2
    path += ` C${mx},${qy} ${mx},${py} ${px},${py}`
  })
  const area = points.length ? `${path} L${x(points[points.length - 1].day)},${y(1)} L${x(points[0].day)},${y(1)} Z` : ''
  const months: Date[] = []
  for (let d = new Date(start.getFullYear(), start.getMonth() + 1, 1); d <= end; d = new Date(d.getFullYear(), d.getMonth() + 1, 1)) months.push(d)
  const h = sel !== null ? points[sel] : null
  const pick = (e: React.PointerEvent<SVGSVGElement>) => {
    const r = e.currentTarget.getBoundingClientRect()
    const mx = ((e.clientX - r.left) / r.width) * W
    let best = 0
    points.forEach((p, i) => { if (Math.abs(x(p.day) - mx) < Math.abs(x(points[best].day) - mx)) best = i })
    setSel(best)
  }
  return (
    <div className="ps-chart-card">
      <div className="row" style={{ alignItems: 'baseline' }}>
        <h4 style={{ fontSize: 20 }}>Mood, last 90 days</h4>
        <span className="spacer" />
        {h ? <span style={{ fontSize: 12, fontWeight: 500 }}>{fmtDay(h.day, { weekday: 'short', day: 'numeric', month: 'short' })} · {MOOD_FACES[h.mood]} {MOOD_WORDS[h.mood]}</span>
          : <span className="muted" style={{ fontSize: 11 }}>Tap for details</span>}
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} onPointerDown={pick} onPointerMove={(e) => e.buttons && pick(e)}>
        <defs>
          <linearGradient id="ps-mood-fill" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor="var(--purple)" stopOpacity="0.35" />
            <stop offset="1" stopColor="var(--purple)" stopOpacity="0.02" />
          </linearGradient>
        </defs>
        {[1, 2, 3, 4, 5].map((m) => (
          <g key={m}>
            <line x1={left} x2={W - right} y1={y(m)} y2={y(m)} stroke="var(--line)" />
            <text x={left - 6} y={y(m) + 5} textAnchor="end" fontSize="13">{MOOD_FACES[m]}</text>
          </g>
        ))}
        {months.map((d) => <text key={d.toISOString()} x={x(d)} y={H - 4} fontSize="10" fill="var(--ink3)" textAnchor="middle">{d.toLocaleDateString(undefined, { month: 'short' })}</text>)}
        <path d={area} fill="url(#ps-mood-fill)" />
        <path d={path} fill="none" stroke="var(--ink)" strokeWidth={1.5} strokeLinecap="round" />
        {h && <circle cx={x(h.day)} cy={y(h.mood)} r={5} fill="var(--ink)" />}
      </svg>
    </div>
  )
}

function WeekdayChart({ points }: { points: MoodPoint[] }) {
  const data = moodByWeekday(points)
  const names = Array.from({ length: 7 }, (_, i) => new Date(2023, 0, 1 + i).toLocaleDateString(undefined, { weekday: 'short' })) // 1 Jan 2023 was a Sunday
  const W = 340, H = 170, bottom = 20, top = 16
  const step = W / Math.max(data.length, 1)
  return (
    <div className="ps-chart-card">
      <h4>By day of the week</h4>
      <svg viewBox={`0 0 ${W} ${H}`}>
        {data.map((d, i) => {
          const h = (d.mood / 5) * (H - top - bottom), bw = step * 0.55, bx = i * step + (step - bw) / 2, by = H - bottom - h
          return (
            <g key={d.weekday}>
              <path d={`M${bx},${H - bottom} V${by + 4} Q${bx},${by} ${bx + 4},${by} H${bx + bw - 4} Q${bx + bw},${by} ${bx + bw},${by + 4} V${H - bottom} Z`} fill="var(--ink)" />
              <text x={bx + bw / 2} y={by - 4} fontSize="10" textAnchor="middle" fill="var(--ink2)">{d.mood.toFixed(1)}</text>
              <text x={bx + bw / 2} y={H - 5} fontSize="10" textAnchor="middle" fill="var(--ink3)">{names[d.weekday]}</text>
            </g>
          )
        })}
      </svg>
    </div>
  )
}
