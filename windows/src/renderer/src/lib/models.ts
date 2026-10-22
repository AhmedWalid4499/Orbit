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

/** Same match key as the Mac (Book.matchKey): title before ":" or "(", plus the author's last word. */
export function matchKey(title: string, author: string): string {
  const t = (title.toLowerCase().split(/[:(]/)[0] ?? '').trim()
  const words = author.toLowerCase().split(' ').filter(Boolean)
  return `${t}|${words[words.length - 1] ?? ''}`
}

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

/** Session length in minutes (an open session counts up to now), same as the Mac's ReadingSession.minutes. */
export const sessionMinutes = (s: ReadingSession, now = new Date()): number => {
  const start = new Date(s.start).getTime(), end = s.end ? new Date(s.end).getTime() : now.getTime()
  return isNaN(start) || isNaN(end) ? 0 : (end - start) / 60_000
}

// MARK: Subscriptions

export type BillingCycle = 'weekly' | 'monthly' | 'quarterly' | 'yearly'
export const BILLING_CYCLES: BillingCycle[] = ['weekly', 'monthly', 'quarterly', 'yearly']
/** How many charges per month, for monthly totals (BillingCycle.perMonth on the Mac). */
export const PER_MONTH: Record<BillingCycle, number> = { weekly: 52 / 12, monthly: 1, quarterly: 1 / 3, yearly: 1 / 12 }

/** kind "subscription": a recurring charge, found in transactions or email, or added by hand. Same fields as the Mac encoder in CloudSync.swift. */
export interface Subscription {
  name: string
  /** Per charge, in your home currency. */
  amount: number
  originalAmount: number
  originalCurrency: string
  cycle: BillingCycle
  nextDate: string | null
  lastCharged: string | null
  category: string
  /** active, trial, cancelled */
  status: 'active' | 'trial' | 'cancelled'
  trialEnds: string | null
  /** Set when a charge comes in at a different price. */
  previousAmount: number
  priceChangedAt: string | null
  /** manual, detected (from transactions), email */
  source: string
  notes: string
  createdAt: string | null
}
export const monthlyCost = (s: Subscription): number =>
  s.status === 'cancelled' ? 0 : (Number(s.amount) || 0) * (PER_MONTH[s.cycle] ?? 1)
export const priceWentUp = (s: Subscription): boolean => s.previousAmount > 0 && s.amount > s.previousAmount * 1.01

// MARK: Documents

export type DocKind = 'passport' | 'id' | 'license' | 'visa' | 'car' | 'insurance' | 'warranty' | 'membership' | 'other'
export const DOC_KINDS: { id: DocKind; title: string; color: string }[] = [
  { id: 'passport', title: 'Passport', color: 'var(--cyan)' },
  { id: 'id', title: 'ID card', color: 'var(--purple)' },
  { id: 'license', title: 'Driving licence', color: 'var(--orange)' },
  { id: 'visa', title: 'Visa', color: 'var(--pink)' },
  { id: 'car', title: 'Car registration', color: 'var(--peach)' },
  { id: 'insurance', title: 'Insurance', color: 'var(--mint)' },
  { id: 'warranty', title: 'Warranty', color: 'var(--lime)' },
  { id: 'membership', title: 'Membership', color: 'var(--purple)' },
  { id: 'other', title: 'Other', color: 'var(--card-hover)' },
]
export const docKind = (k: string) => DOC_KINDS.find((d) => d.id === k) ?? DOC_KINDS[DOC_KINDS.length - 1]

/** kind "document": something with an expiry date (passport, ID, licence, insurance, a warranty…). Same fields as the Mac's DocItem. */
export interface Doc {
  title: string
  kind: DocKind
  /** Keep this short (e.g. last 4 digits); Orbit isn't a password manager. */
  number: string
  issuer: string
  issued: string | null
  expires: string | null
  /** Remind this many days before it expires. */
  remindDays: number
  notes: string
  /** manual, email */
  source: string
  /** Gmail message id for warranties found in email (avoids duplicates). */
  sourceID: string
  createdAt: string | null
}

// MARK: Focus, plans, trips

/** kind "focusSession": a focus timer run (Mac FocusSession). `end` is null while it's running. */
export interface FocusSession {
  /** Id of the task record being focused on, or "" for none. */
  taskUUID: string
  taskTitle: string
  start: string
  end: string | null
  plannedMinutes: number
}

/** kind "dayPlan": the evening plan for a day (Mac DayPlan). */
export interface DayPlan {
  /** "yyyy-MM-dd": the day the plan is for (tomorrow, when made in the evening). */
  day: string
  /** Up to 3 top priorities, in order. */
  top: string[]
  /** Parallel to `top`: the linked task's id, or "" for a typed-in item. */
  taskUUIDs: string[]
  note: string
  createdAt: string | null
}

/** kind "trip": a planned trip (Mac Trip). */
export interface Trip {
  title: string
  destination: string
  start: string | null
  end: string | null
  /** Id of the `bucket` record it came from, or "". */
  bucketUUID: string
  /** Home currency; 0 = no budget. */
  budget: number
  notes: string
  packing: string[]
  /** The subset of `packing` that's packed. */
  packed: string[]
  createdAt: string | null
}

export type BookingKind = 'flight' | 'hotel' | 'train' | 'car' | 'activity' | 'other'
export const BOOKING_KINDS: { id: BookingKind; title: string; color: string }[] = [
  { id: 'flight', title: 'Flight', color: 'var(--cyan)' },
  { id: 'hotel', title: 'Hotel', color: 'var(--purple)' },
  { id: 'train', title: 'Train', color: 'var(--orange)' },
  { id: 'car', title: 'Car', color: 'var(--peach)' },
  { id: 'activity', title: 'Activity', color: 'var(--pink)' },
  { id: 'other', title: 'Other', color: 'var(--mint)' },
]
export const bookingKind = (k: string) => BOOKING_KINDS.find((b) => b.id === k) ?? BOOKING_KINDS[BOOKING_KINDS.length - 1]

/** kind "booking": a flight, hotel, train… (Mac Booking). Found in email by the Mac or added by hand. */
export interface Booking {
  /** Id of the `trip` record, or "" when not assigned yet. */
  tripUUID: string
  kind: BookingKind
  title: string
  provider: string
  confirmation: string
  location: string
  start: string | null
  end: string | null
  /** Positive, home currency. */
  amount: number
  /** manual, email */
  source: string
  sourceID: string
  createdAt: string | null
}
