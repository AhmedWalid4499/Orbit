// Quick add, as on the iPhone (PhoneCapture + CaptureEngine + QuickParser): type or say anything and Joshu files it as a
// task, event, expense, note or journal line. With the AI (Joshu Pro or your own key) Claude sorts it, several things
// at once too; otherwise the offline parser does. "Remind me to … at 6" becomes a task with a reminder.
import { useEffect, useRef, useState } from 'react'
import { Plus, Mic, CheckCircle2 } from 'lucide-react'
import { store } from '@/lib/store'
import { useKeys, structured } from '@/lib/ai'
import { smartParse, saveCaptured } from '@/screens/Today'
import { AREAS, cap, type Area, type Task } from '@/lib/models'
import { iso, relativeDay, fmtTime, startOfDay, addDays } from '@/lib/dates'
import { useMoney } from '@/components/ui'
import { Orb } from './Orb'
import { native, isNative } from '../native'
import { scheduleReminders } from '../reminders'
import '../onboarding.css'

type Captured = Parameters<typeof saveCaptured>[0]
type Money = (v: number, signed?: boolean) => string

export default function CaptureSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const keys = useKeys()
  const money = useMoney()
  const smart = keys.anthropic
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<string | null>(null)
  const [listening, setListening] = useState(false)
  const [heard, setHeard] = useState('')
  const [micError, setMicError] = useState('')
  const field = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    if (!open) { setResult(null); setMicError(''); if (listening) native.stopListening().catch(() => {}); return }
    const t = setTimeout(() => field.current?.focus(), 250)
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => { clearTimeout(t); window.removeEventListener('keydown', onKey) }
  }, [open])

  // Grows with the text, up to five lines.
  useEffect(() => {
    const el = field.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${el.scrollHeight}px`
  }, [text, open, listening])

  if (!open) return null

  const save = async (raw0 = text) => {
    const raw = raw0.trim()
    if (!raw || busy) return
    setBusy(true)
    const summary = await capture(raw, smart, money)
    setBusy(false)
    setText('')
    setResult(summary ? `Added: ${summary}` : 'Nothing to add')
  }

  const listen = async () => {
    if (!isNative) { setMicError('Voice works in the Android app.'); return }
    if (listening) { native.stopListening().catch(() => {}); return }
    setListening(true); setHeard(''); setMicError('')
    const partial = await native.addListener('partial', (d) => setHeard(d.text))
    try {
      const { text: said } = await native.listen({})
      if (said.trim()) { setText(said); await save(said) }
    } catch (e) {
      const m = e instanceof Error ? e.message : String(e)
      if (!/no match|cancel/i.test(m)) setMicError(m)
    } finally {
      partial.remove()
      setListening(false)
    }
  }

  const preview = text.trim() && !smart ? summaryOf(parseQuick(text), money) : ''
  return (
    <div className="backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div className="modal po-sheet po-capture" role="dialog" aria-label="Quick add">
        <span className="po-sheet-grip" />
        <div className="po-capture-head">
          <h2>Quick add</h2>
          <button onClick={onClose}>Done</button>
        </div>
        <div className="po-capture-box">
          {listening
            ? <span className="heard" style={{ color: heard ? 'var(--ink)' : 'var(--ink3)' }}>{heard || 'Listening…'}</span>
            : <textarea ref={field} rows={1} value={text} enterKeyHint="done"
                placeholder="“Dentist Thursday at 3”, “$12 lunch”, “call mom tomorrow !!”"
                onChange={(e) => setText(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); save() } }} />}
          <button className={`po-mic ${listening ? 'on' : ''}`} aria-label={listening ? 'Stop listening' : 'Speak'} onClick={listen}><Mic size={17} /></button>
        </div>
        {preview && <span className="secondary" style={{ fontSize: 13, marginTop: -4 }}>{preview}</span>}
        <button className="btn-primary" disabled={busy || !text.trim()} onClick={() => save()}>
          {smart ? <Orb size={18} busy={busy} /> : <Plus size={16} strokeWidth={2.6} />}
          {busy ? 'Saving…' : 'Add'}
        </button>
        {result && <span className="po-result"><CheckCircle2 size={16} style={{ flex: 'none' }} />{result}</span>}
        {micError && <span style={{ fontSize: 12, color: 'var(--orange)' }}>{micError}</span>}
        <p className="po-hint">One line can hold several things: “gym tomorrow 7am and pay rent friday”. Reminders work too: “remind me to call mom at 6pm”.</p>
      </div>
    </div>
  )
}

// MARK: Capture engine (CaptureEngine.swift)

/** Saves free text as one or more items; returns a short summary of what was saved. */
export async function capture(raw: string, smart: boolean, money: Money): Promise<string> {
  const reminder = await captureReminder(raw, smart)
  if (reminder) return reminder
  let items: Captured[] = [parseQuick(raw)]
  let note = ''
  if (smart) {
    try {
      const out = await smartParse(raw)
      if (out.length) items = out
    } catch {
      note = ' (offline parser)'
    }
  }
  const valid = items.filter((i) => i.title.trim() || i.amount > 0)
  valid.forEach((i) => saveCaptured(i))
  return valid.map((i) => summaryOf(i, money)).join('  |  ') + note
}

interface ReminderParse { is_reminder: boolean; title: string; due_date: string; remind_at: string; remind_place: string }

/** "remind me to call mom at 6pm / tomorrow morning": a task with a reminder. Null when the text isn't a reminder. */
async function captureReminder(raw: string, smart: boolean): Promise<string | null> {
  const lower = raw.toLowerCase()
  if (!(lower.includes('remind') || lower.includes('ذكرني'))) return null
  let title = '', due: Date | null = null, at: Date | null = null, place = ''
  if (smart) {
    const now = new Date()
    const system = `The user typed a quick note into their task app. Decide whether it asks for a reminder and pull out its parts.
Now: ${localStamp(now)} (${Intl.DateTimeFormat().resolvedOptions().timeZone}).
- is_reminder: true if they want to be reminded of something (at a time or a place).
- title: the thing to do, short, starting with a verb ("Call mom", "Buy batteries"), without the reminder words.
- remind_at: local time yyyy-MM-ddTHH:mm if a time is given ("at 6", "in 2 hours", "tomorrow morning" = 09:00), else "".
- remind_place: "home", "work", or the place or shop name if a place is given, else "".
- due_date: yyyy-MM-dd of the day it's for if stated or implied by remind_at, else "".`
    const schema = {
      type: 'object', additionalProperties: false, required: ['is_reminder', 'title', 'due_date', 'remind_at', 'remind_place'],
      properties: { is_reminder: { type: 'boolean' }, title: { type: 'string' }, due_date: { type: 'string' }, remind_at: { type: 'string' }, remind_place: { type: 'string' } },
    }
    try {
      const r = await structured<ReminderParse>(system, raw, schema, 'low', 1500)
      if (!r.is_reminder || !r.title.trim()) return null
      title = r.title.trim(); at = localDate(r.remind_at); place = r.remind_place
      due = localDate(r.due_date) ?? (at ? startOfDay(at) : null)
    } catch { /* offline: below */ }
  }
  if (!title) {
    // Offline: a time of day ("at 6pm") or nothing; the parser finds the day.
    const p = parseQuick(raw.replace(/^\s*remind me (to )?/i, ''))
    if (!p.title || !p.date || !p.has_time) return null
    title = cap(p.title); at = localDate(p.date); due = at && startOfDay(at)
  }
  store.create<Task & { remindAt: string | null }>('task', {
    title, notes: '', area: 'personal', due: due ? iso(due) : null, priority: 0, isDone: false, completedAt: null,
    createdAt: iso(new Date()), repeat: 'none', remindAt: at ? iso(at) : null,
  })
  scheduleReminders()
  const what = `Task “${title}”${at ? ` · reminder ${relativeDay(at)} ${fmtTime(at)}` : due ? ` · due ${relativeDay(due)}` : ''}`
  // Place reminders need the iPhone's location; here it's a plain task.
  return place && !at ? `${what} — no place reminder on Android` : what
}

// MARK: Offline parser (QuickParser.swift)

const MONEY_RE = /(^|\s)([+-]?)([$€£¥]|EGP|AED|SAR)?\s?(\d+(?:[.,]\d{1,2})?)\s?([$€£¥])?(?=\s|$)/i
const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']

/** "dentist thu 3pm #health", "$12 lunch", "note: …" → one item, in the same shape the AI returns. */
export function parseQuick(raw: string, now = new Date()): Captured {
  let text = raw.trim()
  const item: Captured = { kind: 'task', title: text, area: '' as Area, date: '', has_time: false, duration_minutes: 0, amount: 0, category: 'General', priority: 0 }

  for (const [prefix, kind] of [['note:', 'note'], ['journal:', 'journal']] as const) {
    if (text.toLowerCase().startsWith(prefix)) return { ...item, kind, title: text.slice(prefix.length).trim() }
  }

  const tag = text.match(/#(\w+)/)
  if (tag) {
    const area = AREAS.find((a) => a.startsWith(tag[1].toLowerCase()))
    if (area) { item.area = area; text = text.replace(tag[0], '') }
  }

  const bang = text.match(/(^|\s)(!{1,3})(?=\s|$)/)
  if (bang) { item.priority = bang[2].length; text = text.replace(bang[0], ' ') }

  const m = text.match(MONEY_RE)
  if (m && (m[3] || m[5] || m[2] === '+')) {
    const value = Number(m[4].replace(',', '.'))
    const income = m[2] === '+'
    text = text.replace(m[0], ' ')
    item.kind = income ? 'income' : 'expense'
    item.amount = value
    item.title = clean(text)
    item.category = income ? 'Income' : guessCategory(item.title)
    if (!item.area) item.area = 'money'
    return item
  }

  const found = findDate(text, now)
  if (found) {
    item.has_time = found.hasTime
    item.date = localStamp(found.hasTime ? found.date : startOfDay(found.date))
    text = found.rest.replace(/\s(on|at|by)\s*$/i, '')
    if (found.hasTime) { item.kind = 'event'; item.duration_minutes = 60 }
  }
  item.title = clean(text)
  return item
}

/** Days ("today", "tomorrow", "next week", weekday names, "3 Nov", "11/3") and times ("3pm", "15:30", "at 3", "noon"). */
function findDate(text: string, now: Date): { date: Date; hasTime: boolean; rest: string } | null {
  let rest = text
  let day: Date | null = null
  const today = startOfDay(now)
  const take = (re: RegExp, f: (m: RegExpMatchArray) => Date | null) => {
    if (day) return
    const m = rest.match(re)
    if (!m) return
    const d = f(m)
    if (d) { day = d; rest = rest.replace(m[0], ' ') }
  }
  take(/\b(today|tonight)\b/i, () => today)
  take(/\btomorrow\b|\btmrw?\b/i, () => addDays(today, 1))
  take(/\bnext week\b/i, () => addDays(today, 7))
  take(/\b(?:(next)\s+)?(sun|mon|tue|wed|thu|fri|sat)[a-z]*\b/i, (m) => {
    const target = DAYS.indexOf(m[2].toLowerCase())
    const ahead = ((target - today.getDay() + 7) % 7) || 7
    return addDays(today, ahead + (m[1] && ahead < 7 ? 7 : 0))
  })
  const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec']
  const ahead = (d: Date) => (d < today ? new Date(d.getFullYear() + 1, d.getMonth(), d.getDate()) : d)
  take(/\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b/i,
    (m) => ahead(new Date(today.getFullYear(), months.indexOf(m[2].toLowerCase()), +m[1])))
  take(/\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{1,2})(?:st|nd|rd|th)?\b/i,
    (m) => ahead(new Date(today.getFullYear(), months.indexOf(m[1].toLowerCase()), +m[2])))

  let hours: number | null = null, minutes = 0
  const t = rest.match(/(?:\bat\s+)?\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b/i) ?? rest.match(/(?:\bat\s+)?\b(\d{1,2}):(\d{2})\b/) ?? rest.match(/\bat\s+(\d{1,2})\b(?!\s*[$€£%])/i)
  if (t) {
    hours = +t[1]; minutes = t[2] ? +t[2] : 0
    const ap = t[3]?.toLowerCase()
    if (ap === 'pm' && hours < 12) hours += 12
    if (ap === 'am' && hours === 12) hours = 0
    // "at 3" with no am/pm: afternoon for 1-7, like people mean it.
    if (!ap && !t[2] && hours >= 1 && hours <= 7) hours += 12
    if (hours > 23 || minutes > 59) hours = null
    else rest = rest.replace(t[0], ' ')
  } else {
    const w = rest.match(/\b(?:at\s+)?(noon|midnight)\b/i)
    if (w) { hours = w[1].toLowerCase() === 'noon' ? 12 : 0; rest = rest.replace(w[0], ' ') }
  }
  if (!day && hours == null) return null
  const base: Date = day ?? today
  if (hours == null) return { date: base, hasTime: false, rest }
  let date = new Date(base.getFullYear(), base.getMonth(), base.getDate(), hours, minutes)
  if (!day && date < now) date = addDays(date, 1) // "at 9am" when it's already past: tomorrow
  return { date, hasTime: true, rest }
}

const clean = (s: string) => s.replace(/\s+/g, ' ').trim().replace(/^[\s.,;:!?-]+|[\s.,;:!?-]+$/g, '')

function guessCategory(title: string): string {
  const t = title.toLowerCase()
  const map: [string, string[]][] = [
    ['Income', ['salary', 'payroll']],
    ['Food', ['lunch', 'dinner', 'breakfast', 'coffee', 'grocer', 'food', 'restaurant', 'snack', 'carrefour', 'seoudi', 'spinneys', 'talabat', 'supermarket',
      'hypermarket', 'bakery', 'starbucks', 'mcdonald', 'kfc', 'elmenus', 'breadfast', 'rabbit']],
    ['Transport', ['uber', 'taxi', 'fuel', 'gas', 'metro', 'bus', 'train', 'careem', 'parking', 'indrive', 'swvl', 'petrol', 'wataniya']],
    ['Bills', ['rent', 'electric', 'water', 'internet', 'phone', 'bill', 'vodafone', 'etisalat', 'orange', 'telecom egypt', 'fawry']],
    ['Subscriptions', ['netflix', 'spotify', 'icloud', 'subscription', 'youtube', 'claude', 'gym membership']],
    ['Health', ['pharmacy', 'doctor', 'dentist', 'gym', 'medicine']],
    ['Fun', ['cinema', 'movie', 'game', 'concert', 'bar']],
    ['Shopping', ['amazon', 'clothes', 'shoes', 'shop']],
  ]
  return map.find(([, words]) => words.some((w) => t.includes(w)))?.[0] ?? 'General'
}

/** "Event · Thursday 3:00 PM · Health · !!", like QuickParser.Result.summary. */
export function summaryOf(i: Captured, money: Money): string {
  const parts = [{ task: 'Task', event: 'Event', expense: 'Expense', income: 'Income', note: 'Note', journal: 'Journal' }[i.kind] ?? 'Task']
  if (i.amount > 0 && (i.kind === 'expense' || i.kind === 'income')) parts.push(money(i.kind === 'income' ? i.amount : -i.amount))
  const d = localDate(i.date)
  if (d) parts.push(i.has_time ? `${relativeDay(d)} ${fmtTime(d)}` : relativeDay(d))
  if (i.area) parts.push(cap(i.area))
  if (i.priority > 0) parts.push('!'.repeat(Math.min(3, i.priority)))
  return parts.join(' · ')
}

function localStamp(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
}

function localDate(s: string): Date | null {
  const m = s?.match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?/)
  return m ? new Date(+m[1], +m[2] - 1, +m[3], +(m[4] ?? 0), +(m[5] ?? 0)) : null
}
