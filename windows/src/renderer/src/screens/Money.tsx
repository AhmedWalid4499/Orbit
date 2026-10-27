import { useEffect, useMemo, useState, ReactNode } from 'react'
import {
  Plus, ArrowLeft, ArrowRight, Target, ArrowUpRight, ArrowDownLeft, Mail, Repeat, UtensilsCrossed, Car, Zap,
  ShoppingBag, BriefcaseMedical, Drama, LayoutGrid, MoreHorizontal, Trash2, CreditCard, Check,
  Sparkles, RefreshCw, MailPlus, MessagesSquare, MailX,
} from 'lucide-react'
import { structured, useKeys, useAssistantName } from '@/lib/ai'
import { openAsk } from '@/lib/askBus'
import { moneySummary } from '@/lib/snapshot'
import {
  emailExpensesState, onEmailExpensesChange, emailExpensesEnabled, startEmailExpensesTimer, syncEmailExpenses, rejectEmailExpense,
} from '@/lib/emailExpenses'
import { store, useRecords, useSetting, Rec } from '@/lib/store'
import { Txn, Task, MONEY_CATEGORIES } from '@/lib/models'
import { learnCategory } from '@/lib/merchantRules'
import {
  iso, parse, startOfDay, addDays, addMonths, sameDay, isToday, startOfMonth, daysInMonth, startOfWeek, dayKey,
  relativeDay, fmtDay, fromInputs, toDateInput, relativeTime,
} from '@/lib/dates'
import { Card, EmptyHint, Segmented, Modal, useMoney } from '@/components/ui'
import SubscriptionsView from './Subscriptions'
import { ImportStatementButton } from './StatementImport'
import './Money.css'

type Mode = 'overview' | 'calendar' | 'subscriptions'

const CATEGORY_ICON: Record<string, ReactNode> = {
  Food: <UtensilsCrossed size={14} />, Transport: <Car size={14} />, Bills: <Zap size={14} />, Shopping: <ShoppingBag size={14} />,
  Health: <BriefcaseMedical size={14} />, Fun: <Drama size={14} />, Subscriptions: <Repeat size={14} />, Income: <ArrowDownLeft size={14} />,
}
const iconFor = (c: string): ReactNode => CATEGORY_ICON[c] ?? <LayoutGrid size={14} />

const txnDate = (t: Rec<Txn>): Date => parse(t.data.date) ?? new Date(0)

export default function Money() {
  const all = useRecords<Txn>('transaction')
  const tasks = useRecords<Task>('task')
  const budget = Number(useSetting<number>('monthlyBudget', 2000)) || 0
  const money = useMoney()

  const [mode, setModeState] = useState<Mode>(() => { const m = localStorage.getItem('orbit.moneyMode'); return m === 'calendar' || m === 'subscriptions' ? m : 'overview' })
  const setMode = (m: Mode) => { setModeState(m); localStorage.setItem('orbit.moneyMode', m) }
  const [month, setMonth] = useState(() => startOfMonth(new Date()))
  const [adding, setAdding] = useState(false)
  useEffect(() => { startEmailExpensesTimer() }, [])

  const monthEnd = addMonths(month, 1)
  const txns = useMemo(() => all.filter((t) => { const d = txnDate(t); return d >= month && d < monthEnd }), [all, month])
  const spent = -txns.filter((t) => t.data.amount < 0).reduce((s, t) => s + t.data.amount, 0)
  const income = txns.filter((t) => t.data.amount >= 0).reduce((s, t) => s + t.data.amount, 0)
  const expenseCount = txns.filter((t) => t.data.amount < 0).length

  return (
    <div className="page">
      <div className="col" style={{ gap: 22 }}>
        <div className="row" style={{ gap: 12 }}>
          <h1 className="page-title" style={{ whiteSpace: 'nowrap' }}>{mode === 'subscriptions' ? 'Subscriptions' : month.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}</h1>
          <span style={{ marginLeft: 8 }}>
            <Segmented<Mode> options={[{ id: 'overview', label: 'Overview' }, { id: 'calendar', label: 'Calendar' }, { id: 'subscriptions', label: 'Subscriptions' }]} value={mode} onChange={setMode} />
          </span>
          <span className="spacer" />
          <EmailChip />
          <ImportStatementButton />
          <button className="btn-soft" onClick={() => setAdding(true)}><Plus size={14} />Add transaction</button>
          {mode !== 'subscriptions' && <>
          <button className="icon-btn filled" style={{ width: 46, height: 46 }} onClick={() => setMonth(addMonths(month, -1))} title="Previous month"><ArrowLeft size={18} /></button>
          <button className="icon-btn filled" style={{ width: 46, height: 46 }} onClick={() => setMonth(addMonths(month, 1))} title="Next month"><ArrowRight size={18} /></button>
          </>}
        </div>

        {mode === 'subscriptions' ? <SubscriptionsView /> : <>
        <div className="row" style={{ gap: 20, alignItems: 'stretch' }}>
          <BalanceCard title="Left to spend" value={money(budget - spent)} caption={`of ${money(budget)} budget`}
            fill="linear-gradient(135deg, var(--lime), var(--mint))" icon={<Target size={15} />} />
          <BalanceCard title="Spent" value={money(spent)} caption={`${expenseCount} expense${expenseCount === 1 ? '' : 's'}`}
            fill="linear-gradient(135deg, var(--orange), var(--peach))" icon={<ArrowUpRight size={15} />} />
          <BalanceCard title="Income" value={money(income)} caption={`Net ${money(income - spent, true)}`}
            fill="linear-gradient(135deg, var(--cyan), var(--purple))" icon={<ArrowDownLeft size={15} />} />
        </div>

        {mode === 'calendar' ? (
          <MoneyCalendar month={month} transactions={all} tasks={tasks} />
        ) : (
          <>
            <MoneyCoachCard hasExpenses={all.some((t) => t.data.amount < 0)} />
            <div className="row" style={{ gap: 20, alignItems: 'flex-start' }}>
              <div style={{ flex: 1, minWidth: 0 }}><DailyChart month={month} txns={txns} /></div>
              <div style={{ width: 340, flex: 'none' }}><CategoryCard txns={txns} spent={spent} /></div>
            </div>
            <div className="row" style={{ gap: 20, alignItems: 'flex-start' }}>
              <div style={{ flex: 1, minWidth: 0 }}><TransactionsCard txns={txns} /></div>
              <div style={{ width: 340, flex: 'none' }}><RecurringCard all={all} /></div>
            </div>
          </>
        )}
        </>}
      </div>
      <NewTransaction open={adding} onClose={() => setAdding(false)} />
    </div>
  )
}

function BalanceCard({ title, value, caption, fill, icon }: { title: string; value: string; caption: string; fill: string; icon: ReactNode }) {
  return (
    <div className="money-balance" style={{ background: fill }}>
      <div className="row">
        <span style={{ fontWeight: 600 }}>{title}</span>
        <span className="spacer" />
        <span className="badge">{icon}</span>
      </div>
      <div className="value">{value}</div>
      <div style={{ fontSize: 12, fontWeight: 500, opacity: 0.75 }}>{caption}</div>
    </div>
  )
}

// MARK: Daily spending chart (single series, inline SVG)

function niceMax(v: number): number {
  if (v <= 0) return 100
  const p = Math.pow(10, Math.floor(Math.log10(v)))
  for (const m of [1, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10]) if (v <= m * p) return m * p
  return 10 * p
}

function DailyChart({ month, txns }: { month: Date; txns: Rec<Txn>[] }) {
  const money = useMoney()
  const [hover, setHover] = useState<number | null>(null)
  const days = daysInMonth(month)
  const totals = useMemo(() => {
    const arr = new Array(days).fill(0)
    for (const t of txns) if (t.data.amount < 0) { const d = txnDate(t); arr[d.getDate() - 1] += -t.data.amount }
    return arr as number[]
  }, [txns, days])
  const max = niceMax(Math.max(...totals, 0))
  const W = 760, H = 220, left = 64, right = 8, top = 10, bottom = 24
  const plotW = W - left - right, plotH = H - top - bottom
  const step = plotW / days
  const barW = Math.max(3, step * 0.6)
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => f * max)

  return (
    <Card>
      <div className="col" style={{ gap: 14 }}>
        <div className="row" style={{ alignItems: 'baseline' }}>
          <h3 className="section-title">Daily spending</h3>
          <span className="spacer" />
          {hover !== null ? (
            <span style={{ fontSize: 13, fontWeight: 500 }}>
              {fmtDay(addDays(month, hover), { weekday: 'short', day: 'numeric', month: 'short' })} · {money(totals[hover])}
            </span>
          ) : <span className="muted" style={{ fontSize: 12 }}>Hover a bar for details</span>}
        </div>
        <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto', display: 'block' }} onMouseLeave={() => setHover(null)}>
          {ticks.map((v) => {
            const y = top + plotH - (v / max) * plotH
            return (
              <g key={v}>
                <line x1={left} x2={W - right} y1={y} y2={y} stroke="var(--line)" strokeWidth={1} />
                <text x={left - 8} y={y + 4} textAnchor="end" fontSize={10} fill="var(--ink3)">{money(v)}</text>
              </g>
            )
          })}
          {totals.map((v, i) => {
            const h = (v / max) * plotH
            const x = left + i * step + (step - barW) / 2
            const y = top + plotH - h
            const r = Math.min(4, barW / 2, h)
            const d = h > 0
              ? `M${x},${top + plotH} V${y + r} Q${x},${y} ${x + r},${y} H${x + barW - r} Q${x + barW},${y} ${x + barW},${y + r} V${top + plotH} Z`
              : ''
            return (
              <g key={i} onMouseEnter={() => setHover(i)}>
                <rect x={left + i * step} y={top} width={step} height={plotH} fill="transparent" />
                {d && <path d={d} fill={hover === null || hover === i ? 'var(--ink)' : 'var(--ink3)'} opacity={hover === null || hover === i ? 1 : 0.5} />}
              </g>
            )
          })}
          {Array.from({ length: days }, (_, i) => i).filter((i) => i % 7 === 0).map((i) => (
            <text key={i} x={left + i * step + step / 2} y={H - 6} textAnchor="middle" fontSize={10} fill="var(--ink3)">
              {addDays(month, i).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}
            </text>
          ))}
        </svg>
      </div>
    </Card>
  )
}

function CategoryCard({ txns, spent }: { txns: Rec<Txn>[]; spent: number }) {
  const money = useMoney()
  const cats = useMemo(() => {
    const m = new Map<string, number>()
    for (const t of txns) if (t.data.amount < 0) m.set(t.data.category || 'General', (m.get(t.data.category || 'General') ?? 0) - t.data.amount)
    return [...m.entries()].sort((a, b) => b[1] - a[1])
  }, [txns])
  const max = cats[0]?.[1] ?? 1
  return (
    <Card>
      <div className="col" style={{ gap: 14 }}>
        <h3 className="section-title">By category</h3>
        {cats.length === 0 && <EmptyHint text="No spending yet." />}
        {cats.map(([cat, v]) => (
          <div key={cat} className="col" style={{ gap: 5 }}>
            <div className="row">
              <span style={{ fontSize: 13, fontWeight: 500 }}>{cat}</span>
              <span className="spacer" />
              <span style={{ fontSize: 13, fontWeight: 600 }}>{money(v)}</span>
              <span className="muted" style={{ fontSize: 11, width: 34, textAlign: 'right' }}>{Math.round((v / Math.max(spent, 1)) * 100)}%</span>
            </div>
            <div style={{ height: 6, borderRadius: 3, background: 'var(--ink)', width: `${Math.max(2, (v / max) * 100)}%` }} />
          </div>
        ))}
      </div>
    </Card>
  )
}

// MARK: Transactions

function TransactionsCard({ txns }: { txns: Rec<Txn>[] }) {
  const groups = useMemo(() => {
    const m = new Map<string, Rec<Txn>[]>()
    for (const t of [...txns].sort((a, b) => txnDate(b).getTime() - txnDate(a).getTime())) {
      const k = dayKey(txnDate(t))
      m.set(k, [...(m.get(k) ?? []), t])
    }
    return [...m.entries()]
  }, [txns])
  return (
    <Card>
      <div className="col" style={{ gap: 8 }}>
        <h3 className="section-title">Transactions</h3>
        {txns.length === 0 && <EmptyHint icon={<CreditCard size={14} />} text="No transactions this month." />}
        {groups.map(([k, list]) => (
          <div key={k} className="col" style={{ gap: 6 }}>
            <div className="muted" style={{ fontSize: 12, fontWeight: 600, paddingTop: 6 }}>{relativeDay(txnDate(list[0]))}</div>
            {list.map((t) => <TxnRow key={t.id} txn={t} />)}
          </div>
        ))}
      </div>
    </Card>
  )
}

function TxnRow({ txn }: { txn: Rec<Txn> }) {
  const money = useMoney()
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null)
  const t = txn.data
  const expense = t.amount < 0
  const fromEmail = (t.source ?? '').startsWith('gmail:')
  const open = (e: React.MouseEvent) => { e.preventDefault(); setMenu({ x: Math.min(e.clientX, window.innerWidth - 220), y: Math.min(e.clientY, window.innerHeight - 380) }) }

  return (
    <div className="money-txn" onContextMenu={open}>
      <span className="ic" style={{ background: expense ? 'var(--peach)' : 'var(--mint)' }}>{iconFor(t.category)}</span>
      <div style={{ minWidth: 0 }}>
        <div className="clamp1" style={{ fontSize: 14, fontWeight: 500 }}>{t.title || 'Untitled'}</div>
        <div className="row muted" style={{ fontSize: 11, gap: 6 }}>
          {fromEmail && <span title={`Added from ${t.source.slice(6)}`} style={{ display: 'inline-flex' }}><Mail size={11} /></span>}
          <span>{t.category}</span>
          {t.isRecurring && <Repeat size={11} />}
          {t.originalCurrency && <span>· {Number(t.originalAmount).toLocaleString(undefined, { maximumFractionDigits: 2 })} {t.originalCurrency}</span>}
        </div>
      </div>
      <span className="spacer" />
      <span style={{ fontSize: 14, fontWeight: 600, color: expense ? 'var(--ink)' : 'var(--good)' }}>{money(t.amount, true)}</span>
      <button className="menu-btn" title="More" onClick={open}><MoreHorizontal size={15} /></button>
      {menu && <TxnMenu txn={txn} at={menu} onClose={() => setMenu(null)} />}
    </div>
  )
}

function TxnMenu({ txn, at, onClose }: { txn: Rec<Txn>; at: { x: number; y: number }; onClose: () => void }) {
  useEffect(() => {
    const close = () => onClose()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    setTimeout(() => window.addEventListener('mousedown', close), 0)
    window.addEventListener('keydown', onKey)
    return () => { window.removeEventListener('mousedown', close); window.removeEventListener('keydown', onKey) }
  }, [onClose])
  const t = txn.data
  const act = (fn: () => void) => (e: React.MouseEvent) => { e.stopPropagation(); fn(); onClose() }
  return (
    <div className="money-menu" style={{ left: at.x, top: at.y }} onMouseDown={(e) => e.stopPropagation()}>
      <button onClick={act(() => store.update<Txn>(txn.id, { isRecurring: !t.isRecurring }))}>
        <Repeat size={13} />{t.isRecurring ? 'Not recurring' : 'Recurring'}
      </button>
      <div className="sep" />
      <div className="label">Category</div>
      {MONEY_CATEGORIES.map((c) => (
        <button key={c} onClick={act(() => { store.update<Txn>(txn.id, { category: c }); if (t.amount < 0) learnCategory(t.title, c) })}>
          <span style={{ width: 13, display: 'inline-flex' }}>{t.category === c && <Check size={13} />}</span>{c}
        </button>
      ))}
      <div className="sep" />
      {(t.source ?? '').startsWith('gmail:') && (
        <>
          <button onClick={act(() => rejectEmailExpense(txn.id))}><MailX size={13} />Not an expense</button>
          <button onClick={act(() => { window.orbit.openExternal(`https://mail.google.com/mail/u/?authuser=${encodeURIComponent(t.source.slice(6))}#all/${t.sourceID}`) })}>
            <Mail size={13} />Open email
          </button>
        </>
      )}
      <button style={{ color: 'var(--critical)' }} onClick={act(() => store.remove(txn.id))}><Trash2 size={13} />Delete</button>
    </div>
  )
}

function RecurringCard({ all }: { all: Rec<Txn>[] }) {
  const money = useMoney()
  const recurring = useMemo(() => {
    const seen = new Set<string>()
    return [...all].sort((a, b) => txnDate(b).getTime() - txnDate(a).getTime()).filter((t) => {
      if (!t.data.isRecurring) return false
      const k = (t.data.title ?? '').toLowerCase()
      if (seen.has(k)) return false
      seen.add(k)
      return true
    })
  }, [all])
  const fixed = recurring.filter((t) => t.data.amount < 0).reduce((s, t) => s - t.data.amount, 0)
  return (
    <Card fill="var(--blush)">
      <div className="col" style={{ gap: 12 }}>
        <h3 className="section-title">Recurring</h3>
        <div className="secondary" style={{ fontSize: 12 }}>Subscriptions and bills that repeat monthly.</div>
        {recurring.length === 0 && <EmptyHint icon={<Repeat size={13} />} text="Mark a transaction as recurring to track it." />}
        {recurring.map((t) => (
          <div key={t.id} className="row">
            <div style={{ minWidth: 0 }}>
              <div className="clamp1" style={{ fontSize: 14, fontWeight: 500 }}>{t.data.title}</div>
              <div className="muted" style={{ fontSize: 11 }}>
                Next ~ {addMonths(txnDate(t), 1).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}
              </div>
            </div>
            <span className="spacer" />
            <span style={{ fontSize: 14, fontWeight: 600, color: t.data.amount < 0 ? 'var(--ink)' : 'var(--good)' }}>{money(t.data.amount, true)}</span>
          </div>
        ))}
        <div style={{ height: 1, background: 'var(--line)' }} />
        <div className="row">
          <span style={{ fontSize: 13 }}>Fixed costs / month</span>
          <span className="spacer" />
          <span style={{ fontSize: 14, fontWeight: 700 }}>{money(fixed)}</span>
        </div>
      </div>
    </Card>
  )
}

// MARK: Calendar of payments due

interface DuePayment { id: string; date: Date; title: string; amount: number | null; kind: 'bill' | 'recurring'; paid: boolean }

function duePayments(start: Date, end: Date, tasks: Rec<Task>[], txns: Rec<Txn>[]): DuePayment[] {
  const out: DuePayment[] = []
  for (const t of tasks) {
    if (t.data.area !== 'money') continue
    const due = parse(t.data.due)
    if (!due || due < start || due >= end) continue
    out.push({ id: `task-${t.id}`, date: startOfDay(due), title: (t.data.title ?? '').replace(/^Pay /, ''), amount: null, kind: 'bill', paid: !!t.data.isDone })
  }
  // Latest charge of each recurring expense, projected forward month by month.
  const latest = new Map<string, Rec<Txn>>()
  for (const t of txns) {
    if (!t.data.isRecurring || t.data.amount >= 0) continue
    const k = (t.data.title ?? '').toLowerCase()
    const prev = latest.get(k)
    if (!prev || txnDate(t) > txnDate(prev)) latest.set(k, t)
  }
  for (const t of latest.values()) {
    let n = 1
    let next = addMonths(txnDate(t), n)
    while (next < end) {
      if (next >= start) {
        const nm = next
        const paid = txns.some((x) => (x.data.title ?? '').toLowerCase() === (t.data.title ?? '').toLowerCase() &&
          txnDate(x).getFullYear() === nm.getFullYear() && txnDate(x).getMonth() === nm.getMonth())
        out.push({ id: `rec-${t.id}-${n}`, date: startOfDay(next), title: t.data.title, amount: -t.data.amount, kind: 'recurring', paid })
      }
      n++
      next = addMonths(txnDate(t), n)
    }
  }
  return out.sort((a, b) => a.date.getTime() - b.date.getTime())
}

function MoneyCalendar({ month, transactions, tasks }: { month: Date; transactions: Rec<Txn>[]; tasks: Rec<Task>[] }) {
  const money = useMoney()
  const [selected, setSelected] = useState<Date | null>(null)
  const gridStart = startOfWeek(startOfMonth(month))
  const gridDays = Array.from({ length: 42 }, (_, i) => addDays(gridStart, i))
  const gridEnd = addDays(gridStart, 42)
  const due = useMemo(() => duePayments(gridStart, gridEnd, tasks, transactions), [tasks, transactions, month])
  const spentByDay = useMemo(() => {
    const m = new Map<string, number>()
    for (const t of transactions) if (t.data.amount < 0) { const k = dayKey(txnDate(t)); m.set(k, (m.get(k) ?? 0) - t.data.amount) }
    return m
  }, [transactions])
  const today = startOfDay(new Date())
  const upcoming = useMemo(() => duePayments(today, addDays(today, 31), tasks, transactions).filter((d) => !d.paid), [tasks, transactions])
  const upcomingTotal = upcoming.reduce((s, d) => s + (d.amount ?? 0), 0)

  return (
    <div className="row" style={{ gap: 20, alignItems: 'flex-start' }}>
      <div className="col" style={{ flex: 1, minWidth: 0, gap: 6 }}>
        <div className="money-cal-head">
          {gridDays.slice(0, 7).map((d) => (
            <div key={d.getTime()} className="secondary" style={{ textAlign: 'center', fontSize: 12, fontWeight: 600 }}>
              {d.toLocaleDateString(undefined, { weekday: 'short' })}
            </div>
          ))}
        </div>
        <div className="money-cal-grid">
          {gridDays.map((day) => {
            const dayDue = due.filter((d) => sameDay(d.date, day))
            const spent = spentByDay.get(dayKey(day)) ?? 0
            const inMonth = day.getMonth() === month.getMonth()
            const sel = !!selected && sameDay(selected, day)
            return (
              <button key={day.getTime()} className={`money-cell ${inMonth ? '' : 'out'} ${sel ? 'sel' : ''}`}
                onClick={() => setSelected(sel ? null : day)}>
                <span className={`num ${isToday(day) ? 'today' : ''}`}>{day.getDate()}</span>
                {dayDue.slice(0, 2).map((d) => (
                  <span key={d.id} className="chip" style={{ background: d.paid ? 'var(--mint)' : 'var(--orange)' }}>{d.title}</span>
                ))}
                {dayDue.length > 2 && <span className="muted" style={{ fontSize: 10, fontWeight: 600 }}>+{dayDue.length - 2}</span>}
                <span className="spacer" />
                {spent > 0 && <span className="secondary clamp1" style={{ fontSize: 10, fontWeight: 500 }}>{money(spent)}</span>}
              </button>
            )
          })}
        </div>
        <div className="row secondary" style={{ fontSize: 11, gap: 16, paddingTop: 4 }}>
          <span className="row" style={{ gap: 5 }}><span className="dot" style={{ width: 8, height: 8, borderRadius: 4, background: 'var(--orange)' }} />Due</span>
          <span className="row" style={{ gap: 5 }}><span className="dot" style={{ width: 8, height: 8, borderRadius: 4, background: 'var(--good)' }} />Paid</span>
          <span className="row" style={{ gap: 5 }}><CreditCard size={11} />Spent that day</span>
        </div>
      </div>

      <div className="col" style={{ width: 340, flex: 'none', gap: 14 }}>
        {selected && (
          <Card fill="var(--blush)">
            <div className="col" style={{ gap: 8 }}>
              <h3 className="section-title">{fmtDay(selected, { weekday: 'long', day: 'numeric', month: 'long' })}</h3>
              {(() => {
                const d = due.filter((x) => sameDay(x.date, selected))
                const s = transactions.filter((t) => t.data.amount < 0 && sameDay(txnDate(t), selected))
                return (
                  <>
                    {d.length === 0 && s.length === 0 && <EmptyHint text="Nothing on this day." />}
                    {d.map((x) => <DueRow key={x.id} item={x} />)}
                    {s.map((t) => (
                      <div key={t.id} className="row">
                        <span style={{ fontSize: 13 }}>{t.data.title}</span>
                        <span className="spacer" />
                        <span style={{ fontSize: 13, fontWeight: 600 }}>{money(t.data.amount, true)}</span>
                      </div>
                    ))}
                  </>
                )
              })()}
            </div>
          </Card>
        )}
        <Card>
          <div className="col" style={{ gap: 10 }}>
            <h3 className="section-title">Due in the next 30 days</h3>
            {upcomingTotal > 0 && <div className="secondary" style={{ fontSize: 12 }}>About {money(upcomingTotal)} in known amounts</div>}
            {upcoming.length === 0 && <EmptyHint text="Nothing due. Bills from email and recurring payments show up here." />}
            {upcoming.map((d) => <DueRow key={d.id} item={d} />)}
          </div>
        </Card>
      </div>
    </div>
  )
}

function DueRow({ item }: { item: DuePayment }) {
  const money = useMoney()
  return (
    <div className="money-due">
      <span className="dot" style={{ background: item.paid ? 'var(--good)' : 'var(--orange)' }} />
      <div style={{ minWidth: 0 }}>
        <div className="clamp1" style={{ fontSize: 13, fontWeight: 500 }}>{item.title}</div>
        <div className="muted" style={{ fontSize: 11 }}>
          {relativeDay(item.date)} · {item.kind === 'bill' ? 'Bill' : 'Recurring'}{item.paid ? ' · paid' : ''}
        </div>
      </div>
      <span className="spacer" />
      {item.amount !== null && <span style={{ fontSize: 13, fontWeight: 600 }}>{money(item.amount)}</span>}
    </div>
  )
}

// MARK: New transaction

function NewTransaction({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [kind, setKind] = useState<'expense' | 'income'>('expense')
  const [title, setTitle] = useState('')
  const [amount, setAmount] = useState('')
  const [category, setCategory] = useState('Food')
  const [date, setDate] = useState(toDateInput(new Date()))
  const [recurring, setRecurring] = useState(false)

  useEffect(() => {
    if (!open) return
    setKind('expense'); setTitle(''); setAmount(''); setCategory('Food'); setDate(toDateInput(new Date())); setRecurring(false)
  }, [open])

  const value = Number(amount.replace(',', '.'))
  const valid = title.trim() !== '' && amount.trim() !== '' && !isNaN(value) && value > 0

  const add = () => {
    if (!valid) return
    const income = kind === 'income'
    const when = fromInputs(date, '12:00')
    store.create<Txn>('transaction', {
      title: title.trim(), amount: income ? value : -value, category: income ? 'Income' : category, date: iso(when),
      isRecurring: recurring, source: '', sourceID: '', originalAmount: 0, originalCurrency: '',
    })
    onClose()
  }

  return (
    <Modal open={open} onClose={onClose} width={420}>
      <div className="col" style={{ gap: 16 }}>
        <h2 className="display" style={{ fontSize: 28, margin: 0 }}>New transaction</h2>
        <Segmented<'expense' | 'income'> options={[{ id: 'expense', label: 'Expense' }, { id: 'income', label: 'Income' }]} value={kind} onChange={setKind} />
        <label className="col" style={{ gap: 6 }}>
          <span className="secondary" style={{ fontSize: 13 }}>What</span>
          <input className="field" placeholder="Groceries" value={title} autoFocus onChange={(e) => setTitle(e.target.value)} />
        </label>
        <label className="col" style={{ gap: 6 }}>
          <span className="secondary" style={{ fontSize: 13 }}>Amount</span>
          <input className="field" placeholder="0.00" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') add() }} />
        </label>
        <div className="row">
          {kind === 'expense' && (
            <select className="field" style={{ width: 'auto', flex: 1 }} value={category} onChange={(e) => setCategory(e.target.value)}>
              {MONEY_CATEGORIES.filter((c) => c !== 'Income').map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          )}
          <input className="field" type="date" style={{ width: 'auto', flex: 1 }} value={date} onChange={(e) => setDate(e.target.value)} />
        </div>
        <label className="row" style={{ fontSize: 13 }}>
          <input type="checkbox" checked={recurring} onChange={(e) => setRecurring(e.target.checked)} />Repeats monthly
        </label>
        <div className="row">
          <button className="btn-soft" onClick={onClose}>Cancel</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120 }} disabled={!valid} onClick={add}>Add</button>
        </div>
      </div>
    </Modal>
  )
}

// MARK: Money coach (Claude's savings tips, refreshed once a day)

interface Tip { title: string; detail: string; monthly_saving: number }
interface Advice { headline: string; tips: Tip[]; day: string }
const COACH_KEY = 'orbit.moneyCoach'

function MoneyCoachCard({ hasExpenses }: { hasExpenses: boolean }) {
  const keys = useKeys()
  const name = useAssistantName()
  const money = useMoney()
  const currency = useSetting<string>('currencyCode', 'USD')
  const [advice, setAdvice] = useState<Advice | null>(() => { try { return JSON.parse(localStorage.getItem(COACH_KEY) ?? 'null') } catch { return null } })
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const refresh = async (force = false) => {
    if (loading || !keys.anthropic || !hasExpenses) return
    if (!force && advice?.day === dayKey(new Date())) return
    setLoading(true)
    setError('')
    try {
      const system = `You are a practical, kind money coach inside a personal budgeting app. Look at the spending data and suggest specific ways to save.
- headline: one short sentence on how this month is going compared with the budget and previous months.
- tips: 3-4 concrete actions based on THIS data (name the merchants, categories and subscriptions involved), each with a realistic monthly_saving in the user's currency (${currency}). detail is 1-2 sentences. No generic advice like "make a budget".
Don't shame; be encouraging. Plain text, no markdown.`
      const schema = {
        type: 'object',
        properties: {
          headline: { type: 'string' },
          tips: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, detail: { type: 'string' }, monthly_saving: { type: 'number' } }, required: ['title', 'detail', 'monthly_saving'], additionalProperties: false } },
        },
        required: ['headline', 'tips'], additionalProperties: false,
      }
      const r = await structured<{ headline: string; tips: Tip[] }>(system, moneySummary(), schema, 'medium')
      const a = { ...r, day: dayKey(new Date()) }
      setAdvice(a)
      localStorage.setItem(COACH_KEY, JSON.stringify(a))
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { refresh() }, [keys.anthropic, hasExpenses])

  return (
    <div className="card col" style={{ background: '#141416', color: '#f4f4f5', padding: 20, gap: 12 }}>
      <div className="row" style={{ gap: 8 }}>
        <Sparkles size={14} color="var(--lime)" />
        <span style={{ fontSize: 12, fontWeight: 600, opacity: 0.7 }}>Money coach</span>
        <span className="spacer" />
        {keys.anthropic && (
          <button title="Refresh advice" disabled={loading} onClick={() => refresh(true)}
            style={{ width: 28, height: 28, borderRadius: '50%', background: 'rgba(255,255,255,0.1)', color: '#f4f4f5', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
            <RefreshCw size={12} />
          </button>
        )}
      </div>
      {!keys.anthropic ? (
        <span style={{ fontSize: 13, opacity: 0.8 }}>Add your Anthropic API key (or unlock your keys from the Mac) in Settings › AI to get savings advice.</span>
      ) : advice && advice.tips?.length ? (
        <>
          <div className="display" style={{ fontSize: 20 }}>{advice.headline}</div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: 12 }}>
            {advice.tips.map((t) => (
              <div key={t.title} className="col" style={{ gap: 6, padding: 12, borderRadius: 14, background: 'rgba(255,255,255,0.07)' }}>
                <div className="row" style={{ alignItems: 'flex-start', gap: 6 }}>
                  <strong style={{ fontSize: 14, flex: 1 }}>{t.title}</strong>
                  {t.monthly_saving > 0 && <span className="pill compact" style={{ background: 'var(--lime)', fontWeight: 700 }}>~{money(t.monthly_saving)}/mo</span>}
                </div>
                <span style={{ fontSize: 12, opacity: 0.8 }}>{t.detail}</span>
              </div>
            ))}
          </div>
        </>
      ) : error ? (
        <span style={{ fontSize: 12 }}>⚠️ {error}</span>
      ) : loading ? (
        <span className="display" style={{ fontSize: 18, fontWeight: 500 }}>{name} is looking at your spending…</span>
      ) : (
        <span style={{ fontSize: 13, opacity: 0.8 }}>Add a few expenses (or connect Gmail) and {name} will suggest where you can save.</span>
      )}
      {keys.anthropic && (
        <button onClick={() => openAsk("Let's talk about my spending. Where is my money going, and what should I change?")}
          className="row" style={{ alignSelf: 'flex-start', gap: 6, background: 'var(--lime)', color: 'var(--sticker-ink)', borderRadius: 999, padding: '8px 14px', fontWeight: 600, fontSize: 13 }}>
          <MessagesSquare size={14} /> Discuss with {name}
        </button>
      )}
    </div>
  )
}

// MARK: Expenses from email (header chip + popover)

function EmailChip() {
  const keys = useKeys()
  const name = useAssistantName()
  const currency = useSetting<string>('currencyCode', 'USD')
  const [, force] = useState(0)
  const [open, setOpen] = useState(false)
  useEffect(() => onEmailExpensesChange(() => force((n) => n + 1)), [])
  const s = emailExpensesState()
  if (!keys.gmail.length || !emailExpensesEnabled()) return null
  return (
    <span style={{ position: 'relative' }}>
      <button className="btn-soft" onClick={() => setOpen(!open)}>
        {s.running ? <RefreshCw size={13} /> : <MailPlus size={14} />}
        {s.running ? 'Reading receipts…' : 'From email'}
      </button>
      {open && (
        <div className="card col" onMouseLeave={() => setOpen(false)}
          style={{ position: 'absolute', top: 44, right: 0, width: 340, zIndex: 20, background: 'var(--canvas)', boxShadow: '0 20px 60px rgba(0,0,0,0.25)', gap: 10, padding: 20 }}>
          <div className="display" style={{ fontSize: 20 }}>Expenses from email</div>
          <span className="secondary" style={{ fontSize: 12 }}>
            {name} checks your inboxes every few hours: anything under a payments, receipts, bank or orders label, plus receipts, invoices and
            card-charge emails anywhere. Paid amounts are added here (converted to {currency}); bills still due become tasks.
          </span>
          {s.status && <span style={{ fontSize: 12, fontWeight: 500 }}>{s.status}</span>}
          {s.lastSync > 0 && <span className="muted" style={{ fontSize: 11 }}>Last checked {relativeTime(new Date(s.lastSync))}</span>}
          <span className="muted" style={{ fontSize: 11 }}>Wrong one? Right-click it › Not an expense, and it won't come back.</span>
          <button className="btn-primary" disabled={s.running || !keys.anthropic} onClick={() => syncEmailExpenses()}>{s.running ? 'Checking…' : 'Check now'}</button>
        </div>
      )}
    </span>
  )
}
