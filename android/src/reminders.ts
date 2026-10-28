// Reminders on Android: the Mac's Reminders.swift. Tasks due today and overdue (a morning summary), your own task
// reminders, events a few minutes before, bills before and on the day, habits and the journal in the evening,
// free trials and yearly renewals, trips (packing, flights), the evening nudge to plan tomorrow, the week in money
// and the weekly review on Sunday. Settings › Notifications switches each one off and sets the times (notify.*).
// Rescheduled whenever the data changes or Joshu comes back to the front.
import { useEffect, useState } from 'react'
import { LocalNotifications } from '@capacitor/local-notifications'
import { store, SettingKey, useStoreVersion } from '@/lib/store'
import { Task, CalEvent, Habit, Note, Subscription, Trip, Booking } from '@/lib/models'
import { parse, fmtTime, startOfDay, addDays, dayKey, relativeDay } from '@/lib/dates'
import { externalEvents } from '@/lib/externalEvents'
import { planFor } from '@/lib/dayPlan'
import { defaultCurrency } from '@/components/ui'
import { isNative } from './native'

export interface Bill { name: string; amount: number; dueDay: number; remindDays: number; match: string; category: string; paidMonths: string[]; notes: string; createdAt: string }

export const monthKey = (d: Date): string => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`

// MARK: Settings (the Mac's @AppStorage("notify.…"), synced with your account once the keys are in SYNCED_SETTINGS)

export const NOTIFY_DEFAULTS = {
  'notify.tasks': true, 'notify.events': true, 'notify.bills': true, 'notify.habits': true, 'notify.journal': true,
  'notify.review': true, 'notify.subscriptions': true, 'notify.evening': true, 'notify.trips': true, 'notify.weeklyMoney': true,
  'notify.budgets': true, 'notify.bigCharges': true,
  'notify.morningHour': 9, 'notify.habitHour': 20, 'notify.journalHour': 21, 'notify.eventLead': 10,
} as const
export type NotifyKey = keyof typeof NOTIFY_DEFAULTS
export type NotifySwitch = { [K in NotifyKey]: (typeof NOTIFY_DEFAULTS)[K] extends boolean ? K : never }[NotifyKey]
type NotifyValue<K extends NotifyKey> = (typeof NOTIFY_DEFAULTS)[K] extends boolean ? boolean : number

const LOCAL = 'notify.local.'
const subs = new Set<() => void>()

/** The synced value when there is one, then this phone's copy, then the Mac's default. */
export function notify<K extends NotifyKey>(key: K): NotifyValue<K> {
  const synced = store.setting(key as unknown as SettingKey)
  if (synced !== undefined && synced !== null) return synced as NotifyValue<K>
  try {
    const raw = localStorage.getItem(LOCAL + key)
    if (raw !== null) return JSON.parse(raw)
  } catch { /* fall back */ }
  return NOTIFY_DEFAULTS[key] as NotifyValue<K>
}

export function setNotify<K extends NotifyKey>(key: K, value: NotifyValue<K>): void {
  try { localStorage.setItem(LOCAL + key, JSON.stringify(value)) } catch { /* ignore */ }
  store.setSetting(key as unknown as SettingKey, value) // does nothing until the key is synced
  subs.forEach((f) => f())
  soon()
}

export function useNotify<K extends NotifyKey>(key: K): NotifyValue<K> {
  useStoreVersion()
  const [, tick] = useState(0)
  useEffect(() => { const f = () => tick((n) => n + 1); subs.add(f); return () => { subs.delete(f) } }, [])
  return notify(key)
}

/** Whether Android lets Joshu show notifications (null in the browser preview). */
export async function notificationsAllowed(): Promise<boolean | null> {
  if (!isNative) return null
  try { return (await LocalNotifications.checkPermissions()).display === 'granted' } catch { return null }
}

export async function requestNotifications(): Promise<boolean> {
  if (!isNative) return false
  try {
    const ok = (await LocalNotifications.requestPermissions()).display === 'granted'
    if (ok) scheduleReminders()
    return ok
  } catch { return false }
}

// MARK: Scheduling

const MAX = 60

function intID(s: string): number {
  let h = 0
  for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0
  return Math.abs(h) % 2_000_000_000
}

function money(v: number): string {
  const code = store.setting<string>('currencyCode') || defaultCurrency()
  try { return new Intl.NumberFormat(undefined, { style: 'currency', currency: code, maximumFractionDigits: 2, minimumFractionDigits: 0 }).format(Math.abs(v)) }
  catch { return `${code} ${Math.abs(v).toFixed(0)}` }
}

let timer: ReturnType<typeof setTimeout> | null = null
let subscribed = false
function soon(): void { if (timer) clearTimeout(timer); timer = setTimeout(scheduleReminders, 3000) }

interface Pending { id: number; title: string; body: string; schedule: { at: Date; allowWhileIdle: boolean }; extra: { route: string } }

export async function scheduleReminders(): Promise<void> {
  if (!isNative) return
  if (!subscribed) { subscribed = true; store.subscribe(() => { if (timer) clearTimeout(timer); timer = setTimeout(scheduleReminders, 5000) }) }
  try {
    let perm = await LocalNotifications.checkPermissions()
    if ((perm.display === 'prompt' || perm.display === 'prompt-with-rationale') && localStorage.getItem('notify.asked') !== '1') {
      localStorage.setItem('notify.asked', '1') // ask once, like the Mac
      perm = await LocalNotifications.requestPermissions()
    }
    if (perm.display !== 'granted') return
    const { own, auto } = buildReminders(new Date())

    // Replace only the reminders scheduled here before (spending alerts and others are left alone).
    const mine: number[] = JSON.parse(localStorage.getItem('reminders.ids') ?? '[]')
    if (mine.length) await LocalNotifications.cancel({ notifications: mine.map((id) => ({ id })) })
    // Your own reminders always get a slot; the automatic ones fill the rest.
    const byTime = (a: Pending, b: Pending) => a.schedule.at.getTime() - b.schedule.at.getTime()
    const next = [...own.sort(byTime).slice(0, MAX), ...auto.sort(byTime)].slice(0, MAX)
    const seen = new Set<number>()
    const unique = next.filter((n) => !seen.has(n.id) && seen.add(n.id))
    if (unique.length) await LocalNotifications.schedule({ notifications: unique })
    localStorage.setItem('reminders.ids', JSON.stringify(unique.map((n) => n.id)))
  } catch { /* notifications are a nice-to-have */ }
}

/** Everything to schedule from `now`: `own` are the reminders you set on tasks, `auto` the rest. */
export function buildReminders(now: Date): { own: Pending[]; auto: Pending[] } {
  const own: Pending[] = [], auto: Pending[] = []
  const today = startOfDay(now), tomorrow = addDays(today, 1), dayAfter = addDays(today, 2)
  const horizon = addDays(today, 15)
  const at = (day: Date, hour: number, minute = 0) => new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute)
  const add = (list: Pending[], key: string, title: string, body: string, when: Date | null, route: string, until = horizon) => {
    if (!when || when.getTime() <= now.getTime() + 5000 || when >= until) return
    list.push({ id: intID(`orbit.${key}`), title, body, schedule: { at: when, allowWhileIdle: true }, extra: { route } })
  }
  // Summaries are only right for the next couple of days (the Mac schedules two days ahead too).
  const within = (d: Date) => d > now && d < addDays(dayAfter, 1)

  const morningHour = notify('notify.morningHour'), habitHour = notify('notify.habitHour'), journalHour = notify('notify.journalHour')
  const eventLead = notify('notify.eventLead')
  const tasks = store.list<Task & { remindAt?: string | null }>('task').filter((t) => !t.data.isDone)

  // Reminders you set on a task ("remind me at…"): always, like the Mac's SmartReminders.
  for (const t of tasks) {
    const remind = parse(t.data.remindAt ?? null)
    if (!remind) continue
    const due = parse(t.data.due)
    add(own, `at-${t.id}`, t.data.title, t.data.notes?.trim() || (due ? `Due ${/^(Today|Tomorrow|Yesterday)$/.test(relativeDay(due)) ? relativeDay(due).toLowerCase() : relativeDay(due)}` : 'Reminder'), remind, 'tasks', addDays(today, 30))
  }

  if (notify('notify.tasks')) {
    for (const day of [today, tomorrow]) {
      const due = tasks.filter((t) => t.data.area !== 'money' && (() => { const d = parse(t.data.due); return !!d && startOfDay(d).getTime() === day.getTime() })())
        .sort((a, b) => b.data.priority - a.data.priority)
      if (due.length) {
        add(auto, `tasks-${dayKey(day)}`, due.length === 1 ? `Due today: ${due[0].data.title}` : `${due.length} tasks due today`,
          due.slice(0, 4).map((t) => t.data.title).join(' · '), at(day, morningHour), 'tasks')
      }
    }
    const overdue = tasks.filter((t) => { const d = parse(t.data.due); return !!d && startOfDay(d) < today })
    if (overdue.length) {
      const next = at(today, morningHour) > now ? at(today, morningHour) : at(tomorrow, morningHour)
      add(auto, 'overdue', `${overdue.length} overdue task${overdue.length === 1 ? '' : 's'}`, overdue.slice(0, 4).map((t) => t.data.title).join(' · '), next, 'tasks')
    }
    // A task due at a set time (not just a day) also gets its own alert then.
    for (const t of tasks) {
      const due = parse(t.data.due)
      if (!due || t.data.remindAt || (!due.getHours() && !due.getMinutes())) continue
      add(auto, `due-${t.id}`, t.data.title, `Due at ${fmtTime(due)}`, due, 'tasks')
    }
  }

  if (notify('notify.bills')) {
    for (const t of tasks) {
      if (t.data.area !== 'money') continue
      const due = parse(t.data.due)
      if (!due || due < tomorrow || due >= addDays(dayAfter, 1)) continue
      add(auto, `bill-${t.id}`, 'Bill due tomorrow', t.data.title.replace('Pay ', ''), at(addDays(startOfDay(due), -1), 18), 'money')
    }
    // Money › Bills: a few days before (unless it's already paid), and on the day.
    for (const b of store.list<Bill>('bill')) {
      for (const offset of [0, 1]) {
        const m = new Date(today.getFullYear(), today.getMonth() + offset, 1)
        if ((b.data.paidMonths ?? []).includes(monthKey(m))) continue
        const day = Math.min(Math.max(1, b.data.dueDay || 1), new Date(m.getFullYear(), m.getMonth() + 1, 0).getDate())
        const dueDate = new Date(m.getFullYear(), m.getMonth(), day)
        const amount = b.data.amount > 0 ? ` (${money(b.data.amount)})` : ''
        const r = b.data.remindDays ?? 2
        if (r > 0) {
          add(auto, `billsoon-${b.id}-${monthKey(m)}`, `${b.data.name} is due in ${r} day${r === 1 ? '' : 's'}`,
            `Due ${dueDate.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' })}${amount}.`, at(addDays(dueDate, -r), 10), 'money')
        }
        add(auto, `billday-${b.id}-${monthKey(m)}`, `${b.data.name} is due today`, `Pay it today${amount}. Joshu marks it paid when the payment shows up.`, at(dueDate, 9), 'money')
      }
    }
  }

  if (notify('notify.events')) {
    for (const e of store.list<CalEvent>('event')) {
      const start = parse(e.data.start), end = parse(e.data.end)
      if (!start) continue
      const allDay = !start.getHours() && !start.getMinutes() && !!end && end.getTime() - start.getTime() >= 86_400_000 - 60_000
      if (allDay) continue
      add(auto, `event-${e.id}`, e.data.title, `In ${eventLead} minutes · ${fmtTime(start)}${e.data.location ? ` · ${e.data.location}` : ''}`,
        new Date(start.getTime() - eventLead * 60_000), 'calendar')
    }
    // Google Calendar events fetched on this phone.
    for (const e of externalEvents(now, horizon)) {
      if (e.allDay) continue
      add(auto, `event-${e.id}`, e.title, `In ${eventLead} minutes · ${fmtTime(e.start)}${e.calendar ? ` · ${e.calendar}` : ''}`,
        new Date(e.start.getTime() - eventLead * 60_000), 'calendar')
    }
  }

  if (notify('notify.habits')) {
    const habits = store.list<Habit>('habit')
    for (const day of [today, tomorrow]) {
      const left = habits.filter((h) => !(h.data.doneDays ?? []).includes(dayKey(day)))
      if (left.length) add(auto, `habits-${dayKey(day)}`, 'Still time for your habits', left.slice(0, 4).map((h) => h.data.name).join(' · '), at(day, habitHour), 'habits')
    }
  }

  if (notify('notify.journal')) {
    const name = store.setting<string>('assistantName')?.trim() || 'Joshu'
    const journal = store.list<Note>('note').filter((n) => n.data.isJournal)
    for (const day of [today, tomorrow]) {
      const written = journal.some((n) => { const c = parse(n.data.createdAt); return !!c && startOfDay(c).getTime() === day.getTime() && (!!n.data.body?.trim() || !!n.data.chat) })
      if (!written) add(auto, `journal-${dayKey(day)}`, 'How was today?', `Take two minutes to check in with ${name}.`, at(day, journalHour), 'journal')
    }
  }

  if (notify('notify.subscriptions')) {
    for (const s of store.list<Subscription>('subscription')) {
      if (s.data.status === 'cancelled') continue
      const ends = parse(s.data.trialEnds), next = parse(s.data.nextDate)
      if (s.data.status === 'trial' && ends) {
        const when = at(addDays(startOfDay(ends), -2), 10)
        if (within(when)) {
          add(auto, `trial-${s.id}`, `${s.data.name} trial ends in 2 days`,
            `Then it charges ${money(s.data.amount)} ${s.data.cycle}. Cancel before ${ends.toLocaleDateString(undefined, { weekday: 'long' })} if you don't want it.`, when, 'money')
        }
      } else if (next && (s.data.cycle === 'yearly' || s.data.cycle === 'quarterly')) {
        const when = at(addDays(startOfDay(next), -1), 10)
        if (within(when)) add(auto, `renew-${s.id}`, `${s.data.name} renews tomorrow`, `${money(s.data.amount)} for another ${s.data.cycle === 'yearly' ? 'year' : 'quarter'}.`, when, 'money')
      }
    }
  }

  if (notify('notify.trips')) {
    for (const t of store.list<Trip>('trip')) {
      const start = parse(t.data.start)
      if (!start) continue
      const eve = at(addDays(startOfDay(start), -1), 19)
      const left = (t.data.packing ?? []).length - (t.data.packed ?? []).length
      if (within(eve)) add(auto, `pack-${t.id}`, `${t.data.title} is tomorrow ✈️`, left > 0 ? `${left} thing${left === 1 ? '' : 's'} left to pack.` : 'All packed. Have a great trip!', eve, 'bucket')
    }
    for (const f of store.list<Booking>('booking')) {
      if (f.data.kind !== 'flight') continue
      const dep = parse(f.data.start)
      if (!dep) continue
      const when = new Date(dep.getTime() - 3 * 3_600_000)
      if (within(when)) add(auto, `flight-${f.id}`, 'Flight in 3 hours', `${f.data.title}${f.data.confirmation ? ` · ref ${f.data.confirmation}` : ''}`, when, 'bucket')
    }
  }

  if (notify('notify.evening')) {
    // 8:30 pm: plan tomorrow, unless it's already planned.
    for (const day of [today, tomorrow]) {
      const when = at(day, 20, 30)
      if (within(when) && !planFor(dayKey(addDays(day, 1)))) add(auto, `plan-${dayKey(day)}`, 'Plan tomorrow', "Two minutes: clear what's left and pick tomorrow's top 3.", when, 'plan')
    }
  }

  const nextSunday = (hour: number) => {
    let d = today
    while (d.getDay() !== 0 || at(d, hour) <= now) d = addDays(d, 1)
    return d
  }
  if (notify('notify.weeklyMoney')) {
    const d = nextSunday(19)
    add(auto, `money-${dayKey(d)}`, 'Your week in money', 'See where your money went this week.', at(d, 19), 'money')
  }
  if (notify('notify.review')) {
    const d = nextSunday(18)
    add(auto, `review-${dayKey(d)}`, 'Your week in review', 'See how the week went and pick three things for next week.', at(d, 18), 'review')
  }
  return { own, auto }
}
