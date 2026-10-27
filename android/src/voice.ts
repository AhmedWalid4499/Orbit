// Hands-free voice mode, as on the Mac and iPhone (WakeListener.swift): while Joshu is open it listens on this
// phone for "Hey <assistant name>". Then the big orb takes the screen and you just talk: it answers out loud,
// listens again, and keeps going until you say "stop" / "bye", tap ✕, or go quiet for a while.
// Your conversation is saved in your past chats like any other.
import { App as CapApp } from '@capacitor/app'
import { native, isNative } from './native'
import { store } from '@/lib/store'

export type Phase = 'off' | 'listening' | 'thinking' | 'speaking'
interface State { phase: Phase; heard: string; question: string; answer: string; error: string }
let state: State = { phase: 'off', heard: '', question: '', answer: '', error: '' }
const subs = new Set<(s: State) => void>()
const set = (p: Partial<State>) => { state = { ...state, ...p }; subs.forEach((f) => f(state)) }
export const voiceState = () => state
export const onVoice = (f: (s: State) => void): (() => void) => { subs.add(f); return () => { subs.delete(f) } }

/** The assistant screen answers questions asked by voice; it resolves when the reply has been spoken. */
let asker: ((question: string) => Promise<void>) | null = null
export function setVoiceAsker(f: ((q: string) => Promise<void>) | null): void { asker = f }
/** Called by the assistant as the reply is written, so the orb can show it. */
export function voiceAnswer(text: string, speaking = false): void { if (state.phase !== 'off') set({ answer: text, ...(speaking ? { phase: 'speaking' } : {}) }) }

/** Called when a conversation starts, so the app can open the assistant (which answers). */
let opener: (() => void) | null = null
export function onVoiceStart(f: () => void): void { opener = f }

export const wakeEnabled = (): boolean => localStorage.getItem('wake.enabled') === 'on'
export function setWakeEnabled(on: boolean): void {
  localStorage.setItem('wake.enabled', on ? 'on' : 'off')
  if (on) startWake(); else stopWake()
}

const assistantName = (): string => (store.setting<string>('assistantName') ?? '').trim() || 'Joshu'

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
  let row = Array.from({ length: b.length + 1 }, (_, i) => i)
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
  CapApp.addListener('pause', () => { foreground = false; native.stopListening().catch(() => {}) })
  CapApp.addListener('resume', () => { foreground = true; if (wakeEnabled()) startWake() })
}

export async function startWake(): Promise<void> {
  if (!isNative || waking || !wakeEnabled()) return
  waking = true
  let failures = 0
  while (wakeEnabled() && foreground && !conversation && failures < 5) {
    try {
      const { text } = await native.listen({ quiet: true })
      failures = 0
      const end = wakeEnd(text)
      if (end >= 0) {
        const question = text.slice(end).replace(/^[\s,.!?]+/, '').trim()
        waking = false
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
}

export function stopWake(): void { if (!conversation) native.stopListening().catch(() => {}) }

// MARK: Conversation

/** Starts talking (from "Hey Joshu" or the waveform button); `first` is a question already heard. */
export async function startConversation(first = ''): Promise<void> {
  if (conversation || !isNative) return
  conversation = true
  opener?.()
  set({ phase: 'listening', heard: '', question: '', answer: '', error: '' })
  let quiet = 0
  let next = first
  while (conversation) {
    if (!next) {
      set({ phase: 'listening', heard: '', answer: '' })
      const partial = await native.addListener('partial', (d) => set({ heard: d.text }))
      try {
        next = (await native.listen({})).text.trim()
      } catch (e) {
        if (!/no match/i.test(String((e as Error)?.message))) set({ error: String((e as Error)?.message ?? e) })
        next = ''
      } finally { partial.remove() }
      if (!conversation) break
      if (!next) { if (++quiet >= 2) break; continue }
    }
    quiet = 0
    if (isGoodbye(next)) break
    set({ phase: 'thinking', question: next, heard: '' })
    try { await asker?.(next) } catch (e) { set({ error: String((e as Error)?.message ?? e) }) }
    next = ''
  }
  endConversation()
}

export function endConversation(): void {
  conversation = false
  native.stopListening().catch(() => {})
  native.stopSpeaking().catch(() => {})
  set({ phase: 'off', heard: '', answer: '' })
  setTimeout(() => startWake(), 800)
}
