import { useMemo, useState, ReactNode } from 'react'
import { Sun, CalendarDays, Inbox, List, CheckCircle2, Plus } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Task, Area, AREAS, AREA_COLOR, areaOf, cap } from '@/lib/models'
import { iso, parse, startOfDay, addDays, relativeDay } from '@/lib/dates'
import { EmptyHint } from '@/components/ui'
import { TaskRow } from '@/components/TaskRow'

type Filter = 'today' | 'upcoming' | 'inbox' | 'all' | 'completed' | `area:${Area}`

const FILTERS: { id: Filter; title: string; icon: ReactNode }[] = [
  { id: 'today', title: 'Today', icon: <Sun size={13} /> },
  { id: 'upcoming', title: 'Upcoming', icon: <CalendarDays size={13} /> },
  { id: 'inbox', title: 'No date', icon: <Inbox size={13} /> },
  { id: 'all', title: 'All open', icon: <List size={13} /> },
  { id: 'completed', title: 'Completed', icon: <CheckCircle2 size={13} /> },
]

// MARK: Quick add parsing (a small version of QuickParser.swift)

interface Parsed { title: string; area: Area | null; due: Date | null; priority: number }

const WEEKDAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']
const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec']

export function parseTask(raw: string): Parsed {
  let text = ` ${raw.trim()} `
  let area: Area | null = null
  let priority = 0
  let due: Date | null = null
  const today = startOfDay(new Date())

  const tag = text.match(/\s#(\w+)/)
  if (tag) {
    const a = AREAS.find((x) => x.startsWith(tag[1].toLowerCase()))
    if (a) { area = a; text = text.replace(tag[0], ' ') }
  }
  const bang = text.match(/\s(!{1,3})(?=\s)/)
  if (bang) { priority = bang[1].length; text = text.replace(bang[0], ' ') }

  const rules: [RegExp, (m: RegExpMatchArray) => Date | null][] = [
    [/\s(?:on\s|by\s)?today(?=\s)/i, () => today],
    [/\s(?:on\s|by\s)?tonight(?=\s)/i, () => today],
    [/\s(?:on\s|by\s)?tomorrow(?=\s)/i, () => addDays(today, 1)],
    [/\s(?:on\s|by\s)?next week(?=\s)/i, () => addDays(today, 7)],
    [/\s(?:on\s|by\s)?(?:next\s)?(sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)(?:day|nesday|sday|urday)?(?=\s)/i, (m) => {
      const idx = WEEKDAYS.findIndex((w) => w.startsWith(m[1].toLowerCase().slice(0, 3)))
      let n = (idx - today.getDay() + 7) % 7
      if (n === 0) n = 7
      if (/next/i.test(m[0])) n += n < 7 ? 7 : 0
      return addDays(today, n)
    }],
    [/\s(?:on\s|by\s)?(\d{1,2})(?:st|nd|rd|th)?\s(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*(?=\s)/i, (m) => monthDay(Number(m[1]), m[2])],
    [/\s(?:on\s|by\s)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s(\d{1,2})(?:st|nd|rd|th)?(?=\s)/i, (m) => monthDay(Number(m[2]), m[1])],
    [/\sin (\d+) days?(?=\s)/i, (m) => addDays(today, Number(m[1]))],
  ]
  function monthDay(day: number, mon: string): Date | null {
    const mi = MONTHS.indexOf(mon.toLowerCase().slice(0, 3))
    if (mi < 0 || day < 1 || day > 31) return null
    let d = new Date(today.getFullYear(), mi, day)
    if (d < today) d = new Date(today.getFullYear() + 1, mi, day)
    return d
  }
  for (const [re, fn] of rules) {
    const m = text.match(re)
    if (m) {
      const d = fn(m)
      if (d) { due = d; text = text.replace(m[0], ' '); break }
    }
  }
  const title = text.replace(/\s+/g, ' ').trim().replace(/^[\s,.;:-]+|[\s,.;:-]+$/g, '')
  return { title, area, due, priority }
}

function sortTasks(list: Rec<Task>[]): Rec<Task>[] {
  return [...list].sort((a, b) => {
    if ((a.data.priority ?? 0) !== (b.data.priority ?? 0)) return (b.data.priority ?? 0) - (a.data.priority ?? 0)
    const da = parse(a.data.due)?.getTime() ?? Infinity
    const db = parse(b.data.due)?.getTime() ?? Infinity
    return da - db
  })
}

export default function Tasks() {
  const tasks = useRecords<Task>('task')
  const [filter, setFilter] = useState<Filter>('today')
  const [draft, setDraft] = useState('')

  const tomorrow = addDays(startOfDay(new Date()), 1)

  const itemsFor = useMemo(() => (f: Filter): Rec<Task>[] => {
    const open = tasks.filter((t) => !t.data.isDone)
    switch (f) {
      case 'today': return sortTasks(open.filter((t) => { const d = parse(t.data.due); return !!d && d < tomorrow }))
      case 'upcoming': return sortTasks(open.filter((t) => { const d = parse(t.data.due); return !!d && d >= tomorrow }))
      case 'inbox': return sortTasks(open.filter((t) => !t.data.due))
      case 'all': return sortTasks(open)
      case 'completed': return tasks.filter((t) => t.data.isDone)
        .sort((a, b) => (parse(b.data.completedAt)?.getTime() ?? 0) - (parse(a.data.completedAt)?.getTime() ?? 0))
      default: {
        const area = f.slice(5) as Area
        return sortTasks(open.filter((t) => areaOf(t.data.area) === area))
      }
    }
  }, [tasks, tomorrow.getTime()])

  const list = itemsFor(filter)
  const title = filter.startsWith('area:') ? cap(filter.slice(5)) : FILTERS.find((f) => f.id === filter)!.title
  const parsed = draft.trim() ? parseTask(draft) : null

  const add = () => {
    if (!parsed || !parsed.title) return
    let due = parsed.due
    let area = parsed.area
    if (filter === 'today' && !due) due = startOfDay(new Date())
    if (filter.startsWith('area:') && !area) area = filter.slice(5) as Area
    store.create<Task>('task', {
      title: parsed.title, notes: '', area: area ?? 'personal', due: due ? iso(due) : null, priority: parsed.priority,
      isDone: false, completedAt: null, createdAt: iso(new Date()), repeat: 'none',
    })
    setDraft('')
  }

  const preview = parsed && parsed.title
    ? ['Task', parsed.due ? relativeDay(parsed.due) : filter === 'today' ? 'Today' : null, parsed.area ? cap(parsed.area) : null,
       parsed.priority ? '!'.repeat(parsed.priority) : null].filter(Boolean).join(' · ')
    : null

  return (
    <div style={{ height: '100%', display: 'flex', gap: 36, padding: '6px 32px 0' }}>
      <aside className="scroll" style={{ width: 250, flex: 'none', paddingBottom: 24 }}>
        <div className="col" style={{ gap: 4 }}>
          {FILTERS.map((f) => (
            <FilterRow key={f.id} title={f.title} icon={f.icon} selected={filter === f.id}
              count={f.id === 'completed' ? 0 : itemsFor(f.id).length} onClick={() => setFilter(f.id)} />
          ))}
          <div className="muted" style={{ fontSize: 12, fontWeight: 600, padding: '18px 12px 4px' }}>Areas</div>
          {AREAS.map((a) => (
            <FilterRow key={a} title={cap(a)} tint={AREA_COLOR[a]} selected={filter === `area:${a}`}
              count={itemsFor(`area:${a}`).length} onClick={() => setFilter(`area:${a}`)} />
          ))}
        </div>
      </aside>
      <section style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 20 }}>
        <div className="row" style={{ alignItems: 'baseline' }}>
          <h1 className="page-title">{title}</h1>
          <span className="page-title muted" style={{ fontWeight: 500 }}>{filter === 'completed' ? list.length : list.length}</span>
        </div>
        {filter !== 'completed' && (
          <div className="card row" style={{ padding: '12px 16px', gap: 12 }}>
            <Plus size={16} className="muted" />
            <input className="plain" style={{ fontSize: 15 }} value={draft} onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') add() }}
              placeholder="Add a task — try “pay rent friday #money !!”" />
            {preview && <span className="secondary" style={{ fontSize: 12, whiteSpace: 'nowrap' }}>{preview}</span>}
          </div>
        )}
        <div className="scroll col" style={{ gap: 8, paddingBottom: 32, flex: 1 }}>
          {filter === 'upcoming' ? <Upcoming list={list} /> : (
            <>
              {list.length === 0 && <EmptyHint icon={<CheckCircle2 size={14} />} text="Nothing here." />}
              {list.map((t) => <TaskRow key={t.id} rec={t} />)}
            </>
          )}
        </div>
      </section>
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
    <>
      {days.map((d) => {
        const day = new Date(d)
        return (
          <div key={d} className="col" style={{ gap: 8 }}>
            <div className="secondary" style={{ fontSize: 13, fontWeight: 600, paddingTop: 10 }}>
              {relativeDay(day) === day.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
                ? day.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'short' })
                : `${relativeDay(day)} · ${day.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}`}
            </div>
            {groups.get(d)!.map((t) => <TaskRow key={t.id} rec={t} showDue={false} />)}
          </div>
        )
      })}
    </>
  )
}

function FilterRow({ title, icon, tint, count, selected, onClick }: {
  title: string; icon?: ReactNode; tint?: string; count: number; selected: boolean; onClick: () => void
}) {
  const [hover, setHover] = useState(false)
  return (
    <button onClick={onClick} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      className="row" style={{
        gap: 10, padding: '6px 10px', borderRadius: 999, width: '100%',
        background: selected ? 'var(--inverse)' : hover ? 'var(--card)' : 'transparent',
        color: selected ? 'var(--on-inverse)' : 'var(--ink)',
      }}>
      <span style={{
        width: 26, height: 26, borderRadius: '50%', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        background: tint ?? 'transparent', color: tint ? 'var(--sticker-ink)' : undefined,
      }}>{icon ?? <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--sticker-ink)', opacity: 0.6 }} />}</span>
      <span style={{ fontWeight: 500 }}>{title}</span>
      <span className="spacer" />
      {count > 0 && <span style={{ fontSize: 12, fontWeight: 600, opacity: 0.7 }}>{count}</span>}
    </button>
  )
}
