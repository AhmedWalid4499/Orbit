// Slide-over chat with Ask (Claude) that can create things in Orbit, like the Mac's AssistantPanel.
import { useEffect, useRef, useState, ReactNode } from 'react'
import { Sparkles, X, SquarePen, ArrowUp, Undo2, ListChecks, Calendar, Flame, Library, StickyNote, Mountain, CreditCard, Target } from 'lucide-react'
import { streamTurn, useKeys, useAssistantName, Msg, Block } from '@/lib/ai'
import { ASK_TOOLS, runTool, undo as undoAction, Undo } from '@/lib/askTools'
import { getSession } from '@/lib/cloud'
import { store } from '@/lib/store'

interface Item { id: string; role: 'user' | 'assistant' | 'action'; text: string; symbol?: string; undo?: Undo; undone?: boolean }
interface Saved { system: string; messages: Msg[]; items: Item[] }

const SUGGESTIONS = [
  "I can't seem to read every day. Can you help?",
  'Recommend books about Japanese culture',
  "Plan my week around what's on my calendar",
  'How can I spend less on food this month?',
]

const storageKey = (): string => `orbit.ask.${getSession()?.userID ?? 'demo'}`

function load(): Saved {
  try {
    const s: Saved = JSON.parse(localStorage.getItem(storageKey()) ?? 'null')
    if (!s) return { system: '', messages: [], items: [] }
    // A conversation saved mid tool-call can't be continued: start fresh rather than send a broken history.
    const last = s.messages[s.messages.length - 1]
    if (last?.role === 'assistant' && Array.isArray(last.content) && last.content.some((b) => b.type === 'tool_use')) {
      return { system: '', messages: [], items: [] }
    }
    return s
  } catch { return { system: '', messages: [], items: [] } }
}

function systemPrompt(assistant: string): string {
  const name = (store.setting<string>('userName') ?? '').split(' ')[0] || 'the user'
  const now = new Date()
  const when = now.toLocaleString('en', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: 'numeric', minute: '2-digit' })
  return `You are ${assistant}, ${name}'s personal assistant inside Orbit (you're built on Claude, by Anthropic), their life-organizer app on Windows and Mac. You can talk things through and you can act in the app with tools: create tasks, events, habits, notes and transactions, add books to their reading list, set the monthly budget, and look up their data.

How to work:
- When ${name} wants something done, or clearly would benefit from it, just do it with the tools; no need to ask permission for creating things (each action shows an Undo button). Then say briefly what you did.
- When they're talking about a struggle ("I can't read every day"), first acknowledge it, then suggest something small and realistic and set it up (e.g. a habit with a modest weekly target, maybe a reminder task), unless they only want to talk.
- Book recommendations: suggest 3-5 real, well-known books with one line each on why, and add them to their To read list under a category that fits the topic (e.g. "Japanese culture"), unless they ask only for ideas. Check list_books first so you don't recommend books they already have.
- Bucket list: when they mention something they dream of doing someday (travel, experiences, skills), offer to add it, or add it if they ask.
- Use get_overview or get_money_summary when you need their current data instead of guessing.
- Dates: resolve "tomorrow", "next Friday" from the current date below. Use 24-hour times in tool inputs.
- Style: warm, calm, concise. Short paragraphs; simple bullets with "•" when listing. Never more than one question at a time.

Current date and time: ${when} (${Intl.DateTimeFormat().resolvedOptions().timeZone}). Currency: ${store.setting<string>('currencyCode') ?? 'USD'}.`
}

const ICONS: Record<string, ReactNode> = {
  task: <ListChecks size={12} />, event: <Calendar size={12} />, habit: <Flame size={12} />, books: <Library size={12} />,
  note: <StickyNote size={12} />, bucket: <Mountain size={12} />, money: <CreditCard size={12} />, budget: <Target size={12} />,
}

export default function AskPanel({ seed, onSeedUsed, onClose }: { seed?: string; onSeedUsed: () => void; onClose: () => void }) {
  const keys = useKeys()
  const assistant = useAssistantName()
  const [convo, setConvo] = useState<Saved>(load)
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const [revealed, setRevealed] = useState('')
  const [error, setError] = useState('')
  const convoRef = useRef(convo)
  const bottom = useRef<HTMLDivElement>(null)
  const input = useRef<HTMLTextAreaElement>(null)

  const update = (next: Saved) => {
    convoRef.current = next
    setConvo(next)
    try { localStorage.setItem(storageKey(), JSON.stringify(next)) } catch { /* storage full: keep in memory */ }
  }

  useEffect(() => { input.current?.focus() }, [])
  useEffect(() => { bottom.current?.scrollIntoView({ block: 'end' }) }, [convo.items.length, revealed, busy])
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  useEffect(() => {
    if (seed && keys.anthropic && !busy) { onSeedUsed(); send(seed) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seed, keys.anthropic])

  async function send(raw: string) {
    const text = raw.trim()
    if (!text || busy) return
    setDraft('')
    setError('')
    let c = convoRef.current
    if (!c.system) c = { ...c, system: systemPrompt(assistant) } // frozen for the whole conversation
    c = { ...c, items: [...c.items, { id: crypto.randomUUID(), role: 'user', text }], messages: [...c.messages, { role: 'user', content: text }] }
    update(c)
    setBusy(true)
    try {
      for (let i = 0; i < 8; i++) {
        // Reveal streamed text at a calm pace rather than all at once.
        let received = '', shown = '', done = false
        const reveal = (async () => {
          while (!done || shown.length < received.length) {
            if (shown.length < received.length) {
              const next = received.slice(shown.length, shown.length + 3)
              shown += next
              setRevealed(shown)
              await new Promise((r) => setTimeout(r, /[.?!\n]/.test(next) ? 160 : 22))
            } else await new Promise((r) => setTimeout(r, 40))
          }
        })()
        let turn
        try {
          turn = await streamTurn({ system: c.system, messages: c.messages, tools: ASK_TOOLS, effort: 'medium', onText: (t) => { received = t } })
        } finally {
          done = true
          await reveal
          setRevealed('')
        }
        c = { ...convoRef.current, messages: [...convoRef.current.messages, { role: 'assistant', content: turn.content }] }
        if (turn.text.trim()) c = { ...c, items: [...c.items, { id: crypto.randomUUID(), role: 'assistant', text: turn.text.trim() }] }
        update(c)

        const calls = turn.content.filter((b: Block) => b.type === 'tool_use')
        if (turn.stopReason === 'max_tokens') { setError(`${assistant}'s reply was cut off. Ask it to continue.`); break }
        if (turn.stopReason !== 'tool_use' || !calls.length) break

        const results: Block[] = []
        const actions: Item[] = []
        for (const call of calls) {
          const input = call.input && typeof call.input === 'object' ? call.input : null
          const outcome = input ? await runTool(call.name, input) : { result: 'INVALID_JSON: the tool input wasn’t valid JSON. Call the tool again.', isError: true }
          if (outcome.action) actions.push({ id: crypto.randomUUID(), role: 'action', ...outcome.action })
          results.push({ type: 'tool_result', tool_use_id: call.id, content: outcome.result, is_error: !!outcome.isError })
        }
        c = { ...convoRef.current, items: [...convoRef.current.items, ...actions], messages: [...convoRef.current.messages, { role: 'user', content: results }] }
        update(c)
      }
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setBusy(false)
      input.current?.focus()
    }
  }

  function doUndo(item: Item) {
    if (!item.undo || item.undone || busy) return
    undoAction(item.undo)
    const c = convoRef.current
    update({
      ...c,
      items: c.items.map((i) => (i.id === item.id ? { ...i, undone: true } : i)),
      // Let Ask know, so it doesn't assume the thing still exists.
      messages: [...c.messages, { role: 'user', content: `(I undid this: ${item.text})` }, { role: 'assistant', content: 'Got it.' }],
    })
  }

  return (
    <div style={{ position: 'absolute', top: 0, right: 0, bottom: 0, width: 440, background: 'var(--canvas)', borderLeft: '1px solid var(--line)',
      boxShadow: '-8px 0 24px rgba(0,0,0,0.12)', display: 'flex', flexDirection: 'column', zIndex: 40 }}>
      <div className="row" style={{ padding: 16, gap: 10, borderBottom: '1px solid var(--line)' }}>
        <span style={{ width: 32, height: 32, borderRadius: '50%', background: 'var(--lime)', color: 'var(--sticker-ink)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
          <Sparkles size={15} />
        </span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="display" style={{ fontSize: 20 }}>{assistant}</div>
          <div className="muted" style={{ fontSize: 11 }}>Talks things through and sets things up for you</div>
        </div>
        <button className="icon-btn" style={{ width: 32, height: 32 }} title="New chat" disabled={busy} onClick={() => { update({ system: '', messages: [], items: [] }); setError('') }}><SquarePen size={14} /></button>
        <button className="icon-btn" style={{ width: 32, height: 32 }} title="Close (Esc)" onClick={onClose}><X size={14} /></button>
      </div>

      {!keys.anthropic ? (
        <div className="col secondary" style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 32, textAlign: 'center', gap: 12 }}>
          <Sparkles size={28} />
          <div style={{ fontSize: 13 }}>To chat with {assistant}, add your Anthropic API key in Settings › AI, or unlock the keys synced from your Mac with your sync passphrase.</div>
        </div>
      ) : (
        <>
          <div className="scroll" style={{ flex: 1, padding: 16 }}>
            <div className="col" style={{ gap: 10 }}>
              {convo.items.length === 0 && !busy && (
                <div className="col" style={{ gap: 8, marginTop: 8 }}>
                  <div className="display" style={{ fontSize: 22 }}>What's on your mind?</div>
                  <div className="secondary" style={{ fontSize: 12 }}>Ask for advice, or just say what you want: {assistant} can add habits, tasks, events, notes, expenses and books for you.</div>
                  {SUGGESTIONS.map((s) => (
                    <button key={s} onClick={() => send(s)} style={{ textAlign: 'left', padding: '9px 12px', borderRadius: 12, background: 'var(--card)', fontSize: 13 }}>{s}</button>
                  ))}
                </div>
              )}
              {convo.items.map((item) => <Row key={item.id} item={item} onUndo={() => doUndo(item)} />)}
              {busy && (revealed ? <AssistantText text={revealed} /> : <Thinking />)}
              {error && <div style={{ fontSize: 12, color: 'var(--orange)' }}>⚠ {error}</div>}
              <div ref={bottom} />
            </div>
          </div>
          <div style={{ padding: 14 }}>
            <div className="row" style={{ background: 'var(--card)', borderRadius: 16, padding: 10, alignItems: 'flex-end' }}>
              <textarea ref={input} className="plain" rows={1} placeholder={`Message ${assistant}…`} value={draft}
                style={{ resize: 'none', maxHeight: 120, fontSize: 14 }}
                onChange={(e) => { setDraft(e.target.value); e.target.style.height = 'auto'; e.target.style.height = `${e.target.scrollHeight}px` }}
                onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(draft) } }} />
              <button onClick={() => send(draft)} disabled={busy || !draft.trim()} title="Send"
                style={{ width: 30, height: 30, borderRadius: '50%', background: 'var(--inverse)', color: 'var(--on-inverse)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
                <ArrowUp size={14} strokeWidth={3} />
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  )
}

function Row({ item, onUndo }: { item: Item; onUndo: () => void }) {
  if (item.role === 'user') {
    return (
      <div className="row" style={{ justifyContent: 'flex-end' }}>
        <div style={{ maxWidth: '85%', background: 'var(--inverse)', color: 'var(--on-inverse)', padding: '10px 14px', borderRadius: 18, fontSize: 14, whiteSpace: 'pre-wrap', userSelect: 'text' }}>{item.text}</div>
      </div>
    )
  }
  if (item.role === 'assistant') return <AssistantText text={item.text} />
  return (
    <div className="row" style={{ padding: 10, borderRadius: 12, border: '1px solid var(--line)', gap: 10 }}>
      <span style={{ width: 26, height: 26, borderRadius: '50%', flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        background: item.undone ? 'var(--line)' : 'var(--lime)', color: 'var(--sticker-ink)' }}>
        {item.undone ? <Undo2 size={12} /> : ICONS[item.symbol ?? ''] ?? <Sparkles size={12} />}
      </span>
      <span style={{ flex: 1, fontSize: 12, fontWeight: 500, textDecoration: item.undone ? 'line-through' : undefined, color: item.undone ? 'var(--ink3)' : 'var(--ink)' }}>{item.text}</span>
      {item.undo && !item.undone && <button className="link" style={{ fontWeight: 600, fontSize: 11 }} onClick={onUndo}>Undo</button>}
    </div>
  )
}

/** Assistant text with light markdown: **bold**, *italic*, [links](https://…). */
function AssistantText({ text }: { text: string }) {
  return <div style={{ fontSize: 14, lineHeight: 1.55, whiteSpace: 'pre-wrap', userSelect: 'text', paddingRight: 30 }}>{inline(text)}</div>
}

function inline(text: string): ReactNode[] {
  const out: ReactNode[] = []
  const re = /\*\*([^*]+)\*\*|\*([^*\n]+)\*|\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g
  let last = 0, m: RegExpExecArray | null, k = 0
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(text.slice(last, m.index))
    if (m[1]) out.push(<strong key={k++}>{m[1]}</strong>)
    else if (m[2]) out.push(<em key={k++}>{m[2]}</em>)
    else {
      const url = m[4]
      out.push(<a key={k++} href="#" onClick={(e) => { e.preventDefault(); window.orbit.openExternal(url) }}>{m[3]}</a>)
    }
    last = re.lastIndex
  }
  if (last < text.length) out.push(text.slice(last))
  return out
}

function Thinking() {
  return (
    <div className="row" style={{ gap: 5, padding: '8px 0' }}>
      {[0, 1, 2].map((i) => (
        <span key={i} style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--ink3)', animation: `ask-dot 1.2s ${i * 0.2}s infinite ease-in-out` }} />
      ))}
      <style>{'@keyframes ask-dot { 0%, 100% { opacity: 0.3 } 50% { opacity: 1 } }'}</style>
    </div>
  )
}
