// Reminders on Android: the Mac's Reminders.swift, reduced to what a phone needs most: tasks (their
// reminder time, or the due time), events (a few minutes before) and bills (before the due day).
// Rescheduled whenever the data changes or Joshu comes back to the front; the next 14 days are kept.
import { LocalNotifications } from '@capacitor/local-notifications'
import { store } from '@/lib/store'
import { Task, CalEvent } from '@/lib/models'
import { parse, fmtTime } from '@/lib/dates'
import { isNative } from './native'

export interface Bill { name: string; amount: number; dueDay: number; remindDays: number; match: string; category: string; paidMonths: string[]; notes: string; createdAt: string }

const HORIZON = 14 * 86_400_000
const EVENT_LEAD_MIN = 10

function intID(s: string): number {
  let h = 0
  for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0
  return Math.abs(h) % 2_000_000_000
}

export const monthKey = (d: Date): string => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`

let timer: ReturnType<typeof setTimeout> | null = null
let subscribed = false

export async function scheduleReminders(): Promise<void> {
  if (!isNative) return
  if (!subscribed) { subscribed = true; store.subscribe(() => { if (timer) clearTimeout(timer); timer = setTimeout(scheduleReminders, 5000) }) }
  try {
    let perm = await LocalNotifications.checkPermissions()
    if (perm.display === 'prompt' || perm.display === 'prompt-with-rationale') perm = await LocalNotifications.requestPermissions()
    if (perm.display !== 'granted') return
    const now = Date.now(), end = now + HORIZON
    const list: { id: number; title: string; body: string; schedule: { at: Date; allowWhileIdle: boolean } }[] = []
    const add = (key: string, at: Date | null, title: string, body: string) => {
      if (at && at.getTime() > now && at.getTime() < end) list.push({ id: intID(key), title, body, schedule: { at, allowWhileIdle: true } })
    }
    for (const t of store.list<Task & { remindAt?: string }>('task')) {
      if (t.data.isDone) continue
      const remind = parse(t.data.remindAt ?? null)
      const due = parse(t.data.due)
      // A due date at midnight means "that day": remind at 9 in the morning.
      const at = remind ?? (due && (due.getHours() || due.getMinutes()) ? due : due ? new Date(due.getFullYear(), due.getMonth(), due.getDate(), 9) : null)
      add(`task:${t.id}`, at, t.data.title, remind ? 'Reminder' : due && (due.getHours() || due.getMinutes()) ? `Due at ${fmtTime(due)}` : 'Due today')
    }
    for (const e of store.list<CalEvent>('event')) {
      const start = parse(e.data.start)
      if (!start) continue
      add(`event:${e.id}`, new Date(start.getTime() - EVENT_LEAD_MIN * 60_000), e.data.title, `${fmtTime(start)}${e.data.location ? ` · ${e.data.location}` : ''}`)
    }
    const cur = store.setting<string>('currencyCode') ?? 'EGP'
    for (const b of store.list<Bill>('bill')) {
      for (const offset of [0, 1]) {
        const d = new Date(); d.setMonth(d.getMonth() + offset)
        if ((b.data.paidMonths ?? []).includes(monthKey(d))) continue
        const day = Math.min(Math.max(1, b.data.dueDay), new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate())
        const at = new Date(d.getFullYear(), d.getMonth(), day - (b.data.remindDays ?? 2), 10)
        add(`bill:${b.id}:${monthKey(d)}`, at, `${b.data.name} is due ${b.data.remindDays ? `in ${b.data.remindDays} days` : 'today'}`,
          b.data.amount ? `${Math.round(b.data.amount)} ${cur}` : 'Bill reminder')
      }
    }
    const pending = await LocalNotifications.getPending()
    if (pending.notifications.length) await LocalNotifications.cancel({ notifications: pending.notifications.map((n) => ({ id: n.id })) })
    list.sort((a, b) => a.schedule.at.getTime() - b.schedule.at.getTime())
    if (list.length) await LocalNotifications.schedule({ notifications: list.slice(0, 60) })
  } catch { /* notifications are a nice-to-have */ }
}
