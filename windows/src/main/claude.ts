// Claude calls for the Orbit window. They run here, in the desktop process, so the API key never
// reaches the page. Same model and settings as the Mac app.
import Anthropic from '@anthropic-ai/sdk'
import { ipcMain, WebContents } from 'electron'
import { secrets } from './secrets'

const MODEL = 'claude-opus-5-5'
// Server-side fallback: if a safety classifier declines, the API retries on a suitable model.
const BETAS: Anthropic.Beta.AnthropicBeta[] = ['server-side-fallback-2026-07-01']

let client: Anthropic | null = null
let clientKey = ''
function api(): Anthropic {
  const key = secrets.get('anthropic-api-key')
  if (!key) throw new Error('Add your Anthropic API key in Settings › AI.')
  if (!client || key !== clientKey) { client = new Anthropic({ apiKey: key }); clientKey = key }
  return client
}

/** Turns SDK errors into short messages the window can show. */
function explain(e: unknown): string {
  if (e instanceof Anthropic.AuthenticationError) return 'The Anthropic API key was rejected. Check it in Settings › AI.'
  if (e instanceof Anthropic.RateLimitError) return 'Rate limited by the API. Try again in a minute.'
  if (e instanceof Anthropic.APIConnectionError) return 'Network problem: Orbit couldn’t reach Claude.'
  if (e instanceof Anthropic.APIError) return e.status === 529 ? 'Claude is busy right now. Try again shortly.' : `API error ${e.status}: ${e.message}`
  return e instanceof Error ? e.message : String(e)
}

export interface TurnRequest {
  id: string
  system: string
  messages: Anthropic.Beta.BetaMessageParam[]
  tools?: Anthropic.Beta.BetaTool[]
  effort: 'low' | 'medium' | 'high'
  maxTokens?: number
}

export interface TurnResult {
  ok: boolean
  error?: string
  text?: string
  /** The assistant's content blocks, to append to the conversation unchanged. */
  content?: Anthropic.Beta.BetaContentBlock[]
  stopReason?: string | null
}

/** Keeps only what may be echoed back: after a mid-output fallback, non-text blocks before the last `fallback` marker are dropped. */
function replayable(content: Anthropic.Beta.BetaContentBlock[]): Anthropic.Beta.BetaContentBlock[] {
  const boundary = content.map((b) => b.type).lastIndexOf('fallback' as any)
  if (boundary < 0) return content
  return content.filter((b, i) => i >= boundary || b.type === 'text')
}

async function turn(sender: WebContents, req: TurnRequest): Promise<TurnResult> {
  try {
    const stream = api().beta.messages.stream({
      model: MODEL,
      max_tokens: req.maxTokens ?? 16000,
      system: req.system,
      messages: req.messages,
      ...(req.tools?.length ? { tools: req.tools } : {}),
      output_config: { effort: req.effort },
      betas: BETAS,
      fallbacks: 'default',
    })
    let text = ''
    stream.on('text', (delta) => {
      text += delta
      if (!sender.isDestroyed()) sender.send('claude-delta', { id: req.id, text })
    })
    const message = await stream.finalMessage()
    if (message.stop_reason === 'refusal') return { ok: false, error: 'This request was declined.' }
    const all = message.content.filter((b) => b.type === 'text').map((b: any) => b.text).join('')
    return { ok: true, text: all, content: replayable(message.content), stopReason: message.stop_reason }
  } catch (e) {
    return { ok: false, error: explain(e) }
  }
}

/** One request whose answer must match a JSON schema; returns the parsed object. */
async function structured(req: { system: string; user: string; schema: Record<string, unknown>; effort: 'low' | 'medium' | 'high'; maxTokens?: number }):
  Promise<{ ok: boolean; data?: unknown; error?: string }> {
  try {
    const message = await api().beta.messages.create({
      model: MODEL,
      max_tokens: req.maxTokens ?? 16000,
      system: req.system,
      messages: [{ role: 'user', content: req.user }],
      output_config: { effort: req.effort, format: { type: 'json_schema', schema: req.schema } },
      betas: BETAS,
      fallbacks: 'default',
    })
    if (message.stop_reason === 'refusal') return { ok: false, error: 'This request was declined.' }
    const text = message.content.find((b) => b.type === 'text') as Anthropic.Beta.BetaTextBlock | undefined
    if (!text) return { ok: false, error: 'Unexpected response from Claude.' }
    return { ok: true, data: JSON.parse(text.text) }
  } catch (e) {
    return { ok: false, error: explain(e) }
  }
}

export function registerClaude(): void {
  ipcMain.handle('claude-turn', (e, req: TurnRequest) => turn(e.sender, req))
  ipcMain.handle('claude-structured', (_e, req) => structured(req))
  ipcMain.handle('claude-test', async () => {
    const r = await structured({ system: 'Reply with ok=true.', user: 'ping', effort: 'low', maxTokens: 2000,
      schema: { type: 'object', properties: { ok: { type: 'boolean' } }, required: ['ok'], additionalProperties: false } })
    return r.ok ? { ok: true, message: `Connected to ${MODEL}.` } : { ok: false, message: r.error }
  })
}
