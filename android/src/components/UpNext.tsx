// Today › Up next, as on the iPhone (PhoneToday.upNext): a few of today's open tasks and what's still coming up on the
// calendar (yours and Google Calendar), in one card.
import { useMemo } from 'react'
import { CheckCheck } from 'lucide-react'
import { useRecords, Rec } from '@/lib/store'
import { Task, CalEvent, AREA_COLOR, areaOf } from '@/lib/models'
import { parse, startOfDay, addDays, sameDay, fmtTime } from '@/lib/dates'
import { useExternalEvents, externalEvents, ExternalEvent } from '@/lib/externalEvents'
import { Card, SectionHeader, EmptyHint, AreaPill } from '@/components/ui'
import { TaskRow } from '@/components/TaskRow'

type Entry = { id: string; title: string; start: Date; end: Date; allDay: boolean; color: string; calendar?: string; local?: Rec<CalEvent> }

export default function UpNext({ onTasks, onCalendar }: { onTasks: () => void; onCalendar: () => void }) {
  const tasks = useRecords<Task>('task')
  const events = useRecords<CalEvent>('event')
  useExternalEvents()
  const now = new Date(), today = startOfDay(now), tomorrow = addDays(today, 1)

  // Due today or overdue, most important first, then earliest due.
  const open = useMemo(() => tasks
    .filter((t) => !t.data.isDone && (parse(t.data.due)?.getTime() ?? Infinity) < tomorrow.getTime())
    .sort((a, b) => (b.data.priority ?? 0) - (a.data.priority ?? 0) || parse(a.data.due)!.getTime() - parse(b.data.due)!.getTime()), [tasks]) // eslint-disable-line react-hooks/exhaustive-deps

  // Today's events that haven't ended yet.
  const next: Entry[] = [
    ...events.flatMap((e): Entry[] => {
      const start = parse(e.data.start), end = parse(e.data.end)
      return start && end && sameDay(start, today)
        ? [{ id: e.id, title: e.data.title, start, end, allDay: false, color: AREA_COLOR[areaOf(e.data.area)], local: e }] : []
    }),
    ...externalEvents(today, tomorrow).map((g: ExternalEvent): Entry => ({ id: g.id, title: g.title, start: g.start, end: g.end, allDay: g.allDay, color: g.color, calendar: g.calendar })),
  ].filter((e) => e.end > now).sort((a, b) => Number(b.allDay) - Number(a.allDay) || a.start.getTime() - b.start.getTime())

  return (
    <Card className="col" padding={14} style={{ gap: 8, flex: 'none' }}>
      <SectionHeader title="Up next" trailing="All tasks" onTrailing={onTasks} />
      {open.length === 0 && next.length === 0 && <EmptyHint icon={<CheckCheck size={14} />} text="Nothing due and nothing on the calendar. Nice." />}
      {open.slice(0, 3).map((t) => <TaskRow key={t.id} rec={t} showDue={parse(t.data.due)! < today} />)}
      {open.length > 3 && <MoreLink text={`+${open.length - 3} more due today`} onClick={onTasks} />}
      {next.length > 0 && (
        <>
          {open.length > 0 && <div style={{ height: 1, background: 'var(--line)', margin: '2px 0' }} />}
          {next.slice(0, 2).map((e) => <EntryRow key={e.id} e={e} />)}
          {next.length > 2 && <MoreLink text={`+${next.length - 2} more today`} onClick={onCalendar} />}
        </>
      )}
    </Card>
  )
}

function MoreLink({ text, onClick }: { text: string; onClick: () => void }) {
  return <button className="secondary" style={{ alignSelf: 'flex-start', fontSize: 12, fontWeight: 600, padding: '4px 0' }} onClick={onClick}>{text}</button>
}

/** One event, like the iPhone's AgendaRow: times, a colour bar, the title, its area or calendar, and "Now". */
function EntryRow({ e }: { e: Entry }) {
  const now = new Date()
  const area = e.local ? areaOf(e.local.data.area) : null
  return (
    <div className="row inner" style={{ padding: 10, gap: 12 }}>
      <div style={{ width: 56, textAlign: 'right', flex: 'none', fontSize: 12, fontWeight: 600 }}>
        {e.allDay ? 'All day' : <>{fmtTime(e.start)}<div className="muted" style={{ fontSize: 10, fontWeight: 400 }}>{fmtTime(e.end)}</div></>}
      </div>
      <span style={{ width: 4, height: 30, borderRadius: 2, background: e.color, flex: 'none' }} />
      <div className="col" style={{ flex: 1, minWidth: 0, gap: 1 }}>
        <span className="clamp1" style={{ fontWeight: 500, fontSize: 13 }}>{e.title}</span>
        {e.calendar && <span className="muted clamp1" style={{ fontSize: 10 }}>{e.calendar}</span>}
      </div>
      {area && <AreaPill area={area} compact />}
      {!e.allDay && e.start <= now && e.end > now && <span className="pill compact" style={{ background: 'var(--critical)', color: '#fff', fontWeight: 700 }}>Now</span>}
    </div>
  )
}
