// Focus timer UI: the top-bar countdown pill, the "how long?" sheet and the "time's up" dialog.
import { useEffect, useState } from 'react'
import { Timer, Square, Check } from 'lucide-react'
import { useRecords } from '@/lib/store'
import { Task } from '@/lib/models'
import { useActiveFocus, stopFocus, startFocus, plannedEnd, finishIfDue, useFocusRequest, useFocusFinished, rememberedLength, FOCUS_LENGTHS } from '@/lib/focus'
import { completeTask } from './TaskRow'
import { Modal, Segmented } from './ui'

export function FocusPill() {
  const s = useActiveFocus()
  const [, tick] = useState(0)
  useEffect(() => {
    finishIfDue()
    const t = setInterval(() => { finishIfDue(); tick((n) => n + 1) }, 1000)
    return () => clearInterval(t)
  }, [])
  if (!s) return null
  const left = Math.max(0, Math.ceil((plannedEnd(s.data).getTime() - Date.now()) / 1000))
  return (
    <div className="timer-pill no-drag" style={{ background: 'var(--orange)', cursor: 'default' }} title={s.data.taskTitle ? `Focusing on ${s.data.taskTitle}` : 'Focus'}>
      <Timer size={14} />
      <span style={{ fontVariantNumeric: 'tabular-nums' }}>{String(Math.floor(left / 60)).padStart(2, '0')}:{String(left % 60).padStart(2, '0')}</span>
      <span className="clamp1 timer-title">{s.data.taskTitle || 'Focus'}</span>
      <button title="Stop focus" onClick={() => stopFocus(s)}><Square size={11} fill="currentColor" /></button>
    </div>
  )
}

export function FocusStartSheet() {
  const [req, clear] = useFocusRequest()
  const [minutes, setMinutes] = useState(rememberedLength())
  useEffect(() => { if (req) setMinutes(rememberedLength()) }, [req])
  if (!req) return null
  const start = () => { startFocus(req.task, minutes); clear() }
  return (
    <Modal open onClose={clear} width={400}>
      <div className="col" style={{ gap: 16 }}>
        <h2 className="display" style={{ fontSize: 26, margin: 0 }}>Focus</h2>
        <div className="secondary">{req.task ? req.task.data.title : 'No task: just a block of deep work.'}</div>
        <Segmented options={FOCUS_LENGTHS.map((n) => ({ id: String(n), label: `${n} min` }))} value={String(minutes)} onChange={(v) => setMinutes(Number(v))} />
        <div className="row">
          <button className="btn-soft" onClick={clear}>Cancel</button>
          <span className="spacer" />
          <button className="btn-primary" autoFocus style={{ width: 120 }} onClick={start}><Timer size={14} />Start</button>
        </div>
      </div>
    </Modal>
  )
}

export function FocusDoneDialog() {
  const [s, clear] = useFocusFinished()
  const tasks = useRecords<Task>('task')
  if (!s) return null
  const task = s.data.taskUUID ? tasks.find((t) => t.id === s.data.taskUUID && !t.data.isDone) : undefined
  return (
    <Modal open onClose={clear} width={400}>
      <div className="col" style={{ gap: 14 }}>
        <h2 className="display" style={{ fontSize: 26, margin: 0 }}>Focus done 🎯</h2>
        <div className="secondary">{s.data.plannedMinutes} minutes{s.data.taskTitle ? ` on ${s.data.taskTitle}` : ''}. Take a 5-minute break.</div>
        <div className="row">
          <button className="btn-soft" onClick={clear}>Close</button>
          <span className="spacer" />
          {task && <button className="btn-primary" onClick={() => { completeTask(task); clear() }}><Check size={14} />Mark task done</button>}
        </div>
      </div>
    </Modal>
  )
}
