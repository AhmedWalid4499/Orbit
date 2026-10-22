// Top-bar pill while a reading session runs, and the "what page are you on?" sheet after it stops.
// Mirrors ReadingTimerPill and FinishedReadingSheet in ReadingExtras.swift (Mac).
import { useEffect, useState } from 'react'
import { BookOpen, Square } from 'lucide-react'
import { store } from '@/lib/store'
import { Book, ReadingSession, sessionMinutes } from '@/lib/models'
import { iso, parse } from '@/lib/dates'
import { useActiveSession, stopReading, useJustFinished } from '@/lib/readingTimer'
import { Modal } from './ui'

export function ReadingTimerPill({ onOpen }: { onOpen: () => void }) {
  const s = useActiveSession()
  const [, tick] = useState(0)
  useEffect(() => {
    if (!s) return
    const t = setInterval(() => tick((n) => n + 1), 1000)
    return () => clearInterval(t)
  }, [s?.id])
  if (!s) return null
  const secs = Math.max(0, Math.floor((Date.now() - (parse(s.data.start)?.getTime() ?? Date.now())) / 1000))
  return (
    <div className="timer-pill no-drag" onClick={onOpen} title={`Reading ${s.data.bookTitle}`}>
      <BookOpen size={14} />
      <span style={{ fontVariantNumeric: 'tabular-nums' }}>{Math.floor(secs / 60)}:{String(secs % 60).padStart(2, '0')}</span>
      <span className="clamp1 timer-title">{s.data.bookTitle}</span>
      <button title="Stop reading" onClick={(e) => { e.stopPropagation(); stopReading(s) }}><Square size={11} fill="currentColor" /></button>
    </div>
  )
}

export function FinishedReading() {
  const [session, clear] = useJustFinished()
  const [page, setPage] = useState('')
  if (!session) return null
  const book = store.get<Book>(session.data.bookUUID)
  const close = () => { setPage(''); clear() }
  const save = () => {
    const p = parseInt(page, 10)
    if (book && p > 0) {
      const b = book.data
      const before = b.pageCount > 0 ? Math.floor(b.progress * b.pageCount) : 0
      store.update<ReadingSession>(session.id, { pagesRead: Math.max(0, p - before) })
      if (b.pageCount > 0) {
        const progress = Math.min(1, p / b.pageCount)
        const patch: Partial<Book> = { progress }
        if (progress >= 1) { patch.status = 'read'; if (!b.finishedAt) patch.finishedAt = iso(new Date()) }
        store.update<Book>(book.id, patch)
      }
    }
    close()
  }
  return (
    <Modal open onClose={close} width={400}>
      <div className="col" style={{ gap: 16 }}>
        <h2 className="display" style={{ fontSize: 26, margin: 0 }}>Nice reading! 📖</h2>
        <div className="secondary">{Math.round(sessionMinutes(session.data))} minutes with {session.data.bookTitle}.</div>
        {book && (
          <label className="row">
            <span style={{ fontSize: 13 }}>What page are you on?</span>
            <input className="field" autoFocus type="number" min={0} style={{ width: 110 }} value={page}
              placeholder={book.data.pageCount > 0 ? `of ${book.data.pageCount}` : 'page'}
              onChange={(e) => setPage(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && save()} />
          </label>
        )}
        <div className="row">
          <button className="btn-soft" onClick={close}>Skip</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 110 }} onClick={save}>Save</button>
        </div>
      </div>
    </Modal>
  )
}
