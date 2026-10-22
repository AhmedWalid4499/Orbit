// Bucket list, like BucketListView.swift on the Mac.
import { useEffect, useMemo, useState } from 'react'
import { Luggage, Plane, Sparkles, Mountain, GraduationCap, Paintbrush, Users, Star, Plus, Calendar, CheckCircle2, Circle, BadgeCheck } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Bucket as BucketItem, BucketKind, BUCKET_KINDS, bucketKind, Trip } from '@/lib/models'
import { TripsSection, newTripFromBucket } from './Trips'
import { iso, parse, startOfDay, daysBetween, toDateInput, fromInputs, addDays } from '@/lib/dates'
import { Modal, Segmented } from '@/components/ui'

const KIND_ICON: Record<BucketKind, (size: number) => JSX.Element> = {
  travel: (s) => <Plane size={s} />,
  experience: (s) => <Sparkles size={s} />,
  adventure: (s) => <Mountain size={s} />,
  learn: (s) => <GraduationCap size={s} />,
  create: (s) => <Paintbrush size={s} />,
  people: (s) => <Users size={s} />,
  other: (s) => <Star size={s} />,
}
const kindIcon = (k: string, size = 14) => (KIND_ICON[k as BucketKind] ?? KIND_ICON.other)(size)

export default function Bucket() {
  const items = useRecords<BucketItem>('bucket')
  const [show, setShow] = useState<'dreams' | 'done'>('dreams')
  const [kind, setKind] = useState<BucketKind | null>(null)
  const [editing, setEditing] = useState<Rec<BucketItem> | null>(null)
  const [adding, setAdding] = useState(false)
  const [openTrip, setOpenTrip] = useState<string | null>(null)
  const trips = useRecords<Trip>('trip')

  const done = items.filter((i) => i.data.isDone).length
  const today = startOfDay(new Date())

  const upcoming = useMemo(() => items
    .filter((i) => !i.data.isDone && (parse(i.data.targetDate)?.getTime() ?? -Infinity) >= today.getTime())
    .sort((a, b) => parse(a.data.targetDate)!.getTime() - parse(b.data.targetDate)!.getTime()), [items])

  const visible = useMemo(() => items
    .filter((i) => (show === 'done' ? i.data.isDone : !i.data.isDone))
    .filter((i) => !kind || i.data.kind === kind)
    .sort((a, b) => show === 'done'
      ? (parse(b.data.doneAt)?.getTime() ?? 0) - (parse(a.data.doneAt)?.getTime() ?? 0)
      : (b.data.excitement ?? 2) - (a.data.excitement ?? 2)), [items, show, kind])

  return (
    <div className="page">
      <div className="col" style={{ gap: 22 }}>
        <div className="row" style={{ gap: 16 }}>
          <div>
            <h1 className="page-title">Bucket list</h1>
            <div className="secondary" style={{ fontSize: 14, marginTop: 4 }}>
              {items.length === 0 ? 'The things you want to do, see, learn and feel.' : `${done} of ${items.length} done. Keep dreaming.`}
            </div>
          </div>
          <span className="spacer" />
          {items.length > 0 && <Ring done={done} total={items.length} />}
          <button className="btn-soft" onClick={() => setAdding(true)}><Plus size={14} />Add dream</button>
        </div>

        <TripsSection openTrip={openTrip} onOpen={setOpenTrip} />

        {upcoming.length > 0 && (
          <div className="col" style={{ gap: 12 }}>
            <h3 className="section-title">Looking forward to</h3>
            <div className="row" style={{ gap: 14, overflowX: 'auto', paddingBottom: 2 }}>
              {upcoming.map((i) => {
                const days = daysBetween(today, parse(i.data.targetDate)!)
                const k = bucketKind(i.data.kind)
                return (
                  <button key={i.id} onClick={() => setEditing(i)} className="row"
                    style={{ gap: 14, padding: 16, borderRadius: 20, background: k.color, color: 'var(--sticker-ink)', flex: 'none', textAlign: 'left' }}>
                    <div style={{ width: 64, textAlign: 'center' }}>
                      <div className="display" style={{ fontSize: days === 0 ? 30 : 34 }}>{days === 0 ? '🎉' : days}</div>
                      <div style={{ fontSize: 11, fontWeight: 600, opacity: 0.7 }}>{days === 0 ? 'today' : days === 1 ? 'day' : 'days'}</div>
                    </div>
                    <div style={{ width: 180 }}>
                      <div className="row" style={{ gap: 4, fontSize: 11, fontWeight: 600, opacity: 0.75 }}>{kindIcon(i.data.kind, 12)}{k.title}</div>
                      <div className="clamp2" style={{ fontSize: 15, fontWeight: 600 }}>{i.data.title}</div>
                      <div style={{ fontSize: 11, opacity: 0.7 }}>
                        {parse(i.data.targetDate)!.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'short' })}
                      </div>
                    </div>
                  </button>
                )
              })}
            </div>
          </div>
        )}

        <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
          {(['dreams', 'done'] as const).map((s) => (
            <button key={s} onClick={() => setShow(s)}
              style={{ padding: '7px 14px', borderRadius: 999, fontSize: 13, fontWeight: 600,
                background: show === s ? 'var(--inverse)' : 'var(--card)', color: show === s ? 'var(--on-inverse)' : 'var(--ink)' }}>
              {s === 'done' ? `Done (${done})` : `Dreams (${items.length - done})`}
            </button>
          ))}
          <span style={{ width: 1, height: 22, background: 'var(--line)', margin: '0 4px' }} />
          {BUCKET_KINDS.map((k) => (
            <button key={k.id} className="pill" onClick={() => setKind(kind === k.id ? null : k.id)}
              style={{ background: k.color, opacity: !kind || kind === k.id ? 1 : 0.3, padding: '6px 10px' }}>
              {kindIcon(k.id, 12)}{k.title}
            </button>
          ))}
        </div>

        {visible.length === 0 && (
          <div className="col secondary" style={{ alignItems: 'center', padding: '50px 0', gap: 10 }}>
            <Mountain size={40} strokeWidth={1.2} />
            <div style={{ fontSize: 14, textAlign: 'center' }}>
              {show === 'done' ? 'Nothing ticked off yet. Your first one is coming.' : 'What do you want to do one day? See the northern lights, learn Japanese, run a marathon…'}
            </div>
            {show !== 'done' && <button className="btn-soft" onClick={() => setAdding(true)}>Add your first dream</button>}
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))', gap: 16, alignItems: 'start' }}>
          {visible.map((i) => {
            const trip = trips.find((t) => t.data.bucketUUID === i.id)
            const plan = i.data.kind === 'travel' && !i.data.isDone ? () => setOpenTrip(trip ? trip.id : newTripFromBucket(i)) : undefined
            return <BucketCard key={i.id} item={i} onOpen={() => setEditing(i)} onPlanTrip={plan} hasTrip={!!trip} />
          })}
        </div>
      </div>

      {adding && <Editor item={null} onClose={() => setAdding(false)} />}
      {editing && <Editor item={editing} onClose={() => setEditing(null)} />}
    </div>
  )
}

function Ring({ done, total }: { done: number; total: number }) {
  const r = 23, c = 2 * Math.PI * r
  return (
    <div style={{ position: 'relative', width: 54, height: 54 }}>
      <svg width={54} height={54} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={27} cy={27} r={r} fill="none" stroke="var(--card)" strokeWidth={8} />
        <circle cx={27} cy={27} r={r} fill="none" stroke="var(--lime)" strokeWidth={8} strokeLinecap="round"
          strokeDasharray={c} strokeDashoffset={c * (1 - (total ? done / total : 0))} />
      </svg>
      <div className="display" style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>{done}</div>
    </div>
  )
}

function BucketCard({ item, onOpen, onPlanTrip, hasTrip }: { item: Rec<BucketItem>; onOpen: () => void; onPlanTrip?: () => void; hasTrip?: boolean }) {
  const [celebrate, setCelebrate] = useState(false)
  const [hover, setHover] = useState(false)
  const k = bucketKind(item.data.kind)
  const target = parse(item.data.targetDate)
  const doneAt = parse(item.data.doneAt)

  useEffect(() => {
    if (!celebrate) return
    const t = setTimeout(() => setCelebrate(false), 1500)
    return () => clearTimeout(t)
  }, [celebrate])

  const toggle = (e: React.MouseEvent) => {
    e.stopPropagation()
    const isDone = !item.data.isDone
    store.update<BucketItem>(item.id, { isDone, doneAt: isDone ? iso(new Date()) : null })
    setCelebrate(isDone)
  }

  return (
    <div onClick={onOpen} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      className="col"
      style={{ position: 'relative', gap: 10, padding: 18, borderRadius: 22, cursor: 'pointer', color: 'var(--sticker-ink)',
        background: k.color, opacity: item.data.isDone ? 0.6 : 1, transform: hover ? 'scale(1.02)' : 'none', transition: 'transform 0.2s' }}>
      <div className="row">
        <span style={{ width: 34, height: 34, borderRadius: '50%', background: 'rgba(255,255,255,0.5)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
          {kindIcon(item.data.kind, 15)}
        </span>
        <span className="spacer" />
        <span style={{ fontSize: 12 }} title={['', 'Nice to do', 'Really want to', "Can't wait"][Math.max(1, Math.min(3, item.data.excitement || 1))]}>
          {'🔥'.repeat(Math.max(1, item.data.excitement || 1))}
        </span>
      </div>
      <div className="display" style={{ fontSize: 20, lineHeight: 1.2 }}>{item.data.title}</div>
      {item.data.notes && <div className="clamp2" style={{ fontSize: 12, opacity: 0.75 }}>{item.data.notes}</div>}
      <div className="row" style={{ fontSize: 11, fontWeight: 600, flexWrap: 'wrap', rowGap: 6, whiteSpace: 'nowrap' }}>
        {item.data.isDone && doneAt
          ? <span className="row" style={{ gap: 4 }}><BadgeCheck size={13} />Done {doneAt.toLocaleDateString(undefined, { month: 'short', year: 'numeric' })}</span>
          : target
            ? <span className="row" style={{ gap: 4 }}><Calendar size={12} />{target.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}</span>
            : <span style={{ opacity: 0.6 }}>Someday</span>}
        <span className="spacer" />
        {onPlanTrip && (
          <button onClick={(e) => { e.stopPropagation(); onPlanTrip() }} className="row"
            style={{ gap: 5, padding: '5px 10px', borderRadius: 999, background: 'rgba(255,255,255,0.55)', fontSize: 12, fontWeight: 600, color: 'var(--sticker-ink)' }}>
            <Luggage size={13} />{hasTrip ? 'Open trip' : 'Plan trip'}
          </button>
        )}
        <button onClick={toggle} className="row"
          style={{ gap: 5, padding: '5px 10px', borderRadius: 999, background: 'rgba(255,255,255,0.55)', fontSize: 12, fontWeight: 600, color: 'var(--sticker-ink)' }}>
          {item.data.isDone ? <CheckCircle2 size={13} /> : <Circle size={13} />}
          {item.data.isDone ? 'Done' : 'Did it'}
        </button>
      </div>
      {celebrate && <div style={{ position: 'absolute', top: -18, right: -6, fontSize: 40, animation: 'fade 0.2s' }}>🎉</div>}
    </div>
  )
}

function Editor({ item, onClose }: { item: Rec<BucketItem> | null; onClose: () => void }) {
  const d = item?.data
  const [title, setTitle] = useState(d?.title ?? '')
  const [notes, setNotes] = useState(d?.notes ?? '')
  const [kind, setKind] = useState<BucketKind>((d?.kind as BucketKind) ?? 'experience')
  const [excitement, setExcitement] = useState(String(d?.excitement ?? 2) as '1' | '2' | '3')
  const existing = parse(d?.targetDate)
  const [hasDate, setHasDate] = useState(!!existing)
  const [date, setDate] = useState(toDateInput(existing ?? addDays(new Date(), 30)))

  const save = () => {
    const t = title.trim()
    if (!t) return
    const targetDate = hasDate && date ? iso(fromInputs(date)) : null
    if (item) {
      store.update<BucketItem>(item.id, { title: t, notes, kind, excitement: Number(excitement), targetDate })
    } else {
      store.create<BucketItem>('bucket', {
        title: t, notes, kind, targetDate, excitement: Number(excitement), isDone: false, doneAt: null, createdAt: iso(new Date()),
      })
    }
    onClose()
  }

  return (
    <Modal open onClose={onClose} width={500}>
      <div className="col" style={{ gap: 16 }}>
        <h2 className="display" style={{ fontSize: 28, margin: 0 }}>{item ? 'Edit' : 'New dream'}</h2>
        <input className="field" autoFocus placeholder="e.g. See the northern lights" value={title}
          style={{ fontSize: 16 }} onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') save() }} />
        <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
          {BUCKET_KINDS.map((k) => (
            <button key={k.id} className="pill" onClick={() => setKind(k.id)}
              style={{ background: k.color, opacity: kind === k.id ? 1 : 0.3, padding: '6px 10px', outline: kind === k.id ? '1.5px solid var(--ink)' : 'none' }}>
              {kindIcon(k.id, 12)}{k.title}
            </button>
          ))}
        </div>
        <div className="row">
          <span className="secondary" style={{ fontSize: 13 }}>How much do you want it?</span>
          <span className="spacer" />
          <Segmented options={[{ id: '1', label: 'Nice to do' }, { id: '2', label: 'Really want to' }, { id: '3', label: "Can't wait" }]}
            value={excitement} onChange={setExcitement} />
        </div>
        <div className="row" style={{ fontSize: 13 }}>
          <label className="row" style={{ gap: 6, cursor: 'pointer' }}>
            <input type="checkbox" checked={hasDate} onChange={(e) => setHasDate(e.target.checked)} />
            I have a date in mind
          </label>
          {hasDate && <input type="date" className="field" style={{ width: 170, padding: '6px 10px' }} value={date} onChange={(e) => setDate(e.target.value)} />}
        </div>
        <textarea className="field" rows={4} placeholder="Notes: why, who with, what it takes…" value={notes} onChange={(e) => setNotes(e.target.value)} />
        <div className="row">
          {item
            ? <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(item.id); onClose() }}>Delete</button>
            : <button className="btn-soft" onClick={onClose}>Cancel</button>}
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120 }} disabled={!title.trim()} onClick={save}>{item ? 'Save' : 'Add'}</button>
        </div>
      </div>
    </Modal>
  )
}
