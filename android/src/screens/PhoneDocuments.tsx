// Documents on the phone, like PhoneDocuments (DocumentsView.swift) on iPhone: passport, ID, licence, insurance,
// warranties… sorted by what expires first, with a reminder before they do. Records are the Mac's DocItem ("document").
import { ReactNode, useState } from 'react'
import { Plus, Globe, IdCard, Car, Plane, CarFront, Shield, BadgeCheck, CreditCard, FileText, FileSearch } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Doc, DocKind, DOC_KINDS } from '@/lib/models'
import { iso, parse, startOfDay, addDays, daysBetween, toDateInput, fromInputs } from '@/lib/dates'
import { Modal } from '@/components/ui'
import { PtTitle, PtSwitch } from '../components/PtCommon'
import './PhoneDocuments.css'

const ICON: Record<DocKind, (s: number) => ReactNode> = {
  passport: (s) => <Globe size={s} strokeWidth={2.4} />, id: (s) => <IdCard size={s} strokeWidth={2.4} />, license: (s) => <Car size={s} strokeWidth={2.4} />,
  visa: (s) => <Plane size={s} strokeWidth={2.4} />, car: (s) => <CarFront size={s} strokeWidth={2.4} />, insurance: (s) => <Shield size={s} strokeWidth={2.4} />,
  warranty: (s) => <BadgeCheck size={s} strokeWidth={2.4} />, membership: (s) => <CreditCard size={s} strokeWidth={2.4} />, other: (s) => <FileText size={s} strokeWidth={2.4} />,
}
const kindOf = (k: string): DocKind => (DOC_KINDS.some((d) => d.id === k) ? (k as DocKind) : 'other')
const titleOf = (k: DocKind) => DOC_KINDS.find((d) => d.id === k)!.title

/** Days until it expires (negative once it has), or null without an expiry date. */
const daysLeft = (d: Doc): number | null => { const e = parse(d.expires); return e ? daysBetween(new Date(), e) : null }

export default function PhoneDocuments() {
  const docs = useRecords<Doc>('document').slice().sort((a, b) => (a.data.createdAt ?? '').localeCompare(b.data.createdAt ?? ''))
  const [kind, setKind] = useState<DocKind | null>(null)
  const [editing, setEditing] = useState<Rec<Doc> | null>(null)
  const [adding, setAdding] = useState(false)

  const sorted = docs.filter((d) => kind === null || kindOf(d.data.kind) === kind)
    .sort((a, b) => (parse(a.data.expires)?.getTime() ?? Infinity) - (parse(b.data.expires)?.getTime() ?? Infinity))
  const soon = docs.filter((d) => { const n = daysLeft(d.data); return n !== null && n >= 0 && n <= 90 }).length
  const expired = docs.filter((d) => (daysLeft(d.data) ?? 1) < 0).length
  const warranties = docs.filter((d) => kindOf(d.data.kind) === 'warranty' && (daysLeft(d.data) ?? -1) >= 0).length

  return (
    <div className="page pt-page">
      <PtTitle>Documents</PtTitle>
      <div className="pt-sub">Joshu reminds you before anything expires. Keep numbers short (e.g. the last 4 digits).</div>
      <div><button className="btn-soft" onClick={() => setAdding(true)}><Plus size={14} />Add document</button></div>

      <div className="pt-grid2">
        <Tile value={docs.length} label="Documents" color="var(--cyan)" />
        <Tile value={soon} label="Expire within 3 months" color="var(--orange)" />
        <Tile value={expired} label="Expired" color={expired > 0 ? 'var(--pink)' : 'var(--mint)'} />
        <Tile value={warranties} label="Active warranties" color="var(--lime)" />
      </div>

      <div className="pt-chips" style={{ gap: 6 }}>
        <button className={`pt-chip sm ${kind === null ? 'on' : ''}`} onClick={() => setKind(null)}>All</button>
        {DOC_KINDS.filter((k) => docs.some((d) => kindOf(d.data.kind) === k.id)).map((k) => (
          <button key={k.id} className={`pt-chip sm ${kind === k.id ? 'on' : ''}`} onClick={() => setKind(k.id)}>{k.title}</button>
        ))}
      </div>

      {sorted.length === 0 && (
        <div className="pt-doc-empty">
          <FileSearch size={38} strokeWidth={1.2} />
          <div>Add your passport, ID, driving licence, car registration and insurance. Warranties from order emails show up here by themselves.</div>
          <button className="btn-soft" onClick={() => setAdding(true)}>Add your first document</button>
        </div>
      )}
      <div className="col" style={{ gap: 14 }}>
        {sorted.map((d) => <DocCard key={d.id} doc={d.data} onOpen={() => setEditing(d)} />)}
      </div>

      {editing && <DocEditor rec={editing} onClose={() => setEditing(null)} />}
      {adding && <DocEditor rec={null} onClose={() => setAdding(false)} />}
    </div>
  )
}

function Tile({ value, label, color }: { value: number; label: string; color: string }) {
  return (
    <div className="pt-tile" style={{ background: color }}>
      <div className="v">{value}</div>
      <div className="l">{label}</div>
    </div>
  )
}

function DocCard({ doc, onOpen }: { doc: Doc; onOpen: () => void }) {
  const k = kindOf(doc.kind)
  const left = daysLeft(doc)
  const tint = left === null ? null : left < 0 ? 'var(--pink)' : left <= (doc.remindDays || 30) ? 'var(--orange)' : left <= 90 ? 'var(--peach)' : null
  const expires = parse(doc.expires)
  const number = (doc.number ?? '').trim()
  return (
    <button className="pt-doc" onClick={onOpen} style={{ background: tint ?? 'var(--card)', color: tint ? 'var(--sticker-ink)' : 'var(--ink)' }}>
      <span className="ic">{ICON[k](16)}</span>
      <span className="info">
        <span className="t">{doc.title || titleOf(k)}</span>
        <span className="m">{[titleOf(k), doc.issuer, number ? `•••${number.slice(-4)}` : ''].filter(Boolean).join(' · ')}</span>
        {expires
          ? <span className="e">Expires {expires.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}</span>
          : <span className="e none">No expiry date</span>}
      </span>
      {left !== null && (
        <span className="days">
          <span className="n">{left < 0 ? '!' : left >= 730 ? Math.floor(left / 365) : left}</span>
          <span className="u">{left < 0 ? 'expired' : left >= 730 ? 'years' : left === 1 ? 'day' : 'days'}</span>
        </span>
      )}
    </button>
  )
}

const REMIND: { days: number; title: string }[] = [
  { days: 7, title: '1 week before' }, { days: 14, title: '2 weeks before' }, { days: 30, title: '1 month before' },
  { days: 60, title: '2 months before' }, { days: 90, title: '3 months before' }, { days: 180, title: '6 months before' },
]

function DocEditor({ rec, onClose }: { rec: Rec<Doc> | null; onClose: () => void }) {
  const d = rec?.data
  const [title, setTitle] = useState(d?.title ?? titleOf('passport'))
  const [kind, setKindState] = useState<DocKind>(d ? kindOf(d.kind) : 'passport')
  const [number, setNumber] = useState(d?.number ?? '')
  const [issuer, setIssuer] = useState(d?.issuer ?? '')
  const [hasExpiry, setHasExpiry] = useState(d ? !!parse(d.expires) : true)
  const [expires, setExpires] = useState<Date>(parse(d?.expires ?? null) ?? addDays(startOfDay(new Date()), 365))
  const [remindDays, setRemindDays] = useState(d?.remindDays ?? 180)
  const [notes, setNotes] = useState(d?.notes ?? '')

  const pick = (k: DocKind) => {
    setKindState(k)
    if (!title.trim() || DOC_KINDS.some((x) => x.title === title)) setTitle(titleOf(k))
    if (!rec) setRemindDays(k === 'passport' || k === 'visa' ? 180 : 30)
  }

  const save = () => {
    const t = title.trim()
    if (!t) return
    const fields = { title: t, kind, number, issuer, notes, remindDays, expires: hasExpiry ? iso(startOfDay(expires)) : null }
    if (rec) store.update<Doc>(rec.id, fields)
    else store.create<Doc>('document', { ...fields, issued: null, source: 'manual', sourceID: '', createdAt: iso(new Date()) })
    onClose()
  }

  return (
    <Modal open onClose={onClose} width={520}>
      {/* Above the column, so the sheet's floating close button doesn't narrow everything below it. */}
      <h2 className="pt-sheet-title pt-sheet-head">{rec ? 'Edit document' : 'New document'}</h2>
      <div className="col" style={{ gap: 14 }}>
        <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
          {DOC_KINDS.map((k) => (
            <button key={k.id} className={`pt-chip sm ${kind === k.id ? 'on' : ''}`} style={{ fontWeight: 500 }} onClick={() => pick(k.id)}>
              {ICON[k.id](12)}{k.title}
            </button>
          ))}
        </div>
        <div className="pt-form">
          <span className="k">Name</span>
          <input className="field" placeholder="Egyptian passport" value={title} onChange={(e) => setTitle(e.target.value)} />
          <span className="k">Issued by</span>
          <input className="field" placeholder="Authority, insurer, shop…" value={issuer} onChange={(e) => setIssuer(e.target.value)} />
          <span className="k">Number</span>
          <input className="field" placeholder="Last 4 digits is enough" value={number} onChange={(e) => setNumber(e.target.value)} />
          <span className="k">Expires</span>
          <div className="row" style={{ gap: 10 }}>
            <PtSwitch label="Has an expiry date" on={hasExpiry} onChange={setHasExpiry} />
            {hasExpiry && <input type="date" className="field" style={{ width: 'auto', padding: '6px 10px' }} value={toDateInput(expires)}
              onChange={(e) => e.target.value && setExpires(fromInputs(e.target.value))} />}
          </div>
          <span className="k">Remind me</span>
          <select className="field" style={{ width: 'auto', padding: '8px 10px' }} value={remindDays} onChange={(e) => setRemindDays(Number(e.target.value))}>
            {!REMIND.some((r) => r.days === remindDays) && <option value={remindDays}>{remindDays} days before</option>}
            {REMIND.map((r) => <option key={r.days} value={r.days}>{r.title}</option>)}
          </select>
          <span className="k">Notes</span>
          <input className="field" placeholder="Where it's kept, how to renew…" value={notes} onChange={(e) => setNotes(e.target.value)} />
        </div>
        <div className="muted" style={{ fontSize: 11, visibility: kind === 'passport' ? 'visible' : 'hidden' }}>
          Passports often need 6 months of validity to travel, so a longer reminder helps.
        </div>
        <div className="row" style={{ gap: 8 }}>
          {rec && <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(rec.id); onClose() }}>Delete</button>}
          <span className="spacer" />
          <button className="btn-soft" onClick={onClose}>Cancel</button>
          <button className="btn-primary" style={{ width: 110, minHeight: 40 }} disabled={!title.trim()} onClick={save}>Save</button>
        </div>
      </div>
    </Modal>
  )
}
