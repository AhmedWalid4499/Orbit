// Search everything, as on the Mac and iPhone (SearchView.swift): tasks, events, notes, money and books. A tall sheet
// with the field on top and results under a divider; tapping a result (or Enter for the first) opens its section.
import { useEffect, useRef, useState } from 'react'
import { Search as SearchIcon, CheckCircle2, Calendar, FileText, CreditCard, BookOpen, HelpCircle } from 'lucide-react'
import { useRecords } from '@/lib/store'
import { Task, CalEvent, Note, Txn, Book, READING_STATUS, cap } from '@/lib/models'
import { parse } from '@/lib/dates'
import { useMoney } from '@/components/ui'
import '../onboarding.css'

type Dest = 'tasks' | 'calendar' | 'notes' | 'money' | 'reading'

export default function SearchSheet({ open, onClose, onGo }: { open: boolean; onClose: () => void; onGo: (d: Dest) => void }) {
  const [query, setQuery] = useState('')
  const field = useRef<HTMLInputElement>(null)
  const tasks = useRecords<Task>('task'), events = useRecords<CalEvent>('event'), notes = useRecords<Note>('note')
  const txns = useRecords<Txn>('transaction'), books = useRecords<Book>('book')
  const money = useMoney()

  useEffect(() => {
    if (!open) { setQuery(''); return }
    const t = setTimeout(() => field.current?.focus(), 200)
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => { clearTimeout(t); window.removeEventListener('keydown', onKey) }
  }, [open])
  if (!open) return null

  const q = query.trim().toLowerCase()
  const m = (s?: string) => !!s && s.toLowerCase().includes(q)
  const day = (s: string) => parse(s)?.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) ?? ''
  const dayTime = (s: string) => { const d = parse(s); return d ? `${day(s)} at ${d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}` : '' }
  const hits = q.length < 2 ? [] : [
    ...tasks.filter((t) => m(t.data.title)).slice(0, 8).map((t) => ({ id: t.id, title: t.data.title, detail: t.data.isDone ? 'Completed task' : `Task · ${cap(t.data.area)}`, icon: <CheckCircle2 size={17} />, to: 'tasks' as Dest })),
    ...events.filter((e) => m(e.data.title)).slice(0, 6).map((e) => ({ id: e.id, title: e.data.title, detail: `Event · ${dayTime(e.data.start)}`, icon: <Calendar size={17} />, to: 'calendar' as Dest })),
    ...notes.filter((n) => m(n.data.title) || m(n.data.body)).slice(0, 6).map((n) => ({ id: n.id, title: n.data.title || 'Untitled', detail: n.data.isJournal ? 'Journal' : 'Note', icon: <FileText size={17} />, to: 'notes' as Dest })),
    ...txns.filter((t) => m(t.data.title)).slice(0, 6).map((t) => ({ id: t.id, title: t.data.title, detail: `${money(t.data.amount, true)} · ${day(t.data.date)}`, icon: <CreditCard size={17} />, to: 'money' as Dest })),
    ...books.filter((b) => m(b.data.title) || m(b.data.author)).slice(0, 6).map((b) => ({ id: b.id, title: b.data.title,
      detail: `Book · ${b.data.author} · ${READING_STATUS.find((s) => s.id === b.data.status)?.title ?? ''}`, icon: <BookOpen size={17} />, to: 'reading' as Dest })),
  ]
  const go = (d: Dest) => { onGo(d); setQuery(''); onClose() }

  return (
    <div className="backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div className="modal po-sheet po-search" role="dialog" aria-label="Search">
        <span className="po-sheet-grip" />
        <div className="po-search-bar">
          <SearchIcon size={18} style={{ color: 'var(--ink3)', flex: 'none' }} />
          <input ref={field} type="text" enterKeyHint="search" placeholder="Search tasks, events, notes, money…" value={query}
            onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && hits[0]) go(hits[0].to) }} />
        </div>
        <div className="po-search-list">
          {q.length >= 2 && hits.length === 0 && <div className="po-empty"><HelpCircle size={20} />No matches</div>}
          {hits.map((h) => (
            <button key={h.id} className="po-hit" onClick={() => go(h.to)}>
              {h.icon}
              <span style={{ minWidth: 0, flex: 1 }}><b>{h.title}</b><small>{h.detail}</small></span>
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}
