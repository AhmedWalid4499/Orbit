// Plain-text picture of your day for Claude (same content as the Mac's AIAssistant.snapshot).
import { store } from './store'
import { Task, CalEvent, Habit, Txn, Note, Book, Bucket, cap } from './models'
import { parse, startOfDay, addDays, sameDay, dayKey, startOfWeek, startOfMonth, daysInMonth, fmtTime, relativeDay } from './dates'

export function moneyFmt(v: number): string {
  const code = store.setting<string>('currencyCode') ?? 'USD'
  try { return new Intl.NumberFormat('en', { style: 'currency', currency: code, maximumFractionDigits: 2 }).format(v) } catch { return `${code} ${v.toFixed(0)}` }
}

export function daySnapshot(): string {
  const now = new Date(), today = startOfDay(now), tomorrow = addDays(today, 1)
  const tasks = store.list<Task>('task'), events = store.list<CalEvent>('event'), habits = store.list<Habit>('habit')
  const txns = store.list<Txn>('transaction'), notes = store.list<Note>('note')
  const budget = store.setting<number>('monthlyBudget') ?? 2000
  const lines: string[] = [`Now: ${now.toLocaleString('en', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: 'numeric', minute: '2-digit' })}`]

  const todays = events.filter((e) => sameDay(parse(e.data.start)!, today)).sort((a, b) => a.data.start.localeCompare(b.data.start))
  lines.push("\nToday's events:", ...(todays.length ? todays.map((e) => `- ${fmtTime(parse(e.data.start)!)}-${fmtTime(parse(e.data.end)!)} ${e.data.title} [${cap(e.data.area)}]`) : ['(none)']))

  const open = tasks.filter((t) => !t.data.isDone)
  const line = (t: (typeof open)[number]) => `- ${t.data.title} [${cap(t.data.area)}]${t.data.priority ? ` priority ${t.data.priority}/3` : ''}${t.data.due ? ` due ${relativeDay(parse(t.data.due)!)}` : ''}`
  const overdue = open.filter((t) => t.data.due && parse(t.data.due)! < today)
  const dueToday = open.filter((t) => t.data.due && sameDay(parse(t.data.due)!, today))
  const upcoming = open.filter((t) => t.data.due && parse(t.data.due)! >= tomorrow && parse(t.data.due)! < addDays(today, 7))
  lines.push('\nOverdue tasks:', ...(overdue.length ? overdue.map(line) : ['(none)']))
  lines.push('\nDue today:', ...(dueToday.length ? dueToday.map(line) : ['(none)']))
  lines.push('\nDue in the next 7 days:', ...(upcoming.length ? upcoming.slice(0, 10).map(line) : ['(none)']))
  lines.push(`\nUndated open tasks: ${open.filter((t) => !t.data.due).length}`)

  const week = startOfWeek(today)
  lines.push('\nHabits:', ...(habits.length ? habits.map((h) => {
    const thisWeek = Array.from({ length: 7 }, (_, i) => dayKey(addDays(week, i))).filter((k) => h.data.doneDays.includes(k)).length
    let streak = 0, d = h.data.doneDays.includes(dayKey(today)) ? today : addDays(today, -1)
    while (h.data.doneDays.includes(dayKey(d))) { streak++; d = addDays(d, -1) }
    return `- ${h.data.name}: streak ${streak} days, ${thisWeek}/${h.data.targetPerWeek} this week, done today: ${h.data.doneDays.includes(dayKey(today)) ? 'yes' : 'no'}`
  }) : ['(none)']))

  const spent = -txns.filter((t) => t.data.amount < 0 && parse(t.data.date)! >= startOfMonth(now)).reduce((s, t) => s + t.data.amount, 0)
  lines.push(`\nMoney this month: spent ${moneyFmt(spent)} of ${moneyFmt(budget)} budget; day ${now.getDate()} of ${daysInMonth(now)}.`)

  const yesterday = notes.find((n) => n.data.isJournal && sameDay(parse(n.data.createdAt) ?? new Date(0), addDays(today, -1)))
  if (yesterday?.data.body) lines.push(`\nYesterday's journal: ${yesterday.data.body.slice(0, 600)}`)
  return lines.join('\n')
}

/** Day snapshot plus reading and bucket list, for Ask's get_overview tool. */
export function overview(): string {
  const books = store.list<Book>('book'), bucket = store.list<Bucket>('bucket')
  const cats = store.list<{ name: string }>('bookCategory').map((c) => c.data.name)
  const reading = books.filter((b) => b.data.status === 'reading').map((b) => `${b.data.title} (${Math.round(b.data.progress * 100)}%)`)
  return daySnapshot() +
    `\n\nReading: ${reading.length ? reading.join(', ') : 'nothing in progress'}. To read: ${books.filter((b) => b.data.status === 'toRead').length}. Read: ${books.filter((b) => b.data.status === 'read').length}. ` +
    `Bucket list: ${bucket.filter((b) => !b.data.isDone).slice(0, 20).map((b) => b.data.title).join('; ')} (${bucket.filter((b) => b.data.isDone).length} done). ` +
    `Book categories: ${cats.length ? cats.join(', ') : 'none'}. Yearly goal: ${store.setting<number>('readingGoal') ?? 24} books.`
}

/** Spending picture for the last `months` months (same as the Mac's MoneyCoach.summary). */
export function moneySummary(months = 3): string {
  const txns = store.list<Txn>('transaction').map((t) => ({ ...t.data, d: parse(t.data.date)! })).sort((a, b) => a.d.getTime() - b.d.getTime())
  const tasks = store.list<Task>('task')
  const budget = store.setting<number>('monthlyBudget') ?? 2000
  const now = new Date()
  const lines = [`Currency: ${store.setting<string>('currencyCode') ?? 'USD'}. Monthly budget: ${moneyFmt(budget)}. Today: ${now.toDateString()}.`]
  for (let back = months - 1; back >= 0; back--) {
    const start = new Date(now.getFullYear(), now.getMonth() - back, 1), end = new Date(now.getFullYear(), now.getMonth() - back + 1, 1)
    const m = txns.filter((t) => t.d >= start && t.d < end)
    const spent = -m.filter((t) => t.amount < 0).reduce((s, t) => s + t.amount, 0)
    const income = m.filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0)
    lines.push(`\n${start.toLocaleDateString('en', { month: 'long', year: 'numeric' })}${back === 0 ? ` (so far, day ${now.getDate()})` : ''}: spent ${moneyFmt(spent)}, income ${moneyFmt(income)}`)
    const byCat = new Map<string, number>()
    m.filter((t) => t.amount < 0).forEach((t) => byCat.set(t.category, (byCat.get(t.category) ?? 0) - t.amount))
    ;[...byCat].sort((a, b) => b[1] - a[1]).forEach(([c, v]) => lines.push(`  ${c}: ${moneyFmt(v)}`))
    const byMerchant = new Map<string, [number, number]>()
    m.filter((t) => t.amount < 0).forEach((t) => { const x = byMerchant.get(t.title) ?? [0, 0]; byMerchant.set(t.title, [x[0] + 1, x[1] - t.amount]) })
    const top = [...byMerchant].sort((a, b) => b[1][1] - a[1][1]).slice(0, 8)
    if (top.length) lines.push(`  Top: ${top.map(([k, [n, v]]) => `${k} ${moneyFmt(v)} (${n}x)`).join(', ')}`)
  }
  const seen = new Set<string>()
  const recurring = [...txns].reverse().filter((t) => t.isRecurring && t.amount < 0 && !seen.has(t.title.toLowerCase()) && seen.add(t.title.toLowerCase()))
  if (recurring.length) lines.push(`\nRecurring / subscriptions: ${recurring.map((t) => `${t.title} ${moneyFmt(-t.amount)}`).join(', ')}`)
  const bills = tasks.filter((t) => t.data.area === 'money' && !t.data.isDone && t.data.due)
  if (bills.length) lines.push(`Bills due: ${bills.map((t) => `${t.data.title} (${relativeDay(parse(t.data.due)!)})`).join(', ')}`)
  return lines.join('\n')
}
