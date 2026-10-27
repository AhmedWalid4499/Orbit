// Ideas, like IdeasView.swift on the Mac: writing projects and the ideas in them. Jot an idea down, open it to keep
// writing, and let it grow into smaller ideas (parentUUID is the idea it grew from; "" for a top-level one).
import { GrowButton } from '../components/GrowIdeas'
import { useState } from 'react'
import { Plus, Pencil, Pin, PinOff, Lightbulb, GitBranch, CornerDownRight, ChevronLeft, Archive, Trash2 } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { iso, parse, relativeTime } from '@/lib/dates'
import { Modal } from '@/components/ui'

export interface IdeaProject { title: string; summary: string; colorIndex: number; archived: boolean; createdAt: string; updatedAt: string }
export interface Idea { projectUUID: string; parentUUID: string; title: string; body: string; pinned: boolean; createdAt: string; updatedAt: string }

// Same order as the Mac's tints (lime, cyan, pink, peach, lavender, mint, sand).
const TINTS = ['var(--lime)', 'var(--cyan)', 'var(--pink)', 'var(--peach)', 'var(--purple)', 'var(--mint)', 'var(--orange)']
const tint = (i: number) => TINTS[((i % TINTS.length) + TINTS.length) % TINTS.length]
const time = (s: string | null | undefined) => parse(s)?.getTime() ?? 0

const ls = {
  get: (k: string) => { try { return localStorage.getItem(k) ?? '' } catch { return '' } },
  set: (k: string, v: string) => { try { localStorage.setItem(k, v) } catch { /* private mode */ } },
}

// MARK: Making projects and ideas (IdeaStore on the Mac)

function newProject(title: string, summary: string, colorIndex: number): string {
  const now = iso(new Date())
  return store.create<IdeaProject>('ideaProject', { title, summary, colorIndex, archived: false, createdAt: now, updatedAt: now })
}

/** Adds an idea. A long text is split into a short title and the rest as its page. */
function addIdea(text: string, projectID: string, parentID = ''): void {
  let title = text, body = ''
  if (text.length > 90) {
    const first = text.split(/[.!?\n]/)[0] ?? text
    title = first.length <= 90 ? first : text.slice(0, 80) + '…'
    body = text
  }
  const now = iso(new Date())
  store.create<Idea>('idea', { projectUUID: projectID, parentUUID: parentID, title: title.trim(), body, pinned: false, createdAt: now, updatedAt: now })
  store.update<IdeaProject>(projectID, { updatedAt: now })
  if (parentID) store.update<Idea>(parentID, { updatedAt: now })
}

// MARK: Screen

export default function Ideas() {
  const projects = useRecords<IdeaProject>('ideaProject').sort((a, b) => time(b.data.updatedAt) - time(a.data.updatedAt))
  const ideas = useRecords<Idea>('idea')
  const [selectedID, setSelectedID] = useState(() => ls.get('ideas.selected'))
  const [creating, setCreating] = useState(false)
  const [editingProject, setEditingProject] = useState<Rec<IdeaProject> | null>(null)
  const [showArchived, setShowArchived] = useState(false)
  const [open, setOpen] = useState<string | null>(null)
  const [newIdea, setNewIdea] = useState('')

  const live = projects.filter((p) => !p.data.archived), archived = projects.filter((p) => p.data.archived)
  const selected = live.find((p) => p.id === selectedID) ?? live[0]
  const select = (id: string) => { setSelectedID(id); ls.set('ideas.selected', id) }

  const mine = selected ? ideas.filter((i) => i.data.projectUUID === selected.id) : []
  const top = mine.filter((i) => !i.data.parentUUID)
    .sort((a, b) => (+b.data.pinned - +a.data.pinned) || time(b.data.updatedAt) - time(a.data.updatedAt))

  const add = () => {
    const t = newIdea.trim()
    if (!t || !selected) return
    addIdea(t, selected.id)
    setNewIdea('')
  }

  return (
    <div className="page">
      <div className="col" style={{ gap: 16 }}>
        <h1 className="page-title">Ideas</h1>
        {/* Projects */}
        <div className="row" style={{ gap: 8, overflowX: 'auto', paddingBottom: 2 }}>
          {live.map((p) => {
            const on = selected?.id === p.id
            return (
              <button key={p.id} onClick={() => select(p.id)} className="clamp1"
                style={{ flex: 'none', maxWidth: 220, minHeight: 40, padding: '8px 14px', borderRadius: 999, fontSize: 13, fontWeight: 600,
                  background: on ? tint(p.data.colorIndex) : 'var(--card)', color: on ? 'var(--sticker-ink)' : 'var(--ink)' }}>
                {p.data.title || 'Untitled'}
              </button>
            )
          })}
          <button className="btn-soft" style={{ flex: 'none', minHeight: 40 }} onClick={() => setCreating(true)}><Plus size={14} />Project</button>
          {archived.length > 0 && (
            <button className="btn-soft" style={{ flex: 'none', minHeight: 40 }} onClick={() => setShowArchived(true)}><Archive size={14} />{archived.length}</button>
          )}
        </div>

        {!selected && (
          <div className="card col" style={{ gap: 12, padding: 24 }}>
            <span style={{ width: 64, height: 64, borderRadius: '50%', background: 'var(--lime)', color: 'var(--sticker-ink)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
              <Lightbulb size={30} />
            </span>
            <div className="display" style={{ fontSize: 26 }}>Where your ideas grow</div>
            <div className="secondary" style={{ fontSize: 14 }}>
              Make a project for each thing you're writing. Drop ideas in whenever they come. Open an idea to keep writing on it and grow it into more.
            </div>
            <button className="btn-primary" style={{ alignSelf: 'flex-start', minHeight: 40 }} onClick={() => setCreating(true)}><Plus size={14} />New project</button>
          </div>
        )}

        {selected && (
          <>
            <div className="col" style={{ gap: 4 }}>
              <div className="row" style={{ gap: 6 }}>
                <div className="display" style={{ fontSize: 26, minWidth: 0 }}>{selected.data.title}</div>
                <button className="icon-btn" style={{ width: 40, height: 40, flex: 'none' }} onClick={() => setEditingProject(selected)} title="Edit project"><Pencil size={15} /></button>
              </div>
              {selected.data.summary && <div className="secondary" style={{ fontSize: 14 }}>{selected.data.summary}</div>}
              <div className="muted" style={{ fontSize: 12 }}>
                {top.length} idea{top.length === 1 ? '' : 's'} · {mine.length - top.length} grown from them
              </div>
            </div>
            <div className="row card" style={{ gap: 10, padding: 12, alignItems: 'flex-end' }}>
              <textarea className="plain" rows={Math.min(4, Math.max(1, newIdea.split('\n').length))} placeholder={`A new idea for ${selected.data.title}…`}
                value={newIdea} onChange={(e) => setNewIdea(e.target.value)} style={{ flex: 1, fontSize: 15, resize: 'none', background: 'transparent', border: 'none', outline: 'none', color: 'var(--ink)', padding: '8px 0' }} />
              <button className="btn-primary" style={{ minHeight: 40 }} disabled={!newIdea.trim()} onClick={add}>Add</button>
            </div>
            {!top.length && <div className="secondary" style={{ fontSize: 13 }}>No ideas yet. The first one is the hardest; write anything.</div>}
            {top.map((i) => {
              const branches = mine.filter((x) => x.data.parentUUID === i.id).length
              return (
                <button key={i.id} onClick={() => setOpen(i.id)} className="col"
                  style={{ gap: 8, padding: '14px 14px 14px 18px', borderRadius: 18, background: 'var(--card)', textAlign: 'left', color: 'var(--ink)', position: 'relative', alignItems: 'stretch' }}>
                  <span style={{ position: 'absolute', left: 0, top: 14, bottom: 14, width: 4, borderRadius: 2, background: tint(selected.data.colorIndex) }} />
                  <div className="row" style={{ alignItems: 'flex-start' }}>
                    <span className="clamp2" style={{ fontSize: 16, fontWeight: 600, flex: 1 }}>{i.data.title}</span>
                    {i.data.pinned && <Pin size={12} className="muted" />}
                  </div>
                  {i.data.body && <div className="secondary" style={{ fontSize: 13, display: '-webkit-box', WebkitLineClamp: 4, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{i.data.body}</div>}
                  <div className="row secondary" style={{ gap: 10, fontSize: 11 }}>
                    {branches > 0 && <span className="row" style={{ gap: 3, fontWeight: 600 }}><GitBranch size={12} />{branches}</span>}
                    <span className="muted">{parse(i.data.updatedAt) ? relativeTime(parse(i.data.updatedAt)!) : ''}</span>
                  </div>
                </button>
              )
            })}
          </>
        )}
      </div>

      {open && <IdeaSheet first={open} ideas={ideas} projects={projects} onClose={() => setOpen(null)} />}
      {creating && <ProjectEditor project={null} ideas={ideas} onSaved={select} onClose={() => setCreating(false)} />}
      {editingProject && <ProjectEditor project={editingProject} ideas={ideas} onSaved={() => {}} onClose={() => setEditingProject(null)} />}
      {showArchived && (
        <Modal open onClose={() => setShowArchived(false)}>
          <div className="col" style={{ gap: 12 }}>
            <h2 className="display" style={{ fontSize: 24, margin: 0 }}>Archived projects</h2>
            {archived.map((p) => (
              <div key={p.id} className="row" style={{ gap: 10 }}>
                <span style={{ width: 10, height: 28, borderRadius: 5, background: tint(p.data.colorIndex), flex: 'none' }} />
                <span className="clamp1" style={{ flex: 1, fontSize: 14, fontWeight: 600 }}>{p.data.title}</span>
                <button className="btn-soft" style={{ minHeight: 40 }} onClick={() => {
                  store.update<IdeaProject>(p.id, { archived: false, updatedAt: iso(new Date()) })
                  select(p.id)
                  if (archived.length === 1) setShowArchived(false)
                }}>Unarchive</button>
              </div>
            ))}
          </div>
        </Modal>
      )}
    </div>
  )
}

// MARK: One idea, open

/** Write on an idea, see what grew from it, and grow it. Opening a branch moves into it; back returns. */
function IdeaSheet({ first, ideas, projects, onClose }: { first: string; ideas: Rec<Idea>[]; projects: Rec<IdeaProject>[]; onClose: () => void }) {
  const [trail, setTrail] = useState<string[]>([first])
  const [branch, setBranch] = useState('')
  const id = trail[trail.length - 1]
  const idea = ideas.find((i) => i.id === id)
  if (!idea) return null
  const project = projects.find((p) => p.id === idea.data.projectUUID)
  const parent = ideas.find((i) => i.id === idea.data.parentUUID)
  const branches = ideas.filter((i) => i.data.parentUUID === idea.id).sort((a, b) => time(a.data.createdAt) - time(b.data.createdAt))

  const touch = (patch: Partial<Idea> = {}) => {
    const now = iso(new Date())
    store.update<Idea>(idea.id, { ...patch, updatedAt: now })
    if (project) store.update<IdeaProject>(project.id, { updatedAt: now })
  }
  const back = () => (trail.length > 1 ? setTrail(trail.slice(0, -1)) : onClose())
  const remove = () => {
    // Its branches move up instead of vanishing.
    for (const b of branches) store.update<Idea>(b.id, { parentUUID: idea.data.parentUUID })
    store.remove(idea.id)
    back()
  }
  const addBranch = () => {
    const t = branch.trim()
    if (!t || !project) return
    addIdea(t, project.id, idea.id)
    setBranch('')
  }

  return (
    <Modal open onClose={onClose} width={640}>
      <div className="col" style={{ gap: 14 }}>
        <div className="row" style={{ gap: 6, paddingRight: 36 }}>
          {trail.length > 1 && <button className="icon-btn" style={{ width: 40, height: 40, flex: 'none' }} onClick={back} title="Back"><ChevronLeft size={16} /></button>}
          <div style={{ minWidth: 0, flex: 1 }}>
            <div className="muted clamp1" style={{ fontSize: 12, fontWeight: 600 }}>{project?.data.title ?? 'Idea'}</div>
            {parent && <div className="muted clamp1" style={{ fontSize: 11 }}>Grew from “{parent.data.title}”</div>}
          </div>
          <button className="icon-btn" style={{ width: 40, height: 40, flex: 'none' }} onClick={() => touch({ pinned: !idea.data.pinned })}
            title={idea.data.pinned ? 'Unpin' : 'Pin to the top'}>{idea.data.pinned ? <PinOff size={15} /> : <Pin size={15} />}</button>
          <button className="icon-btn" style={{ width: 40, height: 40, flex: 'none', color: 'var(--critical)' }} onClick={remove} title="Delete idea"><Trash2 size={15} /></button>
        </div>
        <textarea key={`t${idea.id}`} className="plain display" rows={2} placeholder="Idea" defaultValue={idea.data.title}
          onChange={(e) => touch({ title: e.target.value })}
          style={{ fontSize: 24, resize: 'none', background: 'transparent', border: 'none', outline: 'none', color: 'var(--ink)', padding: 0 }} />
        <textarea key={`b${idea.id}`} className="field" rows={8} defaultValue={idea.data.body}
          placeholder="Keep writing… what happens, who's in it, why it matters, a line of dialogue."
          onChange={(e) => touch({ body: e.target.value })} style={{ fontSize: 15, lineHeight: 1.5, minHeight: 180 }} />

        <div className="row" style={{ gap: 6, fontSize: 14, fontWeight: 600 }}><GitBranch size={15} />Grown from this</div>
        <GrowButton idea={idea} />
        {branches.map((b) => {
          const n = ideas.filter((x) => x.data.parentUUID === b.id).length
          return (
            <button key={b.id} onClick={() => setTrail([...trail, b.id])} className="row"
              style={{ gap: 10, padding: 12, borderRadius: 14, background: 'var(--card)', textAlign: 'left', color: 'var(--ink)', alignItems: 'flex-start' }}>
              <CornerDownRight size={13} className="muted" style={{ marginTop: 3, flex: 'none' }} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 600 }}>{b.data.title}</div>
                {b.data.body && <div className="secondary clamp2" style={{ fontSize: 12 }}>{b.data.body}</div>}
              </div>
              {n > 0 && <span className="row muted" style={{ gap: 3, fontSize: 11 }}><GitBranch size={11} />{n}</span>}
            </button>
          )
        })}
        <div className="row" style={{ gap: 8 }}>
          <input className="field" style={{ flex: 1 }} placeholder="Grow it: a new thought from this idea…" value={branch}
            onChange={(e) => setBranch(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') addBranch() }} />
          <button className="btn-soft" style={{ minHeight: 40 }} disabled={!branch.trim()} onClick={addBranch}><Plus size={14} /></button>
        </div>
        <button className="btn-primary" style={{ minHeight: 44 }} onClick={onClose}>Done</button>
      </div>
    </Modal>
  )
}

// MARK: Make or edit a project (rename, recolour, archive, delete)

function ProjectEditor({ project, ideas, onSaved, onClose }: {
  project: Rec<IdeaProject> | null; ideas: Rec<Idea>[]; onSaved: (id: string) => void; onClose: () => void
}) {
  const [title, setTitle] = useState(project?.data.title ?? '')
  const [summary, setSummary] = useState(project?.data.summary ?? '')
  const [color, setColor] = useState(project?.data.colorIndex ?? Math.floor(Math.random() * TINTS.length))
  const [confirm, setConfirm] = useState(false)

  const save = () => {
    const t = title.trim()
    if (!t) return
    if (project) store.update<IdeaProject>(project.id, { title: t, summary: summary.trim(), colorIndex: color, updatedAt: iso(new Date()) })
    else onSaved(newProject(t, summary.trim(), color))
    onClose()
  }

  return (
    <Modal open onClose={onClose}>
      <div className="col" style={{ gap: 14 }}>
        <h2 className="display" style={{ fontSize: 24, margin: 0 }}>{project ? 'Project' : 'New project'}</h2>
        <input className="field" autoFocus={!project} placeholder="Name (e.g. My novel, Blog posts)" value={title} onChange={(e) => setTitle(e.target.value)} />
        <textarea className="field" rows={3} placeholder="What it's about (optional)" value={summary} onChange={(e) => setSummary(e.target.value)} />
        <div className="row" style={{ gap: 8 }}>
          {TINTS.map((c, i) => (
            <button key={i} onClick={() => setColor(i)} aria-label={`Colour ${i + 1}`}
              style={{ width: 40, height: 40, borderRadius: '50%', background: c, outline: color === i ? '2px solid var(--ink)' : 'none', outlineOffset: 2 }} />
          ))}
        </div>
        {project && (
          <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
            <button className="btn-soft" style={{ minHeight: 40 }} onClick={() => {
              store.update<IdeaProject>(project.id, { archived: !project.data.archived, updatedAt: iso(new Date()) }); onClose()
            }}><Archive size={14} />{project.data.archived ? 'Unarchive' : 'Archive'}</button>
            <button className="btn-soft" style={{ minHeight: 40, color: 'var(--critical)' }} onClick={() => setConfirm(true)}><Trash2 size={14} />Delete</button>
          </div>
        )}
        {project && confirm && (
          <div className="card" style={{ padding: 12, fontSize: 13 }}>
            Delete {project.data.title} and its {ideas.filter((i) => i.data.projectUUID === project.id).length} ideas?
            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn-soft" onClick={() => setConfirm(false)}>Keep</button>
              <span className="spacer" />
              <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => {
                ideas.filter((i) => i.data.projectUUID === project.id).forEach((i) => store.remove(i.id))
                store.remove(project.id)
                onClose()
              }}>Delete</button>
            </div>
          </div>
        )}
        <div className="row">
          <button className="btn-soft" onClick={onClose}>Cancel</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 120 }} disabled={!title.trim()} onClick={save}>Save</button>
        </div>
      </div>
    </Modal>
  )
}
