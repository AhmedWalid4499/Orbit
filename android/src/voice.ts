// Talking to the assistant on Android, as on the Mac and iPhone (WakeListener.swift, Dictation and Speaker in
// AssistantInput.swift):
// • Speaker: replies are read aloud while they're written, sentence by sentence (Android's text-to-speech).
// • Dictation: the composer's mic; the words appear as you speak, and the message sends when you stop.
// • "Hey <assistant name>": while Joshu is open it can listen for its name. Then the big orb takes the screen and
//   you just talk: it answers out loud, listens again, and keeps going until you say "stop" / "bye", tap ✕, or
//   go quiet for a while. Tapping the orb while it talks interrupts it. The conversation is saved in past chats.
import { App as CapApp } from '@capacitor/app'
import { native, isNative } from './native'
import { store } from '@/lib/store'

interface State {
  /** Voice mode (the orb) is on screen. */
  inConversation: boolean
  /** Waiting for "Hey Joshu". */
  wakeListening: boolean
  /** The composer's mic is on. */
  dictating: boolean
  /** A reply is being read aloud. */
  speaking: boolean
  /** Live words while you talk (voice mode or the mic). */
  heard: string
  /** The last question asked in voice mode. */
  question: string
  /** Microphone loudness 0-1, for the orb. */
  level: number
  error: string
}
let state: State = { inConversation: false, wakeListening: false, dictating: false, speaking: false, heard: '', question: '', level: 0, error: '' }
const subs = new Set<(s: State) => void>()
const set = (p: Partial<State>) => { state = { ...state, ...p }; subs.forEach((f) => f(state)) }
export const voiceState = () => state
export const onVoice = (f: (s: State) => void): (() => void) => { subs.add(f); return () => { subs.delete(f) } }

/** The assistant answers questions asked by voice (it reads its reply aloud as it's written). */
let asker: ((question: string) => Promise<void>) | null = null
export function setVoiceAsker(f: ((q: string) => Promise<void>) | null): void { asker = f }

/** Called when a conversation starts, so the app can open the assistant tab underneath. */
let opener: (() => void) | null = null
export function onVoiceStart(f: () => void): void { opener = f }

export const wakeEnabled = (): boolean => localStorage.getItem('wake.enabled') === 'on'
export function setWakeEnabled(on: boolean): void {
  localStorage.setItem('wake.enabled', on ? 'on' : 'off')
  if (on) startWake(); else stopWake()
  subs.forEach((f) => f(state))
}

const assistantName = (): string => (store.setting<string>('assistantName') ?? '').trim() || 'Joshu'

// MARK: Speaker

/** Text without links, markdown, code or bullets, for reading aloud (Speaker.plain). */
export function plain(text: string): string {
  return text
    .replace(/```[\s\S]*?(```|$)/g, ' ')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/https?:\/\/\S+/g, '')
    .replace(/[*_`#>]+/g, '')
    .replace(/^\s*[•\-–]\s*/gm, '')
    .replace(/\s+/g, ' ')
    .trim()
}

async function sayOne(text: string): Promise<void> {
  const t = plain(text)
  if (!t) return
  if (isNative) { await native.speak({ text: t }).catch(() => {}); return }
  // The browser preview: the browser's own voice, when it has one.
  if (!('speechSynthesis' in window)) return
  await new Promise<void>((resolve) => {
    const u = new SpeechSynthesisUtterance(t)
    u.onend = () => resolve(); u.onerror = () => resolve()
    speechSynthesis.speak(u)
  })
}

let token = 0
let queue: string[] = []
let consumed = 0
let ended = true
let reading = false
let doneWaiters: (() => void)[] = []
const settle = () => { const w = doneWaiters; doneWaiters = []; w.forEach((f) => f()) }

/** Starts reading a reply that's still being written: feed it with `liveFeed`, close it with `liveEnd`. */
export function liveBegin(): void {
  stopSpeaking()
  token++
  queue = []; consumed = 0; ended = false
  readLoop(token)
}

/** The reply so far (of the current part). Whole sentences are queued as soon as they're complete;
 *  `final` queues the rest and makes the next call start a new part. */
export function liveFeed(text: string, final = false): void {
  if (ended) return
  const rest = text.slice(consumed)
  if (final) { if (rest.trim()) queue.push(rest); consumed = 0; return }
  // The very first words go at the first natural pause after a few words, so it starts talking almost at once.
  let cut = -1
  const re = consumed === 0 && !reading ? /([.!?:;,—–]|\n)\s/g : /([.!?]|\n)\s/g
  let m: RegExpExecArray | null
  while ((m = re.exec(rest))) cut = m.index + m[0].length
  if (cut > 0 && (consumed > 0 || reading || rest.slice(0, cut).split(' ').length >= 4 || /[.!?\n]\s$/.test(rest.slice(0, cut)))) {
    queue.push(rest.slice(0, cut))
    consumed += cut
  }
}

/** No more text is coming; reading finishes with what's queued. */
export function liveEnd(): void { ended = true; if (!reading && !queue.length) settle() }

async function readLoop(my: number): Promise<void> {
  while (my === token) {
    const next = queue.shift()
    if (next !== undefined) {
      reading = true
      if (!state.speaking) { set({ speaking: true }); if (waking && isNative) native.stopListening().catch(() => {}) }
      await sayOne(next)
      reading = false
    } else if (ended) break
    else await new Promise((r) => setTimeout(r, 60))
  }
  if (my === token) {
    if (state.speaking) set({ speaking: false })
    settle()
    if (!conversation) setTimeout(() => startWake(), 600)
  }
}

/** Reads one finished text aloud. */
export function speak(text: string): void { liveBegin(); liveFeed(text, true); liveEnd() }

/** Stops reading at once. */
export function stopSpeaking(): void {
  token++
  queue = []; ended = true; reading = false
  if (isNative) native.stopSpeaking().catch(() => {})
  else if ('speechSynthesis' in window) speechSynthesis.cancel()
  if (state.speaking) set({ speaking: false })
  settle()
}

/** Resolves once nothing is being read aloud. */
export function whenDoneSpeaking(): Promise<void> {
  if (!reading && !queue.length && (ended || !state.speaking)) return Promise.resolve()
  return new Promise((r) => doneWaiters.push(r))
}

// MARK: Listening

/** One go of speech to text, with live words and the microphone level. */
async function listenOnce(quiet = false): Promise<string> {
  const handles = quiet ? [] : [
    await native.addListener('partial', (d) => set({ heard: d.text })),
    // The recogniser's rms is about -2…10 dB.
    await native.addListener('level', (d) => set({ level: Math.max(0, Math.min(1, (d.level + 2) / 12)) })),
  ]
  try {
    return (await native.listen(quiet ? { quiet: true } : {})).text.trim()
  } finally {
    handles.forEach((h) => h.remove())
    if (!quiet) set({ level: 0 })
  }
}

/** The composer's mic: returns what was said ('' for nothing). */
export async function dictate(): Promise<string> {
  if (!isNative) throw new Error('Voice works in the Android app.')
  stopSpeaking()
  set({ dictating: true, heard: '', error: '' })
  native.stopListening().catch(() => {}) // the wake word listener lets go of the microphone
  try {
    return await listenOnce()
  } catch (e) {
    const m = String((e as Error)?.message ?? e)
    if (!/no match|cancel/i.test(m)) throw new Error(m)
    return ''
  } finally {
    set({ dictating: false, heard: '' })
    setTimeout(() => startWake(), 800)
  }
}
export function stopDictation(): void { native.stopListening().catch(() => {}) }

// MARK: Matching (WakeListener.wakeRange / isGoodbye)

function letters(s: string): string {
  let t = s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^\p{L}]/gu, '')
  for (const [a, b] of [['ou', 'u'], ['oo', 'u'], ['uu', 'u'], ['ee', 'i'], ['ey', 'i'], ['ie', 'i'], ['ck', 'k'], ['ph', 'f']]) t = t.split(a).join(b)
  if (t.length > 2 && t.endsWith('y')) t = t.slice(0, -1) + 'i'
  return t
}

function close(a: string, b: string): boolean {
  if (a === b) return true
  const allowed = b.length <= 4 ? 1 : 2
  if (Math.abs(a.length - b.length) > allowed) return false
  const row = Array.from({ length: b.length + 1 }, (_, i) => i)
  for (let i = 1; i <= a.length; i++) {
    let prev = row[0]; row[0] = i
    for (let j = 1; j <= b.length; j++) {
      const cur = row[j]
      row[j] = a[i - 1] === b[j - 1] ? prev : Math.min(prev, row[j], row[j - 1]) + 1
      prev = cur
    }
  }
  return row[b.length] <= allowed
}

/** Where "hey <name>" ends in what was heard (allowing for how the recogniser spells names), or -1. */
export function wakeEnd(text: string, name = assistantName()): number {
  const want = letters(name)
  if (want.length < 2) return -1
  const re = /\b(hey|hi|hay|okay|ok)\b[\s,]+/gi
  let m: RegExpExecArray | null
  while ((m = re.exec(text))) {
    const restStart = m.index + m[0].length
    const rest = text.slice(restStart)
    const words = rest.split(/[ ,]+/).filter(Boolean).slice(0, 2)
    let joined = '', end = restStart
    for (const w of words) {
      joined += letters(w)
      end = restStart + rest.indexOf(w) + w.length
      if (close(joined, want)) return end
      if (joined.length >= want.length + 2) break
    }
  }
  return -1
}

export function isGoodbye(text: string): boolean {
  const t = text.toLowerCase().replace(/[^\p{L}' ]/gu, '').trim()
  const exact = ['stop', 'stop it', 'stop talking', 'be quiet', 'cancel', 'never mind', 'nevermind', "that's all", 'thats all',
    "that's it", 'thats it', 'bye', 'goodbye', 'good bye', 'bye bye', "we're done", 'were done', "i'm done", 'im done',
    "thank you that's all", "thanks that's all", "thank you that's it", "thanks that's it", 'thanks bye', 'thank you bye',
    'okay bye', 'ok bye', 'end', 'exit', 'quit']
  if (exact.includes(t)) return true
  const words = t.split(' ')
  return words.length <= 4 && (words.includes('bye') || words.includes('goodbye') || t.startsWith('stop'))
}

// MARK: Listening for "Hey Joshu"

let waking = false
let foreground = true
let conversation = false

if (isNative) {
  CapApp.addListener('pause', () => { foreground = false; native.stopListening().catch(() => {}); stopSpeaking() })
  CapApp.addListener('resume', () => { foreground = true; if (wakeEnabled()) startWake() })
}

export async function startWake(): Promise<void> {
  if (!isNative || waking || !wakeEnabled()) return
  waking = true
  set({ wakeListening: true })
  let failures = 0
  while (wakeEnabled() && foreground && !conversation && !state.dictating && !state.speaking && failures < 5) {
    try {
      const text = await listenOnce(true)
      failures = 0
      const end = wakeEnd(text)
      if (end >= 0) {
        const question = text.slice(end).replace(/^[\s,.!?]+/, '').trim()
        waking = false
        set({ wakeListening: false })
        startConversation(question)
        return
      }
    } catch (e) {
      const m = String((e as Error)?.message ?? e)
      if (/permission|microphone/i.test(m)) { set({ error: m }); break }
      if (!/no match/i.test(m)) failures++
      await new Promise((r) => setTimeout(r, 400))
    }
  }
  waking = false
  set({ wakeListening: false })
}

export function stopWake(): void { if (!conversation && !state.dictating) native.stopListening().catch(() => {}) }

// MARK: Conversation

/** Starts talking (from "Hey Joshu" or the waveform button); `first` is a question already heard. */
export async function startConversation(first = ''): Promise<void> {
  if (conversation) return
  conversation = true
  opener?.()
  stopSpeaking()
  if (isNative) native.stopListening().catch(() => {})
  set({ inConversation: true, heard: '', question: '', error: '', level: 0 })
  if (!isNative) return // the browser preview shows the orb; tap ✕ to close it
  let quiet = 0
  let next = first
  while (conversation) {
    if (!next) {
      set({ heard: '' })
      try {
        next = await listenOnce()
      } catch (e) {
        if (!/no match/i.test(String((e as Error)?.message))) set({ error: String((e as Error)?.message ?? e) })
        next = ''
      }
      if (!conversation) break
      if (!next) { if (++quiet >= 2) break; continue }
    }
    quiet = 0
    if (isGoodbye(next)) break
    set({ question: next, heard: '', error: '' })
    try {
      await asker?.(next)
      await whenDoneSpeaking()
    } catch (e) { set({ error: String((e as Error)?.message ?? e) }) }
    next = ''
  }
  endConversation()
}

/** Tapping the orb while it talks: stop talking and listen. */
export function interrupt(): void { if (state.speaking) stopSpeaking() }

export function endConversation(): void {
  const was = conversation
  conversation = false
  native.stopListening().catch(() => {})
  stopSpeaking()
  set({ inConversation: false, heard: '', level: 0 })
  if (was || isNative) setTimeout(() => startWake(), 800)
}
