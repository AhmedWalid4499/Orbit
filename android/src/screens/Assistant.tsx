// The assistant tab (the iPhone's AssistantTabView → AssistantPanel): header with the orb and the voice buttons,
// the chat with action cards (Undo), saved places on a little map, code blocks with Copy, files and photos, the mic,
// and past chats shared with the Mac and iPhone. The conversation itself lives in assistantSession.ts.
import { useEffect, useRef, useState, ReactNode, CSSProperties } from 'react'
import {
  Sparkles, SquarePen, ArrowUp, Undo2, ListChecks, Calendar, Flame, Library, BookOpen, FileText, Repeat, Mountain, CreditCard, Target,
  Lightbulb, Brain, Flag, Users, MapPin, Globe, FileSearch, Code2, Compass, History, Mic, Square, Paperclip, X, Trash2, Volume2, VolumeX,
  AudioLines, Ear, Copy, Check, AlertTriangle, Image as ImageIcon, UtensilsCrossed, Banknote, CloudSun, Heart, Coffee, Wine, ShoppingBag,
  Landmark, Leaf, Star, BedDouble, Navigation, CheckCircle2,
} from 'lucide-react'
import { useKeys, useAssistantName } from '@/lib/ai'
import { store, useSetting } from '@/lib/store'
import { relativeTime } from '@/lib/dates'
import type { Item } from '../chats'
import { Orb } from '../components/Orb'
import ProSheet from '../components/ProSheet'
import { placeTitle } from '../assistantTools'
import {
  useSession, send, undoItem, newChat, openChatByID, deleteChatByID, pastChats, Attachment, DEMO_AI,
} from '../assistantSession'
import {
  onVoice, voiceState, startConversation, wakeEnabled, setWakeEnabled, dictate, stopDictation, stopSpeaking, whenDoneSpeaking,
} from '../voice'
import './Assistant.css'

// Kept for Settings › AI, which edits what the assistant remembers.
export { memories, setMemories } from '../assistantMemory'

const SUGGESTIONS: { text: string; icon: ReactNode; tint: string }[] = [
  { text: "I'm hungry, what's good near me?", icon: <UtensilsCrossed size={13} strokeWidth={2.6} />, tint: 'var(--peach)' },
  { text: 'Plan my week around my calendar', icon: <Calendar size={13} strokeWidth={2.6} />, tint: 'var(--cyan)' },
  { text: 'How can I spend less on food this month?', icon: <Banknote size={13} strokeWidth={2.6} />, tint: 'var(--mint)' },
  { text: 'Recommend books about Japanese culture', icon: <Library size={13} strokeWidth={2.6} />, tint: 'var(--pa-lavender)' },
  { text: 'What should I wear today?', icon: <CloudSun size={13} strokeWidth={2.6} />, tint: 'var(--pa-sand)' },
  { text: "I can't seem to read every day. Help?", icon: <Heart size={13} strokeWidth={2.6} fill="currentColor" />, tint: 'var(--pink)' },
]

// MARK: Action cards (ActionTint and the SF Symbols the Mac saves)

/** Older Android chats saved their own short names; the Mac's SF Symbol names are used now. */
const LEGACY: Record<string, string> = { task: 'checklist', event: 'calendar', habit: 'flame.fill', books: 'books.vertical.fill', note: 'doc.text',
  bucket: 'mountain.2.fill', money: 'creditcard', budget: 'target', memory: 'brain', web: 'globe', code: 'chevron.left.forwardslash.chevron.right' }

function tint(symbolIn: string): string {
  const s = LEGACY[symbolIn] ?? symbolIn
  if (s.includes('mappin') || s.includes('location')) return 'var(--mint)'
  if (s.includes('creditcard') || s.includes('banknote') || s.includes('target') || s.includes('doc.text')) return 'var(--peach)'
  if (s.includes('calendar') || s.includes('clock')) return 'var(--cyan)'
  if (s.includes('book')) return 'var(--pa-lavender)'
  if (s.includes('brain') || s.includes('heart')) return 'var(--pink)'
  if (s.includes('flag') || s.includes('star')) return 'var(--pa-sand)'
  if (s.includes('person')) return 'var(--mint)'
  return 'var(--lime)'
}

function icon(symbolIn: string, size = 13): ReactNode {
  const s = LEGACY[symbolIn] ?? symbolIn
  const p = { size, strokeWidth: 2.6 }
  if (s === 'globe') return <Globe {...p} />
  if (s.startsWith('doc.text.magnifying')) return <FileSearch {...p} />
  if (s.startsWith('chevron.left.forwardslash')) return <Code2 {...p} />
  if (s === 'checklist') return <ListChecks {...p} />
  if (s === 'calendar') return <Calendar {...p} />
  if (s.startsWith('flame')) return <Flame {...p} />
  if (s.startsWith('books')) return <Library {...p} />
  if (s.startsWith('book')) return <BookOpen {...p} />
  if (s.startsWith('doc')) return <FileText {...p} />
  if (s === 'repeat') return <Repeat {...p} />
  if (s.startsWith('mountain')) return <Mountain {...p} />
  if (s.startsWith('creditcard')) return <CreditCard {...p} />
  if (s === 'target') return <Target {...p} />
  if (s.startsWith('lightbulb')) return <Lightbulb {...p} />
  if (s === 'brain') return <Brain {...p} />
  if (s.startsWith('flag')) return <Flag {...p} />
  if (s.startsWith('person')) return <Users {...p} />
  if (s.startsWith('mappin')) return <MapPin {...p} />
  if (s === 'safari') return <Compass {...p} />
  return <Sparkles {...p} />
}

const PLACE: Record<string, { tint: string; icon: (n: number) => ReactNode }> = {
  food: { tint: 'var(--orange)', icon: (n) => <UtensilsCrossed size={n} strokeWidth={2.6} /> },
  cafe: { tint: 'var(--peach)', icon: (n) => <Coffee size={n} strokeWidth={2.6} /> },
  bar: { tint: 'var(--purple)', icon: (n) => <Wine size={n} strokeWidth={2.6} /> },
  shop: { tint: 'var(--pink)', icon: (n) => <ShoppingBag size={n} strokeWidth={2.6} /> },
  museum: { tint: 'var(--cyan)', icon: (n) => <Landmark size={n} strokeWidth={2.6} /> },
  park: { tint: 'var(--lime)', icon: (n) => <Leaf size={n} strokeWidth={2.6} /> },
  attraction: { tint: 'var(--mint)', icon: (n) => <Star size={n} strokeWidth={2.6} /> },
  hotel: { tint: 'var(--pa-lavender)', icon: (n) => <BedDouble size={n} strokeWidth={2.6} /> },
  other: { tint: 'var(--pa-sand)', icon: (n) => <MapPin size={n} strokeWidth={2.6} /> },
}
const tintVar = (t: string): CSSProperties => ({ ['--pa-tint' as string]: t })

// MARK: Files (ChatAttachment in AssistantInput.swift)

const TEXT_EXT = /\.(txt|md|markdown|csv|tsv|json|xml|yaml|yml|html?|rtf|log|ini|toml|sql|swift|kt|kts|java|js|jsx|ts|tsx|py|rb|go|rs|c|h|cc|cpp|hpp|cs|php|sh|css|scss|dart|r|m|lua|pl|ex|exs|vue|svelte)$/i

const base64 = (file: Blob): Promise<string> => new Promise((res, rej) => {
  const r = new FileReader(); r.onload = () => res(String(r.result).split(',')[1] ?? ''); r.onerror = () => rej(r.error); r.readAsDataURL(file)
})

/** Big photos are shrunk to a JPEG Claude reads well (and HEIC and friends converted). */
async function photo(file: File): Promise<{ data: string; type: string }> {
  if (file.size < 1_500_000 && /^image\/(jpeg|png|gif|webp)$/.test(file.type)) return { data: await base64(file), type: file.type }
  const url = URL.createObjectURL(file)
  try {
    const img = await new Promise<HTMLImageElement>((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error(`Couldn't open ${file.name}.`)); i.src = url })
    const scale = Math.min(1, 1568 / Math.max(img.naturalWidth, img.naturalHeight))
    const c = document.createElement('canvas')
    c.width = Math.round(img.naturalWidth * scale); c.height = Math.round(img.naturalHeight * scale)
    c.getContext('2d')!.drawImage(img, 0, 0, c.width, c.height)
    return { data: c.toDataURL('image/jpeg', 0.85).split(',')[1] ?? '', type: 'image/jpeg' }
  } finally { URL.revokeObjectURL(url) }
}

async function attachmentFrom(file: File): Promise<Attachment> {
  if (file.type === 'application/pdf' || /\.pdf$/i.test(file.name)) {
    if (file.size > 30_000_000) throw new Error(`${file.name} is too big (over 30 MB).`)
    return { name: file.name, kind: 'pdf', block: { type: 'document', title: file.name, source: { type: 'base64', media_type: 'application/pdf', data: await base64(file) } } }
  }
  if (file.type.startsWith('image/')) {
    const p = await photo(file)
    return { name: file.name, kind: 'image', block: { type: 'image', source: { type: 'base64', media_type: p.type, data: p.data } } }
  }
  if (file.type.startsWith('text/') || /json|xml|javascript|csv|yaml/.test(file.type) || TEXT_EXT.test(file.name)) {
    const text = await file.text()
    return { name: file.name, kind: 'text', block: { type: 'document', title: file.name, source: { type: 'text', media_type: 'text/plain', data: text.slice(0, 400_000) } } }
  }
  if (/\.(docx?|xlsx?|pptx?|pages|numbers|key)$/i.test(file.name)) throw new Error(`Save ${file.name} as a PDF (or a CSV for spreadsheets) and send that.`)
  throw new Error(`${file.name} isn't a file ${'Joshu'} can read. Send a PDF, photo or text file.`)
}

// MARK: Screen

export default function Assistant({ seed, onSeedUsed }: { seed?: string; onSeedUsed: () => void }) {
  const session = useSession()
  const keys = useKeys()
  const name = useAssistantName()
  const userName = useSetting<string>('userName', '')
  const speaks = useSetting<boolean>('assistantSpeaks', false) === true
  const [voice, setVoice] = useState(voiceState())
  const [draft, setDraft] = useState('')
  const [files, setFiles] = useState<Attachment[]>([])
  const [fileError, setFileError] = useState('')
  const [menu, setMenu] = useState(false)
  const [proOpen, setProOpen] = useState(false)
  const [focused, setFocused] = useState(false)
  const picker = useRef<HTMLInputElement>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const box = useRef<HTMLTextAreaElement>(null)
  /** The last message was spoken, so the conversation carries on by voice while the chat is on screen. */
  const voiceTurn = useRef(false)
  const mounted = useRef(true)
  const ready = keys.anthropic || DEMO_AI
  const { convo, busy, revealed, error } = session

  useEffect(() => onVoice(setVoice), [])
  useEffect(() => () => { mounted.current = false; voiceTurn.current = false; if (voiceState().dictating) stopDictation() }, [])
  useEffect(() => { const el = scroller.current; if (el) el.scrollTop = el.scrollHeight }, [convo.items.length, revealed, busy, convo.id])
  useEffect(() => {
    if (seed && ready && !busy) { onSeedUsed(); submit(seed) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seed, ready])
  // When you were talking, listen again once the reply has been read out.
  useEffect(() => {
    if (busy || !voiceTurn.current) return
    if (error) { voiceTurn.current = false; return }
    whenDoneSpeaking().then(() => { if (mounted.current && voiceTurn.current && !voiceState().inConversation) mic() })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [busy])

  const firstName = userName.split(' ')[0] ?? ''
  const h = new Date().getHours()
  const part = h < 5 ? 'Up late' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'
  const greeting = firstName ? `${part}, ${firstName}!` : `${part}!`

  function submit(text: string, spoken = false) {
    const t = text.trim()
    if ((!t && !files.length) || busy) return
    if (!spoken) voiceTurn.current = false
    const attached = files
    setDraft(''); setFiles([]); setFileError('')
    if (box.current) box.current.style.height = 'auto'
    box.current?.blur()
    stopSpeaking()
    send(t, attached, { spoken })
  }

  async function mic() {
    if (voice.dictating) { stopDictation(); return }
    setFileError('')
    try {
      const heard = await dictate()
      if (!heard) { voiceTurn.current = false; return }
      voiceTurn.current = true
      submit(heard, true)
    } catch (e) { voiceTurn.current = false; setFileError((e as Error).message) }
  }

  async function addFiles(list: File[]) {
    setFileError('')
    const out: Attachment[] = []
    for (const f of list.slice(0, 5)) {
      try { out.push(await attachmentFrom(f)) } catch (e) { setFileError((e as Error).message) }
    }
    setFiles((cur) => [...cur, ...out])
  }

  const status = busy ? 'Thinking…' : voice.speaking ? 'Speaking…' : voice.inConversation ? 'Listening…' : voice.wakeListening ? `Say “Hey ${name}”` : 'Here for anything'
  const toggleSpeaks = () => {
    const on = !speaks
    store.setSetting('assistantSpeaks', on)
    if (!on) { stopSpeaking(); voiceTurn.current = false }
  }
  const wakeOn = wakeEnabled()

  return (
    <div className="pa-root">
      <header className="pa-header">
        <Orb size={36} busy={busy || voice.speaking} />
        <div className="pa-title">
          <div className="display">{name}</div>
          <div className="pa-status"><i className={busy ? 'busy' : ''} />{status}</div>
        </div>
        <div className="pa-tools">
          <button className={speaks ? '' : 'off'} aria-label={speaks ? 'Reading replies aloud. Tap to turn off.' : 'Read replies aloud'} onClick={toggleSpeaks}>
            {speaks ? <Volume2 size={19} strokeWidth={2.2} /> : <VolumeX size={19} strokeWidth={2.2} />}
          </button>
          <button aria-label="Talk hands-free" onClick={() => startConversation()}><AudioLines size={19} strokeWidth={2.2} /></button>
          <button className={wakeOn ? '' : 'off'} aria-label={wakeOn ? `Listening for “Hey ${name}”. Tap to stop.` : `Answer hands-free when you say “Hey ${name}”`}
            onClick={() => setWakeEnabled(!wakeOn)}><Ear size={19} strokeWidth={wakeOn ? 2.6 : 2.2} fill={wakeOn ? 'currentColor' : 'none'} fillOpacity={0.15} /></button>
          <button aria-label="Past chats" disabled={busy} onClick={() => setMenu(!menu)}><History size={19} strokeWidth={2.2} /></button>
          <button aria-label="New chat" disabled={busy} onClick={() => { newChat(); setMenu(false) }}><SquarePen size={18} strokeWidth={2.2} /></button>
        </div>
        {menu && <PastChats currentID={convo.id} onClose={() => setMenu(false)} />}
      </header>

      {!ready ? (
        <div className="pa-gate">
          <Orb size={56} />
          <h2>{name} comes with Joshu Pro</h2>
          <p>Ask anything, plan your week, write and code with {name}, by voice or text.</p>
          <button className="pa-primary" onClick={() => setProOpen(true)}>See Joshu Pro</button>
        </div>
      ) : <>
        <div className="pa-scroll" ref={scroller} onPointerDown={() => { if (menu) setMenu(false) }}>
          {convo.items.length === 0 && !busy && (
            <div className="pa-empty">
              <Orb size={56} />
              <div>
                <h2>{greeting}</h2>
                <p>What's on your mind? Ask me anything, or tell me what to set up: tasks, plans, places, money, books.</p>
              </div>
              <div className="pa-grid">
                {SUGGESTIONS.map((s) => (
                  <button key={s.text} className="pa-tile" style={tintVar(s.tint)} onClick={() => submit(s.text)}>
                    <span className="ic">{s.icon}</span>{s.text}
                  </button>
                ))}
              </div>
            </div>
          )}
          {convo.items.map((item) => <Row key={item.id} item={item} onUndo={() => undoItem(item)} />)}
          {busy && (
            <div className="pa-bot">
              <Orb size={22} busy />
              <div className="bubble">{revealed ? <AssistantText text={revealed} /> : <Thinking />}</div>
            </div>
          )}
          {error && !voice.inConversation && <div className="pa-error"><AlertTriangle size={14} style={{ flex: 'none', marginTop: 1 }} />{error}</div>}
        </div>

        <div className={`pa-composer ${focused ? 'focused' : ''}`}>
          {files.length > 0 && (
            <div className="pa-chips">
              {files.map((f, i) => (
                <span key={i}>{f.kind === 'image' ? <ImageIcon size={12} /> : <FileText size={12} />}<em>{f.name}</em>
                  <button aria-label={`Remove ${f.name}`} onClick={() => setFiles(files.filter((_, j) => j !== i))}><X size={12} /></button></span>
              ))}
            </div>
          )}
          {(fileError) && <div className="pa-hint">{fileError}</div>}
          <div className="pa-row">
            <button className="pa-clip" aria-label="Send a PDF, photo or document" onClick={() => picker.current?.click()}><Paperclip size={17} strokeWidth={2.3} /></button>
            <input ref={picker} type="file" multiple hidden accept="image/*,application/pdf,text/*,.csv,.json,.md,.xml,.yaml,.yml,.html,.js,.ts,.tsx,.py,.swift,.kt,.java,.c,.cpp,.go,.rs,.rb,.php,.sh,.sql,.css,.docx,.xlsx"
              onChange={(e) => { addFiles([...(e.target.files ?? [])]); e.target.value = '' }} />
            {voice.dictating
              ? <div className={`pa-heard ${voice.heard ? '' : 'empty'}`}>{voice.heard || 'Listening…'}</div>
              : <textarea ref={box} rows={1} value={draft} enterKeyHint="send"
                  placeholder={files.length ? `Ask about ${files.length === 1 ? 'this file' : 'these files'}…` : `Message ${name}…`}
                  onFocus={() => { setFocused(true); setMenu(false) }} onBlur={() => setFocused(false)}
                  onChange={(e) => { setDraft(e.target.value); e.target.style.height = 'auto'; e.target.style.height = `${Math.min(140, e.target.scrollHeight)}px` }} />}
            <button className={`pa-mic ${voice.dictating ? 'live' : ''}`} disabled={busy} aria-label={voice.dictating ? 'Stop listening' : 'Talk instead of typing'}
              style={voice.dictating ? { transform: `scale(${1 + voice.level * 0.25})` } : undefined} onClick={mic}>
              {voice.dictating ? <Square size={12} fill="currentColor" /> : <Mic size={15} strokeWidth={2.6} />}
            </button>
            <button className="pa-send" aria-label="Send" disabled={busy || (!draft.trim() && !files.length)} onClick={() => submit(draft)}>
              <ArrowUp size={16} strokeWidth={3} />
            </button>
          </div>
        </div>
      </>}
      <ProSheet open={proOpen} onClose={() => setProOpen(false)} />
    </div>
  )
}

function PastChats({ currentID, onClose }: { currentID: string; onClose: () => void }) {
  const [, tick] = useState(0)
  const chats = pastChats().slice(0, 25)
  return (
    <div className="pa-menu" role="menu">
      <div className="pa-menu-head">Past chats</div>
      {chats.length === 0 && <div className="pa-menu-empty">No past chats yet. Your conversations on every device show up here.</div>}
      {chats.map((c) => (
        <div key={c.id} className={`pa-menu-row ${c.id === currentID ? 'on' : ''}`}>
          <button onClick={() => { openChatByID(c.id); onClose() }}>
            <span style={{ width: 16, flex: 'none', paddingTop: 2 }}>{c.id === currentID && <Check size={15} strokeWidth={2.6} />}</span>
            <span style={{ minWidth: 0 }}><div className="t">{c.title}</div><div className="d">{relativeTime(c.updated)}</div></span>
          </button>
          <button className="del" aria-label="Delete chat" onClick={() => { if (confirm('Delete this chat on all your devices?')) { deleteChatByID(c.id); tick((n) => n + 1) } }}>
            <Trash2 size={15} />
          </button>
        </div>
      ))}
    </div>
  )
}

function Row({ item, onUndo }: { item: Item; onUndo: () => void }) {
  if (item.role === 'user') {
    return (
      <div className="pa-user">
        {item.files?.length ? <div className="pa-files">{item.files.map((f) => <span key={f}><Paperclip size={11} /><em>{f}</em></span>)}</div> : null}
        <div className="bubble">{item.text}</div>
      </div>
    )
  }
  if (item.role === 'assistant') {
    return (
      <div className="pa-bot">
        <Orb size={22} />
        <div className="bubble"><AssistantText text={item.text} /></div>
      </div>
    )
  }
  if (item.place && !item.undone) return <PlaceCard item={item} onUndo={onUndo} />
  return (
    <div className={`pa-action ${item.undone ? 'undone' : ''}`} style={tintVar(tint(item.symbol))}>
      <span className="ic">{item.undone ? <Undo2 size={13} strokeWidth={2.6} /> : icon(item.symbol)}</span>
      <span className="tx">{item.text}</span>
      {item.androidUndo && !item.undone && <button className="pa-undo" onClick={onUndo}>Undo</button>}
    </div>
  )
}

/** A place the assistant saved: a little map with the pin, the address and directions (PlaceChatCard). */
function PlaceCard({ item, onUndo }: { item: Item; onUndo: () => void }) {
  const p = item.place!
  const cat = PLACE[p.category] ?? PLACE.other
  const pin = p.lat !== 0 || p.lon !== 0
  const directions = () => {
    const url = pin ? `https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lon}`
      : p.link || `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent([p.name, p.address].filter(Boolean).join(' '))}`
    window.orbit.openExternal(url)
  }
  return (
    <div className="pa-place" style={tintVar(cat.tint)}>
      {pin && <MiniMap lat={p.lat} lon={p.lon} icon={cat.icon(13)} />}
      <div className="pa-place-body">
        <div className="pa-place-top">
          <CheckCircle2 size={14} color="var(--good)" />{item.text}<span className="spacer" />
          {item.androidUndo && <button onClick={onUndo}>Undo</button>}
        </div>
        <div className="pa-place-main">
          <span className="ic">{cat.icon(14)}</span>
          <div style={{ minWidth: 0 }}>
            <div className="n clamp2">{p.name}</div>
            <div className="a clamp2">{[placeTitle(p.category), p.address].filter(Boolean).join(' · ')}</div>
          </div>
        </div>
        <button className="pa-directions" onClick={directions}><Navigation size={13} strokeWidth={2.6} />Directions</button>
      </div>
    </div>
  )
}

/** OpenStreetMap tiles around a point, the point in the middle. */
function MiniMap({ lat, lon, icon: pinIcon }: { lat: number; lon: number; icon: ReactNode }) {
  const z = 16, n = 2 ** z
  const x = ((lon + 180) / 360) * n
  const r = (lat * Math.PI) / 180
  const y = ((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * n
  const tx = Math.floor(x), ty = Math.floor(y), fx = (x - tx) * 256, fy = (y - ty) * 256
  const tiles: ReactNode[] = []
  for (let dx = -2; dx <= 2; dx++) for (let dy = -1; dy <= 1; dy++) {
    tiles.push(<img key={`${dx},${dy}`} alt="" loading="lazy" src={`https://tile.openstreetmap.org/${z}/${(tx + dx + n) % n}/${ty + dy}.png`}
      style={{ left: `calc(50% + ${dx * 256 - fx}px)`, top: `calc(50% + ${dy * 256 - fy}px)` }} />)
  }
  return (
    <div className="pa-map" aria-hidden>
      {tiles}
      <span className="pa-pin">{pinIcon}</span>
      <span style={{ position: 'absolute', right: 4, bottom: 2, fontSize: 9, color: '#555', background: 'rgba(255,255,255,0.7)', padding: '0 3px', borderRadius: 3 }}>© OpenStreetMap</span>
    </div>
  )
}

/** Assistant text with light markdown (bold, italics, links) and ``` code blocks (AssistantText). */
function AssistantText({ text }: { text: string }) {
  const parts: ReactNode[] = []
  let rest = text, k = 0
  while (true) {
    const open = rest.indexOf('```')
    if (open < 0) break
    const before = rest.slice(0, open)
    if (before.trim()) parts.push(<div key={k++}>{inline(before.replace(/^\n+|\n+$/g, ''))}</div>)
    const after = rest.slice(open + 3)
    const nl = after.indexOf('\n')
    const lang = (nl < 0 ? after : after.slice(0, nl)).trim()
    const body = nl < 0 ? '' : after.slice(nl + 1)
    const close = body.indexOf('```')
    if (close < 0) { parts.push(<CodeBlock key={k++} lang={lang} code={body} />); rest = ''; break } // still being written
    parts.push(<CodeBlock key={k++} lang={lang} code={body.slice(0, close).replace(/^\n+|\n+$/g, '')} />)
    rest = body.slice(close + 3)
  }
  if (rest.trim()) parts.push(<div key={k++}>{inline(rest.replace(/^\n+|\n+$/g, ''))}</div>)
  return <div className="pa-text">{parts}</div>
}

function CodeBlock({ lang, code }: { lang: string; code: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <div className="pa-code">
      <div className="pa-code-head">
        <span>{lang || 'code'}</span><span className="spacer" />
        <button onClick={() => { navigator.clipboard?.writeText(code); setCopied(true); setTimeout(() => setCopied(false), 1500) }}>
          {copied ? <><Check size={12} /> Copied</> : <><Copy size={12} /> Copy</>}
        </button>
      </div>
      <pre>{code}</pre>
    </div>
  )
}

function inline(text: string): ReactNode[] {
  const out: ReactNode[] = []
  const re = /\*\*([^*]+)\*\*|\*([^*\n]+)\*|`([^`\n]+)`|\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)|(https?:\/\/[^\s)]+)/g
  let last = 0, m: RegExpExecArray | null, k = 0
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(text.slice(last, m.index))
    if (m[1]) out.push(<strong key={k++}>{m[1]}</strong>)
    else if (m[2]) out.push(<em key={k++}>{m[2]}</em>)
    else if (m[3]) out.push(<code key={k++} style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: '0.9em', background: 'var(--canvas)', padding: '1px 4px', borderRadius: 4 }}>{m[3]}</code>)
    else {
      const url = m[5] ?? m[6]
      out.push(<a key={k++} href={url} onClick={(e) => { e.preventDefault(); window.orbit.openExternal(url) }}>{m[4] ?? url.replace(/^https?:\/\/(www\.)?/, '').slice(0, 40)}</a>)
    }
    last = re.lastIndex
  }
  if (last < text.length) out.push(text.slice(last))
  return out
}

function Thinking() {
  return <div className="pa-thinking"><i /><i /><i /></div>
}
