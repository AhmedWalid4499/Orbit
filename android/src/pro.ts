// Joshu Pro on Android, as on the Mac (Pro.swift): the AI works through Joshu's own server when your account
// has Pro (bought on iPhone, or given to you from the admin page), or directly with your own Anthropic key.
// Android has no in-app purchase: Pro comes from the account.
import supabase from '../../Support/Supabase.json'
import { getSession, accessToken } from '@/lib/cloud'
import { native, isNative } from './native'

const KEY = 'pro.until'
const subs = new Set<() => void>()
export const onProChange = (f: () => void): (() => void) => { subs.add(f); return () => { subs.delete(f) } }

/** When this account's Pro ends (ms), or 0. */
export const proUntil = (): number => Number(localStorage.getItem(KEY) ?? 0)
export const isPro = (): boolean => !!getSession() && proUntil() > Date.now()

/** Asks the Joshu server for this account's plan (the entitlements table the admin page writes). */
export async function refreshPro(): Promise<boolean> {
  const s = getSession()
  if (!s) { localStorage.removeItem(KEY); subs.forEach((f) => f()); return false }
  try {
    const r = await fetch(`${supabase.url}/rest/v1/entitlements?select=pro_until&user_id=eq.${s.userID}`, {
      headers: { apikey: supabase.key, Authorization: `Bearer ${await accessToken()}` },
    })
    if (r.ok) {
      const rows = await r.json()
      const until = rows[0]?.pro_until ? new Date(rows[0].pro_until).getTime() : 0
      localStorage.setItem(KEY, String(until))
      subs.forEach((f) => f())
    }
  } catch { /* offline: keep what we knew */ }
  return isPro()
}

/**
 * fetch() for the Anthropic SDK that goes to Joshu's AI server with your Joshu sign-in instead of an API key.
 * The server only answers apps (no browser CORS), so on the phone the request runs natively and streams back.
 */
export async function proFetch(_url: RequestInfo | URL, init: RequestInit = {}): Promise<Response> {
  const headers: Record<string, string> = {}
  new Headers(init.headers ?? {}).forEach((v, k) => { if (k !== 'x-api-key' && !k.startsWith('x-stainless') && k !== 'anthropic-dangerous-direct-browser-access') headers[k] = v })
  headers['authorization'] = `Bearer ${await accessToken()}`
  headers['apikey'] = supabase.key
  const url = `${supabase.url}/functions/v1/claude`
  const body = typeof init.body === 'string' ? init.body : init.body ? await new Response(init.body).text() : ''
  if (!isNative) return fetch(url, { method: 'POST', headers, body, signal: init.signal })

  const id = crypto.randomUUID()
  let controller!: ReadableStreamDefaultController<Uint8Array>
  const stream = new ReadableStream<Uint8Array>({ start(c) { controller = c } })
  return new Promise<Response>((resolve, reject) => {
    const handles = [
      native.addListener('head', (d) => {
        if (d.id === id) resolve(new Response(stream, { status: d.status, headers: { 'content-type': d.contentType } }))
      }),
      native.addListener('chunk', (d) => {
        if (d.id === id) controller.enqueue(Uint8Array.from(atob(d.data), (c) => c.charCodeAt(0)))
      }),
    ]
    const cleanup = () => handles.forEach((h) => h.then((x) => x.remove()))
    native.httpStream({ id, url, headers, body })
      .then(() => { try { controller.close() } catch { /* already closed */ } cleanup() })
      .catch((e) => { try { controller.error(e) } catch { /* not started */ } reject(new TypeError(String(e?.message ?? e))); cleanup() })
  })
}
