// Goodreads updates, the Android side of GoodreadsSync.swift (Mac and iPhone): Joshu sends your reading back to
// Goodreads: progress, shelf (reading / read) and your review with stars. Goodreads closed its public API in 2020, so
// Joshu does what you'd do on the website: you sign in to Goodreads once inside Joshu (GoodreadsPlugin.java shows
// Goodreads' own sign-in page), and Joshu then posts through that sign-in from a hidden browser. Nothing opens in
// front of you. If Goodreads changes its website this can stop working; Joshu then says so instead of failing quietly.
import { useSyncExternalStore } from 'react'
import { Capacitor, registerPlugin } from '@capacitor/core'
import { store, Rec } from '@/lib/store'
import { Book, matchKey } from '@/lib/models'

interface GoodreadsNative {
  signIn(): Promise<{ signedIn: boolean }>
  signOut(): Promise<void>
  load(o: { url: string }): Promise<{ url: string | null }>
  run(o: { script: string; args: Record<string, unknown> }): Promise<{ value: unknown }>
  fetchText(o: { url: string }): Promise<{ status: number; text: string }>
  hasCookies(): Promise<{ present: boolean }>
}

const plugin = registerPlugin<GoodreadsNative>('Goodreads')
const isNative = Capacitor.isNativePlatform()

export const SIGN_IN_URL = 'https://www.goodreads.com/user/sign_in'

// MARK: State (UserDefaults keys on the Mac → localStorage here)

const read = <T,>(key: string, fallback: T): T => {
  try { const s = localStorage.getItem(key); return s == null ? fallback : (JSON.parse(s) as T) } catch { return fallback }
}
const write = (key: string, value: unknown): void => {
  try { localStorage.setItem(key, JSON.stringify(value)) } catch { /* private mode */ }
}

export interface GoodreadsState {
  signedIn: boolean
  /** Push progress automatically when it changes in Joshu (on by default once signed in). */
  autoProgress: boolean
  status: string | null
  busy: boolean
}

let state: GoodreadsState = {
  signedIn: read('goodreads.signedIn', false),
  autoProgress: read('goodreads.autoProgress', true),
  status: null,
  busy: false,
}
const subs = new Set<() => void>()
const set = (patch: Partial<GoodreadsState>): void => { state = { ...state, ...patch }; subs.forEach((f) => f()) }

export function getGoodreads(): GoodreadsState { return state }
export function subscribeGoodreads(f: () => void): () => void { subs.add(f); return () => { subs.delete(f) } }
export function useGoodreads(): GoodreadsState { return useSyncExternalStore(subscribeGoodreads, getGoodreads) }

/** Goodreads book IDs found for your books, by Joshu book. */
const ids = (): Record<string, string> => read('goodreads.ids', {})
/** Last progress sent per book, so the same number isn't posted twice. */
const sent = (): Record<string, number> => read('goodreads.sent', {})

function markSignedIn(on: boolean): void {
  write('goodreads.signedIn', on)
  set({ signedIn: on })
}

export function setAutoProgress(on: boolean): void {
  write('goodreads.autoProgress', on)
  set({ autoProgress: on })
}

const keyOf = (b: Rec<Book>): string => b.id || matchKey(b.data.title, b.data.author)

// MARK: Signing in and out

/** Shows Goodreads' sign-in page; it closes by itself once you're in. */
export async function signIn(): Promise<boolean> {
  if (!isNative) { set({ status: 'Goodreads sign-in works in the Android app.' }); return false }
  const { signedIn } = await plugin.signIn()
  if (signedIn) { markSignedIn(true); set({ status: null }) }
  return signedIn
}

export async function signOut(): Promise<void> {
  if (isNative) await plugin.signOut().catch(() => undefined)
  markSignedIn(false)
  set({ status: null })
}

// MARK: What Joshu sends

// One page at a time in the hidden browser: two updates mustn't load pages over each other.
let queue: Promise<unknown> = Promise.resolve()
function serial<T>(job: () => Promise<T>): Promise<T> {
  const next = queue.then(job, job)
  queue = next.catch(() => undefined)
  return next
}

const pending = new Map<string, ReturnType<typeof setTimeout>>()

/** Sends progress a few seconds after it stops changing (dragging the slider sends once, not fifty times). */
export function schedule(book: Rec<Book>): void {
  if (!state.signedIn || !state.autoProgress) return
  const key = keyOf(book)
  const t = pending.get(key)
  if (t) clearTimeout(t)
  pending.set(key, setTimeout(() => {
    pending.delete(key)
    const latest = store.get<Book>(book.id) ?? book
    void pushProgress(latest)
  }, 4000))
}

/** `schedule` for a book id (e.g. after the "What page are you on?" prompt saves). */
export function scheduleById(id: string): void {
  const b = store.get<Book>(id)
  if (b) schedule(b)
}

const shelf = (b: Book): string => (b.status === 'read' ? 'read' : b.status === 'reading' ? 'currently-reading' : 'to-read')

function signedOutMessage(): string {
  markSignedIn(false)
  return 'Your Goodreads sign-in ran out. Sign in again in Settings › Connections › Goodreads.'
}

/** Your progress on `book` (and its shelf), when it changed since last time. */
export function pushProgress(book: Rec<Book>, force = false): Promise<string> {
  return serial(async () => {
    if (!state.signedIn) return 'Sign in to Goodreads in Settings › Connections first.'
    const b = book.data
    const percent = Math.round((b.progress || 0) * 100)
    const key = keyOf(book)
    if (!force && sent()[key] === percent) return `Goodreads already has ${percent}%.`
    set({ busy: true })
    try {
      const id = await goodreadsID(book)
      if (!id) return `Couldn't find “${b.title}” on Goodreads.`
      if (!(await open(`https://www.goodreads.com/review/edit/${id}`))) return signedOutMessage()
      let result = await post('/shelf/add_to_shelf', { name: shelf(b), book_id: id, a: '' })
      if (b.status !== 'read' && percent > 0 && percent < 100) {
        const fields: Record<string, string> = { 'user_status[book_id]': id, 'user_status[body]': '' }
        if (b.pageCount > 0) fields['user_status[page]'] = String(Math.round((b.progress || 0) * b.pageCount))
        else fields['user_status[percent]'] = String(percent)
        result = await post('/user_status', fields)
      }
      if (!result) return "Goodreads didn't accept the update. Try again later."
      write('goodreads.sent', { ...sent(), [key]: percent })
      const status = `Sent ${b.status === 'read' ? '“read”' : `${percent}%`} for “${b.title}” to Goodreads.`
      set({ status })
      return status
    } finally {
      set({ busy: false })
    }
  })
}

// Fill Goodreads' own review form on that page and send it, keeping any fields it has (shelves, dates).
const REVIEW_JS = `async ({ text, rating }) => {
  const area = document.querySelector('textarea[name="review[review]"]');
  if (!area) return 'noform';
  const form = area.form;
  const data = new FormData(form);
  data.set('review[review]', text);
  if (rating > 0) data.set('review[rating]', String(rating));
  const res = await fetch(form.action, { method: 'POST', body: data, credentials: 'include', redirect: 'follow' });
  return (res.ok && !res.url.includes('sign_in') && !res.url.includes('/user/new')) ? 'ok' : ('status ' + res.status);
}`

/** Posts (or replaces) your review and star rating for `book` on Goodreads. */
export function postReview(book: Rec<Book>, text: string, rating: number): Promise<string> {
  return serial(async () => {
    if (!state.signedIn) return 'Sign in to Goodreads in Settings › Connections first.'
    set({ busy: true })
    try {
      const id = await goodreadsID(book)
      if (!id) return `Couldn't find “${book.data.title}” on Goodreads.`
      if (!(await open(`https://www.goodreads.com/review/edit/${id}`))) return signedOutMessage()
      let out: string | null = null
      try { out = (await plugin.run({ script: REVIEW_JS, args: { text, rating } })).value as string } catch { out = null }
      switch (out) {
        case 'ok': {
          const status = `Posted your review of “${book.data.title}” to Goodreads.`
          set({ status })
          return status
        }
        case 'noform': return "Goodreads' review page has changed, so Joshu couldn't post it. Your review is saved in Joshu."
        default: return `Goodreads didn't accept the review (${out ?? 'no answer'}). It's saved in Joshu.`
      }
    } finally {
      set({ busy: false })
    }
  })
}

// MARK: Finding the book

/** The Goodreads ID: from the Goodreads import, a cached match, or Goodreads' own search. */
export async function goodreadsID(book: Rec<Book>): Promise<string | null> {
  const b = book.data
  if (b.externalID?.startsWith('goodreads:')) return b.externalID.slice(10)
  const key = keyOf(book)
  const cached = ids()[key]
  if (cached) return cached
  const firstPart = (b.title ?? '').split(':').filter(Boolean)[0] ?? ''
  const q = b.isbn ? b.isbn : `${firstPart} ${b.author ?? ''}`
  const url = `https://www.goodreads.com/book/auto_complete?format=json&q=${encodeURIComponent(q)}`
  try {
    const { status, text } = isNative ? await plugin.fetchText({ url }) : { status: 0, text: '' }
    if (status !== 200) return null
    const hits = JSON.parse(text) as { bookId?: string | number }[]
    const id = hits?.[0]?.bookId
    if (id == null || id === '') return null
    write('goodreads.ids', { ...ids(), [key]: String(id) })
    return String(id)
  } catch {
    return null
  }
}

// MARK: The hidden browser

/** Loads a Goodreads page in the background; false when it sends you to sign in. */
async function open(address: string): Promise<boolean> {
  if (!isNative) return false
  try {
    const { url } = await plugin.load({ url: address })
    if (!url) return false
    return !url.includes('sign_in') && !url.includes('/user/new')
  } catch {
    return false
  }
}

const POST_JS = `async ({ path, fields }) => {
  const token = document.querySelector('meta[name="csrf-token"]')?.content || '';
  const data = new FormData();
  data.append('authenticity_token', token);
  for (const [k, v] of Object.entries(fields)) data.append(k, v);
  const res = await fetch(path, { method: 'POST', body: data, credentials: 'include', headers: { 'X-CSRF-Token': token } });
  return res.ok && !res.url.includes('sign_in') && !res.url.includes('/user/new');
}`

/** POSTs a form to Goodreads from the loaded page, with its security token. */
async function post(path: string, fields: Record<string, string>): Promise<boolean> {
  try {
    return (await plugin.run({ script: POST_JS, args: { path, fields } })).value === true
  } catch {
    return false
  }
}

// MARK: Your shelves (Goodreads in BookSources.swift, ReadingSync's Goodreads part)
// Joshu reads your public shelf feed and merges it into the library, matched by Goodreads ID or title and author, so
// syncing again never makes duplicates and a shelf you set in Joshu is never moved backwards (BookLibrary.merge).

export interface ImportedBook {
  title: string; author: string; status: Book['status']; rating: number; isbn: string; pages: number; year: number
  coverURL: string; progress: number; finishedAt: string | null; addedAt: string | null; externalID: string
}

/** A numeric user ID, or one from a profile link like goodreads.com/user/show/12345-name. */
export function goodreadsUserID(input: string): string | null {
  const s = (input ?? '').trim()
  const m = s.match(/(?:user\/show\/|list\/|list_rss\/)(\d+)/)
  if (m) return m[1]
  return /^\d+$/.test(s) ? s : null
}

async function getText(url: string): Promise<{ status: number; text: string }> {
  if (isNative) return plugin.fetchText({ url })
  const r = await fetch(url) // the browser preview: Goodreads usually refuses this (no CORS)
  return { status: r.status, text: await r.text() }
}

const isoOrNull = (s: string | null | undefined): string | null => {
  if (!s) return null
  const d = new Date(s)
  return isNaN(d.getTime()) ? null : d.toISOString().replace(/\.\d{3}Z$/, 'Z')
}

/** Reads the public shelf RSS feed, 100 books a page (the profile must be public). */
export async function fetchShelves(userID: string): Promise<ImportedBook[]> {
  const all: ImportedBook[] = []
  for (let page = 1; page <= 30; page++) {
    const url = `https://www.goodreads.com/review/list_rss/${userID}?shelf=%23ALL%23&per_page=100&page=${page}`
    let res: { status: number; text: string }
    try { res = await getText(url) } catch (e) { throw new Error(`Couldn't reach Goodreads: ${e instanceof Error ? e.message : String(e)}`) }
    const doc = new DOMParser().parseFromString(res.text ?? '', 'text/xml')
    const sawChannel = !!doc.querySelector('channel')
    const items = [...doc.querySelectorAll('item')].map((it) => {
      const get = (n: string) => it.getElementsByTagName(n)[0]?.textContent?.trim() ?? ''
      const shelves = get('user_shelves').split(',').map((x) => x.trim())
      const status: Book['status'] = shelves.includes('currently-reading') ? 'reading' : shelves.includes('to-read') ? 'toRead' : 'read'
      let cover = get('book_large_image_url') || get('book_image_url')
      if (cover.includes('nophoto')) cover = ''
      const id = get('book_id')
      return {
        title: get('title'), author: get('author_name'), status, rating: Number(get('user_rating')) || 0, isbn: get('isbn'),
        pages: Number(get('num_pages')) || 0, year: Number(get('book_published')) || 0, coverURL: cover, progress: status === 'read' ? 1 : 0,
        finishedAt: isoOrNull(get('user_read_at')), addedAt: isoOrNull(get('user_date_added')), externalID: id ? `goodreads:${id}` : '',
      } satisfies ImportedBook
    })
    if (page === 1 && items.length === 0 && !sawChannel) throw new Error("Goodreads didn't return a shelf. Check the user ID and that your profile is public.")
    all.push(...items)
    if (items.length < 100) break
  }
  return all
}

/** Goodreads › My Books › Import and export › Export library (a CSV). */
export function parseGoodreadsCSV(text: string): ImportedBook[] {
  const rows: string[][] = []
  let row: string[] = [], cell = '', quoted = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++ } else if (c === '"') quoted = false; else cell += c
    } else if (c === '"') quoted = true
    else if (c === ',') { row.push(cell); cell = '' }
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; row.push(cell); rows.push(row); row = []; cell = '' }
    else cell += c
  }
  if (cell || row.length) { row.push(cell); rows.push(row) }
  const header = rows[0]
  if (!header || !header.includes('Title')) throw new Error("That doesn't look like a Goodreads library export.")
  const col = (r: string[], name: string) => { const i = header.indexOf(name); return i >= 0 && i < r.length ? r[i].replace(/^[="\s]+|["\s]+$/g, '').trim() : '' }
  const date = (s: string) => { const m = s.match(/^(\d{4})\/(\d{2})\/(\d{2})$/); return m ? isoOrNull(new Date(+m[1], +m[2] - 1, +m[3]).toISOString()) : null }
  return rows.slice(1).flatMap((r) => {
    const title = col(r, 'Title')
    if (!title) return []
    const shelf = col(r, 'Exclusive Shelf')
    const status: Book['status'] = shelf === 'read' ? 'read' : shelf === 'currently-reading' ? 'reading' : 'toRead'
    const id = col(r, 'Book Id')
    return [{
      title, author: col(r, 'Author'), status, rating: Number(col(r, 'My Rating')) || 0, isbn: col(r, 'ISBN13') || col(r, 'ISBN'),
      pages: Number(col(r, 'Number of Pages')) || 0, year: Number(col(r, 'Original Publication Year')) || Number(col(r, 'Year Published')) || 0,
      coverURL: '', progress: status === 'read' ? 1 : 0, finishedAt: date(col(r, 'Date Read')), addedAt: date(col(r, 'Date Added')),
      externalID: id ? `goodreads:${id}` : '',
    }]
  })
}

/** BookLibrary.merge for Goodreads: adds new books and fills in existing ones; never moves a shelf backwards. */
export function mergeGoodreads(items: ImportedBook[]): { added: number; updated: number } {
  const existing = store.list<Book>('book')
  const byID = new Map<string, Rec<Book>>(), byKey = new Map<string, Rec<Book>>()
  for (const b of existing) {
    if (b.data.externalID && !byID.has(b.data.externalID)) byID.set(b.data.externalID, b)
    const k = matchKey(b.data.title ?? '', b.data.author ?? '')
    if (!byKey.has(k)) byKey.set(k, b)
  }
  const order: Book['status'][] = ['toRead', 'reading', 'dnf', 'read']
  const now = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
  let added = 0, updated = 0
  for (const item of items) {
    if (!item.title.trim()) continue
    const key = matchKey(item.title, item.author)
    const found = (item.externalID ? byID.get(item.externalID) : undefined) ?? byKey.get(key)
    if (found) {
      updated++
      const b = store.get<Book>(found.id)?.data ?? found.data
      const patch: Partial<Book> = {}
      if (order.indexOf(item.status) > order.indexOf(b.status)) patch.status = item.status
      if (item.externalID && !b.externalID) patch.externalID = item.externalID
      const sources = b.sources?.length ? [...b.sources] : [b.source || 'manual']
      if (!sources.includes('goodreads')) sources.push('goodreads')
      patch.sources = sources
      if (!b.rating) patch.rating = item.rating
      if (!b.isbn) patch.isbn = item.isbn
      if (!b.pageCount) patch.pageCount = item.pages
      if (!b.year) patch.year = item.year
      const cover = b.coverURL || item.coverURL || (item.isbn ? `https://covers.openlibrary.org/b/isbn/${item.isbn}-M.jpg?default=false` : '')
      if (cover !== b.coverURL) patch.coverURL = cover
      patch.progress = Math.max(b.progress || 0, item.progress)
      if (!b.finishedAt && item.finishedAt) patch.finishedAt = item.finishedAt
      store.update<Book>(found.id, patch)
    } else {
      added++
      const book: Book = {
        title: item.title.trim(), author: item.author.trim(), status: item.status, rating: item.rating, categories: [], notes: '',
        coverURL: item.coverURL || (item.isbn ? `https://covers.openlibrary.org/b/isbn/${item.isbn}-M.jpg?default=false` : ''),
        isbn: item.isbn, pageCount: item.pages, progress: item.progress, year: item.year, addedAt: item.addedAt ?? now,
        startedAt: null, finishedAt: item.finishedAt, source: 'goodreads', sources: ['goodreads'], externalID: item.externalID,
      }
      const id = store.create<Book>('book', book)
      const rec = store.get<Book>(id)
      if (rec) { byKey.set(key, rec); if (item.externalID) byID.set(item.externalID, rec) }
    }
  }
  return { added, updated }
}

// MARK: Daily refresh (ReadingSync: readingAutoSync, readingLastSync, lastResults)

export const shelfSync = {
  get autoSync(): boolean { return read('readingAutoSync', true) },
  set autoSync(on: boolean) { write('readingAutoSync', on); set({}) },
  get lastSync(): number { return read('readingLastSync', 0) },
  get result(): string | null { return read<string | null>('goodreads.shelfResult', null) },
  setResult(s: string | null) { write('goodreads.shelfResult', s); set({}) },
}
let shelfRunning = false
export const shelfSyncRunning = (): boolean => shelfRunning

/** Reads your Goodreads shelves now (or only when a day has passed, with `ifDue`). */
export async function syncShelves(profile: string, ifDue = false): Promise<void> {
  const id = goodreadsUserID(profile)
  if (!id || shelfRunning) return
  if (ifDue && (!shelfSync.autoSync || Date.now() / 1000 - shelfSync.lastSync < 20 * 3600)) return
  shelfRunning = true; set({})
  try {
    const items = await fetchShelves(id)
    const out = mergeGoodreads(items)
    shelfSync.setResult(`Synced ${items.length} books — ${out.added} new, ${out.updated} updated. Refreshes daily.`)
  } catch (e) {
    shelfSync.setResult(e instanceof Error ? e.message : String(e))
  } finally {
    write('readingLastSync', Date.now() / 1000)
    shelfRunning = false; set({})
  }
}
