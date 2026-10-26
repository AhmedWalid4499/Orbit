// Your banks, like AccountsView.swift on the Mac: one card per bank account, card or wallet (added by itself from bank
// texts, or by hand), with the balance the bank last texted. Each opens a page with this month, six months of spending,
// categories and its transactions (linked by the transaction's `account` = the account's id).
import { useState } from 'react'
import { Plus, CreditCard, Landmark, Smartphone, Banknote } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Txn } from '@/lib/models'
import { iso, parse, startOfMonth, addMonths, relativeTime } from '@/lib/dates'
import { Modal, Segmented, useMoney } from '@/components/ui'
import { BankAccount } from '../bank'

type T = Txn & { account?: string }
type Kind = 'card' | 'account' | 'wallet' | 'cash'

const PAIRS = [['#7B5CF5', '#4338CA'], ['#E6FF1F', '#8EEDBF'], ['#27D3F6', '#7B5CF5'], ['#EDAA2F', '#F7C2EC'], ['#F472B6', '#7C3AED'], ['#2A2A30', '#0E0E10']]
const wrap = (i: number) => ((i % 6) + 6) % 6
const gradient = (i: number) => `linear-gradient(135deg, ${PAIRS[wrap(i)][0]}, ${PAIRS[wrap(i)][1]})`
const inkFor = (i: number) => ([1, 3].includes(wrap(i)) ? 'var(--sticker-ink)' : '#fff')
const title = (a: BankAccount) => (a.last4 ? `${a.name} ••${a.last4}` : a.name)

function KindIcon({ kind, size = 16 }: { kind: string; size?: number }) {
  if (kind === 'account') return <Landmark size={size} />
  if (kind === 'wallet') return <Smartphone size={size} />
  if (kind === 'cash') return <Banknote size={size} />
  return <CreditCard size={size} />
}

/** Spent and money in for one account between two dates. */
function totals(id: string, txns: Rec<T>[], from: Date, to: Date) {
  let spent = 0, income = 0
  for (const t of txns) {
    if (t.data.account !== id) continue
    const d = parse(t.data.date)
    if (!d || d < from || d >= to) continue
    if (t.data.amount < 0) spent -= t.data.amount; else income += t.data.amount
  }
  return { spent, income }
}

export default function Accounts() {
  const accounts = useRecords<BankAccount>('account').sort((a, b) => (a.data.createdAt ?? '').localeCompare(b.data.createdAt ?? ''))
  const txns = useRecords<T>('transaction')
  const [open, setOpen] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const month = startOfMonth(new Date()), next = addMonths(month, 1)
  const openRec = accounts.find((a) => a.id === open)

  return (
    <div className="page">
      <div className="col" style={{ gap: 16 }}>
        <div className="row">
          <h1 className="page-title">Your banks</h1>
          <span className="spacer" />
          <button className="btn-soft" style={{ minHeight: 40 }} onClick={() => setAdding(true)}><Plus size={14} />Add</button>
        </div>
        {!accounts.length && (
          <div className="col" style={{ gap: 8, padding: 18, borderRadius: 24, border: '1.5px dashed var(--line)' }}>
            <CreditCard size={22} />
            <div style={{ fontSize: 14, fontWeight: 600 }}>Each bank and card gets its own page here.</div>
            <div className="secondary" style={{ fontSize: 12 }}>
              They appear by themselves from your bank texts, with the balance your bank last texted. You can also add one.
            </div>
          </div>
        )}
        {accounts.map((a) => (
          <button key={a.id} onClick={() => setOpen(a.id)} style={{ textAlign: 'left', display: 'block', width: '100%' }}>
            <AccountCard a={a.data} spent={totals(a.id, txns, month, next).spent} />
          </button>
        ))}
      </div>
      {openRec && <AccountPage account={openRec} txns={txns} onClose={() => setOpen(null)} />}
      {adding && <Editor account={null} count={accounts.length} onClose={() => setAdding(false)} />}
    </div>
  )
}

/** A bank card, like the ones in a banking app. */
function AccountCard({ a, spent }: { a: BankAccount; spent: number }) {
  const money = useMoney()
  const at = parse(a.balanceAt)
  return (
    <div className="col" style={{ position: 'relative', overflow: 'hidden', height: 180, padding: 18, borderRadius: 24, background: gradient(a.colorIndex),
      color: inkFor(a.colorIndex), boxShadow: '0 6px 20px rgba(0,0,0,0.12)', justifyContent: 'space-between' }}>
      <div style={{ position: 'absolute', width: 220, height: 220, borderRadius: '50%', background: 'rgba(255,255,255,0.12)', right: -60, top: -110 }} />
      <div className="row" style={{ position: 'relative' }}>
        <span className="clamp1" style={{ fontSize: 18, fontWeight: 700 }}>{a.name}</span>
        <span className="spacer" />
        <span style={{ opacity: 0.85 }}><KindIcon kind={a.kind} /></span>
      </div>
      <div style={{ position: 'relative', fontFamily: 'ui-monospace, monospace', fontSize: 15, opacity: 0.85 }}>{a.last4 ? `••••  ••••  ••••  ${a.last4}` : ' '}</div>
      <div className="row" style={{ position: 'relative', alignItems: 'flex-end' }}>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontSize: 11, fontWeight: 600, opacity: 0.75 }}>{at ? (a.kind === 'card' ? 'Available' : 'Balance') : 'Spent this month'}</div>
          <div className="clamp1" style={{ fontSize: 24, fontWeight: 700 }}>{money(at ? a.balance : spent)}</div>
        </div>
        <span className="spacer" />
        {at && <span style={{ fontSize: 10, fontWeight: 500, opacity: 0.7 }}>{relativeTime(at)}</span>}
      </div>
    </div>
  )
}

/** One account's page: its card, this month, six months of spending, categories and every transaction. */
function AccountPage({ account, txns, onClose }: { account: Rec<BankAccount>; txns: Rec<T>[]; onClose: () => void }) {
  const money = useMoney()
  const [editing, setEditing] = useState(false)
  const a = account.data
  const month = startOfMonth(new Date()), next = addMonths(month, 1)
  const t = totals(account.id, txns, month, next)
  const mine = txns.filter((x) => x.data.account === account.id)
    .sort((x, y) => (parse(y.data.date)?.getTime() ?? 0) - (parse(x.data.date)?.getTime() ?? 0))
  const thisMonth = mine.filter((x) => { const d = parse(x.data.date); return d && d >= month && d < next })
  const months = [5, 4, 3, 2, 1, 0].map((back) => {
    const s = addMonths(month, -back)
    return { label: s.toLocaleDateString(undefined, { month: 'short' }), spent: totals(account.id, txns, s, addMonths(s, 1)).spent }
  })
  const top = Math.max(1, ...months.map((m) => m.spent))
  const cats = new Map<string, number>()
  for (const x of thisMonth) if (x.data.amount < 0) cats.set(x.data.category, (cats.get(x.data.category) ?? 0) - x.data.amount)
  const categories = [...cats].sort((x, y) => y[1] - x[1]).slice(0, 6)
  const catTotal = Math.max(1, categories.reduce((s, c) => s + c[1], 0))

  return (
    <Modal open onClose={onClose} width={560}>
      <div className="col" style={{ gap: 16 }}>
        <div className="row" style={{ gap: 8, paddingRight: 36 }}>
          <h2 className="display clamp1" style={{ fontSize: 24, margin: 0 }}>{title(a)}</h2>
          <span className="spacer" />
          <button className="btn-soft" style={{ minHeight: 36 }} onClick={() => setEditing(true)}>Edit</button>
        </div>
        <AccountCard a={a} spent={t.spent} />
        <div className="row" style={{ gap: 8 }}>
          {([['Spent', money(t.spent), 'var(--peach)'], ['Money in', money(t.income), 'var(--mint)'], ['Payments', String(thisMonth.length), 'var(--cyan)']] as const).map(([l, v, c]) => (
            <div key={l} style={{ flex: 1, minWidth: 0, padding: 12, borderRadius: 16, background: c, color: 'var(--sticker-ink)' }}>
              <div style={{ fontSize: 11, fontWeight: 600 }}>{l}</div>
              <div className="display clamp1" style={{ fontSize: 17 }}>{v}</div>
              <div style={{ fontSize: 10, opacity: 0.7 }}>this month</div>
            </div>
          ))}
        </div>
        <div className="card" style={{ padding: 16 }}>
          <div style={{ fontSize: 15, fontWeight: 600, marginBottom: 10 }}>Spending by month</div>
          <div className="row" style={{ gap: 8, alignItems: 'flex-end', height: 130 }}>
            {months.map((m) => (
              <div key={m.label} className="col" style={{ flex: 1, gap: 4, alignItems: 'center', justifyContent: 'flex-end', height: '100%' }}>
                <div style={{ width: '100%', height: `${Math.max(2, (m.spent / top) * 100)}px`, borderRadius: 6, background: gradient(a.colorIndex) }} />
                <span className="muted" style={{ fontSize: 10 }}>{m.label}</span>
              </div>
            ))}
          </div>
        </div>
        {categories.length > 0 && (
          <div className="card col" style={{ padding: 16, gap: 10 }}>
            <div style={{ fontSize: 15, fontWeight: 600 }}>Breakdown</div>
            {categories.map(([name, v]) => (
              <div key={name} className="col" style={{ gap: 4 }}>
                <div className="row" style={{ fontSize: 12 }}>
                  <span style={{ fontWeight: 600 }}>{name}</span><span className="spacer" />
                  <span className="secondary">{money(v)} · {Math.round((v / catTotal) * 100)}%</span>
                </div>
                <div style={{ height: 6, borderRadius: 3, background: 'var(--line)' }}>
                  <div style={{ width: `${(v / catTotal) * 100}%`, height: '100%', borderRadius: 3, background: gradient(a.colorIndex) }} />
                </div>
              </div>
            ))}
          </div>
        )}
        <div className="card col" style={{ padding: 16, gap: 8 }}>
          <div style={{ fontSize: 15, fontWeight: 600 }}>Transactions</div>
          {!mine.length && <div className="secondary" style={{ fontSize: 13 }}>Payments from this {a.kind === 'account' ? 'account' : 'card'} show up here.</div>}
          {mine.slice(0, 80).map((x) => (
            <div key={x.id} className="row" style={{ gap: 12, padding: '4px 0' }}>
              <span style={{ width: 36, height: 36, borderRadius: 10, flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                background: gradient(a.colorIndex), color: inkFor(a.colorIndex), fontWeight: 700 }}>{(x.data.title || '?').slice(0, 1).toUpperCase()}</span>
              <div style={{ minWidth: 0, flex: 1 }}>
                <div className="clamp1" style={{ fontSize: 14, fontWeight: 600 }}>{x.data.title}</div>
                <div className="muted" style={{ fontSize: 11 }}>{x.data.category} · {parse(x.data.date)?.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}</div>
              </div>
              <span style={{ fontSize: 14, fontWeight: 600, color: x.data.amount < 0 ? 'var(--critical)' : 'var(--good)' }}>{money(x.data.amount, true)}</span>
            </div>
          ))}
        </div>
      </div>
      {editing && <Editor account={account} count={0} onClose={() => setEditing(false)} onDeleted={onClose} />}
    </Modal>
  )
}

/** Add or change an account: name, last 4 digits, kind, colour and (optionally) its balance. */
function Editor({ account, count, onClose, onDeleted }: { account: Rec<BankAccount> | null; count: number; onClose: () => void; onDeleted?: () => void }) {
  const d = account?.data
  const [name, setName] = useState(d?.name ?? '')
  const [last4, setLast4] = useState(d?.last4 ?? '')
  const [kind, setKind] = useState<Kind>((['card', 'account', 'wallet', 'cash'].includes(d?.kind ?? '') ? d!.kind : 'card') as Kind)
  const [color, setColor] = useState(d?.colorIndex ?? count % 6)
  const [balance, setBalance] = useState(d?.balanceAt ? String(d.balance) : '')
  const [confirm, setConfirm] = useState(false)
  const typed = balance.trim() ? Number(balance.replace(/,/g, '')) : NaN

  const preview: BankAccount = { name: name || 'Bank', last4, kind, colorIndex: color, balance: isNaN(typed) ? 0 : typed,
    balanceAt: isNaN(typed) ? null : iso(new Date()), createdAt: '' }

  const save = () => {
    const n = name.trim()
    if (!n) return
    const patch: Partial<BankAccount> = { name: n, last4, kind, colorIndex: color }
    if (!isNaN(typed)) {
      if (!d?.balanceAt || Math.abs(d.balance - typed) > 0.001) { patch.balance = typed; patch.balanceAt = iso(new Date()) }
    } else if (!balance.trim()) { patch.balance = 0; patch.balanceAt = null }
    if (account) store.update<BankAccount>(account.id, patch)
    else store.create<BankAccount>('account', { name: n, last4, kind, colorIndex: color, balance: 0, balanceAt: null, createdAt: iso(new Date()), ...patch })
    onClose()
  }

  const remove = () => {
    if (!account) return
    // Its transactions stay in Money; they just aren't linked to this card any more.
    for (const t of store.list<T>('transaction')) if (t.data.account === account.id) store.update<T>(t.id, { account: '' })
    store.remove(account.id)
    onClose()
    onDeleted?.()
  }

  return (
    <Modal open onClose={onClose}>
      <div className="col" style={{ gap: 14 }}>
        <h2 className="display" style={{ fontSize: 24, margin: 0 }}>{account ? `Edit ${title(account.data)}` : 'Add a bank or card'}</h2>
        <AccountCard a={preview} spent={0} />
        <input className="field" placeholder="Bank or wallet, e.g. CIB" value={name} onChange={(e) => setName(e.target.value)} />
        <input className="field" inputMode="numeric" placeholder="Last 4 digits (optional)" value={last4}
          onChange={(e) => setLast4(e.target.value.replace(/\D/g, '').slice(0, 4))} />
        <Segmented options={[{ id: 'card', label: 'Card' }, { id: 'account', label: 'Account' }, { id: 'wallet', label: 'Wallet' }, { id: 'cash', label: 'Cash' }]}
          value={kind} onChange={setKind} />
        <div className="row" style={{ gap: 10 }}>
          {PAIRS.map((_, i) => (
            <button key={i} onClick={() => setColor(i)} aria-label={`Colour ${i + 1}`}
              style={{ width: 40, height: 40, borderRadius: '50%', background: gradient(i), outline: color === i ? '2.5px solid var(--ink)' : 'none', outlineOffset: 2 }} />
          ))}
        </div>
        <input className="field" inputMode="decimal" placeholder="Balance now (optional; bank texts keep it up to date)" value={balance}
          onChange={(e) => setBalance(e.target.value)} />
        {confirm && (
          <div className="card" style={{ padding: 12, fontSize: 13 }}>
            Delete {title(account!.data)}? Its transactions stay in Money; they just won't be linked to it any more.
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn-soft" onClick={() => setConfirm(false)}>Keep</button>
              <span className="spacer" />
              <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={remove}>Delete</button>
            </div>
          </div>
        )}
        <div className="row">
          {account
            ? <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => setConfirm(true)}>Delete</button>
            : <button className="btn-soft" onClick={onClose}>Cancel</button>}
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120 }} disabled={!name.trim()} onClick={save}>Save</button>
        </div>
      </div>
    </Modal>
  )
}
