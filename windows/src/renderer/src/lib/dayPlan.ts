// Evening plan: up to three priorities for tomorrow, saved as the Mac's `dayPlan` records (one per day).
import { store, Rec } from './store'
import { DayPlan, Task } from './models'
import { iso, parse, startOfDay, addDays, dayKey } from './dates'

/** The plan for a day ("yyyy-MM-dd"); the newest one if two devices made one. */
export function planFor(day: string, plans: Rec<DayPlan>[] = store.list<DayPlan>('dayPlan')): Rec<DayPlan> | undefined {
  return plans.filter((p) => p.data.day === day).sort((a, b) => (b.data.createdAt ?? '').localeCompare(a.data.createdAt ?? ''))[0]
}

export interface PlanItem { title: string; taskUUID: string }

/** Saves (or replaces) the plan for `day`. Linked tasks without a due date, or due earlier, become due that day. */
export function savePlan(day: string, items: PlanItem[], note: string): void {
  const top = items.slice(0, 3)
  const data: DayPlan = { day, top: top.map((i) => i.title), taskUUIDs: top.map((i) => i.taskUUID), note, createdAt: iso(new Date()) }
  const existing = planFor(day)
  if (existing) store.update<DayPlan>(existing.id, data)
  else store.create<DayPlan>('dayPlan', data)
  const [y, m, d] = day.split('-').map(Number)
  const dayStart = new Date(y, m - 1, d)
  for (const i of top) {
    if (!i.taskUUID) continue
    const t = store.get<Task>(i.taskUUID)
    const due = parse(t?.data.due)
    if (t && (!due || due < dayStart)) store.update<Task>(t.id, { due: iso(dayStart) })
  }
}

export const tomorrowKey = (): string => dayKey(addDays(startOfDay(new Date()), 1))
export const todayKey = (): string => dayKey(new Date())

/** "Plan the user made last night" line for Claude (morning brief). */
export function planText(): string {
  const p = planFor(todayKey())
  if (!p || (!p.data.top.length && !p.data.note)) return ''
  const items = p.data.top.map((t, i) => {
    const task = p.data.taskUUIDs[i] ? store.get<Task>(p.data.taskUUIDs[i]) : undefined
    return `${i + 1}. ${t}${task?.data.isDone ? ' (already done)' : ''}`
  })
  return `Plan the user made last night for today:\n${items.join('\n')}${p.data.note ? `\nNote: ${p.data.note}` : ''}`
}

// Typed-in plan items have no task to complete, so their ticks are kept on this PC.
const tickKey = (day: string) => `orbit.planTicks.${day}`
export function localTicks(day: string): number[] {
  try { return JSON.parse(localStorage.getItem(tickKey(day)) ?? '[]') } catch { return [] }
}
export function setLocalTick(day: string, index: number, on: boolean): void {
  const s = new Set(localTicks(day))
  if (on) s.add(index); else s.delete(index)
  localStorage.setItem(tickKey(day), JSON.stringify([...s]))
}
