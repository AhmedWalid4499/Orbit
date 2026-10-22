// Subscriptions: recurring charges (the Mac's `subscription` records, found in transactions/email or added by hand).
import { useState } from 'react'
import { Plus, Repeat, TrendingUp, Hourglass, Trash2 } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Subscription, BILLING_CYCLES, BillingCycle, monthlyCost, priceWentUp, MONEY_CATEGORIES, cap } from '@/lib/models'
import { iso, parse, startOfDay, daysBetween, relativeDay, fmtDay } from '@/lib/dates'
import { Card, EmptyHint, Modal, Segmented, DateInput, FormRow, useMoney } from '@/components/ui'

const whenText = (d: Date) => { const r = relativeDay(d); return r === 'Today' || r === 'Tomorrow' ? r.toLowerCase() : `on ${r}` }
const STATUS_COLOR: Record<string, string> = { active: 'var(--mint)', trial: 'var(--orange)', cancelled: 'var(--card-hover)' }

export default function SubscriptionsView() {
  const subs = useRecords<Subscription>('subscription')
  const money = useMoney()
  const [editing, setEditing] = useState<string | null>(null)
  const today = startOfDay(new Date())

  const live = subs.filter((s) => s.data.status !== 'cancelled')
  const monthly = subs.reduce((n, s) => n + monthlyCost(s.data), 0)
  const trials = subs.filter((s) => s.data.status === 'trial' && s.data.trialEnds && parse(s.data.trialEnds)! >= today)
    .sort((a, b) => a.data.trialEnds!.localeCompare(b.data.trialEnds!))
  const increases = subs.filter((s) => s.data.status !== 'cancelled' && priceWentUp(s.data))
  const sorted = subs.slice().sort((a, b) =>
    (a.data.status === 'cancelled' ? 1 : 0) - (b.data.status === 'cancelled' ? 1 : 0) || monthlyCost(b.data) - monthlyCost(a.data))

  const add = () => {
    const nextDate = new Date(today); nextDate.setMonth(nextDate.getMonth() + 1); nextDate.setHours(12)
    setEditing(store.create<Subscription>('subscription', {
      name: '', amount: 0, originalAmount: 0, originalCurrency: '', cycle: 'monthly', nextDate: iso(nextDate), lastCharged: null,
      category: 'Subscriptions', status: 'active', trialEnds: null, previousAmount: 0, priceChangedAt: null, source: 'manual', notes: '', createdAt: iso(new Date()),
    }))
  }
  const editingRec = editing ? subs.find((s) => s.id === editing) : undefined

  return (
    <div className="col" style={{ gap: 20 }}>
      <div className="row" style={{ gap: 20, alignItems: 'stretch' }}>
        <div className="money-balance" style={{ background: 'linear-gradient(135deg, var(--purple), var(--pink))' }}>
          <div className="row"><span style={{ fontWeight: 600 }}>Per month</span><span className="spacer" /><span className="badge"><Repeat size={15} /></span></div>
          <div className="value">{money(monthly)}</div>
          <div style={{ fontSize: 12, fontWeight: 500, opacity: 0.75 }}>{live.length} active subscription{live.length === 1 ? '' : 's'}</div>
        </div>
        <div className="money-balance" style={{ background: 'linear-gradient(135deg, var(--cyan), var(--mint))' }}>
          <div className="row"><span style={{ fontWeight: 600 }}>Per year</span><span className="spacer" /></div>
          <div className="value">{money(monthly * 12)}</div>
          <div style={{ fontSize: 12, fontWeight: 500, opacity: 0.75 }}>at today's prices</div>
        </div>
        <div className="money-balance" style={{ background: 'linear-gradient(135deg, var(--orange), var(--peach))' }}>
          <div className="row"><span style={{ fontWeight: 600 }}>Heads-up</span><span className="spacer" /><span className="badge"><Hourglass size={15} /></span></div>
          <div className="value">{trials.length + increases.length}</div>
          <div style={{ fontSize: 12, fontWeight: 500, opacity: 0.75 }}>{trials.length} trial{trials.length === 1 ? '' : 's'} ending · {increases.length} price rise{increases.length === 1 ? '' : 's'}</div>
        </div>
      </div>

      {(trials.length > 0 || increases.length > 0) && (
        <div className="row" style={{ gap: 20, alignItems: 'flex-start' }}>
          {trials.length > 0 && (
            <Card className="col" style={{ flex: 1, minWidth: 0 }}>
              <h3 className="section-title">Trials ending</h3>
              {trials.map((s) => {
                const n = daysBetween(today, parse(s.data.trialEnds)!)
                return (
                  <button key={s.id} className="list-row" onClick={() => setEditing(s.id)}>
                    <span className="days-badge" style={{ background: n <= 3 ? 'var(--critical)' : 'var(--orange)', color: n <= 3 ? '#fff' : undefined }}>{n}<small>{n === 1 ? 'day' : 'days'}</small></span>
                    <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
                      <strong className="clamp1">{s.data.name || 'Untitled'}</strong>
                      <span className="secondary" style={{ fontSize: 12 }}>Starts charging {money(s.data.amount)} {whenText(parse(s.data.trialEnds)!)}. Cancel before then if you don't want it.</span>
                    </div>
                  </button>
                )
              })}
            </Card>
          )}
          {increases.length > 0 && (
            <Card className="col" style={{ flex: 1, minWidth: 0 }}>
              <h3 className="section-title">Price went up</h3>
              {increases.map((s) => (
                <button key={s.id} className="list-row" onClick={() => setEditing(s.id)}>
                  <span className="tile-icon" style={{ background: 'var(--peach)', color: 'var(--sticker-ink)' }}><TrendingUp size={14} /></span>
                  <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
                    <strong className="clamp1">{s.data.name}</strong>
                    <span className="secondary" style={{ fontSize: 12 }}>
                      {money(s.data.previousAmount)} → {money(s.data.amount)} (+{Math.round((s.data.amount / s.data.previousAmount - 1) * 100)}%)
                      {s.data.priceChangedAt && ` since ${fmtDay(parse(s.data.priceChangedAt)!, { day: 'numeric', month: 'short' })}`}
                    </span>
                  </div>
                </button>
              ))}
            </Card>
          )}
        </div>
      )}

      <Card className="col">
        <div className="row">
          <h3 className="section-title">All subscriptions</h3>
          <span className="spacer" />
          <button className="btn-soft" style={{ background: 'var(--canvas)' }} onClick={add}><Plus size={14} />Add subscription</button>
        </div>
        {subs.length === 0 && <EmptyHint text="No subscriptions yet. Orbit on the Mac finds them in your transactions and email, or add one here." />}
        {sorted.map((s) => <SubRow key={s.id} s={s} onClick={() => setEditing(s.id)} />)}
      </Card>
      {editingRec && <SubscriptionEditor rec={editingRec} onClose={() => setEditing(null)} />}
    </div>
  )
}

function SubRow({ s, onClick }: { s: Rec<Subscription>; onClick: () => void }) {
  const money = useMoney()
  const d = s.data
  const next = parse(d.nextDate)
  return (
    <button className="list-row" onClick={onClick} style={{ opacity: d.status === 'cancelled' ? 0.55 : 1 }}>
      <span className="tile-icon" style={{ background: STATUS_COLOR[d.status] ?? 'var(--mint)', color: 'var(--sticker-ink)', width: 34, height: 34 }}><Repeat size={14} /></span>
      <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
        <strong className="clamp1">{d.name || 'Untitled'}</strong>
        <span className="muted" style={{ fontSize: 11 }}>
          {[cap(d.cycle), d.category, d.status !== 'active' ? cap(d.status) : '', next && d.status !== 'cancelled' ? `next ${relativeDay(next)}` : '',
            d.originalCurrency && d.originalAmount ? `${d.originalAmount} ${d.originalCurrency}` : ''].filter(Boolean).join(' · ')}
        </span>
      </div>
      {priceWentUp(d) && <span className="pill compact" style={{ background: 'var(--peach)' }}>Price up</span>}
      <div className="col" style={{ gap: 0, alignItems: 'flex-end' }}>
        <strong>{money(d.amount)}</strong>
        {d.cycle !== 'monthly' && d.status !== 'cancelled' && <span className="muted" style={{ fontSize: 11 }}>{money(monthlyCost(d))}/mo</span>}
      </div>
    </button>
  )
}

function SubscriptionEditor({ rec, onClose }: { rec: Rec<Subscription>; onClose: () => void }) {
  const d = rec.data
  const set = (p: Partial<Subscription>) => store.update<Subscription>(rec.id, p)
  const close = () => { if (!d.name.trim() && !d.amount) store.remove(rec.id); onClose() }
  return (
    <Modal open onClose={close} width={500}>
      <div className="col" style={{ gap: 14 }}>
        <input className="plain display" style={{ fontSize: 24 }} autoFocus={!d.name} placeholder="Name (e.g. Netflix)" value={d.name} onChange={(e) => set({ name: e.target.value })} />
        <Segmented options={[{ id: 'active', label: 'Active' }, { id: 'trial', label: 'Free trial' }, { id: 'cancelled', label: 'Cancelled' }]} value={d.status}
          onChange={(v) => set({ status: v as Subscription['status'] })} />
        <FormRow label="Amount">
          <input type="number" className="field" style={{ width: 130 }} min={0} step="0.01" value={d.amount || ''}
            onChange={(e) => set({ amount: Math.max(0, Number(e.target.value) || 0) })} />
          <select className="field" style={{ width: 130 }} value={d.cycle} onChange={(e) => set({ cycle: e.target.value as BillingCycle })}>
            {BILLING_CYCLES.map((c) => <option key={c} value={c}>{cap(c)}</option>)}
          </select>
        </FormRow>
        <FormRow label="Next charge"><DateInput value={d.nextDate} onChange={(v) => set({ nextDate: v })} /></FormRow>
        {d.status === 'trial' && <FormRow label="Trial ends"><DateInput value={d.trialEnds} onChange={(v) => set({ trialEnds: v })} /></FormRow>}
        <FormRow label="Category">
          <select className="field" style={{ width: 200 }} value={d.category} onChange={(e) => set({ category: e.target.value })}>
            {[...new Set([...MONEY_CATEGORIES.filter((c) => c !== 'Income'), d.category])].map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </FormRow>
        <textarea className="field" rows={3} placeholder="Notes" value={d.notes} onChange={(e) => set({ notes: e.target.value })} />
        <div className="row">
          <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(rec.id); onClose() }}><Trash2 size={13} />Delete</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 110 }} onClick={close}>Done</button>
        </div>
      </div>
    </Modal>
  )
}
