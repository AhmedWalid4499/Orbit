// Claude on Android: the same model, settings and error messages as the desktop process in
// windows/src/main/claude.ts. The key stays in the encrypted secret store and is read per request.
import Anthropic from '@anthropic-ai/sdk'
import { secrets } from './secrets'
import { isPro, proFetch } from './pro'

export const MODEL = 'claude-opus-5-5'
// Server-side fallback: if a safety classifier declines, the API retries on a suitable model.
const BETAS: Anthropic.Beta.AnthropicBeta[] = ['server-side-fallback-2026-07-01']

let client: Anthropic | null = null
let clientKey = ''
/** Your own key if you added one (the owner's setup), otherwise Joshu's AI server with Joshu Pro. */
function api(): Anthropic {
  const key = secrets.get('anthropic-api-key')
  const want = key || (isPro() ? 'joshu-pro' : '')
  if (!want) throw new Error('This needs Joshu Pro.')
  if (!client || want !== clientKey) {
    client = key ? new Anthropic({ apiKey: key, dangerouslyAllowBrowser: true })
      : new Anthropic({ apiKey: 'joshu-pro', dangerouslyAllowBrowser: true, fetch: proFetch as any, maxRetries: 1 })
    clientKey = want
  }
  return client
}

/** Turns SDK errors into short messages the app can show. */
function explain(e: unknown): string {
  // Joshu's AI server explains itself (sign in, needs Pro, today's limit): show its words.
  const joshu = (e as any)?.error?.error
  if (joshu?.type === 'joshu' && joshu.message) return joshu.message
  if (e instanceof Anthropic.AuthenticationError) return 'The Anthropic API key was rejected. Check it in Settings › AI.'
  if (e instanceof Anthropic.RateLimitError) return 'Rate limited by the API. Try again in a minute.'
  if (e instanceof Anthropic.APIConnectionError) return 'Network problem: Joshu couldn’t reach Claude.'
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
  /** The chat's code sandbox, so files made there stay for the next question. */
  container?: string
}

/** Keeps only what may be echoed back: after a mid-output fallback, non-text blocks before the last `fallback` marker are dropped. */
function replayable(content: Anthropic.Beta.BetaContentBlock[]): Anthropic.Beta.BetaContentBlock[] {
  const boundary = content.map((b) => b.type).lastIndexOf('fallback' as any)
  if (boundary < 0) return content
  return content.filter((b, i) => i >= boundary || b.type === 'text')
}

const deltaSubs = new Set<(d: { id: string; text: string }) => void>()
export function onDelta(fn: (d: { id: string; text: string }) => void): () => void {
  deltaSubs.add(fn)
  return () => { deltaSubs.delete(fn) }
}

export async function turn(req: TurnRequest): Promise<any> {
  try {
    const stream = api().beta.messages.stream({
      model: MODEL,
      max_tokens: req.maxTokens ?? 16000,
      system: req.system,
      messages: req.messages,
      ...(req.tools?.length ? { tools: req.tools } : {}),
      ...(req.container ? { container: req.container } : {}),
      output_config: { effort: req.effort },
      betas: BETAS,
      fallbacks: 'default',
    })
    let text = ''
    stream.on('text', (delta) => {
      text += delta
      deltaSubs.forEach((f) => f({ id: req.id, text }))
    })
    const message = await stream.finalMessage()
    if (message.stop_reason === 'refusal') return { ok: false, error: 'This request was declined.' }
    const all = message.content.filter((b) => b.type === 'text').map((b: any) => b.text).join('')
    return { ok: true, text: all, content: replayable(message.content), stopReason: message.stop_reason, container: (message as any).container?.id }
  } catch (e) {
    return { ok: false, error: explain(e) }
  }
}

/** One request whose answer must match a JSON schema; returns the parsed object. */
export async function structured(req: { system: string; user: string; schema: Record<string, unknown>; effort: 'low' | 'medium' | 'high'; maxTokens?: number }):
  Promise<{ ok: boolean; data?: any; error?: string }> {
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

export async function test(): Promise<{ ok: boolean; message?: string }> {
  const r = await structured({ system: 'Reply with ok=true.', user: 'ping', effort: 'low', maxTokens: 2000,
    schema: { type: 'object', properties: { ok: { type: 'boolean' } }, required: ['ok'], additionalProperties: false } })
  return r.ok ? { ok: true, message: `Connected to ${MODEL}.` } : { ok: false, message: r.error }
}
