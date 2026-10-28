// Ideas › Grow with AI (IdeaStore.grow in IdeasView.swift): the assistant, as a writing partner, suggests a few
// directions an idea could grow in; each is saved as a branch (a child idea) you can keep or delete.
import { useEffect, useState } from 'react'
import { store, Rec } from '@/lib/store'
import { iso } from '@/lib/dates'
import { structured, useKeys } from '@/lib/ai'
import type { Idea, IdeaProject } from '../screens/Ideas'
import { Orb } from './Orb'

export interface Growth { title: string; body: string }

/** Asks for up to 5 directions and saves them under the idea. Returns how many were added. */
export async function growIdea(ideaID: string): Promise<number> {
  const idea = store.get<Idea>(ideaID)
  const project = idea && store.get<IdeaProject>(idea.data.projectUUID)
  if (!idea || !project) return 0
  const existing = store.list<Idea>('idea').filter((i) => i.data.parentUUID === idea.id).map((i) => i.data.title)
  const p = project.data, i = idea.data
  const out = await structured<{ branches: Growth[] }>(
    "You're a writing partner helping a writer grow an idea for their project. Suggest 4 distinct directions the idea " +
    'could grow in: a twist, a deeper question, a character or detail, a scene or structure. Each has a short title ' +
    "(under 10 words) and 1-3 sentences that make it concrete. Stay true to their tone and what they've written; " +
    "don't repeat what's already there. Write in the language they write in.",
    `PROJECT: ${p.title}${p.summary ? ` — ${p.summary}` : ''}
IDEA: ${i.title}
WHAT THEY WROTE: ${i.body ? i.body.slice(0, 6000) : '(nothing yet)'}
ALREADY GROWN FROM IT: ${existing.length ? existing.join('; ') : '(nothing)'}`,
    { type: 'object', additionalProperties: false, required: ['branches'],
      properties: { branches: { type: 'array', items: {
        type: 'object', additionalProperties: false, required: ['title', 'body'],
        properties: { title: { type: 'string' }, body: { type: 'string' } } } } } },
    'medium')
  const found = out.branches.filter((g) => g.title?.trim()).slice(0, 5)
  const now = iso(new Date())
  for (const g of found) {
    store.create<Idea>('idea', { projectUUID: project.id, parentUUID: idea.id, title: g.title.trim(), body: g.body?.trim() ?? '', pinned: false, createdAt: now, updatedAt: now })
  }
  if (found.length) {
    store.update<Idea>(idea.id, { updatedAt: now })
    store.update<IdeaProject>(project.id, { updatedAt: now })
  }
  return found.length
}

// The last error per idea, so the message can sit under the header while the button sits in it.
const errors = new Map<string, string>()
const errorSubs = new Set<() => void>()
const setError = (id: string, e: string) => { if (e) errors.set(id, e); else errors.delete(id); errorSubs.forEach((f) => f()) }

/** "Grow with AI", on the right of "Grown from this" (only when the assistant is available, as on iPhone). */
export function GrowButton({ idea }: { idea: Rec<Idea> }) {
  const keys = useKeys()
  const [growing, setGrowing] = useState(false)
  if (!keys.anthropic) return null

  const grow = async () => {
    setGrowing(true); setError(idea.id, '')
    try { await growIdea(idea.id) } catch (e) { setError(idea.id, e instanceof Error ? e.message : String(e)) } finally { setGrowing(false) }
  }
  return (
    <button className="btn-soft" style={{ minHeight: 40, fontWeight: 500 }} disabled={growing} onClick={grow}>
      <Orb size={18} busy={growing} spark={false} />{growing ? 'Growing…' : 'Grow with AI'}
    </button>
  )
}

export function GrowError({ ideaID }: { ideaID: string }) {
  const [, tick] = useState(0)
  useEffect(() => { const f = () => tick((n) => n + 1); errorSubs.add(f); return () => { errorSubs.delete(f) } }, [])
  const e = errors.get(ideaID)
  return e ? <div style={{ fontSize: 12, color: 'var(--orange)' }}>{e}</div> : null
}
