// window.orbit for Android: the same calls the Windows preload exposes (windows/src/preload/index.ts),
// answered here instead of by an Electron main process, so every shared screen works unchanged.
import { App as CapApp } from '@capacitor/app'
import { Browser } from '@capacitor/browser'
import supabase from '../../Support/Supabase.json'
import { isNative } from './native'
import { loadSecrets } from './secrets'
import * as claude from './claude'
import * as google from './google'
import * as vault from './vault'

const RELEASES = 'https://api.github.com/repos/AhmedWalid4499/Orbit/releases/latest'
export const APK_NAME = 'Joshu.apk'

type UpdateState = { state: string; version?: string; progress?: number; message?: string }
const updateSubs = new Set<(s: UpdateState) => void>()
const sendUpdate = (s: UpdateState) => updateSubs.forEach((f) => f(s))
let latestApk: { version: string; url: string } | null = null

export async function appVersion(): Promise<string> {
  if (!isNative) return 'preview'
  try { return (await CapApp.getInfo()).version } catch { return '' }
}

const newer = (a: string, b: string): boolean => {
  const pa = a.split('.').map(Number), pb = b.split('.').map(Number)
  for (let i = 0; i < 3; i++) if ((pa[i] ?? 0) !== (pb[i] ?? 0)) return (pa[i] ?? 0) > (pb[i] ?? 0)
  return false
}

/** Looks for a newer Joshu.apk on the GitHub release the Mac and Windows updaters read. */
export async function checkForUpdates(quiet = false): Promise<void> {
  if (!quiet) sendUpdate({ state: 'checking' })
  try {
    const r = await fetch(RELEASES, { headers: { Accept: 'application/vnd.github+json' } })
    if (!r.ok) throw new Error(`GitHub returned ${r.status}`)
    const rel = await r.json()
    const version = String(rel.tag_name ?? '').replace(/^v/, '')
    const asset = (rel.assets ?? []).find((a: any) => a.name === APK_NAME)
    const current = await appVersion()
    if (asset && current && newer(version, current)) {
      latestApk = { version, url: asset.browser_download_url }
      sendUpdate({ state: 'ready', version })
    } else if (!quiet) {
      sendUpdate({ state: 'none' })
    }
  } catch (e) {
    if (!quiet) sendUpdate({ state: 'error', message: e instanceof Error ? e.message : String(e) })
  }
}

const authSubs = new Set<(url: string) => void>()
let pendingLink: string | null = null

export function installBridge(): void {
  if (isNative) {
    CapApp.addListener('appUrlOpen', ({ url }) => {
      if (authSubs.size) authSubs.forEach((f) => f(url)); else pendingLink = url
    })
  }
  const api = {
    config: async () => ({ supabase, version: await appVersion(), platform: 'android', canUpdate: isNative }),
    openExternal: async (url: string) => { if (/^https?:\/\//.test(url)) await Browser.open({ url }) },
    onAuthCallback: (fn: (url: string) => void) => {
      authSubs.add(fn)
      if (pendingLink) { fn(pendingLink); pendingLink = null }
    },
    checkForUpdates: () => checkForUpdates(false),
    // Android installs the new APK itself once it's downloaded: open the download in Chrome.
    installUpdate: async () => { if (latestApk) await Browser.open({ url: latestApk.url }) },
    onUpdate: (fn: (s: UpdateState) => void) => { updateSubs.add(fn) },

    claudeTurn: (req: any) => claude.turn(req),
    claudeStructured: (req: any) => claude.structured(req),
    claudeTest: () => claude.test(),
    onClaudeDelta: (fn: (d: { id: string; text: string }) => void) => claude.onDelta(fn),

    secretsStatus: async () => { await loadSecrets(); return vault.status() },
    setSecret: (name: string, value: string) => vault.setSecret(name, value),
    vaultSync: async (req: any) => { await loadSecrets(); return vault.syncVault(req) },
    vaultForget: () => vault.forget(),

    googleSignIn: async (hint?: string) => {
      try { return { ok: true, email: await google.signIn(hint) } } catch (e) { return { ok: false, error: e instanceof Error ? e.message : String(e) } }
    },
    googleGet: (email: string, url: string) => google.get(email, url),
    googleRemove: (email: string) => google.remove(email),
  }
  ;(window as any).orbit = api
}
