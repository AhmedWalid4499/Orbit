// Focus timer, same records as the Mac's FocusSession. One session runs at a time; a running one has no end,
// so it survives restarts. When its time is up it closes at the planned end (start + plannedMinutes).
import { useEffect, useState } from 'react'
import { store, useRecords, Rec } from './store'
import { FocusSession, Task } from './models'
import { iso, parse, startOfDay } from './dates'

export const FOCUS_LENGTHS = [15, 25, 50]
const LENGTH_KEY = 'orbit.focusMinutes'

export function rememberedLength(): number {
  const n = Number(localStorage.getItem(LENGTH_KEY))
  return FOCUS_LENGTHS.includes(n) ? n : 25
}

export const plannedEnd = (s: FocusSession): Date =>
  new Date((parse(s.start)?.getTime() ?? Date.now()) + (s.plannedMinutes || 25) * 60_000)

/** Minutes actually focused (a running session counts up to now, capped at its planned end). */
export function focusMinutes(s: FocusSession, now = new Date()): number {
  const start = parse(s.start)?.getTime()
  if (start === undefined) return 0
  const end = s.end ? parse(s.end)!.getTime() : Math.min(now.getTime(), plannedEnd(s).getTime())
  return Math.max(0, (end - start) / 60_000)
}

export function minutesFocusedSince(sessions: Rec<FocusSession>[], since: Date): number {
  return Math.floor(sessions.filter((s) => (parse(s.data.start) ?? new Date(0)) >= since).reduce((n, s) => n + focusMinutes(s.data), 0))
}
export const focusToday = (sessions: Rec<FocusSession>[]): number => minutesFocusedSince(sessions, startOfDay(new Date()))

export function activeFocus(): Rec<FocusSession> | undefined {
  return store.list<FocusSession>('focusSession').find((s) => !s.data.end)
}
export function useActiveFocus(): Rec<FocusSession> | undefined {
  return useRecords<FocusSession>('focusSession').find((s) => !s.data.end)
}

export function startFocus(task: Rec<Task> | null, minutes: number): void {
  const running = activeFocus()
  if (running) stopFocus(running)
  localStorage.setItem(LENGTH_KEY, String(minutes))
  store.create<FocusSession>('focusSession', {
    taskUUID: task?.id ?? '', taskTitle: task?.data.title ?? '', start: iso(new Date()), end: null, plannedMinutes: minutes,
  })
}

/** Stops early. Under a minute isn't worth keeping. */
export function stopFocus(s = activeFocus()): void {
  if (!s) return
  const end = new Date()
  if (end.getTime() - (parse(s.data.start)?.getTime() ?? 0) < 60_000) { store.remove(s.id); return }
  store.update<FocusSession>(s.id, { end: iso(end) })
}

// MARK: Bus: open the start sheet, and the "done" dialog

type Pending = { task: Rec<Task> | null } | null
let pendingStart: Pending = null
let finished: Rec<FocusSession> | null = null
const subs = new Set<() => void>()
const emit = () => subs.forEach((f) => f())

function useBus(): void {
  const [, force] = useState(0)
  useEffect(() => { const f = () => force((n) => n + 1); subs.add(f); return () => { subs.delete(f) } }, [])
}

/** Opens the "how long?" sheet for a task, or for no task. */
export function openFocus(task: Rec<Task> | null = null): void { pendingStart = { task }; emit() }
export function useFocusRequest(): [Pending, () => void] {
  useBus()
  return [pendingStart, () => { pendingStart = null; emit() }]
}
export function useFocusFinished(): [Rec<FocusSession> | null, () => void] {
  useBus()
  return [finished, () => { finished = null; emit() }]
}

/**
 * Closes a session whose time is up, at its planned end. It's announced (notification and the "done" dialog)
 * only when it just ran out; one that ran out while Orbit was closed is closed quietly.
 */
export function finishIfDue(): void {
  const s = activeFocus()
  if (!s) return
  const due = plannedEnd(s.data).getTime()
  if (Date.now() < due) return
  store.update<FocusSession>(s.id, { end: iso(new Date(due)) })
  if (Date.now() - due > 60_000) return
  finished = { ...s, data: { ...s.data, end: iso(new Date(due)) } }
  emit()
  try { new Notification('Focus done', { body: 'Take a 5-minute break.' }) } catch { /* notifications unavailable */ }
}
