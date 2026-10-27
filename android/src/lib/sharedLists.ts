// Shared lists (groceries, a trip plan) between Joshu users, like SharedLists.swift on the Mac. They live in Supabase's
// `shared_lists` table (supabase/shared_lists.sql), not in orbit_records: everyone on a list reads and writes the same
// row. A list is shared by its six-letter code; whoever joins with the code can see and edit it.
import { useEffect, useState } from 'react'
import { rest, getSession, onSessionChange, CloudError } from '@/lib/cloud'
import { store } from '@/lib/store'
import { iso, parse } from '@/lib/dates'

export interface SharedItem {
  id: string
  text: string
  done: boolean
  /** First name of whoever added it. */
  by: string
  at: string | null
}

export interface SharedList {
  id: string
  code: string
  title: string
  ownerID: string
  memberCount: number
  items: SharedItem[]
  updatedAt: string | null
}

export const isMine = (l: SharedList): boolean => !!l.ownerID && l.ownerID === getSession()?.userID
export const openCount = (l: SharedList): number => l.items.filter((i) => !i.done).length
export const inviteText = (l: SharedList): string =>
  `Join my Joshu list “${l.title}”: in Joshu open Tasks › Shared lists › Join and enter ${l.code}.`

/** Your first name, shown next to the items you add. */
export const me = (): string => (store.setting<string>('userName') ?? '').trim().split(/\s+/)[0] ?? ''

export function newItem(text: string, by = me()): SharedItem {
  return { id: crypto.randomUUID().toLowerCase(), text, done: false, by, at: iso(new Date()) }
}

const DEMO = typeof location !== 'undefined' && new URLSearchParams(location.search).has('demo')
const SETUP_KEY = 'sharedLists.setUp'
const SELECT = 'select=id,code,title,owner,members,items,updated_at'
const SETUP_MSG = 'Shared lists need a one-time setup: run supabase/shared_lists.sql in Supabase › SQL Editor.'

interface State {
  lists: SharedList[]
  loading: boolean
  error: string | null
  /** False once Joshu has seen that the shared_lists table isn't in Supabase yet: the feature then stays out of sight. */
  isSetUp: boolean
}

const demoItem = (text: string, by: string, done = false): SharedItem => ({ ...newItem(text, by), done })
const demoLists = (): SharedList[] => [
  { id: 'demo-groceries', code: 'K7Q2MX', title: 'Groceries', ownerID: '', memberCount: 2, updatedAt: iso(new Date()), items: [
    demoItem('Eggs', 'Alex'), demoItem('Tomatoes and cucumbers', 'Sara'), demoItem('Greek yogurt', 'Sara'), demoItem('Coffee beans', 'Alex', true),
  ] },
  { id: 'demo-dahab', code: 'D4HB9T', title: 'Dahab weekend', ownerID: '', memberCount: 3, updatedAt: iso(new Date()), items: [
    demoItem('Book the bus', 'Omar', true), demoItem('Snorkel gear', 'Alex'), demoItem('Sunscreen', 'Sara'),
  ] },
]

let state: State = {
  lists: DEMO ? demoLists() : [],
  loading: false,
  error: null,
  isSetUp: (() => { try { return localStorage.getItem(SETUP_KEY) !== 'false' } catch { return true } })(),
}
const subs = new Set<() => void>()

function set(patch: Partial<State>): void {
  state = { ...state, ...patch }
  if (patch.isSetUp !== undefined) { try { localStorage.setItem(SETUP_KEY, String(patch.isSetUp)) } catch { /* storage unavailable */ } }
  subs.forEach((f) => f())
}

function changeList(id: string, change: (l: SharedList) => SharedList): void {
  set({ lists: state.lists.map((l) => (l.id === id ? change(l) : l)) })
}

export const isAvailable = (): boolean => DEMO || !!getSession()

/** The lists, kept current for any component that reads them. */
export function useSharedLists(): State {
  const [, force] = useState(0)
  useEffect(() => {
    const f = () => force((n) => n + 1)
    subs.add(f)
    const off = onSessionChange(() => { f(); refresh() })
    return () => { subs.delete(f); off() }
  }, [])
  return state
}

export function clearError(): void { if (state.error) set({ error: null }) }

// MARK: Plumbing

function message(e: unknown): string { return e instanceof Error ? e.message : String(e) }

async function call(path: string, init: { method?: string; body?: unknown; prefer?: string } = {}): Promise<any> {
  try {
    return await rest(path, init)
  } catch (e) {
    const m = message(e)
    if (m.includes('404') || m.includes('shared_list') || m.includes("aren't set up")) throw new CloudError(SETUP_MSG)
    throw e
  }
}

async function rpc(name: string, body: Record<string, unknown>): Promise<void> {
  try { await call(`rpc/${name}`, { method: 'POST', body }) } catch (e) { set({ error: message(e) }) }
}

function parseItem(d: any): SharedItem | null {
  if (!d || typeof d.id !== 'string') return null
  return { id: d.id, text: String(d.text ?? ''), done: !!d.done, by: String(d.by ?? ''), at: typeof d.at === 'string' && parse(d.at) ? d.at : null }
}

function parseList(r: any): SharedList | null {
  if (!r || typeof r.id !== 'string') return null
  return {
    id: r.id, code: String(r.code ?? ''), title: String(r.title ?? ''), ownerID: String(r.owner ?? ''),
    memberCount: Array.isArray(r.members) ? r.members.length : 1,
    items: (Array.isArray(r.items) ? r.items : []).map(parseItem).filter((i: SharedItem | null): i is SharedItem => !!i),
    updatedAt: r.updated_at ?? null,
  }
}

// MARK: Actions

let inFlight: Promise<void> | null = null

export function refresh(): Promise<void> {
  if (DEMO) { if (!state.lists.length) set({ lists: demoLists() }); return Promise.resolve() }
  if (!getSession()) { if (state.lists.length) set({ lists: [] }); return Promise.resolve() }
  inFlight ??= (async () => {
    set({ loading: true })
    try {
      const rows = await call(`shared_lists?${SELECT}&order=updated_at.desc`)
      set({ lists: (Array.isArray(rows) ? rows : []).map(parseList).filter((l): l is SharedList => !!l), error: null, isSetUp: true })
    } catch (e) {
      const m = message(e)
      if (m.includes('one-time setup')) set({ isSetUp: false, error: null })
      else set({ error: m })
    } finally {
      set({ loading: false })
      inFlight = null
    }
  })()
  return inFlight
}

export async function createList(title: string): Promise<SharedList | null> {
  const t = title.trim()
  if (!t) return null
  if (DEMO) {
    const l: SharedList = { id: crypto.randomUUID(), code: 'DEMO42', title: t, ownerID: '', memberCount: 1, items: [], updatedAt: iso(new Date()) }
    set({ lists: [l, ...state.lists] })
    return l
  }
  try {
    const rows = await call(`shared_lists?${SELECT}`, { method: 'POST', body: [{ title: t }], prefer: 'return=representation' })
    const l = Array.isArray(rows) && rows.length ? parseList(rows[0]) : null
    if (l) set({ lists: [l, ...state.lists], error: null })
    return l
  } catch (e) {
    set({ error: message(e) })
    return null
  }
}

/** Joins someone else's list by its code. */
export async function joinList(code: string): Promise<boolean> {
  const c = code.trim().toUpperCase()
  if (c.length < 4) { set({ error: 'Enter the code from the invite.' }); return false }
  if (DEMO) { set({ error: `No list has the code ${c}.` }); return false }
  try {
    const id = await call('rpc/join_shared_list', { method: 'POST', body: { p_code: c } })
    if (typeof id !== 'string') { set({ error: `No list has the code ${c}.` }); return false }
    set({ error: null })
    await refresh()
    return true
  } catch (e) {
    const m = message(e)
    set({ error: m.includes('not found') ? `No list has the code ${c}.` : m })
    return false
  }
}

/** Adds an item, or replaces the one with the same id. */
export async function putItem(item: SharedItem, list: SharedList): Promise<void> {
  changeList(list.id, (l) => {
    const i = l.items.findIndex((x) => x.id === item.id)
    return { ...l, items: i >= 0 ? l.items.map((x) => (x.id === item.id ? item : x)) : [...l.items, item] }
  })
  if (DEMO) return
  await rpc('shared_list_put_item', { p_list: list.id, p_item: item })
}

export async function removeItem(item: SharedItem, list: SharedList): Promise<void> {
  changeList(list.id, (l) => ({ ...l, items: l.items.filter((x) => x.id !== item.id) }))
  if (DEMO) return
  await rpc('shared_list_remove_item', { p_list: list.id, p_id: item.id })
}

export async function clearDone(list: SharedList): Promise<void> {
  for (const item of list.items.filter((i) => i.done)) await removeItem(item, list)
}

export async function renameList(list: SharedList, title: string): Promise<void> {
  const t = title.trim()
  if (!t) return
  changeList(list.id, (l) => ({ ...l, title: t }))
  if (DEMO) return
  try { await call(`shared_lists?id=eq.${list.id}`, { method: 'PATCH', body: { title: t }, prefer: 'return=minimal' }) } catch { /* next refresh shows the real title */ }
}

/** Leaves the list. The owner leaving deletes it for everyone. */
export async function leaveList(list: SharedList): Promise<void> {
  set({ lists: state.lists.filter((l) => l.id !== list.id) })
  if (DEMO) return
  await rpc('leave_shared_list', { p_list: list.id })
}
