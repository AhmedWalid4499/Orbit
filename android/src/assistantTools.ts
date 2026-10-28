// Every tool the Mac and iPhone assistant has (AssistantTools in Assistant.swift), for Android. The shared
// renderer's @/lib/askTools has the basic ones; the rest are here, writing records with every field the Mac
// encodes (CloudSync.swift) so they show up the same everywhere. Action rows use the Mac's SF Symbol names, so a
// chat started here looks right when it's opened on the Mac or iPhone.
// Left out: read_browser_tab (it reads Chrome on the Mac).
import { store, Rec } from '@/lib/store'
import { Tool } from '@/lib/ai'
import { ASK_TOOLS, runTool as runShared, undo as undoShared, Undo as SharedUndo } from '@/lib/askTools'
import { AREAS, Area, Task, Note, Book, Bucket, Habit, Txn, Doc, DocKind, DOC_KINDS, Subscription, BILLING_CYCLES, BillingCycle, cap } from '@/lib/models'
import { overview as sharedOverview } from '@/lib/snapshot'
import { externalEvents } from '@/lib/externalEvents'
import { iso, parse, fromInputs, relativeDay, fmtTime, startOfDay, addDays, daysBetween, dayKey, fmtDay } from '@/lib/dates'
import { moneyFmt } from '@/lib/snapshot'
import type { Idea, IdeaProject } from './screens/Ideas'
import type { Goal } from './screens/Goals'
import { Bill, monthKey } from './reminders'
import { remember, forget, memories, setMemories } from './assistantMemory'
import { lookupNearby, forecastText, findPlace, locate, Found } from './nearby'
import { getGoodreads, postReview, pushProgress } from './lib/goodreads'
import { sharedListsNow, refresh as refreshShared, putItem, newItem, isAvailable as sharedAvailable, openCount } from './lib/sharedLists'

export type Undo = SharedUndo | { kind: 'memory'; fact: string }
/** A place the assistant saved, shown as a little map card (ChatPlace on the Mac). */
export interface ChatPlace { name: string; address: string; category: string; lat: number; lon: number; link: string }
export interface Outcome { result: string; isError?: boolean; action?: { text: string; symbol: string; undo?: Undo; place?: ChatPlace } }

/** The shared tools' symbols as the Mac's SF Symbol names. */
const SF: Record<string, string> = {
  task: 'checklist', event: 'calendar', habit: 'flame.fill', books: 'books.vertical.fill', note: 'doc.text', bucket: 'mountain.2.fill',
  money: 'creditcard', budget: 'target', memory: 'brain', web: 'globe', code: 'chevron.left.forwardslash.chevron.right',
}
export const sfSymbol = (s: string): string => SF[s] ?? s

const PLACE_CATEGORIES = ['food', 'cafe', 'bar', 'shop', 'museum', 'park', 'attraction', 'hotel', 'other']
const PLACE_TITLE: Record<string, string> = { food: 'Food', cafe: 'Café', bar: 'Bar', shop: 'Shop', museum: 'Museum', park: 'Park', attraction: 'Sight', hotel: 'Stay', other: 'Other' }
export const placeTitle = (c: string): string => PLACE_TITLE[c] ?? 'Other'

function tool(name: string, description: string, properties: Record<string, unknown>, required?: string[]): Tool {
  return { name, description, eager_input_streaming: true, input_schema: { type: 'object', properties, required: required ?? Object.keys(properties), additionalProperties: false } }
}
const shared = (name: string): Tool => ASK_TOOLS.find((t) => t.name === name)!

export function toolDefinitions(): Tool[] {
  return [
    shared('get_overview'),
    shared('get_money_summary'),
    shared('list_books'),
    tool('create_task', 'Create a task, optionally with a reminder. due_date yyyy-MM-dd or empty for no date. remind_at: local time yyyy-MM-ddTHH:mm for a reminder at a time ("remind me at 6", "in 2 hours"), else empty. remind_place: where to remind them, for "when I get home", "when I\'m at work", "when I\'m near Carrefour": "home", "work", a shop or place name (the nearest one is used) or a maps link; else empty. remind_on: "arrive" or "leave".', {
      title: { type: 'string' }, area: { type: 'string', enum: AREAS }, due_date: { type: 'string' },
      priority: { type: 'integer', description: '0 none, 1 low, 2 medium, 3 high' },
      repeat: { type: 'string', enum: ['none', 'daily', 'weekly', 'monthly'] }, notes: { type: 'string' },
      remind_at: { type: 'string' }, remind_place: { type: 'string' }, remind_on: { type: 'string', enum: ['arrive', 'leave'] },
    }),
    shared('create_event'),
    shared('create_habit'),
    tool('add_idea', 'Save a writing idea to a project in the Ideas tab (the user writes; when an idea pops up they ask you to keep it). project: the project\'s name as they call it (made if new). idea: their idea in their own words, kept close to how they said it (a short title is made from the start). under: the title of an existing idea this one grows from, or empty. Use get_ideas first if unsure which project or idea they mean.', {
      project: { type: 'string' }, idea: { type: 'string' },
      details: { type: 'string', description: 'more of what they said about it, or empty' },
      under: { type: 'string', description: 'existing idea it grows from, or empty' },
    }),
    tool('update_idea', 'Change an idea in the Ideas tab: write more on its page, rewrite it, or rename it. mode "append" adds text at the end of its page (default), "replace" rewrites the whole page (only when they ask to rewrite or tidy it). Find it by project and title.', {
      project: { type: 'string' }, idea: { type: 'string', description: "the idea's current title" },
      text: { type: 'string' }, mode: { type: 'string', enum: ['append', 'replace'] },
      new_title: { type: 'string', description: 'a new title, or empty to keep it' },
    }),
    tool('get_ideas', "The user's writing projects and the ideas in each (with what grew from them). project: one project's name, or empty for all. Use before adding to or developing an idea, or when they ask what ideas they have.", {
      project: { type: 'string' },
    }),
    tool('goodreads_review', "Post the user's review (and star rating) of a book to their Goodreads, and save it as the book's notes in Joshu. Use their words; only polish them if they ask. rating 1-5, or 0 to leave stars as they are.", {
      book: { type: 'string', description: "the book's title" }, review: { type: 'string' }, rating: { type: 'integer' },
    }),
    tool('goodreads_progress', 'Update how far the user is in a book, in Joshu and on Goodreads. percent 0-100 (100 = finished), or page with the page they\'re on (0 if not given).', {
      book: { type: 'string' }, percent: { type: 'integer' }, page: { type: 'integer' },
    }),
    shared('add_books'),
    tool('create_note', 'Save a note in Joshu\'s Notes. You write the body: when the user asks you to write, draft or make notes about something, compose the real content yourself (explanations, key facts, steps, examples, pros and cons, a checklist — whatever fits), organised with short headings on their own line and "•" bullets. Never just save their request or repeat their words back. When they dictate their own notes, keep their meaning but fix spelling and grammar and organise it. Plain text only: no markdown symbols such as #, ** or ```. A clear, specific title.',
      { title: { type: 'string' }, body: { type: 'string' } }),
    tool('list_notes', "Titles and first lines of the user's recent notes (not journal entries). Use before adding to or editing a note.", {}),
    tool('read_note', 'The full text of a note, found by its title.', { title: { type: 'string' } }),
    tool('update_note', 'Change an existing note, found by its title. mode "append" adds body at the end; "replace" rewrites the whole note (only when asked to rewrite, restructure or improve it).', {
      title: { type: 'string' }, body: { type: 'string' }, mode: { type: 'string', enum: ['append', 'replace'] },
    }),
    tool('get_weather', 'Hour-by-hour weather for today and tomorrow where the user is (or a city they name): temperature, feels-like, rain chance, wind, UV. Use for what to wear, whether to take an umbrella or sunscreen, or planning outdoor plans.', {
      city: { type: 'string', description: 'empty for where the user is now' },
    }),
    tool('find_nearby', 'Find any kind of place near the user right now with the map (OpenStreetMap; uses their phone location, or their city when location is off): food, coffee, a gym, a pharmacy, a barber, a phone repair shop, a mall, a bookshop, a park, somewhere to buy a specific thing… query is what they want ("food" when they\'re just hungry). near: a place, address, area or maps link to search around instead of the user\'s location ("Zamalek", "Cairo Festival City", "the Four Seasons Nile Plaza", a Google Maps link), or empty for where they are. radius_meters: 1500 for walking distance, up to 8000 if they\'ll drive or nothing is close.', {
      query: { type: 'string' }, near: { type: 'string' }, radius_meters: { type: 'integer' },
    }),
    tool('add_place', 'Save a place to the Go to list in the bucket list (a restaurant, café, shop, museum… the user liked or wants to try). place is its name with the area or city, or a Google/Apple Maps link. Joshu finds it on the map.', {
      place: { type: 'string' }, notes: { type: 'string', description: 'what they liked or want to try there, or empty' },
      category: { type: 'string', enum: ['', ...PLACE_CATEGORIES], description: 'empty to let Joshu decide' },
    }),
    tool('add_document', 'Track a document or warranty with an expiry date so Joshu reminds the user. expires yyyy-MM-dd or empty.', {
      title: { type: 'string' }, kind: { type: 'string', enum: DOC_KINDS.map((k) => k.id) }, expires: { type: 'string' },
    }),
    tool('add_subscription', 'Track a subscription. amount per charge in the home currency; next_date yyyy-MM-dd or empty.', {
      name: { type: 'string' }, amount: { type: 'number' }, cycle: { type: 'string', enum: BILLING_CYCLES },
      status: { type: 'string', enum: ['active', 'trial', 'cancelled'] }, next_date: { type: 'string' },
    }),
    shared('add_bucket_item'),
    shared('add_transaction'),
    shared('set_monthly_budget'),
    tool('remember', 'Remember a lasting fact about the user for future chats, in one short line in the third person ("Vegetarian", "Gym on Tuesdays and Thursdays", "Sister Mona, birthday 12 March").', { fact: { type: 'string' } }),
    tool('forget', 'Forget something remembered earlier, found by a word or phrase in it.', { text: { type: 'string' } }),
    tool('add_bill', "Track a bill due every month so Joshu reminds the user and marks it paid when the payment shows up. amount 0 if it varies. match: words in the bank text that mean it's paid, comma separated, or empty for the name.", {
      name: { type: 'string' }, amount: { type: 'number' }, due_day: { type: 'integer', description: '1-31' },
      remind_days: { type: 'integer', description: 'days before to remind, usually 3' }, match: { type: 'string' },
    }),
    tool('create_goal', 'Create a goal whose progress fills in by itself. kind: books (books finished), save (income minus spending), habit (days a habit is done; habit is its name), steps (a checklist). target: number of books, amount of money or days (ignored for steps). start yyyy-MM-dd or empty for today (use 1 January for a this-year reading goal). deadline yyyy-MM-dd or empty.', {
      title: { type: 'string' }, kind: { type: 'string', enum: ['books', 'save', 'habit', 'steps'] },
      target: { type: 'number' }, start: { type: 'string' }, deadline: { type: 'string' }, habit: { type: 'string' },
      steps: { type: 'array', items: { type: 'string' } },
    }),
    tool('add_to_shared_list', "Add items to one of the user's shared lists (lists shared with other people), found by its name.", {
      list: { type: 'string' }, items: { type: 'array', items: { type: 'string' } },
    }),
  ]
}

/** Anthropic-run tools: web search, reading pages and a code sandbox (no internet inside it). */
export function serverTools(): any[] {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
  const city = store.setting<string>('weatherCity') || zone.split('/').pop()?.replace(/_/g, ' ') || ''
  return [
    // City and time zone only: web search rejects some country codes (e.g. EG) and fails the whole request.
    { type: 'web_search_20260209', name: 'web_search', max_uses: 6, user_location: { type: 'approximate', timezone: zone, city } },
    { type: 'web_fetch_20260209', name: 'web_fetch', max_uses: 4 },
    { type: 'code_execution_20260521', name: 'code_execution' },
  ]
}

const DAY = /^\d{4}-\d{2}-\d{2}$/
const DAY_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/
const dayDate = (s: string): Date | null => (DAY.test(s) ? fromInputs(s) : null)
const bad = (result: string): Outcome => ({ result, isError: true })
const lower = (s: string) => s.toLowerCase()

/** Runs one tool call. Inputs are untrusted model output: every field is checked before acting. */
export async function runTool(name: string, input: Record<string, any>): Promise<Outcome> {
  const str = (k: string): string => (typeof input?.[k] === 'string' ? input[k].trim() : '')
  const num = (k: string): number => (typeof input?.[k] === 'number' && isFinite(input[k]) ? input[k] : 0)
  const strings = (k: string): string[] => (Array.isArray(input?.[k]) ? input[k].filter((x: unknown) => typeof x === 'string').map((x: string) => x.trim()).filter(Boolean) : [])
  const now = iso(new Date())

  switch (name) {
    case 'get_overview':
      return { result: overview() }

    case 'create_task': {
      const title = str('title')
      if (!title) return bad('title is required')
      const dueStr = str('due_date'), due = dueStr ? dayDate(dueStr) : null
      if (dueStr && !due) return bad('due_date must be yyyy-MM-dd or empty')
      const area = (AREAS.includes(str('area') as Area) ? str('area') : 'personal') as Area
      const repeat = (['none', 'daily', 'weekly', 'monthly'].includes(str('repeat')) ? str('repeat') : 'none') as Task['repeat']
      const remindAt = DAY_TIME.test(str('remind_at')) ? fromInputs(str('remind_at').slice(0, 10), str('remind_at').slice(11, 16)) : null
      let when = due ? ` · due ${relativeDay(due)}` : ''
      if (remindAt) when += ` · reminder ${relativeDay(remindAt)} ${fmtTime(remindAt)}`
      let note = 'Created task.'
      let place = { name: '', lat: 0, lon: 0, onLeave: false }
      const placeText = str('remind_place')
      if (placeText) {
        if (/^(home|my home|my house|house|work|the office|office|my office|my work|البيت|الشغل)$/i.test(placeText)) {
          note += ` Couldn't set the place reminder: Joshu on Android doesn't know their ${/home|house|البيت/i.test(placeText) ? 'home' : 'work'} address. Suggest a time reminder instead (or they can set the place on their iPhone).`
        } else {
          const p = await findPlace(placeText, await locate())
          if (p && !isNaN(p.lat)) {
            place = { name: p.name, lat: p.lat, lon: p.lon, onLeave: str('remind_on') === 'leave' }
            when += ` · ${place.onLeave ? 'when leaving' : 'at'} ${p.name}`.toLowerCase()
            note += " The place is saved on the task: their iPhone reminds them there (Joshu on Android can't remind by place yet, so mention a time reminder if they only use Android)."
          } else note += ` Couldn't find ${placeText} on the map for the place reminder.`
        }
      }
      const id = store.create<Task & { remindAt: string | null; place: typeof place }>('task', {
        title, notes: str('notes'), area, due: due ? iso(due) : null, priority: Math.max(0, Math.min(3, Math.round(num('priority')))),
        isDone: false, completedAt: null, createdAt: now, repeat, remindAt: remindAt ? iso(remindAt) : null, place,
      })
      return { result: note, action: { text: `Task “${title}”${when}`, symbol: 'checklist', undo: { kind: 'records', ids: [id] } } }
    }

    case 'create_note': {
      if (!str('body')) return bad("body is required: write the note's content")
      const title = str('title') || 'Note'
      const id = store.create<Note>('note', { title, body: str('body'), createdAt: now, updatedAt: now, isJournal: false, pinned: false, mood: 0, moodSetByUser: false })
      return { result: 'Saved note.', action: { text: `Note “${title}”`, symbol: 'doc.text', undo: { kind: 'records', ids: [id] } } }
    }

    case 'list_notes': {
      const notes = store.list<Note>('note').filter((n) => !n.data.isJournal)
        .sort((a, b) => (parse(b.data.updatedAt)?.getTime() ?? 0) - (parse(a.data.updatedAt)?.getTime() ?? 0))
      if (!notes.length) return { result: 'No notes yet.' }
      return { result: notes.slice(0, 40).map((n) => { const first = (n.data.body ?? '').split('\n')[0] ?? ''; return `• ${n.data.title}${first ? ` — ${first.slice(0, 80)}` : ''}` }).join('\n') }
    }

    case 'read_note':
    case 'update_note': {
      const wanted = lower(str('title'))
      const notes = store.list<Note>('note').filter((n) => !n.data.isJournal)
      const n = notes.find((x) => lower(x.data.title) === wanted) ?? (wanted ? notes.find((x) => lower(x.data.title).includes(wanted)) : undefined)
      if (!n) return bad(`No note titled “${str('title')}”. Use list_notes to see the titles.`)
      if (name === 'read_note') return { result: `${n.data.title}\n\n${n.data.body}` }
      if (!str('body')) return bad('body is required')
      const body = str('mode') === 'replace' ? str('body') : `${(n.data.body ?? '').trim()}\n\n${str('body')}`
      store.update<Note>(n.id, { body, updatedAt: now })
      return { result: 'Updated note.', action: { text: `Updated note “${n.data.title}”`, symbol: 'doc.text' } }
    }

    case 'get_weather': {
      const r = await forecastText(str('city'))
      return { result: r.text, isError: r.isError }
    }

    case 'find_nearby': {
      const r = await lookupNearby(str('query') || 'food', str('near'), num('radius_meters') > 0 ? num('radius_meters') : 1500)
      return { result: r.text, isError: r.isError }
    }

    case 'add_place': {
      const text = str('place')
      if (!text) return bad('place is required')
      const f: Found | null = await findPlace(text, await locate())
      const fallback = /https?:\/\//i.test(text) ? '' : text
      const title = f?.name || fallback
      if (!title) return bad("Couldn't find that place.")
      const category = PLACE_CATEGORIES.includes(str('category')) && str('category') ? str('category') : f?.category ?? 'other'
      const hasPin = !!f && !isNaN(f.lat)
      const placeData = { category, address: f?.address ?? '', lat: hasPin ? f!.lat : 0, lon: hasPin ? f!.lon : 0, url: f?.url ?? (text.match(/https?:\/\/\S+/)?.[0] ?? '') }
      const id = store.create<Omit<Bucket, 'kind'> & { kind: string; place: typeof placeData }>('bucket', {
        title, notes: str('notes'), kind: 'place', targetDate: null, excitement: 2, isDone: false, doneAt: null, createdAt: now, place: placeData,
      })
      const whereText = placeData.address || (hasPin ? 'pinned on the map' : 'not found on the map')
      return {
        result: `Saved ${title} (${placeTitle(category)}, ${whereText}) to Go to.`,
        action: { text: 'Saved to Go to', symbol: 'mappin.and.ellipse', undo: { kind: 'records', ids: [id] },
          place: { name: title, address: placeData.address, category, lat: placeData.lat, lon: placeData.lon, link: placeData.url } },
      }
    }

    case 'add_document': {
      const title = str('title')
      if (!title) return bad('title is required')
      const expires = dayDate(str('expires'))
      const kind = (DOC_KINDS.some((k) => k.id === str('kind')) ? str('kind') : 'other') as DocKind
      const id = store.create<Doc>('document', { title, kind, number: '', issuer: '', issued: null, expires: expires ? iso(expires) : null,
        remindDays: 30, notes: '', source: 'manual', sourceID: '', createdAt: now })
      return { result: 'Saved.', action: { text: `Document “${title}”${expires ? ` · expires ${expires.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}` : ''}`, symbol: 'doc.text.fill', undo: { kind: 'records', ids: [id] } } }
    }

    case 'add_subscription': {
      const subName = str('name')
      if (!subName) return bad('name is required')
      const cycle = (BILLING_CYCLES.includes(str('cycle') as BillingCycle) ? str('cycle') : 'monthly') as BillingCycle
      const status = (['active', 'trial', 'cancelled'].includes(str('status')) ? str('status') : 'active') as Subscription['status']
      const next = dayDate(str('next_date'))
      const amount = Math.abs(num('amount'))
      const id = store.create<Subscription>('subscription', { name: subName, amount, originalAmount: 0, originalCurrency: '', cycle,
        nextDate: next ? iso(next) : null, lastCharged: null, category: 'Subscriptions', status, trialEnds: status === 'trial' && next ? iso(next) : null,
        previousAmount: 0, priceChangedAt: null, source: 'manual', notes: '', createdAt: now })
      return { result: 'Saved.', action: { text: `Subscription “${subName}” ${moneyFmt(amount)} ${cycle}`, symbol: 'repeat', undo: { kind: 'records', ids: [id] } } }
    }

    case 'remember': {
      const fact = str('fact')
      if (!fact) return bad('fact is required')
      const added = remember(fact)
      return { result: added ? 'Remembered.' : 'Already remembered.', action: added ? { text: `Remembered: ${fact}`, symbol: 'brain', undo: { kind: 'memory', fact } } : undefined }
    }

    case 'forget': {
      const gone = forget(str('text'))
      return { result: gone.length ? `Forgot: ${gone.join('; ')}` : 'Nothing like that was remembered.', action: gone.length ? { text: `Forgot: ${gone.join('; ')}`, symbol: 'brain' } : undefined }
    }

    case 'add_bill': {
      const billName = str('name')
      if (!billName) return bad('name is required')
      const dueDay = Math.min(31, Math.max(1, Math.round(num('due_day')) || 1))
      const amount = Math.max(0, num('amount'))
      const id = store.create<Bill>('bill', { name: billName, amount, dueDay, remindDays: num('remind_days') > 0 ? Math.round(num('remind_days')) : 3,
        match: str('match'), category: 'Bills', paidMonths: [], notes: '', createdAt: now })
      return { result: `Bill added. This month: ${billStatus(store.get<Bill>(id)!)}.`,
        action: { text: `Bill “${billName}” · day ${dueDay}${amount > 0 ? ` · ${moneyFmt(amount)}` : ''}`, symbol: 'doc.text', undo: { kind: 'records', ids: [id] } } }
    }

    case 'create_goal': {
      const title = str('title')
      if (!title) return bad('title is required')
      const kind = (['books', 'save', 'habit', 'steps'].includes(str('kind')) ? str('kind') : 'steps') as Goal['kind']
      const start = dayDate(str('start')) ?? startOfDay(new Date())
      const deadline = dayDate(str('deadline'))
      let target = num('target'), steps: string[] = [], habitUUID = ''
      if (kind === 'steps') {
        steps = strings('steps')
        if (!steps.length) return bad('steps goals need at least one step')
        target = steps.length
      } else if (kind === 'habit') {
        const want = lower(str('habit'))
        const h = want ? store.list<Habit>('habit').find((x) => lower(x.data.name).includes(want)) : undefined
        if (!h) return bad(`No habit called ${str('habit')}. Create the habit first.`)
        habitUUID = h.id
      }
      if (!(target > 0)) return bad('target must be positive')
      const g: Goal = { title, kind, target, start: iso(start), deadline: deadline ? iso(deadline) : null, habitUUID, bucketUUID: '',
        steps, stepsDone: [], doneAt: null, createdAt: now }
      const id = store.create<Goal>('goal', g)
      const p = goalProgress(g)
      return { result: `Goal created. Progress so far: ${p}.`, action: { text: `Goal “${title}” · ${p}`, symbol: 'flag.checkered', undo: { kind: 'records', ids: [id] } } }
    }

    case 'add_to_shared_list': {
      if (!sharedAvailable()) return bad('Shared lists need a Joshu account; they aren\'t signed in.')
      if (!sharedListsNow().length) await refreshShared()
      const lists = sharedListsNow()
      const want = lower(str('list'))
      const list = (want ? lists.find((l) => lower(l.title).includes(want)) : undefined) ?? (lists.length === 1 ? lists[0] : undefined)
      if (!list) return bad(lists.length ? `No shared list called ${str('list')}. Lists: ${lists.map((l) => l.title).join(', ')}.` : 'They have no shared lists (Tasks › Shared lists).')
      const items = strings('items')
      if (!items.length) return bad('items is empty')
      for (const t of items) await putItem(newItem(t), list)
      return { result: `Added ${items.length} to ${list.title}.`, action: { text: `${list.title}: ${items.join(', ')}`, symbol: 'person.2.fill' } }
    }

    case 'add_idea': {
      const text = str('idea')
      if (!text) return bad('idea is required')
      const project = ideaProject(str('project'))
      const ideas = store.list<Idea>('idea')
      const under = lower(str('under'))
      const parent = under ? ideas.find((i) => i.data.projectUUID === project.id && lower(i.data.title).includes(under)) : undefined
      let title = text, body = str('details')
      if (text.length > 90) {
        const first = text.split(/[.!?\n]/)[0] ?? text
        title = first.length <= 90 ? first : `${text.slice(0, 80)}…`
        body = body ? `${text}\n\n${body}` : text
      }
      const id = store.create<Idea>('idea', { projectUUID: project.id, parentUUID: parent?.id ?? '', title: title.trim(), body, pinned: false, createdAt: now, updatedAt: now })
      store.update<IdeaProject>(project.id, { updatedAt: now })
      if (parent) store.update<Idea>(parent.id, { updatedAt: now })
      return { result: `Saved to ${project.data.title}${parent ? ` under “${parent.data.title}”` : ''}.`,
        action: { text: `Idea in ${project.data.title}: “${title.trim()}”`, symbol: 'lightbulb.max.fill', undo: { kind: 'records', ids: [id] } } }
    }

    case 'update_idea': {
      const projects = store.list<IdeaProject>('ideaProject')
      const all = store.list<Idea>('idea')
      const want = lower(str('idea')), proj = lower(str('project'))
      const inProject = proj ? all.filter((i) => { const p = projects.find((x) => x.id === i.data.projectUUID); return !!p && (lower(p.data.title).includes(proj) || proj.includes(lower(p.data.title))) }) : all
      const idea = inProject.find((i) => lower(i.data.title) === want) ?? (want ? inProject.find((i) => lower(i.data.title).includes(want) || want.includes(lower(i.data.title))) : undefined)
      if (!idea) return bad(`No idea called “${str('idea')}”. Use get_ideas to see them.`)
      const before = idea.data.body ?? ''
      let body = before
      if (str('mode') === 'replace') body = str('text')
      else if (str('text')) body = before ? `${before}\n\n${str('text')}` : str('text')
      const title = str('new_title') || idea.data.title
      store.update<Idea>(idea.id, { body, title, updatedAt: now })
      store.update<IdeaProject>(idea.data.projectUUID, { updatedAt: now })
      return { result: `Updated “${title}”${before ? ` (it had ${before.length} characters before).` : '.'}`, action: { text: `Idea “${title}” updated`, symbol: 'lightbulb.max.fill' } }
    }

    case 'get_ideas': {
      const projects = store.list<IdeaProject>('ideaProject').filter((p) => !p.data.archived)
      const all = store.list<Idea>('idea').sort((a, b) => (a.data.createdAt ?? '').localeCompare(b.data.createdAt ?? ''))
      const want = lower(str('project'))
      const chosen = want ? projects.filter((p) => lower(p.data.title).includes(want) || want.includes(lower(p.data.title))) : projects
      if (!chosen.length) return { result: projects.length ? `Projects: ${projects.map((p) => p.data.title).join(', ')}` : 'No projects yet.' }
      const lines = (parent: string, depth: number, p: Rec<IdeaProject>): string[] =>
        all.filter((i) => i.data.projectUUID === p.id && (i.data.parentUUID ?? '') === parent).flatMap((i) => [
          `${'  '.repeat(depth)}- ${i.data.title}${i.data.body ? `: ${i.data.body.slice(0, depth === 0 ? 600 : 200)}` : ''}`,
          ...(depth < 3 ? lines(i.id, depth + 1, p) : []),
        ])
      return { result: chosen.map((p) => `PROJECT ${p.data.title}${p.data.summary ? ` (${p.data.summary})` : ''}\n${lines('', 0, p).join('\n')}`).join('\n\n') }
    }

    case 'goodreads_review':
    case 'goodreads_progress': {
      const books = store.list<Book>('book')
      const want = lower(str('book'))
      const book = books.find((b) => lower(b.data.title) === want)
        ?? (want ? books.find((b) => lower(b.data.title).includes(want) || want.includes(lower(b.data.title).split(':')[0] || '~')) : undefined)
      if (!book) return bad(`No book called “${str('book')}” in their library. Ask which one, or add it first.`)
      if (name === 'goodreads_review') {
        const rating = Math.round(num('rating'))
        store.update<Book>(book.id, { notes: str('review'), ...(rating > 0 ? { rating: Math.min(5, rating) } : {}) })
        const msg = await postReview(store.get<Book>(book.id) ?? book, str('review'), rating)
        return { result: msg, action: { text: `Review of “${book.data.title}”: ${msg}`, symbol: 'book.fill' } }
      }
      const page = Math.round(num('page')), percent = Math.round(num('percent'))
      let progress: number
      if (page > 0 && book.data.pageCount > 0) progress = Math.min(1, page / book.data.pageCount)
      else if (percent > 0) progress = Math.min(1, percent / 100)
      else return bad('Give percent or page.')
      const patch: Partial<Book> = { progress }
      if (progress >= 1) { patch.status = 'read'; patch.finishedAt = book.data.finishedAt ?? now }
      else if (book.data.status === 'toRead') { patch.status = 'reading'; patch.startedAt = book.data.startedAt ?? now }
      store.update<Book>(book.id, patch)
      const msg = getGoodreads().signedIn ? await pushProgress(store.get<Book>(book.id) ?? book, true) : "Saved in Joshu. (Not signed in to Goodreads, so it wasn't sent there.)"
      return { result: msg, action: { text: `“${book.data.title}” → ${Math.round(progress * 100)}%`, symbol: 'book.fill' } }
    }

    case 'read_browser_tab':
      return bad("Reading the browser tab only works in Joshu on the Mac. Ask them to paste the link and use web_fetch.")

    default: {
      const out = await runShared(name, input)
      return { result: out.result, isError: out.isError, action: out.action ? { text: out.action.text, symbol: sfSymbol(out.action.symbol), undo: out.action.undo } : undefined }
    }
  }
}

export function undo(u: Undo): void {
  if (u.kind === 'memory') setMemories(memories().filter((m) => m !== u.fact))
  else undoShared(u)
}

// MARK: Helpers

/** The project with this name (made if new), like IdeaStore.project(named:). */
function ideaProject(nameIn: string): Rec<IdeaProject> {
  const name = nameIn.trim() || 'Ideas'
  const projects = store.list<IdeaProject>('ideaProject')
  const n = lower(name)
  const hit = projects.find((p) => lower(p.data.title) === n) ?? projects.find((p) => !p.data.archived && (lower(p.data.title).includes(n) || n.includes(lower(p.data.title))))
  if (hit) return hit
  const now = iso(new Date())
  const id = store.create<IdeaProject>('ideaProject', { title: name, summary: '', colorIndex: projects.length % 7, archived: false, createdAt: now, updatedAt: now })
  return store.get<IdeaProject>(id)!
}

/** This month's state of a bill, in words (BillTracker.describe). */
function billStatus(b: Rec<Bill>): string {
  const today = startOfDay(new Date())
  const last = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate()
  let due = new Date(today.getFullYear(), today.getMonth(), Math.min(Math.max(1, b.data.dueDay || 1), last))
  // Added after this month's due day: it's next month's bill that counts (BillTracker.current).
  const created = parse(b.data.createdAt)
  if (created && due < startOfDay(created) && !(b.data.paidMonths ?? []).includes(monthKey(due))) {
    const nextLast = new Date(today.getFullYear(), today.getMonth() + 2, 0).getDate()
    due = new Date(today.getFullYear(), today.getMonth() + 1, Math.min(Math.max(1, b.data.dueDay || 1), nextLast))
  }
  if ((b.data.paidMonths ?? []).includes(monthKey(due))) return 'paid'
  const words = (b.data.match || b.data.name).toLowerCase().split(',').map((w) => w.trim()).filter((w) => w.length >= 2)
  const from = addDays(due, -20).getTime(), to = addDays(due, 11).getTime()
  const paid = store.list<Txn>('transaction').some((t) => {
    const d = parse(t.data.date)?.getTime() ?? 0
    return t.data.amount < 0 && d >= from && d < to && words.some((w) => (t.data.title ?? '').toLowerCase().includes(w))
  })
  if (paid) return 'paid'
  const days = daysBetween(today, due)
  return days < 0 ? `${-days} day${days === -1 ? '' : 's'} late` : days === 0 ? 'due today' : `due in ${days} day${days === 1 ? '' : 's'}`
}

/** Progress in words (GoalTracker.describe). */
function goalProgress(g: Goal): string {
  const start = startOfDay(parse(g.start) ?? new Date()).getTime()
  if (g.kind === 'books') {
    const n = store.list<Book>('book').filter((b) => b.data.status === 'read' && (parse(b.data.finishedAt)?.getTime() ?? -Infinity) >= start).length
    return `${n} of ${Math.floor(g.target)} books`
  }
  if (g.kind === 'save') {
    const v = Math.max(0, store.list<Txn>('transaction').reduce((s, t) => s + ((parse(t.data.date)?.getTime() ?? 0) >= start ? t.data.amount : 0), 0))
    return `${moneyFmt(v)} of ${moneyFmt(g.target)}`
  }
  if (g.kind === 'habit') {
    const key = dayKey(new Date(start))
    const n = store.get<Habit>(g.habitUUID)?.data.doneDays.filter((d) => d >= key).length ?? 0
    return `${n} of ${Math.floor(g.target)} days`
  }
  return `${(g.steps ?? []).filter((s) => (g.stepsDone ?? []).includes(s)).length} of ${(g.steps ?? []).length} steps`
}

/** get_overview: the shared day snapshot plus what the Mac adds (calendar, places, documents, subscriptions, bills, goals, shared lists). */
function overview(): string {
  let text = sharedOverview()
  const today = startOfDay(new Date())
  const google = externalEvents(today, addDays(today, 8)).sort((a, b) => a.start.getTime() - b.start.getTime())
  if (google.length) {
    text += `\n\nGoogle Calendar (next 7 days):\n${google.slice(0, 40).map((e) => `- ${fmtDay(e.start, { weekday: 'short', day: 'numeric', month: 'short' })} ${e.allDay ? 'all day' : `${fmtTime(e.start)}-${fmtTime(e.end)}`} ${e.title}${e.calendar ? ` [${e.calendar}]` : ''}`).join('\n')}`
  }
  const places = store.list<Bucket & { place?: { category?: string } }>('bucket').filter((b) => (b.data.kind as string) === 'place' && !b.data.isDone)
  text += '\n\n'
  if (places.length) text += `Go to places saved: ${places.slice(0, 20).map((p) => `${p.data.title} (${placeTitle(p.data.place?.category ?? 'other')})`).join('; ')}. `
  const docs = store.list<Doc>('document').map((d) => ({ d, left: d.data.expires ? daysBetween(today, parse(d.data.expires)!) : 999 })).filter((x) => x.left <= 90)
  text += `Documents expiring within 90 days: ${docs.length ? docs.map((x) => `${x.d.data.title} (${x.left} days)`).join(', ') : 'none'}. `
  const subs = store.list<Subscription>('subscription').filter((s) => s.data.status !== 'cancelled')
  const perMonth: Record<string, number> = { weekly: 52 / 12, monthly: 1, quarterly: 1 / 3, yearly: 1 / 12 }
  const monthly = subs.reduce((s, x) => s + (Number(x.data.amount) || 0) * (perMonth[x.data.cycle] ?? 1), 0)
  text += `Subscriptions: ${subs.length}, ${moneyFmt(monthly)} a month (${subs.slice(0, 15).map((s) => `${s.data.name} ${moneyFmt(s.data.amount)}/${s.data.cycle}`).join(', ')}). `
  const bills = store.list<Bill>('bill')
  if (bills.length) text += `Bills: ${bills.map((b) => `${b.data.name} day ${b.data.dueDay} (${billStatus(b)})`).join(', ')}. `
  const goals = store.list<Goal>('goal').filter((g) => !g.data.doneAt)
  if (goals.length) text += `Goals: ${goals.map((g) => `${g.data.title} (${cap(g.data.kind)}: ${goalProgress(g.data)}${g.data.deadline ? `, by ${parse(g.data.deadline)?.toDateString()}` : ''})`).join('; ')}. `
  const lists = sharedListsNow()
  if (lists.length) text += `Shared lists: ${lists.map((l) => `${l.title} (${openCount(l)} open)`).join(', ')}. `
  return text
}
