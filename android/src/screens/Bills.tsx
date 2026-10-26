// Money › Bills, like BillsView.swift + Bills.swift on the Mac: rent, internet, phone… each with its due day, a reminder
// a few days before, and paid or not this month. A bill counts as paid when marked by hand (paidMonths "yyyy-MM"), or
// when an expense with one of its words comes in near the due date.
import { useState } from 'react'
import { Plus, FileText } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Txn } from '@/lib/models'
import { iso, parse, startOfDay, startOfMonth, addDays, addMonths, daysInMonth, daysBetween, relativeDay } from '@/lib/dates'
import { Card, EmptyHint, Modal, Segmented, useMoney } from '@/components/ui'
import { Bill, monthKey } from '../reminders'

type T = Txn & { account?: string }
type Status = { kind: 'paid'; at: Date | null } | { kind: 'due'; days: number } | { kind: 'late'; days: number }
interface Cycle { due: Date; status: Status; payment: Rec<T> | null }

// MARK: Tracker (BillTracker on the Mac)

const matchWords = (b: Bill): string[] =>
  (b.match || b.name).toLowerCase().split(',').map((w) => w.trim()).filter((w) => w.length >= 2)

/** The due date in the month containing `month`, clamped to its last day. */
const dueDate = (b: Bill, month: Date): Date => {
  const start = startOfMonth(month)
  return addDays(start, Math.min(Math.max(b.dueDay || 1, 1), daysInMonth(start)) - 1)
}

/** The expense Joshu logs when you mark a bill paid by hand (same id as the Mac's). */
const paymentID = (b: Rec<Bill>, due: Date): string => `bill:${b.id}:${monthKey(due)}`

/** An expense that looks like this bill, from 20 days before the due date to 10 days after. */
function payment(b: Rec<Bill>, due: Date, txns: Rec<T>[]): Rec<T> | null {
  const words = matchWords(b.data)
  if (!words.length) return null
  const from = addDays(due, -20).getTime(), to = addDays(due, 11).getTime()
  return txns.find((t) => {
    const d = parse(t.data.date)?.getTime() ?? 0
    if (t.data.amount >= 0 || d < from || d >= to) return false
    // "Mark paid" logs an expense for that month; it mustn't also pay next month's.
    if (t.data.source === 'bill') return t.data.sourceID === paymentID(b, due)
    const title = (t.data.title ?? '').toLowerCase()
    return words.some((w) => title.includes(w))
  }) ?? null
}

function cycle(b: Rec<Bill>, due: Date, txns: Rec<T>[], today: Date): Cycle {
  const days = daysBetween(today, due)
  if ((b.data.paidMonths ?? []).includes(monthKey(due))) {
    const mine = txns.find((t) => t.data.sourceID === paymentID(b, due))
    return { due, status: { kind: 'paid', at: parse(mine?.data.date) }, payment: null }
  }
  const p = payment(b, due, txns)
  if (p) return { due, status: { kind: 'paid', at: parse(p.data.date) }, payment: p }
  return { due, status: days < 0 ? { kind: 'late', days: -days } : { kind: 'due', days }, payment: null }
}

/** This month's bill (kept once paid, as on the Mac's Bills screen), or next month's if it was added after the due day. */
function current(b: Rec<Bill>, txns: Rec<T>[]): Cycle {
  const today = startOfDay(new Date())
  const thisDue = dueDate(b.data, today)
  const c = cycle(b, thisDue, txns, today)
  const created = parse(b.data.createdAt)
  if (created && thisDue < startOfDay(created) && c.status.kind !== 'paid') return cycle(b, dueDate(b.data, addMonths(startOfMonth(today), 1)), txns, today)
  return c
}

/** Marks the month paid (logging the amount as an expense so it comes off Left to spend), or undoes that. */
function setPaid(b: Rec<Bill>, due: Date, paid: boolean, txns: Rec<T>[], amount?: number): void {
  const key = monthKey(due), id = paymentID(b, due)
  const logged = txns.filter((t) => t.data.sourceID === id)
  const months = b.data.paidMonths ?? []
  if (paid) {
    if (!months.includes(key)) store.update<Bill>(b.id, { paidMonths: [...months, key] })
    const value = Math.abs(amount ?? b.data.amount)
    if (!logged.length && value > 0) {
      store.create<T>('transaction', {
        title: b.data.name, amount: -value, category: b.data.category || 'Bills', date: iso(new Date()), isRecurring: true,
        source: 'bill', sourceID: id, originalAmount: 0, originalCurrency: '', account: '',
      })
    }
  } else {
    store.update<Bill>(b.id, { paidMonths: months.filter((m) => m !== key) })
    logged.forEach((t) => store.remove(t.id))
  }
}

function describe(s: Status): string {
  if (s.kind === 'paid') {
    if (!s.at) return 'Paid'
    const r = relativeDay(s.at)
    return `Paid ${r === 'Today' || r === 'Yesterday' ? r.toLowerCase() : r}`
  }
  if (s.kind === 'late') return s.days === 1 ? '1 day late' : `${s.days} days late`
  return s.days === 0 ? 'Due today' : s.days === 1 ? 'Due tomorrow' : `Due in ${s.days} days`
}

// MARK: Screen

export default function Bills() {
  const bills = useRecords<Bill>('bill')
  const txns = useRecords<T>('transaction')
  const money = useMoney()
  const [editing, setEditing] = useState<Rec<Bill> | null>(null)
  const [adding, setAdding] = useState<string | null>(null)
  const [asking, setAsking] = useState<{ bill: Rec<Bill>; due: Date } | null>(null)

  const cycles = bills.map((b) => ({ b, c: current(b, txns) })).sort((x, y) => {
    const px = x.c.status.kind === 'paid', py = y.c.status.kind === 'paid'
    return px !== py ? (px ? 1 : -1) : x.c.due.getTime() - y.c.due.getTime()
  })
  const thisMonth = startOfMonth(new Date()).getTime()
  const left = cycles.reduce((s, { b, c }) => s + (c.status.kind !== 'paid' && startOfMonth(c.due).getTime() === thisMonth ? b.data.amount : 0), 0)

  return (
    <div className="page">
      <div className="col" style={{ gap: 16 }}>
        <div className="row" style={{ gap: 12 }}>
          <div style={{ minWidth: 0 }}>
            <h1 className="page-title">Bills</h1>
            <div className="secondary" style={{ fontSize: 13, marginTop: 4 }}>
              {!bills.length ? 'Add the bills you pay every month. Joshu reminds you before each one.'
                : left > 0 ? `${money(left)} still to pay this month` : 'All paid this month'}
            </div>
          </div>
          <span className="spacer" />
          <button className="btn-soft" style={{ minHeight: 40 }} onClick={() => setAdding('')}><Plus size={14} />Add</button>
        </div>

        {!bills.length && (
          <Card>
            <div className="col" style={{ gap: 10 }}>
              <EmptyHint icon={<FileText size={15} />} text="No bills yet." />
              <div className="secondary" style={{ fontSize: 12 }}>
                When a bank text or receipt with the bill's name comes in near the due date, Joshu marks it paid for you.
              </div>
              <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
                {['Rent', 'Internet', 'Phone', 'Electricity'].map((n) => (
                  <button key={n} className="btn-soft" style={{ minHeight: 40 }} onClick={() => setAdding(n)}>{n}</button>
                ))}
              </div>
            </div>
          </Card>
        )}

        {cycles.map(({ b, c }) => (
          <BillRow key={b.id} bill={b} cycle={c} onEdit={() => setEditing(b)}
            onToggle={() => {
              const paid = c.status.kind === 'paid'
              // A bill whose amount varies asks how much it was, so the right amount comes off Left to spend.
              if (!paid && b.data.amount <= 0) setAsking({ bill: b, due: c.due })
              else setPaid(b, c.due, !paid, txns)
            }} />
        ))}
      </div>

      {adding !== null && <Editor bill={null} name={adding} onClose={() => setAdding(null)} />}
      {editing && <Editor bill={editing} onClose={() => setEditing(null)} />}
      {asking && <AmountSheet name={asking.bill.data.name} onClose={() => setAsking(null)}
        onSave={(v) => { setPaid(asking.bill, asking.due, true, txns, v); setAsking(null) }} />}
    </div>
  )
}

function BillRow({ bill, cycle, onEdit, onToggle }: { bill: Rec<Bill>; cycle: Cycle; onEdit: () => void; onToggle: () => void }) {
  const money = useMoney()
  const s = cycle.status
  const tint = s.kind === 'paid' ? 'var(--mint)' : s.kind === 'late' ? 'var(--peach)' : s.days <= (bill.data.remindDays ?? 3) ? 'var(--lime)' : null
  const chip = tint ? 'rgba(255,255,255,0.6)' : 'var(--canvas)'
  return (
    <div className="row" style={{ gap: 12, padding: 14, borderRadius: 16, alignItems: 'flex-start',
      background: tint ?? 'var(--card)', color: tint ? 'var(--sticker-ink)' : 'var(--ink)' }}>
      <button onClick={onEdit} className="row" style={{ gap: 12, flex: 1, minWidth: 0, textAlign: 'left', color: 'inherit', alignItems: 'flex-start' }}>
        <div style={{ width: 44, height: 48, borderRadius: 10, background: chip, textAlign: 'center', flex: 'none', paddingTop: 5 }}>
          <div style={{ fontSize: 10, fontWeight: 600, textTransform: 'uppercase' }}>{cycle.due.toLocaleDateString(undefined, { month: 'short' })}</div>
          <div className="display" style={{ fontSize: 20, lineHeight: 1.1 }}>{cycle.due.getDate()}</div>
        </div>
        <div className="col" style={{ gap: 3, minWidth: 0, alignItems: 'flex-start' }}>
          <div className="clamp1" style={{ fontSize: 15, fontWeight: 600 }}>{bill.data.name}</div>
          <div style={{ fontSize: 12, fontWeight: 500 }}>{describe(s)}</div>
          {cycle.payment && (
            <div className="clamp1" style={{ fontSize: 11, opacity: 0.7 }}>Matched “{cycle.payment.data.title}” {money(cycle.payment.data.amount)}</div>
          )}
        </div>
      </button>
      <div className="col" style={{ gap: 8, alignItems: 'flex-end', flex: 'none' }}>
        {bill.data.amount > 0 && <div style={{ fontSize: 14, fontWeight: 600 }}>{money(bill.data.amount)}</div>}
        {(s.kind !== 'paid' || !cycle.payment) && (
          <button onClick={onToggle} style={{ minHeight: 36, padding: '6px 12px', borderRadius: 999, background: chip, fontSize: 12, fontWeight: 600, color: 'inherit' }}>
            {s.kind === 'paid' ? 'Undo' : 'Mark paid'}
          </button>
        )}
      </div>
    </div>
  )
}

function AmountSheet({ name, onClose, onSave }: { name: string; onClose: () => void; onSave: (v: number) => void }) {
  const [text, setText] = useState('')
  const value = Number(text.replace(/,/g, '')) || 0
  return (
    <Modal open onClose={onClose}>
      <div className="col" style={{ gap: 14 }}>
        <h2 className="display" style={{ fontSize: 24, margin: 0 }}>How much was {name}?</h2>
        <div className="secondary" style={{ fontSize: 13 }}>It's logged as an expense and comes off what's left to spend.</div>
        <input className="field" autoFocus inputMode="decimal" placeholder="Amount" value={text} onChange={(e) => setText(e.target.value)} />
        <div className="row">
          <button className="btn-soft" onClick={onClose}>Cancel</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 130 }} onClick={() => onSave(value)}>Mark paid</button>
        </div>
      </div>
    </Modal>
  )
}

function Editor({ bill, name: initial = '', onClose }: { bill: Rec<Bill> | null; name?: string; onClose: () => void }) {
  const d = bill?.data
  const [name, setName] = useState(d?.name ?? initial)
  const [amount, setAmount] = useState(d && d.amount > 0 ? String(d.amount) : '')
  const [dueDay, setDueDay] = useState(d?.dueDay ?? 1)
  const [remind, setRemind] = useState(String([0, 1, 3, 7].includes(d?.remindDays ?? 3) ? d?.remindDays ?? 3 : 3) as '0' | '1' | '3' | '7')
  const [match, setMatch] = useState(d?.match ?? '')

  const save = () => {
    const n = name.trim()
    if (!n) return
    const patch = { name: n, amount: Number(amount.replace(/,/g, '')) || 0, dueDay, remindDays: Number(remind), match: match.trim() }
    if (bill) store.update<Bill>(bill.id, patch)
    else store.create<Bill>('bill', { ...patch, category: 'Bills', paidMonths: [], notes: '', createdAt: iso(new Date()) })
    onClose()
  }

  return (
    <Modal open onClose={onClose}>
      <div className="col" style={{ gap: 14 }}>
        <h2 className="display" style={{ fontSize: 26, margin: 0 }}>{bill ? 'Edit bill' : 'New bill'}</h2>
        <input className="field" autoFocus={!initial} placeholder="Rent, Internet, Vodafone…" value={name} onChange={(e) => setName(e.target.value)} />
        <input className="field" inputMode="decimal" placeholder="Usual amount (empty if it changes)" value={amount} onChange={(e) => setAmount(e.target.value)} />
        <label className="row" style={{ gap: 12, fontSize: 13 }}>
          <span className="secondary">Due on day</span>
          <span className="spacer" />
          <select className="field" style={{ width: 90, minHeight: 40 }} value={dueDay} onChange={(e) => setDueDay(Number(e.target.value))}>
            {Array.from({ length: 31 }, (_, i) => <option key={i + 1} value={i + 1}>{i + 1}</option>)}
          </select>
        </label>
        <div className="col" style={{ gap: 6 }}>
          <span className="secondary" style={{ fontSize: 13 }}>Remind me</span>
          <Segmented options={[{ id: '0', label: 'On the day' }, { id: '1', label: '1 day' }, { id: '3', label: '3 days' }, { id: '7', label: 'A week' }]}
            value={remind} onChange={setRemind} />
        </div>
        <div className="col" style={{ gap: 4 }}>
          <input className="field" placeholder={name ? `Bank text words, e.g. ${name.toLowerCase()}` : 'Bank text words, e.g. vodafone, we'}
            value={match} onChange={(e) => setMatch(e.target.value)} />
          <span className="muted" style={{ fontSize: 11 }}>When an expense with one of these words comes in near the due date, the bill is marked paid. Separate words with commas.</span>
        </div>
        <div className="row">
          {bill
            ? <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(bill.id); onClose() }}>Delete</button>
            : <button className="btn-soft" onClick={onClose}>Cancel</button>}
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120 }} disabled={!name.trim()} onClick={save}>Save</button>
        </div>
      </div>
    </Modal>
  )
}
