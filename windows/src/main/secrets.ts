// API keys and sign-in tokens for this device, encrypted with the operating system's key store
// (DPAPI on Windows, Keychain on macOS) through Electron's safeStorage. Names match the Mac app's
// Keychain entries ("anthropic-api-key", "google-client-secret", "gmail:<address>", …) so the
// encrypted key vault synced through the Orbit account can be merged in directly.
import { app, safeStorage } from 'electron'
import { join } from 'path'
import { existsSync, readFileSync, writeFileSync } from 'fs'

const file = (): string => join(app.getPath('userData'), 'secrets.bin')
let cache: Record<string, string> | null = null

function load(): Record<string, string> {
  if (cache) return cache
  try {
    if (existsSync(file()) && safeStorage.isEncryptionAvailable()) {
      cache = JSON.parse(safeStorage.decryptString(readFileSync(file())))
      return cache!
    }
  } catch { /* unreadable: start empty */ }
  cache = {}
  return cache
}

function persist(): void {
  if (!cache || !safeStorage.isEncryptionAvailable()) return
  writeFileSync(file(), safeStorage.encryptString(JSON.stringify(cache)))
}

export const secrets = {
  get: (name: string): string | undefined => load()[name] || undefined,
  set(name: string, value: string): void { load()[name] = value; persist() },
  delete(name: string): void { delete load()[name]; persist() },
  /** Every name and value, for the encrypted vault (device-only entries excluded). */
  all: (): Record<string, string> => ({ ...load() }),
  merge(values: Record<string, string>): void {
    const s = load()
    for (const [k, v] of Object.entries(values)) if (v) s[k] = v
    persist()
  },
  names: (): string[] => Object.keys(load()),
}
