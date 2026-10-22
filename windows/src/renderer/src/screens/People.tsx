// People: birthdays, who to reach out to, and gift ideas. Same `person` records as the Mac.
import { useState } from 'react'
import { Plus, Cake, MessageCircle, Gift, Trash2, Search, Check, X, Users } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Person, RELATIONS, Relation, RELATION_COLOR, cap } from '@/lib/models'
import { iso, parse, startOfDay, daysBetween, fmtDay, relativeTime } from '@/lib/dates'
import { Card, EmptyHint, Modal, DateInput, FormRow } from '@/components/ui'

// MARK: Birthday maths (same rules as Person on the Mac)

/** Birthday as a local date; year 1 (or anything before 1900) means the year isn't known. */
const birthDate = (p: Person): Date | null => parse(p.birthday)
export function nextBirthday(p: Person): Date | null {
  const b = birthDate(p)
  if (!b) return null
  const today = startOfDay(new Date())
  let next = new Date(today.getFullYear(), b.getMonth(), b.getDate())
  if (next < today) next = new Date(today.getFullYear() + 1, b.getMonth(), b.getDate())
  return next
}
export function turningAge(p: Person): number | null {
  const b = birthDate(p), n = nextBirthday(p)
  if (!b || !n || b.getFullYear() <= 1900) return null
  return n.getFullYear() - b.getFullYear()
}
export function overdueForContact(p: Person): boolean {
  if (!(p.contactEveryDays > 0)) return false
  const last = parse(p.lastContact)
  if (!last) return true
  return Date.now() - last.getTime() > p.contactEveryDays * 86_400_000
}

const initials = (name: string) => name.split(' ').filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || '?'

export default function People() {
  const people = useRecords<Person>('person')
  const [editing, setEditing] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const today = startOfDay(new Date())
  const q = query.trim().toLowerCase()
  const visible = people.filter((p) => !q || p.data.name.toLowerCase().includes(q) || p.data.notes.toLowerCase().includes(q))
    .sort((a, b) => a.data.name.localeCompare(b.data.name))

  const birthdays = people.filter((p) => nextBirthday(p.data))
    .map((p) => ({ p, next: nextBirthday(p.data)!, days: daysBetween(today, nextBirthday(p.data)!) }))
    .sort((a, b) => a.days - b.days)
  const upcoming = birthdays.filter((b) => b.days <= 60)
  const reachOut = people.filter((p) => overdueForContact(p.data))
    .sort((a, b) => (a.data.lastContact ?? '').localeCompare(b.data.lastContact ?? ''))
  const gifts = people.filter((p) => (p.data.giftIdeas ?? []).length > 0)

  const add = () => setEditing(store.create<Person>('person', {
    name: '', email: '', phone: '', relation: 'friend', birthday: null, notes: '', giftIdeas: [], lastContact: null,
    lastContactSource: '', contactEveryDays: 0, createdAt: iso(new Date()),
  }))
  const editingRec = editing ? people.find((p) => p.id === editing) : undefined

  return (
    <div className="page">
      <div className="col" style={{ gap: 22 }}>
        <div className="row" style={{ gap: 12 }}>
          <h1 className="page-title">People</h1>
          <span className="spacer" />
          <div className="row" style={{ background: 'var(--card)', borderRadius: 999, padding: '8px 12px', gap: 6 }}>
            <Search size={14} color="var(--ink3)" />
            <input className="plain" style={{ width: 150 }} placeholder="Search people" value={query} onChange={(e) => setQuery(e.target.value)} />
          </div>
          <button className="btn-soft" onClick={add}><Plus size={14} />Add person</button>
        </div>

        {people.length === 0 ? (
          <Card className="col" style={{ alignItems: 'center', padding: 40, gap: 10 }}>
            <Users size={34} strokeWidth={1.3} />
            <div className="secondary">Keep birthdays, gift ideas and a gentle nudge to stay in touch with the people you care about.</div>
            <button className="btn-primary" onClick={add}>Add someone</button>
          </Card>
        ) : (
          <div className="row" style={{ gap: 20, alignItems: 'stretch' }}>
            <Card className="col" style={{ flex: 1, minWidth: 0 }}>
              <div className="row"><Cake size={16} /><h3 className="section-title">Upcoming birthdays</h3></div>
              {upcoming.length === 0 && <EmptyHint text="No birthdays in the next two months." />}
              {upcoming.slice(0, 6).map(({ p, next, days }) => (
                <button key={p.id} className="list-row" onClick={() => setEditing(p.id)}>
                  <span className="days-badge" style={{ background: days === 0 ? 'var(--lime)' : 'var(--pink)' }}>{days === 0 ? '🎉' : days}<small>{days === 0 ? 'today' : days === 1 ? 'day' : 'days'}</small></span>
                  <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
                    <strong className="clamp1">{p.data.name}</strong>
                    <span className="muted" style={{ fontSize: 12 }}>
                      {fmtDay(next, { weekday: 'short', day: 'numeric', month: 'short' })}{turningAge(p.data) ? ` · turns ${turningAge(p.data)}` : ''}
                      {(p.data.giftIdeas ?? []).length > 0 && ` · ${p.data.giftIdeas.length} gift idea${p.data.giftIdeas.length === 1 ? '' : 's'}`}
                    </span>
                  </div>
                </button>
              ))}
            </Card>
            <Card className="col" style={{ flex: 1, minWidth: 0 }}>
              <div className="row"><MessageCircle size={16} /><h3 className="section-title">Reach out</h3></div>
              {reachOut.length === 0 && <EmptyHint text="You're up to date with everyone. Set “Keep in touch” on someone to get a nudge." />}
              {reachOut.slice(0, 6).map((p) => (
                <div key={p.id} className="list-row">
                  <Avatar name={p.data.name} relation={p.data.relation} />
                  <button className="col" style={{ gap: 2, flex: 1, minWidth: 0, textAlign: 'left' }} onClick={() => setEditing(p.id)}>
                    <strong className="clamp1">{p.data.name}</strong>
                    <span className="muted" style={{ fontSize: 12 }}>{p.data.lastContact ? `Last talked ${relativeTime(parse(p.data.lastContact)!)}` : 'No contact logged yet'} · every {p.data.contactEveryDays} days</span>
                  </button>
                  <button className="btn-soft" style={{ background: 'var(--card)' }} title="Log that you talked today"
                    onClick={() => store.update<Person>(p.id, { lastContact: iso(new Date()), lastContactSource: 'manual' })}><Check size={13} />Talked</button>
                </div>
              ))}
            </Card>
            <Card className="col" style={{ width: 320, flex: 'none' }}>
              <div className="row"><Gift size={16} /><h3 className="section-title">Gift ideas</h3></div>
              {gifts.length === 0 && <EmptyHint text="Jot down gift ideas when they come to you." />}
              {gifts.slice(0, 6).map((p) => (
                <button key={p.id} className="list-row" style={{ alignItems: 'flex-start' }} onClick={() => setEditing(p.id)}>
                  <div className="col" style={{ gap: 4, minWidth: 0 }}>
                    <strong className="clamp1" style={{ fontSize: 13 }}>{p.data.name}</strong>
                    <div className="row" style={{ flexWrap: 'wrap', gap: 4 }}>
                      {p.data.giftIdeas.slice(0, 4).map((g) => <span key={g} className="pill compact" style={{ background: 'var(--peach)' }}>{g}</span>)}
                    </div>
                  </div>
                </button>
              ))}
            </Card>
          </div>
        )}

        {people.length > 0 && (
          <div className="col" style={{ gap: 12 }}>
            <h3 className="section-title">Everyone <span className="muted" style={{ fontWeight: 500 }}>{people.length}</span></h3>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: 12 }}>
              {visible.map((p) => {
                const n = nextBirthday(p.data)
                return (
                  <button key={p.id} className="card row" style={{ padding: 14, textAlign: 'left' }} onClick={() => setEditing(p.id)}>
                    <Avatar name={p.data.name} relation={p.data.relation} />
                    <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
                      <strong className="clamp1">{p.data.name || 'Unnamed'}</strong>
                      <span className="muted clamp1" style={{ fontSize: 11 }}>
                        {[cap(p.data.relation), n ? `🎂 ${fmtDay(n, { day: 'numeric', month: 'short' })}` : '', overdueForContact(p.data) ? 'reach out' : ''].filter(Boolean).join(' · ')}
                      </span>
                    </div>
                  </button>
                )
              })}
            </div>
          </div>
        )}
      </div>
      {editingRec && <PersonEditor rec={editingRec} onClose={() => setEditing(null)} />}
    </div>
  )
}

function Avatar({ name, relation }: { name: string; relation: Relation }) {
  return (
    <span style={{ width: 38, height: 38, borderRadius: '50%', flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      background: RELATION_COLOR[relation] ?? 'var(--mint)', color: 'var(--sticker-ink)', fontWeight: 700, fontSize: 13 }}>{initials(name)}</span>
  )
}

function PersonEditor({ rec, onClose }: { rec: Rec<Person>; onClose: () => void }) {
  const p = rec.data
  const set = (patch: Partial<Person>) => store.update<Person>(rec.id, patch)
  const [gift, setGift] = useState('')
  const b = parse(p.birthday)
  const yearUnknown = !!b && b.getFullYear() <= 1900
  const close = () => { if (!p.name.trim()) store.remove(rec.id); onClose() }
  const addGift = () => { const g = gift.trim(); if (g) set({ giftIdeas: [...(p.giftIdeas ?? []), g] }); setGift('') }
  /** Keeps month and day, switching the year to 1 ("unknown", as the Mac stores it) or back to a real year. */
  const setYearUnknown = (unknown: boolean) => {
    if (!b) return
    const d = new Date(2000, b.getMonth(), b.getDate(), 12)
    d.setFullYear(unknown ? 1 : 2000)
    set({ birthday: iso(d) })
  }
  return (
    <Modal open onClose={close} width={540}>
      <div className="col" style={{ gap: 14 }}>
        <input className="plain display" style={{ fontSize: 24 }} autoFocus={!p.name} placeholder="Name" value={p.name} onChange={(e) => set({ name: e.target.value })} />
        <div className="row" style={{ gap: 6 }}>
          {RELATIONS.map((r) => (
            <span key={r} className="pill compact" onClick={() => set({ relation: r })}
              style={{ background: RELATION_COLOR[r], cursor: 'pointer', opacity: p.relation === r ? 1 : 0.4, outline: p.relation === r ? '1.5px solid var(--ink)' : 'none' }}>{cap(r)}</span>
          ))}
        </div>
        <FormRow label="Birthday">
          <DateInput value={p.birthday} onChange={(v) => set({ birthday: v })} />
          {b && <label className="row" style={{ gap: 6, fontSize: 12 }}><input type="checkbox" checked={yearUnknown} onChange={(e) => setYearUnknown(e.target.checked)} />Year unknown</label>}
        </FormRow>
        <FormRow label="Email"><input className="field" value={p.email} onChange={(e) => set({ email: e.target.value })} /></FormRow>
        <FormRow label="Phone"><input className="field" value={p.phone} onChange={(e) => set({ phone: e.target.value })} /></FormRow>
        <FormRow label="Keep in touch">
          <select className="field" style={{ width: 170 }} value={p.contactEveryDays} onChange={(e) => set({ contactEveryDays: Number(e.target.value) })}>
            {[...new Set([0, 7, 14, 30, 60, 90, 180, p.contactEveryDays])].sort((a, b) => a - b).map((n) => <option key={n} value={n}>{n === 0 ? 'No reminder' : `Every ${n} days`}</option>)}
          </select>
        </FormRow>
        <FormRow label="Last talked">
          <span className="secondary" style={{ flex: 1 }}>{p.lastContact ? `${relativeTime(parse(p.lastContact)!)}${p.lastContactSource === 'gmail' ? ' (email)' : ''}` : 'Not logged'}</span>
          <button className="btn-soft" onClick={() => set({ lastContact: iso(new Date()), lastContactSource: 'manual' })}><Check size={13} />Talked today</button>
        </FormRow>
        <div className="col" style={{ gap: 8 }}>
          <div className="muted" style={{ fontSize: 12, fontWeight: 600 }}>Gift ideas</div>
          <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
            {(p.giftIdeas ?? []).map((g, i) => (
              <span key={`${g}-${i}`} className="pill" style={{ background: 'var(--peach)' }}>{g}
                <button title="Remove" onClick={() => set({ giftIdeas: p.giftIdeas.filter((_, j) => j !== i) })}><X size={11} /></button>
              </span>
            ))}
          </div>
          <div className="row">
            <input className="field" placeholder="Add a gift idea" value={gift} onChange={(e) => setGift(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && addGift()} />
            <button className="btn-soft" disabled={!gift.trim()} onClick={addGift}>Add</button>
          </div>
        </div>
        <textarea className="field" rows={3} placeholder="Notes" value={p.notes} onChange={(e) => set({ notes: e.target.value })} />
        <div className="row">
          <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(rec.id); onClose() }}><Trash2 size={13} />Delete</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 110 }} onClick={close}>Done</button>
        </div>
      </div>
    </Modal>
  )
}
