// Documents: things with an expiry date (passport, ID, licence, insurance, warranties…). Same `document` records as the Mac.
import { useState } from 'react'
import { Plus, FileText, Trash2, Search } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Doc, DOC_KINDS, DocKind, docKind } from '@/lib/models'
import { iso, parse, startOfDay, daysBetween, fmtDay } from '@/lib/dates'
import { Card, EmptyHint, Modal, DateInput, FormRow } from '@/components/ui'

export const docDaysLeft = (d: Doc): number | null => { const e = parse(d.expires); return e ? daysBetween(startOfDay(new Date()), e) : null }

function badge(d: Doc): { text: string; sub: string; bg: string; fg?: string } {
  const n = docDaysLeft(d)
  if (n === null) return { text: '—', sub: 'no expiry', bg: 'var(--card)' }
  if (n < 0) return { text: String(-n), sub: -n === 1 ? 'day ago' : 'days ago', bg: 'var(--critical)', fg: '#fff' }
  const big = n > 99
  const text = big ? String(Math.round(n / 30)) : String(n)
  const sub = big ? 'months' : n === 1 ? 'day' : 'days'
  return { text, sub, bg: n <= (d.remindDays || 30) ? 'var(--orange)' : 'var(--mint)' }
}

export default function Documents() {
  const docs = useRecords<Doc>('document')
  const [editing, setEditing] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const q = query.trim().toLowerCase()
  const sorted = docs.filter((d) => !q || d.data.title.toLowerCase().includes(q) || d.data.issuer.toLowerCase().includes(q) || docKind(d.data.kind).title.toLowerCase().includes(q))
    .sort((a, b) => (a.data.expires ? 0 : 1) - (b.data.expires ? 0 : 1) || (a.data.expires ?? '').localeCompare(b.data.expires ?? '') || a.data.title.localeCompare(b.data.title))
  const expired = sorted.filter((d) => (docDaysLeft(d.data) ?? 1) < 0)
  const soon = sorted.filter((d) => { const n = docDaysLeft(d.data); return n !== null && n >= 0 && n <= (d.data.remindDays || 30) })
  const rest = sorted.filter((d) => !expired.includes(d) && !soon.includes(d))

  const add = () => setEditing(store.create<Doc>('document', {
    title: '', kind: 'passport', number: '', issuer: '', issued: null, expires: null, remindDays: 30, notes: '', source: 'manual', sourceID: '', createdAt: iso(new Date()),
  }))
  const editingRec = editing ? docs.find((d) => d.id === editing) : undefined

  return (
    <div className="page">
      <div className="col" style={{ gap: 22, maxWidth: 980, margin: '0 auto' }}>
        <div className="row" style={{ gap: 12 }}>
          <h1 className="page-title">Documents</h1>
          <span className="spacer" />
          <div className="row" style={{ background: 'var(--card)', borderRadius: 999, padding: '8px 12px', gap: 6 }}>
            <Search size={14} color="var(--ink3)" />
            <input className="plain" style={{ width: 150 }} placeholder="Search documents" value={query} onChange={(e) => setQuery(e.target.value)} />
          </div>
          <button className="btn-soft" onClick={add}><Plus size={14} />Add document</button>
        </div>
        <div className="secondary" style={{ fontSize: 13, marginTop: -12 }}>Passports, IDs, licences, insurance and warranties, sorted by when they expire. Orbit reminds you before they do.</div>

        {docs.length === 0 && (
          <Card className="col" style={{ alignItems: 'center', padding: 40, gap: 10 }}>
            <FileText size={34} strokeWidth={1.3} />
            <div className="secondary">Add your passport, ID or car insurance and never get caught by an expiry date again.</div>
            <button className="btn-primary" onClick={add}>Add document</button>
          </Card>
        )}
        {expired.length > 0 && <Section title="Expired" items={expired} onOpen={setEditing} />}
        {soon.length > 0 && <Section title="Expiring soon" items={soon} onOpen={setEditing} />}
        {rest.length > 0 && <Section title={expired.length || soon.length ? 'Later' : 'All documents'} items={rest} onOpen={setEditing} />}
        {docs.length > 0 && sorted.length === 0 && <EmptyHint text="No documents match." />}
      </div>
      {editingRec && <DocEditor rec={editingRec} onClose={() => setEditing(null)} />}
    </div>
  )
}

function Section({ title, items, onOpen }: { title: string; items: Rec<Doc>[]; onOpen: (id: string) => void }) {
  return (
    <Card className="col">
      <h3 className="section-title">{title}</h3>
      {items.map((r) => {
        const d = r.data, b = badge(d), k = docKind(d.kind), exp = parse(d.expires)
        return (
          <button key={r.id} className="list-row" onClick={() => onOpen(r.id)}>
            <span className="days-badge" style={{ background: b.bg, color: b.fg }}>{b.text}<small>{b.sub}</small></span>
            <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
              <strong className="clamp1">{d.title || k.title}</strong>
              <span className="muted clamp1" style={{ fontSize: 12 }}>
                {[d.issuer, d.number ? `•••• ${d.number.slice(-4)}` : '', exp ? `${(docDaysLeft(d) ?? 0) < 0 ? 'Expired' : 'Expires'} ${fmtDay(exp, { day: 'numeric', month: 'short', year: 'numeric' })}` : ''].filter(Boolean).join(' · ')}
              </span>
            </div>
            <span className="pill compact" style={{ background: k.color }}>{k.title}</span>
          </button>
        )
      })}
    </Card>
  )
}

function DocEditor({ rec, onClose }: { rec: Rec<Doc>; onClose: () => void }) {
  const d = rec.data
  const set = (p: Partial<Doc>) => store.update<Doc>(rec.id, p)
  const close = () => { if (!d.title.trim() && !d.expires && !d.number) store.remove(rec.id); onClose() }
  return (
    <Modal open onClose={close} width={520}>
      <div className="col" style={{ gap: 14 }}>
        <input className="plain display" style={{ fontSize: 24 }} autoFocus={!d.title} placeholder={docKind(d.kind).title} value={d.title} onChange={(e) => set({ title: e.target.value })} />
        <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
          {DOC_KINDS.map((k) => (
            <span key={k.id} className="pill compact" onClick={() => set({ kind: k.id as DocKind })}
              style={{ background: k.color, cursor: 'pointer', opacity: d.kind === k.id ? 1 : 0.4, outline: d.kind === k.id ? '1.5px solid var(--ink)' : 'none' }}>{k.title}</span>
          ))}
        </div>
        <FormRow label="Expires"><DateInput value={d.expires} onChange={(v) => set({ expires: v })} /></FormRow>
        <FormRow label="Remind me">
          <select className="field" style={{ width: 200 }} value={d.remindDays} onChange={(e) => set({ remindDays: Number(e.target.value) })}>
            {[...new Set([7, 14, 30, 60, 90, 180, d.remindDays])].sort((a, b) => a - b).map((n) => <option key={n} value={n}>{n} days before</option>)}
          </select>
        </FormRow>
        <FormRow label="Issued"><DateInput value={d.issued} onChange={(v) => set({ issued: v })} /></FormRow>
        <FormRow label="Issuer"><input className="field" placeholder="Country, company or authority" value={d.issuer} onChange={(e) => set({ issuer: e.target.value })} /></FormRow>
        <FormRow label="Number"><input className="field" placeholder="Last 4 digits are enough" value={d.number} onChange={(e) => set({ number: e.target.value })} /></FormRow>
        <textarea className="field" rows={3} placeholder="Notes" value={d.notes} onChange={(e) => set({ notes: e.target.value })} />
        <div className="muted" style={{ fontSize: 11 }}>Orbit isn't a password manager: keep full numbers somewhere safer.</div>
        <div className="row">
          <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(rec.id); onClose() }}><Trash2 size={13} />Delete</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 110 }} onClick={close}>Done</button>
        </div>
      </div>
    </Modal>
  )
}
