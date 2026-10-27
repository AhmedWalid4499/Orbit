// Categories Joshu learned from your corrections, like MerchantRules in MoneySmarts.swift on the Mac: change Talabat to
// Food once and every Talabat expense after that is filed under Food. Synced as "merchantRules": { [merchantKey]: category }.
import { store } from './store'
import { Txn } from './models'

const STOP = ['the', 'www', 'com', 'eg', 'egp', 'llc', 'ltd', 'co', 'inc', 'pos']

/** "TALABAT EGYPT*1234 (USD)" → "talabat egypt". Digits, card refs and currency notes don't change the merchant. */
export function merchantKey(title: string): string {
  const t = title.toLowerCase().replace(/\s*\([a-z]{3}\)$/, '')
  return t.split(/[^\p{L}\p{N}\p{M}&']+/u)
    .filter((w) => w && !/^\p{N}+$/u.test(w) && !STOP.includes(w))
    .slice(0, 2).join(' ')
}

/** "talabat" also matches "talabat mart" and "talabat egypt", and the other way round. */
export const sameMerchant = (a: string, b: string): boolean =>
  !!a && !!b && (a === b || a.startsWith(b + ' ') || b.startsWith(a + ' '))

export const merchantRules = (): Record<string, string> => store.setting<Record<string, string>>('merchantRules') ?? {}

/** The category you taught Joshu for this shop, if any. */
export function learnedCategory(title: string): string | null {
  const k = merchantKey(title)
  if (!k) return null
  const rules = merchantRules()
  return rules[k] ?? Object.entries(rules).find(([m]) => sameMerchant(k, m))?.[1] ?? null
}

/** Remembers the category for this merchant and re-files its other expenses. Returns how many changed. */
export function learnCategory(title: string, category: string): number {
  const k = merchantKey(title)
  if (!k || category === 'Income') return 0
  store.setSetting('merchantRules', { ...merchantRules(), [k]: category })
  const others = store.list<Txn>('transaction')
    .filter((t) => t.data.amount < 0 && t.data.category !== category && sameMerchant(merchantKey(t.data.title ?? ''), k))
  for (const t of others) store.update<Txn>(t.id, { category })
  return others.length
}
