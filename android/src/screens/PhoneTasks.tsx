// Tasks on the phone, like PhoneTasks.swift on iPhone: the Mac's filters as chips (plus Shared lists), one Area menu,
// the smart add bar, and swipe actions on each row (right: Done; left: Focus, Tomorrow, Delete).
import { useEffect, useRef, useState, ReactNode } from 'react'
import { Sun, CalendarDays, Inbox, CheckCircle2, Users, ChevronDown, Plus, Mic, Square, Check, Undo2, Trash2, ArrowRight, Timer, BadgeCheck,
  Repeat as RepeatIcon, AlarmClock, MapPin, Footprints } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Task, Area, AREAS, AREA_COLOR, Repeat, areaOf, cap } from '@/lib/models'
import { iso, parse, startOfDay, addDays, addMonths, relativeDay, sameDay, fmtTime, toDateInput, toTimeInput, fromInputs } from '@/lib/dates'
import { EmptyHint, AreaPill, AreaPicker, CheckCircle, Modal } from '@/components/ui'
import { openFocus, useActiveFocus } from '@/lib/focus'
import { PtSwitch } from '../components/PtCommon'
import { parseTask } from '@/screens/Tasks'
import { isNative, native } from '../native'
import { useSharedLists, refresh as refreshShared } from '../lib/sharedLists'
import SharedLists from './SharedLists'

type Filter = 'today' | 'upcoming' | 'inbox' | 'completed' | 'shared'

const FILTERS: { id: Filter; title: string; icon: ReactNode }[] = [
  { id: 'today', title: 'Today', icon: <Sun size={12} strokeWidth={2.5} /> },
  { id: 'upcoming', title: 'Upcoming', icon: <CalendarDays size={12} strokeWidth={2.5} /> },
  { id: 'inbox', title: 'Anytime', icon: <Inbox size={12} strokeWidth={2.5} /> },
  { id: 'completed', title: 'Done', icon: <CheckCircle2 size={12} strokeWidth={2.5} /> },
  { id: 'shared', title: 'Shared lists', icon: <Users size={12} strokeWidth={2.5} /> },
]

/** A task with the reminder fields the Mac encodes (TaskItem.remindAt and its place reminder). */
type PTask = Task & { remindAt?: string | null; place?: { name: string; lat: number; lon: number; onLeave: boolean } | null }

const AREA_KEY = 'tasksArea'
const readArea = (): Area | null => {
  try { const v = localStorage.getItem(AREA_KEY) ?? ''; return AREAS.includes(v as Area) ? (v as Area) : null } catch { return null }
}

const dueTime = (t: Rec<Task>, fallback: number): number => parse(t.data.due)?.getTime() ?? fallback
const sortOpen = (list: Rec<Task>[]): Rec<Task>[] => [...list].sort((a, b) => {
  const pa = a.data.priority ?? 0, pb = b.data.priority ?? 0
  if (pa !== pb) return pb - pa
  return dueTime(a, Infinity) - dueTime(b, Infinity)
})

export default function PhoneTasks() {
  const tasks = useRecords<Task>('task')
  const shared = useSharedLists()
  const [filter, setFilter] = useState<Filter>('today')
  const [area, setAreaState] = useState<Area | null>(readArea)
  const [draft, setDraft] = useState('')
  const [listening, setListening] = useState(false)

  const setArea = (a: Area | null) => {
    setAreaState(a)
    try { localStorage.setItem(AREA_KEY, a ?? '') } catch { /* storage unavailable */ }
  }

  useEffect(() => { refreshShared() }, [])
  useEffect(() => { if (!shared.isSetUp && filter === 'shared') setFilter('today') }, [shared.isSetUp, filter])
  useEffect(() => () => { if (isNative) native.stopListening().catch(() => {}) }, [])

  const today = startOfDay(new Date())
  const tomorrow = addDays(today, 1)

  const itemsFor = (f: Filter): Rec<Task>[] => {
    const inArea = (t: Rec<Task>) => area === null || areaOf(t.data.area) === area
    const open = tasks.filter((t) => !t.data.isDone && inArea(t))
    switch (f) {
      case 'today': return sortOpen(open.filter((t) => dueTime(t, Infinity) < tomorrow.getTime()))
      case 'upcoming': return sortOpen(open.filter((t) => dueTime(t, -Infinity) >= tomorrow.getTime()))
      case 'inbox': return sortOpen(open.filter((t) => !parse(t.data.due)))
      case 'completed': return tasks.filter((t) => t.data.isDone && inArea(t))
        .sort((a, b) => (parse(b.data.completedAt)?.getTime() ?? Date.now()) - (parse(a.data.completedAt)?.getTime() ?? Date.now()))
      case 'shared': return []
    }
  }

  const filters = FILTERS.filter((f) => f.id !== 'shared' || shared.isSetUp)
  const parsed = draft.trim() ? parseTask(draft) : null
  const summary = parsed && parsed.title
    ? ['Task', parsed.due ? relativeDay(parsed.due) : null, parsed.area ? cap(parsed.area) : null, parsed.priority ? '!'.repeat(parsed.priority) : null]
      .filter(Boolean).join(' · ')
    : null

  const add = (text = draft) => {
    const p = parseTask(text)
    if (!p.title) return
    let due = p.due
    if (filter === 'today' && !due) due = today
    // Every field the Mac's CloudSync encodes for a task.
    store.create('task', {
      title: p.title, notes: '', area: p.area ?? area ?? 'personal', due: due ? iso(due) : null, priority: p.priority,
      isDone: false, completedAt: null, createdAt: iso(new Date()), repeat: 'none',
      remindAt: null, place: { name: '', lat: 0, lon: 0, onLeave: false },
    })
    setDraft('')
  }

  const listen = async () => {
    if (listening) { native.stopListening().catch(() => {}); return }
    setListening(true)
    const partial = await native.addListener('partial', (d) => setDraft(d.text))
    try {
      const { text } = await native.listen({})
      if (text.trim()) add(text)
    } catch { /* no match or cancelled */ } finally {
      partial.remove()
      setListening(false)
    }
  }

  const list = itemsFor(filter)

  return (
    <div className="page col" style={{ gap: 12 }}>

      <div className="row" style={{ gap: 8, overflowX: 'auto', margin: '0 -16px', padding: '0 16px 2px', scrollbarWidth: 'none' }}>
        {filters.map((f) => {
          const n = f.id === 'shared' || f.id === 'completed' ? 0 : itemsFor(f.id).length
          const on = filter === f.id
          return (
            <button key={f.id} onClick={() => setFilter(f.id)} style={{
              display: 'inline-flex', alignItems: 'center', gap: 5, flex: 'none', whiteSpace: 'nowrap', fontSize: 13, fontWeight: 600,
              padding: '8px 12px', borderRadius: 999, background: on ? 'var(--inverse)' : 'var(--card)', color: on ? 'var(--on-inverse)' : 'var(--ink)',
            }}>
              {f.icon}{f.title}{n > 0 && <span style={{ opacity: 0.6 }}>{n}</span>}
            </button>
          )
        })}
        {/* One menu for the seven areas, instead of a chip each. */}
        <label style={{
          position: 'relative', display: 'inline-flex', alignItems: 'center', gap: 5, flex: 'none', whiteSpace: 'nowrap', fontSize: 13, fontWeight: 600,
          padding: '8px 12px', borderRadius: 999, color: 'var(--ink)',
          background: area ? `color-mix(in srgb, ${AREA_COLOR[area]} 35%, transparent)` : 'var(--card)',
        }}>
          <span style={{ width: 7, height: 7, borderRadius: '50%', background: area ? AREA_COLOR[area] : 'var(--ink3)' }} />
          {area ? cap(area) : 'Area'}
          <ChevronDown size={11} strokeWidth={3} />
          <select aria-label="Area" value={area ?? ''} onChange={(e) => setArea((e.target.value || null) as Area | null)}
            style={{ position: 'absolute', inset: 0, opacity: 0, width: '100%', height: '100%' }}>
            <option value="">All areas</option>
            {AREAS.map((a) => <option key={a} value={a}>{cap(a)}</option>)}
          </select>
        </label>
      </div>

      {filter !== 'shared' && (
        <div className="col" style={{ gap: 6 }}>
          <div className="row" style={{ gap: 10, background: 'var(--card)', borderRadius: 14, padding: '6px 6px 6px 14px', minHeight: 48 }}>
            <Plus size={16} className="muted" style={{ flex: 'none' }} />
            <input className="plain" style={{ fontSize: 15 }} value={draft} enterKeyHint="done"
              placeholder={listening ? 'Listening…' : 'Add a task: “pay rent friday #money !!”'}
              onChange={(e) => setDraft(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') add() }} />
            {isNative && (
              <button className={`ask-btn ${listening ? 'live' : ''}`} aria-label={listening ? 'Stop' : 'Talk'} onClick={listen}>
                {listening ? <Square size={14} /> : <Mic size={17} />}
              </button>
            )}
          </div>
          {summary && <div className="secondary" style={{ fontSize: 12, paddingLeft: 4 }}>{summary}</div>}
        </div>
      )}

      {filter === 'shared' ? <SharedLists /> : filter === 'upcoming' ? <Upcoming list={list} /> : (
        <div className="col" style={{ gap: 6 }}>
          {!list.length && (filter === 'completed'
            ? <EmptyHint icon={<CheckCircle2 size={14} />} text="Nothing completed yet." />
            : <EmptyHint icon={<BadgeCheck size={14} />} text="Nothing here. Nice." />)}
          {list.map((t) => {
            const due = parse(t.data.due)
            const overdue = !!due && !t.data.isDone && due < today
            return <SwipeTask key={t.id} rec={t} showDue={filter !== 'today' || overdue} />
          })}
        </div>
      )}
    </div>
  )
}

function Upcoming({ list }: { list: Rec<Task>[] }) {
  const groups = new Map<number, Rec<Task>[]>()
  for (const t of list) {
    const d = startOfDay(parse(t.data.due)!).getTime()
    groups.set(d, [...(groups.get(d) ?? []), t])
  }
  const days = [...groups.keys()].sort((a, b) => a - b)
  if (!days.length) return <EmptyHint icon={<CalendarDays size={14} />} text="Nothing planned yet." />
  return (
    <div className="col" style={{ gap: 6 }}>
      {days.map((d) => {
        const day = new Date(d)
        const date = day.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
        const rel = relativeDay(day)
        return (
          <div key={d} className="col" style={{ gap: 6 }}>
            <div style={{ fontSize: 13, fontWeight: 600, paddingTop: 8 }}>
              {rel === date ? day.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'short' }) : `${rel} · ${date}`}
            </div>
            {groups.get(d)!.map((t) => <SwipeTask key={t.id} rec={t} showDue={false} />)}
          </div>
        )
      })}
    </div>
  )
}

// MARK: Swipe actions

interface SwipeAction { label: string; icon: ReactNode; color: string; run: () => void }

function SwipeTask({ rec, showDue }: { rec: Rec<Task>; showDue: boolean }) {
  const done = rec.data.isDone
  const leading: SwipeAction[] = [
    { label: done ? 'Undo' : 'Done', icon: done ? <Undo2 size={17} /> : <Check size={17} strokeWidth={2.5} />, color: 'var(--good)', run: () => toggleTask(rec) },
  ]
  // First is outermost, as in SwiftUI's swipeActions.
  const trailing: SwipeAction[] = [
    { label: 'Delete', icon: <Trash2 size={17} />, color: 'var(--critical)', run: () => store.remove(rec.id) },
    { label: 'Tomorrow', icon: <ArrowRight size={17} />, color: 'var(--orange)', run: () => store.update<Task>(rec.id, { due: iso(addDays(startOfDay(new Date()), 1)) }) },
    ...(done ? [] : [{ label: 'Focus', icon: <Timer size={17} />, color: 'var(--purple)', run: () => openFocus(rec) }]),
  ]
  return (
    <SwipeRow leading={leading} trailing={trailing}>
      <PhoneTaskRow rec={rec} showDue={showDue} />
    </SwipeRow>
  )
}

/** The one row whose actions are showing; opening another closes it. */
let closeOpenRow: (() => void) | null = null

const ACTION_W = 74

function SwipeRow({ leading, trailing, children }: { leading: SwipeAction[]; trailing: SwipeAction[]; children: ReactNode }) {
  const [x, setX] = useState(0)
  const [dragging, setDragging] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const drag = useRef<{ id: number; x0: number; y0: number; base: number; axis: 'h' | 'v' | null } | null>(null)
  const suppressClick = useRef(false)
  const xRef = useRef(0)
  const maxRight = leading.length * ACTION_W
  const maxLeft = trailing.length * ACTION_W

  const move = (v: number) => { xRef.current = v; setX(v) }
  const closeRef = useRef(() => { xRef.current = 0; setX(0); if (closeOpenRow === closeRef.current) closeOpenRow = null })
  const close = closeRef.current
  useEffect(() => () => { if (closeOpenRow === closeRef.current) closeOpenRow = null }, [])
  // Events from the row's own sheets (the editor, its menu) aren't swipes.
  const inSheet = (e: React.SyntheticEvent) => !!(e.target as Element).closest?.('.backdrop')

  const onPointerDown = (e: React.PointerEvent) => {
    if ((e.pointerType === 'mouse' && e.button !== 0) || inSheet(e)) return
    drag.current = { id: e.pointerId, x0: e.clientX, y0: e.clientY, base: xRef.current, axis: null }
  }
  const onPointerMove = (e: React.PointerEvent) => {
    const d = drag.current
    if (!d || d.id !== e.pointerId) return
    const dx = e.clientX - d.x0, dy = e.clientY - d.y0
    if (!d.axis) {
      if (Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy)) {
        d.axis = 'h'
        setDragging(true)
        try { ref.current?.setPointerCapture(e.pointerId) } catch { /* pointer already gone */ }
        if (closeOpenRow && closeOpenRow !== close) closeOpenRow()
      } else if (Math.abs(dy) > 8) { d.axis = 'v'; return } else return
    }
    if (d.axis !== 'h') return
    const width = ref.current?.offsetWidth ?? 360
    let v = d.base + dx
    // No actions on a side: a little give, then stop.
    if (v > 0 && !leading.length) v = Math.min(v * 0.25, 24)
    if (v < 0 && !trailing.length) v = Math.max(v * 0.25, -24)
    move(Math.max(-width, Math.min(width, v)))
  }
  const onPointerEnd = (e: React.PointerEvent) => {
    const d = drag.current
    if (!d || d.id !== e.pointerId) return
    drag.current = null
    if (d.axis !== 'h') return
    setDragging(false)
    suppressClick.current = true
    setTimeout(() => { suppressClick.current = false }, 50)
    const width = ref.current?.offsetWidth ?? 360
    const v = xRef.current
    // A long swipe runs the outermost action, as on iPhone.
    if (v < -width * 0.6 && trailing.length) { close(); trailing[0].run(); return }
    if (v > width * 0.6 && leading.length) { close(); leading[0].run(); return }
    if (v < -maxLeft / 2 && trailing.length) { move(-maxLeft); closeOpenRow = close }
    else if (v > maxRight / 2 && leading.length) { move(maxRight); closeOpenRow = close }
    else close()
  }
  const onClickCapture = (e: React.MouseEvent) => {
    // A swipe isn't a tap, and a tap on an open row just closes it.
    if (inSheet(e)) return
    if (suppressClick.current || xRef.current !== 0) {
      e.preventDefault(); e.stopPropagation()
      if (!suppressClick.current) close()
    }
  }

  const tap = (a: SwipeAction) => { close(); a.run() }
  const panel = (actions: SwipeAction[], side: 'left' | 'right') => (
    <div style={{ position: 'absolute', top: 0, bottom: 0, [side]: 0, width: Math.abs(x), display: 'flex', flexDirection: side === 'right' ? 'row-reverse' : 'row', overflow: 'hidden' }}>
      {actions.map((a) => (
        <button key={a.label} onClick={() => tap(a)} style={{
          flex: 1, minWidth: 0, background: a.color, color: '#fff', display: 'flex', flexDirection: 'column', alignItems: 'center',
          justifyContent: 'center', gap: 3, fontSize: 11, fontWeight: 600, overflow: 'hidden', whiteSpace: 'nowrap',
        }}>
          {a.icon}{a.label}
        </button>
      ))}
    </div>
  )

  return (
    <div style={{ position: 'relative', overflow: 'hidden', borderRadius: 12, flex: 'none' }}>
      {x > 0 && panel(leading, 'left')}
      {x < 0 && panel(trailing, 'right')}
      <div ref={ref} onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerEnd} onPointerCancel={onPointerEnd}
        onClickCapture={onClickCapture}
        style={{
          position: 'relative', touchAction: 'pan-y', background: 'var(--canvas)',
          // No transform at rest: the row's editor sheet is position: fixed and a transform would trap it.
          transform: x ? `translateX(${x}px)` : undefined,
          transition: dragging ? 'none' : 'transform 0.2s ease-out',
        }}>
        {children}
      </div>
    </div>
  )
}

// MARK: The row (TaskRow in TodayView.swift)

/** Marks a task done; a repeating one gets its next occurrence with the same reminders (TaskItem.complete on the Mac). */
function completeTask(rec: Rec<PTask>): void {
  const t = rec.data
  store.update<PTask>(rec.id, { isDone: true, completedAt: iso(new Date()) })
  const due = parse(t.due)
  const repeat = t.repeat ?? 'none'
  if (!due || repeat === 'none') return
  const next = repeat === 'daily' ? addDays(due, 1) : repeat === 'weekly' ? addDays(due, 7) : addMonths(due, 1)
  const remind = parse(t.remindAt ?? null)
  const remindNext = remind ? new Date(startOfDay(next).getTime() + (remind.getTime() - startOfDay(remind).getTime())) : null
  store.create<PTask>('task', {
    title: t.title, notes: t.notes ?? '', area: areaOf(t.area), due: iso(next), priority: t.priority ?? 0,
    isDone: false, completedAt: null, createdAt: iso(new Date()), repeat,
    remindAt: remindNext ? iso(remindNext) : null, place: t.place ?? { name: '', lat: 0, lon: 0, onLeave: false },
  })
}

function toggleTask(rec: Rec<PTask>): void {
  if (rec.data.isDone) store.update<PTask>(rec.id, { isDone: false, completedAt: null })
  else completeTask(rec)
}

const hasPlace = (t: PTask) => !!t.place && !!t.place.name && (t.place.lat !== 0 || t.place.lon !== 0)

function PhoneTaskRow({ rec, showDue }: { rec: Rec<Task>; showDue: boolean }) {
  const t = rec.data as PTask
  const [editing, setEditing] = useState(false)
  const focus = useActiveFocus()
  const focusing = !!focus && focus.data.taskUUID === rec.id
  const due = parse(t.due)
  const overdue = !!due && !t.isDone && due < startOfDay(new Date())
  const repeat = t.repeat ?? 'none'
  const remind = parse(t.remindAt ?? null)
  const place = hasPlace(t) && !t.isDone
  const meta = (showDue && due) || repeat !== 'none' || (remind && !t.isDone) || place
  return (
    <>
      <div className="row task-row" style={{ gap: 12, padding: '8px 12px', background: 'var(--canvas)', borderRadius: 12, minHeight: 48 }}>
        <CheckCircle on={t.isDone} onClick={() => toggleTask(rec as Rec<PTask>)} />
        <div style={{ flex: 1, minWidth: 0, cursor: 'pointer' }} onClick={() => setEditing(true)}>
          <div style={{ fontSize: 14, fontWeight: 500, color: t.isDone ? 'var(--ink3)' : 'var(--ink)', textDecoration: t.isDone ? 'line-through' : 'none' }}>
            {t.title || 'Untitled'}
          </div>
          {meta && (
            <div className="row" style={{ gap: 8, fontSize: 11, marginTop: 3, flexWrap: 'wrap', color: 'var(--ink3)' }}>
              {showDue && due && <span className="row" style={{ gap: 3, color: overdue ? 'var(--critical)' : 'var(--ink3)' }}><CalendarDays size={11} />{relativeDay(due)}</span>}
              {repeat !== 'none' && <span className="row" style={{ gap: 3 }}><RepeatIcon size={11} />{cap(repeat)}</span>}
              {remind && !t.isDone && (
                <span className="row" style={{ gap: 3 }}><AlarmClock size={11} />{sameDay(remind, new Date()) ? fmtTime(remind) : `${relativeDay(remind)} ${fmtTime(remind)}`}</span>
              )}
              {place && <span className="row" style={{ gap: 3 }}>{t.place!.onLeave ? <Footprints size={11} /> : <MapPin size={11} />}{t.place!.name}</span>}
            </div>
          )}
        </div>
        {focusing && <Timer size={13} strokeWidth={2.5} color="var(--orange)" aria-label="Focusing on this" />}
        {t.priority > 0 && (
          <span style={{ fontWeight: 800, fontSize: 13, color: t.priority === 3 ? 'var(--critical)' : 'var(--ink2)' }}>{'!'.repeat(t.priority)}</span>
        )}
        <AreaPill area={areaOf(t.area)} compact />
      </div>
      {editing && <PhoneTaskEditor rec={rec as Rec<PTask>} onClose={() => setEditing(false)} />}
    </>
  )
}

// MARK: The editor (TaskEditor in TasksView.swift, with ReminderSection)

const REPEATS: { id: Repeat; title: string }[] = [
  { id: 'none', title: 'Never' }, { id: 'daily', title: 'Daily' }, { id: 'weekly', title: 'Weekly' }, { id: 'monthly', title: 'Monthly' },
]
const PRIORITIES = ['None', 'Low', 'Medium', 'High']

function PhoneTaskEditor({ rec, onClose }: { rec: Rec<PTask>; onClose: () => void }) {
  const live = useRecords<PTask>('task').find((r) => r.id === rec.id) ?? rec
  const t = live.data
  const set = (patch: Partial<PTask>) => store.update<PTask>(rec.id, patch)
  const due = parse(t.due)
  const remind = parse(t.remindAt ?? null)
  // The due day at 9:00, or an hour from now.
  const defaultRemind = () => {
    if (due && due > new Date()) { const d = startOfDay(due); d.setHours(9, 0, 0, 0); return d }
    return new Date(Date.now() + 3600_000)
  }
  return (
    <Modal open onClose={onClose} width={520}>
      {/* Above the column, so the sheet's floating close button doesn't narrow everything below it. */}
      <div className="pt-sheet-head" style={{ paddingRight: 40 }}>
        <input className="plain display" style={{ fontSize: 26, width: '100%' }} value={t.title} placeholder="Title" onChange={(e) => set({ title: e.target.value })} />
      </div>
      <div className="col" style={{ gap: 18 }}>
        <AreaPicker value={areaOf(t.area)} onChange={(a) => set({ area: a })} />
        <div className="pt-form">
          <span className="k">Due</span>
          <div className="row" style={{ gap: 10 }}>
            <PtSwitch label="Due date" on={!!due} onChange={(on) => set({ due: on ? iso(startOfDay(new Date())) : null })} />
            {due && <input type="date" className="field" style={{ width: 'auto', padding: '6px 10px' }} value={toDateInput(due)}
              onChange={(e) => e.target.value && set({ due: iso(fromInputs(e.target.value)) })} />}
          </div>
          <span className="k">Priority</span>
          <div className="seg" style={{ display: 'flex', background: 'var(--card)', borderRadius: 10, padding: 2 }}>
            {PRIORITIES.map((p, i) => (
              <button key={p} onClick={() => set({ priority: i })} style={{
                flex: 1, padding: '6px 0', borderRadius: 8, fontSize: 12, fontWeight: 600,
                background: (t.priority ?? 0) === i ? 'var(--canvas)' : 'transparent', color: 'var(--ink)',
                boxShadow: (t.priority ?? 0) === i ? '0 1px 3px rgba(0,0,0,0.12)' : 'none',
              }}>{p}</button>
            ))}
          </div>
          <span className="k">Repeat</span>
          <select className="field" style={{ width: 'auto', padding: '6px 10px' }} value={t.repeat ?? 'none'} onChange={(e) => set({ repeat: e.target.value as Repeat })}>
            {REPEATS.map((r) => <option key={r.id} value={r.id}>{r.title}</option>)}
          </select>
        </div>

        <div className="col" style={{ gap: 10 }}>
          <span className="secondary" style={{ fontSize: 13 }}>Remind me</span>
          <div className="row" style={{ gap: 10, fontSize: 13 }}>
            <AlarmClock size={15} />
            <span style={{ flex: 1 }}>At a time</span>
            <PtSwitch label="Remind me at a time" on={!!remind} onChange={(on) => set({ remindAt: on ? iso(remind ?? defaultRemind()) : null })} />
          </div>
          {remind && (
            <div className="row" style={{ gap: 8 }}>
              <input type="date" className="field" style={{ flex: 1, padding: '6px 10px' }} value={toDateInput(remind)}
                onChange={(e) => e.target.value && set({ remindAt: iso(fromInputs(e.target.value, toTimeInput(remind))) })} />
              <input type="time" className="field" style={{ width: 140, flex: 'none', padding: '6px 10px' }} value={toTimeInput(remind)}
                onChange={(e) => e.target.value && set({ remindAt: iso(fromInputs(toDateInput(remind), e.target.value)) })} />
            </div>
          )}
          {hasPlace(t) && (
            <div className="row" style={{ gap: 8, fontSize: 13 }}>
              <MapPin size={15} />
              <span style={{ flex: 1, minWidth: 0 }}>{t.place!.name} · {t.place!.onLeave ? 'When I leave' : 'When I arrive'}</span>
              <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => set({ place: { name: '', lat: 0, lon: 0, onLeave: false } })}>Remove</button>
            </div>
          )}
          {hasPlace(t) && <span className="muted" style={{ fontSize: 11 }}>Place reminders go off on your iPhone.</span>}
        </div>

        <div className="col" style={{ gap: 8 }}>
          <span className="secondary" style={{ fontSize: 13 }}>Notes</span>
          <textarea className="field" rows={5} style={{ fontSize: 14 }} value={t.notes ?? ''} onChange={(e) => set({ notes: e.target.value })} />
        </div>
        <div className="row">
          <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(rec.id); onClose() }}>Delete</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120, minHeight: 44 }} onClick={onClose}>Done</button>
        </div>
      </div>
    </Modal>
  )
}
