// Local cache of your Orbit records plus two-way sync with Supabase.
// Same table and row format as the Mac app: one row per item, its fields as JSON in `data`.
// Edits are saved locally at once and pushed within a couple of seconds; other devices' changes are
// pulled every 20 seconds and whenever the window regains focus. Fields this app doesn't know about
// (for example a journal chat written on the Mac) are kept untouched when an item is edited here.

import { useSyncExternalStore, useMemo } from 'react'
import { getSession, rest, CloudError } from './cloud'

export interface Rec<T = Record<string, any>> {
  id: string
  kind: string
  data: T
  deleted: boolean
  updated_at?: string
}

/** Settings that follow you between devices (same list as the Mac app). */
export const SYNCED_SETTINGS = ['monthlyBudget', 'readingGoal', 'currencyCode', 'assistantName', 'userName', 'weatherCity', 'profileCard',
  'merchantRules', 'categoryBudgets', 'assistant.memory', 'assistantSpeaks', 'goodreadsUser', 'budget.periodStart', 'notify.budgets', 'notify.bigCharges', 'spendAlerts.sent', 'hiddenTabs', 'launchSound',
  'notify.tasks', 'notify.events', 'notify.bills', 'notify.habits', 'notify.journal', 'notify.review', 'notify.subscriptions', 'notify.evening', 'notify.trips',
  'notify.weeklyMoney', 'notify.morningHour', 'notify.habitHour', 'notify.journalHour', 'notify.eventLead', 'cardPhoto', 'profile.photo'] as const
export type SettingKey = (typeof SYNCED_SETTINGS)[number]

interface Cache {
  cursor: string
  records: Record<string, Rec>
  pending: Record<string, Rec>
  /** Local mode only: the account a kept copy came from. Its edits go back only into that account. */
  owner?: string
}

/** Where Joshu keeps your data when you use it without an account (Android). */
export const LOCAL_CACHE = 'orbit.cache.local'
const ACCOUNT_CACHE = /^orbit\.cache\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

class Store {
  private records = new Map<string, Rec>()
  private pending = new Map<string, Rec>()
  private cursor = ''
  private userID = ''
  private version = 0
  private subs = new Set<() => void>()
  private settingIDs = new Map<string, string>()
  private pushTimer: ReturnType<typeof setTimeout> | null = null
  private saveTimer: ReturnType<typeof setTimeout> | null = null
  private loop: ReturnType<typeof setInterval> | null = null
  private local = false
  private localOwner: string | undefined
  syncing = false
  lastSync: Date | null = null
  /** Edits made here that haven't reached the account yet. */
  get unsent(): number { return this.pending.size }
  status = ''

  // MARK: Lifecycle

  async start(): Promise<void> {
    const s = getSession()
    if (!s) return
    if (this.local) this.stop() // signing in from local mode: adoptLocal() then brings its edits in
    this.userID = s.userID
    for (const key of SYNCED_SETTINGS) this.settingIDs.set(key, await settingID(key))
    this.load()
    this.emit()
    await this.sync()
    this.loop ??= setInterval(() => this.sync(), 20_000)
    window.addEventListener('focus', this.onFocus)
  }

  /** Preview with sample data held in memory only (no account, nothing synced). */
  async startDemo(records: Rec[], settings: Partial<Record<SettingKey, unknown>>): Promise<void> {
    for (const key of SYNCED_SETTINGS) this.settingIDs.set(key, await settingID(key))
    this.records = new Map(records.map((r) => [r.id, r]))
    for (const [k, v] of Object.entries(settings)) {
      const id = this.settingIDs.get(k)!
      this.records.set(id, { id, kind: 'setting', data: { key: k, value: v }, deleted: false })
    }
    this.status = 'Demo data'
    this.emit()
  }

  /** Using Joshu without an account: everything stays on this device under LOCAL_CACHE and nothing syncs.
   *  The first time, a copy kept on this device at sign-out (the most recently synced account) is carried on with. */
  async startLocal(): Promise<void> {
    if (getSession()) return
    for (const key of SYNCED_SETTINGS) this.settingIDs.set(key, await settingID(key))
    let c = readCache(LOCAL_CACHE)
    if (!c) {
      let best: { key: string; cache: Cache } | null = null
      for (const key of Object.keys(localStorage)) {
        if (!ACCOUNT_CACHE.test(key)) continue
        const cache = readCache(key)
        if (cache && (!best || (cache.cursor ?? '') > (best.cache.cursor ?? ''))) best = { key, cache }
      }
      if (best) c = { cursor: '', records: best.cache.records, pending: {}, owner: best.key.slice('orbit.cache.'.length) }
    }
    this.records = new Map(Object.entries(c?.records ?? {}))
    this.pending = new Map(Object.entries(c?.pending ?? {}))
    this.localOwner = c?.owner
    this.cursor = ''
    this.userID = ''
    this.local = true
    this.status = 'On this device only'
    this.writeLocal()
    this.emit()
  }

  /** True while using Joshu without an account. */
  get isLocal(): boolean { return this.local }

  /** Whether there's data made without an account waiting to come into the account you sign in to. */
  hasLocalData(): boolean {
    const c = readCache(LOCAL_CACHE)
    return !!c && Object.values(c.pending ?? {}).some((r) => !r.deleted)
  }

  /** Right after start() on sign-in (like the Mac's adoptDevice): what you did without an account comes into this
   *  account and syncs up, then the local copy is removed. Joshu never moves one account's data into another, so
   *  edits to a copy kept from a different account are dropped (they're safe in that account up to sign-out).
   *  Settings already set in the account keep the account's value. Returns how many items were brought in. */
  async adoptLocal(): Promise<number> {
    const c = readCache(LOCAL_CACHE)
    if (!c || !this.userID) return 0
    let moved = 0
    if (!c.owner || c.owner.toLowerCase() === this.userID.toLowerCase()) {
      for (const r of Object.values(c.pending ?? {})) {
        if (!c.owner && r.deleted) continue // never reached any account
        if (!c.owner && r.kind === 'setting' && this.records.get(r.id) && !this.records.get(r.id)!.deleted) continue
        const { updated_at: _, ...rec } = r
        this.records.set(r.id, rec)
        this.pending.set(r.id, rec)
        moved++
      }
    }
    localStorage.removeItem(LOCAL_CACHE)
    if (moved) {
      this.emit()
      this.save()
      await this.sync()
    }
    return moved
  }

  /** Removes everything kept without an account (e.g. when deleting it from this device). */
  discardLocal(): void {
    localStorage.removeItem(LOCAL_CACHE)
    if (this.local) { this.records.clear(); this.pending.clear(); this.localOwner = undefined; this.emit() }
  }

  private writeLocal(): void {
    const c: Cache = { cursor: '', records: Object.fromEntries(this.records), pending: Object.fromEntries(this.pending), owner: this.localOwner }
    try { localStorage.setItem(LOCAL_CACHE, JSON.stringify(c)) } catch { /* storage full: kept in memory */ }
  }

  stop(): void {
    if (this.local) { this.writeLocal(); this.local = false; this.localOwner = undefined; this.status = '' }
    if (this.loop) clearInterval(this.loop)
    this.loop = null
    window.removeEventListener('focus', this.onFocus)
    this.records.clear()
    this.pending.clear()
    this.cursor = ''
    this.userID = ''
    this.emit()
  }

  private onFocus = (): void => { this.sync() }

  private load(): void {
    try {
      const c: Cache = JSON.parse(localStorage.getItem(`orbit.cache.${this.userID}`) ?? 'null')
      if (!c) return
      this.cursor = c.cursor
      this.records = new Map(Object.entries(c.records))
      this.pending = new Map(Object.entries(c.pending))
    } catch { /* start fresh */ }
  }

  private save(): void {
    if (this.saveTimer) clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => {
      if (this.local) { this.writeLocal(); return }
      if (!this.userID) return
      const c: Cache = { cursor: this.cursor, records: Object.fromEntries(this.records), pending: Object.fromEntries(this.pending) }
      localStorage.setItem(`orbit.cache.${this.userID}`, JSON.stringify(c))
    }, 300)
  }

  // MARK: Subscriptions (React)

  subscribe = (fn: () => void): (() => void) => {
    this.subs.add(fn)
    return () => this.subs.delete(fn)
  }
  getVersion = (): number => this.version
  private emit(): void {
    this.version++
    this.subs.forEach((s) => s())
  }

  // MARK: Reading

  list<T>(kind: string): Rec<T>[] {
    const out: Rec<T>[] = []
    this.records.forEach((r) => { if (r.kind === kind && !r.deleted) out.push(r as Rec<T>) })
    return out
  }

  get<T>(id: string): Rec<T> | undefined {
    const r = this.records.get(id)
    return r && !r.deleted ? (r as Rec<T>) : undefined
  }

  setting<T = any>(key: SettingKey): T | undefined {
    const id = this.settingIDs.get(key)
    const r = id ? this.records.get(id) : undefined
    return r && !r.deleted ? (r.data as any).value ?? undefined : undefined
  }

  // MARK: Writing

  create<T extends object>(kind: string, data: T): string {
    const id = crypto.randomUUID().toLowerCase()
    this.write({ id, kind, data: { ...data }, deleted: false })
    return id
  }

  /** Creates or replaces an item whose id is chosen by the caller (e.g. an assistant chat). */
  put<T extends object>(id: string, kind: string, data: T): void {
    this.write({ id, kind, data: { ...data }, deleted: false })
  }

  /** Merges `patch` into the item's fields, keeping everything else as it was. */
  update<T extends object>(id: string, patch: Partial<T>): void {
    const r = this.records.get(id)
    if (!r || r.deleted) return
    this.write({ ...r, data: { ...r.data, ...patch } })
  }

  remove(id: string): void {
    const r = this.records.get(id)
    if (!r) return
    this.write({ ...r, data: {}, deleted: true })
  }

  setSetting(key: SettingKey, value: unknown): void {
    const id = this.settingIDs.get(key)
    if (!id) return
    this.write({ id, kind: 'setting', data: { key, value }, deleted: false })
  }

  private write(r: Rec): void {
    this.records.set(r.id, r)
    if (this.local) { this.pending.set(r.id, r); this.emit(); this.save(); return } // no account: this device only
    if (!this.userID) { this.emit(); return } // demo preview: keep it in memory
    this.pending.set(r.id, r)
    this.emit()
    this.save()
    if (this.pushTimer) clearTimeout(this.pushTimer)
    this.pushTimer = setTimeout(() => this.sync(), 1500)
  }

  // MARK: Sync

  async sync(): Promise<void> {
    if (this.syncing || !this.userID) return
    this.syncing = true
    try {
      const pushed = await this.push()
      const pulled = await this.pull()
      this.lastSync = new Date()
      this.status = pushed + pulled === 0 ? 'Up to date' : `Synced ${pulled} down, ${pushed} up`
    } catch (e) {
      this.status = e instanceof CloudError ? e.message : navigator.onLine ? String(e) : 'Offline: changes will sync when you reconnect.'
    } finally {
      this.syncing = false
      this.emit()
      this.save()
    }
  }

  private async pull(): Promise<number> {
    let applied = 0
    for (;;) {
      const q = new URLSearchParams({ select: 'id,kind,data,deleted,updated_at', order: 'updated_at.asc,id.asc', limit: '1000' })
      if (this.cursor) q.set('updated_at', `gt.${this.cursor}`)
      const rows: Rec[] = (await rest(`orbit_records?${q.toString()}`)) ?? []
      for (const row of rows) {
        if (row.updated_at) this.cursor = row.updated_at
        if (row.kind === 'vault') continue // encrypted keys: not used here yet
        if (this.pending.has(row.id)) continue // edited here and not sent yet: ours wins
        this.records.set(row.id, { id: row.id, kind: row.kind, data: row.data ?? {}, deleted: !!row.deleted, updated_at: row.updated_at })
        applied++
      }
      if (rows.length < 1000) break
    }
    return applied
  }

  private async push(): Promise<number> {
    const rows = [...this.pending.values()]
    if (!rows.length) return 0
    for (let i = 0; i < rows.length; i += 200) {
      const chunk = rows.slice(i, i + 200)
      await rest('orbit_records?on_conflict=user_id,id', {
        method: 'POST',
        prefer: 'resolution=merge-duplicates,return=minimal',
        body: chunk.map((r) => ({ id: r.id, user_id: this.userID, kind: r.kind, data: r.data, deleted: r.deleted })),
      })
      // Only clear what we sent, in case it was edited again meanwhile.
      for (const r of chunk) if (this.pending.get(r.id) === r) this.pending.delete(r.id)
    }
    return rows.length
  }
}

function readCache(key: string): Cache | null {
  try { return JSON.parse(localStorage.getItem(key) ?? 'null') } catch { return null }
}

/** Same id the Mac app uses for a setting: the first 16 bytes of SHA-256("orbit-setting:<key>") as a UUID. */
async function settingID(key: string): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`orbit-setting:${key}`)))
  const b = h.slice(0, 16)
  b[6] = (b[6] & 0x0f) | 0x50
  b[8] = (b[8] & 0x3f) | 0x80
  const hex = [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

export const store = new Store()

/** Re-renders when anything in the store changes. */
export function useStoreVersion(): number {
  return useSyncExternalStore(store.subscribe, store.getVersion)
}

/** All live items of one kind, e.g. useRecords<Task>('task'). */
export function useRecords<T>(kind: string): Rec<T>[] {
  const v = useStoreVersion()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  return useMemo(() => store.list<T>(kind), [kind, v])
}

export function useSetting<T>(key: SettingKey, fallback: T): T {
  useStoreVersion()
  const v = store.setting<T>(key)
  return v === undefined || v === null ? fallback : v
}
