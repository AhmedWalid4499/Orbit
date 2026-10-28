// Habits on the phone: PhoneHabits in iOS/OrbitPhone/PhoneSections.swift, which shows HabitsView.swift as it is.
// One card per habit in its area's colour: this week's count, the streak, the last 7 days to tick, and the last
// 18 weeks as a grid. Press and hold a card for its target, area and Delete (the Mac's context menu).
import { useState } from 'react'
import { Plus, Repeat, Check, Minus, Trash2, Target, Palette } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Habit, Area, AREA_COLOR, AREAS, areaOf, cap } from '@/lib/models'
import { iso, startOfDay, addDays, startOfWeek, isToday, fmtDay } from '@/lib/dates'
import { AreaPicker, Modal } from '@/components/ui'
import { HABIT_SYMBOLS, habitIcon, habitDone, toggleHabit, streak, doneThisWeek } from '@/screens/Habits'
import { SectionTitle, ActionSheet, useLongPress } from './pm2Kit'
import './pm2.css'

const WEEKS = 18

export default function PhoneHabits() {
  const habits = useRecords<Habit>('habit').slice().sort((a, b) => (a.data.createdAt ?? '').localeCompare(b.data.createdAt ?? ''))
  const [adding, setAdding] = useState(false)
  return (
    <div className="pm2" style={{ gap: 24 }}>
      <SectionTitle>Habits</SectionTitle>
      <div className="pm2-row" style={{ justifyContent: 'flex-end', marginTop: -8 }}>
        <button className="pm2-soft" onClick={() => setAdding(true)}><Plus size={15} />New habit</button>
      </div>
      {habits.length === 0 && <div className="pm2-empty"><Repeat size={15} />Small daily wins add up. Add your first habit.</div>}
      {habits.map((h) => <HabitCard key={h.id} rec={h} />)}
      <Modal open={adding} onClose={() => setAdding(false)}>{adding && <NewHabit onClose={() => setAdding(false)} />}</Modal>
    </div>
  )
}

function HabitCard({ rec }: { rec: Rec<Habit> }) {
  const h = rec.data
  const [menu, setMenu] = useState(false)
  const [areaMenu, setAreaMenu] = useState(false)
  const { consumed, ...press } = useLongPress(() => setMenu(true))
  const Icon = habitIcon(h.symbol)
  const color = AREA_COLOR[areaOf(h.area)]
  const today = startOfDay(new Date())
  const last7 = Array.from({ length: 7 }, (_, i) => addDays(today, i - 6))
  const start = addDays(startOfWeek(new Date()), -7 * (WEEKS - 1))
  const target = Number(h.targetPerWeek) || 7

  return (
    <>
    <div className="pm2-habit" style={{ background: color }} {...press}>
      <div className="pm2-row" style={{ alignItems: 'flex-start', gap: 10 }}>
        <span className="ic"><Icon size={17} strokeWidth={2.4} /></span>
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
          <span className="clamp1" style={{ fontSize: 17, fontWeight: 600 }}>{h.name}</span>
          <span style={{ fontSize: 12, opacity: 0.7 }}>{doneThisWeek(h)} of {target} this week</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
          <span className="streak">{streak(h)}</span>
          <span style={{ fontSize: 11, fontWeight: 500, opacity: 0.7 }}>day streak</span>
        </div>
      </div>

      <div className="pm2-row" style={{ gap: 8 }}>
        {last7.map((d) => {
          const done = habitDone(h, d)
          return (
            <button key={d.getTime()} className="pm2-hday" onClick={() => { if (!consumed()) toggleHabit(rec, d) }}>
              <span className="w">{d.toLocaleDateString(undefined, { weekday: 'narrow' })}</span>
              <span className={`c ${done ? 'done' : ''} ${isToday(d) ? 'today' : ''}`}>{done && <Check size={14} strokeWidth={3.2} color={color} />}</span>
            </button>
          )
        })}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <span style={{ fontSize: 11, fontWeight: 500, opacity: 0.7 }}>Last {WEEKS} weeks</span>
        <div className="pm2-heat">
          {Array.from({ length: WEEKS * 7 }, (_, i) => {
            const day = addDays(start, i)
            const future = day > new Date(), done = habitDone(h, day)
            return <i key={i} className={future ? 'future' : done ? 'done' : ''} title={`${fmtDay(day, { day: 'numeric', month: 'short', year: 'numeric' })} — ${done ? 'done' : 'missed'}`} />
          })}
        </div>
      </div>
    </div>

      <ActionSheet open={menu} onClose={() => setMenu(false)} title={h.name} actions={[
        { label: 'Area', icon: <Palette size={17} />, onClick: () => setAreaMenu(true) },
        { label: 'Delete habit', icon: <Trash2 size={17} />, danger: true, onClick: () => store.remove(rec.id) },
      ]}>
        <div className="pm2-row" style={{ fontSize: 15 }}>
          <Target size={17} /><span>Target: {target}/week</span><span className="pm2-spacer" />
          <span className="pm2-stepper">
            <button aria-label="Fewer" disabled={target <= 1} onClick={() => store.update<Habit>(rec.id, { targetPerWeek: Math.max(1, target - 1) })}><Minus size={16} /></button>
            <button aria-label="More" disabled={target >= 7} onClick={() => store.update<Habit>(rec.id, { targetPerWeek: Math.min(7, target + 1) })}><Plus size={16} /></button>
          </span>
        </div>
      </ActionSheet>
      <ActionSheet open={areaMenu} onClose={() => setAreaMenu(false)} title="Area"
        actions={AREAS.map((a) => ({ label: cap(a), icon: <span style={{ width: 14, height: 14, borderRadius: '50%', background: AREA_COLOR[a] }} />, onClick: () => store.update<Habit>(rec.id, { area: a }) }))} />
    </>
  )
}

/** NewHabitSheet: name, symbol, area and how many days a week. */
function NewHabit({ onClose }: { onClose: () => void }) {
  const [name, setName] = useState('')
  const [area, setArea] = useState<Area>('health')
  const [target, setTarget] = useState(7)
  const [symbol, setSymbol] = useState('checkmark')
  const add = () => {
    if (!name.trim()) return
    store.create<Habit>('habit', { name, symbol, area, targetPerWeek: target, createdAt: iso(new Date()), doneDays: [] })
    onClose()
  }
  return (
    <div className="pm2-sheet" style={{ gap: 18 }}>
      <h2 className="pm2-display" style={{ fontSize: 28 }}>New habit</h2>
      <input className="pm2-field" autoFocus placeholder="e.g. Meditate 10 minutes" value={name} onChange={(e) => setName(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter') add() }} />
      <div className="pm2-symbols">
        {HABIT_SYMBOLS.map((s) => (
          <button key={s.name} className={symbol === s.name ? 'on' : ''} style={symbol === s.name ? { background: AREA_COLOR[area] } : undefined}
            onClick={() => setSymbol(s.name)} aria-label={s.name}><s.icon size={16} /></button>
        ))}
      </div>
      <AreaPicker value={area} onChange={setArea} />
      <div className="pm2-row" style={{ fontSize: 13 }}>
        <span>Target: {target} days a week</span><span className="pm2-spacer" />
        <span className="pm2-stepper">
          <button aria-label="Fewer" disabled={target <= 1} onClick={() => setTarget(Math.max(1, target - 1))}><Minus size={16} /></button>
          <button aria-label="More" disabled={target >= 7} onClick={() => setTarget(Math.min(7, target + 1))}><Plus size={16} /></button>
        </span>
      </div>
      <div className="pm2-row">
        <button className="pm2-soft" onClick={onClose}>Cancel</button>
        <span className="pm2-spacer" />
        <button className="pm2-primary" style={{ width: 140 }} disabled={!name.trim()} onClick={add}>Add habit</button>
      </div>
    </div>
  )
}
