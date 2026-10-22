// Field names match what the Mac app writes (CloudSync.swift), so both apps read the same items.

export type Area = 'health' | 'work' | 'study' | 'money' | 'home' | 'social' | 'personal'
export const AREAS: Area[] = ['health', 'work', 'study', 'money', 'home', 'social', 'personal']
export const AREA_COLOR: Record<Area, string> = {
  health: 'var(--pink)', work: 'var(--cyan)', study: 'var(--lime)', money: 'var(--orange)',
  home: 'var(--purple)', social: 'var(--mint)', personal: 'var(--peach)',
}
export const areaOf = (s: string | undefined): Area => (AREAS.includes(s as Area) ? (s as Area) : 'personal')
export const cap = (s: string): string => (s ? s[0].toUpperCase() + s.slice(1) : s)

export type Repeat = 'none' | 'daily' | 'weekly' | 'monthly'

export interface Task {
  title: string
  notes: string
  area: Area
  due: string | null // ISO date-time
  priority: number // 0-3
  isDone: boolean
  completedAt: string | null
  createdAt: string | null
  repeat: Repeat
}

export interface CalEvent {
  title: string
  start: string
  end: string
  area: Area
  location: string
  notes: string
}

export interface Habit {
  name: string
  symbol: string // SF Symbol name on the Mac
  area: Area
  targetPerWeek: number
  createdAt: string | null
  doneDays: string[] // "yyyy-MM-dd" in local time
}

export interface Txn {
  title: string
  amount: number // negative = expense
  category: string
  date: string
  isRecurring: boolean
  source: string // "" or "gmail:<address>"
  sourceID: string
  originalAmount: number
  originalCurrency: string
}
export const MONEY_CATEGORIES = ['Food', 'Transport', 'Bills', 'Shopping', 'Health', 'Fun', 'Subscriptions', 'Income', 'General']

export interface Note {
  title: string
  body: string
  createdAt: string | null
  updatedAt: string | null
  isJournal: boolean
  pinned: boolean
  mood: number // 0 unset, 1-5
  moodSetByUser: boolean
  chat?: string | null // Mac-only journal chat, kept as is
}
export const MOOD_FACES = ['', '😞', '😕', '😐', '🙂', '😄']
export const MOOD_WORDS = ['', 'Rough', 'Low', 'Okay', 'Good', 'Great']

export type ReadingStatus = 'reading' | 'toRead' | 'read' | 'dnf'
export const READING_STATUS: { id: ReadingStatus; title: string }[] = [
  { id: 'reading', title: 'Reading' }, { id: 'toRead', title: 'To read' }, { id: 'read', title: 'Read' }, { id: 'dnf', title: "Didn't finish" },
]

export interface Book {
  title: string
  author: string
  status: ReadingStatus
  rating: number
  categories: string[]
  notes: string
  coverURL: string
  isbn: string
  pageCount: number
  progress: number // 0-1
  year: number
  addedAt: string | null
  startedAt: string | null
  finishedAt: string | null
  source: string // manual, openlibrary, goodreads, apple-books, kindle
  sources: string[]
  externalID: string
}
export const IMPORTED_SOURCES = ['goodreads', 'apple-books', 'kindle']

export interface BookCategory {
  name: string
  colorIndex: number
  symbol: string
  createdAt: string | null
}
export const PALETTE = ['var(--pink)', 'var(--lime)', 'var(--orange)', 'var(--purple)', 'var(--cyan)', 'var(--mint)', 'var(--peach)']
export const paletteColor = (i: number): string => PALETTE[((i % PALETTE.length) + PALETTE.length) % PALETTE.length]

export type BucketKind = 'travel' | 'experience' | 'adventure' | 'learn' | 'create' | 'people' | 'other'
export const BUCKET_KINDS: { id: BucketKind; title: string; color: string }[] = [
  { id: 'travel', title: 'Travel', color: 'var(--cyan)' },
  { id: 'experience', title: 'Experience', color: 'var(--pink)' },
  { id: 'adventure', title: 'Adventure', color: 'var(--orange)' },
  { id: 'learn', title: 'Learn', color: 'var(--lime)' },
  { id: 'create', title: 'Create', color: 'var(--purple)' },
  { id: 'people', title: 'People', color: 'var(--mint)' },
  { id: 'other', title: 'Other', color: 'var(--peach)' },
]
export const bucketKind = (k: string) => BUCKET_KINDS.find((b) => b.id === k) ?? BUCKET_KINDS[6]

export interface Bucket {
  title: string
  notes: string
  kind: BucketKind
  targetDate: string | null
  excitement: number // 1-3
  isDone: boolean
  doneAt: string | null
  createdAt: string | null
}

/** kind "readingSession": time spent reading (Mac reading timer). Same field names as the Mac encoder in CloudSync.swift. */
export interface ReadingSession {
  bookUUID: string
  bookTitle: string
  start: string
  end: string | null
  pagesRead: number
}

/** kind "highlight": a passage highlighted in a book (Kindle import or added by hand). */
export interface Highlight {
  bookUUID: string
  bookTitle: string
  author: string
  text: string
  note: string
  location: string
  createdAt: string
  /** kindle-clippings, kindle-notebook, kindle-app, manual */
  source: string
  externalID: string
}
