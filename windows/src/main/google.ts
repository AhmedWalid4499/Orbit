// Google sign-in (desktop loopback + PKCE) and Gmail requests, same as the Mac app's Gmail.swift.
// Refresh tokens stay in this process's encrypted secret store as "gmail:<address>", the same names
// the Mac uses, so accounts unlocked from the synced key vault work here without signing in again.
import { ipcMain, shell } from 'electron'
import { createServer } from 'http'
import { createHash, randomBytes } from 'crypto'
import { secrets } from './secrets'

const SCOPE = 'https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.readonly email'
const ALLOWED = /^https:\/\/(gmail|www)\.googleapis\.com\//

const b64url = (b: Buffer): string => b.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
const tokens = new Map<string, { token: string; expires: number }>()

function client(): { id: string; secret: string } {
  const id = secrets.get('google-client-id') ?? ''
  const secret = secrets.get('google-client-secret') ?? ''
  if (!id || !secret) throw new Error('Add the Google client ID and secret first (Settings › Email), or unlock your synced keys.')
  return { id, secret }
}

async function tokenRequest(form: Record<string, string>): Promise<any> {
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form).toString(),
  })
  const json: any = await res.json().catch(() => ({}))
  if (json.error) throw new Error(`Google sign-in failed: ${json.error_description ?? json.error}`)
  return json
}

/** Opens the browser for consent; returns the signed-in Gmail address. */
async function signIn(hint?: string): Promise<string> {
  const { id, secret } = client()
  const verifier = b64url(randomBytes(48))
  const challenge = b64url(createHash('sha256').update(verifier).digest())

  const { code, redirect } = await new Promise<{ code: string; redirect: string }>((resolve, reject) => {
    const server = createServer((req, res) => {
      const url = new URL(req.url ?? '/', 'http://127.0.0.1')
      const code = url.searchParams.get('code'), error = url.searchParams.get('error')
      if (!code && !error) { res.writeHead(404).end(); return }
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
      res.end(`<html><body style="font-family:system-ui;background:#111;color:#f4f4f5;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
        <div style="text-align:center"><h1 style="font-family:Georgia,serif">${code ? "You're connected." : 'Sign-in was cancelled.'}</h1>
        <p>You can close this tab and go back to Orbit.</p></div></body></html>`)
      clearTimeout(timer)
      server.close()
      if (code) resolve({ code, redirect: `http://127.0.0.1:${(server.address() as any).port}` })
      else reject(new Error('Google sign-in was cancelled.'))
    })
    const timer = setTimeout(() => { server.close(); reject(new Error('Google sign-in timed out.')) }, 300_000)
    server.listen(0, '127.0.0.1', () => {
      const port = (server.address() as any).port
      const q = new URLSearchParams({
        client_id: id, redirect_uri: `http://127.0.0.1:${port}`, response_type: 'code', scope: SCOPE,
        code_challenge: challenge, code_challenge_method: 'S256', access_type: 'offline', prompt: 'consent', include_granted_scopes: 'true',
        ...(hint ? { login_hint: hint } : {}),
      })
      shell.openExternal(`https://accounts.google.com/o/oauth2/v2/auth?${q}`)
    })
  })

  const t = await tokenRequest({ grant_type: 'authorization_code', code, redirect_uri: redirect, client_id: id, client_secret: secret, code_verifier: verifier })
  if (!t.refresh_token || !t.access_token) throw new Error("Google didn't return a refresh token. Remove Orbit from your Google account's third-party access and try again.")
  const profile: any = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/profile', { headers: { Authorization: `Bearer ${t.access_token}` } }).then((r) => r.json())
  const email = profile?.emailAddress
  if (!email) throw new Error("Couldn't read the Gmail profile. Is the Gmail API enabled in your Google Cloud project?")
  secrets.set(`gmail:${email}`, t.refresh_token)
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
async function get(email: string, url: string): Promise<{ ok: boolean; status: number; data?: any; error?: string }> {
  if (!ALLOWED.test(url)) return { ok: false, status: 0, error: 'URL not allowed' }
  try {
    const token = await accessToken(email)
    for (let attempt = 0; attempt < 5; attempt++) {
      const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } })
      if (res.ok) return { ok: true, status: 200, data: await res.json() }
      const body = await res.text()
      const limited = res.status === 429 || (res.status === 403 && body.includes('ateLimitExceeded'))
      if ((limited || res.status >= 500) && attempt < 4) {
        const wait = Number(res.headers.get('retry-after')) || 2 ** attempt + Math.random() / 2
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

export function registerGoogle(): void {
  ipcMain.handle('google-sign-in', async (_e, hint?: string) => {
    try { return { ok: true, email: await signIn(hint) } } catch (e) { return { ok: false, error: e instanceof Error ? e.message : String(e) } }
  })
  ipcMain.handle('google-get', (_e, email: string, url: string) => get(email, url))
  ipcMain.handle('google-remove', (_e, email: string) => { secrets.delete(`gmail:${email}`); tokens.delete(email) })
  ipcMain.handle('google-accounts', () => secrets.names().filter((n) => n.startsWith('gmail:')).map((n) => n.slice(6)))
}
