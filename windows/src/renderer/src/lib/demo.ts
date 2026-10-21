// Sample data for previewing the app without an account (?demo in the URL). Nothing is saved or synced.
import { Rec } from './store'
import { iso, startOfDay, addDays, dayKey, startOfWeek } from './dates'

export function demoRecords(): Rec[] {
  const t = startOfDay(new Date())
  const at = (day: number, h: number, m = 0) => { const d = addDays(t, day); d.setHours(h, m); return d }
  let n = 0
  const rec = (kind: string, data: object): Rec => ({ id: `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`, kind, data, deleted: false })
  const week = startOfWeek(t)
  const off = Math.round((week.getTime() - t.getTime()) / 86_400_000)
  const out: Rec[] = []
  for (const [title, day, h, len, area] of [['Team sync', 0, 10, 60, 'work'], ['Gym', 0, 18, 90, 'health'], ['Dinner with Sara', 1, 20, 120, 'social'],
    ['Dentist', 2, 15, 45, 'health'], ['Planning session', off + 1, 9, 60, 'work'], ['Reading club', 3, 19, 60, 'study']] as const) {
    out.push(rec('event', { title, start: iso(at(day, h)), end: iso(new Date(at(day, h).getTime() + len * 60000)), area, location: '', notes: '' }))
  }
  for (const [title, area, day, pr, done] of [['Pay electricity bill', 'money', 0, 3, false], ['Book dentist appointment', 'health', 0, 2, false],
    ['Reply to landlord', 'home', -1, 2, false], ['Prepare slides for Thursday', 'work', 2, 2, false], ['Call grandma', 'social', 1, 0, false],
    ['Renew passport', 'personal', 9, 1, false], ['Weekly review', 'personal', -1, 0, true]] as const) {
    out.push(rec('task', { title, notes: '', area, due: iso(addDays(t, day)), priority: pr, isDone: done, completedAt: done ? iso(addDays(t, -1)) : null, createdAt: iso(t), repeat: 'none' }))
  }
  for (const [name, symbol, area, target, rate] of [['Workout', 'figure.run', 'health', 5, 0.7], ['Read 20 pages', 'book.fill', 'study', 7, 0.8], ['Drink 2L water', 'drop.fill', 'health', 7, 0.9]] as const) {
    const days: string[] = []
    for (let d = 1; d < 120; d++) if (d < 4 || ((d * 37 + name.length * 13) % 100) / 100 < rate) days.push(dayKey(addDays(t, -d)))
    out.push(rec('habit', { name, symbol, area, targetPerWeek: target, createdAt: iso(addDays(t, -120)), doneDays: days }))
  }
  const month = new Date(t.getFullYear(), t.getMonth(), 1)
  for (const [title, amount, cat, day, recurring, mail] of [['Salary', 4200, 'Income', 0, true, false], ['Rent', -1300, 'Bills', 0, true, false],
    ['Netflix', -15, 'Subscriptions', 2, true, true], ['Groceries', -86, 'Food', 4, false, false], ['Uber', -14, 'Transport', 5, false, true],
    ['Pharmacy', -22, 'Health', 8, false, false], ['Cinema', -18, 'Fun', 10, false, false], ['Electricity', -64, 'Bills', 12, true, true],
    ['Running shoes', -95, 'Shopping', 15, false, false], ['Dinner out', -48, 'Food', 19, false, false]] as const) {
    const d = addDays(month, day); d.setHours(12)
    if (d > new Date()) continue
    out.push(rec('transaction', { title, amount, category: cat, date: iso(d), isRecurring: recurring, source: mail ? 'gmail:you@gmail.com' : '', sourceID: mail ? 'demo' : '', originalAmount: 0, originalCurrency: '' }))
  }
  out.push(rec('task', { title: 'Pay Internet — 450 EGP', notes: '', area: 'money', due: iso(addDays(t, 4)), priority: 2, isDone: false, completedAt: null, createdAt: iso(t), repeat: 'none' }))
  out.push(rec('note', { title: 'Gift ideas', body: '- Mom: cookbook\n- Sam: running watch', createdAt: iso(addDays(t, -2)), updatedAt: iso(addDays(t, -1)), isJournal: false, pinned: true, mood: 0, moodSetByUser: false }))
  out.push(rec('note', { title: addDays(t, -1).toLocaleDateString(undefined, { dateStyle: 'full' }), body: 'Productive day. Finished the timesheet and meal prepped.', createdAt: iso(addDays(t, -1)), updatedAt: iso(addDays(t, -1)), isJournal: true, pinned: false, mood: 4, moodSetByUser: true }))
  for (const [title, author, status, rating, source, progress] of [['Meditations', 'Marcus Aurelius', 'read', 5, 'goodreads', 1], ['Atomic Habits', 'James Clear', 'reading', 0, 'kindle', 0.42],
    ['The Pragmatic Programmer', 'David Thomas', 'reading', 0, 'apple-books', 0.7], ['Sapiens', 'Yuval Noah Harari', 'toRead', 0, 'openlibrary', 0],
    ['Deep Work', 'Cal Newport', 'read', 4, 'goodreads', 1]] as const) {
    out.push(rec('book', { title, author, status, rating, categories: [], notes: '', coverURL: '', isbn: '', pageCount: 300, progress, year: 0,
      addedAt: iso(t), startedAt: null, finishedAt: status === 'read' ? iso(addDays(t, -20)) : null, source, sources: [source], externalID: '' }))
  }
  out.push(rec('bookCategory', { name: 'Philosophy', colorIndex: 3, symbol: 'brain.head.profile', createdAt: iso(t) }))
  for (const [title, kind, day, ex] of [['See the northern lights in Norway', 'travel', 23, 3], ['Concert with friends', 'people', 6, 3], ['Learn to surf', 'adventure', null, 2]] as const) {
    out.push(rec('bucket', { title, notes: '', kind, targetDate: day === null ? null : iso(addDays(t, day)), excitement: ex, isDone: false, doneAt: null, createdAt: iso(t) }))
  }
  return out
}
