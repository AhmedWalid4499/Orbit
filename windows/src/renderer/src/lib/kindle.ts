// Kindle highlights import, ported from KindleHighlights in ReadingExtras.swift (Mac) so both apps
// read the same files the same way and produce the same externalIDs (re-importing on either skips duplicates).
// - "My Clippings.txt" from a Kindle e-reader
// - a notebook export from the Kindle app (Notebook › Share › Export notebook, an HTML file)
import { store, Rec } from './store'
import { Book, Highlight, matchKey } from './models'
import { iso } from './dates'

export interface ParsedHighlight {
  bookTitle: string
  author: string
  text: string
  note: string
  location: string
  date: Date | null
}

export class KindleError extends Error {}

/** Reads a file (UTF-8, or UTF-16 with a byte-order mark) and parses it. */
export async function parseKindleFile(file: File): Promise<ParsedHighlight[]> {
  const bytes = new Uint8Array(await file.arrayBuffer())
  let raw: string
  if (bytes[0] === 0xff && bytes[1] === 0xfe) raw = new TextDecoder('utf-16le').decode(bytes)
  else if (bytes[0] === 0xfe && bytes[1] === 0xff) raw = new TextDecoder('utf-16be').decode(bytes)
  else {
    try { raw = new TextDecoder('utf-8', { fatal: true }).decode(bytes) } catch { throw new KindleError("Couldn't read that file.") }
  }
  return parseKindleText(raw)
}

export function parseKindleText(raw: string): ParsedHighlight[] {
  const text = raw.replace(/\uFEFF/g, '')
  if (text.includes('noteText') || text.toLowerCase().includes('<html')) return parseNotebookHTML(text)
  if (text.includes('==========')) return parseClippings(text)
  throw new KindleError('That isn’t a Kindle “My Clippings.txt” or notebook export.')
}

const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december']

/** "EEEE, d MMMM yyyy HH:mm:ss" (en_US_POSIX, local time), the only format the Mac reads. */
function parseAddedOn(s: string): Date | null {
  const m = /^[A-Za-z]+, (\d{1,2}) ([A-Za-z]+) (\d{4}) (\d{1,2}):(\d{2}):(\d{2})$/.exec(s)
  if (!m) return null
  const month = MONTHS.indexOf(m[2].toLowerCase())
  if (month < 0) return null
  const d = new Date(Number(m[3]), month, Number(m[1]), Number(m[4]), Number(m[5]), Number(m[6]))
  return isNaN(d.getTime()) ? null : d
}

/** Kindle e-reader format: title (author) / - Your Highlight on … | Location 10-12 | Added on … / blank / text / ========== */
export function parseClippings(text: string): ParsedHighlight[] {
  const out: ParsedHighlight[] = []
  for (const entry of text.split('==========')) {
    // Kindle starts each title line with an invisible byte-order mark.
    const lines = entry.split(/\r\n|[\n\r\u000B\u000C\u0085\u2028\u2029]/)
      .map((l) => l.replace(/\uFEFF/g, '').replace(/^[ \t]+|[ \t]+$/g, ''))
      .filter((l) => l.length > 0)
    if (lines.length < 3) continue
    const [title, author] = splitTitle(lines[0])
    const meta = lines[1].toLowerCase()
    const body = lines.slice(2).join('\n')
    const location = position(lines[1])
    const added = lines[1].split('Added on ')
    const date = added.length > 1 ? parseAddedOn(added[added.length - 1].trim()) : null
    if (meta.includes('bookmark')) continue
    if (meta.includes('note')) {
      // A note belongs to the highlight just before it (same book, no note yet).
      let i = -1
      for (let j = out.length - 1; j >= 0; j--) if (out[j].bookTitle === title && !out[j].note) { i = j; break }
      if (i >= 0) { out[i].note = body; continue }
    }
    out.push({ bookTitle: title, author, text: body, note: '', location, date })
  }
  return out
}

/** Kindle app notebook export (HTML with bookTitle / authors / noteHeading / noteText). */
export function parseNotebookHTML(html: string): ParsedHighlight[] {
  const strip = (s: string): string => s.replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&').replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&nbsp;/g, ' ')
    .trim()
  const first = (cls: string): string => {
    const m = new RegExp(`class=['"]${cls}['"][^>]*>([\\s\\S]*?)</div>`).exec(html)
    if (!m) return ''
    return strip(m[0].replace(/^class=['"][^'"]+['"][^>]*>/, ''))
  }
  const title = first('bookTitle'), author = first('authors')
  const out: ParsedHighlight[] = []
  const re = /class=['"]noteHeading['"][^>]*>([\s\S]*?)<\/div>\s*<div class=['"]noteText['"][^>]*>([\s\S]*?)<\/(?:div|h3)>/g
  for (let m = re.exec(html); m; m = re.exec(html)) {
    const heading = strip(m[1])
    const body = strip(m[2])
    if (!body) continue
    const location = position(heading)
    if (heading.toLowerCase().startsWith('note') && out.length) out[out.length - 1].note = body
    else out.push({ bookTitle: title, author, text: body, note: '', location, date: null })
  }
  return out
}

/** "Location 410-412" when there is one, otherwise "Page 27". */
function position(text: string): string {
  for (const p of [/(location|loc\.)\s*[\d-]+/i, /page\s*[\d-]+/i]) {
    const m = p.exec(text)
    if (m) return m[0]
  }
  return ''
}

function splitTitle(line: string): [string, string] {
  const open = line.lastIndexOf(' (')
  if (!line.endsWith(')') || open < 0) return [line, '']
  return [line.slice(0, open), line.slice(open + 2, -1)]
}

/** First n characters as Swift counts them (grapheme clusters), so ids match the Mac's String.prefix. */
function prefix(s: string, n: number): string {
  const seg = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
  let out = '', i = 0
  for (const g of seg.segment(s)) { if (i++ >= n) break; out += g.segment }
  return out
}

/** Same stable key as the Mac, so re-importing on either app doesn't duplicate. */
export const kindleExternalID = (p: ParsedHighlight): string =>
  `kindle:${prefix(p.bookTitle.toLowerCase(), 60)}|${p.location}|${prefix(p.text, 80)}`

/** Adds new highlights, linking them to books already in your library. Returns [added, skipped as duplicates]. */
export function importHighlights(items: ParsedHighlight[], source: string): [number, number] {
  const existing = new Set(store.list<Highlight>('highlight').map((h) => h.data.externalID))
  const books = store.list<Book>('book')
  const byKey = new Map<string, Rec<Book>>()
  for (const b of books) { const k = matchKey(b.data.title ?? '', b.data.author ?? ''); if (!byKey.has(k)) byKey.set(k, b) }
  let added = 0, skipped = 0
  for (const p of items) {
    const id = kindleExternalID(p)
    if (existing.has(id)) { skipped++; continue }
    existing.add(id)
    const book = byKey.get(matchKey(p.bookTitle, p.author))
      ?? books.find((b) => (b.data.title ?? '').localeCompare(p.bookTitle, undefined, { sensitivity: 'accent' }) === 0)
    store.create<Highlight>('highlight', {
      bookUUID: book?.id ?? '', bookTitle: book?.data.title ?? p.bookTitle, author: p.author, text: p.text, note: p.note,
      location: p.location, createdAt: iso(p.date ?? new Date()), source, externalID: id,
    })
    added++
  }
  return [added, skipped]
}
