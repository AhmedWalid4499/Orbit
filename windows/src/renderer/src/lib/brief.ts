// Morning brief: same prompt and schema as the Mac (AIAssistant.refreshBrief), generated once a day.
import { useEffect, useState } from 'react'
import { structured } from './ai'
import { daySnapshot } from './snapshot'
import { dayKey } from './dates'

export interface Brief { headline: string; summary: string; focus: string[]; heads_up: string; day: string; generatedAt: string }

const KEY = 'orbit.brief'
const SYSTEM = `You write the morning brief at the top of a personal life-organizer app. The reader is the app's owner.
Use only the data provided; never invent events, tasks or numbers. Write like a thoughtful friend: warm, concrete, short.
- headline: at most 8 words capturing the shape of the day.
- summary: 2-3 sentences covering what's on today and anything time-sensitive.
- focus: up to 3 specific, doable suggestions for today, drawn from the tasks, habits, and money data. Each under 14 words.
- heads_up: one thing that could slip (overdue task, budget pace, broken streak), or an empty string if nothing stands out.
Plain text only, no markdown.`
const SCHEMA = {
  type: 'object',
  properties: { headline: { type: 'string' }, summary: { type: 'string' }, focus: { type: 'array', items: { type: 'string' } }, heads_up: { type: 'string' } },
  required: ['headline', 'summary', 'focus', 'heads_up'],
  additionalProperties: false,
}

const cached = (): Brief | null => { try { return JSON.parse(localStorage.getItem(KEY) ?? 'null') } catch { return null } }
let loading: Promise<void> | null = null

export function useBrief(enabled: boolean): { brief: Brief | null; loading: boolean; error: string; refresh: () => void } {
  const [brief, setBrief] = useState<Brief | null>(cached())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const run = (force: boolean) => {
    if (!enabled || loading) return
    const c = cached()
    if (!force && c?.day === dayKey(new Date())) { setBrief(c); return }
    setBusy(true)
    setError('')
    loading = structured<Omit<Brief, 'day' | 'generatedAt'>>(SYSTEM, daySnapshot(), SCHEMA, 'medium')
      .then((b) => {
        const full: Brief = { ...b, day: dayKey(new Date()), generatedAt: new Date().toISOString() }
        localStorage.setItem(KEY, JSON.stringify(full))
        setBrief(full)
      })
      .catch((e) => setError(e.message))
      .finally(() => { loading = null; setBusy(false) })
  }

  // Wait a moment after opening so synced data has arrived before writing the brief.
  useEffect(() => { const t = setTimeout(() => run(false), 2500); return () => clearTimeout(t) }, [enabled])
  return { brief: brief?.day === dayKey(new Date()) ? brief : null, loading: busy, error, refresh: () => run(true) }
}
