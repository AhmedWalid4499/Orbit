// Google sign-in (loopback + PKCE, like windows/src/main/google.ts) and Gmail/Calendar requests.
// The loopback listener runs natively (OrbitNativePlugin); Google requests go through Capacitor's
// native HTTP so they aren't subject to the web view's CORS rules. Refresh tokens are stored as
// "gmail:<address>", the Mac's names, so accounts unlocked from the synced vault work right away.
import { CapacitorHttp } from '@capacitor/core'
import { Browser } from '@capacitor/browser'
import { native, isNative } from './native'
import { secrets } from './secrets'

const SCOPE = 'https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.readonly email'
const ALLOWED = /^https:\/\/(gmail|www)\.googleapis\.com\//
const tokens = new Map<string, { token: string; expires: number }>()

const b64url = (bytes: Uint8Array): string => {
  let s = ''
  bytes.forEach((b) => (s += String.fromCharCode(b)))
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function client(): { id: string; secret: string } {
  const id = secrets.get('google-client-id') ?? ''
  const secret = secrets.get('google-client-secret') ?? ''
  if (!id || !secret) throw new Error('Add the Google client ID and secret first (Settings › Email), or unlock your synced keys.')
  return { id, secret }
}

async function http(method: 'GET' | 'POST', url: string, opts: { headers?: Record<string, string>; form?: Record<string, string> } = {}) {
  if (isNative) {
    const r = await CapacitorHttp.request({
      method, url, headers: { ...(opts.headers ?? {}), ...(opts.form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}) },
      data: opts.form ? new URLSearchParams(opts.form).toString() : undefined,
      responseType: 'text',
    })
    const text = typeof r.data === 'string' ? r.data : JSON.stringify(r.data)
    return { status: r.status, text, header: (k: string) => r.headers?.[k] ?? r.headers?.[k.toLowerCase()] ?? null }
  }
  const res = await fetch(url, {
    method, headers: { ...(opts.headers ?? {}), ...(opts.form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}) },
    body: opts.form ? new URLSearchParams(opts.form).toString() : undefined,
  })
  return { status: res.status, text: await res.text(), header: (k: string) => res.headers.get(k) }
}

async function tokenRequest(form: Record<string, string>): Promise<any> {
  const r = await http('POST', 'https://oauth2.googleapis.com/token', { form })
  let json: any = {}
  try { json = JSON.parse(r.text) } catch { /* not JSON */ }
  if (json.error) throw new Error(`Google sign-in failed: ${json.error_description ?? json.error}`)
  return json
}

/** Opens Chrome for consent; returns the signed-in Gmail address. */
export async function signIn(hint?: string): Promise<string> {
  if (!isNative) throw new Error('Google sign-in works in the Android app.')
  const { id, secret } = client()
  const verifier = b64url(crypto.getRandomValues(new Uint8Array(48)))
  const challenge = b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))))
  const { port } = await native.startLoopback()
  const redirect = `http://127.0.0.1:${port}`
  const q = new URLSearchParams({
    client_id: id, redirect_uri: redirect, response_type: 'code', scope: SCOPE,
    code_challenge: challenge, code_challenge_method: 'S256', access_type: 'offline', prompt: 'consent', include_granted_scopes: 'true',
    ...(hint ? { login_hint: hint } : {}),
  })
  const waiting = native.waitLoopback()
  await Browser.open({ url: `https://accounts.google.com/o/oauth2/v2/auth?${q}` })
  const back = new URLSearchParams((await waiting).query)
  native.bringToFront().catch(() => {})
  const code = back.get('code')
  if (!code) throw new Error('Google sign-in was cancelled.')

  const t = await tokenRequest({ grant_type: 'authorization_code', code, redirect_uri: redirect, client_id: id, client_secret: secret, code_verifier: verifier })
  if (!t.refresh_token || !t.access_token) throw new Error("Google didn't return a refresh token. Remove Joshu from your Google account's third-party access and try again.")
  const profile = await http('GET', 'https://gmail.googleapis.com/gmail/v1/users/me/profile', { headers: { Authorization: `Bearer ${t.access_token}` } })
  let email = ''
  try { email = JSON.parse(profile.text).emailAddress ?? '' } catch { /* below */ }
  if (!email) throw new Error("Couldn't read the Gmail profile. Is the Gmail API enabled in your Google Cloud project?")
  await secrets.set(`gmail:${email}`, t.refresh_token)
  tokens.set(email, { token: t.access_token, expires: Date.now() + ((t.expires_in ?? 3600) - 60) * 1000 })
  return email
}

async function accessToken(email: string): Promise<string> {
  const cached = tokens.get(email)
  if (cached && cached.expires > Date.now()) return cached.token
  const refresh = secrets.get(`gmail:${email}`)
  if (!refresh) throw new Error(`${email} needs to be connected again.`)
  const { id, secret } = client()
  const t = await tokenRequest({ grant_type: 'refresh_token', refresh_token: refresh, client_id: id, client_secret: secret })
  if (!t.access_token) throw new Error(`Google sign-in for ${email} expired. Reconnect it in Settings › Email.`)
  tokens.set(email, { token: t.access_token, expires: Date.now() + ((t.expires_in ?? 3600) - 60) * 1000 })
  return t.access_token
}

/** GET a Gmail/Google API URL as `email`, waiting and retrying when Google says it's busy (429). */
export async function get(email: string, url: string): Promise<{ ok: boolean; status: number; data?: any; error?: string }> {
  if (!ALLOWED.test(url)) return { ok: false, status: 0, error: 'URL not allowed' }
  try {
    const token = await accessToken(email)
    for (let attempt = 0; attempt < 5; attempt++) {
      const res = await http('GET', url, { headers: { Authorization: `Bearer ${token}` } })
      if (res.status >= 200 && res.status < 300) return { ok: true, status: 200, data: JSON.parse(res.text) }
      const body = res.text
      const limited = res.status === 429 || (res.status === 403 && body.includes('ateLimitExceeded'))
      if ((limited || res.status >= 500) && attempt < 4) {
        const wait = Number(res.header('retry-after')) || 2 ** attempt + Math.random() / 2
        await new Promise((r) => setTimeout(r, Math.min(wait, 30) * 1000))
        continue
      }
      if (res.status === 401) { tokens.delete(email); return { ok: false, status: 401, error: 'Gmail access expired. Reconnect the account in Settings › Email.' } }
      return { ok: false, status: res.status, error: body.includes('accessNotConfigured') || body.includes('SERVICE_DISABLED')
        ? 'That Google API isn’t enabled in your Google Cloud project.' : `Google returned an error (${res.status}).` }
    }
    return { ok: false, status: 0, error: "Google didn't respond." }
  } catch (e) {
    return { ok: false, status: 0, error: e instanceof Error ? e.message : String(e) }
  }
}

export async function remove(email: string): Promise<void> {
  await secrets.delete(`gmail:${email}`)
  tokens.delete(email)
}
