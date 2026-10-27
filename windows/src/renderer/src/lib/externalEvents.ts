// Calendar events that live outside the account (e.g. Google Calendar, fetched by the Android app), shown
// next to your own events but never synced or edited here. Empty unless a platform fills it.
import { useSyncExternalStore } from 'react'

export interface ExternalEvent { id: string; title: string; start: Date; end: Date; allDay: boolean; calendar: string; color: string }

let events: ExternalEvent[] = []
const subs = new Set<() => void>()

export function setExternalEvents(list: ExternalEvent[]): void { events = list; subs.forEach((f) => f()) }
export function externalEvents(from: Date, to: Date): ExternalEvent[] { return events.filter((e) => e.start < to && e.end > from) }
export function useExternalEvents(): ExternalEvent[] {
  return useSyncExternalStore((f) => { subs.add(f); return () => { subs.delete(f) } }, () => events)
}
