// Notes and journal, like NotesView.swift on the Mac, including the journal check-in with the assistant.
import { useEffect, useMemo, useRef, useState } from 'react'
import { Search, Pin, PinOff, Trash2, SquarePen, Sun, BookText, Sparkles, ArrowUp, Wand2, AlertTriangle, MessagesSquare } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Note, MOOD_FACES, MOOD_WORDS } from '@/lib/models'
import { iso, parse, isToday, relativeDay, fmtDay } from '@/lib/dates'
import { useKeys, useAssistantName } from '@/lib/ai'
import { decodeChat, startChat, sendMessage, reply, writeEntry, Turn } from './journalChat'

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
  // Body rewritten elsewhere (e.g. "Write my entry"): show it unless the user is mid-edit.
  useEffect(() => { if (!pendingPatch.current.body) setBody(note.data.body ?? '') }, [note.data.body])

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

      {note.data.isJournal && <CheckIn note={note} onBodyFlush={flush} />}
    </>
  )
}

// MARK: - Check-in with the assistant

function CheckIn({ note, onBodyFlush }: { note: Rec<Note>; onBodyFlush: () => void }) {
  const keys = useKeys()
  const assistant = useAssistantName()
  const chat = useMemo(() => decodeChat(note.data.chat), [note.data.chat])
  const allTurns = (chat?.turns ?? []).filter((t) => !t.hidden)
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [shown, setShown] = useState('')
  const [revealing, setRevealing] = useState(false)
  const [undoBody, setUndoBody] = useState<string | null>(null)
  const received = useRef('')
  const finished = useRef(true)
  const streamStart = useRef(Infinity)
  const bottom = useRef<HTMLDivElement>(null)
  const input = useRef<HTMLTextAreaElement>(null)
  const isTodayEntry = isToday(parse(note.data.createdAt) ?? new Date(0))

  // While a reply is still being revealed, its saved turn stays hidden behind the live bubble.
  const REF = 978307200
  const turns = revealing && allTurns.length && allTurns[allTurns.length - 1].role === 'assistant'
    && (allTurns[allTurns.length - 1].at + REF) * 1000 >= streamStart.current
    ? allTurns.slice(0, -1) : allTurns

  useEffect(() => { bottom.current?.scrollIntoView({ block: 'end' }) }, [turns.length, shown, busy])

  /** Runs a streaming request and reveals the reply gently, a few characters at a time. */
  const stream = (work: (onText: (t: string) => void) => Promise<void>) => {
    setBusy(true); setError(null); setShown(''); setRevealing(true)
    received.current = ''; finished.current = false; streamStart.current = Date.now() - 1000
    let local = ''
    ;(async () => {
      while (!finished.current || local.length < received.current.length) {
        if (local.length < received.current.length) {
          const next = received.current.slice(local.length, local.length + 3)
          local += next
          setShown(local)
          await new Promise((r) => setTimeout(r, /[.?!]/.test(next) ? 220 : 28))
        } else {
          await new Promise((r) => setTimeout(r, 40))
        }
      }
      setRevealing(false); setBusy(false)
      input.current?.focus()
    })()
    work((t) => { received.current = t })
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
      .finally(() => { finished.current = true })
  }

  const run = (work: () => Promise<void>) => {
    setBusy(true); setError(null)
    work().catch((e) => setError(e instanceof Error ? e.message : String(e))).finally(() => setBusy(false))
  }

  const send = () => {
    const text = draft.trim()
    if (!text || busy) return
    setDraft('')
    stream((onText) => sendMessage(note.id, text, assistant, onText))
  }

  return (
    <div className="col" style={{ width: 400, flex: 'none', borderLeft: '1px solid var(--line)', gap: 0, background: 'rgba(255,255,255,0.12)' }}>
      <div className="row" style={{ padding: 16, gap: 8 }}>
        <span style={{ width: 28, height: 28, borderRadius: '50%', background: 'var(--lime)', color: 'var(--sticker-ink)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
          <Sparkles size={14} />
        </span>
        <div>
          <div style={{ fontWeight: 600, fontSize: 14 }}>Check-in with {assistant}</div>
          <div className="muted" style={{ fontSize: 11 }}>Talk it through, then turn it into your entry</div>
        </div>
      </div>

      {!keys.anthropic ? (
        <div className="col secondary" style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, textAlign: 'center', fontSize: 13 }}>
          Add your Anthropic API key in Settings › AI, or unlock the keys synced from your Mac, to chat about your day.
        </div>
      ) : (
        <>
          <div className="scroll col" style={{ flex: 1, gap: 10, padding: '0 16px 12px' }}>
            {turns.length === 0 && !busy && (
              <div className="col" style={{ alignItems: 'center', gap: 14, paddingTop: 60, textAlign: 'center' }}>
                <div className="display" style={{ fontSize: 22 }}>{isTodayEntry ? 'How was today?' : 'Look back on this day'}</div>
                <div className="secondary" style={{ fontSize: 13 }}>{assistant} will ask about your mood and what you got up to, one question at a time.</div>
                <button className="btn-primary" style={{ width: 200 }} onClick={() => { onBodyFlush(); stream((onText) => startChat(note.id, assistant, onText)) }}>
                  <MessagesSquare size={14} /> Start check-in
                </button>
              </div>
            )}
            {turns.map((t) => <Bubble key={t.id} turn={t} />)}
            {revealing && shown ? <Bubble turn={{ id: 'live', role: 'assistant', text: shown, hidden: false, at: 0 }} />
              : busy ? <TypingDots /> : null}
            {error && (
              <div className="row" style={{ background: 'var(--canvas)', borderRadius: 10, padding: 10, gap: 6, fontSize: 12, alignItems: 'flex-start' }}>
                <AlertTriangle size={14} color="var(--orange)" style={{ flex: 'none', marginTop: 1 }} />
                <span style={{ flex: 1 }}>{error}</span>
                <button style={{ fontWeight: 600 }} onClick={() => stream((onText) => reply(note.id, onText))}>Retry</button>
              </div>
            )}
            <div ref={bottom} />
          </div>

          {allTurns.length > 0 && (
            <div className="row" style={{ justifyContent: 'center', gap: 8, paddingBottom: 8 }}>
              <button className="btn-soft" disabled={busy || !allTurns.some((t) => t.role === 'user')}
                onClick={() => { onBodyFlush(); run(async () => { const r = await writeEntry(note.id); setUndoBody(r.previous) }) }}>
                <Wand2 size={13} /> {note.data.body ? 'Update my entry' : 'Write my entry'}
              </button>
              {undoBody !== null && (
                <button className="link" style={{ fontWeight: 600 }} onClick={() => { store.update<Note>(note.id, { body: undoBody, updatedAt: iso(new Date()) }); setUndoBody(null) }}>Undo</button>
              )}
            </div>
          )}

          <div className="row" style={{ margin: '0 14px 14px', background: 'var(--canvas)', borderRadius: 16, padding: 10, gap: 8, alignItems: 'flex-end' }}>
            <textarea ref={input} className="plain" rows={1} placeholder="Reply…" value={draft} disabled={busy}
              style={{ resize: 'none', fontSize: 14, maxHeight: 120 }}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() } }} />
            <button onClick={send} disabled={busy || !draft.trim()}
              style={{ width: 30, height: 30, borderRadius: '50%', background: 'var(--inverse)', color: 'var(--on-inverse)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
              <ArrowUp size={14} strokeWidth={3} />
            </button>
          </div>
        </>
      )}
    </div>
  )
}

/** The assistant separates thoughts with a blank line; each becomes its own soft bubble. */
function Bubble({ turn }: { turn: Turn }) {
  const mine = turn.role === 'user'
  const parts = mine ? [turn.text] : turn.text.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean)
  return (
    <div className="col" style={{ gap: 6, alignItems: mine ? 'flex-end' : 'flex-start' }}>
      {parts.map((p, i) => (
        <div key={i} style={{ maxWidth: '85%', padding: '10px 14px', borderRadius: 18, fontSize: 14, lineHeight: 1.45, whiteSpace: 'pre-wrap', userSelect: 'text',
          background: mine ? 'var(--inverse)' : 'var(--canvas)', color: mine ? 'var(--on-inverse)' : 'var(--ink)' }}>
          {p}
        </div>
      ))}
    </div>
  )
}

function TypingDots() {
  return (
    <div className="row" style={{ gap: 5, background: 'var(--canvas)', borderRadius: 18, padding: '12px 14px', alignSelf: 'flex-start' }}>
      {[0, 1, 2].map((i) => (
        <span key={i} style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--ink3)', animation: `orbitDot 1.2s ${i * 0.2}s infinite ease-in-out` }} />
      ))}
      <style>{'@keyframes orbitDot { 0%, 100% { opacity: 0.3 } 50% { opacity: 1 } }'}</style>
    </div>
  )
}
