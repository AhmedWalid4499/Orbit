// Journal check-in with the assistant, ported from JournalCompanion.swift.
// The chat is stored on the note exactly as the Mac stores it (JournalChat encoded by Swift's JSONEncoder,
// then base64), so a conversation started on one device can continue on the other.
import { store } from '@/lib/store'
import { Note } from '@/lib/models'
import { iso } from '@/lib/dates'
import { streamTurn, structured, Block, Msg } from '@/lib/ai'
import { daySnapshot } from '@/lib/snapshot'

export interface Turn {
  id: string // UUID, uppercase like Swift's UUID encoding
  role: 'user' | 'assistant'
  text: string
  raw?: string // base64 of the JSON array of assistant content blocks
  hidden: boolean
  at: number // seconds since 2001-01-01 (Swift's default Date encoding)
}
export interface Chat { system: string; turns: Turn[] }

const REFERENCE_DATE = 978307200 // 2001-01-01T00:00:00Z in Unix seconds

function b64encode(text: string): string {
  const bytes = new TextEncoder().encode(text)
  let bin = ''
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  return btoa(bin)
}
function b64decode(b64: string): string {
  return new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)))
}

/** Reads a stored chat, tolerating older or partial data. */
export function decodeChat(stored: string | null | undefined): Chat | null {
  if (!stored) return null
  try {
    const json = JSON.parse(b64decode(stored))
    return {
      system: typeof json.system === 'string' ? json.system : '',
      turns: (Array.isArray(json.turns) ? json.turns : []).map((t: any) => ({
        id: typeof t.id === 'string' ? t.id : crypto.randomUUID().toUpperCase(),
        role: t.role === 'assistant' ? 'assistant' : 'user',
        text: typeof t.text === 'string' ? t.text : '',
        ...(typeof t.raw === 'string' ? { raw: t.raw } : {}),
        hidden: !!t.hidden,
        at: typeof t.at === 'number' ? t.at : Date.now() / 1000 - REFERENCE_DATE,
      })),
    }
  } catch {
    return null
  }
}

export function encodeChat(chat: Chat): string {
  return b64encode(JSON.stringify({
    system: chat.system,
    turns: chat.turns.map((t) => ({ id: t.id, role: t.role, text: t.text, ...(t.raw ? { raw: t.raw } : {}), hidden: t.hidden, at: t.at })),
  }))
}

const turn = (role: Turn['role'], text: string, extra: Partial<Turn> = {}): Turn =>
  ({ id: crypto.randomUUID().toUpperCase(), role, text, hidden: false, at: Date.now() / 1000 - REFERENCE_DATE, ...extra })

function current(noteID: string): { note: Note; chat: Chat | null } | null {
  const r = store.get<Note>(noteID)
  return r ? { note: r.data, chat: decodeChat(r.data.chat) } : null
}

function save(noteID: string, chat: Chat): void {
  store.update<Note>(noteID, { chat: encodeChat(chat), updatedAt: iso(new Date()) })
}

export function systemPrompt(assistant: string): string {
  const name = (store.setting<string>('userName') ?? '').split(' ')[0] || 'there'
  return `You are ${assistant}, a gentle, warm journaling companion inside ${name}'s personal organizer app. You help ${name} unwind and reflect on today through a calm, unhurried conversation, so their journal entry almost writes itself.

Tone:
- Soft and kind, like a close friend checking in at the end of the day. Never clinical, never a coach, never a therapist.
- Short. Usually one or two sentences, and never more than one question per message.
- Start with a little warmth before you ask anything. If they share something hard, acknowledge it gently first; don't rush to the next question or try to fix it.
- If you have two separate thoughts (a reflection and then a question), put a blank line between them.
- Plain text only. No lists, no headings, no markdown, no emoji unless they use them first.

Flow:
- Open by asking how they're feeling today.
- Then, at their pace, ask about what they did, a moment that stood out, and anything on their mind for tomorrow.
- Use the day's data below to make questions specific ("How did the budget review go?"), but never assume something happened just because it was planned.
- After about 4-6 exchanges, or when they seem done, mention softly that they can tap "Write my entry" to turn the chat into today's journal.
- If they mention feeling unsafe or in crisis, respond with care and encourage reaching out to someone they trust or local emergency services.

Today's data from the app:
${daySnapshot()}`
}

/** Starts the check-in: the assistant opens with a question about mood. */
export async function startChat(noteID: string, assistant: string, onText: (t: string) => void): Promise<void> {
  const c = current(noteID)
  if (!c) return
  const chat = c.chat ?? { system: systemPrompt(assistant), turns: [] }
  if (!chat.turns.length) {
    chat.turns.push(turn('user', "I just opened today's journal.", { hidden: true }))
    save(noteID, chat)
  }
  await reply(noteID, onText)
}

export async function sendMessage(noteID: string, text: string, assistant: string, onText: (t: string) => void): Promise<void> {
  const c = current(noteID)
  if (!c) return
  const chat = c.chat ?? { system: systemPrompt(assistant), turns: [] }
  chat.turns.push(turn('user', text))
  save(noteID, chat)
  updateMood(noteID).catch(() => {})
  await reply(noteID, onText)
}

/** Streams the next assistant message. On failure the user's turn stays, so a retry continues cleanly. */
export async function reply(noteID: string, onText: (t: string) => void): Promise<void> {
  const c = current(noteID)
  if (!c?.chat || c.chat.turns[c.chat.turns.length - 1]?.role !== 'user') return
  const chat = c.chat
  const messages: Msg[] = chat.turns.map((t) => {
    if (t.role === 'assistant' && t.raw) {
      try { return { role: 'assistant', content: JSON.parse(b64decode(t.raw)) as Block[] } } catch { /* fall back to text */ }
    }
    return { role: t.role, content: t.text }
  })
  const result = await streamTurn({ system: chat.system, messages, effort: 'low', onText })
  const latest = current(noteID)?.chat ?? chat
  latest.turns.push(turn('assistant', result.text.trim(), { raw: b64encode(JSON.stringify(result.content)) }))
  save(noteID, latest)
}

/** Quietly estimates today's mood from what they've said (never overrides a mood they picked). */
async function updateMood(noteID: string): Promise<void> {
  const c = current(noteID)
  if (!c?.chat || c.note.moodSetByUser) return
  const said = c.chat.turns.filter((t) => t.role === 'user' && !t.hidden).map((t) => t.text).join('\n')
  if (!said) return
  const guess = await structured<{ mood: number }>(
    "Estimate the writer's mood today from 1 (rough) to 5 (great), from their own words only. 0 if they haven't said how they feel.",
    said, { type: 'object', properties: { mood: { type: 'integer' } }, required: ['mood'], additionalProperties: false }, 'low', 2000)
  const after = store.get<Note>(noteID)
  if (after && guess.mood >= 1 && guess.mood <= 5 && !after.data.moodSetByUser) store.update<Note>(noteID, { mood: guess.mood })
}

/** Writes one entry from what's already written plus the chat, replacing the body. Returns the previous body for Undo. */
export async function writeEntry(noteID: string): Promise<{ previous: string; entry: string }> {
  const c = current(noteID)
  if (!c?.chat) return { previous: c?.note.body ?? '', entry: c?.note.body ?? '' }
  const transcript = c.chat.turns.filter((t) => !t.hidden).map((t) => `${t.role === 'user' ? 'Me' : 'Companion'}: ${t.text}`).join('\n')
  const system = `Write today's journal entry in the first person, as the user ("Me").
You get what they've already written in their journal (may be empty) and a conversation with their companion.
Produce ONE cohesive entry that includes everything from both without repeating anything: keep their own sentences where you can, fix only obvious typos, and fold in what they said in the chat.
Use only what the user actually wrote or said; don't add events or feelings they didn't express.
2-4 short paragraphs of plain text, no headings, no markdown, no date line.
mood: 1 (rough) to 5 (great) from what they said, or 0 if unclear.`
  const input = `ALREADY WRITTEN:\n${c.note.body ? c.note.body : '(nothing yet)'}\n\nCONVERSATION:\n${transcript}`
  const result = await structured<{ entry: string; mood: number }>(system, input, {
    type: 'object', properties: { entry: { type: 'string' }, mood: { type: 'integer' } }, required: ['entry', 'mood'], additionalProperties: false,
  }, 'medium')
  const after = store.get<Note>(noteID)
  const patch: Partial<Note> = { body: result.entry, updatedAt: iso(new Date()) }
  if (result.mood >= 1 && result.mood <= 5 && !after?.data.moodSetByUser) patch.mood = result.mood
  store.update<Note>(noteID, patch)
  return { previous: c.note.body ?? '', entry: result.entry }
}
