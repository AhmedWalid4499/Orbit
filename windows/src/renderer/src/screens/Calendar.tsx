// Calendar: Day, Week and Month views of your Orbit events (same data as the Mac app's Calendar).
import { useEffect, useMemo, useRef, useState } from 'react'
import { ArrowLeft, ArrowRight, ChevronDown, Plus, CalendarDays, Clock, Trash2 } from 'lucide-react'
import './Calendar.css'
import { useRecords, store, Rec } from '@/lib/store'
import { useExternalEvents } from '@/lib/externalEvents'
import { CalEvent, AREA_COLOR, areaOf, Area } from '@/lib/models'
import {
  iso, parse, startOfDay, addDays, addMinutes, addMonths, sameDay, isToday, startOfMonth, startOfWeek,
  fmtTime, fmtDay, fromInputs, toDateInput, toTimeInput,
} from '@/lib/dates'
import { AreaPill, AreaPicker, Modal, Segmented } from '@/components/ui'

type Mode = 'day' | 'week' | 'month'
const HOURS = Array.from({ length: 18 }, (_, i) => i + 6) // 6am … 11pm
const HOUR_H = 76
const FIRST_HOUR = HOURS[0]

interface Entry { id: string; title: string; start: Date; end: Date; area: Area; color?: string; calendar?: string }

function hourLabel(h: number): string {
  if (h === 12) return 'Noon'
  const d = new Date(2000, 0, 1, h)
  return d.toLocaleTimeString(undefined, { hour: 'numeric' })
}

/** Overlapping events share the column width side by side. */
function lanes(entries: Entry[]): Map<string, { lane: number; count: number }> {
  const out = new Map<string, { lane: number; count: number }>()
  let cluster: Entry[] = []
  let clusterEnd = 0
  let laneEnds: number[] = []
  const flush = () => {
    const count = Math.max(laneEnds.length, 1)
    for (const e of cluster) out.set(e.id, { lane: out.get(e.id)?.lane ?? 0, count })
    cluster = []
    laneEnds = []
  }
  for (const e of [...entries].sort((a, b) => a.start.getTime() - b.start.getTime())) {
    if (e.start.getTime() >= clusterEnd) flush()
    const free = laneEnds.findIndex((t) => t <= e.start.getTime())
    if (free >= 0) { laneEnds[free] = e.end.getTime(); out.set(e.id, { lane: free, count: 1 }) }
    else { laneEnds.push(e.end.getTime()); out.set(e.id, { lane: laneEnds.length - 1, count: 1 }) }
    cluster.push(e)
    clusterEnd = Math.max(clusterEnd, e.end.getTime())
  }
  flush()
  return out
}

const yOf = (d: Date): number => Math.max(0, ((d.getHours() - FIRST_HOUR) * 60 + d.getMinutes()) / 60 * HOUR_H)

export default function CalendarScreen() {
  const [mode, setModeState] = useState<Mode>(() => (localStorage.getItem('orbit.calendarMode') as Mode) || 'week')
  const setMode = (m: Mode) => { setModeState(m); localStorage.setItem('orbit.calendarMode', m) }
  const [anchor, setAnchor] = useState(new Date())
  const [menu, setMenu] = useState(false)
  const [newSlot, setNewSlot] = useState<Date | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const [now, setNow] = useState(new Date())
  const scrollRef = useRef<HTMLDivElement>(null)
  const raw = useRecords<CalEvent>('event')
  const outside = useExternalEvents()

  useEffect(() => { const t = setInterval(() => setNow(new Date()), 60_000); return () => clearInterval(t) }, [])

  const weekStart = mode === 'day' ? startOfDay(anchor) : startOfWeek(anchor)
  const days = mode === 'day' ? [startOfDay(anchor)] : Array.from({ length: 7 }, (_, i) => addDays(weekStart, i))
  const monthDays = useMemo(() => {
    const s = startOfWeek(startOfMonth(anchor))
    return Array.from({ length: 42 }, (_, i) => addDays(s, i))
  }, [anchor])

  const entries: Entry[] = useMemo(() => raw.flatMap((r: Rec<CalEvent>) => {
    const start = parse(r.data.start), end = parse(r.data.end)
    if (!start || !end) return []
    return [{ id: r.id, title: r.data.title || 'Untitled', start, end: end > start ? end : addMinutes(start, 30), area: areaOf(r.data.area) }]
  }).concat(outside.filter((e) => !e.allDay).map((e) => ({ id: e.id, title: e.title, start: e.start, end: e.end > e.start ? e.end : addMinutes(e.start, 30),
    area: 'work' as Area, color: e.color, calendar: e.calendar })))
    .sort((a, b) => a.start.getTime() - b.start.getTime()), [raw, outside])

  // Open week/day views around 7am.
  useEffect(() => { if (scrollRef.current) scrollRef.current.scrollTop = HOUR_H * (7 - FIRST_HOUR) }, [mode])

  const step = (dir: number) => {
    if (mode === 'day') setAnchor(addDays(anchor, dir))
    else if (mode === 'week') setAnchor(addDays(anchor, 7 * dir))
    else setAnchor(addMonths(anchor, dir))
  }

  const title = mode === 'day'
    ? fmtDay(anchor, { weekday: 'long', day: 'numeric', month: 'short' })
    : mode === 'week'
      ? addDays(weekStart, 3).toLocaleDateString(undefined, { month: 'short', year: 'numeric' })
      : anchor.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })

  const selectedEntry = selected ? entries.find((e) => e.id === selected) : undefined

  return (
    <div className="cal">
      <div className="cal-toolbar">
        <div style={{ position: 'relative' }}>
          <button className="cal-title" onClick={() => setMenu(!menu)}>
            {title}<ChevronDown size={18} strokeWidth={2.5} />
          </button>
          {menu && (
            <div className="cal-menu" onMouseLeave={() => setMenu(false)}>
              {[-3, -2, -1, 0, 1, 2, 3].map((m) => {
                const d = addMonths(startOfMonth(anchor), m)
                return (
                  <button key={m} onClick={() => { setAnchor(d); setMenu(false) }} style={{ fontWeight: m === 0 ? 700 : 400 }}>
                    {d.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}
                  </button>
                )
              })}
            </div>
          )}
        </div>
        <span className="spacer" />
        <span className="muted" style={{ fontSize: 11 }}>Apple and Google calendars appear in the Mac app only.</span>
        <Segmented<Mode> options={[{ id: 'day', label: 'Day' }, { id: 'week', label: 'Week' }, { id: 'month', label: 'Month' }]} value={mode} onChange={setMode} />
        <button className="btn-soft" onClick={() => setAnchor(new Date())}>Today</button>
        <button className="icon-btn filled" style={{ width: 44, height: 44 }} onClick={() => step(-1)} title="Previous"><ArrowLeft size={18} /></button>
        <button className="icon-btn filled" style={{ width: 44, height: 44 }} onClick={() => step(1)} title="Next"><ArrowRight size={18} /></button>
      </div>

      {mode === 'month' ? (
        <MonthGrid days={monthDays} month={anchor} entries={entries} onOpenDay={(d) => { setAnchor(d); setMode('day') }} />
      ) : (
        <>
          <div className="cal-head" style={{ paddingLeft: 64 }}>
            {days.map((d) => (
              <div key={d.toISOString()} className="cal-headday">
                <span className={`cal-headnum ${isToday(d) ? 'today' : ''}`}>{d.getDate()}</span>
                <span className="secondary" style={{ fontSize: 13 }}>{d.toLocaleDateString(undefined, { weekday: 'long' })}</span>
                <span className="cal-tick" />
              </div>
            ))}
          </div>
          <div className="cal-scroll" ref={scrollRef}>
            <div className="cal-grid">
              <div className="cal-gutter">
                {HOURS.map((h) => <div key={h} style={{ height: HOUR_H }} className="cal-hourlabel">{hourLabel(h)}</div>)}
              </div>
              {days.map((day) => (
                <DayColumn key={day.toISOString()} day={day} now={now}
                  entries={entries.filter((e) => sameDay(e.start, day))}
                  selectedSlot={newSlot}
                  onSlot={setNewSlot} onSelect={setSelected} />
              ))}
            </div>
          </div>
        </>
      )}

      <Modal open={!!newSlot} onClose={() => setNewSlot(null)} width={360}>
        {newSlot && <NewEvent start={newSlot} onDone={() => setNewSlot(null)} />}
      </Modal>
      <Modal open={!!selectedEntry} onClose={() => setSelected(null)} width={340}>
        {selectedEntry && <EventDetail entry={selectedEntry} onDone={() => setSelected(null)} />}
      </Modal>
    </div>
  )
}

function DayColumn({ day, entries, now, selectedSlot, onSlot, onSelect }: {
  day: Date; entries: Entry[]; now: Date; selectedSlot: Date | null; onSlot: (d: Date) => void; onSelect: (id: string) => void
}) {
  const ref = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(0)
  useEffect(() => {
    if (!ref.current) return
    const ro = new ResizeObserver(([e]) => setWidth(e.contentRect.width))
    ro.observe(ref.current)
    return () => ro.disconnect()
  }, [])
  const lane = lanes(entries)
  return (
    <div className="cal-col" ref={ref} style={{ height: HOUR_H * HOURS.length }}>
      {HOURS.map((h) => {
        const slot = new Date(day.getFullYear(), day.getMonth(), day.getDate(), h)
        const past = addMinutes(slot, 60) < now
        const on = selectedSlot?.getTime() === slot.getTime()
        return (
          <div key={h} className="cal-slot" style={{ height: HOUR_H }} onClick={() => onSlot(slot)}>
            {past && <div className="hatch" />}
            <div className={`add ${on ? 'show' : ''}`}><Plus size={18} strokeWidth={1.5} /></div>
          </div>
        )
      })}
      {entries.map((e) => {
        const { lane: l, count } = lane.get(e.id) ?? { lane: 0, count: 1 }
        const w = (width - 8) / count
        const h = Math.max(28, (e.end.getTime() - e.start.getTime()) / 3_600_000 * HOUR_H - 4)
        return (
          <div key={e.id} className="cal-event" title={e.title}
            style={{ top: yOf(e.start) + 2, left: 4 + l * w, width: Math.max(20, w - 4), height: h, padding: h > 40 ? '8px 12px' : '4px 12px',
              ...(e.color ? { background: e.color, color: 'var(--sticker-ink)' } : {}) }}
            onClick={(ev) => { ev.stopPropagation(); onSelect(e.id) }}>
            <span className="t" style={{ whiteSpace: h > 60 ? 'normal' : 'nowrap' }}>{e.title}</span>
            {h > 56 && <span className="time">{fmtTime(e.start)} – {fmtTime(e.end)}</span>}
            <span className="spacer" />
            {h > 92 && (e.calendar ? <span className="time">{e.calendar}</span> : <span><AreaPill area={e.area} compact /></span>)}
          </div>
        )
      })}
      {isToday(day) && now.getHours() >= FIRST_HOUR && <div className="cal-now" style={{ top: yOf(now) }} />}
    </div>
  )
}

function MonthGrid({ days, month, entries, onOpenDay }: { days: Date[]; month: Date; entries: Entry[]; onOpenDay: (d: Date) => void }) {
  return (
    <div className="cal-month">
      {days.slice(0, 7).map((d) => <div key={d.toISOString()} className="wd">{d.toLocaleDateString(undefined, { weekday: 'short' })}</div>)}
      {days.map((day) => {
        const list = entries.filter((e) => sameDay(e.start, day))
        const inMonth = day.getMonth() === month.getMonth()
        return (
          <div key={day.toISOString()} className={`cal-cell ${inMonth ? '' : 'out'}`} onClick={() => onOpenDay(day)}
            title={`Open ${fmtDay(day, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}`}>
            <span className={`num ${isToday(day) ? 'today' : ''}`}>{day.getDate()}</span>
            {list.slice(0, 3).map((e) => (
              <span key={e.id} className="ev"><i style={{ background: e.color ?? AREA_COLOR[e.area] }} />{fmtTime(e.start)} {e.title}</span>
            ))}
            {list.length > 3 && <span className="muted" style={{ fontSize: 10, fontWeight: 600 }}>+{list.length - 3} more</span>}
          </div>
        )
      })}
    </div>
  )
}

function NewEvent({ start, onDone }: { start: Date; onDone: () => void }) {
  const [title, setTitle] = useState('')
  const [date, setDate] = useState(toDateInput(start))
  const [from, setFrom] = useState(toTimeInput(start))
  const [to, setTo] = useState(toTimeInput(addMinutes(start, 60)))
  const [area, setArea] = useState<Area>('personal')

  const add = () => {
    const t = title.trim()
    if (!t) return
    const s = fromInputs(date, from)
    let e = fromInputs(date, to)
    if (e <= s) e = addMinutes(s, 15)
    store.create<CalEvent>('event', { title: t, start: iso(s), end: iso(e), area, location: '', notes: '' })
    onDone()
  }

  return (
    <div className="col cal-form" style={{ gap: 14 }}>
      <input className="plain" autoFocus placeholder="New event" value={title} onChange={(e) => setTitle(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter') add() }} style={{ fontSize: 20, fontWeight: 500 }} />
      <div className="row"><CalendarDays size={16} className="secondary" /><input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></div>
      <div className="row">
        <Clock size={16} className="secondary" />
        <input type="time" value={from} onChange={(e) => setFrom(e.target.value)} />
        <span className="muted">–</span>
        <input type="time" value={to} onChange={(e) => setTo(e.target.value)} />
      </div>
      <AreaPicker value={area} onChange={setArea} />
      <button className="btn-primary" disabled={!title.trim()} onClick={add}>Add</button>
    </div>
  )
}

function EventDetail({ entry, onDone }: { entry: Entry; onDone: () => void }) {
  return (
    <div className="col" style={{ gap: 12, fontSize: 13 }}>
      <h2 className="display" style={{ fontSize: 22, margin: 0 }}>{entry.title}</h2>
      <div className="row"><CalendarDays size={15} />{fmtDay(entry.start)}</div>
      <div className="row"><Clock size={15} />{fmtTime(entry.start)} – {fmtTime(entry.end)}</div>
      {entry.calendar ? <div className="row muted"><span style={{ width: 10, height: 10, borderRadius: '50%', background: entry.color }} />{entry.calendar}</div> : <>
      <AreaPicker value={entry.area} onChange={(a) => store.update<CalEvent>(entry.id, { area: a })} />
      <button className="btn-soft" style={{ alignSelf: 'flex-start', color: 'var(--critical)' }}
        onClick={() => { store.remove(entry.id); onDone() }}>
        <Trash2 size={14} />Delete event
      </button></>}
    </div>
  )
}
