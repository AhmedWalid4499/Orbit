// Orbit account (Supabase Auth) and REST access to `orbit_records`, matching the Mac app's CloudSync.swift.

export interface Session {
  accessToken: string
  refreshToken: string
  expiresAt: number // ms since epoch
  userID: string
  email: string
}

export class CloudError extends Error {}

const SESSION_KEY = 'orbit.session'
const CALLBACK = 'com.personal.orbit://auth-callback'

let config = { url: '', key: '' }
const listeners = new Set<() => void>()

export function configure(c: { url: string; key: string }): void { config = c }
export function isConfigured(): boolean { return !!config.url && !!config.key }
export function cloudConfig(): { url: string; key: string } { return config }

export function getSession(): Session | null {
  try { return JSON.parse(localStorage.getItem(SESSION_KEY) ?? 'null') } catch { return null }
}
function setSession(s: Session | null): void {
  if (s) localStorage.setItem(SESSION_KEY, JSON.stringify(s))
  else localStorage.removeItem(SESSION_KEY)
  listeners.forEach((l) => l())
}
export function onSessionChange(fn: () => void): () => void {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

function parseSession(json: any): Session | null {
  if (!json?.access_token || !json?.refresh_token || !json?.user?.id) return null
  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token,
    expiresAt: Date.now() + (json.expires_in ?? 3600) * 1000,
    userID: json.user.id,
    email: json.user.email ?? '',
  }
}

async function auth(path: string, body: Record<string, string>): Promise<any> {
  if (!isConfigured()) throw new CloudError("Sync isn't set up in this copy of Orbit.")
  const res = await fetch(`${config.url}/auth/v1/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: config.key },
    body: JSON.stringify(body),
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new CloudError(json.msg ?? json.error_description ?? json.message ?? `Error ${res.status}`)
  return json
}

export async function signIn(email: string, password: string): Promise<void> {
  const s = parseSession(await auth('token?grant_type=password', { email, password }))
  if (!s) throw new CloudError('Sign-in failed.')
  setSession(s)
}

export async function signUp(email: string, password: string): Promise<'signedIn' | 'checkEmail'> {
  const s = parseSession(await auth('signup', { email, password }))
  if (s) { setSession(s); return 'signedIn' }
  return 'checkEmail'
}

export async function resetPassword(email: string): Promise<void> { await auth('recover', { email }) }

export function signOut(): void {
  const s = getSession()
  if (s) {
    fetch(`${config.url}/auth/v1/logout`, { method: 'POST', headers: { apikey: config.key, Authorization: `Bearer ${s.accessToken}` } }).catch(() => {})
  }
  setSession(null)
}

// MARK: Google (PKCE through the system browser; Supabase sends the browser back to Orbit)

let pendingVerifier: string | null = null
let pendingGoogle: { resolve: () => void; reject: (e: Error) => void } | null = null

function base64url(bytes: Uint8Array): string {
  let s = ''
  bytes.forEach((b) => (s += String.fromCharCode(b)))
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export async function signInWithGoogle(): Promise<void> {
  if (!isConfigured()) throw new CloudError("Sync isn't set up in this copy of Orbit.")
  pendingGoogle?.reject(new CloudError('Cancelled.'))
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(48)))
  const challenge = base64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))))
  pendingVerifier = verifier
  const url = new URL(`${config.url}/auth/v1/authorize`)
  url.searchParams.set('provider', 'google')
  url.searchParams.set('redirect_to', CALLBACK)
  url.searchParams.set('code_challenge', challenge)
  url.searchParams.set('code_challenge_method', 's256')
  await window.orbit.openExternal(url.toString())
  return new Promise((resolve, reject) => { pendingGoogle = { resolve, reject } })
}

/** Called with the com.personal.orbit://auth-callback link the browser hands back. */
export async function handleCallback(link: string): Promise<void> {
  if (!link.startsWith(CALLBACK) || !pendingVerifier || !pendingGoogle) return
  const p = pendingGoogle
  const verifier = pendingVerifier
  pendingGoogle = null
  pendingVerifier = null
  const u = new URL(link.replace(CALLBACK, 'https://x/cb'))
  const frag = new URLSearchParams(u.hash.replace(/^#/, ''))
  const code = u.searchParams.get('code') ?? frag.get('code')
  if (!code) {
    p.reject(new CloudError((u.searchParams.get('error_description') ?? frag.get('error_description') ?? 'Google sign-in was cancelled.').replace(/\+/g, ' ')))
    return
  }
  try {
    const s = parseSession(await auth('token?grant_type=pkce', { auth_code: code, code_verifier: verifier }))
    if (!s) throw new CloudError("Google sign-in didn't finish.")
    setSession(s)
    p.resolve()
  } catch (e) {
    p.reject(e as Error)
  }
}

// MARK: Tokens and REST

let refreshing: Promise<string> | null = null

export async function accessToken(): Promise<string> {
  const s = getSession()
  if (!s) throw new CloudError('Not signed in.')
  if (s.expiresAt - Date.now() > 60_000) return s.accessToken
  refreshing ??= (async () => {
    try {
      const fresh = parseSession(await auth('token?grant_type=refresh_token', { refresh_token: s.refreshToken }))
      if (!fresh) { setSession(null); throw new CloudError('Your Orbit sign-in expired. Please sign in again.') }
      setSession(fresh)
      return fresh.accessToken
    } finally {
      refreshing = null
    }
  })()
  return refreshing
}

export async function rest(path: string, init: { method?: string; body?: unknown; prefer?: string } = {}): Promise<any> {
  const res = await fetch(`${config.url}/rest/v1/${path}`, {
    method: init.method ?? 'GET',
    headers: {
      apikey: config.key,
      Authorization: `Bearer ${await accessToken()}`,
      'Content-Type': 'application/json',
      ...(init.prefer ? { Prefer: init.prefer } : {}),
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  })
  const text = await res.text()
  if (!res.ok) {
    let msg = ''
    try { msg = JSON.parse(text).message ?? '' } catch { /* not JSON */ }
    if (res.status === 401) throw new CloudError('Your Orbit sign-in expired. Please sign in again.')
    throw new CloudError(`Sync error ${res.status}${msg ? `: ${msg}` : ''}`)
  }
  return text ? JSON.parse(text) : null
}
