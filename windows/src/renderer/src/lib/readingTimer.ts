// Reading timer, same behaviour as ReadingTimer in ReadingExtras.swift (Mac).
// One session runs at a time. A running session is a `readingSession` record with no end, so it survives
// restarts and shows on the Mac too. Sessions under 30 seconds are thrown away.
import { useEffect, useState } from 'react'
import { store, useRecords, Rec } from './store'
import { Book, ReadingSession, sessionMinutes } from './models'
import { iso, parse, startOfDay, addDays, dayKey } from './dates'

let finished: Rec<ReadingSession> | null = null
const subs = new Set<() => void>()
const emit = () => subs.forEach((f) => f())

/** The running session, if any. */
export function activeSession(): Rec<ReadingSession> | undefined {
  return store.list<ReadingSession>('readingSession').find((s) => !s.data.end)
}

export function useActiveSession(): Rec<ReadingSession> | undefined {
  const all = useRecords<ReadingSession>('readingSession')
  return all.find((s) => !s.data.end)
}

export function startReading(book: Rec<Book>): void {
  const running = activeSession()
  if (running) stopReading(running)
  store.create<ReadingSession>('readingSession', { bookUUID: book.id, bookTitle: book.data.title, start: iso(new Date()), end: null, pagesRead: 0 })
  if (book.data.status !== 'reading') store.update<Book>(book.id, { status: 'reading', ...(book.data.startedAt ? {} : { startedAt: iso(new Date()) }) })
}

export function stopReading(session = activeSession()): void {
  if (!session) return
  const end = iso(new Date())
  store.update<ReadingSession>(session.id, { end })
  const s = { ...session, data: { ...session.data, end } }
  if (sessionMinutes(s.data) < 0.5) store.remove(session.id)
  else { finished = s; emit() }
}

/** The session that just stopped, so the window can ask what page you reached. */
export function useJustFinished(): [Rec<ReadingSession> | null, () => void] {
  const [, force] = useState(0)
  useEffect(() => { const f = () => force((n) => n + 1); subs.add(f); return () => { subs.delete(f) } }, [])
  return [finished, () => { finished = null; emit() }]
}

export function minutesSince(sessions: Rec<ReadingSession>[], since: Date): number {
  return Math.floor(sessions.filter((s) => (parse(s.data.start) ?? new Date(0)) >= since).reduce((n, s) => n + sessionMinutes(s.data), 0))
}

/** Consecutive days with at least one session, ending today or yesterday. */
export function readingStreak(sessions: Rec<ReadingSession>[]): number {
  const days = new Set(sessions.map((s) => parse(s.data.start)).filter((d): d is Date => !!d).map(dayKey))
  let day = startOfDay(new Date())
  if (!days.has(dayKey(day))) day = addDays(day, -1)
  let n = 0
  while (days.has(dayKey(day))) { n++; day = addDays(day, -1) }
  return n
}
