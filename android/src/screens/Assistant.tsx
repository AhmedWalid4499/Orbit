// The assistant tab (the iPhone's AssistantTabView): chat with tools that act in Joshu, past chats shared
// with the Mac and iPhone, photos and PDFs, and voice (speak, and hear the reply).
import { useEffect, useRef, useState, ReactNode } from 'react'
import { Sparkles, SquarePen, ArrowUp, Undo2, ListChecks, Calendar, Flame, Library, StickyNote, Mountain, CreditCard, Target, History, Mic, Square, Paperclip, X, Trash2, Volume2, VolumeX, Brain, Globe, Code2, Copy, Check, AudioLines } from 'lucide-react'
import { streamTurn, useKeys, useAssistantName, Block, Tool } from '@/lib/ai'
import { ASK_TOOLS, runTool, undo as undoAction, Outcome } from '@/lib/askTools'
import { store, useStoreVersion } from '@/lib/store'
import { relativeTime, parse } from '@/lib/dates'
import { Convo, Item, newConvo, listChats, openChat, saveChat, deleteChat } from '../chats'
import { native, isNative } from '../native'
import { Orb } from '../components/Orb'
import { setVoiceAsker, voiceAnswer, voiceState, startConversation } from '../voice'

const SUGGESTIONS = [
  'What should I focus on today?',
  'How can I spend less on food this month?',
  "Plan my week around what's on my calendar",
  'Recommend books like the last one I loved',
]

// MARK: Memory (Settings › AI on the Mac; synced as a JSON list in "assistant.memory")

export function memories(): string[] {
  const raw = store.setting<string>('assistant.memory')
  try { return raw ? JSON.parse(raw) : [] } catch { return [] }
}
export function setMemories(list: string[]): void {
  const clean = list.map((s) => s.trim()).filter(Boolean).slice(-60)
  store.setSetting('assistant.memory', clean.length ? JSON.stringify(clean) : null)
}

const EXTRA_TOOLS: Tool[] = [
  { name: 'remember', description: 'Remember a lasting fact or preference about the user for future chats (e.g. "vegetarian", "gym on Tuesdays"). Not for one-off details.',
    input_schema: { type: 'object', properties: { fact: { type: 'string' } }, required: ['fact'], additionalProperties: false } },
  { name: 'forget', description: 'Forget remembered facts containing this text.',
    input_schema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'], additionalProperties: false } },
]

/** Anthropic-run tools, as on the Mac: web search, reading pages and a code sandbox. */
function serverTools(): any[] {
  const city = store.setting<string>('weatherCity') || Intl.DateTimeFormat().resolvedOptions().timeZone.split('/').pop()?.replace(/_/g, ' ') || ''
  return [
    { type: 'web_search_20260209', name: 'web_search', max_uses: 6, user_location: { type: 'approximate', timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, city } },
    { type: 'web_fetch_20260209', name: 'web_fetch', max_uses: 4 },
    { type: 'code_execution_20260521', name: 'code_execution' },
  ]
}

/** What a server tool did, as a row in the chat (Assistant.swift). */
function serverActions(content: Block[]): Item[] {
  const out: Item[] = []
  for (const b of content) {
    if (b.type !== 'server_tool_use') continue
    const input = b.input ?? {}
    let text = ''
    if (b.name === 'web_search' && input.query) text = `Searched the web: “${input.query}”`
    else if (b.name === 'web_fetch' && input.url) { try { text = `Read ${new URL(input.url).host}` } catch { text = `Read ${input.url}` } }
    else if (String(b.name).includes('code_execution')) text = input.command ? `Ran: ${String(input.command).slice(0, 60)}` : input.path ? `Worked on ${input.path}` : 'Ran code'
    if (text && out[out.length - 1]?.text !== text) out.push({ id: crypto.randomUUID(), role: 'action', text, symbol: b.name === 'web_search' || b.name === 'web_fetch' ? 'web' : 'code', undone: false })
  }
  return out
}

async function run(name: string, input: Record<string, any>): Promise<Outcome> {
  if (name === 'remember') {
    const f = String(input.fact ?? '').trim()
    if (!f) return { result: 'Empty fact.', isError: true }
    const list = memories()
    if (list.some((x) => x.toLowerCase() === f.toLowerCase())) return { result: 'Already remembered.' }
    setMemories([...list, f])
    return { result: 'Remembered.', action: { text: `Remembered: ${f}`, symbol: 'memory' } }
  }
  if (name === 'forget') {
    const t = String(input.text ?? '').trim().toLowerCase()
    const gone = memories().filter((x) => x.toLowerCase().includes(t) || t.includes(x.toLowerCase()))
    setMemories(memories().filter((x) => !gone.includes(x)))
    return { result: gone.length ? `Forgot: ${gone.join('; ')}` : 'Nothing matched.', action: gone.length ? { text: `Forgot ${gone.length} thing${gone.length > 1 ? 's' : ''}`, symbol: 'memory' } : undefined }
  }
  return runTool(name, input)
}

function systemPrompt(assistant: string): string {
  const name = (store.setting<string>('userName') ?? '').split(' ')[0] || 'the user'
  const now = new Date()
  const when = now.toLocaleString('en', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: 'numeric', minute: '2-digit' })
  const mem = memories()
  return `You are ${assistant}, ${name}'s personal assistant inside Joshu (you're built on Claude, by Anthropic), their life-organizer app on Android, iPhone, Mac and Windows. You can talk things through and you can act in the app with tools: create tasks, events, habits, notes and transactions, add books to their reading list, add bucket-list dreams, set the monthly budget, look up their data, and remember things about them.

How to work:
- When ${name} wants something done, or clearly would benefit from it, just do it with the tools; no need to ask permission for creating things (each action shows an Undo button). Then say briefly what you did.
- When they're talking about a struggle, first acknowledge it, then suggest something small and realistic and set it up, unless they only want to talk.
- Book recommendations: suggest 3-5 real, well-known books with one line each on why, and add them to their To read list under a fitting category, unless they ask only for ideas. Check list_books first.
- Use get_overview or get_money_summary when you need their current data instead of guessing.
- When they tell you a lasting preference or fact about themselves, remember it.
- Dates: resolve "tomorrow", "next Friday" from the current date below. Use 24-hour times in tool inputs.
- Style: warm, calm, concise. Short paragraphs; simple bullets with "•" when listing. Never more than one question at a time. They may be talking by voice on their phone: keep spoken answers short.

Current date and time: ${when} (${Intl.DateTimeFormat().resolvedOptions().timeZone}). Currency: ${store.setting<string>('currencyCode') ?? 'EGP'}.${mem.length ? `\n\nWhat you remember about them (from earlier chats; use it naturally, don't recite it):\n${mem.map((m) => `• ${m}`).join('\n')}` : ''}`
}

const ICONS: Record<string, ReactNode> = {
  task: <ListChecks size={12} />, event: <Calendar size={12} />, habit: <Flame size={12} />, books: <Library size={12} />,
  note: <StickyNote size={12} />, web: <Globe size={12} />, code: <Code2 size={12} />, bucket: <Mountain size={12} />, money: <CreditCard size={12} />, budget: <Target size={12} />, memory: <Brain size={12} />,
}

interface Attachment { name: string; block: Block }

async function attachmentFrom(file: File): Promise<Attachment | null> {
  const data = await new Promise<string>((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result).split(',')[1] ?? ''); r.onerror = rej; r.readAsDataURL(file) })
  if (file.type === 'application/pdf') return { name: file.name, block: { type: 'document', title: file.name, source: { type: 'base64', media_type: 'application/pdf', data } } }
  if (/^image\/(jpeg|png|gif|webp)$/.test(file.type)) return { name: file.name, block: { type: 'image', source: { type: 'base64', media_type: file.type, data } } }
  if (file.type.startsWith('text/')) return { name: file.name, block: { type: 'document', title: file.name, source: { type: 'text', media_type: 'text/plain', data: (await file.text()).slice(0, 150_000) } } }
  return null
}

const SPEAK_KEY = 'assistant.speakReplies'

export default function Assistant({ seed, onSeedUsed }: { seed?: string; onSeedUsed: () => void }) {
  useStoreVersion()
  const keys = useKeys()
  const assistant = useAssistantName()
  const [convo, setConvo] = useState<Convo>(() => { const last = listChats()[0]; return (last && openChat(last.id)) || newConvo() })
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const [revealed, setRevealed] = useState('')
  const [error, setError] = useState('')
  const [history, setHistory] = useState(false)
  const [files, setFiles] = useState<Attachment[]>([])
  const [listening, setListening] = useState(false)
  const [speakAll, setSpeakAll] = useState(() => localStorage.getItem(SPEAK_KEY) === 'on')
  const convoRef = useRef(convo)
  const bottom = useRef<HTMLDivElement>(null)
  const picker = useRef<HTMLInputElement>(null)

  const update = (next: Convo) => { convoRef.current = next; setConvo(next) }

  useEffect(() => { bottom.current?.scrollIntoView({ block: 'end' }) }, [convo.items.length, revealed, busy])
  useEffect(() => {
    if (seed && keys.anthropic && !busy) { onSeedUsed(); send(seed) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seed, keys.anthropic])
  useEffect(() => () => { if (isNative && voiceState().phase === 'off') { native.stopListening().catch(() => {}); native.stopSpeaking().catch(() => {}) } }, [])
  // Questions asked by voice ("Hey Joshu") are answered here and read aloud.
  const sendRef = useRef(send)
  sendRef.current = send
  useEffect(() => { setVoiceAsker((q) => sendRef.current(q, true)); return () => setVoiceAsker(null) }, [])

  async function send(raw: string, spoken = false) {
    let text = raw.trim()
    const attached = files
    if ((!text && !attached.length) || busy) return
    if (!text) text = attached.length === 1 ? "Here's a file. What's in it, and is there anything I should do about it?" : "Here are some files. What's in them, and is there anything I should do about them?"
    setDraft(''); setFiles([]); setError('')
    let c = convoRef.current
    if (!c.system) c = { ...c, system: systemPrompt(assistant) } // frozen for the whole conversation
    const content = attached.length ? [...attached.map((a) => a.block), { type: 'text', text }] : text
    c = { ...c, items: [...c.items, { id: crypto.randomUUID(), role: 'user', text, symbol: '', undone: false, ...(attached.length ? { files: attached.map((a) => a.name) } : {}) }],
      messages: [...c.messages, { role: 'user', content }] }
    update(c)
    saveChat(c)
    setBusy(true)
    let spokenReply = ''
    try {
      for (let i = 0; i < 8; i++) {
        let received = '', shown = '', done = false
        const reveal = (async () => {
          while (!done || shown.length < received.length) {
            if (shown.length < received.length) {
              const next = received.slice(shown.length, shown.length + 3)
              shown += next
              setRevealed(shown)
              voiceAnswer(shown)
              await new Promise((r) => setTimeout(r, /[.?!\n]/.test(next) ? 140 : 18))
            } else await new Promise((r) => setTimeout(r, 40))
          }
        })()
        let turn
        try {
          turn = await streamTurn({ system: c.system, messages: c.messages, tools: [...ASK_TOOLS, ...EXTRA_TOOLS, ...serverTools()], effort: 'medium',
            container: c.container, onText: (t) => { received = t } })
        } finally {
          done = true
          await reveal
          setRevealed('')
        }
        c = { ...convoRef.current, ...(turn.container ? { container: turn.container } : {}),
          messages: [...convoRef.current.messages, { role: 'assistant', content: turn.content }] }
        c = { ...c, items: [...c.items, ...serverActions(turn.content)] }
        if (turn.text.trim()) {
          c = { ...c, items: [...c.items, { id: crypto.randomUUID(), role: 'assistant', text: turn.text.trim(), symbol: '', undone: false }] }
          spokenReply += (spokenReply ? '\n' : '') + turn.text.trim()
        }
        update(c)

        // A long web search pauses the turn; sending the conversation back as it is lets it carry on.
        if (turn.stopReason === 'pause_turn') continue
        const calls = turn.content.filter((b: Block) => b.type === 'tool_use')
        if (turn.stopReason === 'max_tokens') { setError(`${assistant}'s reply was cut off. Ask it to continue.`); break }
        if (turn.stopReason !== 'tool_use' || !calls.length) break

        const results: Block[] = []
        const actions: Item[] = []
        for (const call of calls) {
          const input = call.input && typeof call.input === 'object' ? call.input : null
          const outcome = input ? await run(call.name, input) : { result: 'INVALID_JSON: the tool input wasn’t valid JSON. Call the tool again.', isError: true }
          if (outcome.action) actions.push({ id: crypto.randomUUID(), role: 'action', text: outcome.action.text, symbol: outcome.action.symbol, undone: false, androidUndo: outcome.action.undo })
          results.push({ type: 'tool_result', tool_use_id: call.id, content: outcome.result, is_error: !!outcome.isError })
        }
        c = { ...convoRef.current, items: [...convoRef.current.items, ...actions], messages: [...convoRef.current.messages, { role: 'user', content: results }] }
        update(c)
      }
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setBusy(false)
      saveChat(convoRef.current)
    }
    if (spokenReply && (spoken || speakAll) && isNative) {
      voiceAnswer(spokenReply, true)
      await native.speak({ text: spokenReply.replace(/\*\*?|\[([^\]]+)\]\([^)]+\)/g, '$1').replace(/•/g, '') }).catch(() => {})
    }
  }

  async function listen() {
    if (!isNative) { setError('Voice works in the Android app.'); return }
    if (listening) { native.stopListening().catch(() => {}); return }
    await native.stopSpeaking().catch(() => {})
    setListening(true); setError('')
    const partial = await native.addListener('partial', (d) => setDraft(d.text))
    try {
      const { text } = await native.listen({})
      if (text.trim()) await send(text, true)
    } catch (e) {
      const m = (e as Error).message
      if (!/no match|cancel/i.test(m)) setError(m)
    } finally {
      partial.remove()
      setListening(false)
    }
  }

  function doUndo(item: Item) {
    if (!item.androidUndo || item.undone || busy) return
    undoAction(item.androidUndo)
    const c = convoRef.current
    const next: Convo = {
      ...c,
      items: c.items.map((i) => (i.id === item.id ? { ...i, undone: true } : i)),
      messages: [...c.messages, { role: 'user', content: `(I undid this: ${item.text})` }, { role: 'assistant', content: 'Got it.' }],
    }
    update(next); saveChat(next)
  }

  const fresh = () => { if (!busy) { update(newConvo()); setError(''); setHistory(false) } }

  if (history) {
    const chats = listChats()
    return (
      <div className="page col" style={{ gap: 12 }}>
        <div className="row"><h1 className="page-title">Past chats</h1><span className="spacer" />
          <button className="icon-btn" onClick={() => setHistory(false)} aria-label="Close"><X size={16} /></button></div>
        <button className="btn-primary" onClick={fresh}><SquarePen size={14} /> New chat</button>
        {chats.length === 0 && <div className="muted">Your conversations with {assistant} on every device show up here.</div>}
        {chats.map((c) => (
          <div key={c.id} className="list-row" style={{ background: c.id === convo.id ? 'var(--card)' : undefined }}>
            <button style={{ flex: 1, textAlign: 'left', minWidth: 0 }} onClick={() => { const o = openChat(c.id); if (o) { update(o); setHistory(false) } }}>
              <div className="clamp1" style={{ fontWeight: 600 }}>{c.data.title || 'Chat'}</div>
              <div className="muted" style={{ fontSize: 12 }}>{relativeTime(parse(c.data.updatedAt) ?? new Date())}</div>
            </button>
            <button className="icon-btn" style={{ width: 34, height: 34 }} aria-label="Delete chat"
              onClick={() => { if (confirm('Delete this chat on all your devices?')) { deleteChat(c.id); if (c.id === convo.id) update(newConvo()) } }}><Trash2 size={14} /></button>
          </div>
        ))}
      </div>
    )
  }

  return (
    <div className="assistant">
      <div className="row" style={{ padding: '4px 16px 10px', gap: 10 }}>
        <Orb size={34} busy={busy || listening} />
        <div className="display" style={{ fontSize: 24, flex: 1 }}>{assistant}</div>
        <button className="icon-btn" aria-label={speakAll ? 'Stop reading replies aloud' : 'Read replies aloud'}
          onClick={() => { const v = !speakAll; setSpeakAll(v); localStorage.setItem(SPEAK_KEY, v ? 'on' : 'off'); if (!v && isNative) native.stopSpeaking() }}>
          {speakAll ? <Volume2 size={16} /> : <VolumeX size={16} />}
        </button>
        <button className="icon-btn" aria-label="Talk hands-free" onClick={() => startConversation()}><AudioLines size={16} /></button>
        <button className="icon-btn" aria-label="Past chats" onClick={() => setHistory(true)}><History size={16} /></button>
        <button className="icon-btn" aria-label="New chat" disabled={busy} onClick={fresh}><SquarePen size={16} /></button>
      </div>

      {!keys.anthropic ? (
        <div className="col secondary" style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 32, textAlign: 'center', gap: 12 }}>
          <Sparkles size={28} />
          <div style={{ fontSize: 14 }}>{assistant} comes with Joshu Pro: no keys, nothing to set up. Once Pro is on your account, open Settings › Joshu Pro and tap Check my plan.</div>
        </div>
      ) : (
        <>
          <div className="scroll" style={{ flex: 1, padding: '4px 16px 16px' }}>
            <div className="col" style={{ gap: 10 }}>
              {convo.items.length === 0 && !busy && (
                <div className="col" style={{ gap: 8, marginTop: 8 }}>
                  <div className="display" style={{ fontSize: 26 }}>What's on your mind?</div>
                  <div className="secondary" style={{ fontSize: 13 }}>Ask for advice, or just say what you want: {assistant} can add habits, tasks, events, notes, expenses and books for you. Tap the mic to talk.</div>
                  {SUGGESTIONS.map((s) => (
                    <button key={s} onClick={() => send(s)} style={{ textAlign: 'left', padding: '12px 14px', borderRadius: 14, background: 'var(--card)', fontSize: 14 }}>{s}</button>
                  ))}
                </div>
              )}
              {convo.items.map((item) => <Row key={item.id} item={item} onUndo={() => doUndo(item)} />)}
              {busy && (revealed ? <AssistantText text={revealed} /> : <Thinking />)}
              {error && <div style={{ fontSize: 13, color: 'var(--orange)' }}>⚠ {error}</div>}
              <div ref={bottom} />
            </div>
          </div>
          <div style={{ padding: '8px 12px 10px' }}>
            {files.length > 0 && (
              <div className="row" style={{ flexWrap: 'wrap', gap: 6, marginBottom: 6 }}>
                {files.map((f, i) => (
                  <span key={i} className="pill" style={{ background: 'var(--card)', color: 'var(--ink)' }}>{f.name}
                    <button onClick={() => setFiles(files.filter((_, j) => j !== i))} aria-label="Remove"><X size={12} /></button></span>
                ))}
              </div>
            )}
            <div className="row" style={{ background: 'var(--card)', borderRadius: 22, padding: '6px 6px 6px 8px', alignItems: 'flex-end', gap: 6 }}>
              <button className="ask-btn" aria-label="Attach a photo or file" onClick={() => picker.current?.click()}><Paperclip size={17} /></button>
              <input ref={picker} type="file" accept="image/*,application/pdf,text/*" multiple hidden
                onChange={async (e) => { const list = await Promise.all([...(e.target.files ?? [])].map(attachmentFrom)); setFiles([...files, ...list.filter(Boolean) as Attachment[]]); e.target.value = '' }} />
              <textarea className="plain" rows={1} placeholder={listening ? 'Listening…' : `Message ${assistant}…`} value={draft}
                style={{ resize: 'none', maxHeight: 140, fontSize: 16, padding: '8px 0' }}
                onChange={(e) => { setDraft(e.target.value); e.target.style.height = 'auto'; e.target.style.height = `${e.target.scrollHeight}px` }} />
              {draft.trim() || files.length ? (
                <button className="ask-btn send" onClick={() => send(draft)} disabled={busy} aria-label="Send"><ArrowUp size={17} strokeWidth={3} /></button>
              ) : (
                <button className={`ask-btn ${listening ? 'live' : 'send'}`} onClick={listen} disabled={busy} aria-label={listening ? 'Stop' : 'Talk'}>
                  {listening ? <Square size={15} /> : <Mic size={17} />}
                </button>
              )}
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
      <div className="col" style={{ alignItems: 'flex-end', gap: 4 }}>
        {item.files?.length ? <div className="muted" style={{ fontSize: 11 }}>📎 {item.files.join(', ')}</div> : null}
        <div style={{ maxWidth: '85%', background: 'var(--inverse)', color: 'var(--on-inverse)', padding: '10px 14px', borderRadius: 18, fontSize: 15, whiteSpace: 'pre-wrap', userSelect: 'text' }}>{item.text}</div>
      </div>
    )
  }
  if (item.role === 'assistant') return <AssistantText text={item.text} />
  return (
    <div className="row" style={{ padding: 10, borderRadius: 12, border: '1px solid var(--line)', gap: 10 }}>
      <span style={{ width: 26, height: 26, borderRadius: '50%', flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        background: item.undone ? 'var(--line)' : 'var(--lime)', color: 'var(--sticker-ink)' }}>
        {item.undone ? <Undo2 size={12} /> : ICONS[item.symbol] ?? <Sparkles size={12} />}
      </span>
      <span style={{ flex: 1, fontSize: 13, fontWeight: 500, textDecoration: item.undone ? 'line-through' : undefined, color: item.undone ? 'var(--ink3)' : 'var(--ink)' }}>{item.text}</span>
      {item.androidUndo && !item.undone && <button className="link" style={{ fontWeight: 600, fontSize: 12 }} onClick={onUndo}>Undo</button>}
    </div>
  )
}

/** Assistant text with light markdown: **bold**, *italic*, [links](https://…), and ``` code blocks with a Copy button. */
function AssistantText({ text }: { text: string }) {
  const parts = text.split(/```([\w+-]*)\n?([\s\S]*?)(?:```|$)/g)
  const out: ReactNode[] = []
  for (let i = 0; i < parts.length; i += 3) {
    if (parts[i]) out.push(<span key={i}>{inline(parts[i].replace(/^\n+|\n+$/g, ''))}</span>)
    if (i + 2 < parts.length) out.push(<CodeBlock key={`c${i}`} lang={parts[i + 1]} code={parts[i + 2].replace(/\n$/, '')} />)
  }
  return <div style={{ fontSize: 15, lineHeight: 1.55, whiteSpace: 'pre-wrap', userSelect: 'text', paddingRight: 20, minWidth: 0 }}>{out}</div>
}

function CodeBlock({ lang, code }: { lang: string; code: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <div className="code-block">
      <div className="row" style={{ padding: '6px 10px', fontSize: 11, fontWeight: 600 }}>
        <span className="muted">{lang || 'code'}</span><span className="spacer" />
        <button className="row" style={{ gap: 4, fontSize: 12 }} onClick={() => { navigator.clipboard?.writeText(code); setCopied(true); setTimeout(() => setCopied(false), 1500) }}>
          {copied ? <><Check size={12} /> Copied</> : <><Copy size={12} /> Copy</>}
        </button>
      </div>
      <pre>{code}</pre>
    </div>
  )
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
