// End-to-end encrypted key vault shared with the Mac (VaultCrypto.swift), ported from
// windows/src/main/vault.ts to WebCrypto:
//   key = PBKDF2-HMAC-SHA256(passphrase, salt, 210 000, 32 bytes)
//   box = base64(nonce ‖ AES-256-GCM ciphertext ‖ tag), mac = hex HMAC-SHA256(key, plaintext)
// The plaintext is JSON with sorted keys, written exactly like Apple's JSONSerialization.
import { secrets } from './secrets'
import { isPro } from './pro'

const DEVICE_ONLY = new Set(['sync-passphrase', 'vault-mac', 'github-user', 'google-client-id'])
type Bytes = Uint8Array<ArrayBuffer>
const keyCache = new Map<string, Bytes>()
const enc = new TextEncoder()

const b64 = (b: Bytes): string => { let s = ''; b.forEach((x) => (s += String.fromCharCode(x))); return btoa(s) }
const unb64 = (s: string): Bytes => Uint8Array.from(atob(s), (c) => c.charCodeAt(0))
const hex = (b: Bytes): string => [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
const same = (a: Bytes, b: Bytes): boolean => a.length === b.length && a.every((x, i) => x === b[i])

async function deriveKey(pass: string, salt: Bytes): Promise<Bytes> {
  const id = `${b64(salt)}|${pass}`
  if (!keyCache.has(id)) {
    const base = await crypto.subtle.importKey('raw', enc.encode(pass), 'PBKDF2', false, ['deriveBits'])
    const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: 210_000 }, base, 256)
    keyCache.set(id, new Uint8Array(bits))
  }
  return keyCache.get(id)!
}

const aes = (key: Bytes) => crypto.subtle.importKey('raw', key, 'AES-GCM', false, ['encrypt', 'decrypt'])

async function seal(plain: Bytes, key: Bytes): Promise<string> {
  const nonce = crypto.getRandomValues(new Uint8Array(12))
  const body = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, await aes(key), plain))
  const all = new Uint8Array(12 + body.length)
  all.set(nonce); all.set(body, 12)
  return b64(all)
}

async function open(box: string, key: Bytes): Promise<Bytes | null> {
  try {
    const all = unb64(box)
    return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: all.subarray(0, 12) }, await aes(key), all.subarray(12)))
  } catch { return null }
}

async function mac(plain: Bytes, key: Bytes): Promise<string> {
  const k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return hex(new Uint8Array(await crypto.subtle.sign('HMAC', k, plain)))
}

/** JSON exactly as JSONSerialization(.sortedKeys) writes it. */
function appleJSON(v: unknown): string {
  const sort = (x: any): any => Array.isArray(x) ? x.map(sort)
    : x && typeof x === 'object' ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, sort(x[k])])) : x
  return JSON.stringify(sort(v)).replace(/\//g, '\\/')
}

async function settingID(key: string): Promise<string> {
  const b = new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(`orbit-setting:${key}`))).subarray(0, 16)
  b[6] = (b[6] & 0x0f) | 0x50
  b[8] = (b[8] & 0x3f) | 0x80
  const h = hex(b)
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

interface Payload { secrets: Record<string, string>; config: Record<string, unknown> }

function localPayload(): Payload {
  const all = secrets.all()
  const s: Record<string, string> = {}
  for (const [k, v] of Object.entries(all)) if (!DEVICE_ONLY.has(k) && v) s[k] = v
  const config: Record<string, unknown> = {}
  if (all['google-client-id']) config.googleClientID = all['google-client-id']
  if (all['github-user']) config.githubUser = all['github-user']
  const accounts = Object.keys(all).filter((k) => k.startsWith('gmail:')).map((k) => k.slice(6)).sort()
  if (accounts.length) config.gmailAccounts = accounts
  return { secrets: s, config }
}

async function apply(p: Payload): Promise<void> {
  await secrets.merge(Object.fromEntries(Object.entries(p.secrets ?? {}).filter(([k]) => !DEVICE_ONLY.has(k))))
  const c = p.config ?? {}
  if (typeof c.googleClientID === 'string' && c.googleClientID) await secrets.set('google-client-id', c.googleClientID)
  if (typeof c.githubUser === 'string' && c.githubUser) await secrets.set('github-user', c.githubUser)
}

/** Union of both sides; where both have a value, `preferLocal` decides (same rule as the Mac). */
function mergePayloads(remote: Payload, local: Payload, preferLocal: boolean): Payload {
  const s = { ...(remote.secrets ?? {}) }
  for (const [k, v] of Object.entries(local.secrets)) if (preferLocal || s[k] === undefined) s[k] = v
  const config: Record<string, unknown> = { ...(remote.config ?? {}) }
  for (const [k, v] of Object.entries(local.config)) if (k !== 'gmailAccounts' && (preferLocal || config[k] === undefined)) config[k] = v
  const accounts = new Set([...((remote.config?.gmailAccounts as string[]) ?? []), ...((local.config.gmailAccounts as string[]) ?? [])])
  if (accounts.size) config.gmailAccounts = [...accounts].sort()
  return { secrets: s, config }
}

export interface VaultRequest { url: string; key: string; accessToken: string; userID: string; passphrase?: string }
export type VaultState = 'needsNewPassphrase' | 'needsPassphrase' | 'on' | 'wrongPassphrase' | 'error'

async function rest(r: VaultRequest, path: string, init: RequestInit = {}): Promise<any> {
  const res = await fetch(`${r.url}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: r.key, Authorization: `Bearer ${r.accessToken}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) },
  })
  if (!res.ok) throw new Error(`Sync error ${res.status}`)
  const t = await res.text()
  return t ? JSON.parse(t) : null
}

async function upload(r: VaultRequest, id: string, plain: Bytes, salt: Bytes, key: Bytes): Promise<void> {
  const data = { v: 1, salt: b64(salt), box: await seal(plain, key), mac: await mac(plain, key) }
  await rest(r, 'orbit_records?on_conflict=user_id,id', {
    method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify([{ id, user_id: r.userID, kind: 'vault', data, deleted: false }]),
  })
}

/** Two-way sync of keys and sign-ins with the encrypted vault in your account. */
export async function syncVault(r: VaultRequest): Promise<{ state: VaultState; message?: string }> {
  try {
    if (r.passphrase) await secrets.set('sync-passphrase', r.passphrase)
    const id = await settingID('vault')
    const rows = (await rest(r, `orbit_records?id=eq.${id}&select=data,deleted`)) ?? []
    const remote = rows[0] && !rows[0].deleted ? rows[0].data : null
    const pass = secrets.get('sync-passphrase')
    if (!pass) return { state: remote ? 'needsPassphrase' : 'needsNewPassphrase' }

    const local = localPayload()
    if (remote?.salt && remote?.box) {
      const salt = unb64(remote.salt)
      const key = await deriveKey(pass, salt)
      const remotePlain = await open(remote.box, key)
      if (!remotePlain) {
        if (r.passphrase) await secrets.delete('sync-passphrase')
        return { state: 'wrongPassphrase', message: "That passphrase doesn't match the one you set on your Mac." }
      }
      const remotePayload = JSON.parse(new TextDecoder().decode(remotePlain)) as Payload
      const localMac = await mac(enc.encode(appleJSON(local)), key)
      if (localMac === remote.mac) { await secrets.set('vault-mac', localMac); return { state: 'on' } }
      const known = secrets.get('vault-mac')
      const merged = mergePayloads(remotePayload, local, !!known && known !== localMac)
      await apply(merged)
      const mergedPlain = enc.encode(appleJSON(merged))
      if (!same(mergedPlain, remotePlain)) await upload(r, id, mergedPlain, salt, key)
      await secrets.set('vault-mac', await mac(mergedPlain, key))
    } else {
      const salt = crypto.getRandomValues(new Uint8Array(16))
      const key = await deriveKey(pass, salt)
      const plain = enc.encode(appleJSON(local))
      await upload(r, id, plain, salt, key)
      await secrets.set('vault-mac', await mac(plain, key))
    }
    return { state: 'on' }
  } catch (e) {
    return { state: 'error', message: e instanceof Error ? e.message : String(e) }
  }
}

export async function forget(): Promise<void> {
  await secrets.delete('sync-passphrase')
  await secrets.delete('vault-mac')
}

export function status() {
  const names = secrets.names()
  return {
    // "Can use the AI": Joshu Pro on this account, or your own key.
    anthropic: names.includes('anthropic-api-key') || isPro(),
    googleClient: names.includes('google-client-id') && names.includes('google-client-secret'),
    passphrase: names.includes('sync-passphrase'),
    gmail: names.filter((n) => n.startsWith('gmail:')).map((n) => n.slice(6)).sort(),
  }
}

const SETTABLE = new Set(['anthropic-api-key', 'google-client-id', 'google-client-secret', 'github-token', 'github-user'])
export async function setSecret(name: string, value: string): Promise<boolean> {
  if (!SETTABLE.has(name)) return false
  if (value) await secrets.set(name, value.trim()); else await secrets.delete(name)
  return true
}
