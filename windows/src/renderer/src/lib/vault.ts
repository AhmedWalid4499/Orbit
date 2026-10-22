// Unlocks the API keys and Gmail sign-ins synced from the Mac (end-to-end encrypted with your sync passphrase).
import { getSession, accessToken, cloudConfig } from './cloud'
import { refreshKeys } from './ai'

export type VaultState = 'idle' | 'needsNewPassphrase' | 'needsPassphrase' | 'on' | 'wrongPassphrase' | 'error'
let state: { state: VaultState; message?: string } = { state: 'idle' }
const subs = new Set<() => void>()
export const vaultState = () => state
export const onVaultChange = (f: () => void) => { subs.add(f); return () => subs.delete(f) }

export async function syncVault(passphrase?: string): Promise<{ state: VaultState; message?: string }> {
  const s = getSession()
  if (!s) return state
  const c = cloudConfig()
  state = (await window.orbit.vaultSync({ url: c.url, key: c.key, accessToken: await accessToken(), userID: s.userID, passphrase })) as any
  subs.forEach((f) => f())
  await refreshKeys()
  return state
}

export async function forgetPassphrase(): Promise<void> {
  await window.orbit.vaultForget()
  state = { state: 'needsPassphrase' }
  subs.forEach((f) => f())
  await refreshKeys()
}
