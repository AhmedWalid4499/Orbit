// Bank statement import (CSV or PDF), matching the Mac's statement import so the two apps dedupe each other:
// every imported transaction has source "statement" and sourceID "stmt:" + SHA-1 hex of
// "yyyy-MM-dd|<amount with 2 decimals>|<description lowercased, trimmed>".
import { store, Rec } from './store'
import { Txn, MONEY_CATEGORIES } from './models'
import { structured } from './ai'
import { iso, parse, dayKey } from './dates'

export interface StatementRow {
  date: Date
  description: string
  /** Negative = money out. */
  amount: number
}

export type Field = 'date' | 'description' | 'amount' | 'debit' | 'credit' | 'sign' | 'ignore'
export const FIELD_LABEL: Record<Field, string> = {
  date: 'Date', description: 'Description', amount: 'Amount', debit: 'Money out (debit)', credit: 'Money in (credit)', sign: 'Debit/credit flag', ignore: 'Ignore',
}

// MARK: Ids and duplicates

export async function statementSourceID(r: StatementRow): Promise<string> {
  const key = `${dayKey(r.date)}|${r.amount.toFixed(2)}|${r.description.toLowerCase().trim()}`
  const h = new Uint8Array(await crypto.subtle.digest('SHA-1', new TextEncoder().encode(key)))
  return `stmt:${[...h].map((b) => b.toString(16).padStart(2, '0')).join('')}`
}

/** Already in Orbit: same sourceID, or a transaction within a day either side with the same amount. */
export function isDuplicate(r: StatementRow, sourceID: string, txns: Rec<Txn>[]): boolean {
  return txns.some((t) => {
    if (t.data.sourceID === sourceID) return true
    const d = parse(t.data.date)
    return !!d && dayDiff(d, r.date) <= 1 && Math.abs(t.data.amount - r.amount) < 0.005
  })
}
const dayDiff = (a: Date, b: Date) => Math.abs(Math.round((new Date(a.getFullYear(), a.getMonth(), a.getDate()).getTime() - new Date(b.getFullYear(), b.getMonth(), b.getDate()).getTime()) / 86_400_000))

// MARK: Categories

/** Keyword guess, same table as QuickParser.guessCategory on the Mac. */
export function guessCategory(title: string, amount: number): string {
  if (amount > 0) return 'Income'
  const t = title.toLowerCase()
  const map: [string, string[]][] = [
    ['Food', ['lunch', 'dinner', 'breakfast', 'coffee', 'grocer', 'food', 'restaurant', 'snack']],
    ['Transport', ['uber', 'taxi', 'fuel', 'gas', 'metro', 'bus', 'train', 'careem', 'parking']],
    ['Bills', ['rent', 'electric', 'water', 'internet', 'phone', 'bill']],
    ['Subscriptions', ['netflix', 'spotify', 'icloud', 'subscription', 'youtube', 'claude', 'gym membership']],
    ['Health', ['pharmacy', 'doctor', 'dentist', 'gym', 'medicine']],
    ['Fun', ['cinema', 'movie', 'game', 'concert', 'bar']],
    ['Shopping', ['amazon', 'clothes', 'shoes', 'shop']],
  ]
  return map.find(([, words]) => words.some((w) => t.includes(w)))?.[0] ?? 'General'
}

/** One Claude call for the whole batch. */
export async function categorize(rows: StatementRow[]): Promise<string[]> {
  const r = await structured<{ categories: string[] }>(
    `You categorise bank statement lines for a personal budgeting app. For each numbered line return exactly one category from: ${MONEY_CATEGORIES.join(', ')}.
Money in (positive amounts) is usually Income unless it's clearly a refund of a purchase. Use General when unsure. Return the categories in the same order, one per line.`,
    rows.map((r, i) => `${i + 1}. ${r.description} | ${r.amount.toFixed(2)}`).join('\n'),
    { type: 'object', properties: { categories: { type: 'array', items: { type: 'string', enum: MONEY_CATEGORIES } } }, required: ['categories'], additionalProperties: false },
    'low')
  return rows.map((row, i) => r.categories[i] ?? guessCategory(row.description, row.amount))
}

// MARK: Numbers and dates

const ARABIC_DIGITS = '٠١٢٣٤٥٦٧٨٩', PERSIAN_DIGITS = '۰۱۲۳۴۵۶۷۸۹'
const westernDigits = (s: string) => s.replace(/[٠-٩۰-۹]/g, (c) => String(Math.max(ARABIC_DIGITS.indexOf(c), PERSIAN_DIGITS.indexOf(c))))
  .replace(/٫/g, '.').replace(/٬/g, ',')

/** "1,234.50", "(12.00)", "-12", "12.00-", "1.234,50", "EGP 99", "45.00 DR" → number, or null. */
export function parseAmount(raw: string): number | null {
  let s = westernDigits(raw ?? '').trim()
  if (!s) return null
  let neg = false
  if (/^\(.*\)$/.test(s)) { neg = true; s = s.slice(1, -1) }
  if (/\b(dr|debit)\b\.?$/i.test(s)) { neg = true; s = s.replace(/\b(dr|debit)\b\.?$/i, '') }
  s = s.replace(/\b(cr|credit)\b\.?$/i, '')
  if (/-\s*$/.test(s)) { neg = true; s = s.replace(/-\s*$/, '') }
  if (/^\s*[-−–]/.test(s)) { neg = !neg; s = s.replace(/^\s*[-−–]/, '') }
  s = s.replace(/[^\d.,-]/g, '')
  if (!/\d/.test(s)) return null
  const lastDot = s.lastIndexOf('.'), lastComma = s.lastIndexOf(',')
  if (lastDot >= 0 && lastComma >= 0) {
    s = lastComma > lastDot ? s.replace(/\./g, '').replace(',', '.') : s.replace(/,/g, '')
  } else if (lastComma >= 0) {
    s = /,\d{1,2}$/.test(s) && (s.match(/,/g) ?? []).length === 1 ? s.replace(',', '.') : s.replace(/,/g, '')
  } else if ((s.match(/\./g) ?? []).length > 1) {
    s = s.replace(/\./g, '')
  }
  const n = Number(s)
  if (!isFinite(n)) return null
  return neg ? -n : n
}

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec']
const year4 = (y: number) => (y < 100 ? 2000 + y : y)

/** Day-first (dd/mm) or month-first (mm/dd), decided per column. */
export type DateOrder = 'dmy' | 'mdy'

export function parseDate(raw: string, order: DateOrder = 'dmy'): Date | null {
  const s = westernDigits(raw ?? '').trim().replace(/\s+/g, ' ')
  if (!s) return null
  let m = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/.exec(s)
  if (m) return mk(+m[1], +m[2], +m[3])
  m = /^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})/.exec(s)
  if (m) return order === 'mdy' ? mk(year4(+m[3]), +m[1], +m[2]) : mk(year4(+m[3]), +m[2], +m[1])
  m = /^(\d{1,2})[ -]([A-Za-z]{3,9})\.?[ -,]*(\d{2,4})/.exec(s)
  if (m) { const mo = MONTHS.indexOf(m[2].slice(0, 3).toLowerCase()); if (mo >= 0) return mk(year4(+m[3]), mo + 1, +m[1]) }
  m = /^([A-Za-z]{3,9})\.? (\d{1,2}),? (\d{2,4})/.exec(s)
  if (m) { const mo = MONTHS.indexOf(m[1].slice(0, 3).toLowerCase()); if (mo >= 0) return mk(year4(+m[3]), mo + 1, +m[2]) }
  return null
}
function mk(y: number, mo: number, d: number): Date | null {
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null
  const r = new Date(y, mo - 1, d, 12)
  return r.getMonth() === mo - 1 ? r : null
}

/** mm/dd when some value can only be month-first, otherwise day-first. */
export function detectOrder(values: string[]): DateOrder {
  let dmy = false, mdy = false
  for (const v of values) {
    const m = /^(\d{1,2})[-/.](\d{1,2})[-/.]\d{2,4}/.exec(westernDigits(v.trim()))
    if (!m) continue
    if (+m[1] > 12) dmy = true
    if (+m[2] > 12) mdy = true
  }
  return mdy && !dmy ? 'mdy' : 'dmy'
}

// MARK: CSV

export function parseCSV(text: string): string[][] {
  const clean = text.replace(/^\uFEFF/, '')
  const sample = clean.split(/\r?\n/).slice(0, 20).join('\n')
  const delim = [',', ';', '\t', '|'].map((d) => [d, sample.split(d).length] as const).sort((a, b) => b[1] - a[1])[0][0]
  const rows: string[][] = []
  let row: string[] = [], cell = '', quoted = false
  for (let i = 0; i < clean.length; i++) {
    const c = clean[i]
    if (quoted) {
      if (c === '"' && clean[i + 1] === '"') { cell += '"'; i++ } else if (c === '"') quoted = false
      else cell += c
    } else if (c === '"') quoted = true
    else if (c === delim) { row.push(cell.trim()); cell = '' }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && clean[i + 1] === '\n') i++
      row.push(cell.trim()); cell = ''
      if (row.some((x) => x)) rows.push(row)
      row = []
    } else cell += c
  }
  row.push(cell.trim())
  if (row.some((x) => x)) rows.push(row)
  return rows
}

const HEADER_WORDS: [Field, RegExp][] = [
  ['sign', /^(debit\s*\/\s*credit|withdrawals?\s*\/\s*deposits?|dr\s*\/\s*cr|credit\s*\/\s*debit|type|نوع|مدين\s*\/\s*دائن)$/i],
  ['date', /(date|posted|booked|تاريخ|التاريخ)/i],
  ['debit', /(debit|withdraw|money out|paid out|^out$|مدين|سحب|مسحوب|خصم)/i],
  ['credit', /(credit|deposit|money in|paid in|^in$|دائن|إيداع|ايداع|مودع)/i],
  ['amount', /(amount|value|sum|المبلغ|القيمة|مبلغ)/i],
  ['description', /(description|details|narrative|narration|merchant|payee|memo|particulars|transaction|reference|remarks|البيان|الوصف|التفاصيل|بيان)/i],
]

export interface CSVGuess { header: number; mapping: Field[]; order: DateOrder }

/** Finds the header row and guesses what each column is. */
export function guessColumns(rows: string[][]): CSVGuess {
  let best = { header: -1, mapping: [] as Field[], score: 0 }
  for (let i = 0; i < Math.min(rows.length, 30); i++) {
    const mapping = rows[i].map((h) => {
      const v = h.trim()
      if (!v || v.length > 40) return 'ignore' as Field
      // "Withdrawals/Deposits" or "Debit/Credit" in one header is a sign column only next to an amount column; decided below.
      for (const [f, re] of HEADER_WORDS) if (re.test(v)) return f
      return 'ignore' as Field
    })
    const has = (f: Field) => mapping.includes(f)
    const score = (has('date') ? 2 : 0) + (has('amount') || has('debit') || has('credit') || has('sign') ? 2 : 0) + (has('description') ? 1 : 0)
    if (score > best.score) best = { header: i, mapping, score }
    if (score >= 5) break
  }
  let { header, mapping } = best
  if (best.score < 3 || !best.mapping.some((f) => ['amount', 'debit', 'credit', 'sign'].includes(f))) { header = -1; mapping = guessByContent(rows) }
  else {
    if (!mapping.includes('date')) {
      const byContent = guessByContent(rows.slice(header + 1)).indexOf('date')
      if (byContent >= 0 && mapping[byContent] === 'ignore') mapping[byContent] = 'date'
    }
    // Keep one of each, except debit/credit; a "Debit/Credit" flag needs an amount column, else it is the amount.
    const seen = new Set<Field>()
    mapping = mapping.map((f) => (f !== 'ignore' && seen.has(f) ? 'ignore' : (seen.add(f), f)))
    if (mapping.includes('sign') && !mapping.includes('amount')) mapping = mapping.map((f) => (f === 'sign' ? 'amount' : f))
    if (!mapping.includes('description')) {
      const body = rows.slice(header + 1, header + 30)
      let bestCol = -1, bestLen = 0
      mapping.forEach((f, c) => {
        if (f !== 'ignore') return
        const len = body.reduce((n, r) => n + (r[c]?.length ?? 0), 0)
        if (len > bestLen) { bestLen = len; bestCol = c }
      })
      if (bestCol >= 0) mapping[bestCol] = 'description'
    }
  }
  const dateCol = mapping.indexOf('date')
  const order = detectOrder(rows.slice(header + 1).map((r) => r[dateCol] ?? ''))
  return { header, mapping, order }
}

function guessByContent(rows: string[][]): Field[] {
  const body = rows.slice(0, 40)
  const cols = Math.max(...body.map((r) => r.length))
  const mapping: Field[] = new Array(cols).fill('ignore')
  const ratio = (c: number, test: (v: string) => boolean) => body.filter((r) => r[c] && test(r[c])).length / Math.max(1, body.filter((r) => r[c]).length)
  let dateCol = -1, amountCol = -1, descCol = -1, descLen = 0
  for (let c = 0; c < cols; c++) {
    if (dateCol < 0 && ratio(c, (v) => !!(parseDate(v) ?? parseDate(v, 'mdy'))) > 0.6) { dateCol = c; continue }
    if (ratio(c, (v) => parseAmount(v) !== null && /\d/.test(v) && !/[A-Za-z]{3,}/.test(v)) > 0.6) { if (amountCol < 0) amountCol = c; continue }
    const len = body.reduce((n, r) => n + (r[c]?.length ?? 0), 0)
    if (len > descLen) { descLen = len; descCol = c }
  }
  if (dateCol >= 0) mapping[dateCol] = 'date'
  if (amountCol >= 0) mapping[amountCol] = 'amount'
  if (descCol >= 0) mapping[descCol] = 'description'
  return mapping
}

const SIGN_OUT = /^(dr|d|debit|withdrawal|out|مدين|سحب|خصم)$/i

/** Applies a column mapping to the rows below the header. */
export function rowsFromCSV(rows: string[][], g: CSVGuess): StatementRow[] {
  const col = (f: Field) => g.mapping.indexOf(f)
  const [dc, sc, ac, dbc, crc, sgc] = [col('date'), col('description'), col('amount'), col('debit'), col('credit'), col('sign')]
  const out: StatementRow[] = []
  for (const r of rows.slice(g.header + 1)) {
    const date = dc >= 0 ? parseDate(r[dc] ?? '', g.order) : null
    if (!date) continue
    let amount: number | null = null
    if (ac >= 0) {
      amount = parseAmount(r[ac] ?? '')
      if (amount !== null && sgc >= 0) amount = SIGN_OUT.test((r[sgc] ?? '').trim()) ? -Math.abs(amount) : Math.abs(amount)
    }
    if (amount === null && (dbc >= 0 || crc >= 0)) {
      const debit = dbc >= 0 ? parseAmount(r[dbc] ?? '') : null
      const credit = crc >= 0 ? parseAmount(r[crc] ?? '') : null
      if (debit) amount = -Math.abs(debit)
      else if (credit) amount = Math.abs(credit)
    }
    if (amount === null || amount === 0) continue
    const description = (sc >= 0 ? r[sc] : '')?.replace(/\s+/g, ' ').trim() || 'Bank transaction'
    out.push({ date, description, amount: Math.round(amount * 100) / 100 })
  }
  return out
}

// MARK: PDF

export async function pdfText(file: File): Promise<string> {
  const pdfjs = await import('pdfjs-dist')
  // Run pdf.js in this thread (statements are small), so no worker file has to be loaded from disk.
  ;(globalThis as any).pdfjsWorker ??= await import('pdfjs-dist/build/pdf.worker.min.mjs')
  const doc = await pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()) }).promise
  const pages: string[] = []
  for (let p = 1; p <= doc.numPages; p++) {
    const content = await (await doc.getPage(p)).getTextContent()
    // Rebuild lines from text positions (same y = same line), left to right.
    const lines = new Map<number, { x: number; s: string }[]>()
    for (const it of content.items as { str: string; transform: number[] }[]) {
      if (!it.str?.trim()) continue
      const y = Math.round(it.transform[5] / 2) * 2
      lines.set(y, [...(lines.get(y) ?? []), { x: it.transform[4], s: it.str }])
    }
    pages.push([...lines].sort((a, b) => b[0] - a[0]).map(([, parts]) => parts.sort((a, b) => a.x - b.x).map((x) => x.s).join('  ')).join('\n'))
  }
  return pages.join('\n\n')
}

/** Claude reads the statement text and returns the transactions. */
export async function rowsFromPDFText(text: string): Promise<StatementRow[]> {
  const r = await structured<{ rows: { date: string; description: string; amount: number }[] }>(
    `You extract transactions from the text of a bank or card statement. Return every transaction line, in order.
- date: yyyy-MM-dd (statements may use dd/mm/yyyy; work out the order from the whole statement).
- description: the merchant or narrative, cleaned up but not invented.
- amount: a number; negative for money out (debits, purchases, withdrawals, fees), positive for money in.
Skip opening/closing balances, running balances, totals and page headers. Never invent rows.`,
    text.slice(0, 150_000),
    {
      type: 'object',
      properties: { rows: { type: 'array', items: { type: 'object', properties: { date: { type: 'string' }, description: { type: 'string' }, amount: { type: 'number' } }, required: ['date', 'description', 'amount'], additionalProperties: false } } },
      required: ['rows'], additionalProperties: false,
    }, 'medium', 32000)
  return r.rows.map((x) => ({ date: parseDate(x.date), description: x.description.trim(), amount: Math.round(x.amount * 100) / 100 }))
    .filter((x): x is StatementRow => !!x.date && !!x.amount)
}

// MARK: Import

export interface PreviewRow extends StatementRow { sourceID: string; duplicate: boolean; checked: boolean; category: string }

export async function preview(rows: StatementRow[]): Promise<PreviewRow[]> {
  const txns = store.list<Txn>('transaction')
  return Promise.all(rows.map(async (r) => {
    const sourceID = await statementSourceID(r)
    const duplicate = isDuplicate(r, sourceID, txns)
    return { ...r, sourceID, duplicate, checked: !duplicate, category: guessCategory(r.description, r.amount) }
  }))
}

export function importRows(rows: PreviewRow[]): number {
  let n = 0
  for (const r of rows) {
    if (!r.checked) continue
    store.create<Txn>('transaction', {
      title: r.description, amount: r.amount, category: r.category, date: iso(r.date), isRecurring: false,
      source: 'statement', sourceID: r.sourceID, originalAmount: 0, originalCurrency: '',
    })
    n++
  }
  return n
}
