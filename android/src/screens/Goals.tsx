// Goals, like GoalsView.swift + Goals.swift on the Mac: progress fills in by itself from Reading (books finished),
// Money (saved since the start), a habit (days done), or from ticking off steps. A steps goal can make a bucket-list
// dream happen (bucketUUID). Ahead or behind the even pace to the deadline.
import { useState } from 'react'
import { Plus, Library, Banknote, Flame, ListChecks, Flag, X } from 'lucide-react'
import { store, useRecords, useSetting, Rec } from '@/lib/store'
import { Book, Habit, Txn, Bucket } from '@/lib/models'
import { iso, parse, startOfDay, addDays, dayKey, daysBetween, toDateInput, fromInputs } from '@/lib/dates'
import { Card, EmptyHint, Modal, CheckCircle, useMoney, defaultCurrency } from '@/components/ui'

type Kind = 'books' | 'save' | 'habit' | 'steps'
export interface Goal {
  title: string; kind: Kind; target: number; start: string; deadline: string | null
  habitUUID: string; bucketUUID: string; steps: string[]; stepsDone: string[]; doneAt: string | null; createdAt: string
}

const KINDS: { id: Kind; title: string; tint: string; icon: (s: number) => JSX.Element }[] = [
  { id: 'books', title: 'Read books', tint: '#D9C8FF', icon: (s) => <Library size={s} /> },
  { id: 'save', title: 'Save money', tint: 'var(--mint)', icon: (s) => <Banknote size={s} /> },
  { id: 'habit', title: 'Keep a habit', tint: 'var(--peach)', icon: (s) => <Flame size={s} /> },
  { id: 'steps', title: 'Steps', tint: '#F3DE9E', icon: (s) => <ListChecks size={s} /> },
]
const kindOf = (k: string) => KINDS.find((x) => x.id === k) ?? KINDS[3]

interface Sources { books: Rec<Book>[]; txns: Rec<Txn>[]; habits: Rec<Habit>[] }
interface Progress { value: number; target: number; fraction: number; complete: boolean; pace: number | null }

// MARK: Tracker (GoalTracker on the Mac)

function progress(g: Goal, s: Sources): Progress {
  const start = startOfDay(parse(g.start) ?? new Date())
  let value = 0, target = g.target
  if (g.kind === 'books') {
    value = s.books.filter((b) => b.data.status === 'read' && (parse(b.data.finishedAt)?.getTime() ?? -Infinity) >= start.getTime()).length
  } else if (g.kind === 'save') {
    value = Math.max(0, s.txns.reduce((sum, t) => sum + ((parse(t.data.date)?.getTime() ?? 0) >= start.getTime() ? t.data.amount : 0), 0))
  } else if (g.kind === 'habit') {
    const key = dayKey(start)
    value = s.habits.find((h) => h.id === g.habitUUID)?.data.doneDays.filter((d) => d >= key).length ?? 0
  } else {
    target = (g.steps ?? []).length
    value = (g.steps ?? []).filter((x) => (g.stepsDone ?? []).includes(x)).length
  }
  const deadline = parse(g.deadline)
  let pace: number | null = null
  if (deadline && deadline > start && target > 0) {
    const elapsed = Math.min(1, Math.max(0, (Date.now() - start.getTime()) / (deadline.getTime() - start.getTime())))
    pace = value / target - elapsed
  }
  return { value, target, fraction: target > 0 ? Math.min(1, Math.max(0, value / target)) : 0, complete: target > 0 && value >= target, pace }
}

function paceText(g: Goal, p: Progress): string | null {
  if (p.complete) return 'Done 🎉'
  const deadline = parse(g.deadline)
  if (p.pace === null || !deadline) return null
  const days = daysBetween(new Date(), deadline)
  if (days < 0) return 'Deadline passed'
  if (p.pace >= 0.05) return `Ahead of pace · ${days} days left`
  if (p.pace <= -0.1) return `Behind pace · ${days} days left`
  return `On track · ${days} days left`
}

const newGoal = (title: string, kind: Kind, target: number, extra: Partial<Goal> = {}): Goal => ({
  title, kind, target, start: iso(startOfDay(new Date())), deadline: null, habitUUID: '', bucketUUID: '',
  steps: [], stepsDone: [], doneAt: null, createdAt: iso(new Date()), ...extra,
})

// MARK: Screen

/** Bucket list › Goals on the iPhone (GoalsSection in GoalsView.swift): header, starters when empty, open goals, then reached ones. */
export function GoalsSection() {
  const goals = useRecords<Goal>('goal').slice().sort((a, b) => (b.data.createdAt ?? '').localeCompare(a.data.createdAt ?? ''))
  const s: Sources = { books: useRecords<Book>('book'), txns: useRecords<Txn>('transaction'), habits: useRecords<Habit>('habit') }
  const [editing, setEditing] = useState<Rec<Goal> | null>(null)
  const [adding, setAdding] = useState(false)
  const money = useMoney()
  const open = goals.filter((g) => !g.data.doneAt), done = goals.filter((g) => g.data.doneAt)

  const now = new Date(), y = now.getFullYear()
  const june = new Date(y, 5, 30) > now ? new Date(y, 5, 30) : new Date(y + 1, 5, 30)
  const starters: { label: string; kind: Kind; make: () => Goal }[] = [
    // A reading goal for the year counts from January.
    { label: 'Read 24 books this year', kind: 'books', make: () => newGoal('Read 24 books this year', 'books', 24, { start: iso(new Date(y, 0, 1)), deadline: iso(new Date(y, 11, 31, 12)) }) },
    { label: `Save ${money(50000)} by June`, kind: 'save', make: () => newGoal(`Save ${money(50000)} by June`, 'save', 50000, { deadline: iso(new Date(june.getFullYear(), 5, 30, 12)) }) },
    ...(s.habits[0] ? [{ label: `${s.habits[0].data.name} 30 days`, kind: 'habit' as Kind, make: () => newGoal(`${s.habits[0].data.name} 30 days`, 'habit', 30, { habitUUID: s.habits[0].id }) }] : []),
  ]

  return (
    <div className="col" style={{ gap: 16 }}>
      <div className="row" style={{ gap: 12, alignItems: 'flex-start' }}>
        <div style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
          <span className="display" style={{ fontSize: 24 }}>Goals</span>
          <span className="secondary" style={{ fontSize: 13 }}>Progress fills in from your books, money and habits.</span>
        </div>
        <span className="spacer" />
        <button className="btn-soft" style={{ minHeight: 38 }} onClick={() => setAdding(true)}><Plus size={14} />Add goal</button>
      </div>

      {!goals.length && (
        <Card>
          <div className="col" style={{ gap: 10 }}>
            <EmptyHint icon={<Flag size={15} />} text="No goals yet. Try one of these:" />
            {starters.map((x) => (
              <button key={x.label} className="btn-soft" style={{ minHeight: 40, justifyContent: 'flex-start', background: 'var(--canvas)' }}
                onClick={() => store.create<Goal>('goal', x.make())}>{kindOf(x.kind).icon(14)}{x.label}</button>
            ))}
          </div>
        </Card>
      )}

      {open.map((g) => <GoalCard key={g.id} goal={g} p={progress(g.data, s)} onOpen={() => setEditing(g)} />)}
      {done.length > 0 && (
        <>
          <div className="secondary" style={{ fontSize: 13, fontWeight: 600, marginTop: 6 }}>Reached ({done.length})</div>
          {done.map((g) => <GoalCard key={g.id} goal={g} p={progress(g.data, s)} onOpen={() => setEditing(g)} />)}
        </>
      )}
      {adding && <Editor goal={null} onClose={() => setAdding(false)} />}
      {editing && <Editor goal={editing} onClose={() => setEditing(null)} />}
    </div>
  )
}

/** Goals on their own page (on the iPhone they live under Bucket list › Goals). */
export default function Goals() {
  return (
    <div className="page">
      <GoalsSection />
    </div>
  )
}

function GoalCard({ goal, p, onOpen }: { goal: Rec<Goal>; p: Progress; onOpen: () => void }) {
  const money = useMoney()
  const g = goal.data, k = kindOf(g.kind)
  const pace = paceText(g, p)
  const desc = g.kind === 'save' ? `${money(p.value)} of ${money(p.target)}`
    : `${Math.floor(p.value)} of ${Math.floor(p.target)} ${g.kind === 'books' ? 'books' : g.kind === 'habit' ? 'days' : 'steps'}`
  const toggle = (step: string) => {
    const on = (g.stepsDone ?? []).includes(step)
    store.update<Goal>(goal.id, { stepsDone: on ? g.stepsDone.filter((x) => x !== step) : [...(g.stepsDone ?? []), step] })
  }
  return (
    <div onClick={onOpen} className="col" style={{ gap: 12, padding: 18, borderRadius: 'var(--radius)', background: k.tint, color: 'var(--sticker-ink)',
      opacity: g.doneAt ? 0.7 : 1, cursor: 'pointer' }}>
      <div className="row">
        <span style={{ width: 32, height: 32, borderRadius: '50%', background: 'rgba(255,255,255,0.6)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>{k.icon(14)}</span>
        <span className="spacer" />
        <span className="display" style={{ fontSize: 26 }}>{Math.round(p.fraction * 100)}%</span>
      </div>
      <div className="clamp2" style={{ fontSize: 16, fontWeight: 600 }}>{g.title}</div>
      <div style={{ height: 6, borderRadius: 3, background: 'rgba(17,17,17,0.12)' }}>
        <div style={{ height: '100%', borderRadius: 3, background: 'var(--sticker-ink)', width: `max(6px, ${p.fraction * 100}%)` }} />
      </div>
      <div>
        <div style={{ fontSize: 13, fontWeight: 600 }}>{desc}</div>
        {pace && <div style={{ fontSize: 11, opacity: 0.7 }}>{pace}</div>}
      </div>
      {g.kind === 'steps' && (g.steps ?? []).length > 0 && (
        <div className="col" style={{ gap: 2 }} onClick={(e) => e.stopPropagation()}>
          {g.steps.slice(0, 6).map((step) => {
            const on = (g.stepsDone ?? []).includes(step)
            return (
              <button key={step} className="row" style={{ gap: 10, minHeight: 40, textAlign: 'left', color: 'inherit' }} onClick={() => toggle(step)}>
                <CheckCircle on={on} tint="var(--sticker-ink)" size={18} />
                <span className="clamp1" style={{ fontSize: 13, textDecoration: on ? 'line-through' : 'none' }}>{step}</span>
              </button>
            )
          })}
          {g.steps.length > 6 && <div style={{ fontSize: 11, opacity: 0.7 }}>+{g.steps.length - 6} more</div>}
        </div>
      )}
      {p.complete && !g.doneAt && (
        <button onClick={(e) => { e.stopPropagation(); store.update<Goal>(goal.id, { doneAt: iso(new Date()) }) }}
          style={{ alignSelf: 'flex-start', minHeight: 36, padding: '6px 14px', borderRadius: 999, background: 'rgba(255,255,255,0.65)', fontSize: 12, fontWeight: 600, color: 'inherit' }}>
          Mark as reached 🎉
        </button>
      )}
    </div>
  )
}

function Editor({ goal, onClose }: { goal: Rec<Goal> | null; onClose: () => void }) {
  const habits = useRecords<Habit>('habit')
  const dreams = useRecords<Bucket>('bucket').filter((b) => !b.data.isDone && (b.data.kind as string) !== 'place')
  const d = goal?.data
  const [title, setTitle] = useState(d?.title ?? '')
  const [kind, setKind] = useState<Kind>(d ? kindOf(d.kind).id : 'books')
  const [target, setTarget] = useState(d && d.target > 0 ? String(d.target) : '')
  const [start, setStart] = useState(toDateInput(parse(d?.start) ?? new Date()))
  const [hasDeadline, setHasDeadline] = useState(!!d?.deadline)
  const [deadline, setDeadline] = useState(toDateInput(parse(d?.deadline) ?? addDays(new Date(), 90)))
  const [habitUUID, setHabitUUID] = useState(d?.habitUUID ?? '')
  const [bucketUUID, setBucketUUID] = useState(d?.bucketUUID ?? '')
  const [steps, setSteps] = useState<string[]>(d?.steps ?? [])
  const [newStep, setNewStep] = useState('')

  const currency = useSetting<string>('currencyCode', defaultCurrency())
  const num = Number(target.replace(/,/g, '')) || 0
  const valid = !!title.trim() && (kind === 'steps' ? steps.length > 0 : kind === 'habit' ? !!habitUUID && num > 0 : num > 0)

  const addStep = () => {
    const s = newStep.trim()
    if (s && !steps.includes(s)) setSteps([...steps, s])
    setNewStep('')
  }

  const save = () => {
    if (!valid) return
    const patch: Partial<Goal> = {
      title: title.trim(), kind, target: kind === 'steps' ? steps.length : num,
      start: iso(startOfDay(fromInputs(start))), deadline: hasDeadline && deadline ? iso(fromInputs(deadline, '12:00')) : null,
      habitUUID: kind === 'habit' ? habitUUID : '', bucketUUID: kind === 'steps' ? bucketUUID : '',
      steps: kind === 'steps' ? steps : [], stepsDone: (d?.stepsDone ?? []).filter((x) => kind === 'steps' && steps.includes(x)),
    }
    if (goal) store.update<Goal>(goal.id, patch)
    else store.create<Goal>('goal', { ...newGoal('', kind, 0), ...patch })
    onClose()
  }

  const since = kind === 'books' ? 'Counting books finished since' : kind === 'save' ? 'Saving since' : 'Counting since'
  return (
    <Modal open onClose={onClose}>
      <div className="col" style={{ gap: 14 }}>
        <h2 className="display" style={{ fontSize: 26, margin: 0 }}>{goal ? 'Edit goal' : 'New goal'}</h2>
        <input className="field" autoFocus={!goal} placeholder="Read 24 books, save for a car…" value={title} onChange={(e) => setTitle(e.target.value)} />
        <span className="secondary" style={{ fontSize: 13, marginBottom: -6 }}>Tracks</span>
        <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          {KINDS.map((k) => (
            <button key={k.id} className="pill" onClick={() => setKind(k.id)}
              style={{ background: k.tint, opacity: kind === k.id ? 1 : 0.35, padding: '8px 12px', minHeight: 36, outline: kind === k.id ? '1.5px solid var(--ink)' : 'none' }}>
              {k.icon(13)}{k.title}
            </button>
          ))}
        </div>

        {kind === 'habit' && (
          <select className="field" style={{ minHeight: 40 }} value={habitUUID} onChange={(e) => setHabitUUID(e.target.value)}>
            <option value="">Choose…</option>
            {habits.map((h) => <option key={h.id} value={h.id}>{h.data.name}</option>)}
          </select>
        )}
        {kind !== 'steps' && (
          <>
            <label className="row" style={{ gap: 12, fontSize: 13 }}>
              <span className="secondary">{kind === 'books' ? 'Books' : kind === 'save' ? `Amount (${currency})` : 'Days'}</span><span className="spacer" />
              <input className="field" style={{ width: 160 }} inputMode="decimal" value={target} onChange={(e) => setTarget(e.target.value)}
                placeholder={kind === 'books' ? '24' : kind === 'save' ? '50000' : '30'} />
            </label>
            <label className="row" style={{ gap: 12, fontSize: 13 }}>
              <span className="secondary">{since}</span><span className="spacer" />
              <input type="date" className="field" style={{ width: 160 }} value={start} onChange={(e) => setStart(e.target.value)} />
            </label>
            {kind === 'save' && <span className="muted" style={{ fontSize: 11, marginTop: -8 }}>Counts your income minus your spending in Money since that day.</span>}
          </>
        )}
        {kind === 'steps' && (
          <div className="col" style={{ gap: 8 }}>
            <select className="field" style={{ minHeight: 40 }} value={bucketUUID} onChange={(e) => setBucketUUID(e.target.value)}>
              <option value="">None</option>
              {dreams.map((b) => <option key={b.id} value={b.id}>{b.data.title}</option>)}
            </select>
            {steps.map((s) => (
              <div key={s} className="row" style={{ gap: 8, fontSize: 14 }}>
                <span className="clamp1" style={{ flex: 1 }}>{s}</span>
                <button className="icon-btn" style={{ width: 40, height: 40 }} onClick={() => setSteps(steps.filter((x) => x !== s))}><X size={15} /></button>
              </div>
            ))}
            <div className="row" style={{ gap: 8 }}>
              <input className="field" style={{ flex: 1 }} placeholder="Book flights, save for tickets…" value={newStep}
                onChange={(e) => setNewStep(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') addStep() }} />
              <button className="btn-soft" style={{ minHeight: 40 }} disabled={!newStep.trim()} onClick={addStep}>Add</button>
            </div>
          </div>
        )}

        <div className="row" style={{ fontSize: 13, minHeight: 40 }}>
          <label className="row" style={{ gap: 6 }}>
            <input type="checkbox" checked={hasDeadline} onChange={(e) => setHasDeadline(e.target.checked)} />Deadline
          </label>
          <span className="spacer" />
          {hasDeadline && <input type="date" className="field" style={{ width: 160 }} value={deadline} onChange={(e) => setDeadline(e.target.value)} />}
        </div>

        <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
          {goal && <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(goal.id); onClose() }}>Delete</button>}
          {goal?.data.doneAt && <button className="btn-soft" onClick={() => { store.update<Goal>(goal.id, { doneAt: null }); onClose() }}>Reopen</button>}
          <span className="spacer" />
          <button className="btn-soft" onClick={onClose}>Cancel</button>
          <button className="btn-primary" style={{ width: 110 }} disabled={!valid} onClick={save}>Save</button>
        </div>
      </div>
    </Modal>
  )
}
