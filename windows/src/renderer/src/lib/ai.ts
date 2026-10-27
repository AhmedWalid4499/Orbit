// Claude from the window: calls go to the desktop process, which holds the API key.
import { useEffect, useState } from 'react'
import { useSetting } from './store'

export type Effort = 'low' | 'medium' | 'high'
export interface Block { type: string; [k: string]: any }
export interface Msg { role: 'user' | 'assistant'; content: string | Block[] }
export interface Tool { name: string; description: string; input_schema: Record<string, unknown>; eager_input_streaming?: boolean }

export class AIError extends Error {}

/** One answer that must match `schema`; returns the parsed object. */
export async function structured<T>(system: string, user: string, schema: Record<string, unknown>, effort: Effort = 'medium', maxTokens = 16000): Promise<T> {
  const r = await window.orbit.claudeStructured({ system, user, schema, effort, maxTokens })
  if (!r.ok) throw new AIError(r.error ?? 'Claude request failed.')
  return r.data as T
}

/** One streamed model turn. `onText` gets the full text so far. */
export async function streamTurn(opts: { system: string; messages: Msg[]; tools?: Tool[]; effort?: Effort; maxTokens?: number; container?: string; onText?: (text: string) => void }):
  Promise<{ text: string; content: Block[]; stopReason: string | null; container?: string }> {
  const id = crypto.randomUUID()
  const off = window.orbit.onClaudeDelta((d) => { if (d.id === id) opts.onText?.(d.text) })
  try {
    const r = await window.orbit.claudeTurn({ id, system: opts.system, messages: opts.messages, tools: opts.tools, effort: opts.effort ?? 'low', maxTokens: opts.maxTokens, container: opts.container })
    if (!r.ok) throw new AIError(r.error ?? 'Claude request failed.')
    return { text: r.text ?? '', content: r.content ?? [], stopReason: r.stopReason ?? null, container: r.container }
  } finally {
    off()
  }
}

// MARK: Key status (shared across the app)

export interface KeyStatus { anthropic: boolean; googleClient: boolean; passphrase: boolean; gmail: string[] }
let status: KeyStatus = { anthropic: false, googleClient: false, passphrase: false, gmail: [] }
const subs = new Set<(s: KeyStatus) => void>()

export async function refreshKeys(): Promise<KeyStatus> {
  status = await window.orbit.secretsStatus()
  subs.forEach((f) => f(status))
  return status
}

export function useKeys(): KeyStatus {
  const [s, set] = useState(status)
  useEffect(() => { subs.add(set); refreshKeys(); return () => { subs.delete(set) } }, [])
  return s
}

/** What the user calls their AI ("Ask" unless renamed; synced with the Mac). */
export function useAssistantName(): string {
  const n = useSetting<string>('assistantName', 'Ask')
  return n?.trim() || 'Ask'
}
