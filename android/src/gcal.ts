// Google Calendar on Android, like the Mac's GoogleCalendarStore: events from every connected Google account
// (the same sign-in as Gmail), 45 days back to 180 ahead, refreshed at most every 15 minutes. They show in
// Calendar and on Today next to your own events, and are never copied into your account.
import { setExternalEvents, ExternalEvent } from '@/lib/externalEvents'
import { refreshKeys } from '@/lib/ai'
import { addDays, startOfDay } from '@/lib/dates'

const CACHE = 'orbit.gcal'
let last = 0
export let gcalProblem = ''

function restore(): void {
  try {
    const c = JSON.parse(localStorage.getItem(CACHE) ?? 'null')
    if (c) setExternalEvents(c.map((e: any) => ({ ...e, start: new Date(e.start), end: new Date(e.end) })))
  } catch { /* none yet */ }
}
restore()

const dayOnly = (s: string): Date => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d) }

export async function refreshGoogleCalendar(force = false): Promise<void> {
  // Turned off in Connections.
  if (localStorage.getItem('googleCalendarEnabled') === 'false') { setExternalEvents([]); return }
  if (!force && Date.now() - last < 15 * 60_000) return
  last = Date.now()
  const { gmail } = await refreshKeys()
  if (!gmail.length) { setExternalEvents([]); return }
  const from = addDays(startOfDay(new Date()), -45).toISOString(), to = addDays(startOfDay(new Date()), 180).toISOString()
  const out: ExternalEvent[] = []
  const problems: string[] = []
  for (const account of gmail) {
    const list = await window.orbit.googleGet(account, 'https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader')
    if (!list.ok) { problems.push(list.status === 403 ? `${account}: reconnect it in Settings › Email to allow Calendar.` : `${account}: ${list.error}`); continue }
    const calendars = (list.data?.items ?? []).filter((c: any) => c.selected ?? c.primary ?? false)
    for (const cal of calendars) {
      let page = ''
      do {
        const q = new URLSearchParams({ timeMin: from, timeMax: to, singleEvents: 'true', orderBy: 'startTime', maxResults: '2500', ...(page ? { pageToken: page } : {}) })
        const r = await window.orbit.googleGet(account, `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(cal.id)}/events?${q}`)
        if (!r.ok) break
        for (const e of r.data?.items ?? []) {
          if (e.status === 'cancelled' || !e.start || !e.end) continue
          const allDay = !!e.start.date
          const start = allDay ? dayOnly(e.start.date) : new Date(e.start.dateTime)
          const end = allDay ? dayOnly(e.end.date) : new Date(e.end.dateTime)
          if (isNaN(start.getTime()) || isNaN(end.getTime())) continue
          out.push({ id: `g:${account}-${e.id}`, title: e.summary ?? '(No title)', start, end, allDay,
            calendar: cal.summaryOverride ?? cal.summary ?? 'Google', color: cal.backgroundColor ?? 'var(--cyan)' })
        }
        page = r.data?.nextPageToken ?? ''
      } while (page)
    }
  }
  gcalProblem = problems[0] ?? ''
  setExternalEvents(out)
  try { localStorage.setItem(CACHE, JSON.stringify(out)) } catch { /* too big: memory only */ }
}
