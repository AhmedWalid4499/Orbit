import { useState } from 'react'
import { CalendarDays, Repeat as RepeatIcon, Trash2 } from 'lucide-react'
import { store, Rec } from '@/lib/store'
import { Task, Repeat, areaOf, cap } from '@/lib/models'
import { iso, parse, startOfDay, addDays, addMonths, relativeDay, toDateInput, fromInputs } from '@/lib/dates'
import { AreaPicker, AreaPill, CheckCircle, Modal, Segmented } from '@/components/ui'

export const isOverdue = (t: Task): boolean => {
  const due = parse(t.due)
  return !!due && !t.isDone && due < startOfDay(new Date())
}

/** Marks a task done; repeating tasks get their next occurrence (same as TaskItem.complete on the Mac). */
export function completeTask(rec: Rec<Task>): void {
  const t = rec.data
  store.update<Task>(rec.id, { isDone: true, completedAt: iso(new Date()) })
  const due = parse(t.due)
  const repeat = t.repeat ?? 'none'
  if (!due || repeat === 'none') return
  const next = repeat === 'daily' ? addDays(due, 1) : repeat === 'weekly' ? addDays(due, 7) : addMonths(due, 1)
  store.create<Task>('task', {
    title: t.title, notes: t.notes ?? '', area: areaOf(t.area), due: iso(next), priority: t.priority ?? 0,
    isDone: false, completedAt: null, createdAt: iso(new Date()), repeat,
  })
}

export function toggleTask(rec: Rec<Task>): void {
  if (rec.data.isDone) store.update<Task>(rec.id, { isDone: false, completedAt: null })
  else completeTask(rec)
}

export function TaskRow({ rec, showDue = true }: { rec: Rec<Task>; showDue?: boolean }) {
  const t = rec.data
  const [editing, setEditing] = useState(false)
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null)
  const due = parse(t.due)
  const overdue = isOverdue(t)
  const repeat = t.repeat ?? 'none'

  return (
    <>
      <div className="inner row" style={{ gap: 12, padding: '8px 12px' }}
        onContextMenu={(e) => { e.preventDefault(); setMenu({ x: e.clientX, y: e.clientY }) }}>
        <CheckCircle on={t.isDone} onClick={() => toggleTask(rec)} />
        <div style={{ flex: 1, minWidth: 0, cursor: 'pointer' }} onClick={() => setEditing(true)}>
          <div className="clamp1" style={{ fontWeight: 500, color: t.isDone ? 'var(--ink3)' : 'var(--ink)', textDecoration: t.isDone ? 'line-through' : 'none' }}>
            {t.title || 'Untitled'}
          </div>
          {((showDue && due) || repeat !== 'none') && (
            <div className="row" style={{ gap: 8, fontSize: 11, marginTop: 2 }}>
              {showDue && due && (
                <span className="row" style={{ gap: 3, color: overdue ? 'var(--critical)' : 'var(--ink3)' }}>
                  <CalendarDays size={11} />{relativeDay(due)}
                </span>
              )}
              {repeat !== 'none' && <span className="row muted" style={{ gap: 3 }}><RepeatIcon size={11} />{cap(repeat)}</span>}
            </div>
          )}
        </div>
        {t.priority > 0 && (
          <span style={{ fontWeight: 800, fontSize: 13, color: t.priority === 3 ? 'var(--critical)' : 'var(--ink2)' }}>{'!'.repeat(t.priority)}</span>
        )}
        <AreaPill area={areaOf(t.area)} compact />
      </div>
      {menu && (
        <div className="backdrop" style={{ background: 'transparent' }} onMouseDown={() => setMenu(null)}>
          <div className="card" style={{ position: 'fixed', left: menu.x, top: menu.y, padding: 6, boxShadow: '0 10px 30px rgba(0,0,0,.2)', background: 'var(--canvas)' }}
            onMouseDown={(e) => e.stopPropagation()}>
            <MenuItem label="Edit…" onClick={() => { setMenu(null); setEditing(true) }} />
            <MenuItem label="Due today" onClick={() => { store.update<Task>(rec.id, { due: iso(startOfDay(new Date())) }); setMenu(null) }} />
            <MenuItem label="Due tomorrow" onClick={() => { store.update<Task>(rec.id, { due: iso(addDays(startOfDay(new Date()), 1)) }); setMenu(null) }} />
            <MenuItem label="No date" onClick={() => { store.update<Task>(rec.id, { due: null }); setMenu(null) }} />
            <MenuItem label="Delete" danger onClick={() => { store.remove(rec.id); setMenu(null) }} />
          </div>
        </div>
      )}
      <TaskEditor rec={rec} open={editing} onClose={() => setEditing(false)} />
    </>
  )
}

function MenuItem({ label, onClick, danger }: { label: string; onClick: () => void; danger?: boolean }) {
  return (
    <button onClick={onClick} style={{ display: 'block', width: '100%', textAlign: 'left', padding: '7px 12px', borderRadius: 8, fontSize: 13, color: danger ? 'var(--critical)' : 'var(--ink)' }}
      onMouseEnter={(e) => (e.currentTarget.style.background = 'var(--card)')} onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}>
      {label}
    </button>
  )
}

export function TaskEditor({ rec, open, onClose }: { rec: Rec<Task>; open: boolean; onClose: () => void }) {
  const t = rec.data
  const set = (patch: Partial<Task>) => store.update<Task>(rec.id, patch)
  const due = parse(t.due)
  return (
    <Modal open={open} onClose={onClose} width={520}>
      <div className="col" style={{ gap: 16 }}>
        <input className="plain display" style={{ fontSize: 26 }} value={t.title} placeholder="Title" onChange={(e) => set({ title: e.target.value })} />
        <AreaPicker value={areaOf(t.area)} onChange={(a) => set({ area: a })} />
        <div className="row" style={{ fontSize: 13 }}>
          <span className="secondary" style={{ width: 70 }}>Due</span>
          <input type="checkbox" checked={!!due} onChange={(e) => set({ due: e.target.checked ? iso(startOfDay(new Date())) : null })} />
          {due && <input type="date" className="field" style={{ width: 170, padding: '6px 10px' }} value={toDateInput(due)}
            onChange={(e) => e.target.value && set({ due: iso(fromInputs(e.target.value)) })} />}
        </div>
        <div className="row" style={{ fontSize: 13 }}>
          <span className="secondary" style={{ width: 70 }}>Priority</span>
          <Segmented options={[{ id: '0', label: 'None' }, { id: '1', label: 'Low' }, { id: '2', label: 'Medium' }, { id: '3', label: 'High' }]}
            value={String(t.priority ?? 0)} onChange={(v) => set({ priority: Number(v) })} />
        </div>
        <div className="row" style={{ fontSize: 13 }}>
          <span className="secondary" style={{ width: 70 }}>Repeat</span>
          <select className="field" style={{ width: 150, padding: '6px 10px' }} value={t.repeat ?? 'none'} onChange={(e) => set({ repeat: e.target.value as Repeat })}>
            <option value="none">Never</option><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="monthly">Monthly</option>
          </select>
        </div>
        <span className="secondary" style={{ fontSize: 13 }}>Notes</span>
        <textarea className="field" rows={5} value={t.notes ?? ''} onChange={(e) => set({ notes: e.target.value })} />
        <div className="row">
          <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(rec.id); onClose() }}><Trash2 size={13} />Delete</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120 }} onClick={onClose}>Done</button>
        </div>
      </div>
    </Modal>
  )
}
