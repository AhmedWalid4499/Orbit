// Assistant conversations as `chat` records, in the Mac's format (Assistant.swift `Saved`), so past chats
// follow you between the Mac, iPhone and Android:
//   record data: { title, updatedAt, payload }
//   payload: JSON { system, messages: base64(JSON of API messages), items: [{ id, role, text, symbol, undone }] }
// Files sent with a message stay on this phone; the shared copy keeps a note of their names instead.
import { store, Rec } from '@/lib/store'
import { iso } from '@/lib/dates'
import type { Msg, Block } from '@/lib/ai'
import type { Undo } from '@/lib/askTools'

export interface Item { id: string; role: 'user' | 'assistant' | 'action'; text: string; symbol: string; undone: boolean; files?: string[]; androidUndo?: Undo }
export interface Convo { id: string; system: string; messages: Msg[]; items: Item[]; container?: string }
interface ChatRec { title: string; updatedAt: string; payload: string }

const toB64 = (s: string): string => { let out = ''; new TextEncoder().encode(s).forEach((b) => (out += String.fromCharCode(b))); return btoa(out) }
const fromB64 = (s: string): string => new TextDecoder().decode(Uint8Array.from(atob(s), (c) => c.charCodeAt(0)))

export const newConvo = (): Convo => ({ id: crypto.randomUUID().toLowerCase(), system: '', messages: [], items: [] })

/** Messages without file contents (images and PDFs become a short note). */
function withoutFiles(messages: Msg[]): Msg[] {
  return messages.map((m) => typeof m.content === 'string' ? m : {
    ...m,
    content: m.content.map((b: Block) => b.type === 'image' || b.type === 'document'
      ? { type: 'text', text: `[${b.type === 'image' ? 'An image' : `A file${b.title ? ` (${b.title})` : ''}`} was attached here]` } : b),
  })
}

export function listChats(): Rec<ChatRec>[] {
  return store.list<ChatRec>('chat').sort((a, b) => (b.data.updatedAt ?? '').localeCompare(a.data.updatedAt ?? ''))
}

export function openChat(id: string): Convo | null {
  const r = store.get<ChatRec>(id)
  if (!r) return null
  try {
    const p = JSON.parse(r.data.payload)
    const messages: Msg[] = p.messages ? JSON.parse(fromB64(p.messages)) : []
    const items: Item[] = (p.items ?? []).map((i: any) => ({ id: i.id, role: i.role, text: i.text ?? '', symbol: i.symbol ?? '', undone: !!i.undone, files: i.files, androidUndo: i.androidUndo }))
    // A conversation saved mid tool-call can't be continued as is: keep what was said, drop the dangling call.
    const last = messages[messages.length - 1]
    if (last?.role === 'assistant' && Array.isArray(last.content) && last.content.some((b) => b.type === 'tool_use')) messages.pop()
    return { id, system: p.system ?? '', messages, items, container: p.container ?? undefined }
  } catch { return null }
}

export function saveChat(c: Convo): void {
  if (!c.items.length) return
  const first = c.items.find((i) => i.role === 'user')?.text ?? 'New chat'
  const title = first.length > 60 ? `${first.slice(0, 57).trim()}…` : first
  const payload = JSON.stringify({
    system: c.system,
    ...(c.container ? { container: c.container } : {}),
    messages: toB64(JSON.stringify(withoutFiles(c.messages))),
    items: c.items.map((i) => ({ id: i.id.toUpperCase(), role: i.role, text: i.text, symbol: i.symbol, undone: i.undone,
      ...(i.files ? { files: i.files } : {}), ...(i.androidUndo ? { androidUndo: i.androidUndo } : {}) })),
  })
  const data = { title, updatedAt: iso(new Date()), payload }
  store.put(c.id, 'chat', data)
}

export function deleteChat(id: string): void { store.remove(id) }
