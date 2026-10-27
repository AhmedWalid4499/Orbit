// Today: the assistant asks you something about your day (CheckInCard.swift). On the Mac your answer opens the chat;
// here it goes into today's journal check-in (same chat as Notes › Journal), which then opens so you can keep talking.
import { useState } from 'react'
import { ArrowUp, X } from 'lucide-react'
import { store, useRecords } from '@/lib/store'
import { CalEvent, Note, Task } from '@/lib/models'
import { iso, parse, startOfDay, addDays, isToday, dayKey, fmtDay, fmtTime } from '@/lib/dates'
import { useExternalEvents, externalEvents } from '@/lib/externalEvents'
import { useKeys, useAssistantName } from '@/lib/ai'
import { decodeChat, encodeChat, systemPrompt, sendMessage, Turn } from '@/screens/journalChat'
import { Orb } from './Orb'

const ANSWERED = 'checkin.answered'
const ls = {
  get: (k: string) => { try { return localStorage.getItem(k) ?? '' } catch { return '' } },
  set: (k: string, v: string) => { try { localStorage.setItem(k, v) } catch { /* private mode */ } },
}

/** Day plus part of day: one question each morning, afternoon and evening. */
function currentSlot(): string {
  const h = new Date().getHours()
  return dayKey(new Date()) + (h < 12 ? '-am' : h < 17 ? '-pm' : '-eve')
}

const turn = (role: Turn['role'], text: string, hidden = false): Turn =>
  ({ id: crypto.randomUUID().toUpperCase(), role, text, hidden, at: Date.now() / 1000 - 978307200 })

/** Puts the question and your answer into today's journal chat and asks for the reply in the background. */
function answerInJournal(question: string, answer: string, assistant: string): void {
  const now = new Date()
  const existing = store.list<Note>('note').find((n) => n.data.isJournal && isToday(parse(n.data.createdAt) ?? new Date(0)))
  const id = existing?.id ?? store.create<Note>('note', {
    title: fmtDay(now, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }),
    body: '', createdAt: iso(now), updatedAt: iso(now), isJournal: true, pinned: false, mood: 0, moodSetByUser: false,
  })
  const chat = decodeChat(existing?.data.chat) ?? { system: systemPrompt(assistant), turns: [] }
  // Keep user/assistant turns alternating: the question is the assistant's turn.
  const last = chat.turns[chat.turns.length - 1]
  if (!last) chat.turns.push(turn('user', "I just opened today's journal.", true))
  else if (last.role === 'assistant') chat.turns.push(turn('user', "I'm back on the Today screen.", true))
  chat.turns.push(turn('assistant', question))
  store.update<Note>(id, { chat: encodeChat(chat), updatedAt: iso(now) })
  sendMessage(id, answer, assistant, () => {}).catch(() => { /* the journal offers Retry */ })
}

export default function CheckInCard({ onOpenJournal }: { onOpenJournal: () => void }) {
  const keys = useKeys()
  const name = useAssistantName()
  const events = useRecords<CalEvent>('event')
  const tasks = useRecords<Task>('task')
  useExternalEvents()
  const [answered, setAnswered] = useState(() => ls.get(ANSWERED))
  const [draft, setDraft] = useState('')
  const slot = currentSlot()
  if (!keys.anthropic || answered === slot) return null

  const q = question(events.map((e) => e.data), tasks.map((t) => t.data))
  const dismiss = () => { ls.set(ANSWERED, slot); setAnswered(slot) }
  const answer = (text: string) => {
    const t = text.trim()
    if (!t) return
    setDraft('')
    dismiss()
    answerInJournal(q.text, t, name)
    onOpenJournal()
  }

  return (
    <div className="col" style={{ gap: 10, padding: 14, borderRadius: 'var(--radius)', color: 'var(--sticker-ink)', flex: 'none',
      background: 'linear-gradient(135deg, color-mix(in srgb, var(--purple) 45%, #fff), var(--pink))' }}>
      <div className="row" style={{ gap: 10, alignItems: 'flex-start' }}>
        <Orb size={30} style={{ flex: 'none' }} />
        <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
          <span style={{ fontSize: 11, fontWeight: 600, opacity: 0.65 }}>{name} asks</span>
          <span style={{ fontSize: 15, fontWeight: 600 }}>{q.text}</span>
        </div>
        <button onClick={dismiss} title="Not now" aria-label="Not now" style={{ opacity: 0.5, padding: 6, margin: -6, color: 'inherit' }}><X size={13} strokeWidth={3} /></button>
      </div>
      <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
        {q.chips.map((c) => (
          <button key={c} onClick={() => answer(c)}
            style={{ fontSize: 12, fontWeight: 500, padding: '7px 12px', borderRadius: 999, background: 'rgba(255,255,255,0.7)', color: 'var(--sticker-ink)' }}>{c}</button>
        ))}
      </div>
      <div className="row" style={{ gap: 8, padding: '5px 5px 5px 12px', borderRadius: 999, background: 'rgba(255,255,255,0.7)' }}>
        <input className="plain" value={draft} placeholder={`Tell ${name}…`} onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') answer(draft) }} style={{ flex: 1, fontSize: 14, color: 'var(--sticker-ink)' }} />
        <button onClick={() => answer(draft)} disabled={!draft.trim()} aria-label="Send"
          style={{ width: 30, height: 30, flex: 'none', borderRadius: '50%', background: 'var(--sticker-ink)', color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', opacity: draft.trim() ? 1 : 0.4 }}>
          <ArrowUp size={14} strokeWidth={3} />
        </button>
      </div>
    </div>
  )
}

/** Same questions as the Mac: about the next or last event, how the day's going, or how it went. */
function question(events: CalEvent[], tasks: Task[]): { text: string; chips: string[] } {
  const now = new Date(), today = startOfDay(now), tomorrow = addDays(today, 1), h = now.getHours()
  const entries = [
    ...events.map((e) => ({ title: e.title, start: parse(e.start), end: parse(e.end) }))
      .filter((e): e is { title: string; start: Date; end: Date } => !!e.start && !!e.end && e.start >= today && e.start < tomorrow),
    ...externalEvents(today, tomorrow).filter((g) => !g.allDay && g.start >= today).map((g) => ({ title: g.title, start: g.start, end: g.end })),
  ].sort((a, b) => a.start.getTime() - b.start.getTime())
  const doneToday = tasks.filter((t) => t.isDone && isToday(parse(t.completedAt) ?? new Date(0))).length
  if (h < 12) {
    const next = entries.find((e) => e.start > now)
    if (next) return { text: `You've got ${next.title} at ${fmtTime(next.start)}. What's the one thing you want to get done today?`, chips: ['Ready for it', 'Bit nervous', 'Just getting through'] }
    return { text: 'Morning! What would make today a good day?', chips: ['Getting things done', 'Some rest', 'Seeing people'] }
  }
  if (h < 17) {
    const last = [...entries].reverse().find((e) => e.end < now && e.end.getTime() > now.getTime() - 5 * 3600_000)
    if (last) return { text: `How did ${last.title} go?`, chips: ['Went well 🙌', 'It was okay', 'Not great'] }
    return { text: "How's your day going so far?", chips: ['Pretty good', 'Busy', 'Dragging a bit'] }
  }
  if (doneToday >= 3) return { text: `You got ${doneToday} things done today. How are you feeling about it?`, chips: ['Proud 💪', 'Tired', "Could've done more"] }
  return { text: 'How was today, really? Anything you want to remember?', chips: ['Good day 🙂', 'Meh', 'Rough one'] }
}
