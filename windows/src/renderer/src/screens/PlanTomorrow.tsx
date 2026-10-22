// Evening plan sheet and the "Today's top 3" card (Mac evening planning).
import { useState } from 'react'
import { Check, ArrowRight, CalendarX, Plus, X, Moon, Target } from 'lucide-react'
import { store, useRecords, useStoreVersion, Rec } from '@/lib/store'
import { Task, CalEvent, DayPlan, AREA_COLOR, areaOf } from '@/lib/models'
import { iso, parse, startOfDay, addDays, sameDay, fmtTime, fmtDay } from '@/lib/dates'
import { planFor, savePlan, tomorrowKey, todayKey, PlanItem, localTicks, setLocalTick } from '@/lib/dayPlan'
import { completeTask } from '@/components/TaskRow'
import { Card, CheckCircle, EmptyHint, Modal } from '@/components/ui'

export function PlanTomorrowSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  if (!open) return null
  return <Sheet onClose={onClose} />
}

function Sheet({ onClose }: { onClose: () => void }) {
  const tasks = useRecords<Task>('task')
  const events = useRecords<CalEvent>('event')
  const today = startOfDay(new Date()), tomorrow = addDays(today, 1)
  const existing = planFor(tomorrowKey())
  const [items, setItems] = useState<PlanItem[]>(() => existing ? existing.data.top.map((t, i) => ({ title: t, taskUUID: existing.data.taskUUIDs[i] ?? '' })) : [])
  const [typed, setTyped] = useState('')
  const [note, setNote] = useState(existing?.data.note ?? '')

  const open = tasks.filter((t) => !t.data.isDone)
  const leftovers = open.filter((t) => { const d = parse(t.data.due); return !!d && d < tomorrow })
    .sort((a, b) => (a.data.due ?? '').localeCompare(b.data.due ?? ''))
  const candidates = open.slice().sort((a, b) => b.data.priority - a.data.priority || (a.data.due ?? '9').localeCompare(b.data.due ?? '9'))
  const tomorrowEvents = events.filter((e) => { const s = parse(e.data.start); return !!s && sameDay(s, tomorrow) }).sort((a, b) => a.data.start.localeCompare(b.data.start))
  const picked = (id: string) => items.some((i) => i.taskUUID === id)
  const toggle = (t: Rec<Task>) => setItems((xs) => picked(t.id) ? xs.filter((i) => i.taskUUID !== t.id) : xs.length >= 3 ? xs : [...xs, { title: t.data.title, taskUUID: t.id }])
  const addTyped = () => { const v = typed.trim(); if (v && items.length < 3) setItems([...items, { title: v, taskUUID: '' }]); setTyped('') }
  const save = () => { savePlan(tomorrowKey(), items, note.trim()); onClose() }

  return (
    <Modal open onClose={onClose} width={720}>
      <div className="col" style={{ gap: 18 }}>
        <div>
          <h2 className="display" style={{ fontSize: 28, margin: 0 }}>Plan tomorrow</h2>
          <div className="secondary" style={{ fontSize: 13 }}>{fmtDay(tomorrow)}. Clear today, then pick what matters most.</div>
        </div>

        <div className="col" style={{ gap: 8 }}>
          <div className="muted" style={{ fontSize: 12, fontWeight: 600 }}>1 · Left from today</div>
          {leftovers.length === 0 && <EmptyHint text="Nothing left over. Nice." />}
          {leftovers.map((t) => (
            <div key={t.id} className="inner row" style={{ gap: 10, padding: '6px 10px' }}>
              <span style={{ width: 4, height: 22, borderRadius: 2, background: AREA_COLOR[areaOf(t.data.area)], flex: 'none' }} />
              <span className="clamp1" style={{ flex: 1, fontSize: 13, fontWeight: 500 }}>{t.data.title}</span>
              {parse(t.data.due)! < today && <span style={{ fontSize: 11, color: 'var(--critical)' }}>overdue</span>}
              <button className="btn-soft" style={{ padding: '5px 10px' }} onClick={() => completeTask(t)}><Check size={12} />Done</button>
              <button className="btn-soft" style={{ padding: '5px 10px' }} onClick={() => store.update<Task>(t.id, { due: iso(tomorrow) })}><ArrowRight size={12} />Tomorrow</button>
              <button className="btn-soft" style={{ padding: '5px 10px' }} onClick={() => store.update<Task>(t.id, { due: null })}><CalendarX size={12} />No date</button>
            </div>
          ))}
        </div>

        <div className="col" style={{ gap: 6 }}>
          <div className="muted" style={{ fontSize: 12, fontWeight: 600 }}>2 · Tomorrow's calendar</div>
          {tomorrowEvents.length === 0 && <EmptyHint text="Nothing scheduled. A clear day." />}
          <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
            {tomorrowEvents.map((e) => (
              <span key={e.id} className="pill" style={{ background: AREA_COLOR[areaOf(e.data.area)] }}>{fmtTime(parse(e.data.start)!)} {e.data.title}</span>
            ))}
          </div>
        </div>

        <div className="col" style={{ gap: 8 }}>
          <div className="muted" style={{ fontSize: 12, fontWeight: 600 }}>3 · Top 3 for tomorrow ({items.length}/3)</div>
          <div className="row" style={{ gap: 8, alignItems: 'stretch' }}>
            {[0, 1, 2].map((i) => (
              <div key={i} className="row" style={{ flex: 1, minWidth: 0, gap: 8, padding: '10px 12px', borderRadius: 14, minHeight: 46,
                background: items[i] ? 'var(--lime)' : 'var(--card)', color: items[i] ? 'var(--sticker-ink)' : 'var(--ink3)' }}>
                <span className="display" style={{ fontSize: 18 }}>{i + 1}</span>
                <span className="clamp2" style={{ flex: 1, fontSize: 13, fontWeight: 600 }}>{items[i]?.title ?? 'Pick a task below'}</span>
                {items[i] && <button title="Remove" onClick={() => setItems(items.filter((_, j) => j !== i))}><X size={13} /></button>}
              </div>
            ))}
          </div>
          <div className="scroll col" style={{ gap: 4, maxHeight: 170 }}>
            {candidates.map((t) => (
              <button key={t.id} className="inner row" style={{ gap: 10, padding: '6px 10px', textAlign: 'left', opacity: !picked(t.id) && items.length >= 3 ? 0.45 : 1 }}
                onClick={() => toggle(t)}>
                <CheckCircle on={picked(t.id)} size={18} tint="var(--lime)" />
                <span className="clamp1" style={{ flex: 1, fontSize: 13 }}>{t.data.title}</span>
                {t.data.priority > 0 && <span style={{ fontWeight: 800, fontSize: 12 }}>{'!'.repeat(t.data.priority)}</span>}
              </button>
            ))}
          </div>
          <div className="row">
            <input className="field" placeholder="Or type one…" value={typed} disabled={items.length >= 3}
              onChange={(e) => setTyped(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && addTyped()} />
            <button className="btn-soft" disabled={!typed.trim() || items.length >= 3} onClick={addTyped}><Plus size={13} />Add</button>
          </div>
        </div>

        <div className="col" style={{ gap: 6 }}>
          <div className="muted" style={{ fontSize: 12, fontWeight: 600 }}>4 · A note for tomorrow (optional)</div>
          <textarea className="field" rows={2} placeholder="e.g. Start with the slides before email." value={note} onChange={(e) => setNote(e.target.value)} />
        </div>

        <div className="row">
          <button className="btn-soft" onClick={onClose}>Cancel</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 140 }} onClick={save}><Moon size={14} />Save plan</button>
        </div>
      </div>
    </Modal>
  )
}

/** Today's top 3 from last night's plan. */
export function TopThreeCard({ plan, onPlan }: { plan: Rec<DayPlan>; onPlan: () => void }) {
  useStoreVersion()
  const [, force] = useState(0)
  const day = todayKey()
  const ticks = localTicks(day)
  return (
    <Card className="col" padding={12} style={{ gap: 5, flex: 'none', background: 'var(--lime)', color: 'var(--sticker-ink)' }}>
      <div className="row"><Target size={15} /><h3 className="section-title" style={{ fontSize: 18 }}>Today's top 3</h3><span className="spacer" />
        <button style={{ fontSize: 12, fontWeight: 500, opacity: 0.7 }} onClick={onPlan}>Plan tomorrow</button></div>
      {plan.data.top.map((title, i) => {
        const task = plan.data.taskUUIDs[i] ? store.get<Task>(plan.data.taskUUIDs[i]) : undefined
        const done = task ? task.data.isDone : ticks.includes(i)
        const toggle = () => {
          if (task) { if (task.data.isDone) store.update<Task>(task.id, { isDone: false, completedAt: null }); else completeTask(task) }
          else { setLocalTick(day, i, !done); force((n) => n + 1) }
        }
        return (
          <div key={i} className="row" style={{ gap: 10 }}>
            <CheckCircle on={done} size={18} onClick={toggle} />
            <span className="clamp1" style={{ fontSize: 13, fontWeight: 600, textDecoration: done ? 'line-through' : 'none', opacity: done ? 0.55 : 1 }}>{title}</span>
          </div>
        )
      })}
      {plan.data.note && <div style={{ fontSize: 11, opacity: 0.7 }}>{plan.data.note}</div>}
    </Card>
  )
}

/** Evening card on Today (from 17:00). Kept compact so the day's tasks keep their room. */
export function PlanTomorrowCard({ onPlan }: { onPlan: () => void }) {
  const plans = useRecords<DayPlan>('dayPlan')
  const plan = planFor(tomorrowKey(), plans)
  return (
    <Card className="col" padding={14} style={{ flex: 'none', gap: 6, background: '#141416', color: '#f4f4f5' }}>
      <div className="row" style={{ gap: 8 }}>
        <Moon size={15} />
        <h3 className="section-title" style={{ fontSize: 18 }}>{plan ? "Tomorrow's plan" : 'Plan tomorrow'}</h3>
        <span className="spacer" />
        {plan
          ? <button className="link" style={{ color: '#f4f4f5', opacity: 0.7 }} onClick={onPlan}>Edit</button>
          : <button className="btn-lime" style={{ height: 32 }} onClick={onPlan}>Plan</button>}
      </div>
      {plan
        ? <div className="clamp1" style={{ fontSize: 12, opacity: 0.8 }}>{plan.data.top.map((t, i) => `${i + 1}. ${t}`).join('  ·  ') || plan.data.note}</div>
        : <div className="clamp1" style={{ fontSize: 12, opacity: 0.7 }}>Clear what's left and pick your top 3 for tomorrow.</div>}
    </Card>
  )
}
