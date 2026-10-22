// End-to-end encrypted key vault shared with the Mac app (VaultCrypto.swift / CloudSync.syncVault):
//   key = PBKDF2-HMAC-SHA256(passphrase, salt, 210 000, 32 bytes)
//   box = base64(nonce ‖ AES-256-GCM ciphertext ‖ tag), mac = hex HMAC-SHA256(key, plaintext)
// The plaintext is JSON with sorted keys, written exactly like Apple's JSONSerialization (compact,
// "/" escaped as "\/") so both apps compute the same fingerprint for the same content.
import { ipcMain } from 'electron'
import { createCipheriv, createDecipheriv, createHash, createHmac, pbkdf2Sync, randomBytes } from 'crypto'
import { secrets } from './secrets'

const DEVICE_ONLY = new Set(['sync-passphrase', 'vault-mac', 'github-user', 'google-client-id'])
const keyCache = new Map<string, Buffer>()

function deriveKey(pass: string, salt: Buffer): Buffer {
  const id = `${salt.toString('base64')}|${pass}`
  if (!keyCache.has(id)) keyCache.set(id, pbkdf2Sync(pass, salt, 210_000, 32, 'sha256'))
  return keyCache.get(id)!
}

function seal(plain: Buffer, key: Buffer): string {
  const nonce = randomBytes(12)
  const c = createCipheriv('aes-256-gcm', key, nonce)
  const body = Buffer.concat([c.update(plain), c.final()])
  return Buffer.concat([nonce, body, c.getAuthTag()]).toString('base64')
}

function open(box: string, key: Buffer): Buffer | null {
  try {
    const all = Buffer.from(box, 'base64')
    const d = createDecipheriv('aes-256-gcm', key, all.subarray(0, 12))
    d.setAuthTag(all.subarray(all.length - 16))
    return Buffer.concat([d.update(all.subarray(12, all.length - 16)), d.final()])
  } catch { return null }
}

const mac = (plain: Buffer, key: Buffer): string => createHmac('sha256', key).update(plain).digest('hex')

/** JSON exactly as JSONSerialization(.sortedKeys) writes it. */
function appleJSON(v: unknown): string {
  const sort = (x: any): any => Array.isArray(x) ? x.map(sort)
    : x && typeof x === 'object' ? Object.fromEntries(Object.keys(x).sort().map((k) => [k, sort(x[k])])) : x
  return JSON.stringify(sort(v)).replace(/\//g, '\\/')
}

function settingID(key: string): string {
  const b = createHash('sha256').update(`orbit-setting:${key}`).digest().subarray(0, 16)
  b[6] = (b[6] & 0x0f) | 0x50
  b[8] = (b[8] & 0x3f) | 0x80
  const h = b.toString('hex')
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

function apply(p: Payload): void {
  secrets.merge(Object.fromEntries(Object.entries(p.secrets ?? {}).filter(([k]) => !DEVICE_ONLY.has(k))))
  const c = p.config ?? {}
  if (typeof c.googleClientID === 'string' && c.googleClientID) secrets.set('google-client-id', c.googleClientID)
  if (typeof c.githubUser === 'string' && c.githubUser) secrets.set('github-user', c.githubUser)
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

async function upload(r: VaultRequest, id: string, plain: Buffer, salt: Buffer, key: Buffer): Promise<void> {
  const data = { v: 1, salt: salt.toString('base64'), box: seal(plain, key), mac: mac(plain, key) }
  await rest(r, 'orbit_records?on_conflict=user_id,id', {
    method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify([{ id, user_id: r.userID, kind: 'vault', data, deleted: false }]),
  })
}

/** Two-way sync of keys and sign-ins with the encrypted vault in your Orbit account. */
export async function syncVault(r: VaultRequest): Promise<{ state: VaultState; message?: string }> {
  try {
    if (r.passphrase) secrets.set('sync-passphrase', r.passphrase)
    const id = settingID('vault')
    const rows = (await rest(r, `orbit_records?id=eq.${id}&select=data,deleted`)) ?? []
    const remote = rows[0] && !rows[0].deleted ? rows[0].data : null
    const pass = secrets.get('sync-passphrase')
    if (!pass) return { state: remote ? 'needsPassphrase' : 'needsNewPassphrase' }

    const local = localPayload()
    if (remote?.salt && remote?.box) {
      const salt = Buffer.from(remote.salt, 'base64')
      const key = deriveKey(pass, salt)
      const remotePlain = open(remote.box, key)
      if (!remotePlain) {
        if (r.passphrase) secrets.delete('sync-passphrase')
        return { state: 'wrongPassphrase', message: "That passphrase doesn't match the one you set on your Mac." }
      }
      const remotePayload = JSON.parse(remotePlain.toString('utf8')) as Payload
      const localMac = mac(Buffer.from(appleJSON(local)), key)
      if (localMac === remote.mac) { secrets.set('vault-mac', localMac); return { state: 'on' } }
      const known = secrets.get('vault-mac')
      const merged = mergePayloads(remotePayload, local, !!known && known !== localMac)
      apply(merged)
      const mergedPlain = Buffer.from(appleJSON(merged))
      if (!mergedPlain.equals(remotePlain)) await upload(r, id, mergedPlain, salt, key)
      secrets.set('vault-mac', mac(mergedPlain, key))
    } else {
      const salt = randomBytes(16)
      const key = deriveKey(pass, salt)
      const plain = Buffer.from(appleJSON(local))
      await upload(r, id, plain, salt, key)
      secrets.set('vault-mac', mac(plain, key))
    }
    return { state: 'on' }
  } catch (e) {
    return { state: 'error', message: e instanceof Error ? e.message : String(e) }
  }
}

export function registerVault(): void {
  ipcMain.handle('vault-sync', (_e, r: VaultRequest) => syncVault(r))
  ipcMain.handle('vault-forget', () => { secrets.delete('sync-passphrase'); secrets.delete('vault-mac') })
  ipcMain.handle('secrets-status', () => {
    const names = secrets.names()
    return {
      anthropic: names.includes('anthropic-api-key'),
      googleClient: names.includes('google-client-id') && names.includes('google-client-secret'),
      passphrase: names.includes('sync-passphrase'),
      gmail: names.filter((n) => n.startsWith('gmail:')).map((n) => n.slice(6)).sort(),
    }
  })
  // Only these can be set from the window; tokens arrive through sign-in or the vault.
  const settable = new Set(['anthropic-api-key', 'google-client-id', 'google-client-secret'])
  ipcMain.handle('secret-set', (_e, name: string, value: string) => {
    if (!settable.has(name)) return false
    if (value) secrets.set(name, value.trim()); else secrets.delete(name)
    return true
  })
}
