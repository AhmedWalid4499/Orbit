// The stretch of time the monthly budget covers, like BudgetPeriod.swift on the Mac. Calendar months unless you start a
// new month yourself (Money › New month, e.g. on payday the 25th): then each budget month runs from that moment to the
// same day next month, and rolls on by itself. Spending before the start doesn't count.
// Synced as "budget.periodStart": seconds since 1970 (a Double, as the Mac's UserDefaults holds it); 0 or missing = calendar months.
import { useEffect, useState } from 'react'
import { store, useSetting, Rec } from '@/lib/store'
import { Txn } from '@/lib/models'
import { parse, startOfDay, startOfMonth, daysBetween, daysInMonth } from '@/lib/dates'

export const PERIOD_KEY = 'budget.periodStart'

export interface Period { start: Date; end: Date }

const DAY = 86_400_000

/** Calendar month arithmetic that keeps the time of day (Calendar.date(byAdding: .month) on the Mac). */
function plusMonths(d: Date, n: number): Date {
  const first = new Date(d.getFullYear(), d.getMonth() + n, 1)
  return new Date(first.getFullYear(), first.getMonth(), Math.min(d.getDate(), daysInMonth(first)),
    d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds())
}

/** Whole months from `a` to `b`, truncated toward zero. */
function monthsBetween(a: Date, b: Date): number {
  let n = (b.getFullYear() - a.getFullYear()) * 12 + b.getMonth() - a.getMonth()
  if (n > 0 && plusMonths(a, n) > b) n--
  if (n < 0 && plusMonths(a, n) < b) n++
  return n
}

const anchorFrom = (v: unknown): Date | null => {
  const t = Number(v) || 0
  return t > 0 ? new Date(t * 1000) : null
}

/** The moment you last started a new month, or null for calendar months. */
export const anchor = (): Date | null => anchorFrom(store.setting(PERIOD_KEY))
export const isCustom = (): boolean => anchor() !== null

/** The budget month that contains `date`. */
export function periodContaining(date: Date = new Date(), a: Date | null = anchor()): Period {
  if (!a) {
    const start = startOfMonth(date)
    return { start, end: new Date(start.getFullYear(), start.getMonth() + 1, 1) }
  }
  // Step whole months from the anchor (forwards or backwards) until the period holds `date`.
  let n = monthsBetween(a, date)
  let start = plusMonths(a, n)
  if (start > date) { n--; start = plusMonths(a, n) }
  let end = plusMonths(a, n + 1)
  if (end <= date) { start = end; end = plusMonths(a, n + 2) }
  return { start, end }
}

export const currentPeriod = (now: Date = new Date()): Period => periodContaining(now)

/** The period `months` before or after `p`. */
export const shifted = (p: Period, months: number): Period =>
  periodContaining(new Date(plusMonths(p.start, months).getTime() + 3_600_000))

export const samePeriod = (a: Period, b: Period): boolean => a.start.getTime() === b.start.getTime() && a.end.getTime() === b.end.getTime()

/** Starts a new budget month right now: anything spent before this moment, even earlier today, no longer counts. */
export function startNewMonth(moment: Date = new Date()): void {
  store.setSetting(PERIOD_KEY, moment.getTime() / 1000)
}

/** Back to calendar months (0, not removed, so it syncs like the Mac's). */
export function backToCalendarMonths(): void {
  store.setSetting(PERIOD_KEY, 0)
}

/** "October 2026", or "25 Oct – 24 Nov" for a month that starts on payday. */
export function periodTitle(p: Period, custom: boolean = isCustom()): string {
  if (!custom) return p.start.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })
  const f = (d: Date) => d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
  return `${f(p.start)} – ${f(new Date(p.end.getFullYear(), p.end.getMonth(), p.end.getDate() - 1))}`
}

type TxnLike = Txn | Rec<Txn>
const txnOf = (t: TxnLike): Txn => ('data' in t ? t.data : t)

export function inPeriod(t: TxnLike, p: Period): boolean {
  const d = parse(txnOf(t).date)
  return !!d && d >= p.start && d < p.end
}

/** Spending in a budget month (the current one by default), as a positive number. */
export function spent(txns: TxnLike[], p: Period = currentPeriod()): number {
  let s = 0
  for (const t of txns) { const x = txnOf(t); if (x.amount < 0 && inPeriod(x, p)) s -= x.amount }
  return s
}

/** Money in during a budget month. */
export function income(txns: TxnLike[], p: Period = currentPeriod()): number {
  let s = 0
  for (const t of txns) { const x = txnOf(t); if (x.amount > 0 && inPeriod(x, p)) s += x.amount }
  return s
}

/** Days gone and days in the budget month, for pace ("day 12 of 30"). */
export function dayOf(p: Period = currentPeriod(), now: Date = new Date()): { day: number; of: number } {
  const total = daysBetween(p.start, p.end) || 30
  // Whole days from the start to today's midnight (an hour's slack for daylight saving).
  const ms = startOfDay(now).getTime() - p.start.getTime()
  const d = Math.trunc((ms + Math.sign(ms) * 3_600_000) / DAY) + 1
  return { day: Math.min(Math.max(d, 1), total), of: total }
}

/** What the "New month" confirmation says (newBudgetMonthDialog on the Mac). */
export function newMonthMessage(now: Date = new Date()): string {
  const next = plusMonths(startOfDay(now), 1)
  next.setDate(next.getDate() - 1)
  const when = next.toLocaleDateString(undefined, { day: 'numeric', month: 'long' })
  return `Your budget starts again from now and runs to ${when}, then month to month from this day. Nothing spent before now counts. Handy on payday.`
}

/** The anchor, re-rendering when it syncs in. */
export function useAnchor(): Date | null {
  return anchorFrom(useSetting<number>(PERIOD_KEY, 0))
}

/** The budget month being looked at, with ‹ › switching. Jumps back to the current month when the anchor changes. */
export function useBudgetPeriod(): { period: Period; custom: boolean; shift: (n: number) => void; reset: () => void } {
  const a = useAnchor()
  const t = a?.getTime() ?? 0
  const [period, setPeriod] = useState(() => periodContaining(new Date(), a))
  useEffect(() => { setPeriod(periodContaining(new Date(), a)) }, [t]) // eslint-disable-line react-hooks/exhaustive-deps
  return {
    period,
    custom: a !== null,
    shift: (n) => setPeriod((p) => periodContaining(new Date(plusMonths(p.start, n).getTime() + 3_600_000), a)),
    reset: () => setPeriod(periodContaining(new Date(), a)),
  }
}
