// Journal & Notes on the phone: PhoneNotes in iOS/OrbitPhone/PhoneSections.swift, with NoteRow, NoteEditor and
// JournalEditor from NotesView.swift (the journal's Talk / Write switch and the check-in chat from
// JournalCompanion.swift, through the shared journalChat.ts so a chat started on one device continues on another)
// and the Google Keep import from KeepImport.swift.
import { useEffect, useMemo, useRef, useState } from 'react'
import { Search, Sun, SquarePen, BookText, Pin, Trash2, ArrowUp, TriangleAlert, WandSparkles, MessagesSquare } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Note, MOOD_FACES, MOOD_WORDS } from '@/lib/models'
import { iso, parse, isToday, relativeDay, relativeTime } from '@/lib/dates'
import { useKeys, useAssistantName, structured } from '@/lib/ai'
import { decodeChat, startChat, sendMessage, reply, Turn } from '@/screens/journalChat'
import { Modal } from '@/components/ui'
import { Orb } from '../components/Orb'
import { SectionTitle, PushPage } from './pm2Kit'
import './pm2.css'

const time = (s: string | null | undefined) => parse(s)?.getTime() ?? 0

/** A new note, with every field the Mac encodes. */
function makeNote(journal: boolean): string {
  const now = new Date()
  return store.create<Note>('note', {
    title: journal ? now.toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }) : '',
    body: '', createdAt: iso(now), updatedAt: iso(now), isJournal: journal, pinned: false, mood: 0, moodSetByUser: false, chat: null,
  })
}

/** The request to open today's journal (Today's mood card, the check-in) that this screen has already handled. */
let handledJournalRequest = 0

export default function PhoneNotes({ openJournalRequest = 0 }: { openJournalRequest?: number }) {
  const notes = useRecords<Note>('note')
  const [showJournal, setShowJournal] = useState(false)
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState<string | null>(null)

  const q = query.trim().toLowerCase()
  const visible = notes.filter((n) => !!n.data.isJournal === showJournal)
    .filter((n) => !q || (n.data.title ?? '').toLowerCase().includes(q) || (n.data.body ?? '').toLowerCase().includes(q))
    .sort((a, b) => {
      const pa = a.data.pinned ? 1 : 0, pb = b.data.pinned ? 1 : 0
      if (pa !== pb) return pb - pa
      return showJournal ? time(b.data.createdAt) - time(a.data.createdAt) : time(b.data.updatedAt) - time(a.data.updatedAt)
    })

  const newNote = (journal = showJournal) => {
    if (journal) {
      const existing = store.list<Note>('note').find((n) => n.data.isJournal && isToday(parse(n.data.createdAt) ?? new Date(0)))
      if (existing) { setOpen(existing.id); return }
    }
    setOpen(makeNote(journal))
  }

  useEffect(() => {
    if (openJournalRequest > 0 && openJournalRequest !== handledJournalRequest) {
      handledJournalRequest = openJournalRequest
      setShowJournal(true)
      newNote(true)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [openJournalRequest])

  const openRec = open ? notes.find((n) => n.id === open) : undefined
  const remove = (id: string) => { store.remove(id); if (open === id) setOpen(null) }

  return (
    <div className="pm2" style={{ gap: 14 }}>
      <SectionTitle>Journal &amp; Notes</SectionTitle>
      <label className="pm2-search">
        <Search size={17} color="var(--ink3)" />
        <input className="pm2-plain" placeholder="Search" value={query} onChange={(e) => setQuery(e.target.value)} enterKeyHint="search" />
      </label>
      <div className="pm2-seg">
        <button className={!showJournal ? 'on' : ''} onClick={() => setShowJournal(false)}>Notes</button>
        <button className={showJournal ? 'on' : ''} onClick={() => setShowJournal(true)}>Journal</button>
      </div>
      <button className="pm2-primary" onClick={() => newNote()}>
        {showJournal ? <Sun size={16} /> : <SquarePen size={16} />}{showJournal ? "Today's entry" : 'New note'}
      </button>
      {!showJournal && <KeepImportButton />}

      {visible.map((n) => (
        <SwipeToDelete key={n.id} onDelete={() => remove(n.id)}>
          <NoteRow note={n.data} onClick={() => setOpen(n.id)} />
        </SwipeToDelete>
      ))}
      {visible.length === 0 && <div className="pm2-empty"><BookText size={15} />{showJournal ? 'No journal entries yet.' : 'No notes yet.'}</div>}

      {openRec && (
        <PushPage onBack={() => setOpen(null)} className={openRec.data.isJournal ? 'pm2-journal' : ''}>
          {openRec.data.isJournal
            ? <JournalEditor key={openRec.id} note={openRec} onDelete={() => remove(openRec.id)} />
            : <NoteEditor key={openRec.id} note={openRec} onDelete={() => remove(openRec.id)} />}
        </PushPage>
      )}
    </div>
  )
}

/** NoteRow in NotesView.swift. */
function NoteRow({ note, onClick }: { note: Note; onClick: () => void }) {
  const when = parse(note.isJournal ? note.createdAt : note.updatedAt) ?? new Date()
  return (
    <button className="pm2-note" onClick={onClick}>
      <span className="pm2-row" style={{ width: '100%' }}>
        <span className="t clamp1" style={{ flex: 1 }}>{note.title || 'Untitled'}</span>
        {note.pinned && <Pin size={11} fill="currentColor" />}
        {note.isJournal && note.mood > 0 && <span>{MOOD_FACES[note.mood]}</span>}
      </span>
      <span className="b clamp2">{note.body || 'No content'}</span>
      <span className="d">{relativeDay(when)}</span>
    </button>
  )
}

/** The iPhone list's swipe to delete. */
function SwipeToDelete({ onDelete, children }: { onDelete: () => void; children: React.ReactNode }) {
  const [dx, setDx] = useState(0)
  const start = useRef<{ x: number; y: number; base: number; horizontal: boolean | null } | null>(null)
  return (
    <div className="pm2-swipe">
      {dx < 0 && <button className="del" onClick={onDelete}><Trash2 size={17} />Delete</button>}
      <div className="front" style={{ transform: `translateX(${dx}px)`, transition: start.current ? 'none' : undefined }}
        onTouchStart={(e) => { start.current = { x: e.touches[0].clientX, y: e.touches[0].clientY, base: dx, horizontal: null } }}
        onTouchMove={(e) => {
          const s = start.current
          if (!s) return
          const mx = e.touches[0].clientX - s.x, my = e.touches[0].clientY - s.y
          if (s.horizontal === null && Math.hypot(mx, my) > 8) s.horizontal = Math.abs(mx) > Math.abs(my)
          if (s.horizontal) setDx(Math.min(0, Math.max(-120, s.base + mx)))
        }}
        onTouchEnd={() => {
          const s = start.current
          start.current = null
          if (dx < -200) onDelete()
          else setDx(s?.horizontal ? (dx < -44 ? -88 : 0) : s && s.base < 0 ? 0 : dx)
        }}
        onClickCapture={(e) => { if (dx < 0) { e.stopPropagation(); setDx(0) } }}>
        {children}
      </div>
    </div>
  )
}

/** NoteEditor: when it was edited, pin, delete, then the title and the text. */
function NoteEditor({ note, onDelete }: { note: Rec<Note>; onDelete: () => void }) {
  const n = note.data
  const set = (p: Partial<Note>) => store.update<Note>(note.id, { ...p, updatedAt: iso(new Date()) })
  return (
    <div className="pm2-editor" style={{ padding: '16px 48px 32px' }}>
      <div className="meta">
        <span>{n.isJournal ? 'Journal' : `Edited ${relativeTime(parse(n.updatedAt) ?? new Date())}`}</span>
        <span className="pm2-spacer" />
        <button aria-label="Pin" onClick={() => store.update<Note>(note.id, { pinned: !n.pinned })}>{n.pinned ? <Pin size={17} fill="currentColor" /> : <Pin size={17} />}</button>
        <button aria-label="Delete" onClick={onDelete}><Trash2 size={17} /></button>
      </div>
      <AutoText className="pm2-plain title" placeholder="Title" value={n.title} onChange={(v) => set({ title: v })} />
      <textarea className="pm2-plain body" value={n.body} onChange={(e) => set({ body: e.target.value })} />
    </div>
  )
}

/** A text field that grows with its text (TextField(axis: .vertical)). */
function AutoText({ value, onChange, className, placeholder }: { value: string; onChange: (v: string) => void; className?: string; placeholder?: string }) {
  const ref = useRef<HTMLTextAreaElement>(null)
  useEffect(() => { const t = ref.current; if (t) { t.style.height = 'auto'; t.style.height = `${t.scrollHeight}px` } }, [value])
  return <textarea ref={ref} rows={1} className={className} placeholder={placeholder} value={value} onChange={(e) => onChange(e.target.value.replace(/\n/g, ' '))} />
}

// MARK: - Journal with the check-in

const REF = 978307200 // Swift's reference date, in Unix seconds

/** JournalCompanion.writeEntry on the Mac: one entry from what's written plus the chat and the day, replacing the body. */
async function writeEntry(noteID: string): Promise<string> {
  const rec = store.get<Note>(noteID)
  const chat = decodeChat(rec?.data.chat)
  if (!rec || !chat) return rec?.data.body ?? ''
  const transcript = chat.turns.filter((t) => !t.hidden).map((t) => `${t.role === 'user' ? 'Me' : 'Companion'}: ${t.text}`).join('\n')
  const system = `You turn a journaling chat into a real journal entry, written in the first person as the user ("Me"). Don't transcribe the chat or paste their messages back: write it up the way a thoughtful person would in their own diary.
You get what they've already written (may be empty), the conversation with their companion, and what the app knows about their day (calendar, tasks done, habits, spending).
- Open with a short, vivid paragraph about the day: what happened and how it felt, in flowing sentences, connecting what they said with what the day's data shows (the meeting they had, the workout they did, tasks they finished). Keep their own good phrases.
- Then a paragraph that reflects: what stood out, what it meant to them, anything they learned or are wrestling with, based on what they said.
- Then short notes, each on its own line starting with "• ", under these plain labels on their own line (skip any that would be empty):
  Highlights
  On my mind
  Tomorrow
- Facts and feelings must come from their words or the day's data; never invent events, people or emotions. Don't mention the app or the companion.
- Plain text: no markdown symbols, no date line. Fix typos.
mood: 1 (rough) to 5 (great) from what they said, or 0 if unclear.`
  const day = (chat.system.split("Today's data from the app:")[1] ?? '').trim()
  const input = `ALREADY WRITTEN:\n${rec.data.body ? rec.data.body : '(nothing yet)'}\n\nCONVERSATION:\n${transcript}\n\nTHE DAY IN THE APP:\n${day || '(none)'}`
  const result = await structured<{ entry: string; mood: number }>(system, input, {
    type: 'object', properties: { entry: { type: 'string' }, mood: { type: 'integer' } }, required: ['entry', 'mood'], additionalProperties: false,
  }, 'medium')
  const previous = rec.data.body ?? ''
  const after = store.get<Note>(noteID)
  const patch: Partial<Note> = { body: result.entry, updatedAt: iso(new Date()) }
  if (result.mood >= 1 && result.mood <= 5 && !after?.data.moodSetByUser) patch.mood = result.mood
  store.update<Note>(noteID, patch)
  return previous
}

/** JournalEditor on the iPhone: Talk (the check-in) or Write (the entry itself). */
function JournalEditor({ note, onDelete }: { note: Rec<Note>; onDelete: () => void }) {
  const [talking, setTalking] = useState(true)
  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
      <div className="pm2-seg" style={{ margin: '8px 16px' }}>
        <button className={talking ? 'on' : ''} onClick={() => setTalking(true)}>Talk</button>
        <button className={!talking ? 'on' : ''} onClick={() => setTalking(false)}>Write</button>
      </div>
      {talking ? <CheckIn note={note} /> : <Writing note={note} onDelete={onDelete} />}
    </div>
  )
}

function Writing({ note, onDelete }: { note: Rec<Note>; onDelete: () => void }) {
  const n = note.data
  const assistant = useAssistantName()
  return (
    <div className="pm2-editor">
      <div className="meta">
        <span>Journal</span><span className="pm2-spacer" />
        <button aria-label="Delete entry" onClick={onDelete}><Trash2 size={17} /></button>
      </div>
      <AutoText className="pm2-plain title" placeholder="Title" value={n.title} onChange={(v) => store.update<Note>(note.id, { title: v })} />
      <div className="pm2-moods">
        <span className="pm2-secondary" style={{ fontSize: 12, fontWeight: 600, marginRight: 4 }}>Mood</span>
        {[1, 2, 3, 4, 5].map((m) => (
          <button key={m} className={n.mood === m ? 'on' : ''} title={MOOD_WORDS[m]} style={{ opacity: !n.mood || n.mood === m ? 1 : 0.45 }}
            onClick={() => { const v = n.mood === m ? 0 : m; store.update<Note>(note.id, { mood: v, moodSetByUser: v !== 0 }) }}>{MOOD_FACES[m]}</button>
        ))}
        {n.mood > 0 && <span className="pm2-secondary" style={{ fontSize: 12, fontWeight: 500, marginLeft: 4 }}>{MOOD_WORDS[n.mood]}</span>}
      </div>
      <textarea className="pm2-plain body" value={n.body}
        placeholder={`Write freely, or chat with ${assistant} on the right and let it write the entry for you.`}
        onChange={(e) => store.update<Note>(note.id, { body: e.target.value, updatedAt: iso(new Date()) })} />
    </div>
  )
}

function CheckIn({ note }: { note: Rec<Note> }) {
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
  const last = allTurns[allTurns.length - 1]
  const turns = revealing && last?.role === 'assistant' && (last.at + REF) * 1000 >= streamStart.current ? allTurns.slice(0, -1) : allTurns

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

  const send = () => {
    const text = draft.trim()
    if (!text || busy) return
    setDraft('')
    stream((onText) => sendMessage(note.id, text, assistant, onText))
  }

  const write = () => {
    setBusy(true); setError(null)
    writeEntry(note.id).then((prev) => setUndoBody(prev))
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
      .finally(() => setBusy(false))
  }

  return (
    <div className="pm2-chat">
      <div className="pm2-chat-head">
        <Orb size={28} />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
          <span style={{ fontSize: 14, fontWeight: 600 }}>Check-in with {assistant}</span>
          <span className="pm2-muted" style={{ fontSize: 11 }}>Talk it through, then turn it into your entry</span>
        </div>
      </div>

      {!keys.anthropic ? (
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', padding: 24 }}>
          <div className="pm2-upsell" style={{ width: '100%' }}>
            <Orb size={40} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontSize: 15, fontWeight: 600 }}>Chat about your day</span>
              <span className="pm2-secondary" style={{ fontSize: 12 }}>Journal with {assistant}. Part of Joshu Pro (Settings › Joshu Pro).</span>
            </div>
          </div>
        </div>
      ) : (
        <>
          <div className="pm2-chat-list">
            {turns.length === 0 && !busy && (
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14, paddingTop: 60, textAlign: 'center' }}>
                <span className="pm2-display" style={{ fontSize: 22 }}>{isTodayEntry ? 'How was today?' : 'Look back on this day'}</span>
                <span className="pm2-secondary" style={{ fontSize: 13 }}>{assistant} will ask about your mood and what you got up to, one question at a time.</span>
                <button className="pm2-primary" style={{ width: 200 }} onClick={() => stream((onText) => startChat(note.id, assistant, onText))}>
                  <MessagesSquare size={15} />Start check-in
                </button>
              </div>
            )}
            {turns.map((t) => <Bubble key={t.id} turn={t} />)}
            {revealing && shown ? <Bubble turn={{ id: 'live', role: 'assistant', text: shown, hidden: false, at: 0 }} />
              : busy ? <div className="pm2-typing"><i /><i /><i /></div> : null}
            {error && (
              <div className="pm2-row" style={{ alignItems: 'flex-start', padding: 10, borderRadius: 10, background: 'var(--canvas)', fontSize: 12 }}>
                <TriangleAlert size={14} color="var(--orange)" style={{ flex: 'none' }} />
                <span style={{ flex: 1 }}>{error}</span>
                <button style={{ fontWeight: 600 }} onClick={() => stream((onText) => reply(note.id, onText))}>Retry</button>
              </div>
            )}
            <div ref={bottom} />
          </div>

          {turns.length > 0 && (
            <div className="pm2-row" style={{ justifyContent: 'center', paddingBottom: 8 }}>
              <button className="pm2-soft" disabled={busy || !turns.some((t) => t.role === 'user')} onClick={write}>
                <WandSparkles size={14} />{note.data.body ? 'Update my entry' : 'Write my entry'}
              </button>
              {undoBody !== null && (
                <button className="pm2-secondary" style={{ fontSize: 12, fontWeight: 600 }}
                  onClick={() => { store.update<Note>(note.id, { body: undoBody, updatedAt: iso(new Date()) }); setUndoBody(null) }}>Undo</button>
              )}
            </div>
          )}

          <div className="pm2-composer">
            <textarea ref={input} className="pm2-plain" rows={1} placeholder="Reply…" value={draft} disabled={busy}
              onChange={(e) => { setDraft(e.target.value); e.target.style.height = 'auto'; e.target.style.height = `${e.target.scrollHeight}px` }}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() } }} />
            <button className="pm2-send" aria-label="Send" disabled={busy || !draft.trim()} onClick={send}><ArrowUp size={15} strokeWidth={3} /></button>
          </div>
        </>
      )}
    </div>
  )
}

/** Each of the assistant's thoughts (split on a blank line) is its own soft bubble. */
function Bubble({ turn }: { turn: Turn }) {
  const mine = turn.role === 'user'
  const parts = mine ? [turn.text] : turn.text.split('\n\n').map((p) => p.trim()).filter(Boolean)
  return <>{parts.map((p, i) => <div key={i} className={`pm2-bubble ${mine ? 'mine' : 'theirs'}`}>{p}</div>)}</>
}

// MARK: - Google Keep (KeepImport.swift)

const keepKey = (title: string, seconds: number) => `${title.toLowerCase()}|${Math.floor(seconds)}`

/** Reads Google Takeout's Keep notes (one .json per note) into Notes, skipping ones already imported. */
async function importKeep(files: File[]): Promise<{ added: number; skipped: number }> {
  const existing = new Set(store.list<Note>('note').map((n) => keepKey(n.data.title ?? '', time(n.data.createdAt) / 1000)))
  const out = { added: 0, skipped: 0 }
  for (const f of files.filter((f) => f.name.toLowerCase().endsWith('.json'))) {
    let j: any
    try { j = JSON.parse(await f.text()) } catch { continue }
    if (!j || typeof j !== 'object' || (j.textContent === undefined && j.listContent === undefined && j.title === undefined)) continue
    if (j.isTrashed === true) continue
    let body = String(j.textContent ?? '').trim()
    if (Array.isArray(j.listContent) && j.listContent.length) {
      const list = j.listContent.map((i: any) => `${i?.isChecked === true ? '☑︎' : '☐'} ${i?.text ?? ''}`).join('\n')
      body = body ? `${body}\n\n${list}` : list
    }
    const labels = (Array.isArray(j.labels) ? j.labels : []).map((l: any) => l?.name).filter((n: unknown): n is string => typeof n === 'string')
    if (labels.length) body += '\n\n' + labels.map((l: string) => '#' + l.replace(/ /g, '')).join(' ')
    let title = String(j.title ?? '').trim()
    if (!title) title = (body.split('\n').find((l) => l) ?? 'Keep note').slice(0, 60)
    const created = typeof j.createdTimestampUsec === 'number' ? new Date(j.createdTimestampUsec / 1000) : new Date()
    const edited = typeof j.userEditedTimestampUsec === 'number' ? new Date(j.userEditedTimestampUsec / 1000) : created
    const key = keepKey(title, created.getTime() / 1000)
    if (existing.has(key)) { out.skipped++; continue }
    existing.add(key)
    store.create<Note>('note', {
      title, body, createdAt: iso(created), updatedAt: iso(edited), isJournal: false, pinned: j.isPinned === true, mood: 0, moodSetByUser: false, chat: null,
    })
    out.added++
  }
  return out
}

/** "Import from Google Keep" with Google's how-to. */
function KeepImportButton() {
  const [help, setHelp] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const picker = useRef<HTMLInputElement>(null)
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      <button className="pm2-soft" onClick={() => setHelp(true)}>
        <KeepLogo />Import from Google Keep
      </button>
      {message && <span style={{ fontSize: 11, color: 'var(--good)' }}>{message}</span>}
      <input ref={picker} type="file" accept=".json,application/json" multiple hidden onChange={async (e) => {
        const files = Array.from(e.target.files ?? [])
        e.target.value = ''
        const r = await importKeep(files)
        setMessage(r.added === 0 && r.skipped === 0 ? 'No Keep notes found there. Pick the notes from the Keep folder of the export.'
          : `Added ${r.added} note${r.added === 1 ? '' : 's'} from Keep${r.skipped > 0 ? `, ${r.skipped} already here` : ''}.`)
      }} />
      <Modal open={help} onClose={() => setHelp(false)}>
        <div className="pm2-sheet">
          <h2 style={{ fontSize: 17, fontWeight: 600 }}>Import from Google Keep</h2>
          <div className="pm2-secondary" style={{ fontSize: 14, whiteSpace: 'pre-line' }}>
            {"Google doesn't let apps sign in to Keep for personal accounts, so Joshu reads Google's export instead.\n\n1. Open Google Takeout, keep only Keep selected and export.\n2. Download and unzip it.\n3. Choose the notes in its Takeout › Keep folder here.\n\nYou can do it again any time; notes already imported are skipped."}
          </div>
          <div className="pm2-actions">
            <button onClick={() => { setHelp(false); window.orbit.openExternal('https://takeout.google.com/settings/takeout/custom/keep') }}>Open Google Takeout</button>
            <button onClick={() => { setHelp(false); picker.current?.click() }}>Choose the Keep notes…</button>
            <button onClick={() => setHelp(false)}>Cancel</button>
          </div>
        </div>
      </Modal>
    </div>
  )
}

/** Google Keep's mark: a yellow note with a bulb. */
function KeepLogo() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden>
      <rect x="4" y="2" width="16" height="20" rx="3" fill="#FBBC04" />
      <circle cx="12" cy="11" r="3.4" fill="#fff" />
      <rect x="10.4" y="14.6" width="3.2" height="2.4" rx="0.6" fill="#fff" />
    </svg>
  )
}
