// Spending alerts on Android, like SpendingAlerts in MoneySmarts.swift on the Mac: a notification when a category budget
// (synced "categoryBudgets") or the monthly budget reaches 80% / 100% in the current budget month, and for a charge far
// bigger than you usually spend. Switches: synced "notify.budgets" / "notify.bigCharges" (default on).
// Each alert is sent once. The "already sent" memory is "spendAlerts.sent", a list of alert ids as on the Mac
// ("2026-10|Food|80", "2026-10|month|100", "big|<transaction id>"), newest 300 kept. It lives on the phone and, once
// "spendAlerts.sent" is a synced setting, is shared with the Mac and iPhone too so they don't all nag.
import { LocalNotifications } from '@capacitor/local-notifications'
import { store, Rec, SettingKey } from '@/lib/store'
import { Txn } from '@/lib/models'
import { parse } from '@/lib/dates'
import { defaultCurrency } from '@/components/ui'
import { currentPeriod } from './lib/budgetPeriod'
import { isNative } from './native'

export interface SpendingAlert { id: string; title: string; body: string }

const SENT_KEY = 'spendAlerts.sent'
const DAY = 86_400_000

const flag = (key: string): boolean => store.setting<boolean>(key as SettingKey) ?? true
const budgetAlerts = () => flag('notify.budgets')
const bigChargeAlerts = () => flag('notify.bigCharges')

/** Category limits above 0 (SpendingAlerts.budgets). */
function budgets(): Record<string, number> {
  const b = store.setting<Record<string, number>>('categoryBudgets') ?? {}
  return Object.fromEntries(Object.entries(b).map(([k, v]) => [k, Number(v) || 0]).filter(([, v]) => (v as number) > 0))
}

const monthlyBudget = (): number => {
  const v = store.setting('monthlyBudget')
  return v === undefined || v === null ? 2000 : Number(v) || 0
}

/** Fmt.money: the currency with 0–2 decimals. */
function money(v: number): string {
  const code = store.setting<string>('currencyCode') || defaultCurrency()
  const s = (() => {
    try { return new Intl.NumberFormat(undefined, { style: 'currency', currency: code, maximumFractionDigits: 2, minimumFractionDigits: 0 }).format(Math.abs(v)) }
    catch { return `${code} ${Math.abs(v).toFixed(0)}` }
  })()
  return v < 0 ? `-${s}` : s
}

// MARK: Sent memory

function readSent(): Set<string> {
  const out = new Set<string>()
  const synced = store.setting<string[]>(SENT_KEY as SettingKey)
  if (Array.isArray(synced)) for (const s of synced) if (typeof s === 'string') out.add(s)
  try {
    const local = JSON.parse(localStorage.getItem(SENT_KEY) ?? '[]')
    if (Array.isArray(local)) for (const s of local) if (typeof s === 'string') out.add(s)
  } catch { /* ignore */ }
  return out
}

function writeSent(sent: Set<string>): void {
  // Like the Mac: sorted, the last 300.
  const list = [...sent].sort().slice(-300)
  try { localStorage.setItem(SENT_KEY, JSON.stringify(list)) } catch { /* ignore */ }
  // Only takes effect once "spendAlerts.sent" is in SYNCED_SETTINGS (setSetting ignores unknown keys).
  const synced = store.setting<string[]>(SENT_KEY as SettingKey)
  if (JSON.stringify(synced ?? null) !== JSON.stringify(list)) store.setSetting(SENT_KEY as SettingKey, list)
}

// MARK: What to say

/** What should be said about these transactions right now (pure apart from settings, like SpendingAlerts.alerts). */
export function spendingAlerts(all: Rec<Txn>[], now: Date = new Date()): SpendingAlert[] {
  const month = currentPeriod(now).start
  const monthKey = `${month.getFullYear()}-${String(month.getMonth() + 1).padStart(2, '0')}`
  const tomorrow = new Date(now.getTime() + DAY)
  const expenses = all
    .map((r) => ({ r, d: parse(r.data.date) }))
    .filter((x): x is { r: Rec<Txn>; d: Date } => !!x.d && x.r.data.amount < 0)
  const spentThisMonth = expenses.filter((x) => x.d >= month && x.d <= tomorrow)
  let out: SpendingAlert[] = []

  if (budgetAlerts()) {
    const limits = Object.entries(budgets()).map(([name, limit]) => ({
      name, limit, spent: -spentThisMonth.filter((x) => x.r.data.category === name).reduce((s, x) => s + x.r.data.amount, 0),
    }))
    const monthly = monthlyBudget()
    if (monthly > 0) limits.push({ name: '', limit: monthly, spent: -spentThisMonth.reduce((s, x) => s + x.r.data.amount, 0) })
    for (const l of limits) {
      if (l.spent < l.limit * 0.8) continue
      const over = l.spent >= l.limit
      const what = l.name ? `your ${l.name} budget` : 'your monthly budget'
      const left = money(Math.max(0, l.limit - l.spent))
      out.push({
        id: `${monthKey}|${l.name || 'month'}|${over ? 100 : 80}`,
        title: over ? `Over ${what}` : `${Math.trunc(l.spent / l.limit * 100)}% of ${what} used`,
        body: over ? `${money(l.spent)} spent of ${money(l.limit)} this month.`
                   : `${money(l.spent)} of ${money(l.limit)} spent, ${left} left this month.`,
      })
    }
    // Only the strongest alert per budget.
    const ids = new Set(out.map((a) => a.id))
    out = out.filter((a) => !(a.id.endsWith('|80') && ids.has(a.id.slice(0, -2) + '100')))
  }

  if (bigChargeAlerts()) {
    const history = expenses.filter((x) => x.d.getTime() >= now.getTime() - 120 * DAY)
    const monthly = monthlyBudget()
    for (const t of expenses) {
      if (t.d.getTime() < now.getTime() - 2 * DAY || t.d > tomorrow || t.r.data.isRecurring) continue
      const same = history.filter((x) => x.r.id !== t.r.id && x.r.data.category === t.r.data.category).map((x) => -x.r.data.amount)
      const pool = same.length >= 5 ? same : history.filter((x) => x.r.id !== t.r.id).map((x) => -x.r.data.amount)
      if (pool.length < 5) continue
      const typical = [...pool].sort((a, b) => a - b)[Math.floor(pool.length / 2)]
      const value = -t.r.data.amount
      if (value < Math.max(typical * 3, monthly * 0.1)) continue
      out.push({
        id: `big|${t.r.id}`,
        title: `Big charge: ${money(value)} at ${t.r.data.title}`,
        body: `About ${Math.round(value / Math.max(typical, 1))}× what you usually spend${same.length >= 5 ? ` on ${t.r.data.category}` : ''}. Not you? Check with your bank.`,
      })
    }
  }
  return out
}

// MARK: Posting

function intID(s: string): number {
  let h = 0
  for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0
  return Math.abs(h) % 2_000_000_000
}

let running: Promise<void> | null = null

/** Looks at this month's spending and posts any alerts that are due. Safe to call often: each alert goes out once. */
export function checkSpendingAlerts(): Promise<void> {
  if (!isNative) return Promise.resolve()
  if (running) return running
  running = (async () => {
    try {
      const sent = readSent()
      const due = spendingAlerts(store.list<Txn>('transaction')).filter((a) => !sent.has(a.id))
      if (!due.length) return
      // Remember them first (as the Mac does), so a second call can't send them again.
      for (const a of due) sent.add(a.id)
      writeSent(sent)
      const perm = await LocalNotifications.checkPermissions()
      if (perm.display !== 'granted') return
      const at = new Date(Date.now() + 1000)
      await LocalNotifications.schedule({
        notifications: due.slice(0, 3).map((a) => ({
          id: intID('orbit.spend.' + a.id), title: a.title, body: a.body, schedule: { at }, extra: { route: 'money' },
        })),
      })
    } catch { /* notifications are a nice-to-have */ } finally {
      running = null
    }
  })()
  return running
}
