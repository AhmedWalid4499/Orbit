// Date helpers. ISO strings are written without milliseconds because the Mac app's parser
// (ISO8601DateFormatter) doesn't accept fractional seconds.

export const iso = (d: Date): string => d.toISOString().replace(/\.\d{3}Z$/, 'Z')
export const parse = (s: string | null | undefined): Date | null => {
  if (!s) return null
  const d = new Date(s)
  return isNaN(d.getTime()) ? null : d
}

export const startOfDay = (d: Date): Date => new Date(d.getFullYear(), d.getMonth(), d.getDate())
export const addDays = (d: Date, n: number): Date => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes())
export const addMinutes = (d: Date, n: number): Date => new Date(d.getTime() + n * 60_000)
export const addMonths = (d: Date, n: number): Date => {
  const first = new Date(d.getFullYear(), d.getMonth() + n, 1, d.getHours(), d.getMinutes())
  return new Date(first.getFullYear(), first.getMonth(), Math.min(d.getDate(), daysInMonth(first)), d.getHours(), d.getMinutes())
}
export const sameDay = (a: Date, b: Date): boolean => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
export const isToday = (d: Date): boolean => sameDay(d, new Date())
export const startOfMonth = (d: Date): Date => new Date(d.getFullYear(), d.getMonth(), 1)
export const daysInMonth = (d: Date): number => new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()

/** First day of the week for your region (0 = Sunday … 6 = Saturday). */
export const firstWeekday: number = (() => {
  try {
    const loc = new Intl.Locale(navigator.language) as any
    const info = loc.getWeekInfo?.() ?? loc.weekInfo
    if (info?.firstDay) return info.firstDay % 7
  } catch { /* fall back */ }
  return 1
})()

export const startOfWeek = (d: Date): Date => {
  const s = startOfDay(d)
  return addDays(s, -((s.getDay() - firstWeekday + 7) % 7))
}

/** "yyyy-MM-dd" in local time: the key the Mac uses for habit check-ins. */
export const dayKey = (d: Date): string =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
export const fromDayKey = (k: string): Date => { const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d) }

export const daysBetween = (a: Date, b: Date): number => Math.round((startOfDay(b).getTime() - startOfDay(a).getTime()) / 86_400_000)

export const fmtTime = (d: Date): string => d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })
export const fmtDay = (d: Date, opts: Intl.DateTimeFormatOptions = { weekday: 'long', day: 'numeric', month: 'long' }): string =>
  d.toLocaleDateString(undefined, opts)

export function relativeDay(d: Date): string {
  const n = daysBetween(new Date(), d)
  if (n === 0) return 'Today'
  if (n === 1) return 'Tomorrow'
  if (n === -1) return 'Yesterday'
  if (n > 0 && n < 7) return d.toLocaleDateString(undefined, { weekday: 'long' })
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
}

export function relativeTime(d: Date): string {
  const s = Math.round((d.getTime() - Date.now()) / 1000)
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' })
  const a = Math.abs(s)
  if (a < 60) return rtf.format(Math.round(s), 'second')
  if (a < 3600) return rtf.format(Math.round(s / 60), 'minute')
  if (a < 86400) return rtf.format(Math.round(s / 3600), 'hour')
  return rtf.format(Math.round(s / 86400), 'day')
}

/** Local date+time from <input type="date"> and <input type="time"> values. */
export const fromInputs = (date: string, time = '00:00'): Date => {
  const [y, m, d] = date.split('-').map(Number)
  const [h, min] = time.split(':').map(Number)
  return new Date(y, m - 1, d, h || 0, min || 0)
}
export const toDateInput = (d: Date): string => dayKey(d)
export const toTimeInput = (d: Date): string => `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
