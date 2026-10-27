// Top of Money on Android, like PhoneMoney.swift on iPhone: the budget month with ‹ › switching and what's left of it,
// "Budgets" (MoneyRulesSheet) and "New month" (start the budget month today, e.g. on payday), then the week in money.
// Pass `period`/`onShift` to drive the screen below from the same month; otherwise it keeps its own.
import { useState } from 'react'
import { ChevronLeft, ChevronRight, SlidersHorizontal, RotateCcw } from 'lucide-react'
import { useRecords, useSetting } from '@/lib/store'
import { Txn } from '@/lib/models'
import { Modal, useMoney } from '@/components/ui'
import { Period, useBudgetPeriod, periodTitle, spent, dayOf, currentPeriod, samePeriod, startNewMonth, backToCalendarMonths, newMonthMessage } from '../lib/budgetPeriod'
import MoneyRulesSheet from './MoneyRules'
import WeeklyMoneyCard from './WeeklyMoney'

export default function MoneyBar({ period: shown, onShift }: { period?: Period; onShift?: (n: number) => void } = {}) {
  const own = useBudgetPeriod()
  const period = shown ?? own.period
  const shift = onShift ?? own.shift
  const txns = useRecords<Txn>('transaction')
  const budget = Number(useSetting<number>('monthlyBudget', 2000)) || 0
  const money = useMoney()
  const [rules, setRules] = useState(false)
  const [confirm, setConfirm] = useState(false)

  const out = spent(txns, period)
  const isNow = samePeriod(period, currentPeriod())
  const { day, of } = dayOf(period)
  const since = period.start.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })

  return (
    <div className="col" style={{ gap: 12 }}>
      <div className="row" style={{ gap: 8 }}>
        <button className="icon-btn" style={{ width: 36, height: 36 }} onClick={() => shift(-1)} title="Previous month"><ChevronLeft size={17} /></button>
        <div className="col" style={{ gap: 2, flex: 1, minWidth: 0, alignItems: 'center' }}>
          <div className="display clamp1" style={{ fontSize: 21 }}>{periodTitle(period, own.custom)}</div>
          <div className="secondary clamp1" style={{ fontSize: 12 }}>
            {budget > 0 ? `${money(budget - out)} left of ${money(budget)}` : `${money(out)} spent`}
            {own.custom ? ` · since ${since}` : ''}{isNow ? ` · day ${day} of ${of}` : ''}
          </div>
        </div>
        <button className="icon-btn" style={{ width: 36, height: 36 }} onClick={() => shift(1)} title="Next month"><ChevronRight size={17} /></button>
      </div>

      <div className="row" style={{ gap: 8 }}>
        <button className="btn-soft" style={{ minHeight: 38 }} onClick={() => setRules(true)}><SlidersHorizontal size={14} />Budgets</button>
        <button className="btn-soft" style={{ minHeight: 38 }} onClick={() => setConfirm(true)}><RotateCcw size={14} />New month</button>
      </div>

      <WeeklyMoneyCard />

      <MoneyRulesSheet open={rules} onClose={() => setRules(false)} />
      <Modal open={confirm} onClose={() => setConfirm(false)}>
        <div className="col" style={{ gap: 14 }}>
          <h2 className="display" style={{ fontSize: 24, margin: 0 }}>Start a new budget month today?</h2>
          <div className="secondary" style={{ fontSize: 13 }}>{newMonthMessage()}</div>
          <button className="btn-primary" style={{ minHeight: 44 }} onClick={() => { startNewMonth(); setConfirm(false) }}>Start new month</button>
          {own.custom && (
            <button className="btn-soft" style={{ minHeight: 44, justifyContent: 'center' }}
              onClick={() => { backToCalendarMonths(); setConfirm(false) }}>Go back to calendar months</button>
          )}
          <button className="btn-soft" style={{ minHeight: 44, justifyContent: 'center' }} onClick={() => setConfirm(false)}>Cancel</button>
        </div>
      </Modal>
    </div>
  )
}
