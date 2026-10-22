// Tools Ask can use to act in Orbit, mirroring the Mac app's AssistantTools (Assistant.swift).
import { store } from './store'
import { Tool } from './ai'
import { AREAS, Area, MONEY_CATEGORIES, BUCKET_KINDS, Book, BookCategory, Task, CalEvent, Habit, Note, Bucket, Txn, ReadingStatus } from './models'
import { iso, fmtTime, relativeDay, fromInputs } from './dates'
import { overview, moneySummary, moneyFmt } from './snapshot'

/** What an action did, so it can be shown as a chip and undone. */
export type Undo = { kind: 'records'; ids: string[] } | { kind: 'budget'; previous: number }
export interface Outcome { result: string; isError?: boolean; action?: { text: string; symbol: string; undo?: Undo } }

export const HABIT_SYMBOLS = ['checkmark', 'figure.run', 'book.fill', 'drop.fill', 'bed.double.fill', 'leaf.fill', 'brain.head.profile',
  'creditcard', 'fork.knife', 'dumbbell.fill', 'pencil', 'moon.stars.fill', 'phone.down.fill', 'sun.max.fill', 'music.note', 'heart.fill']

function tool(name: string, description: string, properties: Record<string, unknown>, required?: string[]): Tool {
  return {
    name, description,
    // Inputs stream as they're written; run() validates every field before acting.
    eager_input_streaming: true,
    input_schema: { type: 'object', properties, required: required ?? Object.keys(properties), additionalProperties: false },
  }
}

export const ASK_TOOLS: Tool[] = [
  tool('get_overview', "Today's events, tasks, habits and streaks, reading shelves and budget. Use before planning or advising.", {}),
  tool('get_money_summary', 'Spending by category and merchant for the last three months, subscriptions and bills due.', {}),
  tool('list_books', "Books in the user's library, filtered by shelf.", { shelf: { type: 'string', enum: ['all', 'reading', 'toRead', 'read', 'dnf'] } }),
  tool('create_task', 'Create a task. due_date yyyy-MM-dd or empty for no date.', {
    title: { type: 'string' }, area: { type: 'string', enum: AREAS }, due_date: { type: 'string' },
    priority: { type: 'integer', description: '0 none, 1 low, 2 medium, 3 high' },
    repeat: { type: 'string', enum: ['none', 'daily', 'weekly', 'monthly'] }, notes: { type: 'string' },
  }),
  tool('create_event', 'Add an event to the calendar. start is local time yyyy-MM-ddTHH:mm.', {
    title: { type: 'string' }, start: { type: 'string' }, duration_minutes: { type: 'integer' }, area: { type: 'string', enum: AREAS },
  }),
  tool('create_habit', 'Create a habit to track. Keep targets realistic.', {
    name: { type: 'string' }, symbol: { type: 'string', enum: HABIT_SYMBOLS }, area: { type: 'string', enum: AREAS },
    target_per_week: { type: 'integer', description: '1-7 days a week' },
  }),
  tool('add_books', 'Add books to the reading list. category is optional (empty string for none) and is created if missing.', {
    books: {
      type: 'array', items: {
        type: 'object',
        properties: { title: { type: 'string' }, author: { type: 'string' }, shelf: { type: 'string', enum: ['toRead', 'reading', 'read'] }, category: { type: 'string' } },
        required: ['title', 'author', 'shelf', 'category'], additionalProperties: false,
      },
    },
  }),
  tool('create_note', 'Save a note.', { title: { type: 'string' }, body: { type: 'string' } }),
  tool('add_bucket_item', "Add something to the user's bucket list (things they want to do in life). target_date yyyy-MM-dd or empty.", {
    title: { type: 'string' }, kind: { type: 'string', enum: BUCKET_KINDS.map((k) => k.id) },
    notes: { type: 'string' }, target_date: { type: 'string' },
    excitement: { type: 'integer', description: "1 nice to do, 2 really want to, 3 can't wait" },
  }),
  tool('add_transaction', 'Log money spent or received. date yyyy-MM-dd.', {
    title: { type: 'string' }, amount: { type: 'number', description: 'positive number in the home currency' },
    kind: { type: 'string', enum: ['expense', 'income'] }, category: { type: 'string', enum: MONEY_CATEGORIES }, date: { type: 'string' },
  }),
  tool('set_monthly_budget', 'Change the monthly spending budget (home currency).', { amount: { type: 'number' } }),
]

const DAY = /^\d{4}-\d{2}-\d{2}$/
const DAY_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/
const dayDate = (s: string): Date | null => (DAY.test(s) ? fromInputs(s) : null)
const bad = (msg: string): Outcome => ({ result: msg, isError: true })

/** Runs one tool call. Inputs are untrusted model output: every field is checked before acting. */
export async function runTool(name: string, input: Record<string, any>): Promise<Outcome> {
  const str = (k: string): string => (typeof input?.[k] === 'string' ? input[k].trim() : '')
  const num = (k: string): number => (typeof input?.[k] === 'number' && isFinite(input[k]) ? input[k] : NaN)
  const area = (k: string, fallback: Area = 'personal'): Area => (AREAS.includes(str(k) as Area) ? (str(k) as Area) : fallback)
  const now = iso(new Date())

  switch (name) {
    case 'get_overview':
      return { result: overview() }

    case 'get_money_summary':
      return { result: moneySummary() }

    case 'list_books': {
      const shelf = str('shelf') || 'all'
      if (!['all', 'reading', 'toRead', 'read', 'dnf'].includes(shelf)) return bad('shelf must be all, reading, toRead, read or dnf')
      const books = store.list<Book>('book').filter((b) => shelf === 'all' || b.data.status === shelf)
      if (!books.length) return { result: 'No books on that shelf.' }
      const title = (s: string) => ({ reading: 'Reading', toRead: 'To read', read: 'Read', dnf: "Didn't finish" } as Record<string, string>)[s] ?? s
      return { result: books.slice(0, 150).map((b) => `${b.data.title} — ${b.data.author} [${title(b.data.status)}${b.data.categories?.length ? '; ' + b.data.categories.join(', ') : ''}]`).join('\n') }
    }

    case 'create_task': {
      const title = str('title')
      if (!title) return bad('title is required')
      const dueStr = str('due_date')
      const due = dueStr ? dayDate(dueStr) : null
      if (dueStr && !due) return bad('due_date must be yyyy-MM-dd or empty')
      const repeat = ['none', 'daily', 'weekly', 'monthly'].includes(str('repeat')) ? str('repeat') : 'none'
      const priority = isNaN(num('priority')) ? 0 : Math.max(0, Math.min(3, Math.round(num('priority'))))
      const id = store.create<Task>('task', { title, notes: str('notes'), area: area('area'), due: due ? iso(due) : null, priority,
        isDone: false, completedAt: null, createdAt: now, repeat: repeat as Task['repeat'] })
      return { result: 'Created task.', action: { text: `Task “${title}”${due ? ` · due ${relativeDay(due)}` : ''}`, symbol: 'task', undo: { kind: 'records', ids: [id] } } }
    }

    case 'create_event': {
      const s = str('start')
      if (!DAY_TIME.test(s)) return bad('start must be yyyy-MM-ddTHH:mm')
      const start = fromInputs(s.slice(0, 10), s.slice(11, 16))
      const title = str('title')
      if (!title) return bad('title is required')
      const minutes = Math.max(5, isNaN(num('duration_minutes')) ? 60 : Math.round(num('duration_minutes')))
      const end = new Date(start.getTime() + minutes * 60_000)
      const id = store.create<CalEvent>('event', { title, start: iso(start), end: iso(end), area: area('area'), location: '', notes: '' })
      return { result: 'Added event.', action: { text: `Event “${title}” · ${relativeDay(start)} ${fmtTime(start)}`, symbol: 'event', undo: { kind: 'records', ids: [id] } } }
    }

    case 'create_habit': {
      const habitName = str('name')
      if (!habitName) return bad('name is required')
      const target = isNaN(num('target_per_week')) ? 7 : Math.max(1, Math.min(7, Math.round(num('target_per_week'))))
      const id = store.create<Habit>('habit', { name: habitName, symbol: HABIT_SYMBOLS.includes(str('symbol')) ? str('symbol') : 'checkmark',
        area: area('area', 'health'), targetPerWeek: target, createdAt: now, doneDays: [] })
      return { result: 'Created habit.', action: { text: `Habit “${habitName}” · ${target}× a week`, symbol: 'habit', undo: { kind: 'records', ids: [id] } } }
    }

    case 'add_books': {
      const list = Array.isArray(input?.books) ? input.books.slice(0, 12) : []
      if (!list.length) return bad('books is empty')
      const existing = store.list<Book>('book')
      const keys = new Set(existing.map((b) => matchKey(b.data.title, b.data.author)))
      const created: string[] = []
      let already = 0
      const found = await Promise.all(list.map(async (b: any) => {
        const title = typeof b?.title === 'string' ? b.title.trim() : ''
        const author = typeof b?.author === 'string' ? b.author.trim() : ''
        return { title, author, shelf: ['toRead', 'reading', 'read'].includes(b?.shelf) ? (b.shelf as ReadingStatus) : 'toRead',
          category: typeof b?.category === 'string' ? b.category.trim() : '', hit: title ? await lookup(`${title} ${author}`) : null }
      }))
      for (const b of found) {
        if (!b.title) continue
        if (keys.has(matchKey(b.title, b.author))) { already++; continue }
        if (b.category) created.push(...ensureCategory(b.category))
        keys.add(matchKey(b.title, b.author))
        created.push(store.create<Book>('book', {
          title: b.title, author: b.author, status: b.shelf, rating: 0, categories: b.category ? [b.category] : [], notes: '',
          coverURL: b.hit?.coverURL ?? '', isbn: b.hit?.isbn ?? '', pageCount: b.hit?.pages ?? 0, progress: b.shelf === 'read' ? 1 : 0,
          year: b.hit?.year ?? 0, addedAt: now, startedAt: b.shelf === 'reading' ? now : null, finishedAt: b.shelf === 'read' ? now : null,
          source: 'openlibrary', sources: ['openlibrary'], externalID: b.hit ? `openlibrary:${b.hit.key}` : '',
        }))
      }
      const added = created.length
      return {
        result: `Added ${found.filter((b) => b.title).length - already} new, ${already} were already in the library.`,
        action: { text: `Added to reading list: ${found.map((b) => b.title).filter(Boolean).join(', ')}`, symbol: 'books', undo: added ? { kind: 'records', ids: created } : undefined },
      }
    }

    case 'create_note': {
      const title = str('title') || 'Untitled'
      const id = store.create<Note>('note', { title, body: str('body'), createdAt: now, updatedAt: now, isJournal: false, pinned: false, mood: 0, moodSetByUser: false })
      return { result: 'Saved note.', action: { text: `Note “${title}”`, symbol: 'note', undo: { kind: 'records', ids: [id] } } }
    }

    case 'add_bucket_item': {
      const title = str('title')
      if (!title) return bad('title is required')
      const t = str('target_date')
      const target = t ? dayDate(t) : null
      if (t && !target) return bad('target_date must be yyyy-MM-dd or empty')
      const kind = BUCKET_KINDS.some((k) => k.id === str('kind')) ? str('kind') : 'other'
      const excitement = isNaN(num('excitement')) ? 2 : Math.max(1, Math.min(3, Math.round(num('excitement'))))
      const id = store.create<Bucket>('bucket', { title, notes: str('notes'), kind: kind as Bucket['kind'], targetDate: target ? iso(target) : null,
        excitement, isDone: false, doneAt: null, createdAt: now })
      return { result: 'Added to bucket list.', action: { text: `Bucket list: “${title}”`, symbol: 'bucket', undo: { kind: 'records', ids: [id] } } }
    }

    case 'add_transaction': {
      const amount = Math.abs(num('amount'))
      if (!amount) return bad('amount must be a positive number')
      const income = str('kind') === 'income'
      const d = str('date') ? dayDate(str('date')) : new Date()
      if (!d) return bad('date must be yyyy-MM-dd')
      if (str('date')) d.setHours(12)
      const title = str('title') || (income ? 'Income' : 'Expense')
      const category = income ? 'Income' : MONEY_CATEGORIES.includes(str('category')) ? str('category') : 'General'
      const id = store.create<Txn>('transaction', { title, amount: income ? amount : -amount, category, date: iso(d), isRecurring: false,
        source: '', sourceID: '', originalAmount: 0, originalCurrency: '' })
      return { result: 'Logged.', action: { text: `${income ? 'Income' : 'Expense'} “${title}” ${income ? '+' : '−'}${moneyFmt(amount)}`, symbol: 'money', undo: { kind: 'records', ids: [id] } } }
    }

    case 'set_monthly_budget': {
      const amount = num('amount')
      if (!(amount > 0)) return bad('amount must be positive')
      const previous = store.setting<number>('monthlyBudget') ?? 2000
      store.setSetting('monthlyBudget', amount)
      return { result: 'Budget set.', action: { text: `Monthly budget → ${moneyFmt(amount)}`, symbol: 'budget', undo: { kind: 'budget', previous } } }
    }

    default:
      return bad(`Unknown tool ${name}`)
  }
}

export function undo(u: Undo): void {
  if (u.kind === 'records') u.ids.forEach((id) => store.remove(id))
  else store.setSetting('monthlyBudget', u.previous)
}

/** Same match key as the Mac: lowercased title before ':' or '(' + '|' + author's last word. */
function matchKey(title: string, author: string): string {
  const t = title.toLowerCase().split(/[:(]/)[0].trim()
  const a = author.toLowerCase().split(' ').filter(Boolean).pop() ?? ''
  return `${t}|${a}`
}

/** Creates the reading category if it doesn't exist; returns new ids (for undo). */
function ensureCategory(name: string): string[] {
  const all = store.list<BookCategory>('bookCategory')
  if (all.some((c) => c.data.name.toLowerCase() === name.toLowerCase())) return []
  return [store.create<BookCategory>('bookCategory', { name, colorIndex: all.length % 7, symbol: 'tag.fill', createdAt: iso(new Date()) })]
}

async function lookup(q: string): Promise<{ key: string; coverURL: string; pages: number; year: number; isbn: string } | null> {
  try {
    const url = `https://openlibrary.org/search.json?q=${encodeURIComponent(q)}&limit=1&fields=key,title,author_name,first_publish_year,number_of_pages_median,isbn,cover_i`
    const d = (await fetch(url).then((r) => r.json()))?.docs?.[0]
    if (!d) return null
    return { key: d.key ?? '', coverURL: d.cover_i ? `https://covers.openlibrary.org/b/id/${d.cover_i}-M.jpg` : '',
      pages: d.number_of_pages_median ?? 0, year: d.first_publish_year ?? 0, isbn: d.isbn?.[0] ?? '' }
  } catch { return null }
}

