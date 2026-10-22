// Reading: shelves, categories, library tabs (Goodreads, Kindle, Apple Books, added by you) and Open Library search.
// Mirrors ReadingView.swift on the Mac; books are the same `book` / `bookCategory` records.
import { useMemo, useRef, useState, ReactNode } from 'react'
import {
  Highlighter, Timer, Square, Download, Copy, Trash2, StickyNote,
  Library, BookOpen, Bookmark, BadgeCheck, CircleX, Tag, Plus, Minus, Search, ArrowUpDown, Check, Star,
  Heart, Brain, Briefcase, Sparkles, Globe, FlaskConical, Drama, Leaf, Moon, Zap, BookMarked, GraduationCap, DollarSign, Users, User, Flame,
} from 'lucide-react'
import { store, useRecords, useSetting, Rec } from '@/lib/store'
import { Book, BookCategory, ReadingStatus, READING_STATUS, IMPORTED_SOURCES, paletteColor, PALETTE, matchKey, Highlight, ReadingSession, sessionMinutes } from '@/lib/models'
import { iso, parse, toDateInput, fromInputs, startOfWeek } from '@/lib/dates'
import { useActiveSession, startReading, stopReading, minutesSince, readingStreak } from '@/lib/readingTimer'
import { parseKindleFile, importHighlights } from '@/lib/kindle'
import { Modal, Segmented, EmptyHint } from '@/components/ui'
import './Reading.css'

// MARK: - Helpers

export { matchKey }

const sourcesOf = (b: Book): string[] => (b.sources?.length ? b.sources : [b.source])
const inLibrary = (b: Book, lib: string): boolean =>
  lib === 'mine' ? !sourcesOf(b).every((s) => IMPORTED_SOURCES.includes(s)) : sourcesOf(b).includes(lib) || b.source === lib

const STATUS_ICON: Record<ReadingStatus, ReactNode> = {
  reading: <BookOpen size={12} />, toRead: <Bookmark size={12} />, read: <BadgeCheck size={12} />, dnf: <CircleX size={12} />,
}
const STATUS_BADGE: Record<string, string> = { read: 'var(--lime)', reading: 'var(--cyan)', dnf: 'var(--peach)' }

/** Category icons (named after the Mac's SF Symbols so both apps agree). */
const CATEGORY_ICONS: { id: string; icon: (s: number) => ReactNode }[] = [
  { id: 'tag.fill', icon: (s) => <Tag size={s} /> },
  { id: 'heart.fill', icon: (s) => <Heart size={s} /> },
  { id: 'star.fill', icon: (s) => <Star size={s} /> },
  { id: 'brain.head.profile', icon: (s) => <Brain size={s} /> },
  { id: 'briefcase.fill', icon: (s) => <Briefcase size={s} /> },
  { id: 'sparkles', icon: (s) => <Sparkles size={s} /> },
  { id: 'globe.europe.africa.fill', icon: (s) => <Globe size={s} /> },
  { id: 'flask.fill', icon: (s) => <FlaskConical size={s} /> },
  { id: 'theatermasks.fill', icon: (s) => <Drama size={s} /> },
  { id: 'leaf.fill', icon: (s) => <Leaf size={s} /> },
  { id: 'moon.stars.fill', icon: (s) => <Moon size={s} /> },
  { id: 'bolt.fill', icon: (s) => <Zap size={s} /> },
  { id: 'book.closed.fill', icon: (s) => <BookMarked size={s} /> },
  { id: 'graduationcap.fill', icon: (s) => <GraduationCap size={s} /> },
  { id: 'dollarsign.circle.fill', icon: (s) => <DollarSign size={s} /> },
  { id: 'person.2.fill', icon: (s) => <Users size={s} /> },
]
const categoryIcon = (symbol: string, size = 12): ReactNode => (CATEGORY_ICONS.find((c) => c.id === symbol) ?? CATEGORY_ICONS[0]).icon(size)

function sumCodes(s: string): number { let n = 0; for (const ch of s) n += ch.codePointAt(0) ?? 0; return n }

// MARK: - Cover

export function BookCover({ book }: { book: Book }) {
  const [failed, setFailed] = useState(false)
  const color = paletteColor(sumCodes(book.title ?? ''))
  return (
    <div className="cover" style={{ background: `linear-gradient(${color}, ${color})` }}>
      <div className="ph">
        <div className="t">{book.title}</div>
        <div className="a">{book.author}</div>
      </div>
      {book.coverURL && !failed && <img src={book.coverURL} alt="" onError={() => setFailed(true)}
        onLoad={(e) => { if ((e.target as HTMLImageElement).naturalWidth < 5) setFailed(true) }} />}
    </div>
  )
}

function Stars({ rating, size = 12, onChange }: { rating: number; size?: number; onChange?: (r: number) => void }) {
  return (
    <span className="row" style={{ gap: 2 }}>
      {[1, 2, 3, 4, 5].map((i) => (
        <Star key={i} size={size} strokeWidth={2.2}
          fill={i <= rating ? 'var(--orange)' : 'none'} color={i <= rating ? 'var(--orange)' : 'var(--ink3)'}
          style={{ cursor: onChange ? 'pointer' : undefined }}
          onClick={onChange ? () => onChange(rating === i ? 0 : i) : undefined} />
      ))}
    </span>
  )
}

// MARK: - Screen

type Filter = { type: 'all' } | { type: 'status'; status: ReadingStatus } | { type: 'category'; name: string }
const SORTS = ['Recently added', 'Recently finished', 'Title', 'Author', 'Rating'] as const
type Sort = (typeof SORTS)[number]

export default function Reading() {
  const books = useRecords<Book>('book')
  const highlights = useRecords<Highlight>('highlight')
  const sessions = useRecords<ReadingSession>('readingSession')
  const active = useActiveSession()
  const categories = useRecords<BookCategory>('bookCategory')
    .slice().sort((a, b) => (a.data.createdAt ?? '').localeCompare(b.data.createdAt ?? ''))
  const userName = useSetting<string>('userName', '')
  const first = userName.split(' ')[0]
  const goal = Number(useSetting<number>('readingGoal', 24)) || 24

  const [filter, setFilter] = useState<Filter>({ type: 'all' })
  const [library, setLibrary] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState<Sort>('Recently added')
  const [sortOpen, setSortOpen] = useState(false)
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<string | null>(null)
  const [catEditor, setCatEditor] = useState<{ open: boolean; cat?: Rec<BookCategory> }>({ open: false })

  const year = new Date().getFullYear()
  const readThisYear = books.filter((b) => b.data.status === 'read' && parse(b.data.finishedAt)?.getFullYear() === year)
  const reading = books.filter((b) => b.data.status === 'reading')

  const visible = useMemo(() => {
    let list = books.slice()
    if (filter.type === 'status') list = list.filter((b) => b.data.status === filter.status)
    if (filter.type === 'category') list = list.filter((b) => (b.data.categories ?? []).includes(filter.name))
    if (library) list = list.filter((b) => inLibrary(b.data, library))
    const q = query.trim().toLowerCase()
    if (q) list = list.filter((b) => b.data.title?.toLowerCase().includes(q) || b.data.author?.toLowerCase().includes(q))
    const t = (s: string | null) => parse(s)?.getTime() ?? 0
    switch (sort) {
      case 'Title': list.sort((a, b) => a.data.title.localeCompare(b.data.title)); break
      case 'Author': list.sort((a, b) => a.data.author.localeCompare(b.data.author)); break
      case 'Rating': list.sort((a, b) => b.data.rating - a.data.rating); break
      case 'Recently finished': list.sort((a, b) => t(b.data.finishedAt) - t(a.data.finishedAt)); break
      default: list.sort((a, b) => t(b.data.addedAt) - t(a.data.addedAt))
    }
    return list
  }, [books, filter, library, query, sort])

  const shelfTitle = filter.type === 'all' ? 'All books' : filter.type === 'status'
    ? READING_STATUS.find((s) => s.id === filter.status)!.title : filter.name
  const editingBook = editing ? books.find((b) => b.id === editing) : undefined
  const currentCategory = filter.type === 'category' ? filter.name : undefined

  const deleteCategory = (c: Rec<BookCategory>) => {
    for (const b of books) {
      if ((b.data.categories ?? []).includes(c.data.name)) store.update<Book>(b.id, { categories: b.data.categories.filter((x) => x !== c.data.name) })
    }
    if (filter.type === 'category' && filter.name === c.data.name) setFilter({ type: 'all' })
    store.remove(c.id)
  }

  return (
    <div className="reading">
      {/* Sidebar */}
      <aside className="reading-side">
        <FilterRow title="All books" icon={<Library size={12} />} count={books.length} on={filter.type === 'all'} onClick={() => setFilter({ type: 'all' })} />
        {READING_STATUS.map((s) => (
          <FilterRow key={s.id} title={s.title} icon={STATUS_ICON[s.id]} count={books.filter((b) => b.data.status === s.id).length}
            on={filter.type === 'status' && filter.status === s.id} onClick={() => setFilter({ type: 'status', status: s.id })} />
        ))}
        <div className="rside-label">
          Categories<span className="spacer" />
          <button title="New category" onClick={() => setCatEditor({ open: true })}><Plus size={14} color="var(--ink2)" /></button>
        </div>
        {categories.length === 0 && (
          <button className="btn-soft" style={{ marginLeft: 6 }} onClick={() => setCatEditor({ open: true })}><Tag size={13} />Create a category</button>
        )}
        {categories.map((c) => (
          <div key={c.id} onContextMenu={(e) => { e.preventDefault(); setCatEditor({ open: true, cat: c }) }}>
            <FilterRow title={c.data.name} icon={categoryIcon(c.data.symbol)} tint={paletteColor(c.data.colorIndex)}
              count={books.filter((b) => (b.data.categories ?? []).includes(c.data.name)).length}
              on={filter.type === 'category' && filter.name === c.data.name}
              onClick={() => setFilter({ type: 'category', name: c.data.name })}
              onDoubleClick={() => setCatEditor({ open: true, cat: c })} />
          </div>
        ))}
        {categories.length > 0 && <div className="muted" style={{ fontSize: 11, padding: '8px 12px' }}>Double-click a category to edit it.</div>}
      </aside>

      {/* Main */}
      <section className="reading-main">
        <div className="row" style={{ gap: 12 }}>
          <h1 className="page-title">{first ? `${first}'s Reading` : 'Reading'}</h1>
          <span className="spacer" />
          <div className="row" style={{ background: 'var(--card)', borderRadius: 999, padding: '8px 12px', gap: 6 }}>
            <Search size={14} color="var(--ink3)" />
            <input className="plain" style={{ width: 150 }} placeholder="Search books" value={query} onChange={(e) => setQuery(e.target.value)} />
          </div>
          <div style={{ position: 'relative' }}>
            <button className="icon-btn" title="Sort" onClick={() => setSortOpen((o) => !o)}><ArrowUpDown size={15} /></button>
            {sortOpen && (
              <div className="sortmenu" onMouseLeave={() => setSortOpen(false)}>
                {SORTS.map((s) => (
                  <button key={s} onClick={() => { setSort(s); setSortOpen(false) }}>
                    <span style={{ width: 14 }}>{sort === s && <Check size={14} />}</span>{s}
                  </button>
                ))}
              </div>
            )}
          </div>
          <button className="btn-soft" onClick={() => setAdding(true)}><Plus size={14} />Add book</button>
        </div>

        {/* Stats */}
        <div className="row" style={{ gap: 12, alignItems: 'stretch' }}>
          <GoalTile done={readThisYear.length} goal={goal} year={year} />
          <div className="rstat" style={{ background: 'var(--lime)' }}><div className="v">{reading.length}</div><div className="l">Reading now</div></div>
          <div className="rstat" style={{ background: 'var(--cyan)' }}><div className="v">{books.filter((b) => b.data.status === 'toRead').length}</div><div className="l">To read</div></div>
          <div className="rstat" style={{ background: 'var(--purple)' }}><div className="v">{books.filter((b) => b.data.status === 'read').length}</div><div className="l">Read all time</div></div>
          <div className="rstat" style={{ background: 'var(--orange)' }}>
            <div className="v">{minutesSince(sessions, startOfWeek(new Date()))} min</div>
            <div className="l clamp1">{readingStreak(sessions) > 1 ? `This week · ${readingStreak(sessions)}-day streak` : 'Read this week'}</div>
          </div>
        </div>

        <LibraryTabs books={books} highlights={highlights.length} value={library} onChange={setLibrary} />

        {library === 'highlights' && <HighlightsList highlights={highlights} />}

        {library !== 'highlights' && filter.type === 'all' && !library && !query.trim() && reading.length > 0 && (
          <div className="col" style={{ gap: 14 }}>
            <h3 className="section-title">Currently reading</h3>
            <div className="row" style={{ gap: 16, overflowX: 'auto', alignItems: 'stretch' }}>
              {reading.map((b) => (
                <button key={b.id} className="shelf-card" onClick={() => setEditing(b.id)}>
                  <div style={{ width: 84, height: 126, flex: 'none' }}><BookCover book={b.data} /></div>
                  <div className="col" style={{ width: 180, gap: 6 }}>
                    <div className="clamp2" style={{ fontSize: 15, fontWeight: 600 }}>{b.data.title}</div>
                    <div className="secondary clamp1" style={{ fontSize: 12 }}>{b.data.author}</div>
                    <span className="spacer" />
                    <div className="secondary" style={{ fontSize: 11, fontWeight: 500 }}>
                      {Math.round((b.data.progress || 0) * 100)}%
                      {b.data.pageCount > 0 && ` · page ${Math.round((b.data.progress || 0) * b.data.pageCount)} of ${b.data.pageCount}`}
                    </div>
                    <div className="pbar"><div style={{ width: `${Math.max(3, (b.data.progress || 0) * 100)}%` }} /></div>
                    {active?.data.bookUUID === b.id
                      ? <span role="button" className="btn-soft" style={{ background: 'var(--canvas)', alignSelf: 'flex-start' }} onClick={(e) => { e.stopPropagation(); stopReading(active) }}><Square size={11} fill="currentColor" />Stop</span>
                      : <span role="button" className="btn-soft" style={{ background: 'var(--canvas)', alignSelf: 'flex-start' }} onClick={(e) => { e.stopPropagation(); startReading(b) }}><Timer size={13} />Start reading</span>}
                  </div>
                </button>
              ))}
            </div>
          </div>
        )}

        {library !== 'highlights' && <div className="col" style={{ gap: 14 }}>
          <div className="row" style={{ alignItems: 'baseline' }}>
            <h3 className="section-title">{shelfTitle}</h3>
            <span className="display muted" style={{ fontSize: 21, fontWeight: 500 }}>{visible.length}</span>
          </div>
          {visible.length === 0 && (
            <div className="col secondary" style={{ alignItems: 'center', padding: '50px 0', gap: 12 }}>
              <Library size={36} strokeWidth={1.2} />
              <div>{books.length === 0 ? 'Your shelf is empty. Add a book to get started.' : 'No books here yet.'}</div>
              {books.length === 0 && <button className="btn-soft" onClick={() => setAdding(true)}>Add book</button>}
            </div>
          )}
          <div className="book-grid">
            {visible.map((b) => (
              <button key={b.id} className="book-tile" onClick={() => setEditing(b.id)}>
                <div className="cv">
                  <BookCover book={b.data} />
                  {b.data.status !== 'toRead' && STATUS_BADGE[b.data.status] && (
                    <span className="badge" style={{ background: STATUS_BADGE[b.data.status] }}>{STATUS_ICON[b.data.status]}</span>
                  )}
                </div>
                <div className="clamp2" style={{ fontSize: 13, fontWeight: 600 }}>{b.data.title}</div>
                <div className="secondary clamp1" style={{ fontSize: 11 }}>{b.data.author}</div>
                {b.data.rating > 0 && <Stars rating={b.data.rating} size={10} />}
              </button>
            ))}
          </div>
        </div>}
      </section>

      <AddBookModal open={adding} onClose={() => setAdding(false)} books={books} categories={categories} defaultCategory={currentCategory} />
      {editingBook && <BookDetail book={editingBook} categories={categories} onClose={() => setEditing(null)} />}
      <CategoryEditor key={catEditor.cat?.id ?? 'new'} open={catEditor.open} cat={catEditor.cat} all={categories} books={books}
        onClose={() => setCatEditor({ open: false })} onDelete={(c) => { deleteCategory(c); setCatEditor({ open: false }) }} />
    </div>
  )
}

// MARK: - Pieces

function FilterRow({ title, icon, count, on, tint, onClick, onDoubleClick }: {
  title: string; icon: ReactNode; count: number; on: boolean; tint?: string; onClick: () => void; onDoubleClick?: () => void
}) {
  return (
    <button className={`rfilter ${on ? 'on' : ''}`} onClick={onClick} onDoubleClick={onDoubleClick}>
      <span className="ic" style={{ background: tint ?? 'transparent', color: tint ? 'var(--sticker-ink)' : undefined }}>{icon}</span>
      <span className="clamp1" style={{ textAlign: 'left' }}>{title}</span>
      <span className="spacer" />
      {count > 0 && <span className="count">{count}</span>}
    </button>
  )
}

function GoalTile({ done, goal, year }: { done: number; goal: number; year: number }) {
  const ratio = Math.min(done / Math.max(goal, 1), 1)
  const r = 19, c = 2 * Math.PI * r
  const setGoal = (g: number) => store.setSetting('readingGoal', Math.max(1, Math.min(365, g)))
  return (
    <div className="rstat row" style={{ background: 'var(--pink)', gap: 14 }}>
      <svg width="44" height="44" viewBox="0 0 44 44" style={{ flex: 'none' }}>
        <circle cx="22" cy="22" r={r} fill="none" stroke="rgba(0,0,0,0.12)" strokeWidth="6" />
        <circle cx="22" cy="22" r={r} fill="none" stroke="#111" strokeWidth="6" strokeLinecap="round"
          strokeDasharray={`${c * ratio} ${c}`} transform="rotate(-90 22 22)" />
      </svg>
      <div style={{ minWidth: 0 }}>
        <div className="v">{done}/{goal}</div>
        <div className="row" style={{ gap: 6 }}>
          <span className="l">{year} goal</span>
          <button className="ring-step" title="Lower goal" onClick={() => setGoal(goal - 1)}><Minus size={11} /></button>
          <button className="ring-step" title="Raise goal" onClick={() => setGoal(goal + 1)}><Plus size={11} /></button>
        </div>
      </div>
    </div>
  )
}

function LibraryTabs({ books, highlights, value, onChange }: { books: Rec<Book>[]; highlights: number; value: string | null; onChange: (v: string | null) => void }) {
  const tabs: { key: string | null; title: string; icon: ReactNode; color: string }[] = [
    { key: null, title: 'All', icon: <Library size={12} />, color: 'transparent' },
    { key: 'goodreads', title: 'Goodreads', icon: <span style={{ fontWeight: 800, fontSize: 12 }}>g</span>, color: 'var(--peach)' },
    { key: 'kindle', title: 'Kindle', icon: <Flame size={12} />, color: 'var(--cyan)' },
    { key: 'apple-books', title: 'Books', icon: <BookOpen size={12} />, color: 'var(--orange)' },
    { key: 'mine', title: 'Added by me', icon: <User size={12} />, color: 'var(--mint)' },
    { key: 'highlights', title: 'Highlights', icon: <Highlighter size={12} />, color: 'var(--lime)' },
  ]
  return (
    <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
      {tabs.map((t) => {
        const count = t.key === 'highlights' ? highlights : t.key === null ? books.length : books.filter((b) => inLibrary(b.data, t.key!)).length
        if (t.key !== null && t.key !== 'highlights' && count === 0) return null
        const on = value === t.key
        return (
          <button key={t.title} className={`libtab ${on ? 'on' : ''}`} onClick={() => onChange(t.key)}>
            <span className="ic" style={{ background: t.color, color: t.key === null ? 'inherit' : undefined }}>{t.icon}</span>
            {t.title}<span className="n">{count}</span>
          </button>
        )
      })}
    </div>
  )
}

function CategoryChips({ categories, selected, onToggle }: { categories: Rec<BookCategory>[]; selected: string[]; onToggle: (name: string) => void }) {
  return (
    <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
      {categories.map((c) => {
        const on = selected.includes(c.data.name)
        return (
          <span key={c.id} className="chip" style={{ background: paletteColor(c.data.colorIndex), opacity: on ? 1 : 0.3 }}
            onClick={() => onToggle(c.data.name)}>{categoryIcon(c.data.symbol, 11)}{c.data.name}</span>
        )
      })}
    </div>
  )
}

// MARK: - Book detail

function BookDetail({ book, categories, onClose }: { book: Rec<Book>; categories: Rec<BookCategory>[]; onClose: () => void }) {
  const b = book.data
  const set = (patch: Partial<Book>) => store.update<Book>(book.id, patch)
  const setStatus = (s: ReadingStatus) => {
    const patch: Partial<Book> = { status: s }
    if (s === 'reading' && !b.startedAt) patch.startedAt = iso(new Date())
    if (s === 'read') { if (!b.finishedAt) patch.finishedAt = iso(new Date()); patch.progress = 1 }
    set(patch)
  }
  const sourceLabel: Record<string, string> = {
    goodreads: 'From Goodreads', 'apple-books': 'From Apple Books', kindle: 'From Kindle', openlibrary: 'From Open Library',
  }
  const dateField = (label: string, value: string | null, key: 'startedAt' | 'finishedAt') => (
    <label className="row" style={{ gap: 12 }}>
      <span className="secondary" style={{ width: 70 }}>{label}</span>
      <input type="date" className="field" style={{ width: 170 }} value={toDateInput(parse(value) ?? new Date())}
        onChange={(e) => e.target.value && set({ [key]: iso(fromInputs(e.target.value, '12:00')) } as Partial<Book>)} />
    </label>
  )
  return (
    <Modal open onClose={onClose} width={660}>
      <div className="row" style={{ alignItems: 'flex-start', gap: 26 }}>
        <div className="col" style={{ alignItems: 'center', gap: 12, flex: 'none' }}>
          <div style={{ width: 150, height: 225 }}><BookCover book={b} /></div>
          <Stars rating={b.rating} size={16} onChange={(r) => set({ rating: r })} />
          <div className="muted" style={{ fontSize: 11 }}>{sourceLabel[b.source] ?? 'Added by you'}</div>
        </div>
        <div className="col" style={{ flex: 1, gap: 14, minWidth: 0 }}>
          <input className="plain display" style={{ fontSize: 24 }} value={b.title} onChange={(e) => set({ title: e.target.value })} />
          <input className="plain secondary" style={{ fontSize: 15 }} value={b.author} placeholder="Author" onChange={(e) => set({ author: e.target.value })} />
          <Segmented options={READING_STATUS.map((s) => ({ id: s.id, label: s.title }))} value={b.status} onChange={setStatus} />
          {b.status === 'reading' && (
            <div className="col" style={{ gap: 4 }}>
              <span style={{ fontSize: 12, fontWeight: 600 }}>Progress {Math.round((b.progress || 0) * 100)}%</span>
              <input type="range" min={0} max={1} step={0.01} value={b.progress || 0} onChange={(e) => set({ progress: Number(e.target.value) })} />
            </div>
          )}
          <div className="col" style={{ gap: 10, fontSize: 13 }}>
            <label className="row" style={{ gap: 12 }}>
              <span className="secondary" style={{ width: 70 }}>Pages</span>
              <input type="number" className="field" style={{ width: 100 }} value={b.pageCount || ''} min={0}
                onChange={(e) => set({ pageCount: Math.max(0, Number(e.target.value) || 0) })} />
            </label>
            {b.status !== 'toRead' && dateField('Started', b.startedAt, 'startedAt')}
            {b.status === 'read' && dateField('Finished', b.finishedAt, 'finishedAt')}
          </div>
          <div style={{ fontSize: 12, fontWeight: 600 }} className="muted">Categories</div>
          {categories.length === 0
            ? <EmptyHint text="Create categories from the Reading sidebar." />
            : <CategoryChips categories={categories} selected={b.categories ?? []} onToggle={(name) => {
                const cur = b.categories ?? []
                set({ categories: cur.includes(name) ? cur.filter((x) => x !== name) : [...cur, name] })
              }} />}
          <BookExtras book={book} />
          <div style={{ fontSize: 12, fontWeight: 600 }} className="muted">Notes & highlights</div>
          <textarea className="field" rows={5} style={{ fontFamily: 'var(--display)', fontSize: 14 }} value={b.notes ?? ''}
            onChange={(e) => set({ notes: e.target.value })} />
          <div className="row">
            <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(book.id); onClose() }}>Delete</button>
            <span className="spacer" />
            <button className="btn-primary" style={{ width: 110 }} onClick={onClose}>Done</button>
          </div>
        </div>
      </div>
    </Modal>
  )
}

/** Reading time, the timer button, and this book's highlights. */
function BookExtras({ book }: { book: Rec<Book> }) {
  const active = useActiveSession()
  const sessions = useRecords<ReadingSession>('readingSession')
  const all = useRecords<Highlight>('highlight')
  const mine = all.filter((h) => h.data.bookUUID === book.id || (h.data.bookTitle ?? '').toLowerCase() === (book.data.title ?? '').toLowerCase())
    .sort((a, b) => (a.data.createdAt ?? '').localeCompare(b.data.createdAt ?? ''))
  const minutes = Math.floor(sessions.filter((s) => s.data.bookUUID === book.id).reduce((n, s) => n + sessionMinutes(s.data), 0))
  return (
    <>
      <div className="row">
        <span className="row secondary" style={{ gap: 6, fontSize: 12 }}><Timer size={13} />
          {minutes === 0 ? 'No reading time yet' : minutes < 60 ? `${minutes} min read` : `${(minutes / 60).toFixed(1)} h read`}</span>
        <span className="spacer" />
        {active?.data.bookUUID === book.id
          ? <button className="btn-soft" onClick={() => stopReading(active)}><Square size={11} fill="currentColor" />Stop reading</button>
          : <button className="btn-soft" onClick={() => startReading(book)}><Timer size={13} />Start reading</button>}
      </div>
      {mine.length > 0 && (
        <>
          <div style={{ fontSize: 12, fontWeight: 600 }} className="muted">Highlights ({mine.length})</div>
          <div className="col scroll" style={{ gap: 6, maxHeight: 180 }}>{mine.map((h) => <HighlightRow key={h.id} h={h} />)}</div>
        </>
      )}
    </>
  )
}

// MARK: - Highlights

function HighlightsList({ highlights }: { highlights: Rec<Highlight>[] }) {
  const [query, setQuery] = useState('')
  const [message, setMessage] = useState('')
  const input = useRef<HTMLInputElement>(null)
  const q = query.trim().toLowerCase()
  const filtered = highlights.filter((h) => !q || h.data.text.toLowerCase().includes(q) || h.data.bookTitle.toLowerCase().includes(q))
    .sort((a, b) => (b.data.createdAt ?? '').localeCompare(a.data.createdAt ?? ''))
  const groups = new Map<string, Rec<Highlight>[]>()
  for (const h of filtered) groups.set(h.data.bookTitle, [...(groups.get(h.data.bookTitle) ?? []), h])
  const grouped = [...groups].sort((a, b) => a[0].localeCompare(b[0]))

  const onFile = async (file: File | undefined) => {
    if (!file) return
    try {
      const items = await parseKindleFile(file)
      const source = file.name.toLowerCase().endsWith('.txt') ? 'kindle-clippings' : 'kindle-notebook'
      const [added, skipped] = importHighlights(items, source)
      setMessage(`Imported ${added} highlight${added === 1 ? '' : 's'}${skipped > 0 ? ` (${skipped} already here).` : '.'}`)
    } catch (e) {
      setMessage((e as Error).message)
    }
    if (input.current) input.current.value = ''
  }

  return (
    <div className="col" style={{ gap: 16 }}>
      <div className="row" style={{ gap: 10 }}>
        <h3 className="section-title">Highlights</h3>
        <span className="display muted" style={{ fontSize: 21, fontWeight: 500 }}>{highlights.length}</span>
        <span className="spacer" />
        <div className="row" style={{ background: 'var(--card)', borderRadius: 999, padding: '8px 12px', gap: 6 }}>
          <Search size={14} color="var(--ink3)" />
          <input className="plain" style={{ width: 160 }} placeholder="Search highlights" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        <button className="btn-soft" onClick={() => input.current?.click()}><Download size={14} />Import Kindle highlights…</button>
        <input ref={input} type="file" accept=".txt,.html,.htm,text/plain,text/html" style={{ display: 'none' }} onChange={(e) => onFile(e.target.files?.[0])} />
      </div>
      {message && <div style={{ fontSize: 12, fontWeight: 500 }}>{message}</div>}
      {highlights.length === 0 && (
        <div className="card col" style={{ gap: 8, fontSize: 13 }}>
          <strong style={{ fontSize: 14 }}>Bring in your Kindle highlights and notes:</strong>
          <div>• <b>Kindle e-reader:</b> plug it in with USB, open it in File Explorer, and import <b>documents › My Clippings.txt</b>.</div>
          <div>• <b>Kindle app on iPhone, iPad or Android:</b> open a book › Notebook › Share › <b>Export notebook</b>, send the file to this PC, and import it.</div>
          <div className="muted">Orbit matches highlights to the books in your library and skips ones it already has.</div>
        </div>
      )}
      {grouped.map(([title, items]) => (
        <div key={title} className="card col" style={{ gap: 10, padding: 16 }}>
          <div className="row">
            <strong style={{ fontSize: 16 }}>{title}</strong>
            {items[0]?.data.author && <span className="secondary" style={{ fontSize: 12 }}>{items[0].data.author}</span>}
            <span className="spacer" />
            <span className="muted" style={{ fontSize: 12, fontWeight: 600 }}>{items.length}</span>
          </div>
          {items.map((h) => <HighlightRow key={h.id} h={h} />)}
        </div>
      ))}
    </div>
  )
}

function HighlightRow({ h }: { h: Rec<Highlight> }) {
  const [copied, setCopied] = useState(false)
  const copy = () => {
    navigator.clipboard.writeText(`“${h.data.text}” — ${h.data.bookTitle}`).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1500) })
  }
  return (
    <div className="hl-row">
      <span className="bar" />
      <div className="col" style={{ gap: 6, flex: 1, minWidth: 0 }}>
        <div className="display" style={{ fontSize: 15, fontWeight: 500, userSelect: 'text', whiteSpace: 'pre-wrap' }}>{h.data.text}</div>
        {h.data.note && <div className="row secondary" style={{ gap: 6, fontSize: 12, alignItems: 'flex-start' }}><StickyNote size={12} style={{ marginTop: 2, flex: 'none' }} />{h.data.note}</div>}
        {h.data.location && <div className="muted" style={{ fontSize: 10, textTransform: 'capitalize' }}>{h.data.location.toLowerCase()}</div>}
      </div>
      <div className="hl-actions">
        <button title="Copy" onClick={copy}>{copied ? <Check size={13} /> : <Copy size={13} />}</button>
        <button title="Delete" onClick={() => store.remove(h.id)}><Trash2 size={13} /></button>
      </div>
    </div>
  )
}

// MARK: - Add book

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

function AddBookModal({ open, onClose, books, categories, defaultCategory }: {
  open: boolean; onClose: () => void; books: Rec<Book>[]; categories: Rec<BookCategory>[]; defaultCategory?: string
}) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<OLResult[]>([])
  const [searching, setSearching] = useState(false)
  const [error, setError] = useState('')
  const [status, setStatus] = useState<ReadingStatus>('toRead')
  const [picked, setPicked] = useState<string[] | null>(null)
  const [title, setTitle] = useState('')
  const [author, setAuthor] = useState('')
  const [added, setAdded] = useState('')
  const chosen = picked ?? (defaultCategory ? [defaultCategory] : [])

  const search = async () => {
    const q = query.trim()
    if (!q) return
    setSearching(true); setError('')
    try {
      const r = await searchOpenLibrary(q)
      setResults(r)
      if (!r.length) setError('No matches. Add it by hand below.')
    } catch (e) {
      setError(`Search failed: ${String(e)}`)
    }
    setSearching(false)
  }

  const insert = (b: { title: string; author: string; isbn?: string; pages?: number; year?: number; coverURL?: string; externalID?: string }, source: string) => {
    const key = matchKey(b.title, b.author)
    const existing = books.find((x) => (b.externalID && x.data.externalID === b.externalID) || matchKey(x.data.title, x.data.author) === key)
    if (existing) {
      const cats = [...new Set([...(existing.data.categories ?? []), ...chosen])]
      store.update<Book>(existing.id, { categories: cats })
      setAdded(`“${existing.data.title}” is already in your library.`)
      return
    }
    const now = iso(new Date())
    const book: Book = {
      title: b.title.trim(), author: b.author.trim(), status, rating: 0, categories: chosen, notes: '',
      coverURL: b.coverURL || (b.isbn ? `https://covers.openlibrary.org/b/isbn/${b.isbn}-M.jpg?default=false` : ''),
      isbn: b.isbn ?? '', pageCount: b.pages ?? 0, progress: status === 'read' ? 1 : 0, year: b.year ?? 0,
      addedAt: now, startedAt: status === 'reading' || status === 'read' ? now : null, finishedAt: status === 'read' ? now : null,
      source, sources: [source], externalID: b.externalID ?? '',
    }
    store.create<Book>('book', book)
    setAdded(`Added “${book.title}”.`)
  }

  const close = () => { setResults([]); setQuery(''); setError(''); setAdded(''); setPicked(null); onClose() }

  return (
    <Modal open={open} onClose={close} width={600}>
      <div className="col" style={{ gap: 16 }}>
        <h2 className="display" style={{ fontSize: 28, margin: 0 }}>Add a book</h2>
        <div className="row" style={{ background: 'var(--card)', borderRadius: 12, padding: '10px 12px' }}>
          <Search size={15} color="var(--ink3)" />
          <input className="plain" autoFocus placeholder="Search by title, author or ISBN" value={query}
            onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && search()} />
          {searching && <span className="muted" style={{ fontSize: 12 }}>Searching…</span>}
        </div>
        <Segmented options={READING_STATUS.map((s) => ({ id: s.id, label: s.title }))} value={status} onChange={setStatus} />
        {categories.length > 0 && (
          <CategoryChips categories={categories} selected={chosen}
            onToggle={(n) => setPicked(chosen.includes(n) ? chosen.filter((x) => x !== n) : [...chosen, n])} />
        )}
        <div className="col scroll" style={{ height: 300, gap: 8 }}>
          {error && <div style={{ color: 'var(--critical)', fontSize: 12 }}>{error}</div>}
          {results.map((r) => (
            <div key={r.key} className="ol-result">
              {r.coverURL ? <img src={r.coverURL} alt="" /> : <span className="noimg" />}
              <div style={{ minWidth: 0, flex: 1 }}>
                <div className="clamp2" style={{ fontSize: 14, fontWeight: 600 }}>{r.title}</div>
                <div className="secondary clamp1" style={{ fontSize: 12 }}>
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
        <div className="muted" style={{ fontSize: 12, fontWeight: 600 }}>Or add it by hand</div>
        <div className="row">
          <input className="field" placeholder="Title" value={title} onChange={(e) => setTitle(e.target.value)} />
          <input className="field" placeholder="Author" value={author} onChange={(e) => setAuthor(e.target.value)} />
          <button className="btn-soft" disabled={!title.trim()} onClick={() => { insert({ title, author }, 'manual'); setTitle(''); setAuthor('') }}>Add</button>
        </div>
        <div className="row">
          {added && <span className="secondary" style={{ fontSize: 12 }}>{added}</span>}
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120 }} onClick={close}>Done</button>
        </div>
      </div>
    </Modal>
  )
}

// MARK: - Category editor

function CategoryEditor({ open, cat, all, books, onClose, onDelete }: {
  open: boolean; cat?: Rec<BookCategory>; all: Rec<BookCategory>[]; books: Rec<Book>[]; onClose: () => void; onDelete: (c: Rec<BookCategory>) => void
}) {
  const [name, setName] = useState(cat?.data.name ?? '')
  const [color, setColor] = useState(cat?.data.colorIndex ?? all.length % PALETTE.length)
  const [symbol, setSymbol] = useState(cat?.data.symbol ?? 'tag.fill')
  const trimmed = name.trim()
  const valid = !!trimmed && !all.some((c) => c.id !== cat?.id && c.data.name.toLowerCase() === trimmed.toLowerCase())

  const save = () => {
    if (!valid) return
    if (cat) {
      const old = cat.data.name
      if (old !== trimmed) {
        for (const b of books) {
          if ((b.data.categories ?? []).includes(old)) store.update<Book>(b.id, { categories: b.data.categories.map((x) => (x === old ? trimmed : x)) })
        }
      }
      store.update<BookCategory>(cat.id, { name: trimmed, colorIndex: color, symbol })
    } else {
      store.create<BookCategory>('bookCategory', { name: trimmed, colorIndex: color, symbol, createdAt: iso(new Date()) })
    }
    onClose()
  }

  return (
    <Modal open={open} onClose={onClose} width={420}>
      <div className="col" style={{ gap: 16 }}>
        <h2 className="display" style={{ fontSize: 26, margin: 0 }}>{cat ? 'Edit category' : 'New category'}</h2>
        <input className="field" autoFocus placeholder="e.g. Philosophy, Book club, Favourites" value={name}
          onChange={(e) => setName(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && save()} />
        <div className="row" style={{ gap: 8 }}>
          {PALETTE.map((p, i) => (
            <button key={p} onClick={() => setColor(i)} title="Colour"
              style={{ width: 28, height: 28, borderRadius: '50%', background: p, outline: color === i ? '2px solid var(--ink)' : 'none', outlineOffset: 1 }} />
          ))}
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(8, 38px)', gap: 8 }}>
          {CATEGORY_ICONS.map((c) => (
            <button key={c.id} onClick={() => setSymbol(c.id)}
              style={{ width: 36, height: 36, borderRadius: '50%', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                background: symbol === c.id ? paletteColor(color) : 'var(--card)', color: symbol === c.id ? 'var(--sticker-ink)' : 'var(--ink)' }}>
              {c.icon(15)}
            </button>
          ))}
        </div>
        <div className="row">
          {cat
            ? <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => onDelete(cat)}>Delete</button>
            : <button className="btn-soft" onClick={onClose}>Cancel</button>}
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120 }} disabled={!valid} onClick={save}>{cat ? 'Save' : 'Create'}</button>
        </div>
      </div>
    </Modal>
  )
}
