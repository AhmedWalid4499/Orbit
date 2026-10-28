// Calendar on the phone, like PhoneCalendar in iOS/OrbitPhone/PhoneCalendar.swift: a week strip or month grid on top,
// the chosen day's events below (yours plus Google Calendar), then the tasks due that day. Swipe sideways to move.
// The new-event and event sheets are NewEventPopover / EventDetailPopover from CalendarWeekView.swift.
import { useRef, useState } from 'react'
import { ChevronLeft, ChevronRight, Plus, Calendar as CalIcon, Clock, Trash2 } from 'lucide-react'
import { store, useRecords } from '@/lib/store'
import { useExternalEvents } from '@/lib/externalEvents'
import { useKeys } from '@/lib/ai'
import { CalEvent, Task, Area, AREA_COLOR, areaOf } from '@/lib/models'
import { iso, parse, startOfDay, addDays, addMinutes, addMonths, sameDay, isToday, startOfMonth, startOfWeek, fmtTime, fromInputs, toDateInput, toTimeInput } from '@/lib/dates'
import { AreaPill, AreaPicker, Modal } from '@/components/ui'
import { TaskRow } from '@/components/TaskRow'
import { SectionTitle } from './pm2Kit'
import './pm2.css'

/** CalEntry: your own event or one from Google Calendar. */
interface Entry { id: string; title: string; start: Date; end: Date; allDay: boolean; area: Area | null; tint: string; calendar: string | null; local: boolean }

const narrow = (d: Date) => d.toLocaleDateString(undefined, { weekday: 'narrow' })

export default function PhoneCalendar() {
  const events = useRecords<CalEvent>('event')
  const google = useExternalEvents()
  const tasks = useRecords<Task>('task')
  const keys = useKeys()
  const [day, setDay] = useState(() => startOfDay(new Date()))
  const [showMonth, setShowMonth] = useState(false)
  const [adding, setAdding] = useState(false)
  const [detail, setDetail] = useState<Entry | null>(null)
  const touch = useRef<{ x: number; y: number } | null>(null)

  const all: Entry[] = [
    ...events.flatMap((r) => {
      const s = parse(r.data.start), e = parse(r.data.end)
      if (!s || !e) return []
      const area = areaOf(r.data.area)
      return [{ id: r.id, title: r.data.title, start: s, end: e, allDay: false, area, tint: AREA_COLOR[area], calendar: null, local: true }]
    }),
    ...google.map((g) => ({ id: `google-${g.id}`, title: g.title, start: g.start, end: g.end, allDay: g.allDay, area: null, tint: g.color, calendar: g.calendar || null, local: false })),
  ].sort((a, b) => a.start.getTime() - b.start.getTime())
  const entries = (from: Date, to: Date) => all.filter((e) => e.start >= from && e.start < to)

  const week = Array.from({ length: 7 }, (_, i) => addDays(startOfWeek(day), i))
  const monthDays = Array.from({ length: 42 }, (_, i) => addDays(startOfWeek(startOfMonth(day)), i))

  const move = (step: number) => setDay(showMonth ? startOfMonth(addMonths(day, step)) : addDays(day, 7 * step))

  const countBy = (list: Entry[]) => {
    const m = new Map<number, number>()
    for (const e of list) { const k = startOfDay(e.start).getTime(); m.set(k, (m.get(k) ?? 0) + 1) }
    return m
  }

  const list = entries(day, addDays(day, 1))
  const due = tasks.filter((t) => !t.data.isDone && sameDay(parse(t.data.due) ?? new Date(0), day))
  const googleOn = keys.gmail.length > 0 && localStorage.getItem('googleCalendarEnabled') !== 'false'

  const defaultStart = (() => {
    const hour = isToday(day) ? Math.min(new Date().getHours() + 1, 22) : 9
    const d = new Date(day); d.setHours(hour, 0, 0, 0); return d
  })()

  return (
    <div className="pm2"
      onTouchStart={(e) => { touch.current = { x: e.touches[0].clientX, y: e.touches[0].clientY } }}
      onTouchEnd={(e) => {
        const s = touch.current; touch.current = null
        if (!s || document.querySelector('.modal')) return
        const dx = e.changedTouches[0].clientX - s.x, dy = e.changedTouches[0].clientY - s.y
        if (Math.abs(dx) >= 30 && Math.abs(dx) > Math.abs(dy)) move(dx < 0 ? 1 : -1)
      }}>
      <SectionTitle>Calendar</SectionTitle>

      <div className="pm2-cal-nav">
        <button aria-label="Previous" onClick={() => move(-1)}><ChevronLeft size={20} strokeWidth={2.6} /></button>
        <h2 className="pm2-display">{day.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}</h2>
        <button aria-label="Next" onClick={() => move(1)}><ChevronRight size={20} strokeWidth={2.6} /></button>
      </div>

      <div className="pm2-seg">
        <button className={!showMonth ? 'on' : ''} onClick={() => setShowMonth(false)}>Week</button>
        <button className={showMonth ? 'on' : ''} onClick={() => setShowMonth(true)}>Month</button>
      </div>

      {showMonth ? (() => {
        const counts = countBy(entries(monthDays[0], addDays(monthDays[41], 1)))
        return (
          <div className="pm2-month">
            {monthDays.slice(0, 7).map((d) => <div key={`h${d.getTime()}`} className="h">{narrow(d)}</div>)}
            {monthDays.map((d) => {
              const n = counts.get(d.getTime()) ?? 0
              const inMonth = d.getMonth() === day.getMonth() && d.getFullYear() === day.getFullYear()
              return (
                <button key={d.getTime()} className={`pm2-mday ${sameDay(d, day) ? 'sel' : isToday(d) ? 'today' : ''}`}
                  style={{ opacity: inMonth ? 1 : 0.35, fontWeight: isToday(d) ? 700 : 400 }} onClick={() => setDay(d)}>
                  <span>{d.getDate()}</span>
                  <span className="dots">{Array.from({ length: Math.min(n, 3) }, (_, i) => <i key={i} />)}</span>
                </button>
              )
            })}
          </div>
        )
      })() : (() => {
        const counts = countBy(entries(week[0], addDays(week[6], 1)))
        return (
          <div className="pm2-week">
            {week.map((d) => (
              <button key={d.getTime()} className={`pm2-wday ${sameDay(d, day) ? 'sel' : isToday(d) ? 'today' : ''}`} onClick={() => setDay(d)}>
                <span className="w">{narrow(d)}</span>
                <span className={`n ${isToday(d) ? 'today' : ''}`}>{d.getDate()}</span>
                <span className="pm2-dot" style={{ opacity: (counts.get(d.getTime()) ?? 0) > 0 ? 1 : 0 }} />
              </button>
            ))}
          </div>
        )
      })()}

      <div className="pm2-row">
        <h2 className="pm2-display" style={{ fontSize: 22, margin: 0, minWidth: 0 }}>
          {isToday(day) ? 'Today' : day.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' })}
        </h2>
        <span className="pm2-spacer" />
        {!isToday(day) && <button className="pm2-soft" onClick={() => setDay(startOfDay(new Date()))}>Today</button>}
        <button className="pm2-soft" onClick={() => setAdding(true)}><Plus size={15} />Event</button>
      </div>

      {list.length === 0 && (
        <div className="pm2-empty"><CalIcon size={15} />
          {googleOn ? 'Nothing on this day.' : 'Nothing here yet. Connect Google Calendar in Settings to see all your calendars.'}
        </div>
      )}
      {list.map((e) => <AgendaRow key={e.id} entry={e} onClick={() => setDetail(e)} />)}

      {due.length > 0 && (
        <>
          <div className="pm2-secondary" style={{ fontSize: 13, fontWeight: 600, marginTop: 6 }}>Tasks due</div>
          {due.map((t) => <TaskRow key={t.id} rec={t} showDue={false} />)}
        </>
      )}

      <Modal open={adding} onClose={() => setAdding(false)}>
        {adding && <NewEvent start={defaultStart} onDone={() => setAdding(false)} />}
      </Modal>
      <Modal open={!!detail} onClose={() => setDetail(null)}>
        {detail && <EventDetail entry={detail} onDone={() => setDetail(null)} />}
      </Modal>
    </div>
  )
}

/** AgendaRow in TodayView.swift. */
function AgendaRow({ entry: e, onClick }: { entry: Entry; onClick: () => void }) {
  const now = new Date()
  return (
    <button className="pm2-agenda" style={{ opacity: e.end < now ? 0.5 : 1 }} onClick={onClick}>
      <span className="time">
        <b>{e.allDay ? 'All day' : fmtTime(e.start)}</b>
        {!e.allDay && <span>{fmtTime(e.end)}</span>}
      </span>
      <span className="bar" style={{ background: e.tint }} />
      <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
        <span className="clamp1" style={{ fontSize: 13, fontWeight: 500 }}>{e.title}</span>
        {e.calendar && <span className="pm2-muted" style={{ fontSize: 10 }}>{e.calendar}</span>}
      </span>
      {e.area && <AreaPill area={e.area} compact />}
      {e.start <= now && e.end > now && <span className="pm2-now">Now</span>}
    </button>
  )
}

/** NewEventPopover: title, date, from–to, area. */
function NewEvent({ start, onDone }: { start: Date; onDone: () => void }) {
  const [title, setTitle] = useState('')
  const [date, setDate] = useState(toDateInput(start))
  const [from, setFrom] = useState(toTimeInput(start))
  const [to, setTo] = useState(toTimeInput(addMinutes(start, 60)))
  const [area, setArea] = useState<Area>('personal')

  // Moving the start keeps the length (onChange(of: from) on the Mac).
  const changeFrom = (v: string) => {
    if (!v) return
    const old = fromInputs(date, from), next = fromInputs(date, v)
    setTo(toTimeInput(addMinutes(fromInputs(date, to), Math.round((next.getTime() - old.getTime()) / 60_000))))
    setFrom(v)
  }
  const add = () => {
    const t = title.trim()
    if (!t) return
    const s = fromInputs(date, from)
    let e = fromInputs(date, to)
    if (e < addMinutes(s, 15)) e = addMinutes(s, 15)
    store.create<CalEvent>('event', { title: t, start: iso(s), end: iso(e), area, location: '', notes: '' })
    onDone()
  }

  return (
    <div className="pm2-sheet">
      <input className="pm2-plain" autoFocus placeholder="New event" value={title} onChange={(e) => setTitle(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter') add() }} style={{ fontSize: 20, fontWeight: 500 }} />
      <div className="pm2-row" style={{ gap: 10 }}>
        <CalIcon size={17} color="var(--ink2)" />
        <input type="date" className="pm2-input" style={{ width: 'auto' }} value={date} onChange={(e) => e.target.value && setDate(e.target.value)} />
      </div>
      <div className="pm2-row" style={{ gap: 10 }}>
        <Clock size={17} color="var(--ink2)" />
        <input type="time" className="pm2-input" style={{ width: 'auto' }} value={from} onChange={(e) => changeFrom(e.target.value)} />
        <span className="pm2-muted">–</span>
        <input type="time" className="pm2-input" style={{ width: 'auto' }} value={to} onChange={(e) => e.target.value && setTo(e.target.value)} />
      </div>
      <AreaPicker value={area} onChange={setArea} />
      <button className="pm2-primary" disabled={!title.trim()} onClick={add}>Add</button>
    </div>
  )
}

/** EventDetailPopover: when, and for your own events the area and Delete. */
function EventDetail({ entry, onDone }: { entry: Entry; onDone: () => void }) {
  const rec = entry.local ? store.get<CalEvent>(entry.id) : undefined
  const [area, setArea] = useState<Area>(entry.area ?? 'personal')
  return (
    <div className="pm2-sheet" style={{ gap: 12, fontSize: 13 }}>
      <h2 className="pm2-display" style={{ fontSize: 22 }}>{entry.title}</h2>
      <div className="pm2-row"><CalIcon size={15} />{entry.start.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' })}</div>
      <div className="pm2-row"><Clock size={15} />{entry.allDay ? 'All day' : `${fmtTime(entry.start)} – ${fmtTime(entry.end)}`}</div>
      {!entry.local && <div className="pm2-row pm2-secondary"><span style={{ width: 10, height: 10, borderRadius: '50%', background: entry.tint }} />From {entry.calendar ?? 'Google'} (Google Calendar)</div>}
      {rec && (
        <>
          <AreaPicker value={area} onChange={(a) => { setArea(a); store.update<CalEvent>(rec.id, { area: a }) }} />
          <button className="pm2-soft pm2-danger" style={{ alignSelf: 'flex-start' }} onClick={() => { store.remove(rec.id); onDone() }}>
            <Trash2 size={14} />Delete event
          </button>
        </>
      )}
    </div>
  )
}
