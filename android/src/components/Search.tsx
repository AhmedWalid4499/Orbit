// Search everything, like the Mac's SearchView: tasks, events, notes, money and books. Tapping a result opens its section.
import { useState } from 'react'
import { Search as SearchIcon, CheckCircle2, Calendar, FileText, CreditCard, BookOpen } from 'lucide-react'
import { useRecords } from '@/lib/store'
import { Task, CalEvent, Note, Txn, Book, READING_STATUS, cap } from '@/lib/models'
import { parse } from '@/lib/dates'
import { Modal, EmptyHint, useMoney } from '@/components/ui'

type Dest = 'tasks' | 'calendar' | 'notes' | 'money' | 'reading'

export default function SearchSheet({ open, onClose, onGo }: { open: boolean; onClose: () => void; onGo: (d: Dest) => void }) {
  const [query, setQuery] = useState('')
  const tasks = useRecords<Task>('task'), events = useRecords<CalEvent>('event'), notes = useRecords<Note>('note')
  const txns = useRecords<Txn>('transaction'), books = useRecords<Book>('book')
  const money = useMoney()
  const m = (s?: string) => !!s && s.toLowerCase().includes(query.trim().toLowerCase())
  const day = (s: string, time = false) => parse(s)?.toLocaleDateString(undefined, { day: 'numeric', month: 'short', ...(time ? { hour: 'numeric', minute: '2-digit' } : {}) }) ?? ''
  const hits = query.trim().length < 2 ? [] : [
    ...tasks.filter((t) => m(t.data.title)).slice(0, 8).map((t) => ({ id: t.id, title: t.data.title, detail: t.data.isDone ? 'Completed task' : `Task · ${cap(t.data.area)}`, icon: <CheckCircle2 size={17} />, to: 'tasks' as Dest })),
    ...events.filter((e) => m(e.data.title)).slice(0, 6).map((e) => ({ id: e.id, title: e.data.title, detail: `Event · ${day(e.data.start, true)}`, icon: <Calendar size={17} />, to: 'calendar' as Dest })),
    ...notes.filter((n) => m(n.data.title) || m(n.data.body)).slice(0, 6).map((n) => ({ id: n.id, title: n.data.title || 'Untitled', detail: n.data.isJournal ? 'Journal' : 'Note', icon: <FileText size={17} />, to: 'notes' as Dest })),
    ...txns.filter((t) => m(t.data.title)).slice(0, 6).map((t) => ({ id: t.id, title: t.data.title, detail: `${money(t.data.amount, true)} · ${day(t.data.date)}`, icon: <CreditCard size={17} />, to: 'money' as Dest })),
    ...books.filter((b) => m(b.data.title) || m(b.data.author)).slice(0, 6).map((b) => ({ id: b.id, title: b.data.title,
      detail: `Book · ${b.data.author} · ${READING_STATUS.find((s) => s.id === b.data.status)?.title ?? ''}`, icon: <BookOpen size={17} />, to: 'reading' as Dest })),
  ]
  const go = (d: Dest) => { onGo(d); setQuery(''); onClose() }
  return (
    <Modal open={open} onClose={onClose}>
      <div className="row" style={{ gap: 10, marginBottom: 12, marginRight: 40 }}>
        <SearchIcon size={18} className="muted" />
        <input autoFocus className="plain" style={{ fontSize: 18 }} placeholder="Search tasks, events, notes, money…" value={query}
          onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && hits[0]) go(hits[0].to) }} />
      </div>
      <div className="col" style={{ gap: 2, minHeight: 200 }}>
        {query.trim().length >= 2 && hits.length === 0 && <EmptyHint text="No matches" />}
        {hits.map((h) => (
          <button key={h.id} className="list-row" style={{ minHeight: 52 }} onClick={() => go(h.to)}>
            {h.icon}
            <span className="col" style={{ gap: 1, minWidth: 0 }}>
              <span className="clamp1" style={{ fontWeight: 500 }}>{h.title}</span>
              <span className="muted clamp1" style={{ fontSize: 12 }}>{h.detail}</span>
            </span>
          </button>
        ))}
      </div>
    </Modal>
  )
}
