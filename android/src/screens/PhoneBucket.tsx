// Bucket list on the phone: PhoneBucket in iOS/OrbitPhone/PhoneSections.swift, which shows BucketListView.swift as it is:
// Dreams (trips from TripsView.swift, "Looking forward to", filters and dream cards), Goals (GoalsSection, in Goals.tsx)
// and Go to (GoToView.swift: places on a map, found by name or from a Google or Apple Maps link, with directions).
// Records are the Mac's `bucket`, `trip` and `booking` rows with every field its encoder writes (CloudSync.swift).
import { ReactNode, useEffect, useRef, useState } from 'react'
import {
  Plus, Sparkles, Flag, MapPinned, Plane, Mountain, GraduationCap, Paintbrush, Users, Star, Luggage, Ticket, BedDouble,
  TramFront, Car, Calendar as CalIcon, BadgeCheck, CircleCheck, Circle, Mail, X, Utensils, Coffee, Wine, ShoppingBag,
  Landmark, Leaf, MapPin, Map as MapIcon, Search, Navigation, Globe, CircleX, Trash2,
} from 'lucide-react'
import { CapacitorHttp } from '@capacitor/core'
import { store, useRecords, useSetting, Rec } from '@/lib/store'
import { Bucket, Trip, Booking, Txn } from '@/lib/models'
import { iso, parse, startOfDay, addDays, sameDay, fromInputs, toDateInput, toTimeInput } from '@/lib/dates'
import { structured, useAssistantName } from '@/lib/ai'
import { openAsk } from '@/lib/askBus'
import { Modal, useMoney, defaultCurrency } from '@/components/ui'
import { Orb } from '../components/Orb'
import { isNative } from '../native'
import { GoalsSection } from './Goals'
import { SectionTitle, ActionSheet, Toggle, CheckDot, daysFromToday } from './pm2Kit'
import './pm2.css'

// MARK: - Kinds (BucketKind, BookingKind and PlaceCategory on the Mac)

type DreamKind = 'travel' | 'experience' | 'adventure' | 'learn' | 'create' | 'people' | 'other'
const DREAMS: { id: DreamKind; title: string; color: string; icon: (s: number) => ReactNode }[] = [
  { id: 'travel', title: 'Travel', color: 'var(--cyan)', icon: (s) => <Plane size={s} fill="currentColor" /> },
  { id: 'experience', title: 'Experience', color: 'var(--pink)', icon: (s) => <Sparkles size={s} fill="currentColor" /> },
  { id: 'adventure', title: 'Adventure', color: 'var(--orange)', icon: (s) => <Mountain size={s} fill="currentColor" /> },
  { id: 'learn', title: 'Learn', color: 'var(--lime)', icon: (s) => <GraduationCap size={s} /> },
  { id: 'create', title: 'Create', color: 'var(--purple)', icon: (s) => <Paintbrush size={s} /> },
  { id: 'people', title: 'People', color: 'var(--mint)', icon: (s) => <Users size={s} fill="currentColor" /> },
  { id: 'other', title: 'Other', color: 'var(--peach)', icon: (s) => <Star size={s} fill="currentColor" /> },
]
const dream = (k: string) => DREAMS.find((d) => d.id === k) ?? DREAMS[1]

type BookingKind = 'flight' | 'hotel' | 'train' | 'car' | 'activity' | 'other'
const BOOKINGS: { id: BookingKind; title: string; icon: (s: number) => ReactNode }[] = [
  { id: 'flight', title: 'Flight', icon: (s) => <Plane size={s} fill="currentColor" /> },
  { id: 'hotel', title: 'Hotel', icon: (s) => <BedDouble size={s} /> },
  { id: 'train', title: 'Train', icon: (s) => <TramFront size={s} /> },
  { id: 'car', title: 'Car', icon: (s) => <Car size={s} /> },
  { id: 'activity', title: 'Activity', icon: (s) => <Ticket size={s} /> },
  { id: 'other', title: 'Other', icon: (s) => <Luggage size={s} /> },
]
const booking = (k: string) => BOOKINGS.find((b) => b.id === k) ?? BOOKINGS[5]

type PlaceCategory = 'food' | 'cafe' | 'bar' | 'shop' | 'museum' | 'park' | 'attraction' | 'hotel' | 'other'
const PLACES: { id: PlaceCategory; title: string; color: string; icon: (s: number) => ReactNode }[] = [
  { id: 'food', title: 'Food', color: 'var(--orange)', icon: (s) => <Utensils size={s} /> },
  { id: 'cafe', title: 'Café', color: 'var(--peach)', icon: (s) => <Coffee size={s} /> },
  { id: 'bar', title: 'Bar', color: 'var(--purple)', icon: (s) => <Wine size={s} /> },
  { id: 'shop', title: 'Shop', color: 'var(--pink)', icon: (s) => <ShoppingBag size={s} /> },
  { id: 'museum', title: 'Museum', color: 'var(--cyan)', icon: (s) => <Landmark size={s} /> },
  { id: 'park', title: 'Park', color: 'var(--lime)', icon: (s) => <Leaf size={s} /> },
  { id: 'attraction', title: 'Sight', color: 'var(--mint)', icon: (s) => <Star size={s} /> },
  { id: 'hotel', title: 'Stay', color: 'var(--pm2-lavender)', icon: (s) => <BedDouble size={s} /> },
  { id: 'other', title: 'Other', color: 'var(--pm2-sand)', icon: (s) => <MapPin size={s} /> },
]
const placeCat = (k: string | undefined) => PLACES.find((p) => p.id === k) ?? PLACES[8]

/** A bucket row as the Mac writes it: dreams plus Go to places (kind "place", with `place`). */
interface Place { category: string; address: string; lat: number; lon: number; url: string }
interface Item extends Omit<Bucket, 'kind'> { kind: string; place?: Place }
const hasLocation = (p?: Place) => !!p && (Number(p.lat) !== 0 || Number(p.lon) !== 0)

const fmtShort = (d: Date) => d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })

// MARK: - TripStore

const BASICS = ['Passport', 'Phone charger', 'Power adapter', 'Toothbrush', 'Medication', 'Headphones', 'Cards and some cash']

function newTrip(fields: Partial<Trip>): string {
  return store.create<Trip>('trip', {
    title: '', destination: '', start: null, end: null, bucketUUID: '', budget: 0, notes: '', packing: [...BASICS], packed: [],
    createdAt: iso(new Date()), ...fields,
  })
}

/** Starts a trip from a travel dream (or opens the one already planned). */
function planTrip(item: Rec<Item>): string {
  const existing = store.list<Trip>('trip').find((t) => t.data.bucketUUID === item.id)
  if (existing) return existing.id
  const s = parse(item.data.targetDate)
  return newTrip({ title: item.data.title, bucketUUID: item.id, start: s ? iso(s) : null, notes: item.data.notes ?? '' })
}

/** Bookings plus expenses dated during the trip (not counting an expense that is itself a booking from email). */
function spent(trip: Rec<Trip>, bookings: Rec<Booking>[], txns: Rec<Txn>[]): number {
  const mine = bookings.filter((b) => b.data.tripUUID === trip.id)
  let total = mine.reduce((n, b) => n + (Number(b.data.amount) || 0), 0)
  const s = parse(trip.data.start)
  if (s) {
    const from = startOfDay(s), to = addDays(startOfDay(parse(trip.data.end) ?? s), 1)
    const fromEmail = new Set(mine.map((b) => b.data.sourceID).filter(Boolean))
    total += -txns.filter((t) => { const d = parse(t.data.date); return t.data.amount < 0 && !!d && d >= from && d < to && !fromEmail.has(t.data.sourceID) })
      .reduce((n, t) => n + t.data.amount, 0)
  }
  return total
}

const daysUntil = (t: Trip): number | null => { const s = parse(t.start); return s ? daysFromToday(s) : null }
const nights = (t: Trip): number | null => {
  const s = parse(t.start), e = parse(t.end)
  return s && e ? daysFromToday(e) - daysFromToday(s) : null
}

// MARK: - Screen

type Section = 'dreams' | 'goals' | 'goto'
const SECTION_KEY = 'bucketSection'

export default function PhoneBucket() {
  const everything = useRecords<Item>('bucket').slice().sort((a, b) => (b.data.createdAt ?? '').localeCompare(a.data.createdAt ?? ''))
  const items = everything.filter((i) => i.data.kind !== 'place')
  const assistant = useAssistantName()
  const [section, setSectionState] = useState<Section>(() => {
    try { const v = localStorage.getItem(SECTION_KEY); return v === 'goals' || v === 'goto' ? v : 'dreams' } catch { return 'dreams' }
  })
  const setSection = (s: Section) => { setSectionState(s); try { localStorage.setItem(SECTION_KEY, s) } catch { /* private mode */ } }
  const [show, setShow] = useState<'Dreams' | 'Done'>('Dreams')
  const [kind, setKind] = useState<DreamKind | null>(null)
  const [editing, setEditing] = useState<Rec<Item> | null>(null)
  const [adding, setAdding] = useState(false)
  const [openTrip, setOpenTrip] = useState<string | null>(null)

  const today = startOfDay(new Date())
  const upcoming = items.filter((i) => !i.data.isDone && (parse(i.data.targetDate) ?? new Date(0)) >= today)
    .sort((a, b) => (parse(a.data.targetDate)?.getTime() ?? 0) - (parse(b.data.targetDate)?.getTime() ?? 0))
  const visible = items.filter((i) => (show === 'Done' ? i.data.isDone : !i.data.isDone))
    .filter((i) => !kind || i.data.kind === kind)
    .sort((a, b) => show === 'Done'
      ? (parse(b.data.doneAt)?.getTime() ?? 0) - (parse(a.data.doneAt)?.getTime() ?? 0)
      : (b.data.excitement ?? 0) - (a.data.excitement ?? 0))
  const done = items.filter((i) => i.data.isDone).length

  return (
    <div className="pm2" style={{ gap: 22 }}>
      <SectionTitle>Bucket list</SectionTitle>

      {/* PageHeader on the phone: the subtitle, then the actions wrap underneath. */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: -12 }}>
        <span className="pm2-secondary" style={{ fontSize: 14 }}>
          {items.length === 0 ? 'The things you want to do, see, learn and feel.' : `${done} of ${items.length} done. Keep dreaming.`}
        </span>
        <div className="pm2-wrap">
          {items.length > 0 && <Ring done={done} total={items.length} />}
          <button className="pm2-soft" onClick={() => openAsk('Help me add some ideas to my bucket list. Ask me a couple of questions first.')}>
            <Orb size={18} spark={false} />Ideas from {assistant}
          </button>
          <button className="pm2-soft" onClick={() => setAdding(true)}><Plus size={15} />Add dream</button>
        </div>
      </div>

      <div className="pm2-tabs">
        {([['dreams', 'Dreams', <Sparkles key="s" size={15} fill="currentColor" />], ['goals', 'Goals', <Flag key="f" size={15} />],
          ['goto', 'Go to', <MapPinned key="m" size={15} />]] as [Section, string, ReactNode][]).map(([key, label, icon]) => (
          <button key={key} className={section === key ? 'on' : ''} onClick={() => setSection(key)}>{icon}{label}</button>
        ))}
      </div>

      {section === 'goto' ? <GoToSection /> : section === 'goals' ? <GoalsSection /> : (
        <>
          <TripsSection onOpen={setOpenTrip} />
          {upcoming.length > 0 && <LookingForward items={upcoming} onOpen={setEditing} />}
          <div className="pm2-scrollx">
            {(['Dreams', 'Done'] as const).map((s) => (
              <button key={s} className={`pm2-chip ${show === s ? 'on' : ''}`} onClick={() => setShow(s)}>
                {s === 'Done' ? `Done (${done})` : `Dreams (${items.length - done})`}
              </button>
            ))}
            <span className="pm2-divider" />
            {DREAMS.map((k) => (
              <button key={k.id} className="pm2-kchip" style={{ background: k.color, opacity: !kind || kind === k.id ? 1 : 0.3 }}
                onClick={() => setKind(kind === k.id ? null : k.id)}>{k.icon(12)}{k.title}</button>
            ))}
          </div>
          {visible.length === 0 && (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, padding: '50px 0', color: 'var(--ink2)', textAlign: 'center' }}>
              <Mountain size={40} strokeWidth={1.2} />
              <span style={{ fontSize: 14 }}>{show === 'Done' ? 'Nothing ticked off yet. Your first one is coming.'
                : 'What do you want to do one day? See the northern lights, learn Japanese, run a marathon…'}</span>
              {show !== 'Done' && <button className="pm2-soft" onClick={() => setAdding(true)}>Add your first dream</button>}
            </div>
          )}
          {visible.map((i) => <DreamCard key={i.id} item={i} onOpen={() => setEditing(i)} onTrip={() => setOpenTrip(planTrip(i))} />)}
        </>
      )}

      <Modal open={adding} onClose={() => setAdding(false)}>{adding && <DreamEditor item={null} onClose={() => setAdding(false)} />}</Modal>
      <Modal open={!!editing} onClose={() => setEditing(null)}>{editing && <DreamEditor item={editing} onClose={() => setEditing(null)} />}</Modal>
      <TripSheetHost id={openTrip} onClose={() => setOpenTrip(null)} />
    </div>
  )
}

function Ring({ done, total }: { done: number; total: number }) {
  const r = 23, c = 2 * Math.PI * r
  return (
    <span className="pm2-ring">
      <svg width="54" height="54" viewBox="0 0 54 54">
        <circle cx="27" cy="27" r={r} fill="none" stroke="var(--card)" strokeWidth="8" />
        {done > 0 && <circle cx="27" cy="27" r={r} fill="none" stroke="var(--lime)" strokeWidth="8" strokeLinecap="round"
          strokeDasharray={`${total ? (done / total) * c : 0} ${c}`} />}
      </svg>
      <b>{done}</b>
    </span>
  )
}

function LookingForward({ items, onOpen }: { items: Rec<Item>[]; onOpen: (i: Rec<Item>) => void }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <h3 className="pm2-display" style={{ fontSize: 22, margin: 0 }}>Looking forward to</h3>
      <div className="pm2-scrollx" style={{ gap: 14 }}>
        {items.map((i) => {
          const d = parse(i.data.targetDate)!, days = daysFromToday(d), k = dream(i.data.kind)
          return (
            <button key={i.id} className="pm2-forward" style={{ background: k.color }} onClick={() => onOpen(i)}>
              <span className="n">
                <span className="pm2-display" style={{ fontSize: days === 0 ? 30 : 34, lineHeight: 1.1 }}>{days === 0 ? '🎉' : days}</span>
                <span style={{ fontSize: 11, fontWeight: 600, opacity: 0.7 }}>{days === 0 ? 'today' : days === 1 ? 'day' : 'days'}</span>
              </span>
              <span style={{ width: 180, display: 'flex', flexDirection: 'column', gap: 4 }}>
                <span className="pm2-row" style={{ gap: 5, fontSize: 11, fontWeight: 600, opacity: 0.75 }}>{k.icon(11)}{k.title}</span>
                <span className="clamp2" style={{ fontSize: 15, fontWeight: 600 }}>{i.data.title}</span>
                <span style={{ fontSize: 11, opacity: 0.7 }}>{d.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' })}</span>
              </span>
            </button>
          )
        })}
      </div>
    </div>
  )
}

/** BucketCard: kind, Plan trip for travel dreams, how much you want it, when, and Did it. */
function DreamCard({ item, onOpen, onTrip }: { item: Rec<Item>; onOpen: () => void; onTrip: () => void }) {
  const d = item.data, k = dream(d.kind)
  const trips = useRecords<Trip>('trip')
  const [celebrate, setCelebrate] = useState(false)
  useEffect(() => { if (!celebrate) return; const t = setTimeout(() => setCelebrate(false), 1500); return () => clearTimeout(t) }, [celebrate])
  const planned = trips.some((t) => t.data.bucketUUID === item.id)
  const doneAt = parse(d.doneAt), target = parse(d.targetDate)
  const toggle = () => {
    const now = !d.isDone
    store.update<Item>(item.id, { isDone: now, doneAt: now ? iso(new Date()) : null })
    setCelebrate(now)
  }
  return (
    <div className="pm2-dream" style={{ background: d.isDone ? `color-mix(in srgb, ${k.color} 55%, var(--canvas))` : k.color }} onClick={onOpen}>
      <div className="pm2-row">
        <span className="ic">{k.icon(14)}</span>
        <span className="pm2-spacer" />
        {d.kind === 'travel' && !d.isDone && (
          <button className="pm2-pill" onClick={(e) => { e.stopPropagation(); onTrip() }}><Luggage size={12} />{planned ? 'Trip' : 'Plan trip'}</button>
        )}
        <span style={{ fontSize: 12 }}>{'🔥'.repeat(Math.max(1, d.excitement || 1))}</span>
      </div>
      <span className="pm2-display" style={{ fontSize: 20 }}>{d.title}</span>
      {d.notes && <span style={{ fontSize: 12, opacity: 0.75, display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{d.notes}</span>}
      <div className="pm2-row">
        {d.isDone && doneAt ? <span className="pm2-row" style={{ gap: 5, fontSize: 11, fontWeight: 600 }}><BadgeCheck size={13} />Done {doneAt.toLocaleDateString(undefined, { month: 'short', year: 'numeric' })}</span>
          : target ? <span className="pm2-row" style={{ gap: 5, fontSize: 11, fontWeight: 600 }}><CalIcon size={13} />{target.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}</span>
          : <span style={{ fontSize: 11, fontWeight: 600, opacity: 0.6 }}>Someday</span>}
        <span className="pm2-spacer" />
        <button className="pm2-pill" onClick={(e) => { e.stopPropagation(); toggle() }}>
          {d.isDone ? <CircleCheck size={13} fill="currentColor" stroke="var(--canvas)" /> : <Circle size={13} />}{d.isDone ? 'Done' : 'Did it'}
        </button>
      </div>
      {celebrate && <span className="pm2-celebrate">🎉</span>}
    </div>
  )
}

/** BucketEditor: title, kind, how much you want it, a date, notes. */
function DreamEditor({ item, onClose }: { item: Rec<Item> | null; onClose: () => void }) {
  const d = item?.data
  const [title, setTitle] = useState(d?.title ?? '')
  const [notes, setNotes] = useState(d?.notes ?? '')
  const [kind, setKind] = useState<DreamKind>(d ? dream(d.kind).id : 'experience')
  const [hasDate, setHasDate] = useState(!!parse(d?.targetDate))
  const [date, setDate] = useState(toDateInput(parse(d?.targetDate) ?? addDays(new Date(), 30)))
  const [excitement, setExcitement] = useState(d?.excitement || 2)

  const save = () => {
    const t = title.trim()
    if (!t) return
    const targetDate = hasDate ? iso(startOfDay(fromInputs(date))) : null
    if (item) store.update<Item>(item.id, { title: t, notes, kind, excitement, targetDate })
    else store.create<Item>('bucket', {
      title: t, notes, kind, targetDate, excitement, isDone: false, doneAt: null, createdAt: iso(new Date()),
      place: { category: '', address: '', lat: 0, lon: 0, url: '' },
    })
    onClose()
  }

  return (
    <div className="pm2-sheet">
      <h2 className="pm2-display" style={{ fontSize: 28 }}>{item ? 'Edit' : 'New dream'}</h2>
      <input className="pm2-field" autoFocus={!item} placeholder="e.g. See the northern lights" value={title} onChange={(e) => setTitle(e.target.value)} />
      <div className="pm2-wrap" style={{ gap: 6 }}>
        {DREAMS.map((k) => (
          <button key={k.id} className={`pm2-kchip ${kind === k.id ? 'sel' : ''}`} style={{ background: k.color, opacity: kind === k.id ? 1 : 0.3 }}
            onClick={() => setKind(k.id)}>{k.icon(12)}{k.title}</button>
        ))}
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <span className="pm2-secondary" style={{ fontSize: 13 }}>How much do you want it?</span>
        <div className="pm2-seg">
          {['Nice to do', 'Really want to', "Can't wait"].map((l, i) => (
            <button key={l} className={excitement === i + 1 ? 'on' : ''} style={{ fontSize: 13 }} onClick={() => setExcitement(i + 1)}>{l}</button>
          ))}
        </div>
      </div>
      <div className="pm2-row" style={{ fontSize: 13, minHeight: 40 }}>
        <span>I have a date in mind</span>
        <Toggle on={hasDate} onChange={setHasDate} />
        <span className="pm2-spacer" />
        {hasDate && <input type="date" className="pm2-input" style={{ width: 'auto' }} value={date} onChange={(e) => e.target.value && setDate(e.target.value)} />}
      </div>
      <textarea className="pm2-field" rows={3} placeholder="Notes: why, who with, what it takes…" value={notes} onChange={(e) => setNotes(e.target.value)} />
      <div className="pm2-row">
        {item ? <button className="pm2-soft pm2-danger" onClick={() => { store.remove(item.id); onClose() }}>Delete</button>
          : <button className="pm2-soft" onClick={onClose}>Cancel</button>}
        <span className="pm2-spacer" />
        <button className="pm2-primary" style={{ width: 120 }} disabled={!title.trim()} onClick={save}>{item ? 'Save' : 'Add'}</button>
      </div>
    </div>
  )
}

// MARK: - Trips (TripsView.swift)

function TripsSection({ onOpen }: { onOpen: (id: string) => void }) {
  const trips = useRecords<Trip>('trip')
  const bookings = useRecords<Booking>('booking')
  const txns = useRecords<Txn>('transaction')
  const [assigning, setAssigning] = useState<Rec<Booking> | null>(null)
  const cutoff = addDays(startOfDay(new Date()), -14).getTime()
  const far = Number.MAX_SAFE_INTEGER
  const sorted = trips.slice()
    .sort((a, b) => (parse(a.data.start)?.getTime() ?? far) - (parse(b.data.start)?.getTime() ?? far))
    .filter((t) => (parse(t.data.end)?.getTime() ?? parse(t.data.start)?.getTime() ?? far) >= cutoff)
  const unassigned = bookings.filter((b) => !b.data.tripUUID)

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div className="pm2-row">
        <h3 className="pm2-display" style={{ fontSize: 22, margin: 0 }}>Trips</h3>
        <span className="pm2-spacer" />
        <button className="pm2-soft" onClick={() => onOpen(newTrip({ title: 'New trip' }))}><Plus size={15} />New trip</button>
      </div>
      {sorted.length === 0 && (
        <span className="pm2-secondary" style={{ fontSize: 13 }}>Plan a trip from a travel dream below, or start a new one. Flights and hotels from your email are added by themselves.</span>
      )}
      {sorted.length > 0 && (
        <div className="pm2-scrollx" style={{ gap: 14 }}>
          {sorted.map((t) => <TripCard key={t.id} trip={t} count={bookings.filter((b) => b.data.tripUUID === t.id).length}
            spent={spent(t, bookings, txns)} onClick={() => onOpen(t.id)} />)}
        </div>
      )}
      {unassigned.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <span className="pm2-row pm2-secondary" style={{ gap: 6, fontSize: 12, fontWeight: 600 }}><Mail size={13} fill="currentColor" stroke="var(--canvas)" />Found in your email</span>
          {unassigned.map((b) => {
            const s = parse(b.data.start)
            return (
              <div key={b.id} className="pm2-found">
                <span style={{ width: 20, display: 'inline-flex', justifyContent: 'center' }}>{booking(b.data.kind).icon(15)}</span>
                <span className="clamp1" style={{ fontSize: 13, fontWeight: 500, minWidth: 0 }}>{b.data.title}</span>
                {s && <span className="pm2-secondary" style={{ fontSize: 12, whiteSpace: 'nowrap' }}>{fmtShort(s)}</span>}
                <span className="pm2-spacer" />
                <button style={{ fontSize: 14, color: 'var(--ink)', whiteSpace: 'nowrap' }} onClick={() => setAssigning(b)}>Add to trip</button>
              </div>
            )
          })}
        </div>
      )}
      <ActionSheet open={!!assigning} onClose={() => setAssigning(null)} title="Add to trip" actions={assigning ? [
        ...trips.map((t) => ({ label: t.data.title || 'Untitled trip', onClick: () => store.update<Booking>(assigning.id, { tripUUID: t.id }) })),
        { label: 'New trip', icon: <Plus size={17} />, onClick: () => {
          const b = assigning.data, s = parse(b.start), e = parse(b.end)
          const id = newTrip({ title: b.location || b.title, destination: b.location, start: s ? iso(startOfDay(s)) : null, end: e ? iso(startOfDay(e)) : null })
          store.update<Booking>(assigning.id, { tripUUID: id })
          onOpen(id)
        } },
        { label: 'Not a trip', danger: true, onClick: () => store.remove(assigning.id) },
      ] : []} />
    </div>
  )
}

function TripCard({ trip, count, spent, onClick }: { trip: Rec<Trip>; count: number; spent: number; onClick: () => void }) {
  const t = trip.data, money = useMoney()
  const days = daysUntil(t)
  const s = parse(t.start), e = parse(t.end)
  const dates = !s ? '' : e && !sameDay(s, e) ? `${fmtShort(s)} – ${fmtShort(e)}` : fmtShort(s)
  const packing = t.packing ?? [], packed = t.packed ?? []
  return (
    <button className="pm2-trip" onClick={onClick}>
      <span className="pm2-row" style={{ alignItems: 'flex-start', width: '100%' }}>
        <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
          <span className="pm2-display clamp1" style={{ fontSize: 20 }}>{t.title}</span>
          <span className="clamp1" style={{ fontSize: 12, opacity: 0.75 }}>{[t.destination, dates].filter(Boolean).join(' · ')}</span>
        </span>
        {days !== null && (
          <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
            <span className="pm2-display" style={{ fontSize: 26, lineHeight: 1.1 }}>{days < 0 ? '✈️' : days === 0 ? '🎉' : days}</span>
            <span style={{ fontSize: 10, fontWeight: 600, opacity: 0.7 }}>{days < 0 ? 'now' : days === 0 ? 'today' : days === 1 ? 'day' : 'days'}</span>
          </span>
        )}
      </span>
      <span className="pm2-row" style={{ gap: 12, fontSize: 11, fontWeight: 600, opacity: 0.8 }}>
        <span className="pm2-row" style={{ gap: 5 }}><Luggage size={12} />{packed.length}/{packing.length} packed</span>
        <span className="pm2-row" style={{ gap: 5 }}><Ticket size={12} />{count} booking{count === 1 ? '' : 's'}</span>
      </span>
      {t.budget > 0 && (
        <span style={{ display: 'flex', flexDirection: 'column', gap: 4, width: '100%' }}>
          <span className="pm2-meter"><div style={{ width: `${Math.min(1, spent / t.budget) * 100}%`, background: spent > t.budget ? 'var(--critical)' : 'var(--sticker-ink)' }} /></span>
          <span style={{ fontSize: 11, fontWeight: 600, opacity: 0.8 }}>{money(spent)} of {money(t.budget)}</span>
        </span>
      )}
    </button>
  )
}

/** Shows the trip sheet for whichever trip is open (it may have just been created). */
function TripSheetHost({ id, onClose }: { id: string | null; onClose: () => void }) {
  const trips = useRecords<Trip>('trip')
  const trip = id ? trips.find((t) => t.id === id) : undefined
  return <Modal open={!!trip} onClose={onClose}>{trip && <TripSheet trip={trip} onClose={onClose} />}</Modal>
}

/** TripSheet: name and destination, countdown / nights / spent, dates and budget, bookings, packing, notes. */
function TripSheet({ trip, onClose }: { trip: Rec<Trip>; onClose: () => void }) {
  const t = trip.data
  const set = (p: Partial<Trip>) => store.update<Trip>(trip.id, p)
  const all = useRecords<Booking>('booking')
  const txns = useRecords<Txn>('transaction')
  const money = useMoney()
  const currency = useSetting<string>('currencyCode', defaultCurrency())
  const [budgetText, setBudgetText] = useState(t.budget > 0 ? String(Math.round(t.budget * 100) / 100) : '')
  const [newItem, setNewItem] = useState('')
  const [suggesting, setSuggesting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<Rec<Booking> | null>(null)
  const [addingBooking, setAddingBooking] = useState(false)
  const far = Number.MAX_SAFE_INTEGER
  const mine = all.filter((b) => b.data.tripUUID === trip.id).sort((a, b) => (parse(a.data.start)?.getTime() ?? far) - (parse(b.data.start)?.getTime() ?? far))
  const packing = t.packing ?? [], packed = t.packed ?? []
  const used = spent(trip, all, txns)
  const days = daysUntil(t), n = nights(t)

  const suggest = async () => {
    setSuggesting(true); setError(null)
    try {
      const s = parse(t.start), e = parse(t.end)
      const when = [s, e].filter((d): d is Date => !!d).map((d) => d.toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })).join(' to ')
      const user = `Trip: ${t.title}. Destination: ${t.destination || 'not set'}. Dates: ${when || 'not set'}${n !== null ? ` (${n} nights)` : ''}.
Notes: ${t.notes || 'none'}
Already on the list: ${packing.join(', ')}`
      const system = `You make packing lists. Suggest 15-25 practical items for this trip, taking the destination's usual weather in that season and the trip length into account.
Short item names (1-4 words), with quantities where useful ("3 T-shirts"). Skip anything already on the list. No categories or commentary.`
      const r = await structured<{ items: string[] }>(system, user,
        { type: 'object', properties: { items: { type: 'array', items: { type: 'string' } } }, required: ['items'], additionalProperties: false }, 'low')
      const latest = store.get<Trip>(trip.id)?.data.packing ?? packing
      const have = new Set(latest.map((p) => p.toLowerCase()))
      set({ packing: [...latest, ...r.items.filter((i) => !have.has(i.toLowerCase()))] })
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
    setSuggesting(false)
  }

  const dateField = (label: 'From' | 'To', key: 'start' | 'end') => {
    const v = parse(t[key])
    return (
      <span className="pm2-row" style={{ gap: 6 }}>
        <span className="pm2-secondary" style={{ fontSize: 12 }}>{label}</span>
        {v ? (
          <>
            <input type="date" className="pm2-input" style={{ width: 'auto' }} value={toDateInput(v)}
              onChange={(e) => e.target.value && set({ [key]: iso(startOfDay(fromInputs(e.target.value))) })} />
            <button aria-label="Clear" onClick={() => set({ [key]: null })}><CircleX size={17} color="var(--ink3)" /></button>
          </>
        ) : (
          <button className="pm2-soft" onClick={() => set({ [key]: iso(startOfDay(label === 'To' ? addDays(parse(t.start) ?? new Date(), 4) : addDays(new Date(), 30))) })}>Set date</button>
        )}
      </span>
    )
  }

  const addItem = () => {
    const v = newItem.trim()
    if (v && !packing.includes(v)) set({ packing: [...packing, v] })
    setNewItem('')
  }

  return (
    <div className="pm2-sheet">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <input className="pm2-plain pm2-display" style={{ fontSize: 28 }} placeholder="Trip name" value={t.title} onChange={(e) => set({ title: e.target.value })} />
        <span className="pm2-row">
          <MapPinned size={16} color="var(--ink3)" />
          <input className="pm2-plain" style={{ fontSize: 14 }} placeholder="Destination, e.g. Lisbon" value={t.destination} onChange={(e) => set({ destination: e.target.value })} />
        </span>
      </div>
      <div className="pm2-wrap" style={{ gap: 10 }}>
        {days !== null && days >= 0 && <span className="pm2-stat" style={{ background: 'var(--lime)' }}>{days === 0 ? 'Today!' : `${days} day${days === 1 ? '' : 's'} to go`}</span>}
        {n !== null && n > 0 && <span className="pm2-stat" style={{ background: 'var(--pink)' }}>{n} night{n === 1 ? '' : 's'}</span>}
        <span className="pm2-stat" style={{ background: t.budget > 0 && used > t.budget ? 'var(--orange)' : 'var(--cyan)' }}>
          {t.budget > 0 ? `${money(used)} of ${money(t.budget)}` : `${money(used)} spent`}
        </span>
      </div>
      <div className="pm2-wrap" style={{ gap: 14 }}>
        {dateField('From', 'start')}
        {dateField('To', 'end')}
        <span className="pm2-row" style={{ gap: 6 }}>
          <span className="pm2-secondary" style={{ fontSize: 12 }}>Budget</span>
          <input className="pm2-input" style={{ width: 90 }} inputMode="decimal" placeholder="0" value={budgetText}
            onChange={(e) => { setBudgetText(e.target.value); set({ budget: Number(e.target.value.replace(/,/g, '')) || 0 }) }} />
          <span className="pm2-muted" style={{ fontSize: 12 }}>{currency}</span>
        </span>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div className="pm2-row">
          <span style={{ fontSize: 15, fontWeight: 600 }}>Bookings</span><span className="pm2-spacer" />
          <button className="pm2-soft" onClick={() => setAddingBooking(true)}><Plus size={15} />Add</button>
        </div>
        {mine.length === 0 && <span className="pm2-muted" style={{ fontSize: 12 }}>Flights and hotels in your email show up here by themselves. You can also add them by hand.</span>}
        {mine.map((b) => {
          const s = parse(b.data.start)
          return (
            <button key={b.id} className="pm2-booking" onClick={() => setEditing(b)}>
              <span className="ic">{booking(b.data.kind).icon(13)}</span>
              <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                <span className="pm2-row" style={{ gap: 6 }}>
                  <span className="clamp1" style={{ fontSize: 13, fontWeight: 600 }}>{b.data.title}</span>
                  {b.data.source === 'email' && <span className="pm2-tag">from email</span>}
                </span>
                <span className="pm2-secondary clamp1" style={{ fontSize: 11 }}>
                  {[s ? `${fmtShort(s)}, ${s.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}` : '', b.data.confirmation ? `Ref ${b.data.confirmation}` : '', b.data.provider].filter(Boolean).join(' · ')}
                </span>
              </span>
              {b.data.amount > 0 && <span style={{ fontSize: 12, fontWeight: 600 }}>{money(b.data.amount)}</span>}
            </button>
          )
        })}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div className="pm2-row">
          <span style={{ fontSize: 15, fontWeight: 600 }}>Packing</span>
          <span className="pm2-muted" style={{ fontSize: 12 }}>{packed.length}/{packing.length}</span>
          <span className="pm2-spacer" />
          <button className="pm2-soft" disabled={suggesting} onClick={suggest}><Orb size={18} busy={suggesting} spark={false} />{suggesting ? 'Thinking…' : 'Suggest'}</button>
        </div>
        <span className="pm2-row" style={{ padding: '8px 12px', borderRadius: 12, background: 'var(--card)' }}>
          <Plus size={15} color="var(--ink3)" />
          <input className="pm2-plain" style={{ fontSize: 15 }} placeholder="Add an item" value={newItem} onChange={(e) => setNewItem(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') addItem() }} enterKeyHint="done" />
        </span>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          {packing.map((p) => {
            const on = packed.includes(p)
            return (
              <div key={p} className="pm2-pack">
                <CheckDot on={on} onClick={() => set({ packed: on ? packed.filter((x) => x !== p) : [...packed, p] })} />
                <span style={{ flex: 1, fontSize: 13, color: on ? 'var(--ink3)' : 'var(--ink)', textDecoration: on ? 'line-through' : 'none' }}>{p}</span>
                <button aria-label="Remove" style={{ width: 32, height: 32, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: 'var(--ink3)' }}
                  onClick={() => set({ packing: packing.filter((x) => x !== p), packed: packed.filter((x) => x !== p) })}><X size={12} /></button>
              </div>
            )
          })}
        </div>
      </div>

      <textarea className="pm2-field" rows={2} placeholder="Notes: where to stay, what to see, who's coming…" value={t.notes} onChange={(e) => set({ notes: e.target.value })} />
      <div className="pm2-row">
        <button className="pm2-soft pm2-danger" onClick={() => {
          for (const b of mine) store.update<Booking>(b.id, { tripUUID: '' })
          store.remove(trip.id); onClose()
        }}>Delete trip</button>
        {error && <span style={{ fontSize: 11, color: 'var(--critical)', minWidth: 0 }} className="clamp2">{error}</span>}
        <span className="pm2-spacer" />
        <button className="pm2-primary" style={{ width: 110 }} onClick={onClose}>Done</button>
      </div>

      <Modal open={addingBooking} onClose={() => setAddingBooking(false)}>{addingBooking && <BookingEditor rec={null} tripID={trip.id} onClose={() => setAddingBooking(false)} />}</Modal>
      <Modal open={!!editing} onClose={() => setEditing(null)}>{editing && <BookingEditor rec={editing} tripID={trip.id} onClose={() => setEditing(null)} />}</Modal>
    </div>
  )
}

const toLocal = (d: Date) => `${toDateInput(d)}T${toTimeInput(d)}`
const fromLocal = (v: string): Date => { const [date, t] = v.split('T'); return fromInputs(date, t) }

/** BookingEditor: kind, what, with, where, reference, when, cost. */
function BookingEditor({ rec, tripID, onClose }: { rec: Rec<Booking> | null; tripID: string; onClose: () => void }) {
  const b = rec?.data
  const currency = useSetting<string>('currencyCode', defaultCurrency())
  const [kind, setKind] = useState<BookingKind>(b ? booking(b.kind).id : 'flight')
  const [title, setTitle] = useState(b?.title ?? '')
  const [provider, setProvider] = useState(b?.provider ?? '')
  const [location, setLocation] = useState(b?.location ?? '')
  const [confirmation, setConfirmation] = useState(b?.confirmation ?? '')
  const [hasStart, setHasStart] = useState(b ? !!parse(b.start) : true)
  const [start, setStart] = useState(toLocal(parse(b?.start) ?? addDays(new Date(), 30)))
  const [hasEnd, setHasEnd] = useState(!!parse(b?.end))
  const [end, setEnd] = useState(toLocal(parse(b?.end) ?? addDays(new Date(), 33)))
  const [amount, setAmount] = useState(b && b.amount > 0 ? String(Math.round(b.amount * 100) / 100) : '')

  const save = () => {
    if (!title.trim()) return
    const patch: Partial<Booking> = {
      kind, title: title.trim(), provider, confirmation, location,
      start: hasStart ? iso(fromLocal(start)) : null, end: hasEnd ? iso(fromLocal(end)) : null,
      amount: Math.abs(Number(amount.replace(/,/g, '')) || 0),
    }
    if (rec) store.update<Booking>(rec.id, patch)
    else store.create<Booking>('booking', {
      tripUUID: tripID, kind, title: '', provider: '', confirmation: '', location: '', start: null, end: null, amount: 0,
      source: 'manual', sourceID: '', createdAt: iso(new Date()), ...patch,
    } as Booking)
    onClose()
  }

  return (
    <div className="pm2-sheet" style={{ gap: 14 }}>
      <h2 className="pm2-display" style={{ fontSize: 24 }}>{rec ? 'Edit booking' : 'New booking'}</h2>
      <div className="pm2-wrap" style={{ gap: 6 }}>
        {BOOKINGS.map((k) => (
          <button key={k.id} className={`pm2-chip ${kind === k.id ? 'on' : ''}`} style={{ fontSize: 12, fontWeight: 500, padding: '6px 10px' }} onClick={() => setKind(k.id)}>
            {k.icon(12)}{k.title}
          </button>
        ))}
      </div>
      <div className="pm2-grid2">
        <span className="l">What</span><input className="pm2-input" placeholder="Cairo → Lisbon, MS777" value={title} onChange={(e) => setTitle(e.target.value)} />
        <span className="l">With</span><input className="pm2-input" placeholder="Airline, hotel, company" value={provider} onChange={(e) => setProvider(e.target.value)} />
        <span className="l">Where</span><input className="pm2-input" placeholder="City or address" value={location} onChange={(e) => setLocation(e.target.value)} />
        <span className="l">Reference</span><input className="pm2-input" placeholder="Booking code" value={confirmation} onChange={(e) => setConfirmation(e.target.value)} />
        <span className="l">{kind === 'hotel' ? 'Check-in' : 'Starts'}</span>
        <span className="pm2-row"><Toggle on={hasStart} onChange={setHasStart} />{hasStart && <input type="datetime-local" className="pm2-input" value={start} onChange={(e) => e.target.value && setStart(e.target.value)} />}</span>
        <span className="l">{kind === 'hotel' ? 'Check-out' : 'Ends'}</span>
        <span className="pm2-row"><Toggle on={hasEnd} onChange={setHasEnd} />{hasEnd && <input type="datetime-local" className="pm2-input" value={end} onChange={(e) => e.target.value && setEnd(e.target.value)} />}</span>
        <span className="l">Cost</span>
        <span className="pm2-row"><input className="pm2-input" style={{ width: 120 }} inputMode="decimal" placeholder="0" value={amount} onChange={(e) => setAmount(e.target.value)} /><span className="pm2-muted">{currency}</span></span>
      </div>
      <div className="pm2-row">
        {rec && <button className="pm2-soft pm2-danger" onClick={() => { store.remove(rec.id); onClose() }}>Delete</button>}
        <span className="pm2-spacer" />
        <button className="pm2-soft" onClick={onClose}>Cancel</button>
        <button className="pm2-primary" style={{ width: 110 }} disabled={!title.trim()} onClick={save}>Save</button>
      </div>
    </div>
  )
}

// MARK: - Go to (GoToView.swift)

function GoToSection() {
  const places = useRecords<Item>('bucket').filter((p) => p.data.kind === 'place')
    .sort((a, b) => (b.data.createdAt ?? '').localeCompare(a.data.createdAt ?? ''))
  const [category, setCategory] = useState<PlaceCategory | null>(null)
  const [showVisited, setShowVisited] = useState(false)
  const [selected, setSelected] = useState<string | null>(null)
  const [editing, setEditing] = useState<Rec<Item> | null>(null)
  const [adding, setAdding] = useState(false)

  const shown = places.filter((p) => (!category || placeCat(p.data.place?.category).id === category) && !!p.data.isDone === showVisited)
  const pins = places.filter((p) => hasLocation(p.data.place) && (!category || placeCat(p.data.place?.category).id === category))
  const toGo = places.filter((p) => !p.data.isDone).length, been = places.length - toGo

  const select = (id: string) => {
    setSelected(id)
    const p = places.find((x) => x.id === id)
    if (p && !!p.data.isDone !== showVisited) setShowVisited(!!p.data.isDone)
    setTimeout(() => document.getElementById(`pm2-place-${id}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' }), 50)
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div className="pm2-row" style={{ alignItems: 'flex-start' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <span className="pm2-display" style={{ fontSize: 24 }}>Go to</span>
          <span className="pm2-secondary" style={{ fontSize: 13 }}>{places.length === 0 ? 'Places you liked or want to try.' : `${toGo} to go · ${been} been`}</span>
        </div>
        <span className="pm2-spacer" />
        <button className="pm2-soft" onClick={() => setAdding(true)}><Plus size={15} />Add place</button>
      </div>

      {places.some((p) => hasLocation(p.data.place)) && (
        <PinMap height={260} selected={selected} onSelect={select}
          pins={pins.map((p) => ({ id: p.id, lat: Number(p.data.place!.lat), lon: Number(p.data.place!.lon), color: p.data.isDone ? '#9a9aa2' : placeCat(p.data.place?.category).color, icon: placeCat(p.data.place?.category).icon(14) }))} />
      )}

      <div className="pm2-scrollx">
        <button className="pm2-kchip" style={{ background: 'var(--inverse)', color: 'var(--on-inverse)' }} onClick={() => setShowVisited(!showVisited)}>
          {showVisited ? <BadgeCheck size={12} /> : <MapPin size={12} />}{showVisited ? 'Been' : 'To go'}
        </button>
        <span className="pm2-divider" />
        {PLACES.map((c) => {
          const n = places.filter((p) => placeCat(p.data.place?.category).id === c.id && !!p.data.isDone === showVisited).length
          return n > 0 ? (
            <button key={c.id} className="pm2-kchip" style={{ background: c.color, opacity: !category || category === c.id ? 1 : 0.3 }}
              onClick={() => setCategory(category === c.id ? null : c.id)}>{c.icon(12)}{c.title} {n}</button>
          ) : null
        })}
      </div>

      {shown.length === 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, padding: '30px 0', color: 'var(--ink2)', textAlign: 'center' }}>
          <MapIcon size={36} strokeWidth={1.2} />
          <span style={{ fontSize: 14 }}>{places.length === 0 ? 'Loved a restaurant, a shop or a museum? Add it by name or paste its Google or Apple Maps link, and it lands here on your map.'
            : showVisited ? 'No places ticked off yet.' : 'Nothing here in this filter.'}</span>
          {places.length === 0 && <button className="pm2-soft" onClick={() => setAdding(true)}>Add your first place</button>}
        </div>
      )}
      {shown.map((p) => <PlaceCard key={p.id} place={p} highlighted={selected === p.id} onOpen={() => setEditing(p)} />)}

      <Modal open={adding} onClose={() => setAdding(false)}>{adding && <PlaceEditor place={null} onClose={() => setAdding(false)} />}</Modal>
      <Modal open={!!editing} onClose={() => setEditing(null)}>{editing && <PlaceEditor place={editing} onClose={() => setEditing(null)} />}</Modal>
    </div>
  )
}

function PlaceCard({ place, highlighted, onOpen }: { place: Rec<Item>; highlighted: boolean; onOpen: () => void }) {
  const d = place.data, p = d.place, c = placeCat(p?.category)
  const [directions, setDirections] = useState(false)
  const located = hasLocation(p)
  return (
    <>
      <div id={`pm2-place-${place.id}`} className={`pm2-place ${highlighted ? 'hl' : ''}`} onClick={onOpen}>
        <span className="ic" style={{ background: c.color }}>{c.icon(16)}</span>
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span className="clamp2" style={{ fontSize: 16, fontWeight: 600 }}>{d.title}</span>
          <span className="pm2-secondary clamp2" style={{ fontSize: 12 }}>{[c.title, p?.address].filter(Boolean).join(' · ')}</span>
          {d.notes && <span style={{ fontSize: 13, paddingTop: 2, display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{d.notes}</span>}
          <div className="pm2-wrap" style={{ paddingTop: 4 }} onClick={(e) => e.stopPropagation()}>
            {(located || /^https?:/.test(p?.url ?? '')) && (
              <button className="pm2-dir" onClick={() => setDirections(true)}><Navigation size={13} fill="currentColor" />Directions</button>
            )}
            <button className="pm2-soft" style={{ fontSize: 12, background: 'var(--canvas)' }}
              onClick={() => store.update<Item>(place.id, { isDone: !d.isDone, doneAt: !d.isDone ? iso(new Date()) : null })}>
              {d.isDone ? <CircleCheck size={13} fill="currentColor" stroke="var(--canvas)" /> : <Circle size={13} />}{d.isDone ? 'Been there' : 'Went'}
            </button>
          </div>
        </div>
      </div>
      <ActionSheet open={directions} onClose={() => setDirections(false)} title="Directions" actions={[
        { label: 'Apple Maps', icon: <MapIcon size={17} />, onClick: () => window.orbit.openExternal(mapsLink('apple', d.title, p)) },
        { label: 'Google Maps', icon: <Globe size={17} />, onClick: () => window.orbit.openExternal(mapsLink('google', d.title, p)) },
      ]} />
    </>
  )
}

/** MapsLink on the Mac: directions in Apple Maps or Google Maps (the link the place came from when there are no coordinates). */
function mapsLink(app: 'apple' | 'google', name: string, p?: Place): string {
  const located = hasLocation(p), link = p?.url ?? '', address = p?.address ?? ''
  const where = [name, address].filter(Boolean).join(', ')
  if (app === 'apple') {
    if (!located && link.includes('maps.apple')) return link
    const q = located ? `daddr=${p!.lat},${p!.lon}&q=${encodeURIComponent(name)}` : `daddr=${encodeURIComponent(where)}`
    return `https://maps.apple.com/?${q}`
  }
  if (!located && link.includes('google.')) return link
  return `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(located ? `${p!.lat},${p!.lon}` : where)}`
}

// MARK: Map (Apple Maps on the iPhone; OpenStreetMap tiles here)

interface Pin { id: string; lat: number; lon: number; color: string; icon: ReactNode }

/** A map that frames every pin, never closer than a neighbourhood (GoToSection.fit). Tap a pin to select it. */
function PinMap({ pins, height, selected, onSelect, minSpan = 0.03 }: {
  pins: Pin[]; height: number; selected?: string | null; onSelect?: (id: string) => void; minSpan?: number
}) {
  const ref = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(0)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    setWidth(el.clientWidth)
    const ro = new ResizeObserver(() => setWidth(el.clientWidth))
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const project = (lat: number, lon: number, z: number) => {
    const size = 256 * 2 ** z, r = (Math.max(-85, Math.min(85, lat)) * Math.PI) / 180
    return { x: ((lon + 180) / 360) * size, y: ((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * size }
  }

  let content: ReactNode = null
  if (width > 0 && pins.length) {
    const lats = pins.map((p) => p.lat), lons = pins.map((p) => p.lon)
    const cLat = (Math.min(...lats) + Math.max(...lats)) / 2, cLon = (Math.min(...lons) + Math.max(...lons)) / 2
    const sLat = Math.max(minSpan, (Math.max(...lats) - Math.min(...lats)) * 1.4), sLon = Math.max(minSpan, (Math.max(...lons) - Math.min(...lons)) * 1.4)
    let z = 18
    for (; z > 1; z--) {
      const a = project(cLat + sLat / 2, cLon - sLon / 2, z), b = project(cLat - sLat / 2, cLon + sLon / 2, z)
      if (b.x - a.x <= width && b.y - a.y <= height) break
    }
    const c = project(cLat, cLon, z)
    const left = c.x - width / 2, top = c.y - height / 2, n = 2 ** z
    const tiles: ReactNode[] = []
    for (let tx = Math.floor(left / 256); tx <= Math.floor((left + width) / 256); tx++) {
      for (let ty = Math.floor(top / 256); ty <= Math.floor((top + height) / 256); ty++) {
        if (ty < 0 || ty >= n) continue
        const wx = ((tx % n) + n) % n
        tiles.push(<img key={`${tx}/${ty}`} alt="" src={`https://tile.openstreetmap.org/${z}/${wx}/${ty}.png`}
          style={{ left: tx * 256 - left, top: ty * 256 - top }} />)
      }
    }
    content = (
      <>
        {tiles}
        {pins.map((p) => {
          const at = project(p.lat, p.lon, z)
          return (
            <button key={p.id} className={`pm2-pin ${selected === p.id ? 'sel' : ''}`} style={{ left: at.x - left, top: at.y - top, zIndex: selected === p.id ? 2 : 1 }}
              onClick={(e) => { e.stopPropagation(); onSelect?.(p.id) }}>
              <span className="head" style={{ background: p.color }}>{p.icon}</span>
              <span className="tip" />
            </button>
          )
        })}
        <span className="attr">© OpenStreetMap</span>
      </>
    )
  }
  return <div ref={ref} className="pm2-map" style={{ height }}>{content}</div>
}

// MARK: Place lookup (PlaceLookup.swift, with OpenStreetMap's Photon search instead of Apple Maps)

interface Found { name: string; address: string; lat: number | null; lon: number | null; category: PlaceCategory; url: string }

async function getJSON(url: string): Promise<any> {
  if (isNative) {
    const r = await CapacitorHttp.get({ url, headers: { Accept: 'application/json' } })
    return typeof r.data === 'string' ? JSON.parse(r.data) : r.data
  }
  const r = await fetch(url)
  if (!r.ok) throw new Error(`Search failed (${r.status})`)
  return r.json()
}

const firstURL = (text: string): string | null => text.match(/https?:\/\/[^\s]+/i)?.[0] ?? null

/** The Mac's word list for names Apple Maps doesn't categorise. */
function categoryFromName(name: string): PlaceCategory {
  const n = name.toLowerCase()
  const words: [PlaceCategory, string[]][] = [
    ['cafe', ['cafe', 'café', 'coffee', 'roaster', 'tea house', 'كافيه', 'قهوة']],
    ['bar', [' bar', 'pub', 'lounge', 'rooftop']],
    ['food', ['restaurant', 'kitchen', 'grill', 'pizza', 'burger', 'sushi', 'bistro', 'diner', 'koshary', 'شاورما', 'مطعم']],
    ['museum', ['museum', 'gallery', 'متحف']],
    ['shop', ['mall', 'store', 'shop', 'market', 'boutique', 'outlet']],
    ['park', ['park', 'garden', 'beach', 'حديقة']],
    ['hotel', ['hotel', 'resort', 'inn', 'hostel', 'فندق']],
    ['attraction', ['temple', 'pyramid', 'castle', 'citadel', 'tower', 'palace', 'cinema', 'theatre', 'theater', 'zoo']],
  ]
  return words.find(([, ws]) => ws.some((w) => n.includes(w)))?.[0] ?? 'other'
}

/** OpenStreetMap's tags for the place, mapped like the Mac maps Apple's point-of-interest categories. */
function categoryFromOSM(key: string, value: string, name: string): PlaceCategory {
  if (key === 'amenity') {
    if (['restaurant', 'fast_food', 'food_court', 'ice_cream'].includes(value)) return 'food'
    if (value === 'cafe') return 'cafe'
    if (['bar', 'pub', 'nightclub', 'biergarten'].includes(value)) return 'bar'
    if (['theatre', 'cinema'].includes(value)) return 'attraction'
  }
  if (key === 'shop') return value === 'bakery' ? 'food' : 'shop'
  if (key === 'tourism') {
    if (['museum', 'gallery'].includes(value)) return 'museum'
    if (['hotel', 'hostel', 'guest_house', 'motel', 'apartment'].includes(value)) return 'hotel'
    if (['theme_park', 'zoo', 'aquarium', 'attraction', 'viewpoint'].includes(value)) return 'attraction'
    if (value === 'camp_site') return 'park'
  }
  if (key === 'leisure') {
    if (['park', 'garden', 'nature_reserve', 'beach_resort', 'marina'].includes(value)) return 'park'
    if (['stadium', 'water_park'].includes(value)) return 'attraction'
  }
  if (key === 'natural' && value === 'beach') return 'park'
  if (key === 'historic') return 'attraction'
  return categoryFromName(name)
}

const appleMapsURL = (name: string, lat: number, lon: number) => `https://maps.apple.com/?q=${encodeURIComponent(name)}&ll=${lat},${lon}`

function fromFeature(f: any, url = ''): Found {
  const p = f?.properties ?? {}, [lon, lat] = f?.geometry?.coordinates ?? [null, null]
  const name = p.name ?? [p.street, p.housenumber].filter(Boolean).join(' ') ?? ''
  const street = p.street ? [p.housenumber, p.street].filter(Boolean).join(' ') : ''
  const address = [street, p.district ?? p.locality, p.city].filter((x) => x && x !== name).join(', ')
  return {
    name, address, lat: typeof lat === 'number' ? lat : null, lon: typeof lon === 'number' ? lon : null,
    category: categoryFromOSM(p.osm_key ?? '', p.osm_value ?? '', name),
    url: url || (typeof lat === 'number' ? appleMapsURL(name, lat, lon) : ''),
  }
}

const subtitleOf = (f: any) => {
  const p = f?.properties ?? {}
  return [p.street ? [p.housenumber, p.street].filter(Boolean).join(' ') : '', p.district ?? p.locality, p.city, p.country].filter(Boolean).join(', ')
}

async function search(query: string, near?: { lat: number; lon: number } | null, limit = 6): Promise<any[]> {
  const q = new URLSearchParams({ q: query, limit: String(limit) })
  if (near) { q.set('lat', String(near.lat)); q.set('lon', String(near.lon)) }
  const r = await getJSON(`https://photon.komoot.io/api/?${q.toString()}`)
  return Array.isArray(r?.features) ? r.features.filter((f: any) => f?.properties?.name || f?.properties?.street) : []
}

function meters(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const R = 6371000, toR = Math.PI / 180
  const dLat = (b.lat - a.lat) * toR, dLon = (b.lon - a.lon) * toR
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * toR) * Math.cos(b.lat * toR) * Math.sin(dLon / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(h))
}
const coordOf = (f: any) => { const [lon, lat] = f?.geometry?.coordinates ?? []; return typeof lat === 'number' ? { lat, lon } : null }

/** PlaceLookup.parse: the place name and coordinates in a Google or Apple Maps link. */
function parseLink(link: string): { name: string; coord: { lat: number; lon: number } | null } {
  let s = link
  try { s = decodeURIComponent(link) } catch { /* keep as is */ }
  let params: URLSearchParams
  try { params = new URL(link).searchParams } catch { params = new URLSearchParams() }
  const q = (k: string) => params.get(k)?.trim() || null
  const coord = (t: string | null) => {
    const parts = (t ?? '').split(',').map((x) => Number(x.trim()))
    if (parts.length < 2 || parts.some((x) => isNaN(x))) return null
    const [lat, lon] = parts
    return Math.abs(lat) <= 90 && Math.abs(lon) <= 180 && (lat !== 0 || lon !== 0) ? { lat, lon } : null
  }
  let name = '', c: { lat: number; lon: number } | null = null
  if (s.includes('maps.apple')) {
    name = q('q') ?? q('name') ?? ''
    c = coord(q('ll')) ?? coord(q('coordinate')) ?? coord(q('sll'))
    if (!name && q('address')) name = q('address')!
  } else {
    const place = s.match(/\/place\/([^/@]+)/)
    if (place) name = place[1].replace(/\+/g, ' ')
    const d = s.match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/)
    const at = s.match(/@(-?\d+\.\d+),(-?\d+\.\d+)/)
    if (d) c = coord(`${d[1]},${d[2]}`)
    else if (at) c = coord(`${at[1]},${at[2]}`)
    const query = q('q') ?? q('query')
    if (!name && query) { const qc = coord(query); if (qc) c = c ?? qc; else name = query.replace(/\+/g, ' ') }
  }
  return { name: name.trim(), coord: c }
}

/** Google Maps (including maps.app.goo.gl short links) and Apple Maps links. */
async function fromLink(link: string): Promise<Found | null> {
  let url = link
  try {
    const host = new URL(link).hostname.toLowerCase()
    if ((host.includes('goo.gl') || host === 'g.co' || host.endsWith('page.link')) && isNative) {
      const r = await CapacitorHttp.get({ url: link, headers: { 'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Mobile' } })
      if (r.url) url = r.url
    }
  } catch { /* use the link as given */ }
  const { name, coord } = parseLink(url)
  if (!name && !coord) return null
  if (name) {
    const results = await search(name, coord).catch(() => [])
    const best = results.slice().sort((a, b) => (coord ? meters(coordOf(a) ?? coord, coord) - meters(coordOf(b) ?? coord, coord) : 0))[0]
    const at = best ? coordOf(best) : null
    if (best && (!coord || (at && meters(at, coord) < 400))) return { ...fromFeature(best, link), name }
  }
  if (coord) {
    const r = await getJSON(`https://photon.komoot.io/reverse?lat=${coord.lat}&lon=${coord.lon}&limit=5&radius=0.06`).catch(() => null)
    const near = (Array.isArray(r?.features) ? r.features : []).filter((f: any) => f?.properties?.name)
      .sort((a: any, b: any) => meters(coordOf(a) ?? coord, coord) - meters(coordOf(b) ?? coord, coord))[0]
    if (near) { const f = fromFeature(near, link); return name ? { ...f, name } : f }
    return { name: name || 'Pinned place', address: '', lat: coord.lat, lon: coord.lon, category: categoryFromName(name), url: link }
  }
  return { name, address: '', lat: null, lon: null, category: categoryFromName(name), url: link }
}

/** A link or a name. Null when nothing could be found. */
async function resolve(input: string): Promise<Found | null> {
  const text = input.trim()
  if (!text) return null
  const link = firstURL(text)
  if (link) { const f = await fromLink(link).catch(() => null); if (f) return f }
  const first = (await search(text, null, 1).catch(() => []))[0]
  return first ? fromFeature(first) : null
}

/** PlaceEditor: search a place or paste a maps link, then name, kind, notes and whether you've been. */
function PlaceEditor({ place, onClose }: { place: Rec<Item> | null; onClose: () => void }) {
  const d = place?.data, p = d?.place
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<any[]>([])
  const [found, setFound] = useState<Found | null>(null)
  const [name, setName] = useState(d?.title ?? '')
  const [category, setCategory] = useState<PlaceCategory>(d ? placeCat(p?.category).id : 'food')
  const [notes, setNotes] = useState(d?.notes ?? '')
  const [been, setBeen] = useState(!!d?.isDone)
  const [looking, setLooking] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const seq = useRef(0)

  const apply = (f: Found) => { setFound(f); setName(f.name); setCategory(f.category); setResults([]) }

  const lookUp = async (text: string) => {
    setLooking(true); setMessage(null)
    const f = await resolve(text)
    if (f) apply(f)
    else {
      const isLink = !!firstURL(text)
      setMessage(isLink ? "Couldn't read that link. Try the place's name instead." : 'No place found. Type its name below to save it anyway.')
      if (!isLink) setName(text)
    }
    setLooking(false)
  }

  // Live suggestions as you type (MKLocalSearchCompleter on the iPhone); a pasted link is looked up at once.
  useEffect(() => {
    const q = query.trim()
    const n = ++seq.current
    if (firstURL(q)) { setResults([]); lookUp(q); return }
    if (q.length < 2) { setResults([]); return }
    const t = setTimeout(() => { search(q).then((r) => { if (seq.current === n) setResults(r) }).catch(() => {}) }, 300)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query])

  const coord = found && found.lat !== null && found.lon !== null ? { lat: found.lat, lon: found.lon! }
    : hasLocation(p) ? { lat: Number(p!.lat), lon: Number(p!.lon) } : null

  const save = () => {
    const title = name.trim()
    if (!title) return
    const doneChange = !!d?.isDone !== been ? { isDone: been, doneAt: been ? iso(new Date()) : null } : {}
    // Like the Mac: a looked-up place brings its address, link and (when it has one) its pin; otherwise they stay.
    const located = !!found && found.lat !== null && found.lon !== null
    const nextPlace: Place = {
      category, address: found ? found.address : p?.address ?? '',
      lat: located ? found!.lat! : Number(p?.lat) || 0, lon: located ? found!.lon! : Number(p?.lon) || 0,
      url: found ? found.url : p?.url ?? '',
    }
    if (place) store.update<Item>(place.id, { title, kind: 'place', notes, place: nextPlace, ...doneChange })
    else store.create<Item>('bucket', {
      title, notes, kind: 'place', targetDate: null, excitement: 2, isDone: been, doneAt: been ? iso(new Date()) : null,
      createdAt: iso(new Date()), place: nextPlace,
    })
    onClose()
  }

  const q = query.trim()
  return (
    <div className="pm2-sheet pm2-own-close" style={{ gap: 14 }}>
      <div className="pm2-row">
        <h2 className="pm2-display" style={{ fontSize: 26 }}>{place ? 'Edit place' : 'Add a place'}</h2>
        <span className="pm2-spacer" />
        <button className="pm2-soft" onClick={onClose}>Cancel</button>
      </div>
      {!place && (
        <>
          <span className="pm2-row" style={{ padding: 12, borderRadius: 12, background: 'var(--card)' }}>
            <Search size={16} color="var(--ink3)" />
            <input className="pm2-plain" style={{ fontSize: 15 }} autoFocus autoCapitalize="words" autoCorrect="off"
              placeholder="Search a place, or paste a Google or Apple Maps link" value={query}
              onChange={(e) => { setQuery(e.target.value); setFound(null) }} onKeyDown={(e) => { if (e.key === 'Enter') lookUp(query) }} />
            {looking && <Orb size={16} busy spark={false} />}
          </span>
          {!found && results.length > 0 && (
            <div className="pm2-results">
              {results.map((r, i) => (
                <button key={i} onClick={() => apply(fromFeature(r))}>
                  <span style={{ fontSize: 14, fontWeight: 500 }}>{r.properties?.name ?? r.properties?.street}</span>
                  {subtitleOf(r) && <span className="pm2-secondary" style={{ fontSize: 12 }}>{subtitleOf(r)}</span>}
                </button>
              ))}
            </div>
          )}
          {!found && results.length === 0 && q.length >= 2 && !firstURL(q) && !looking && (
            <button className="pm2-soft" style={{ alignSelf: 'flex-start', whiteSpace: 'normal', textAlign: 'left' }} onClick={() => lookUp(query)}>
              <Search size={14} />Search Maps for “{q}”
            </button>
          )}
          {message && <span style={{ fontSize: 12, color: 'var(--orange)' }}>{message}</span>}
        </>
      )}

      {coord && <PinMap key={`${coord.lat},${coord.lon}`} height={170} minSpan={0.0054}
        pins={[{ id: 'here', lat: coord.lat, lon: coord.lon, color: placeCat(category).color, icon: placeCat(category).icon(14) }]} />}

      {(found || place || name) && (
        <>
          <input className="pm2-field" style={{ fontWeight: 600 }} placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} />
          {(found?.address ?? p?.address) && <span className="pm2-row pm2-secondary" style={{ gap: 5, fontSize: 12 }}><MapPin size={12} />{found?.address ?? p?.address}</span>}
          <div className="pm2-wrap" style={{ gap: 6 }}>
            {PLACES.map((c) => (
              <button key={c.id} className={`pm2-kchip ${category === c.id ? 'sel' : ''}`} style={{ background: c.color, opacity: category === c.id ? 1 : 0.35 }}
                onClick={() => setCategory(c.id)}>{c.icon(12)}{c.title}</button>
            ))}
          </div>
          <textarea className="pm2-field" rows={2} placeholder="What did you like? What to order, who to go with…" value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="pm2-row" style={{ fontSize: 14, minHeight: 40 }}>
            <span>I've been here</span><span className="pm2-spacer" /><Toggle on={been} onChange={setBeen} />
          </div>
          <div className="pm2-row">
            {place && <button className="pm2-soft pm2-danger" onClick={() => { store.remove(place.id); onClose() }}><Trash2 size={14} />Delete</button>}
            <span className="pm2-spacer" />
            <button className="pm2-primary" disabled={!name.trim()} onClick={save}>{place ? 'Save' : 'Save to Go to'}</button>
          </div>
        </>
      )}
    </div>
  )
}
