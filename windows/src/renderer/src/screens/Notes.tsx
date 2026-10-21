// Notes and journal, like NotesView.swift on the Mac. The journal chat with the assistant is shown read-only.
import { useEffect, useMemo, useRef, useState } from 'react'
import { Search, Pin, PinOff, Trash2, SquarePen, Sun, BookText } from 'lucide-react'
import { store, useRecords, useSetting, Rec } from '@/lib/store'
import { Note, MOOD_FACES, MOOD_WORDS } from '@/lib/models'
import { iso, parse, isToday, relativeDay, fmtDay } from '@/lib/dates'

type Chat = { system?: string; turns?: { role: string; text: string; hidden?: boolean }[] }

function decodeChat(b64: string | null | undefined): Chat | null {
  if (!b64) return null
  try {
    const bin = atob(b64)
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0))
    return JSON.parse(new TextDecoder().decode(bytes))
  } catch {
    return null
  }
}

function newNote(journal: boolean): string {
  const now = new Date()
  return store.create<Note>('note', {
    title: journal ? fmtDay(now, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) : '',
    body: '', createdAt: iso(now), updatedAt: iso(now), isJournal: journal, pinned: false, mood: 0, moodSetByUser: false,
  })
}

export default function Notes({ openJournalRequest }: { openJournalRequest: number }) {
  const notes = useRecords<Note>('note')
  const [journal, setJournal] = useState(false)
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState<string | null>(null)

  const todaysJournal = () => notes.find((n) => n.data.isJournal && isToday(parse(n.data.createdAt) ?? new Date(0)))

  useEffect(() => {
    if (openJournalRequest <= 0) return
    setJournal(true)
    const existing = notes.find((n) => n.data.isJournal && isToday(parse(n.data.createdAt) ?? new Date(0)))
    setSelected(existing ? existing.id : newNote(true))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [openJournalRequest])

  const visible = useMemo(() => {
    const q = query.toLowerCase()
    const time = (n: Rec<Note>) => (parse(journal ? n.data.createdAt : n.data.updatedAt)?.getTime() ?? 0)
    return notes
      .filter((n) => !!n.data.isJournal === journal)
      .filter((n) => !q || (n.data.title ?? '').toLowerCase().includes(q) || (n.data.body ?? '').toLowerCase().includes(q))
      .sort((a, b) => Number(!!b.data.pinned) - Number(!!a.data.pinned) || time(b) - time(a))
  }, [notes, journal, query])

  // Keep something selected when the list changes.
  useEffect(() => {
    if (selected && store.get(selected)) return
    setSelected(visible[0]?.id ?? null)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible.length, journal])

  const current = selected ? notes.find((n) => n.id === selected) : undefined

  const create = () => {
    if (journal) {
      const t = todaysJournal()
      setSelected(t ? t.id : newNote(true))
    } else {
      setSelected(newNote(false))
    }
  }

  return (
    <div style={{ height: '100%', display: 'flex', gap: 28, padding: '6px 32px 28px' }}>
      <div className="col" style={{ width: 300, flex: 'none', gap: 14 }}>
        <div className="row" style={{ gap: 8 }}>
          {[false, true].map((j) => (
            <button key={String(j)} onClick={() => { setJournal(j); setSelected(null) }}
              style={{ flex: 1, padding: '9px 0', borderRadius: 999, fontWeight: 500, fontSize: 14,
                background: journal === j ? 'var(--inverse)' : 'var(--card)', color: journal === j ? 'var(--on-inverse)' : 'var(--ink)' }}>
              {j ? 'Journal' : 'Notes'}
            </button>
          ))}
        </div>
        <div className="row" style={{ background: 'var(--card)', borderRadius: 12, padding: '0 10px' }}>
          <Search size={14} className="muted" />
          <input className="plain" style={{ padding: '10px 0' }} placeholder="Search" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        <button className="btn-primary" onClick={create}>
          {journal ? <Sun size={14} /> : <SquarePen size={14} />}
          {journal ? "Today's entry" : 'New note'}
        </button>
        <div className="scroll col" style={{ gap: 6, flex: 1 }}>
          {visible.map((n) => {
            const on = n.id === selected
            const date = parse(journal ? n.data.createdAt : n.data.updatedAt)
            return (
              <button key={n.id} onClick={() => setSelected(n.id)}
                style={{ textAlign: 'left', padding: 12, borderRadius: 14, background: on ? 'var(--inverse)' : 'var(--card)', color: on ? 'var(--on-inverse)' : 'var(--ink)' }}>
                <div className="row" style={{ gap: 6 }}>
                  <span className="clamp1" style={{ fontWeight: 600, fontSize: 14, flex: 1 }}>{n.data.title || 'Untitled'}</span>
                  {n.data.pinned && <Pin size={11} />}
                  {n.data.isJournal && n.data.mood > 0 && <span>{MOOD_FACES[n.data.mood]}</span>}
                </div>
                <div className="clamp2" style={{ fontSize: 12, opacity: 0.7, marginTop: 4 }}>{n.data.body || 'No content'}</div>
                {date && <div style={{ fontSize: 11, opacity: 0.5, marginTop: 4 }}>{relativeDay(date)}</div>}
              </button>
            )
          })}
          {visible.length === 0 && <div className="muted" style={{ fontSize: 13, padding: 8 }}>{query ? 'No matches.' : journal ? 'No journal entries yet.' : 'No notes yet.'}</div>}
        </div>
      </div>

      <div style={{ flex: 1, minWidth: 0, borderRadius: 24, background: journal ? 'var(--blush)' : 'var(--card)', display: 'flex', overflow: 'hidden' }}>
        {current
          ? <Editor key={current.id} note={current} onDelete={() => { store.remove(current.id); setSelected(null) }} />
          : (
            <div className="col muted" style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
              <BookText size={40} strokeWidth={1.2} />
              <div className="display" style={{ fontWeight: 500, fontSize: 20 }}>Pick a note or start a new one</div>
            </div>
          )}
      </div>
    </div>
  )
}

function Editor({ note, onDelete }: { note: Rec<Note>; onDelete: () => void }) {
  const [title, setTitle] = useState(note.data.title ?? '')
  const [body, setBody] = useState(note.data.body ?? '')
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const pendingPatch = useRef<Partial<Note>>({})
  const assistant = useSetting<string>('assistantName', 'Ask') || 'Ask'
  const chat = useMemo(() => decodeChat(note.data.chat), [note.data.chat])
  const turns = (chat?.turns ?? []).filter((t) => !t.hidden)

  const flush = () => {
    if (timer.current) clearTimeout(timer.current)
    timer.current = null
    if (Object.keys(pendingPatch.current).length) {
      store.update<Note>(note.id, { ...pendingPatch.current, updatedAt: iso(new Date()) })
      pendingPatch.current = {}
    }
  }
  const edit = (patch: Partial<Note>) => {
    pendingPatch.current = { ...pendingPatch.current, ...patch }
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(flush, 400)
  }
  useEffect(() => () => flush(), []) // save on switching notes

  const setMood = (m: number) => {
    const mood = note.data.mood === m ? 0 : m
    store.update<Note>(note.id, { mood, moodSetByUser: mood !== 0 })
  }

  const edited = parse(note.data.updatedAt)

  return (
    <>
      <div className="col" style={{ flex: 1, minWidth: 0, padding: 32, gap: 14 }}>
        <div className="row">
          <span className="muted" style={{ fontSize: 12 }}>
            {note.data.isJournal ? 'Journal' : edited ? `Edited ${relativeDay(edited).toLowerCase()}` : ''}
          </span>
          <span className="spacer" />
          <button title={note.data.pinned ? 'Unpin' : 'Pin'} onClick={() => store.update<Note>(note.id, { pinned: !note.data.pinned })}>
            {note.data.pinned ? <PinOff size={15} /> : <Pin size={15} />}
          </button>
          <button title="Delete" onClick={onDelete}><Trash2 size={15} /></button>
        </div>
        <textarea className="plain display" rows={1} placeholder="Title" value={title}
          style={{ fontSize: 30, resize: 'none', lineHeight: 1.2 }}
          onChange={(e) => { setTitle(e.target.value); edit({ title: e.target.value }) }} />
        {note.data.isJournal && (
          <div className="row" style={{ gap: 6 }}>
            <span className="secondary" style={{ fontSize: 12, fontWeight: 600, marginRight: 4 }}>Mood</span>
            {[1, 2, 3, 4, 5].map((m) => (
              <button key={m} title={MOOD_WORDS[m]} onClick={() => setMood(m)}
                style={{ width: 38, height: 38, borderRadius: '50%', fontSize: 20,
                  background: note.data.mood === m ? 'var(--lime)' : 'rgba(255,255,255,0.4)',
                  opacity: !note.data.mood || note.data.mood === m ? 1 : 0.45 }}>
                {MOOD_FACES[m]}
              </button>
            ))}
            {note.data.mood > 0 && <span className="secondary" style={{ fontSize: 12, fontWeight: 500, marginLeft: 4 }}>{MOOD_WORDS[note.data.mood]}</span>}
          </div>
        )}
        <textarea className="plain" placeholder={note.data.isJournal ? 'How did today go? Write freely.' : 'Start writing…'}
          value={body} style={{ flex: 1, fontFamily: 'var(--display)', fontSize: 17, lineHeight: 1.6, resize: 'none' }}
          onChange={(e) => { setBody(e.target.value); edit({ body: e.target.value }) }} />
      </div>

      {note.data.isJournal && turns.length > 0 && (
        <div className="col" style={{ width: 360, flex: 'none', borderLeft: '1px solid var(--line)', padding: 16, gap: 10 }}>
          <div>
            <div style={{ fontWeight: 600, fontSize: 14 }}>Check-in with {assistant}</div>
            <div className="muted" style={{ fontSize: 11 }}>Chatting with {assistant} is on the Mac for now</div>
          </div>
          <div className="scroll col" style={{ gap: 8, flex: 1 }}>
            {turns.map((t, i) => {
              const mine = t.role === 'user'
              return (
                <div key={i} style={{ display: 'flex', justifyContent: mine ? 'flex-end' : 'flex-start' }}>
                  <div style={{ maxWidth: '85%', padding: '10px 14px', borderRadius: 18, fontSize: 14, whiteSpace: 'pre-wrap', userSelect: 'text',
                    background: mine ? 'var(--inverse)' : 'var(--canvas)', color: mine ? 'var(--on-inverse)' : 'var(--ink)' }}>
                    {t.text}
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}
    </>
  )
}
