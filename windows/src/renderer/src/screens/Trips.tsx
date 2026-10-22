// Trips on the Bucket list screen: trip cards, the trip sheet (bookings, packing, budget) and bookings found in email.
// Same `trip` / `booking` records as the Mac.
import { useState } from 'react'
import { Plane, Hotel, TrainFront, Car, Ticket, Bookmark, Plus, Trash2, Sparkles, Mail, Luggage, X } from 'lucide-react'
import { store, useRecords, Rec } from '@/lib/store'
import { Trip, Booking, BookingKind, BOOKING_KINDS, bookingKind, Txn, Bucket } from '@/lib/models'
import { iso, parse, startOfDay, addDays, daysBetween, fmtDay, fmtTime } from '@/lib/dates'
import { structured, useKeys } from '@/lib/ai'
import { Card, Modal, DateInput, FormRow, useMoney, EmptyHint } from '@/components/ui'

const KIND_ICON: Record<BookingKind, (s: number) => JSX.Element> = {
  flight: (s) => <Plane size={s} />, hotel: (s) => <Hotel size={s} />, train: (s) => <TrainFront size={s} />,
  car: (s) => <Car size={s} />, activity: (s) => <Ticket size={s} />, other: (s) => <Bookmark size={s} />,
}
const bookingIcon = (k: string, s = 14) => (KIND_ICON[k as BookingKind] ?? KIND_ICON.other)(s)

const short = (d: Date) => fmtDay(d, { day: 'numeric', month: 'short' })

export function tripDates(t: Trip): string {
  const s = parse(t.start), e = parse(t.end)
  if (!s) return 'Dates not set'
  return e && !sameDayish(s, e) ? `${short(s)} – ${short(e)}` : short(s)
}
const sameDayish = (a: Date, b: Date) => startOfDay(a).getTime() === startOfDay(b).getTime()

/** Bookings on the trip plus expenses dated during it. */
export function budgetUsed(trip: Rec<Trip>, bookings: Rec<Booking>[], txns: Rec<Txn>[]): number {
  const booked = bookings.filter((b) => b.data.tripUUID === trip.id).reduce((n, b) => n + Math.abs(Number(b.data.amount) || 0), 0)
  const s = parse(trip.data.start)
  if (!s) return booked
  const from = startOfDay(s), to = addDays(startOfDay(parse(trip.data.end) ?? s), 1)
  const spent = txns.filter((t) => { const d = parse(t.data.date); return t.data.amount < 0 && !!d && d >= from && d < to }).reduce((n, t) => n - t.data.amount, 0)
  return booked + spent
}

function countdown(t: Trip): { big: string; small: string } {
  const s = parse(t.start)
  if (!s) return { big: '—', small: 'no date' }
  const today = startOfDay(new Date())
  const n = daysBetween(today, s)
  if (n > 0) return { big: String(n), small: n === 1 ? 'day to go' : 'days to go' }
  const e = parse(t.end) ?? s
  if (daysBetween(today, e) >= 0) return { big: '✈️', small: 'on the trip' }
  return { big: '✓', small: 'been there' }
}

export function newTripFromBucket(item: Rec<Bucket>): string {
  return store.create<Trip>('trip', {
    title: item.data.title, destination: '', start: item.data.targetDate, end: null, bucketUUID: item.id, budget: 0,
    notes: '', packing: [], packed: [], createdAt: iso(new Date()),
  })
}

// MARK: Section on the Bucket list

export function TripsSection({ openTrip, onOpen }: { openTrip: string | null; onOpen: (id: string | null) => void }) {
  const trips = useRecords<Trip>('trip')
  const bookings = useRecords<Booking>('booking')
  const txns = useRecords<Txn>('transaction')
  const money = useMoney()
  const today = startOfDay(new Date())
  const sorted = trips.slice().sort((a, b) => {
    const pa = (parse(a.data.end ?? a.data.start)?.getTime() ?? Infinity) < today.getTime() ? 1 : 0
    const pb = (parse(b.data.end ?? b.data.start)?.getTime() ?? Infinity) < today.getTime() ? 1 : 0
    return pa - pb || (a.data.start ?? '9').localeCompare(b.data.start ?? '9')
  })
  const unassigned = bookings.filter((b) => !b.data.tripUUID)
  const add = () => onOpen(store.create<Trip>('trip', { title: '', destination: '', start: null, end: null, bucketUUID: '', budget: 0, notes: '', packing: [], packed: [], createdAt: iso(new Date()) }))
  const current = openTrip ? trips.find((t) => t.id === openTrip) : undefined

  return (
    <div className="col" style={{ gap: 12 }}>
      <div className="row">
        <h3 className="section-title">Trips</h3>
        <span className="spacer" />
        <button className="btn-soft" onClick={add}><Plus size={14} />New trip</button>
      </div>
      {trips.length === 0 && <EmptyHint icon={<Luggage size={14} />} text="Plan a trip from a travel dream, or start one here. Bookings Orbit finds in your email land here too." />}
      {sorted.length > 0 && (
        <div className="row" style={{ gap: 14, overflowX: 'auto', paddingBottom: 2, alignItems: 'stretch' }}>
          {sorted.map((t) => {
            const c = countdown(t.data)
            const used = budgetUsed(t, bookings, txns)
            const packing = t.data.packing ?? []
            const packed = (t.data.packed ?? []).filter((p) => packing.includes(p)).length
            return (
              <button key={t.id} className="card col" style={{ width: 330, flex: 'none', gap: 10, padding: 16, textAlign: 'left' }} onClick={() => onOpen(t.id)}>
                <div className="row" style={{ gap: 12, alignItems: 'flex-start' }}>
                  <div style={{ minWidth: 0, flex: 1 }}>
                    <div className="clamp2" style={{ fontSize: 16, fontWeight: 700 }}>{t.data.title || 'New trip'}</div>
                    <div className="secondary clamp1" style={{ fontSize: 12 }}>{[t.data.destination, tripDates(t.data)].filter(Boolean).join(' · ')}</div>
                  </div>
                  <div className="days-badge" style={{ background: 'var(--cyan)' }}>{c.big}<small>{c.small}</small></div>
                </div>
                <div className="row" style={{ gap: 6, fontSize: 11, fontWeight: 600 }}>
                  <span className="pill compact" style={{ background: 'var(--mint)' }}><Luggage size={11} />Packed {packed}/{packing.length}</span>
                  <span className="pill compact" style={{ background: 'var(--peach)' }}>{bookings.filter((b) => b.data.tripUUID === t.id).length} bookings</span>
                </div>
                {t.data.budget > 0 ? (
                  <div className="col" style={{ gap: 4 }}>
                    <div className="row" style={{ fontSize: 11 }}><span className="secondary">Budget</span><span className="spacer" /><strong style={{ color: used > t.data.budget ? 'var(--critical)' : undefined }}>{money(used)} of {money(t.data.budget)}</strong></div>
                    <div className="pbar" style={{ height: 6, borderRadius: 999, background: 'var(--line)', overflow: 'hidden' }}>
                      <div style={{ height: '100%', width: `${Math.min(100, (used / t.data.budget) * 100)}%`, background: used > t.data.budget ? 'var(--critical)' : 'var(--ink)', borderRadius: 999 }} />
                    </div>
                  </div>
                ) : <div className="muted" style={{ fontSize: 11 }}>{used > 0 ? `${money(used)} spent so far` : 'No budget set'}</div>}
              </button>
            )
          })}
        </div>
      )}
      {unassigned.length > 0 && <FoundInEmail bookings={unassigned} trips={sorted} />}
      {current && <TripSheet trip={current} onClose={() => onOpen(null)} />}
    </div>
  )
}

function FoundInEmail({ bookings, trips }: { bookings: Rec<Booking>[]; trips: Rec<Trip>[] }) {
  const money = useMoney()
  return (
    <Card className="col" style={{ gap: 8, padding: 14 }}>
      <div className="row" style={{ gap: 8 }}><Mail size={14} /><strong style={{ fontSize: 13 }}>Found in your email</strong><span className="muted" style={{ fontSize: 12 }}>{bookings.length}</span></div>
      <div className="row" style={{ gap: 10, overflowX: 'auto', paddingBottom: 2 }}>
        {bookings.map((b) => (
          <div key={b.id} className="inner row" style={{ gap: 10, flex: 'none', padding: '8px 10px' }}>
            <span className="tile-icon" style={{ background: bookingKind(b.data.kind).color, color: 'var(--sticker-ink)' }}>{bookingIcon(b.data.kind, 13)}</span>
            <div className="col" style={{ gap: 0, minWidth: 0, maxWidth: 200 }}>
              <strong className="clamp1" style={{ fontSize: 12 }}>{b.data.title || bookingKind(b.data.kind).title}</strong>
              <span className="muted clamp1" style={{ fontSize: 11 }}>{[b.data.provider, parse(b.data.start) ? short(parse(b.data.start)!) : '', b.data.amount ? money(b.data.amount) : ''].filter(Boolean).join(' · ')}</span>
            </div>
            <select className="field" style={{ width: 130, padding: '6px 8px', fontSize: 12 }} value="" onChange={(e) => {
              const v = e.target.value
              if (v === '__new') {
                const s = parse(b.data.start)
                const id = store.create<Trip>('trip', { title: b.data.location || b.data.title, destination: b.data.location, start: b.data.start, end: b.data.end ?? (s ? iso(addDays(s, 3)) : null), bucketUUID: '', budget: 0, notes: '', packing: [], packed: [], createdAt: iso(new Date()) })
                store.update<Booking>(b.id, { tripUUID: id })
              } else if (v) store.update<Booking>(b.id, { tripUUID: v })
            }}>
              <option value="">Add to trip…</option>
              {trips.map((t) => <option key={t.id} value={t.id}>{t.data.title || 'New trip'}</option>)}
              <option value="__new">New trip</option>
            </select>
          </div>
        ))}
      </div>
    </Card>
  )
}

// MARK: Trip sheet

function TripSheet({ trip, onClose }: { trip: Rec<Trip>; onClose: () => void }) {
  const t = trip.data
  const set = (p: Partial<Trip>) => store.update<Trip>(trip.id, p)
  const bookings = useRecords<Booking>('booking').filter((b) => b.data.tripUUID === trip.id).sort((a, b) => (a.data.start ?? '9').localeCompare(b.data.start ?? '9'))
  const txns = useRecords<Txn>('transaction')
  const keys = useKeys()
  const money = useMoney()
  const [editing, setEditing] = useState<string | null>(null)
  const [item, setItem] = useState('')
  const [suggesting, setSuggesting] = useState(false)
  const [error, setError] = useState('')
  const packing = t.packing ?? [], packed = t.packed ?? []
  const used = budgetUsed(trip, store.list<Booking>('booking'), txns)

  const addItems = (items: string[]) => {
    const have = new Set(packing.map((p) => p.trim().toLowerCase()))
    const fresh: string[] = []
    for (const i of items) { const v = i.trim(); if (v && !have.has(v.toLowerCase())) { have.add(v.toLowerCase()); fresh.push(v) } }
    if (fresh.length) set({ packing: [...packing, ...fresh] })
  }
  const suggest = async () => {
    setSuggesting(true); setError('')
    const s = parse(t.start), e = parse(t.end)
    const nights = s && e ? Math.max(0, daysBetween(s, e)) : 0
    try {
      const r = await structured<{ items: string[] }>(
        'You write packing lists for a trip. Return 15-30 short, specific items (2-4 words each) suited to the destination, the season of the dates and the number of nights. No categories, no duplicates, no quantities unless useful.',
        `Destination: ${t.destination || t.title || 'unknown'}\nTrip: ${t.title}\nDates: ${s ? s.toDateString() : 'not set'}${e ? ` to ${e.toDateString()}` : ''}\nNights: ${nights || 'unknown'}\nAlready on the list: ${packing.join(', ') || 'nothing'}`,
        { type: 'object', properties: { items: { type: 'array', items: { type: 'string' } } }, required: ['items'], additionalProperties: false }, 'low')
      addItems(r.items)
    } catch (err) {
      setError((err as Error).message)
    }
    setSuggesting(false)
  }
  const addBooking = () => setEditing(store.create<Booking>('booking', {
    tripUUID: trip.id, kind: 'flight', title: '', provider: '', confirmation: '', location: t.destination, start: t.start, end: null, amount: 0, source: 'manual', sourceID: '', createdAt: iso(new Date()),
  }))
  const close = () => { if (!t.title.trim() && !t.destination.trim() && !bookings.length && !packing.length) store.remove(trip.id); onClose() }
  const editingRec = editing ? store.get<Booking>(editing) : undefined

  return (
    <Modal open onClose={close} width={760}>
      <div className="col" style={{ gap: 16 }}>
        <input className="plain display" style={{ fontSize: 26 }} autoFocus={!t.title} placeholder="Trip name" value={t.title} onChange={(e) => set({ title: e.target.value })} />
        <div className="row" style={{ gap: 18, alignItems: 'flex-start' }}>
          <div className="col" style={{ flex: 1, gap: 10 }}>
            <FormRow label="Destination"><input className="field" placeholder="City, country" value={t.destination} onChange={(e) => set({ destination: e.target.value })} /></FormRow>
            <FormRow label="From"><DateInput value={t.start} onChange={(v) => set({ start: v })} /></FormRow>
            <FormRow label="To"><DateInput value={t.end} onChange={(v) => set({ end: v })} /></FormRow>
            <FormRow label="Budget">
              <input type="number" className="field" style={{ width: 130 }} min={0} value={t.budget || ''} placeholder="None" onChange={(e) => set({ budget: Math.max(0, Number(e.target.value) || 0) })} />
              <span className="secondary" style={{ fontSize: 12 }}>{money(used)} used</span>
            </FormRow>
            <textarea className="field" rows={3} placeholder="Notes" value={t.notes} onChange={(e) => set({ notes: e.target.value })} />
          </div>
          <div className="col" style={{ width: 300, flex: 'none', gap: 8 }}>
            <div className="row"><strong style={{ fontSize: 13 }}>Packing</strong><span className="muted" style={{ fontSize: 12 }}>{packed.filter((p) => packing.includes(p)).length}/{packing.length}</span><span className="spacer" />
              {keys.anthropic && <button className="btn-soft" style={{ padding: '5px 10px' }} disabled={suggesting} onClick={suggest}><Sparkles size={12} />{suggesting ? 'Thinking…' : 'Suggest with AI'}</button>}</div>
            {error && <span style={{ fontSize: 11, color: 'var(--critical)' }}>{error}</span>}
            <div className="scroll col" style={{ gap: 2, maxHeight: 220 }}>
              {packing.length === 0 && <EmptyHint text="Nothing on the list yet." />}
              {packing.map((p) => (
                <div key={p} className="row hl-row" style={{ gap: 8, padding: '3px 6px', background: 'transparent' }}>
                  <input type="checkbox" checked={packed.includes(p)} onChange={(e) => set({ packed: e.target.checked ? [...packed.filter((x) => x !== p), p] : packed.filter((x) => x !== p) })} />
                  <span style={{ flex: 1, fontSize: 13, textDecoration: packed.includes(p) ? 'line-through' : 'none', opacity: packed.includes(p) ? 0.55 : 1 }}>{p}</span>
                  <span className="hl-actions"><button title="Remove" onClick={() => set({ packing: packing.filter((x) => x !== p), packed: packed.filter((x) => x !== p) })}><X size={12} /></button></span>
                </div>
              ))}
            </div>
            <div className="row">
              <input className="field" placeholder="Add an item" value={item} onChange={(e) => setItem(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') { addItems([item]); setItem('') } }} />
              <button className="btn-soft" disabled={!item.trim()} onClick={() => { addItems([item]); setItem('') }}>Add</button>
            </div>
          </div>
        </div>

        <div className="col" style={{ gap: 8 }}>
          <div className="row"><strong style={{ fontSize: 13 }}>Bookings</strong><span className="spacer" /><button className="btn-soft" onClick={addBooking}><Plus size={13} />Add booking</button></div>
          {bookings.length === 0 && <EmptyHint text="Flights, hotels, trains… Orbit on the Mac also finds them in your email." />}
          {bookings.map((b) => {
            const s = parse(b.data.start)
            return (
              <button key={b.id} className="list-row" style={{ background: 'var(--card)' }} onClick={() => setEditing(b.id)}>
                <span className="tile-icon" style={{ background: bookingKind(b.data.kind).color, color: 'var(--sticker-ink)', width: 32, height: 32 }}>{bookingIcon(b.data.kind)}</span>
                <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
                  <strong className="clamp1" style={{ fontSize: 13 }}>{b.data.title || bookingKind(b.data.kind).title}</strong>
                  <span className="muted clamp1" style={{ fontSize: 11 }}>{[b.data.provider, s ? `${short(s)} ${fmtTime(s)}` : '', b.data.confirmation ? `Ref ${b.data.confirmation}` : ''].filter(Boolean).join(' · ')}</span>
                </div>
                {b.data.source === 'email' && <span className="pill compact" style={{ background: 'var(--cyan)' }}><Mail size={10} />from email</span>}
                {b.data.amount > 0 && <strong style={{ fontSize: 13 }}>{money(b.data.amount)}</strong>}
              </button>
            )
          })}
        </div>

        <div className="row">
          <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => {
            for (const b of bookings) store.update<Booking>(b.id, { tripUUID: '' })
            store.remove(trip.id); onClose()
          }}><Trash2 size={13} />Delete trip</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 110 }} onClick={close}>Done</button>
        </div>
      </div>
      {editingRec && <BookingEditor rec={editingRec} onClose={() => setEditing(null)} />}
    </Modal>
  )
}

const toLocalInput = (v: string | null): string => {
  const d = parse(v)
  if (!d) return ''
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
}
const fromLocalInput = (v: string): string | null => (v ? iso(new Date(v)) : null)

function BookingEditor({ rec, onClose }: { rec: Rec<Booking>; onClose: () => void }) {
  const b = rec.data
  const set = (p: Partial<Booking>) => store.update<Booking>(rec.id, p)
  const close = () => { if (!b.title.trim() && !b.provider.trim() && !b.amount && !b.confirmation) store.remove(rec.id); onClose() }
  return (
    <Modal open onClose={close} width={500}>
      <div className="col" style={{ gap: 12 }}>
        <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          {BOOKING_KINDS.map((k) => (
            <span key={k.id} className="pill compact" onClick={() => set({ kind: k.id })}
              style={{ background: k.color, cursor: 'pointer', opacity: b.kind === k.id ? 1 : 0.4, outline: b.kind === k.id ? '1.5px solid var(--ink)' : 'none' }}>{bookingIcon(k.id, 11)}{k.title}</span>
          ))}
          {b.source === 'email' && <span className="pill compact" style={{ background: 'var(--card)', color: 'var(--ink)' }}><Mail size={10} />from email</span>}
        </div>
        <input className="plain display" style={{ fontSize: 22 }} autoFocus={!b.title} placeholder="e.g. Cairo → Oslo" value={b.title} onChange={(e) => set({ title: e.target.value })} />
        <FormRow label="Provider"><input className="field" placeholder="Airline, hotel…" value={b.provider} onChange={(e) => set({ provider: e.target.value })} /></FormRow>
        <FormRow label="Confirmation"><input className="field" value={b.confirmation} onChange={(e) => set({ confirmation: e.target.value })} /></FormRow>
        <FormRow label="Where"><input className="field" value={b.location} onChange={(e) => set({ location: e.target.value })} /></FormRow>
        <FormRow label="Starts"><input type="datetime-local" className="field" style={{ width: 220 }} value={toLocalInput(b.start)} onChange={(e) => set({ start: fromLocalInput(e.target.value) })} /></FormRow>
        <FormRow label="Ends"><input type="datetime-local" className="field" style={{ width: 220 }} value={toLocalInput(b.end)} onChange={(e) => set({ end: fromLocalInput(e.target.value) })} /></FormRow>
        <FormRow label="Cost"><input type="number" className="field" style={{ width: 140 }} min={0} step="0.01" value={b.amount || ''} onChange={(e) => set({ amount: Math.abs(Number(e.target.value) || 0) })} /></FormRow>
        <div className="row">
          <button className="btn-soft" style={{ color: 'var(--critical)' }} onClick={() => { store.remove(rec.id); onClose() }}><Trash2 size={13} />Delete</button>
          <span className="spacer" />
          <button className="btn-primary" style={{ width: 110 }} onClick={close}>Done</button>
        </div>
      </div>
    </Modal>
  )
}
