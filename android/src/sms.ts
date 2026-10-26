// Bank texts on Android: Joshu reads new SMS from your banks whenever it opens or comes back to the
// front, and logs the payments (bank.ts). Nothing leaves the phone except the text sent to Claude for
// reading, when there's an API key, exactly like the iPhone's Shortcuts automation.
import { native, isNative } from './native'
import { logMessage, acceptsSender, looksLikeBank } from './bank'
import { secrets } from './secrets'

const ENABLED = 'bankSMS.android'
const SINCE = 'bankSMS.since'
const ACTIVITY = 'bankSMS.activity'

export interface Activity { t: number; sender: string; text: string; result: string }

export const smsEnabled = (): boolean => localStorage.getItem(ENABLED) === 'on'
export const smsActivity = (): Activity[] => { try { return JSON.parse(localStorage.getItem(ACTIVITY) ?? '[]') } catch { return [] } }

const subs = new Set<() => void>()
export const onSmsChange = (f: () => void): (() => void) => { subs.add(f); return () => { subs.delete(f) } }
const emit = () => subs.forEach((f) => f())

function record(a: Activity): void {
  const list = [a, ...smsActivity()].slice(0, 20)
  localStorage.setItem(ACTIVITY, JSON.stringify(list))
}

/** Turns automatic logging on (asking Android for SMS access) and reads the last `days` days. */
export async function enableSms(days = 3): Promise<boolean> {
  if (!isNative) return false
  const { granted } = await native.smsPermission({ request: true })
  if (!granted) return false
  localStorage.setItem(ENABLED, 'on')
  if (!localStorage.getItem(SINCE)) localStorage.setItem(SINCE, String(Date.now() - days * 86_400_000))
  emit()
  await checkBankTexts()
  return true
}

export function disableSms(): void { localStorage.setItem(ENABLED, 'off'); emit() }

let running = false
export async function checkBankTexts(): Promise<number> {
  if (!isNative || !smsEnabled() || running) return 0
  running = true
  let logged = 0
  try {
    const { granted } = await native.smsPermission({ request: false })
    if (!granted) return 0
    const since = Number(localStorage.getItem(SINCE) ?? Date.now() - 86_400_000)
    const { messages } = await native.readSms({ since, limit: 200 })
    const useAI = !!secrets.get('anthropic-api-key')
    let newest = since
    // Oldest first, so expenses land in the order they happened.
    for (const m of [...messages].sort((a, b) => a.date - b.date)) {
      newest = Math.max(newest, m.date)
      if (!acceptsSender(m.address) && !looksLikeBank(m.body)) continue
      const result = await logMessage(m.body, m.address, new Date(m.date), useAI)
      if (result.startsWith('Logged')) logged++
      if (!result.startsWith('Not from')) record({ t: m.date, sender: m.address, text: m.body.slice(0, 140), result })
    }
    localStorage.setItem(SINCE, String(newest))
  } catch (e) {
    record({ t: Date.now(), sender: '', text: '', result: `Couldn't read texts: ${e instanceof Error ? e.message : String(e)}` })
  } finally {
    running = false
    emit()
  }
  return logged
}
