// Money › Budgets & rules, like MoneyRulesView.swift on the Mac: spending alerts, a budget per category (synced
// "categoryBudgets": { [category]: number }, limits above 0 only) and the merchant categories Joshu learned from your
// corrections (synced "merchantRules": { [merchantKey]: category }, keys from merchantKey() as in MoneySmarts.swift).
import { useEffect, useState } from 'react'
import { ArrowRight, XCircle } from 'lucide-react'
import { store, useRecords, SettingKey } from '@/lib/store'
import { Txn, MONEY_CATEGORIES } from '@/lib/models'
import { merchantRules } from '@/lib/merchantRules'
import { parse } from '@/lib/dates'
import { Modal, useMoney } from '@/components/ui'
import { currentPeriod } from '../lib/budgetPeriod'

const CATEGORIES = MONEY_CATEGORIES.filter((c) => c !== 'Income')
// Alert switches (bools, default on), synced.
const NOTIFY_BUDGETS = 'notify.budgets' as SettingKey
const NOTIFY_BIG = 'notify.bigCharges' as SettingKey

// MARK: Merchant rules (MerchantRules on the Mac), shared with the Money screen

export { merchantKey, sameMerchant, merchantRules, learnedCategory, learnCategory } from '@/lib/merchantRules'

// MARK: Sheet

const titleCase = (s: string) => s.replace(/(^|\s)(\p{L})/gu, (_, a, b) => a + b.toUpperCase())
const num = (s: string) => Math.max(0, Number(s.replace(/,/g, '')) || 0)
const bool = (key: SettingKey) => store.setting<boolean>(key) ?? true

export default function MoneyRulesSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const txns = useRecords<Txn>('transaction')
  const money = useMoney()
  const [monthly, setMonthly] = useState('')
  const [budgets, setBudgets] = useState<Record<string, string>>({})
  const [rules, setRules] = useState<Record<string, string>>({})
  const [budgetAlerts, setBudgetAlerts] = useState(true)
  const [bigCharges, setBigCharges] = useState(true)

  // Fresh copy of the synced values each time the sheet opens.
  useEffect(() => {
    if (!open) return
    setMonthly(String(Number(store.setting('monthlyBudget') ?? 2000) || 0))
    const b = store.setting<Record<string, number>>('categoryBudgets') ?? {}
    setBudgets(Object.fromEntries(Object.entries(b).filter(([, v]) => Number(v) > 0).map(([k, v]) => [k, String(v)])))
    setRules(merchantRules())
    setBudgetAlerts(bool(NOTIFY_BUDGETS))
    setBigCharges(bool(NOTIFY_BIG))
  }, [open])

  // Spent per category since the budget month started.
  const start = currentPeriod().start
  const spentBy: Record<string, number> = {}
  for (const t of txns) {
    const d = parse(t.data.date)
    if (t.data.amount >= 0 || !d || d < start) continue
    const c = t.data.category || 'General'
    spentBy[c] = (spentBy[c] ?? 0) - t.data.amount
  }
  const total = Object.values(spentBy).reduce((a, b) => a + b, 0)

  const save = () => {
    const changed = (key: SettingKey, value: unknown) => {
      if (JSON.stringify(store.setting(key) ?? null) !== JSON.stringify(value)) store.setSetting(key, value)
    }
    changed('monthlyBudget', num(monthly))
    changed('categoryBudgets', Object.fromEntries(Object.entries(budgets).map(([k, v]) => [k, num(v)]).filter(([, v]) => (v as number) > 0)))
    changed('merchantRules', rules)
    changed(NOTIFY_BUDGETS, budgetAlerts)
    changed(NOTIFY_BIG, bigCharges)
  }
  const close = () => { save(); onClose() }

  const budgetRow = (name: string, spent: number, value: string, set: (v: string) => void) => {
    const limit = num(value), p = limit > 0 ? Math.min(1, spent / limit) : 0
    return (
      <div key={name} className="col" style={{ gap: 6 }}>
        <div className="row" style={{ gap: 8 }}>
          <span style={{ fontSize: 14, fontWeight: 500 }}>{name}</span>
          <span className="spacer" />
          <span className="secondary" style={{ fontSize: 12 }}>{money(spent)} of</span>
          <input className="field" inputMode="decimal" placeholder="0" value={value} onChange={(e) => set(e.target.value)}
            style={{ width: 88, padding: '6px 8px', textAlign: 'right', background: 'var(--canvas)' }} />
        </div>
        {limit > 0 && (
          <div style={{ height: 6, borderRadius: 3, background: 'var(--canvas)', overflow: 'hidden' }}>
            <div style={{ width: `${p * 100}%`, height: '100%', borderRadius: 3,
              background: p >= 1 ? 'var(--critical)' : p >= 0.8 ? 'var(--orange)' : 'var(--lime)' }} />
          </div>
        )}
      </div>
    )
  }

  const toggle = (label: string, on: boolean, set: (v: boolean) => void) => (
    <label className="row" style={{ gap: 10, fontSize: 14, alignItems: 'flex-start' }}>
      <input type="checkbox" checked={on} onChange={(e) => set(e.target.checked)} style={{ marginTop: 3 }} />
      <span>{label}</span>
    </label>
  )

  return (
    <Modal open={open} onClose={close}>
      <div className="col" style={{ gap: 16 }}>
        <div className="row">
          <h2 className="display" style={{ fontSize: 26, margin: 0 }}>Budgets & rules</h2>
          <span className="spacer" />
          <button className="btn-primary" onClick={close}>Done</button>
        </div>

        <div className="card col" style={{ gap: 10, padding: 16 }}>
          <h3 className="section-title" style={{ fontSize: 19 }}>Alerts</h3>
          {toggle('Tell me when spending reaches 80% and 100% of a budget', budgetAlerts, setBudgetAlerts)}
          {toggle('Tell me about unusually large charges', bigCharges, setBigCharges)}
        </div>

        <div className="card col" style={{ gap: 12, padding: 16 }}>
          <h3 className="section-title" style={{ fontSize: 19 }}>Budgets this month</h3>
          {budgetRow('Everything', total, monthly, setMonthly)}
          {CATEGORIES.map((c) => budgetRow(c, spentBy[c] ?? 0, budgets[c] ?? '', (v) => setBudgets((b) => ({ ...b, [c]: v }))))}
          <div className="muted" style={{ fontSize: 12 }}>Leave a category at 0 for no limit.</div>
        </div>

        <div className="card col" style={{ gap: 10, padding: 16 }}>
          <h3 className="section-title" style={{ fontSize: 19 }}>Learned from you</h3>
          {!Object.keys(rules).length && (
            <div className="secondary" style={{ fontSize: 13 }}>
              Change an expense's category (long-press it › Category) and Joshu files that shop the same way from then on,
              including email, bank texts and receipts.
            </div>
          )}
          {Object.keys(rules).sort().map((m) => (
            <div key={m} className="row" style={{ gap: 8 }}>
              <span className="clamp1" style={{ fontSize: 14, fontWeight: 500, minWidth: 0 }}>{titleCase(m)}</span>
              <ArrowRight size={12} className="muted" style={{ flex: 'none' }} />
              <select className="field" value={rules[m]} onChange={(e) => setRules((r) => ({ ...r, [m]: e.target.value }))}
                style={{ width: 'auto', padding: '6px 8px', background: 'var(--canvas)' }}>
                {(CATEGORIES.includes(rules[m]) ? CATEGORIES : [rules[m], ...CATEGORIES]).map((c) => <option key={c}>{c}</option>)}
              </select>
              <span className="spacer" />
              <button className="muted" title="Forget this rule" style={{ display: 'inline-flex', padding: 6 }}
                onClick={() => setRules(({ [m]: _, ...rest }) => rest)}><XCircle size={17} /></button>
            </div>
          ))}
        </div>
      </div>
    </Modal>
  )
}
