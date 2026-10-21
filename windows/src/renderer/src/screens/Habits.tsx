import { useState } from 'react'
import {
  Check, Footprints, BookOpen, Droplet, BedDouble, Leaf, Brain, CreditCard, Utensils, Dumbbell, Pencil, MoonStar,
  PhoneOff, Sun, Music, Heart, Plus, Repeat, Trash2, LucideIcon,
} from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Habit, Area, AREA_COLOR, areaOf } from '@/lib/models'
import { iso, dayKey, startOfDay, addDays, startOfWeek, isToday, fmtDay } from '@/lib/dates'
import { AreaPicker, EmptyHint, Modal } from '@/components/ui'

/** The Mac stores SF Symbol names; these are the ones its habit picker offers. */
export const HABIT_SYMBOLS: { name: string; icon: LucideIcon }[] = [
  { name: 'checkmark', icon: Check }, { name: 'figure.run', icon: Footprints }, { name: 'book.fill', icon: BookOpen },
  { name: 'drop.fill', icon: Droplet }, { name: 'bed.double.fill', icon: BedDouble }, { name: 'leaf.fill', icon: Leaf },
  { name: 'brain.head.profile', icon: Brain }, { name: 'creditcard', icon: CreditCard }, { name: 'fork.knife', icon: Utensils },
  { name: 'dumbbell.fill', icon: Dumbbell }, { name: 'pencil', icon: Pencil }, { name: 'moon.stars.fill', icon: MoonStar },
  { name: 'phone.down.fill', icon: PhoneOff }, { name: 'sun.max.fill', icon: Sun }, { name: 'music.note', icon: Music },
  { name: 'heart.fill', icon: Heart },
]
export const habitIcon = (name: string): LucideIcon => HABIT_SYMBOLS.find((s) => s.name === name)?.icon ?? Check

export const habitDone = (h: Habit, d: Date): boolean => (h.doneDays ?? []).includes(dayKey(d))

export function toggleHabit(rec: Rec<Habit>, d: Date): void {
  const k = dayKey(d)
  const days = rec.data.doneDays ?? []
  store.update<Habit>(rec.id, { doneDays: days.includes(k) ? days.filter((x) => x !== k) : [...days, k].sort() })
}

/** Consecutive days done, ending today (or yesterday if today isn't done yet). */
export function streak(h: Habit): number {
  let day = startOfDay(new Date())
  if (!habitDone(h, day)) day = addDays(day, -1)
  let n = 0
  while (habitDone(h, day)) { n++; day = addDays(day, -1) }
  return n
}

export function doneThisWeek(h: Habit): number {
  const start = startOfWeek(new Date())
  let n = 0
  for (let i = 0; i < 7; i++) if (habitDone(h, addDays(start, i))) n++
  return n
}

export default function Habits() {
  const habits = useRecords<Habit>('habit').sort((a, b) => (a.data.createdAt ?? '').localeCompare(b.data.createdAt ?? ''))
  const [adding, setAdding] = useState(false)
  return (
    <div className="page">
      <div className="col" style={{ gap: 24, paddingBottom: 32 }}>
        <div className="row" style={{ alignItems: 'baseline' }}>
          <h1 className="page-title">Habits</h1>
          <span className="spacer" />
          <button className="btn-soft" onClick={() => setAdding(true)}><Plus size={14} />New habit</button>
        </div>
        {habits.length === 0 && <EmptyHint icon={<Repeat size={14} />} text="Small daily wins add up. Add your first habit." />}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: 20 }}>
          {habits.map((h) => <HabitCard key={h.id} rec={h} />)}
        </div>
      </div>
      <NewHabit open={adding} onClose={() => setAdding(false)} />
    </div>
  )
}

const WEEKS = 18

function HabitCard({ rec }: { rec: Rec<Habit> }) {
  const h = rec.data
  const [menu, setMenu] = useState(false)
  const Icon = habitIcon(h.symbol)
  const today = startOfDay(new Date())
  const last7 = Array.from({ length: 7 }, (_, i) => addDays(today, i - 6))
  const gridStart = addDays(startOfWeek(new Date()), -7 * (WEEKS - 1))
  const color = AREA_COLOR[areaOf(h.area)]

  return (
    <div style={{ background: color, borderRadius: 22, padding: 20, color: 'var(--sticker-ink)', position: 'relative' }}
      onContextMenu={(e) => { e.preventDefault(); setMenu(true) }}>
      <div className="row" style={{ alignItems: 'flex-start', gap: 12 }}>
        <span style={{ width: 42, height: 42, borderRadius: '50%', background: 'rgba(255,255,255,.55)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon size={17} />
        </span>
        <div style={{ minWidth: 0 }}>
          <div className="clamp1" style={{ fontSize: 17, fontWeight: 600 }}>{h.name}</div>
          <div style={{ fontSize: 12, opacity: 0.7 }}>{doneThisWeek(h)} of {h.targetPerWeek ?? 7} this week</div>
        </div>
        <span className="spacer" />
        <div style={{ textAlign: 'right' }}>
          <div className="display" style={{ fontSize: 44, lineHeight: 1 }}>{streak(h)}</div>
          <div style={{ fontSize: 11, fontWeight: 500, opacity: 0.7 }}>day streak</div>
        </div>
      </div>

      <div className="row" style={{ gap: 8, marginTop: 16 }}>
        {last7.map((d) => {
          const done = habitDone(h, d)
          return (
            <button key={d.getTime()} onClick={() => toggleHabit(rec, d)} title={fmtDay(d)}
              style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, color: 'var(--sticker-ink)' }}>
              <span style={{ fontSize: 11, fontWeight: 500, opacity: 0.7 }}>{d.toLocaleDateString(undefined, { weekday: 'narrow' })}</span>
              <span style={{
                width: 34, height: 34, borderRadius: '50%', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                background: done ? '#111' : 'rgba(255,255,255,.55)', color: color,
                boxShadow: isToday(d) ? 'inset 0 0 0 1.5px #111' : undefined, transition: 'all .15s',
              }}>{done && <Check size={14} strokeWidth={3} />}</span>
            </button>
          )
        })}
      </div>

      <div style={{ fontSize: 11, fontWeight: 500, opacity: 0.7, margin: '16px 0 6px' }}>Last {WEEKS} weeks</div>
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${WEEKS}, 1fr)`, gap: 3 }}>
        {Array.from({ length: WEEKS }, (_, w) => (
          <div key={w} style={{ display: 'grid', gap: 3 }}>
            {Array.from({ length: 7 }, (_, d) => {
              const day = addDays(gridStart, w * 7 + d)
              const future = day > new Date()
              const done = habitDone(h, day)
              return <div key={d} title={`${fmtDay(day, { day: 'numeric', month: 'short', year: 'numeric' })}: ${done ? 'done' : 'missed'}`}
                style={{ aspectRatio: '1', borderRadius: 2.5, background: future ? 'transparent' : done ? 'rgba(17,17,17,.85)' : 'rgba(255,255,255,.45)' }} />
            })}
          </div>
        ))}
      </div>

      {menu && (
        <div className="backdrop" style={{ background: 'transparent' }} onMouseDown={() => setMenu(false)}>
          <div className="card col" style={{ position: 'absolute', padding: 12, gap: 10, background: 'var(--canvas)', color: 'var(--ink)', boxShadow: '0 10px 30px rgba(0,0,0,.2)', width: 300 }}
            onMouseDown={(e) => e.stopPropagation()}>
            <input className="field" value={h.name} onChange={(e) => store.update<Habit>(rec.id, { name: e.target.value })} />
            <div className="row" style={{ fontSize: 13 }}>
              Target
              <input type="number" min={1} max={7} className="field" style={{ width: 70, padding: '6px 10px' }} value={h.targetPerWeek ?? 7}
                onChange={(e) => store.update<Habit>(rec.id, { targetPerWeek: Math.max(1, Math.min(7, Number(e.target.value) || 1)) })} />
              per week
            </div>
            <AreaPicker value={areaOf(h.area)} onChange={(a) => store.update<Habit>(rec.id, { area: a })} />
            <div className="row">
              <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(rec.id); setMenu(false) }}><Trash2 size={13} />Delete habit</button>
              <span className="spacer" />
              <button className="btn-primary" onClick={() => setMenu(false)}>Done</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function NewHabit({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [name, setName] = useState('')
  const [symbol, setSymbol] = useState('checkmark')
  const [area, setArea] = useState<Area>('health')
  const [target, setTarget] = useState(7)

  const add = () => {
    if (!name.trim()) return
    store.create<Habit>('habit', { name: name.trim(), symbol, area, targetPerWeek: target, createdAt: iso(new Date()), doneDays: [] })
    setName(''); setSymbol('checkmark'); setTarget(7)
    onClose()
  }

  return (
    <Modal open={open} onClose={onClose} width={440}>
      <div className="col" style={{ gap: 18 }}>
        <h2 className="display" style={{ fontSize: 28, margin: 0 }}>New habit</h2>
        <input className="field" style={{ fontSize: 16 }} autoFocus placeholder="e.g. Meditate 10 minutes" value={name}
          onChange={(e) => setName(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') add() }} />
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(8, 38px)', gap: 8 }}>
          {HABIT_SYMBOLS.map(({ name: n, icon: I }) => (
            <button key={n} onClick={() => setSymbol(n)} title={n} style={{
              width: 38, height: 38, borderRadius: '50%', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              background: symbol === n ? AREA_COLOR[area] : 'var(--card)', color: symbol === n ? 'var(--sticker-ink)' : 'var(--ink)',
            }}><I size={16} /></button>
          ))}
        </div>
        <AreaPicker value={area} onChange={setArea} />
        <div className="row" style={{ fontSize: 13 }}>
          Target:
          <input type="number" min={1} max={7} className="field" style={{ width: 70, padding: '6px 10px' }} value={target}
            onChange={(e) => setTarget(Math.max(1, Math.min(7, Number(e.target.value) || 1)))} />
          days a week
        </div>
        <div className="row">
          <button className="btn-soft" onClick={onClose}>Cancel</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 140 }} disabled={!name.trim()} onClick={add}>Add habit</button>
        </div>
      </div>
    </Modal>
  )
}
