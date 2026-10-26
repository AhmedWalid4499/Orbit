// API keys and sign-in tokens on this phone, encrypted with an Android Keystore key (the Android
// equivalent of the Mac's Keychain item). Names match the Mac's entries ("anthropic-api-key",
// "google-client-secret", "gmail:<address>", …) so the synced key vault merges in directly.
import { native, isNative } from './native'

let cache: Record<string, string> | null = null
const PREVIEW_KEY = 'orbit.preview-secrets'

export async function loadSecrets(): Promise<Record<string, string>> {
  if (cache) return cache
  try {
    const json = isNative ? (await native.loadSecrets()).json : localStorage.getItem(PREVIEW_KEY) ?? ''
    cache = json ? JSON.parse(json) : {}
  } catch { cache = {} }
  return cache!
}

async function persist(): Promise<void> {
  const json = JSON.stringify(cache ?? {})
  if (isNative) await native.saveSecrets({ json })
  else localStorage.setItem(PREVIEW_KEY, json)
}

export const secrets = {
  get: (name: string): string | undefined => cache?.[name] || undefined,
  async set(name: string, value: string): Promise<void> { (await loadSecrets())[name] = value; await persist() },
  async delete(name: string): Promise<void> { delete (await loadSecrets())[name]; await persist() },
  all: (): Record<string, string> => ({ ...(cache ?? {}) }),
  async merge(values: Record<string, string>): Promise<void> {
    const s = await loadSecrets()
    for (const [k, v] of Object.entries(values)) if (v) s[k] = v
    await persist()
  },
  names: (): string[] => Object.keys(cache ?? {}),
}
