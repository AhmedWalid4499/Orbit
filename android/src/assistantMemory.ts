// Things the assistant remembers about you between chats (AssistantMemory.swift): a JSON list in the synced
// "assistant.memory" setting, so the Mac, iPhone and Android share it. Listed and editable in Settings › AI.
import { store } from '@/lib/store'

const LIMIT = 60

export function memories(): string[] {
  const raw = store.setting<string>('assistant.memory')
  try { const list = raw ? JSON.parse(raw) : []; return Array.isArray(list) ? list.filter((x) => typeof x === 'string') : [] } catch { return [] }
}

export function setMemories(list: string[]): void {
  const clean = list.map((s) => s.trim()).filter(Boolean).slice(-LIMIT)
  store.setSetting('assistant.memory', clean.length ? JSON.stringify(clean) : null)
}

/** Adds a fact; false if it was already known. */
export function remember(fact: string): boolean {
  const f = fact.trim()
  if (!f) return false
  const list = memories()
  if (list.some((x) => x.toLowerCase() === f.toLowerCase())) return false
  setMemories([...list, f])
  return true
}

/** Removes facts containing `text` (or contained in it); returns what was removed. */
export function forget(text: string): string[] {
  const t = text.trim().toLowerCase()
  if (!t) return []
  const list = memories()
  const gone = list.filter((x) => x.toLowerCase().includes(t) || t.includes(x.toLowerCase()))
  setMemories(list.filter((x) => !gone.includes(x)))
  return gone
}

/** The block added to the assistant's instructions. */
export function memoryPromptBlock(): string {
  const list = memories()
  return list.length ? `\n\nWhat you remember about them (from earlier chats; use it naturally, don't recite it):\n${list.map((m) => `• ${m}`).join('\n')}` : ''
}
