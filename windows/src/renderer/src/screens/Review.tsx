// Week in review and mood & life insights. Mirrors ReviewView.swift on the Mac.
import { useEffect, useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight, Sparkles, RefreshCw, CheckCircle2, Undo2, AlertTriangle, X } from 'lucide-react'
import { store, useStoreVersion } from '@/lib/store'
import { Task, Note, MOOD_FACES, MOOD_WORDS, areaOf } from '@/lib/models'
import { iso, startOfWeek, addDays, sameDay, isToday, fmtDay } from '@/lib/dates'
import { useKeys, useAssistantName } from '@/lib/ai'
import { openAsk } from '@/lib/askBus'
import {
  computeWeek, weekLabel, weekAsText, WeekStats, WeeklyReflection, Focus, cachedReflection, reflect,
  moodSeries, moodByWeekday, moodFacts, MoodPoint, MoodFact, LifePattern, cachedPatterns, explainFacts,
} from '@/lib/review'
import { Card, Segmented, useMoney } from '@/components/ui'

type Section = 'week' | 'insights'

export default function Review({ open, onClose, startOnInsights }: { open: boolean; onClose: () => void; startOnInsights?: boolean }) {
  const [section, setSection] = useState<Section>(startOnInsights ? 'insights' : 'week')
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])
  if (!open) return null
  return (
    <div className="backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div className="modal" style={{ width: 940, height: 'min(760px, 90vh)', padding: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <div className="row" style={{ padding: 24, gap: 12 }}>
          <h2 className="page-title" style={{ fontSize: 28 }}>{section === 'week' ? 'Week in review' : 'Mood & life insights'}</h2>
          <span className="spacer" />
          <Segmented<Section> options={[{ id: 'week', label: 'This week' }, { id: 'insights', label: 'Insights' }]} value={section} onChange={setSection} />
          <button className="icon-btn" style={{ width: 32, height: 32 }} onClick={onClose} title="Close"><X size={15} /></button>
        </div>
        <div className="scroll" style={{ flex: 1, padding: '0 24px 24px' }}>
          {section === 'week' ? <WeekView onClose={onClose} /> : <Insights />}
        </div>
      </div>
    </div>
  )
}

// MARK: This week

let reflecting: string | null = null

function WeekView({ onClose }: { onClose: () => void }) {
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
    const nextWeek = addDays(startOfWeek(new Date()), 7)
    store.create<Task>('task', {
      title: f.title, notes: f.why, area: areaOf(f.area), due: iso(nextWeek), priority: 2, isDone: false,
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
    <div className="col" style={{ gap: 18 }}>
      <div className="row" style={{ gap: 8 }}>
        <button className="icon-btn" style={{ width: 30, height: 30 }} onClick={() => setWeek(addDays(week, -7))} title="Previous week"><ChevronLeft size={15} /></button>
        <strong style={{ fontSize: 14 }}>{weekLabel(s)}</strong>
        <button className="icon-btn" style={{ width: 30, height: 30 }} disabled={week >= startOfWeek(new Date())} onClick={() => setWeek(addDays(week, 7))} title="Next week"><ChevronRight size={15} /></button>
      </div>

      <div className="row" style={{ gap: 12, alignItems: 'stretch' }}>
        <Tile value={String(s.tasksDone.length)} label="Tasks done" color="var(--pink)" />
        <Tile value={habitPct === null ? '—' : `${habitPct}%`} label="Habits kept" color="var(--lime)" />
        <Tile value={money(s.spent)} label="Spent this week" color="var(--cyan)" />
        <Tile value={avgMood === null ? '—' : `${MOOD_FACES[Math.round(avgMood)]} ${avgMood.toFixed(1)}`} label="Average mood" color="var(--peach)" />
        <Tile value={`${s.focusMinutes} min`} label="Focus time" color="var(--orange)" />
        <Tile value={`${s.readingMinutes} min`} label={s.booksFinished.length ? `Read · ${s.booksFinished.length} finished` : 'Reading'} color="var(--purple)" />
      </div>

      <MoodStrip s={s} />

      {keys.anthropic ? (
        <div className="col" style={{ gap: 12, padding: 20, borderRadius: 20, background: '#141416', color: '#f4f4f5' }}>
          <div className="row">
            <Sparkles size={15} color="var(--lime)" />
            <span style={{ fontSize: 12, fontWeight: 600, opacity: 0.7 }}>{assistant}'s take</span>
            <span className="spacer" />
            {loading && <span style={{ fontSize: 11, opacity: 0.6 }}>Thinking…</span>}
            <button title="Write it again" disabled={loading} onClick={() => run(true)} style={{ color: '#f4f4f5' }}><RefreshCw size={14} /></button>
          </div>
          {reflection ? (
            <>
              <div className="display" style={{ fontSize: 22 }}>{reflection.headline}</div>
              {reflection.wins.length > 0 && (
                <div className="col" style={{ gap: 4 }}>
                  {reflection.wins.map((w) => <div key={w} className="row" style={{ gap: 8, fontSize: 13, alignItems: 'flex-start' }}><CheckCircle2 size={14} style={{ flex: 'none', marginTop: 2 }} />{w}</div>)}
                </div>
              )}
              {reflection.struggles.map((w) => <div key={w} className="row" style={{ gap: 8, fontSize: 13, opacity: 0.85, alignItems: 'flex-start' }}><Undo2 size={14} style={{ flex: 'none', marginTop: 2 }} />{w}</div>)}
              {reflection.insight && <div className="display" style={{ fontSize: 15, fontWeight: 500, fontStyle: 'italic', opacity: 0.85 }}>{reflection.insight}</div>}
              <div style={{ fontSize: 12, fontWeight: 600, opacity: 0.7, marginTop: 4 }}>Focus for next week</div>
              <div className="row" style={{ gap: 10, alignItems: 'stretch' }}>
                {reflection.focus.map((f) => (
                  <div key={f.title} className="col" style={{ flex: 1, minWidth: 0, gap: 6, padding: 12, minHeight: 120, borderRadius: 14, background: 'rgba(255,255,255,0.07)' }}>
                    <strong style={{ fontSize: 14 }}>{f.title}</strong>
                    <span style={{ fontSize: 11, opacity: 0.75 }}>{f.why}</span>
                    <span className="spacer" />
                    <button className="pill" style={{ background: 'var(--lime)', fontWeight: 600, alignSelf: 'flex-start' }} disabled={added.has(f.title)} onClick={() => addFocus(f)}>
                      {added.has(f.title) ? 'Added ✓' : 'Add to next week'}
                    </button>
                  </div>
                ))}
              </div>
              <div className="row" style={{ marginTop: 4, fontSize: 12, fontWeight: 600 }}>
                <button style={{ color: '#f4f4f5' }} onClick={() => { onClose(); openAsk(`Let's talk about my week (${weekLabel(s)}). Here's how it went:\n${weekAsText(s)}`) }}>
                  Talk it through with {assistant}
                </button>
                <span className="spacer" />
                <button style={{ color: '#f4f4f5' }} disabled={saved} onClick={() => saveToJournal(reflection)}>{saved ? 'Saved to notes ✓' : 'Save review to journal'}</button>
              </div>
            </>
          ) : error ? (
            <div className="row" style={{ gap: 8, fontSize: 12 }}><AlertTriangle size={14} />{error}</div>
          ) : (
            <div className="display" style={{ fontSize: 18, fontWeight: 500 }}>{assistant} is looking back at your week…</div>
          )}
        </div>
      ) : (
        <div className="secondary" style={{ fontSize: 13 }}>Add your Anthropic API key in Settings and {assistant} will write your review and suggest next week's focus.</div>
      )}

      <div className="row" style={{ gap: 16, alignItems: 'flex-start' }}>
        <ListCard title="Finished" items={[...s.tasksDone, ...s.booksFinished.map((b) => `📖 ${b}`), ...s.bucketDone.map((b) => `⛰ ${b}`)]} empty="Nothing ticked off this week." />
        <ListCard title="Habits" items={s.habits.map((h) => `${h.name}: ${h.done} of ${h.target}`)} empty="No habits yet." />
        <ListCard title="Money" items={[`Month: ${money(s.monthSpent)} of ${money(s.budget)}`, ...s.topCategories.map(([c, n]) => `${c}: ${money(n)}`)]} empty="" />
      </div>
    </div>
  )
}

function Tile({ value, label, color }: { value: string; label: string; color: string }) {
  return (
    <div className="col" style={{ flex: 1, minWidth: 0, gap: 4, padding: 14, borderRadius: 16, background: color, color: 'var(--sticker-ink)' }}>
      <div className="display clamp1" style={{ fontSize: 22 }}>{value}</div>
      <div className="clamp1" style={{ fontSize: 11, fontWeight: 600, opacity: 0.8 }}>{label}</div>
    </div>
  )
}

function MoodStrip({ s }: { s: WeekStats }) {
  return (
    <div className="row" style={{ gap: 8 }}>
      {Array.from({ length: 7 }, (_, i) => addDays(s.start, i)).map((day) => {
        const m = s.moods.find((x) => sameDay(x.day, day))?.mood
        return (
          <div key={day.toISOString()} className="col" style={{ flex: 1, alignItems: 'center', gap: 4, padding: '8px 0', borderRadius: 12, background: isToday(day) ? 'var(--blush)' : 'var(--card)' }}>
            <span style={{ fontSize: 22, height: 28, lineHeight: '28px' }}>{m ? MOOD_FACES[m] : '·'}</span>
            <span className="muted" style={{ fontSize: 11 }}>{day.toLocaleDateString(undefined, { weekday: 'short' })}</span>
          </div>
        )
      })}
    </div>
  )
}

function ListCard({ title, items, empty }: { title: string; items: string[]; empty: string }) {
  return (
    <Card className="col" padding={14} style={{ flex: 1, minWidth: 0, gap: 6 }}>
      <div className="display" style={{ fontSize: 17 }}>{title}</div>
      {items.length === 0 && empty && <div className="muted" style={{ fontSize: 12 }}>{empty}</div>}
      {items.slice(0, 8).map((t, i) => <div key={i} className="clamp2" style={{ fontSize: 12 }}>• {t}</div>)}
      {items.length > 8 && <div className="muted" style={{ fontSize: 11 }}>+{items.length - 8} more</div>}
    </Card>
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
      <div className="col" style={{ alignItems: 'center', padding: '60px 0', gap: 10, textAlign: 'center' }}>
        <span style={{ fontSize: 44 }}>🙂</span>
        <div className="secondary" style={{ maxWidth: 460 }}>Rate your mood in the journal (or let {assistant} pick it up in your check-ins) for a few days, and patterns start showing here.</div>
        <strong style={{ fontSize: 12 }}>{points.length} of 5 days so far</strong>
      </div>
    )
  }
  return (
    <div className="col" style={{ gap: 18 }}>
      <MoodChart points={points} />
      <div className="row" style={{ gap: 16, alignItems: 'flex-start' }}>
        <div style={{ width: 380, flex: 'none' }}><WeekdayChart points={points} /></div>
        <Card fill="var(--blush)" className="col" style={{ flex: 1, minWidth: 0, gap: 10 }}>
          <div className="row">
            <div className="display" style={{ fontSize: 18 }}>Patterns</div>
            <span className="spacer" />
            {loading && <span className="muted" style={{ fontSize: 11 }}>Thinking…</span>}
            {keys.anthropic && <button title="Refresh" disabled={loading || !facts.length} onClick={explain}><RefreshCw size={14} /></button>}
          </div>
          <PatternList facts={facts} patterns={patterns} />
          <div className="muted" style={{ fontSize: 10 }}>Patterns are correlations from your own data, not causes.</div>
        </Card>
      </div>
    </div>
  )
}

function PatternList({ facts, patterns }: { facts: MoodFact[]; patterns: LifePattern[] }) {
  if (!facts.length) return <div className="secondary" style={{ fontSize: 12 }}>No clear patterns yet. They appear once there are a few days on both sides (e.g. gym days and rest days).</div>
  if (patterns.length) {
    return (
      <>
        {patterns.map((p) => (
          <div key={p.title} className="col" style={{ gap: 3, padding: 10, borderRadius: 12, background: 'var(--canvas)' }}>
            <strong style={{ fontSize: 14 }}>{p.title}</strong>
            <span className="secondary" style={{ fontSize: 12 }}>{p.detail}</span>
          </div>
        ))}
      </>
    )
  }
  return <>{facts.slice(0, 5).map((f) => <div key={f.text} style={{ fontSize: 12 }}>• {f.text}</div>)}</>
}

function MoodChart({ points }: { points: MoodPoint[] }) {
  const [hover, setHover] = useState<number | null>(null)
  const W = 860, H = 200, left = 34, right = 10, top = 10, bottom = 22
  const end = new Date(), start = addDays(end, -90)
  const span = end.getTime() - start.getTime()
  const x = (d: Date) => left + ((d.getTime() - start.getTime()) / span) * (W - left - right)
  const y = (m: number) => top + ((5 - m) / 4) * (H - top - bottom)
  // Smooth line through the points (monotone-ish: horizontal tangents at each point).
  let path = ''
  points.forEach((p, i) => {
    const px = x(p.day), py = y(p.mood)
    if (i === 0) { path += `M${px},${py}`; return }
    const prev = points[i - 1], qx = x(prev.day), qy = y(prev.mood), mx = (qx + px) / 2
    path += ` C${mx},${qy} ${mx},${py} ${px},${py}`
  })
  const months: Date[] = []
  for (let d = new Date(start.getFullYear(), start.getMonth() + 1, 1); d <= end; d = new Date(d.getFullYear(), d.getMonth() + 1, 1)) months.push(d)
  const h = hover !== null ? points[hover] : null
  return (
    <Card className="col" style={{ gap: 10 }}>
      <div className="row">
        <div className="display" style={{ fontSize: 20 }}>Mood, last 90 days</div>
        <span className="spacer" />
        {h ? <span style={{ fontSize: 12, fontWeight: 500 }}>{fmtDay(h.day, { weekday: 'short', day: 'numeric', month: 'short' })} · {MOOD_FACES[h.mood]} {MOOD_WORDS[h.mood]}</span>
          : <span className="muted" style={{ fontSize: 11 }}>Hover for details</span>}
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }} onMouseLeave={() => setHover(null)}
        onMouseMove={(e) => {
          const r = (e.currentTarget as SVGSVGElement).getBoundingClientRect()
          const mx = ((e.clientX - r.left) / r.width) * W
          let best = 0
          points.forEach((p, i) => { if (Math.abs(x(p.day) - mx) < Math.abs(x(points[best].day) - mx)) best = i })
          setHover(best)
        }}>
        {[1, 2, 3, 4, 5].map((m) => (
          <g key={m}>
            <line x1={left} x2={W - right} y1={y(m)} y2={y(m)} stroke="var(--line)" />
            <text x={left - 8} y={y(m) + 5} textAnchor="end" fontSize="13">{MOOD_FACES[m]}</text>
          </g>
        ))}
        {months.map((d) => <text key={d.toISOString()} x={x(d)} y={H - 4} fontSize="10" fill="var(--ink3)" textAnchor="middle">{d.toLocaleDateString(undefined, { month: 'short' })}</text>)}
        <path d={path} fill="none" stroke="var(--ink)" strokeWidth={2} />
        {points.map((p, i) => <circle key={i} cx={x(p.day)} cy={y(p.mood)} r={hover === i ? 5 : 3} fill="var(--ink)" />)}
      </svg>
    </Card>
  )
}

function WeekdayChart({ points }: { points: MoodPoint[] }) {
  const data = moodByWeekday(points)
  const names = Array.from({ length: 7 }, (_, i) => new Date(2023, 0, 1 + i).toLocaleDateString(undefined, { weekday: 'short' })) // 1 Jan 2023 was a Sunday
  const W = 340, H = 170, bottom = 20, top = 16
  const step = W / Math.max(data.length, 1)
  return (
    <Card className="col" style={{ gap: 10 }}>
      <div className="display" style={{ fontSize: 18 }}>By day of the week</div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }}>
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
    </Card>
  )
}
