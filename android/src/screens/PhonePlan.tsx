// Plan tomorrow on Android: the iPhone's PlanTomorrowSheet (PlanTomorrowView.swift + DayPlanning.swift).
// Clear what's left from today, glance at tomorrow's calendar, pick tomorrow's top 3 (or type them) and a note.
// With Joshu Pro there's a second tab, "Talk it through", where the assistant fills the same plan with tools.
import { useEffect, useMemo, useRef, useState } from 'react'
import { Check, ArrowRight, CalendarMinus, Plus, X, ArrowUp, Mic, Volume2, VolumeX } from 'lucide-react'
import { Modal } from '@/components/ui'
import { store, useRecords, Rec } from '@/lib/store'
import { Task, CalEvent, AREA_COLOR, areaOf } from '@/lib/models'
import { iso, parse, startOfDay, addDays, sameDay, fmtTime, fmtDay, relativeDay } from '@/lib/dates'
import { planFor, savePlan, tomorrowKey, PlanItem } from '@/lib/dayPlan'
import { useExternalEvents } from '@/lib/externalEvents'
import { useKeys, useAssistantName, streamTurn, Msg, Tool, Block } from '@/lib/ai'
import { completeTask } from '@/components/TaskRow'
import { Orb } from '../components/Orb'
import { isNative, native } from '../native'
import '../screens/phoneSheets.css'

const SLOT_COLORS = ['var(--lime)', 'var(--pink)', 'var(--cyan)']

interface Entry { id: string; title: string; start: Date; end: Date; allDay: boolean; tint: string }

export default function PhonePlan({ open, onClose }: { open: boolean; onClose: () => void }) {
  if (!open) return null
  return <Sheet onClose={onClose} />
}

function Sheet({ onClose }: { onClose: () => void }) {
  const tasks = useRecords<Task>('task')
  const events = useRecords<CalEvent>('event')
  const external = useExternalEvents()
  const keys = useKeys()
  const today = startOfDay(new Date()), tomorrow = addDays(today, 1)

  const existing = useMemo(() => planFor(tomorrowKey()), [])
  const [picks, setPicks] = useState<PlanItem[]>(() => existing ? existing.data.top.map((t, i) => ({ title: t, taskUUID: existing.data.taskUUIDs[i] ?? '' })) : [])
  const [note, setNote] = useState(existing?.data.note ?? '')
  const [handled, setHandled] = useState<Set<string>>(new Set())
  const [typed, setTyped] = useState('')
  const [talking, setTalking] = useState(true)

  const open = tasks.filter((t) => !t.data.isDone)
  const leftovers = open.filter((t) => { const d = parse(t.data.due); return !!d && d < tomorrow && !handled.has(t.id) })
    .sort((a, b) => (a.data.due ?? '').localeCompare(b.data.due ?? ''))
  const entries: Entry[] = [
    ...events.flatMap((e) => {
      const s = parse(e.data.start), en = parse(e.data.end)
      if (!s || !sameDay(s, tomorrow)) return []
      const allDay = !s.getHours() && !s.getMinutes() && !!en && en.getTime() - s.getTime() >= 86_400_000 - 60_000
      return [{ id: e.id, title: e.data.title, start: s, end: en ?? s, allDay, tint: AREA_COLOR[areaOf(e.data.area)] }]
    }),
    ...external.filter((e) => e.start < addDays(tomorrow, 1) && e.end > tomorrow)
      .map((e) => ({ id: e.id, title: e.title, start: e.start, end: e.end, allDay: e.allDay, tint: e.color || 'var(--cyan)' })),
  ].sort((a, b) => Number(b.allDay) - Number(a.allDay) || a.start.getTime() - b.start.getTime())
  const pickedIDs = new Set(picks.map((p) => p.taskUUID).filter(Boolean))
  const soon = (t: Rec<Task>) => { const d = parse(t.data.due); return !!d && d < addDays(tomorrow, 1) }
  const candidates = open.filter((t) => !pickedIDs.has(t.id))
    .sort((a, b) => Number(soon(b)) - Number(soon(a)) || b.data.priority - a.data.priority).slice(0, 14)

  const handle = (t: Rec<Task>, action: 'done' | 'tomorrow' | 'none') => {
    if (action === 'done') completeTask(t)
    else store.update<Task>(t.id, { due: action === 'tomorrow' ? iso(tomorrow) : null })
    setHandled((h) => new Set(h).add(t.id))
  }
  const addTyped = () => {
    const v = typed.trim()
    if (v && picks.length < 3) setPicks([...picks, { title: v, taskUUID: '' }])
    setTyped('')
  }
  const save = (p = picks, n = note) => { savePlan(tomorrowKey(), p, n.trim()); onClose() }
  const canSave = picks.length > 0 || note.trim().length > 0

  const draft: Draft = { picks, setPicks, note, setNote, handled, setHandled, leftovers, open, entries }

  return (
    <Modal open onClose={onClose} width={640}>
      <div className="ps-root">
        {keys.anthropic && (
          <div className="ps-plan-tabs">
            <button className={talking ? 'on' : ''} onClick={() => setTalking(true)}>Talk it through</button>
            <button className={!talking ? 'on' : ''} onClick={() => setTalking(false)}>Plan</button>
          </div>
        )}
        {keys.anthropic && talking ? <PlanChat draft={draft} onSave={save} onClose={onClose} /> : <>
          <div className="ps-plan-head">
            <h2>Plan tomorrow</h2>
            <div className="ps-plan-sub">{fmtDay(tomorrow, { weekday: 'long', day: 'numeric', month: 'long' })}</div>
          </div>
          <div className="ps-plan-body">
            <section className="ps-plan-sec">
              <h3>What's left from today</h3>
              {leftovers.length === 0 && <span className="secondary" style={{ fontSize: 13 }}>All clear ✨</span>}
              {leftovers.map((t) => (
                <div key={t.id} className="ps-left">
                  <div className="ps-left-title">
                    <span className="t">{t.data.title}</span>
                    {parse(t.data.due)! < today && <span className="ps-overdue">overdue</span>}
                  </div>
                  <div className="ps-flow">
                    <button className="ps-chip" onClick={() => handle(t, 'done')}><Check size={13} strokeWidth={2.6} />Done</button>
                    <button className="ps-chip" onClick={() => handle(t, 'tomorrow')}><ArrowRight size={13} strokeWidth={2.6} />Tomorrow</button>
                    <button className="ps-chip" onClick={() => handle(t, 'none')}><CalendarMinus size={13} strokeWidth={2.4} />No date</button>
                  </div>
                </div>
              ))}
            </section>

            <section className="ps-plan-sec">
              <h3>Tomorrow's calendar</h3>
              {entries.length === 0 && <span className="secondary" style={{ fontSize: 13 }}>Nothing on the calendar. A good day for deep work.</span>}
              <div className="ps-flow">
                {entries.map((e) => (
                  <span key={e.id} className="ps-cap"><span className="ps-dot" style={{ background: e.tint }} /><span>{e.allDay ? e.title : `${fmtTime(e.start)} ${e.title}`}</span></span>
                ))}
              </div>
            </section>

            <section className="ps-plan-sec">
              <h3>Your top 3 for tomorrow</h3>
              <div className="col" style={{ gap: 6 }}>
                {[0, 1, 2].map((i) => (
                  <div key={i} className="ps-slot">
                    <span className="ps-num" style={{ background: SLOT_COLORS[i] }}>{i + 1}</span>
                    {picks[i] ? <>
                      <span className="ps-slot-t">{picks[i].title}</span>
                      <button className="ps-x" aria-label="Remove" onClick={() => setPicks(picks.filter((_, j) => j !== i))}><X size={15} /></button>
                    </> : <span className="ps-slot-t ph">{i === picks.length ? 'Pick a task below or type one' : '—'}</span>}
                  </div>
                ))}
              </div>
              {picks.length < 3 && <>
                <label className="ps-typed">
                  <Plus size={18} />
                  <input placeholder="Type a priority and press Return" value={typed} enterKeyHint="done"
                    onChange={(e) => setTyped(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && addTyped()} onBlur={() => typed.trim() && addTyped()} />
                </label>
                <div className="ps-flow">
                  {candidates.map((t) => (
                    <button key={t.id} className="ps-cap" onClick={() => picks.length < 3 && setPicks([...picks, { title: t.data.title, taskUUID: t.id }])}>
                      <span className="ps-dot" style={{ background: AREA_COLOR[areaOf(t.data.area)] }} />
                      <span>{t.data.title}</span>
                      {t.data.priority > 0 && <b style={{ fontWeight: 900 }}>{'!'.repeat(t.data.priority)}</b>}
                    </button>
                  ))}
                </div>
              </>}
            </section>

            <section className="ps-plan-sec">
              <h3>Anything to remember?</h3>
              <input className="ps-field" style={{ background: 'var(--canvas)', border: '1px solid var(--line)' }} placeholder="e.g. Bring the charger, call the bank before 10"
                value={note} onChange={(e) => setNote(e.target.value)} />
            </section>
          </div>
          <div className="ps-plan-foot">
            <div className="ps-btnrow">
              <button className="ps-soft ps-wide" onClick={onClose}>Cancel</button>
              <button className="ps-primary ps-wide" disabled={!canSave} onClick={() => save()}>Save plan</button>
            </div>
            <span className="note">Your top 3 shows on Today and in tomorrow's morning brief.</span>
          </div>
        </>}
      </div>
    </Modal>
  )
}

// MARK: Talk it through (PlanChat in DayPlanning.swift)

interface Draft {
  picks: PlanItem[]; setPicks: (p: PlanItem[]) => void
  note: string; setNote: (n: string) => void
  handled: Set<string>; setHandled: (h: Set<string>) => void
  leftovers: Rec<Task>[]; open: Rec<Task>[]; entries: Entry[]
}
interface Item { role: 'user' | 'assistant' | 'action'; text: string }

const TOOLS: Tool[] = [
  { name: 'set_top3', description: 'Set tomorrow\'s top priorities (1-3, most important first). Use task_id for an existing task, or "" for something new.',
    input_schema: { type: 'object', additionalProperties: false, required: ['items'], properties: {
      items: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['title', 'task_id'], properties: { title: { type: 'string' }, task_id: { type: 'string' } } } } } } },
  { name: 'update_task', description: 'Handle a task: mark it done, move it to tomorrow, or remove its date.',
    input_schema: { type: 'object', additionalProperties: false, required: ['task_id', 'action'], properties: {
      task_id: { type: 'string' }, action: { type: 'string', enum: ['done', 'tomorrow', 'no_date'] } } } },
  { name: 'add_task', description: 'Create a new task, due tomorrow unless the user wants no date. Returns its task_id.',
    input_schema: { type: 'object', additionalProperties: false, required: ['title', 'priority', 'due'], properties: {
      title: { type: 'string' }, priority: { type: 'integer', description: '0 none … 3 high' }, due: { type: 'string', enum: ['tomorrow', 'none'] } } } },
  { name: 'set_note', description: 'Set the note for tomorrow (things to remember).',
    input_schema: { type: 'object', additionalProperties: false, required: ['note'], properties: { note: { type: 'string' } } } },
  { name: 'save_plan', description: 'Save the plan and close, when the user says they\'re done or asks to save.',
    input_schema: { type: 'object', additionalProperties: false, properties: {} } },
]

function PlanChat({ draft, onSave, onClose }: { draft: Draft; onSave: (p: PlanItem[], n: string) => void; onClose: () => void }) {
  const assistant = useAssistantName()
  const userName = (store.setting<string>('userName') ?? '').split(' ')[0] || 'the user'
  const tomorrow = addDays(startOfDay(new Date()), 1)
  const greeting = useMemo(() => {
    const l = draft.leftovers
    let t = "Let's set up tomorrow."
    t += l.length === 0 ? ' Today is all clear.'
      : ` You have ${l.length} thing${l.length === 1 ? '' : 's'} left from today: ${l.slice(0, 3).map((x) => x.data.title).join(', ')}${l.length > 3 ? '…' : ''}.`
    t += draft.entries.length === 0 ? ' Your calendar is free.' : ` You have ${draft.entries.length} event${draft.entries.length === 1 ? '' : 's'} on the calendar.`
    return t + ' What do you most want to get done?'
  }, [])
  const [items, setItems] = useState<Item[]>([{ role: 'assistant', text: greeting }])
  const [busy, setBusy] = useState(false)
  const [live, setLive] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [listening, setListening] = useState(false)
  const [speaks, setSpeaks] = useState(() => localStorage.getItem('assistant.speakReplies') === 'on')
  const messages = useRef<Msg[]>([{ role: 'user', content: '(I opened Plan tomorrow.)' }, { role: 'assistant', content: greeting }])
  const ids = useRef<Record<string, string>>({})
  // The latest plan, for tools that run between renders.
  const state = useRef({ picks: draft.picks, note: draft.note, handled: draft.handled })
  state.current = { picks: draft.picks, note: draft.note, handled: draft.handled }
  const list = useRef<HTMLDivElement>(null)
  useEffect(() => { list.current?.scrollTo({ top: list.current.scrollHeight, behavior: 'smooth' }) }, [items.length, live])
  useEffect(() => () => { if (isNative) { native.stopSpeaking().catch(() => {}); native.stopListening().catch(() => {}) } }, [])

  const prompt = (): string => {
    const today = startOfDay(new Date())
    const open = store.list<Task>('task').filter((t) => !t.data.isDone)
    const left = open.filter((t) => { const d = parse(t.data.due); return !!d && d < tomorrow && !state.current.handled.has(t.id) })
    const others = open.filter((t) => !left.includes(t))
      .sort((a, b) => (a.data.due ?? '9').localeCompare(b.data.due ?? '9') || b.data.priority - a.data.priority).slice(0, 30)
    const news = Object.fromEntries(Object.entries(ids.current).filter(([k]) => k.startsWith('N')))
    ids.current = { ...news }
    const line = (id: string, t: Rec<Task>) => {
      ids.current[id] = t.id
      const due = parse(t.data.due)
      return `- ${id}: ${t.data.title}${t.data.priority > 0 ? ` (priority ${t.data.priority})` : ''}${due ? ` due ${relativeDay(due)}` : ''}`
    }
    const p = state.current
    return `You are ${assistant}, helping ${userName} plan tomorrow (${fmtDay(tomorrow)}) in Joshu's evening planner. They may be typing or talking out loud.
Goal, in a short, friendly back-and-forth:
1. Deal with what's left from today: ask, or act on what they say (update_task done / tomorrow / no_date).
2. Understand what tomorrow needs, then set up to 3 priorities with set_top3, most important first. Use existing task ids when a priority matches a task; add_task for anything new that should be tracked.
3. Anything to remember goes in set_note.
Act as soon as what they said is clear; don't ask permission for each step. Every tool call takes effect immediately, so never repeat a call that already succeeded.
If they asked you to save, call save_plan right after the other changes, in the same turn. Keep replies to 1-3 short, spoken-style sentences, one question at a time, no lists or markdown.
Be realistic: if tomorrow is packed with events, suggest fewer or smaller priorities. When the plan looks complete, say so in a sentence and ask if they want to save; call save_plan when they agree or ask to save.

Left from today:
${left.length ? left.map((t, i) => line(`L${i + 1}`, t)).join('\n') : '(none)'}
Other open tasks:
${others.length ? others.map((t, i) => line(`T${i + 1}`, t)).join('\n') : '(none)'}
${Object.keys(news).length ? 'Tasks created in this chat:\n' + Object.entries(news).sort().map(([k, v]) => `- ${k}: ${store.get<Task>(v)?.data.title ?? ''}`).join('\n') : ''}
Tomorrow's calendar:
${draft.entries.length ? draft.entries.map((e) => `- ${e.allDay ? 'all day' : `${fmtTime(e.start)}–${fmtTime(e.end)}`} ${e.title}`).join('\n') : '(nothing)'}
Current plan: ${p.picks.length ? p.picks.map((x, i) => `${i + 1}. ${x.title}`).join('; ') : 'no priorities yet'}. Note: ${p.note || 'none'}
Now: ${new Date().toLocaleString(undefined, { weekday: 'long', hour: 'numeric', minute: '2-digit' })}. (${today.toDateString()})`
  }

  const run = (name: string, input: any): [string, string | null] => {
    const str = (k: string) => String(input?.[k] ?? '').trim()
    switch (name) {
      case 'set_top3': {
        const picks = (Array.isArray(input?.items) ? input.items : []).slice(0, 3)
          .map((i: any) => ({ title: String(i?.title ?? '').trim(), taskUUID: ids.current[String(i?.task_id ?? '').toUpperCase()] ?? '' }))
          .filter((p: PlanItem) => p.title)
        state.current.picks = picks
        draft.setPicks(picks)
        const top = picks.map((p: PlanItem) => p.title).join(' · ')
        return [`Done: the top 3 is now ${top}.`, `Top 3: ${top}`]
      }
      case 'update_task': {
        const id = ids.current[str('task_id').toUpperCase()]
        const t = id ? store.get<Task>(id) : undefined
        if (!t) return ['No task with that id.', null]
        const a = str('action')
        if (a === 'done') completeTask(t)
        else store.update<Task>(t.id, { due: a === 'tomorrow' ? iso(tomorrow) : null })
        const h = new Set(state.current.handled).add(t.id)
        state.current.handled = h
        draft.setHandled(h)
        const what = a === 'done' ? 'marked done' : a === 'tomorrow' ? 'moved to tomorrow' : 'date removed'
        return [`Done: “${t.data.title}” ${what}.`, `${t.data.title}: ${what}`]
      }
      case 'add_task': {
        const now = iso(new Date())
        const id = store.create<Task>('task', {
          title: str('title'), notes: '', area: 'personal', due: str('due') === 'none' ? null : iso(tomorrow),
          priority: Math.max(0, Math.min(3, Number(input?.priority) || 0)), isDone: false, completedAt: null, createdAt: now, repeat: 'none',
        })
        const key = `N${Object.keys(ids.current).filter((k) => k.startsWith('N')).length + 1}`
        ids.current[key] = id
        return [`Created with task_id ${key}.`, `New task: ${str('title')}`]
      }
      case 'set_note':
        state.current.note = str('note')
        draft.setNote(str('note'))
        return ['Done: note saved.', `Note: ${str('note')}`]
      case 'save_plan':
        return ['Saved.', 'Plan saved']
      default:
        return ['Unknown tool.', null]
    }
  }

  const talk = async (raw: string, voice: boolean) => {
    const text = raw.trim()
    if (!text || busy) return
    setMessage(''); setError('')
    if (isNative) native.stopSpeaking().catch(() => {})
    setItems((x) => [...x, { role: 'user', text }])
    messages.current.push({ role: 'user', content: text })
    setBusy(true)
    let lastReply = ''
    try {
      for (let step = 0; step < 6; step++) {
        const r = await streamTurn({ system: prompt(), messages: messages.current, tools: TOOLS, effort: 'low', onText: setLive })
        setLive('')
        messages.current.push({ role: 'assistant', content: r.content })
        const said = r.text.trim()
        if (said) { lastReply = said; setItems((x) => [...x, { role: 'assistant', text: said }]) }
        const calls = r.content.filter((b: Block) => b.type === 'tool_use')
        if (r.stopReason !== 'tool_use' || !calls.length) break
        const results: Block[] = []
        let saving = false
        for (const c of calls) {
          const [result, action] = run(c.name, c.input)
          if (action) setItems((x) => x.slice(-8).some((i) => i.role === 'action' && i.text === action) ? x : [...x, { role: 'action', text: action }])
          if (c.name === 'save_plan') saving = true
          results.push({ type: 'tool_result', tool_use_id: c.id, content: result })
        }
        messages.current.push({ role: 'user', content: results })
        if (saving) { onSave(state.current.picks, state.current.note); return }
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false); setLive('')
    }
    if (lastReply && (speaks || voice) && isNative) {
      await native.speak({ text: lastReply }).catch(() => {})
      if (voice) listen()
    }
  }

  const listen = async () => {
    if (!isNative) return
    if (listening) { native.stopListening().catch(() => {}); setListening(false); return }
    setListening(true)
    try {
      const r = await native.listen({})
      setListening(false)
      if (r.text?.trim()) talk(r.text, true)
    } catch { setListening(false) }
  }

  return (
    <div className="ps-chat">
      <div className="ps-chat-head">
        <Orb size={30} busy={busy} />
        <div className="col" style={{ gap: 1, flex: 1, minWidth: 0 }}>
          <h3>Talk it through</h3>
          <span className="muted" style={{ fontSize: 11 }}>Tell {assistant} about tomorrow</span>
        </div>
        <button className="ps-x" aria-label={speaks ? 'Stop reading replies aloud' : 'Read replies aloud'}
          onClick={() => { const v = !speaks; setSpeaks(v); localStorage.setItem('assistant.speakReplies', v ? 'on' : 'off'); if (!v && isNative) native.stopSpeaking().catch(() => {}) }}
          style={{ color: speaks ? 'var(--ink)' : 'var(--ink3)' }}>
          {speaks ? <Volume2 size={17} /> : <VolumeX size={17} />}
        </button>
        <button className="ps-x" aria-label="Close" onClick={onClose}><X size={17} /></button>
      </div>
      <div className="ps-chat-list" ref={list}>
        {items.map((i, n) => i.role === 'user' ? <div key={n} className="ps-bub-user">{i.text}</div>
          : i.role === 'assistant' ? <div key={n} className="ps-bub-ai">{i.text}</div>
          : <div key={n} className="ps-bub-act"><Check size={13} className="ps-good" />{i.text}</div>)}
        {busy && <div className="ps-bub-ai secondary">{live || '…'}</div>}
        {error && <div className="ps-bub-act ps-warn">{error}</div>}
        {(draft.picks.length > 0 || draft.note) && (
          <div className="col" style={{ gap: 6, marginTop: 6 }}>
            {draft.picks.map((p, i) => (
              <div key={i} className="ps-slot"><span className="ps-num" style={{ background: SLOT_COLORS[i] }}>{i + 1}</span><span className="ps-slot-t">{p.title}</span></div>
            ))}
            {draft.note && <span className="secondary" style={{ fontSize: 12 }}>Note: {draft.note}</span>}
            <button className="ps-primary ps-wide" onClick={() => onSave(draft.picks, draft.note)}>Save plan</button>
          </div>
        )}
      </div>
      <div className="ps-composer">
        {listening
          ? <span style={{ flex: 1, fontSize: 14, padding: '6px 0' }} className="muted">Listening…</span>
          : <textarea rows={1} placeholder="Tomorrow I need to…" value={message} onChange={(e) => setMessage(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); talk(message, false) } }} />}
        {isNative && <button className={`ps-round${listening ? ' listening' : ''}`} aria-label="Speak" disabled={busy} onClick={listen}><Mic size={17} /></button>}
        <button className="ps-round ink" aria-label="Send" disabled={busy || !message.trim()} onClick={() => talk(message, false)}><ArrowUp size={16} strokeWidth={2.6} /></button>
      </div>
    </div>
  )
}
