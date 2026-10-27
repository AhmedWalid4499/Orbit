// "Your week in money", like WeeklyMoneyCard (BillsView.swift) and WeeklyMoney.swift on the Mac: the last seven days
// next to the seven before, and subscriptions or bills that need a look. Worked out on the phone, no AI.
import { ReactNode } from 'react'
import { ArrowDownRight, ArrowUpRight, ArrowUpCircle, Calendar, CalendarClock, AlertCircle, HelpCircle, Hourglass, Inbox } from 'lucide-react'
import { useRecords, Rec } from '@/lib/store'
import { Txn, Subscription, priceWentUp } from '@/lib/models'
import { parse, startOfDay, startOfMonth, addDays, addMonths, daysInMonth, daysBetween, relativeDay } from '@/lib/dates'
import { Card, EmptyHint, useMoney } from '@/components/ui'
import { Bill, monthKey } from '../reminders'
import { currentPeriod } from '../lib/budgetPeriod'

type Money = (v: number, signed?: boolean) => string
interface Change { name: string; spent: number; before: number }
interface Flag { icon: ReactNode; text: string }
interface Report {
  from: Date
  spent: number
  lastWeek: number
  categories: Change[]
  biggest: Txn | null
  topMerchant: { name: string; total: number; count: number } | null
  flags: Flag[]
}

const at = (t: Rec<Txn>) => parse(t.data.date)?.getTime() ?? 0
const short = (d: Date) => d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })

function report(txns: Rec<Txn>[], subs: Rec<Subscription>[], bills: Rec<Bill>[], money: Money, now = new Date()): Report {
  // After "New month", the week starts no earlier than the new budget month, and there's no "last week" to compare.
  const periodStart = currentPeriod(now).start
  const end = addDays(startOfDay(now), 1)
  const from = new Date(Math.max(addDays(end, -7).getTime(), periodStart.getTime())), before = addDays(end, -14)
  const week = txns.filter((t) => at(t) >= from.getTime() && at(t) < end.getTime())
  const prior = periodStart > before ? [] : txns.filter((t) => at(t) >= before.getTime() && at(t) < addDays(end, -7).getTime())
  const spentIn = (l: Rec<Txn>[]) => l.reduce((s, t) => s - Math.min(0, t.data.amount), 0)
  const byCategory = (l: Rec<Txn>[]) => {
    const m: Record<string, number> = {}
    for (const t of l) if (t.data.amount < 0) m[t.data.category || 'General'] = (m[t.data.category || 'General'] ?? 0) - t.data.amount
    return m
  }
  const now7 = byCategory(week), then7 = byCategory(prior)
  const categories = Object.entries(now7).map(([name, spent]) => ({ name, spent, before: then7[name] ?? 0 })).sort((a, b) => b.spent - a.spent)
  const expenses = week.filter((t) => t.data.amount < 0)
  const groups = new Map<string, Rec<Txn>[]>()
  for (const t of expenses) {
    const k = (t.data.title ?? '').trim().toLowerCase()
    groups.set(k, [...(groups.get(k) ?? []), t])
  }
  const topMerchant = [...groups.values()].filter((l) => l.length > 1)
    .map((l) => ({ name: l[0].data.title, total: -l.reduce((s, t) => s + t.data.amount, 0), count: l.length }))
    .sort((a, b) => b.total - a.total)[0] ?? null
  const biggest = expenses.reduce<Rec<Txn> | null>((m, t) => (!m || t.data.amount < m.data.amount ? t : m), null)
  return { from, spent: spentIn(week), lastWeek: spentIn(prior), categories, biggest: biggest?.data ?? null, topMerchant,
    flags: flags(subs, bills, txns, money, now) }
}

// MARK: Flags

/** "today", "tomorrow", "on Monday", "on 3 Nov". */
const when = (d: Date) => { const r = relativeDay(d); return r === 'Today' || r === 'Tomorrow' ? r.toLowerCase() : `on ${r}` }

const nextCharge = (s: Subscription, d: Date): Date =>
  s.cycle === 'weekly' ? addDays(d, 7) : addMonths(d, s.cycle === 'quarterly' ? 3 : s.cycle === 'yearly' ? 12 : 1)

/** Price rises, trials about to charge, forgotten subscriptions, and bills late or due within a week. */
function flags(subs: Rec<Subscription>[], bills: Rec<Bill>[], txns: Rec<Txn>[], money: Money, now: Date): Flag[] {
  const out: Flag[] = []
  const ago60 = addDays(now, -60), in8 = addDays(now, 8)
  for (const { data: s } of subs) {
    if (s.status === 'cancelled') continue
    const changed = parse(s.priceChangedAt)
    if (priceWentUp(s) && changed && changed > ago60)
      out.push({ icon: <ArrowUpCircle size={13} />, text: `${s.name} went up from ${money(s.previousAmount)} to ${money(s.amount)}.` })
    const ends = parse(s.trialEnds)
    if (s.status === 'trial' && ends && ends > now && ends < in8)
      out.push({ icon: <Hourglass size={13} />, text: `${s.name} trial turns paid ${when(ends)} (${money(s.amount)}).` })
    // No charge for two whole cycles: cancelled somewhere else, or paying for something you don't use.
    const last = parse(s.lastCharged)
    if (s.status === 'active' && last && nextCharge(s, nextCharge(s, last)) < now)
      out.push({ icon: <HelpCircle size={13} />, text: `No ${s.name} charge since ${short(last)}. Still using it, or cancel it here?` })
  }
  for (const b of bills) {
    const st = billStatus(b, txns, now)
    if (st === null) continue
    if (st < 0) out.push({ icon: <AlertCircle size={13} />, text: `${b.data.name} is ${-st} day${st === -1 ? '' : 's'} late.` })
    else if (st <= 7) out.push({ icon: <CalendarClock size={13} />,
      text: `${b.data.name}${b.data.amount > 0 ? ` (${money(b.data.amount)})` : ''} is due ${st === 0 ? 'today' : st === 1 ? 'tomorrow' : `in ${st} days`}.` })
  }
  return out
}

// Bill status, as BillTracker.current on the Mac (and Bills.tsx): days until due (negative = late), or null when paid.
const dueIn = (b: Bill, month: Date) => { const s = startOfMonth(month); return addDays(s, Math.min(Math.max(b.dueDay || 1, 1), daysInMonth(s)) - 1) }

function isPaid(b: Rec<Bill>, due: Date, txns: Rec<Txn>[]): boolean {
  if ((b.data.paidMonths ?? []).includes(monthKey(due))) return true
  const words = (b.data.match || b.data.name || '').toLowerCase().split(',').map((w) => w.trim()).filter((w) => w.length >= 2)
  if (!words.length) return false
  const from = addDays(due, -20).getTime(), to = addDays(due, 11).getTime(), id = `bill:${b.id}:${monthKey(due)}`
  return txns.some((t) => {
    const d = at(t)
    if (t.data.amount >= 0 || d < from || d >= to) return false
    if (t.data.source === 'bill') return t.data.sourceID === id
    return words.some((w) => (t.data.title ?? '').toLowerCase().includes(w))
  })
}

function billStatus(b: Rec<Bill>, txns: Rec<Txn>[], now: Date): number | null {
  const today = startOfDay(now)
  let due = dueIn(b.data, today), paid = isPaid(b, due, txns)
  const created = parse(b.data.createdAt)
  // Added after this month's due day (never late), or this month is paid: look at next month's.
  if ((created && due < startOfDay(created) && !paid) || (paid && due < today)) {
    due = dueIn(b.data, addMonths(startOfMonth(today), 1))
    paid = isPaid(b, due, txns)
  }
  return paid ? null : daysBetween(today, due)
}

// MARK: Card

export default function WeeklyMoneyCard() {
  const txns = useRecords<Txn>('transaction')
  const subs = useRecords<Subscription>('subscription')
  const bills = useRecords<Bill>('bill')
  const money = useMoney()
  const r = report(txns, subs, bills, money)
  const change = r.lastWeek > 0 ? r.spent / r.lastWeek - 1 : null

  return (
    <Card padding={16}>
      <div className="col" style={{ gap: 12 }}>
        <div className="row" style={{ gap: 6, alignItems: 'baseline' }}>
          <span className="secondary row" style={{ gap: 5, fontSize: 12, fontWeight: 600 }}><Calendar size={12} />Your week in money</span>
          <span className="spacer" />
          <span className="muted" style={{ fontSize: 11 }}>{short(r.from)} – today</span>
        </div>

        <div className="col" style={{ gap: 4 }}>
          <div className="display" style={{ fontSize: 30 }}>{money(r.spent)}</div>
          {change !== null && Math.abs(change) >= 0.01 ? (
            <span className="row" style={{ gap: 4, fontSize: 12, fontWeight: 600, color: change > 0 ? 'var(--critical)' : 'var(--good)' }}>
              {change > 0 ? <ArrowUpRight size={13} /> : <ArrowDownRight size={13} />}
              {Math.round(Math.abs(change) * 100)}% {change > 0 ? 'more' : 'less'} than last week
            </span>
          ) : (
            <span className="secondary" style={{ fontSize: 12 }}>{r.lastWeek > 0 ? 'About the same as last week' : 'Spent in the last 7 days'}</span>
          )}
        </div>

        <div className="col" style={{ gap: 6 }}>
          {r.categories.slice(0, 3).map((c) => {
            const d = c.before > 0 ? c.spent / c.before - 1 : null
            return (
              <div key={c.name} className="row" style={{ gap: 8, fontSize: 13 }}>
                <span style={{ fontWeight: 500 }}>{c.name}</span>
                <span className="spacer" />
                <span style={{ fontWeight: 600 }}>{money(c.spent)}</span>
                <span style={{ width: 44, textAlign: 'right', fontSize: 11, fontWeight: 500,
                  color: d === null ? 'var(--ink3)' : d > 0.05 ? 'var(--critical)' : d < -0.05 ? 'var(--good)' : 'var(--ink3)' }}>
                  {d === null ? 'new' : `${d >= 0 ? '+' : '−'}${Math.round(Math.abs(d) * 100)}%`}
                </span>
              </div>
            )
          })}
          {r.biggest && (
            <div className="muted" style={{ fontSize: 11 }}>
              Biggest: {r.biggest.title} {money(-r.biggest.amount)}{r.topMerchant ? ` · Most often: ${r.topMerchant.name} ×${r.topMerchant.count}` : ''}
            </div>
          )}
          {!r.categories.length && <EmptyHint icon={<Inbox size={14} />} text="Nothing spent this week." />}
        </div>

        {r.flags.length > 0 && (
          <div className="col" style={{ gap: 6, borderTop: '1px solid var(--line)', paddingTop: 10 }}>
            {r.flags.slice(0, 5).map((f) => (
              <div key={f.text} className="row" style={{ gap: 8, fontSize: 12, alignItems: 'flex-start' }}>
                <span style={{ flex: 'none', marginTop: 1 }}>{f.icon}</span><span>{f.text}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </Card>
  )
}
