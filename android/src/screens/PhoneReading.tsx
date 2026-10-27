// Reading on the phone: PhoneReading in iOS/OrbitPhone/PhoneSections.swift, with the wooden bookshelf from
// Sources/Orbit/Views/BookshelfView.swift and the book sheet from ReadingView.swift (BookDetailSheet, AddBookSheet).
// Progress, shelf and reviews go to Goodreads through ~/lib/goodreads (GoodreadsSync.swift on the Mac).
import { useEffect, useMemo, useRef, useState, ReactNode, CSSProperties } from 'react'
import {
  Library, BookOpen, Bookmark, BadgeCheck, CircleX, Highlighter, Plus, RefreshCw, Search, Timer, Square, Star,
  Copy, Check, Trash2, StickyNote, Pencil, Image as ImageIcon, Send, Laptop,
} from 'lucide-react'
import { store, useRecords, useSetting, Rec } from '@/lib/store'
import { Book, BookCategory, Highlight, ReadingSession, ReadingStatus, matchKey, paletteColor, sessionMinutes } from '@/lib/models'
import { iso, parse, startOfWeek, toDateInput, fromInputs } from '@/lib/dates'
import { useActiveSession, startReading, stopReading, minutesSince, readingStreak } from '@/lib/readingTimer'
import { Modal, EmptyHint } from '@/components/ui'
import { BookCover } from '@/screens/Reading'
import { schedule, postReview, useGoodreads } from '../lib/goodreads'
import GoodreadsSettings from '../components/GoodreadsSettings'
import './PhoneReading.css'

// MARK: - Shelves (the Mac's ReadingStatus, in its order and wording)

const STATUSES: { id: ReadingStatus; title: string; icon: (s: number) => ReactNode }[] = [
  { id: 'reading', title: 'Currently reading', icon: (s) => <BookOpen size={s} /> },
  { id: 'toRead', title: 'To read', icon: (s) => <Bookmark size={s} /> },
  { id: 'read', title: 'Read', icon: (s) => <BadgeCheck size={s} /> },
  { id: 'dnf', title: "Didn't finish", icon: (s) => <CircleX size={s} /> },
]
const statusInfo = (s: ReadingStatus) => STATUSES.find((x) => x.id === s) ?? STATUSES[1]
const BADGE: Partial<Record<ReadingStatus, string>> = { read: 'var(--lime)', reading: 'var(--cyan)', dnf: 'var(--peach)' }
const SHELF_COLOR: Record<ReadingStatus, string> = { reading: 'var(--orange)', toRead: 'var(--cyan)', read: 'var(--lime)', dnf: 'var(--pink)' }

/** Book.status's setter on the Mac: starting sets startedAt, finishing sets finishedAt and 100%. */
function setStatus(book: Rec<Book>, s: ReadingStatus): void {
  const b = book.data
  const patch: Partial<Book> = { status: s }
  if (s === 'reading' && !b.startedAt) patch.startedAt = iso(new Date())
  if (s === 'read') { if (!b.finishedAt) patch.finishedAt = iso(new Date()); patch.progress = 1 }
  store.update<Book>(book.id, patch)
}

/** Sends the change to Goodreads a few seconds later (BookDetailSheet's onChange on the Mac). */
const syncLater = (id: string) => { const b = store.get<Book>(id); if (b) schedule(b) }

/** BookLibrary.currentlyReading: the book you last read (timer sessions) first, then the one most recently started or added. */
function currentlyReading(books: Rec<Book>[], sessions: Rec<ReadingSession>[]): Rec<Book>[] {
  const last = new Map<string, number>()
  for (const s of sessions) {
    if (!s.data.bookUUID) continue
    const t = parse(s.data.start)?.getTime() ?? 0
    last.set(s.data.bookUUID, Math.max(last.get(s.data.bookUUID) ?? 0, t))
  }
  const key = (b: Rec<Book>) => Math.max(last.get(b.id) ?? 0, parse(b.data.startedAt)?.getTime() ?? 0, parse(b.data.addedAt)?.getTime() ?? 0)
  return books.filter((b) => b.data.status === 'reading').sort((a, b) => key(b) - key(a))
}

const includes = (s: string | undefined, q: string) => (s ?? '').toLowerCase().includes(q)

// MARK: - Screen

export default function PhoneReading() {
  const books = useRecords<Book>('book').slice().sort((a, b) => (parse(b.data.addedAt)?.getTime() ?? 0) - (parse(a.data.addedAt)?.getTime() ?? 0))
  const highlights = useRecords<Highlight>('highlight').slice().sort((a, b) => (b.data.createdAt ?? '').localeCompare(a.data.createdAt ?? ''))
  const sessions = useRecords<ReadingSession>('readingSession')
  const goal = Number(useSetting<number>('readingGoal', 24)) || 24

  const [shelf, setShelf] = useState<string>('all')
  const [query, setQuery] = useState('')
  const [detail, setDetail] = useState<string | null>(null)
  const [menuFor, setMenuFor] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [sources, setSources] = useState(false)

  const year = new Date().getFullYear()
  const readThisYear = books.filter((b) => b.data.status === 'read' && parse(b.data.finishedAt)?.getFullYear() === year).length
  const q = query.trim().toLowerCase()
  const shown = books.filter((b) => shelf === 'all' || b.data.status === shelf)
    .filter((b) => !q || includes(b.data.title, q) || includes(b.data.author, q))
  const current = currentlyReading(books, sessions)
  const detailBook = detail ? books.find((b) => b.id === detail) : undefined
  const menuBook = menuFor ? books.find((b) => b.id === menuFor) : undefined

  return (
    <div className="page col pr">
      <div className="pr-search">
        <Search size={15} color="var(--ink3)" />
        <input className="plain" placeholder={shelf === 'highlights' ? 'Search highlights' : 'Search books'} value={query}
          onChange={(e) => setQuery(e.target.value)} enterKeyHint="search" />
      </div>

      <div className="pr-stats">
        <ReadingStat value={`${readThisYear}/${goal}`} label="This year" color="var(--pink)" />
        <ReadingStat value={`${minutesSince(sessions, startOfWeek(new Date()))} min`} label="This week" color="var(--orange)" />
        <ReadingStat value={`${readingStreak(sessions)}`} label="Day streak" color="var(--lime)" />
      </div>

      {current.length > 0 && !q && <CurrentlyReadingStrip books={current} onOpen={(b) => setDetail(b.id)} />}

      <div className="pr-actions">
        <button className="btn-soft" onClick={() => setAdding(true)}><Plus size={14} />Add book</button>
        <button className="btn-soft" onClick={() => setSources(true)}><RefreshCw size={14} />Goodreads sync</button>
      </div>

      <div className="pr-chips">
        <Chip on={shelf === 'all'} onClick={() => setShelf('all')} icon={<Library size={13} />} title="All" />
        {STATUSES.map((s) => <Chip key={s.id} on={shelf === s.id} onClick={() => setShelf(s.id)} icon={s.icon(13)} title={s.title} />)}
        <Chip on={shelf === 'highlights'} onClick={() => setShelf('highlights')} icon={<Highlighter size={13} />} title="Highlights" />
      </div>

      {shelf === 'highlights' ? (
        <div className="col" style={{ gap: 8 }}>
          {highlights.length === 0 && <EmptyHint icon={<Highlighter size={14} />} text="Highlights from Kindle show up here after the Mac imports them." />}
          {highlights.filter((h) => !q || includes(h.data.text, q) || includes(h.data.bookTitle, q)).map((h) => <HighlightRow key={h.id} h={h} showBook />)}
        </div>
      ) : (
        <>
          {shown.length === 0 && <EmptyHint icon={<Library size={14} />} text="No books here yet." />}
          <Bookshelf books={shown} onTap={(b) => setDetail(b.id)} onMenu={(b) => setMenuFor(b.id)} />
        </>
      )}

      {menuBook && (
        <Modal open onClose={() => setMenuFor(null)} width={360}>
          <div className="col" style={{ gap: 12 }}>
            <div style={{ paddingRight: 36 }}>
              <div className="display clamp2" style={{ fontSize: 20 }}>{menuBook.data.title}</div>
              {menuBook.data.author && <div className="secondary" style={{ fontSize: 13 }}>{menuBook.data.author}</div>}
            </div>
            <div className="pr-menu">
              {STATUSES.map((s) => (
                <button key={s.id} className={menuBook.data.status === s.id ? 'on' : ''}
                  onClick={() => { setStatus(menuBook, s.id); syncLater(menuBook.id); setMenuFor(null) }}>
                  {s.icon(16)}{s.title}<span className="spacer" />{menuBook.data.status === s.id && <Check size={16} />}
                </button>
              ))}
            </div>
          </div>
        </Modal>
      )}
      {detailBook && <BookDetailSheet key={detailBook.id} book={detailBook} onClose={() => setDetail(null)} />}
      {adding && <AddBookSheet books={books} onClose={() => setAdding(false)} />}
      {sources && <GoodreadsSheet books={books} onClose={() => setSources(false)} />}
    </div>
  )
}

function Chip({ on, onClick, icon, title }: { on: boolean; onClick: () => void; icon: ReactNode; title: string }) {
  return <button className={`pr-chip ${on ? 'on' : ''}`} onClick={onClick}>{icon}{title}</button>
}

function ReadingStat({ value, label, color }: { value: string; label: string; color: string }) {
  const size = value.length > 7 ? 18 : value.length > 5 ? 21 : 26
  return (
    <div className="pr-stat" style={{ background: color }}>
      <div className="v" style={{ fontSize: size }}>{value}</div>
      <div className="l">{label}</div>
    </div>
  )
}

function Stars({ rating, size = 12, onChange }: { rating: number; size?: number; onChange?: (r: number) => void }) {
  return (
    <span className="row" style={{ gap: 2 }}>
      {[1, 2, 3, 4, 5].map((i) => (
        <Star key={i} size={size} strokeWidth={2.2}
          fill={i <= rating ? 'var(--orange)' : 'none'} color={i <= rating ? 'var(--orange)' : 'var(--ink3)'}
          onClick={onChange ? (e) => { e.stopPropagation(); onChange(rating === i ? 0 : i) } : undefined} />
      ))}
    </span>
  )
}

// MARK: - Currently reading

function TimerButton({ book, short }: { book: Rec<Book>; short?: boolean }) {
  const active = useActiveSession()
  const on = active?.data.bookUUID === book.id
  return on
    ? <span role="button" className="btn-soft" style={{ alignSelf: 'flex-start', background: short ? 'var(--canvas)' : undefined }}
        onClick={(e) => { e.stopPropagation(); stopReading(active) }}><Square size={11} fill="currentColor" />{short ? 'Stop' : 'Stop reading'}</span>
    : <span role="button" className="btn-soft" style={{ alignSelf: 'flex-start', background: short ? 'var(--canvas)' : undefined }}
        onClick={(e) => { e.stopPropagation(); startReading(book) }}><Timer size={13} />Start reading</span>
}

function CurrentlyReadingStrip({ books, onOpen }: { books: Rec<Book>[]; onOpen: (b: Rec<Book>) => void }) {
  return (
    <div className="col" style={{ gap: 14 }}>
      <h3 className="section-title" style={{ fontSize: 22 }}>Currently reading</h3>
      <div className="pr-strip">
        {books.map((b) => {
          const p = b.data.progress || 0
          return (
            <div key={b.id} role="button" className="pr-current" onClick={() => onOpen(b)}>
              <div style={{ width: 84, height: 126, flex: 'none' }}><BookCover book={b.data} /></div>
              <div className="info">
                <div className="clamp2" style={{ fontSize: 15, fontWeight: 600 }}>{b.data.title}</div>
                <div className="secondary clamp1" style={{ fontSize: 12 }}>{b.data.author}</div>
                <span className="spacer" />
                <div className="secondary" style={{ fontSize: 11, fontWeight: 500 }}>
                  {Math.floor(p * 100)}%{b.data.pageCount > 0 && ` · page ${Math.floor(p * b.data.pageCount)} of ${b.data.pageCount}`}
                </div>
                <div className="pr-bar"><div style={{ width: `max(6px, ${p * 100}%)` }} /></div>
                <TimerButton book={b} short />
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

// MARK: - The wooden bookshelf

/** Grain: thin, slightly wavy darker streaks (ShelfBack's Canvas, with the same seeded random numbers). */
const GRAIN: string = (() => {
  const W = 360, H = 170
  let seed = 7n
  const mask = (1n << 64n) - 1n
  const rand = () => { seed = (seed * 6364136223846793005n + 1442695040888963407n) & mask; return Number(seed >> 33n) / 4294967295 }
  let paths = ''
  for (let i = 0; i < Math.floor(W / 9); i++) {
    // Same order of random draws as the Swift: start x, end x, control 1, control 2, then opacity and width.
    const x = rand() * W
    const ex = x + (rand() - 0.5) * 14
    const c1x = x + (rand() - 0.5) * 20, c1y = H * 0.35
    const c2x = x + (rand() - 0.5) * 20, c2y = H * 0.7
    const o = 0.05 + rand() * 0.08, w = 0.6 + rand() * 1.6
    paths += `<path d='M${x.toFixed(1)} 0C${c1x.toFixed(1)} ${c1y} ${c2x.toFixed(1)} ${c2y} ${ex.toFixed(1)} ${H}' stroke='rgba(0,0,0,${o.toFixed(3)})' stroke-width='${w.toFixed(2)}' fill='none' vector-effect='non-scaling-stroke'/>`
  }
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 ${W} ${H}' preserveAspectRatio='none'>${paths}</svg>`
  return `url("data:image/svg+xml,${encodeURIComponent(svg)}")`
})()

const COVER_W = 96, SPACING = 14, INSET = 14

function Bookshelf({ books, onTap, onMenu }: { books: Rec<Book>[]; onTap: (b: Rec<Book>) => void; onMenu: (b: Rec<Book>) => void }) {
  const ref = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(0)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    const ro = new ResizeObserver(() => setWidth(el.clientWidth))
    ro.observe(el)
    setWidth(el.clientWidth)
    return () => ro.disconnect()
  }, [])
  const perRow = Math.max(2, Math.floor((width - INSET * 2 + SPACING) / (COVER_W + SPACING)))
  const rows: Rec<Book>[][] = []
  if (width > 0) for (let i = 0; i < books.length; i += perRow) rows.push(books.slice(i, i + perRow))

  return (
    <div ref={ref} className="pr-shelves" style={{ '--pr-grain': GRAIN } as CSSProperties}>
      {rows.map((row) => (
        <div key={row[0].id} className="pr-shelf">
          {/* The back of the shelf, with the books standing in it. */}
          <div className="pr-shelf-back">
            {row.map((b) => <ShelfBook key={b.id} book={b} onTap={() => onTap(b)} onMenu={() => onMenu(b)} />)}
          </div>
          <div className="pr-plank"><div className="top" /><div className="front" /></div>
          {/* Little labels under each book. */}
          <div className="pr-labels">
            {row.map((b) => (
              <button key={b.id} className="pr-label" onClick={() => onTap(b)} onContextMenu={(e) => { e.preventDefault(); onMenu(b) }}>
                <span className="t clamp2">{b.data.title}</span>
                {b.data.author && <span className="a clamp1">{b.data.author}</span>}
                {b.data.rating > 0 && <Stars rating={b.data.rating} size={9} />}
              </button>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

/** One book standing on the shelf, cover out, casting a soft shadow on the wood. Long-press to move it to another shelf. */
function ShelfBook({ book, onTap, onMenu }: { book: Rec<Book>; onTap: () => void; onMenu: () => void }) {
  const b = book.data
  return (
    <button className="pr-book" onClick={onTap} onContextMenu={(e) => { e.preventDefault(); onMenu() }} aria-label={b.title}>
      <BookCover book={b} />
      {b.status !== 'toRead' && BADGE[b.status] && (
        <span className="badge" style={{ background: BADGE[b.status] }}>{statusInfo(b.status).icon(10)}</span>
      )}
      {b.status === 'reading' && (b.progress || 0) > 0 && (
        <span className="prog"><div style={{ width: `max(4px, ${(b.progress || 0) * 100}%)` }} /></span>
      )}
    </button>
  )
}

// MARK: - Highlights

function HighlightRow({ h, showBook }: { h: Rec<Highlight>; showBook?: boolean }) {
  const [copied, setCopied] = useState(false)
  const copy = () => {
    navigator.clipboard?.writeText(`“${h.data.text}” — ${h.data.bookTitle}`).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1500) }).catch(() => undefined)
  }
  return (
    <div className="pr-hl">
      <span className="bar" />
      <div className="col" style={{ gap: 6, flex: 1, minWidth: 0 }}>
        <div className="display" style={{ fontSize: 15, fontWeight: 500, userSelect: 'text', whiteSpace: 'pre-wrap' }}>{h.data.text}</div>
        {h.data.note && <div className="row secondary" style={{ gap: 6, fontSize: 12, alignItems: 'flex-start' }}><StickyNote size={12} style={{ marginTop: 2, flex: 'none' }} />{h.data.note}</div>}
        {showBook && h.data.bookTitle && <div className="secondary" style={{ fontSize: 12, fontWeight: 600 }}>{h.data.bookTitle}</div>}
        {h.data.location && <div className="muted" style={{ fontSize: 10, textTransform: 'capitalize' }}>{h.data.location.toLowerCase()}</div>}
      </div>
      <div className="acts">
        <button title="Copy" onClick={copy}>{copied ? <Check size={14} /> : <Copy size={14} />}</button>
        <button title="Delete" onClick={() => store.remove(h.id)}><Trash2 size={14} /></button>
      </div>
    </div>
  )
}

// MARK: - Book sheet (BookDetailSheet)

const SOURCE_LABEL: Record<string, string> = {
  goodreads: 'From Goodreads', 'apple-books': 'From Apple Books', kindle: 'From Kindle', openlibrary: 'From Open Library',
}

function sumCodes(s: string): number { let n = 0; for (const ch of s) n += ch.codePointAt(0) ?? 0; return n }

function BookDetailSheet({ book, onClose }: { book: Rec<Book>; onClose: () => void }) {
  const b = book.data
  const categories = useRecords<BookCategory>('bookCategory').slice().sort((x, y) => (x.data.createdAt ?? '').localeCompare(y.data.createdAt ?? ''))
  const allHighlights = useRecords<Highlight>('highlight')
  const sessions = useRecords<ReadingSession>('readingSession')
  const goodreads = useGoodreads()
  const [editingName, setEditingName] = useState(false)
  const [changingCover, setChangingCover] = useState(false)
  const [reviewStatus, setReviewStatus] = useState<string | null>(null)

  const set = (patch: Partial<Book>) => store.update<Book>(book.id, patch)
  const tint = paletteColor(sumCodes(b.title ?? ''))
  const mine = allHighlights.filter((h) => h.data.bookUUID === book.id || (h.data.bookTitle ?? '').toLowerCase() === (b.title ?? '').toLowerCase())
    .sort((x, y) => (x.data.createdAt ?? '').localeCompare(y.data.createdAt ?? ''))
  const minutes = Math.floor(sessions.filter((s) => s.data.bookUUID === book.id).reduce((n, s) => n + sessionMinutes(s.data), 0))
  const progress = b.progress || 0

  const dateRow = (label: string, value: string | null, key: 'startedAt' | 'finishedAt') => (
    <div className="r">
      <span>{label}</span>
      <input type="date" value={toDateInput(parse(value) ?? new Date())}
        onChange={(e) => e.target.value && set({ [key]: iso(fromInputs(e.target.value, '12:00')) } as Partial<Book>)} />
    </div>
  )

  return (
    <Modal open onClose={onClose} width={520}>
      <div className="col pr-detail" style={{ clear: 'both', paddingTop: 4 }}>
        {/* The cover, centred on a wash of its own colour, with the title, author and rating under it. */}
        <div className="pr-hero" style={{ background: `linear-gradient(color-mix(in srgb, ${tint} 45%, transparent), color-mix(in srgb, ${tint} 8%, transparent))` }}>
          <div className="cv"><BookCover book={b} /></div>
          <button className="pr-link" onClick={() => setChangingCover(true)}><ImageIcon size={13} />Change cover</button>
          {editingName ? (
            <div className="col" style={{ gap: 8, width: '100%', alignItems: 'center' }}>
              <input className="field display" style={{ fontSize: 20, textAlign: 'center' }} placeholder="Title" value={b.title} onChange={(e) => set({ title: e.target.value })} />
              <input className="field" style={{ textAlign: 'center' }} placeholder="Author" value={b.author} onChange={(e) => set({ author: e.target.value })}
                onKeyDown={(e) => e.key === 'Enter' && setEditingName(false)} />
              <button className="btn-soft" onClick={() => setEditingName(false)}>Done</button>
            </div>
          ) : (
            <>
              <div className="display" style={{ fontSize: 24 }}>{b.title || 'Untitled'}</div>
              <div className="row" style={{ gap: 6, justifyContent: 'center' }}>
                <span className="secondary" style={{ fontSize: 15 }}>{b.author || 'Unknown author'}</span>
                <button title="Edit title and author" style={{ color: 'var(--ink3)', padding: 4 }} onClick={() => setEditingName(true)}><Pencil size={13} /></button>
              </div>
            </>
          )}
          <div style={{ paddingTop: 2 }}><Stars rating={b.rating} size={20} onChange={(r) => set({ rating: r })} /></div>
          <div className="muted" style={{ fontSize: 11 }}>{SOURCE_LABEL[b.source] ?? 'Added by you'}</div>
        </div>

        {/* One big button per shelf, the current one filled. */}
        <div className="pr-shelfpick">
          {STATUSES.map((s) => {
            const on = b.status === s.id
            return (
              <button key={s.id} className={on ? 'on' : ''} style={on ? { background: SHELF_COLOR[s.id] } : undefined}
                onClick={() => { setStatus(book, s.id); syncLater(book.id) }}>
                {s.icon(18)}{s.id === 'dnf' ? 'Stopped' : s.title}
              </button>
            )
          })}
        </div>

        {b.status === 'reading' && (
          <div className="pr-progress">
            <div className="row">
              <span style={{ fontSize: 13, fontWeight: 600 }}>Progress</span>
              <span className="spacer" />
              <span style={{ fontSize: 13, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{Math.floor(progress * 100)}%</span>
            </div>
            <input type="range" min={0} max={1} step={0.01} value={progress}
              onChange={(e) => { set({ progress: Number(e.target.value) }); syncLater(book.id) }} />
          </div>
        )}

        <div className="pr-cardbox">
          <div className="r">
            <span>Pages</span>
            <input type="number" inputMode="numeric" min={0} style={{ width: 90 }} value={b.pageCount || ''}
              onChange={(e) => set({ pageCount: Math.max(0, Math.floor(Number(e.target.value) || 0)) })} />
          </div>
          {b.status !== 'toRead' && dateRow('Started', b.startedAt, 'startedAt')}
          {b.status === 'read' && dateRow('Finished', b.finishedAt, 'finishedAt')}
        </div>

        <div className="col" style={{ gap: 8 }}>
          <span className="pr-sub">Categories</span>
          {categories.length === 0 && <span className="muted" style={{ fontSize: 12 }}>Create categories from the Reading sidebar.</span>}
          <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
            {categories.map((c) => {
              const on = (b.categories ?? []).includes(c.data.name)
              return (
                <button key={c.id} className="pr-catchip"
                  style={{ background: `color-mix(in srgb, ${paletteColor(c.data.colorIndex)} ${on ? 100 : 30}%, transparent)` }}
                  onClick={() => { const cur = b.categories ?? []; set({ categories: on ? cur.filter((x) => x !== c.data.name) : [...cur, c.data.name] }) }}>
                  {c.data.name}
                </button>
              )
            })}
          </div>
        </div>

        <div className="col" style={{ gap: 10 }}>
          <div className="row">
            <span className="row secondary" style={{ gap: 6, fontSize: 12 }}><Timer size={13} />
              {minutes === 0 ? 'No reading time yet' : minutes < 60 ? `${minutes} min read` : `${(minutes / 60).toFixed(1)} h read`}</span>
            <span className="spacer" />
            <TimerButton book={book} />
          </div>
          {mine.length > 0 && (
            <>
              <span className="pr-sub">Highlights ({mine.length})</span>
              <div className="col" style={{ gap: 6, maxHeight: 180, overflowY: 'auto' }}>{mine.map((h) => <HighlightRow key={h.id} h={h} />)}</div>
            </>
          )}
        </div>

        <div className="col" style={{ gap: 8 }}>
          <span className="pr-sub">Notes</span>
          <textarea className="pr-notes" value={b.notes ?? ''} onChange={(e) => set({ notes: e.target.value })} />
          {goodreads.signedIn && (b.notes ?? '').trim() && (
            <div className="row" style={{ gap: 10, alignItems: 'center' }}>
              <button className="btn-soft" onClick={async () => {
                setReviewStatus('Posting…')
                const latest = store.get<Book>(book.id) ?? book
                setReviewStatus(await postReview(latest, latest.data.notes, latest.data.rating))
              }}><Send size={13} />Post as my Goodreads review</button>
              {reviewStatus && <span className="secondary clamp2" style={{ fontSize: 11 }}>{reviewStatus}</span>}
            </div>
          )}
        </div>

        <div className="row">
          <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(book.id); onClose() }}>Delete</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 110 }} onClick={onClose}>Done</button>
        </div>
      </div>
      {changingCover && <CoverPicker book={book} onClose={() => setChangingCover(false)} />}
    </Modal>
  )
}

// MARK: - Choose a cover (CoverPicker, from Open Library)

async function findCovers(b: Book): Promise<string[]> {
  const out: string[] = []
  const add = (u: string) => { if (u && !out.includes(u)) out.push(u) }
  if (b.isbn) add(`https://covers.openlibrary.org/b/isbn/${b.isbn}-L.jpg?default=false`)
  const params = new URLSearchParams({ title: (b.title ?? '').split(':')[0].trim(), limit: '20', fields: 'cover_i,isbn' })
  if (b.author) params.set('author', b.author)
  try {
    const json = await fetch(`https://openlibrary.org/search.json?${params}`).then((r) => r.json())
    for (const d of json.docs ?? []) if (d.cover_i) add(`https://covers.openlibrary.org/b/id/${d.cover_i}-L.jpg`)
  } catch { /* offline: show what we have */ }
  return out.slice(0, 24)
}

function CoverPicker({ book, onClose }: { book: Rec<Book>; onClose: () => void }) {
  const [options, setOptions] = useState<string[] | null>(null)
  const [broken, setBroken] = useState<string[]>([])
  useEffect(() => { let live = true; findCovers(book.data).then((o) => live && setOptions(o)); return () => { live = false } }, [book.id])
  const visible = (options ?? []).filter((u) => !broken.includes(u))
  return (
    <Modal open onClose={onClose} width={620}>
      <div className="col" style={{ gap: 16, clear: 'both' }}>
        <h2 className="display" style={{ fontSize: 24, margin: 0 }}>Choose a cover</h2>
        <div className="secondary" style={{ fontSize: 12 }}>
          Covers that match “{book.data.title}”{book.data.author ? ` by ${book.data.author}` : ''}.
        </div>
        {options === null && <div className="muted" style={{ fontSize: 13 }}>Looking…</div>}
        {options !== null && visible.length === 0 && (
          <div className="secondary" style={{ fontSize: 13 }}>No other covers found for this title. Check the title and author.</div>
        )}
        <div className="pr-covers">
          {visible.map((u) => (
            <button key={u} className={book.data.coverURL === u ? 'on' : ''} onClick={() => { store.update<Book>(book.id, { coverURL: u }); onClose() }}>
              <img src={u} alt="" loading="lazy"
                onError={() => setBroken((x) => [...x, u])}
                onLoad={(e) => { if ((e.target as HTMLImageElement).naturalWidth < 5) setBroken((x) => [...x, u]) }} />
            </button>
          ))}
        </div>
        <div className="row"><span className="spacer" /><button className="btn-primary" style={{ width: 110 }} onClick={onClose}>Done</button></div>
      </div>
    </Modal>
  )
}

// MARK: - Add a book (AddBookSheet)

interface OLResult { key: string; title: string; author: string; year: number; pages: number; isbn: string; coverURL: string }

async function searchOpenLibrary(q: string): Promise<OLResult[]> {
  const url = `https://openlibrary.org/search.json?q=${encodeURIComponent(q)}&limit=12&fields=key,title,author_name,first_publish_year,number_of_pages_median,isbn,cover_i`
  const json = await fetch(url).then((r) => r.json())
  return (json.docs ?? []).filter((d: any) => d.title).map((d: any) => ({
    key: d.key ?? crypto.randomUUID(),
    title: d.title,
    author: d.author_name?.[0] ?? '',
    year: d.first_publish_year ?? 0,
    pages: d.number_of_pages_median ?? 0,
    isbn: d.isbn?.[0] ?? '',
    coverURL: d.cover_i ? `https://covers.openlibrary.org/b/id/${d.cover_i}-M.jpg` : '',
  }))
}

function AddBookSheet({ books, onClose }: { books: Rec<Book>[]; onClose: () => void }) {
  const categories = useRecords<BookCategory>('bookCategory').slice().sort((x, y) => (x.data.createdAt ?? '').localeCompare(y.data.createdAt ?? ''))
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<OLResult[]>([])
  const [searching, setSearching] = useState(false)
  const [error, setError] = useState('')
  const [status, setStatusValue] = useState<ReadingStatus>('toRead')
  const [picked, setPicked] = useState<string[]>([])
  const [title, setTitle] = useState('')
  const [author, setAuthor] = useState('')
  const [added, setAdded] = useState('')

  const search = async () => {
    const q = query.trim()
    if (!q) return
    setSearching(true); setError('')
    try {
      const r = await searchOpenLibrary(q)
      setResults(r)
      if (!r.length) setError('No matches. Add it by hand below.')
    } catch (e) {
      setError(`Search failed: ${(e as Error).message ?? String(e)}`)
    }
    setSearching(false)
  }

  const insert = (x: { title: string; author: string; isbn?: string; pages?: number; year?: number; coverURL?: string; externalID?: string }, source: string) => {
    const key = matchKey(x.title, x.author)
    const existing = books.find((b) => (x.externalID && b.data.externalID === x.externalID) || matchKey(b.data.title, b.data.author) === key)
    if (existing) {
      store.update<Book>(existing.id, { categories: [...new Set([...(existing.data.categories ?? []), ...picked])] })
      setAdded(`“${existing.data.title}” is already in your library.`)
      return
    }
    const now = iso(new Date())
    const book: Book = {
      title: x.title.trim(), author: x.author.trim(), status, rating: 0, categories: picked, notes: '',
      coverURL: x.coverURL || (x.isbn ? `https://covers.openlibrary.org/b/isbn/${x.isbn}-M.jpg?default=false` : ''),
      isbn: x.isbn ?? '', pageCount: x.pages ?? 0, progress: status === 'read' ? 1 : 0, year: x.year ?? 0,
      addedAt: now, startedAt: status === 'reading' ? now : null, finishedAt: status === 'read' ? now : null,
      source, sources: [source], externalID: x.externalID ?? '',
    }
    store.create<Book>('book', book)
    setAdded(`Added “${book.title}”.`)
  }

  return (
    <Modal open onClose={onClose} width={600}>
      <div className="col" style={{ gap: 16, clear: 'both' }}>
        <h2 className="display" style={{ fontSize: 28, margin: 0 }}>Add a book</h2>
        <div className="pr-search">
          <Search size={15} color="var(--ink3)" />
          <input className="plain" placeholder="Search by title, author or ISBN" value={query} enterKeyHint="search"
            onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && search()} />
          {searching && <span className="muted" style={{ fontSize: 12 }}>Searching…</span>}
        </div>
        <div className="row">
          <select className="pr-select" value={status} onChange={(e) => setStatusValue(e.target.value as ReadingStatus)} aria-label="Shelf">
            {STATUSES.map((s) => <option key={s.id} value={s.id}>{s.title}</option>)}
          </select>
          <span className="spacer" />
        </div>
        {categories.length > 0 && (
          <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
            {categories.map((c) => {
              const on = picked.includes(c.data.name)
              return (
                <button key={c.id} className="pr-catchip"
                  style={{ background: `color-mix(in srgb, ${paletteColor(c.data.colorIndex)} ${on ? 100 : 30}%, transparent)` }}
                  onClick={() => setPicked(on ? picked.filter((n) => n !== c.data.name) : [...picked, c.data.name])}>{c.data.name}</button>
              )
            })}
          </div>
        )}
        <div className="pr-results">
          {error && <div style={{ color: 'var(--critical)', fontSize: 12 }}>{error}</div>}
          {results.map((r) => (
            <div key={r.key} className="pr-result">
              {r.coverURL ? <img src={r.coverURL} alt="" /> : <span className="noimg" />}
              <div style={{ minWidth: 0, flex: 1 }}>
                <div className="clamp2" style={{ fontSize: 14, fontWeight: 600 }}>{r.title}</div>
                <div className="secondary clamp2" style={{ fontSize: 12 }}>
                  {[r.author, r.year ? String(r.year) : '', r.pages ? `${r.pages} pages` : ''].filter(Boolean).join(' · ')}
                </div>
              </div>
              <button className="btn-soft" onClick={() => {
                insert({ title: r.title, author: r.author, isbn: r.isbn, pages: r.pages, year: r.year, coverURL: r.coverURL, externalID: `openlibrary:${r.key}` }, 'openlibrary')
                setResults((rs) => rs.filter((x) => x.key !== r.key))
              }}>Add</button>
            </div>
          ))}
        </div>
        <div style={{ height: 1, background: 'var(--line)' }} />
        <span className="pr-sub">Or add it by hand</span>
        <div className="col" style={{ gap: 8 }}>
          <input className="field" placeholder="Title" value={title} onChange={(e) => setTitle(e.target.value)} />
          <div className="row">
            <input className="field" placeholder="Author" value={author} onChange={(e) => setAuthor(e.target.value)} />
            <button className="btn-soft" disabled={!title.trim()} onClick={() => { insert({ title, author }, 'manual'); setTitle(''); setAuthor('') }}>Add</button>
          </div>
        </div>
        <div className="row">
          {added && <span className="secondary" style={{ fontSize: 12, flex: 1 }}>{added}</span>}
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120 }} onClick={onClose}>Done</button>
        </div>
      </div>
    </Modal>
  )
}

// MARK: - Goodreads sync

/** The "Goodreads sync" sheet: sending your reading to Goodreads (sign in here) and where your shelves come from. */
function GoodreadsSheet({ books, onClose }: { books: Rec<Book>[]; onClose: () => void }) {
  const profile = useSetting<string>('goodreadsUser', '')
  const fromGoodreads = books.filter((b) => (b.data.sources ?? []).includes('goodreads') || b.data.source === 'goodreads').length
  const apple = books.filter((b) => (b.data.sources ?? []).includes('apple-books') || b.data.source === 'apple-books').length
  const kindle = books.filter((b) => (b.data.sources ?? []).includes('kindle') || b.data.source === 'kindle').length
  return (
    <Modal open onClose={onClose} width={600}>
      <div className="col" style={{ gap: 16, clear: 'both' }}>
        <h2 className="display" style={{ fontSize: 28, margin: 0 }}>Goodreads sync</h2>
        <GoodreadsSettings />
        <div className="card col" style={{ gap: 6, padding: 14 }}>
          <strong style={{ fontSize: 15 }}>Your Goodreads shelves</strong>
          <span className="secondary" style={{ fontSize: 12 }}>
            {profile
              ? 'Joshu reads your public Goodreads shelves and the books appear here on their own.'
              : 'Joshu reads your public Goodreads shelves. Add your profile link in Joshu on your Mac or iPhone (Reading › Goodreads sync).'}
          </span>
          {fromGoodreads > 0 && <span style={{ fontSize: 12, fontWeight: 500, color: 'var(--good)' }}>{fromGoodreads} book{fromGoodreads === 1 ? '' : 's'} from Goodreads</span>}
        </div>
        <div className="card row" style={{ gap: 12, padding: 14, alignItems: 'flex-start' }}>
          <span style={{ width: 34, height: 34, borderRadius: 10, background: 'var(--cyan)', color: 'var(--sticker-ink)', flex: 'none',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}><Laptop size={16} /></span>
          <div className="col" style={{ gap: 4, minWidth: 0 }}>
            <strong style={{ fontSize: 15 }}>Apple Books and Kindle</strong>
            <span className="secondary" style={{ fontSize: 12 }}>Joshu on your Mac imports these libraries, and the books then appear here on their own.</span>
            {apple + kindle > 0 && <span style={{ fontSize: 12, fontWeight: 500, color: 'var(--good)' }}>{apple} from Apple Books · {kindle} from Kindle</span>}
          </div>
        </div>
        <div className="row"><span className="spacer" /><button className="btn-primary" style={{ width: 120 }} onClick={onClose}>Done</button></div>
      </div>
    </Modal>
  )
}
