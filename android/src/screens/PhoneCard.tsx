// My Card on Android: the iPhone's PhoneCardSheet + ProfileCardSheet (ProfileCardView.swift, ProfileCard.swift).
// The card fills the width with Share / Copy image / Copy links under it, then the editor: about you, contact,
// links, the public web page and the look (photo or colour card, card photo, colour, what the QR code opens).
import { useEffect, useMemo, useRef, useState, ReactNode } from 'react'
import { Share2, Copy, Link as LinkIcon, Plus, MinusCircle, X, ImagePlus } from 'lucide-react'
import { Modal } from '@/components/ui'
import { store, useSetting, SettingKey } from '@/lib/store'
import * as cloud from '@/lib/cloud'
import {
  LINK_KINDS, LinkKind, CARD_COLORS, LINK_PLACEHOLDER, linkTitle, filledLinks, newLinkID, vCard, shareText, linkURL, linkDisplay,
  useProfileCard, useProfilePhoto, chooseProfilePhoto, resizeSquare, SLUG_RE, publicURL, suggestSlug, unpublishPublicCard,
} from '@/lib/profileCard'
import { drawPhoneCard, phoneCardPNG, PhoneCardData, linkHandle } from '../components/cardFace'
import { SheetNav, Switch } from '../components/psKit'

// MARK: Storage

/** The synced "profileCard" JSON, keeping fields the shared decoder drops (the Mac's `style`). */
function useCard(): [PhoneCardData, (c: PhoneCardData) => void] {
  const raw = useSetting<unknown>('profileCard', null)
  const base = useProfileCard()
  const json = useMemo(() => {
    if (typeof raw === 'string') { try { return JSON.parse(raw) ?? {} } catch { return {} } }
    return raw && typeof raw === 'object' ? raw as Record<string, unknown> : {}
  }, [raw])
  const card: PhoneCardData = { ...base, style: json.style === 'color' ? 'color' : 'photo' }
  const save = (c: PhoneCardData) => store.setSetting('profileCard', JSON.stringify({ ...json, ...c }))
  return [card, save]
}

// The card's own background photo (the Mac's CardPhoto, UserDefaults "cardPhoto": a base64 JPEG). It syncs once
// "cardPhoto" is in SYNCED_SETTINGS; until then this phone keeps its own copy.
const COVER_KEY = 'cardPhoto' as SettingKey
const COVER_LOCAL = 'orbit.cardPhoto'
const coverSubs = new Set<() => void>()
function useCover(): string | null {
  const synced = useSetting<string>(COVER_KEY, '')
  const [, tick] = useState(0)
  useEffect(() => { const f = () => tick((n) => n + 1); coverSubs.add(f); return () => { coverSubs.delete(f) } }, [])
  let b64 = synced
  if (!b64) { try { b64 = localStorage.getItem(COVER_LOCAL) ?? '' } catch { b64 = '' } }
  return b64 ? `data:image/jpeg;base64,${b64}` : null
}
function setCover(b64: string): void {
  try { if (b64) localStorage.setItem(COVER_LOCAL, b64); else localStorage.removeItem(COVER_LOCAL) } catch { /* too big for this phone's storage */ }
  store.setSetting(COVER_KEY, b64 || null)
  coverSubs.forEach((f) => f())
}

/** Your profile photo on this phone, or the one synced from your Mac or iPhone ("profile.photo"). */
function usePhoto(): string | null {
  const local = useProfilePhoto()
  const synced = useSetting<string>('profile.photo' as SettingKey, '')
  return local ?? (synced ? `data:image/jpeg;base64,${synced}` : null)
}

/** A JPEG no larger than `max` on its long side, as base64 or a data URL. */
function jpeg(src: string, max: number, quality: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => {
      const s = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight))
      const c = document.createElement('canvas')
      c.width = Math.round(img.naturalWidth * s); c.height = Math.round(img.naturalHeight * s)
      c.getContext('2d')!.drawImage(img, 0, 0, c.width, c.height)
      resolve(c.toDataURL('image/jpeg', quality))
    }
    img.onerror = reject
    img.src = src
  })
}

function pickImage(): Promise<string | null> {
  return new Promise((resolve) => {
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = 'image/*'
    input.onchange = () => { const f = input.files?.[0]; resolve(f ? URL.createObjectURL(f) : null) }
    input.click()
  })
}

// MARK: Public page (public_cards, as CloudSync.publishCard with ProfileCard.publicData)

async function publicData(c: PhoneCardData, photo: string | null, cover: string | null): Promise<Record<string, unknown>> {
  let small = '', big = ''
  if (c.showPhoto && photo) { try { small = await resizeSquare(photo, 200, 'image/jpeg', 0.7) } catch { /* none */ } }
  if (c.style === 'photo' && c.showPhoto && (cover ?? photo)) { try { big = await jpeg((cover ?? photo)!, 900, 0.72) } catch { /* none */ } }
  return {
    name: c.name, headline: c.headline, company: c.company, location: c.location, bio: c.bio, colorIndex: c.colorIndex, style: c.style, cover: big,
    links: filledLinks(c).map((l) => ({ kind: l.kind, url: linkURL(l), display: linkDisplay(l), title: linkTitle(l.kind), handle: linkHandle(l) })),
    email: c.publicShowContact ? c.email : '', phone: c.publicShowContact ? c.phone : '', photo: small,
  }
}

async function publish(c: PhoneCardData, photo: string | null, cover: string | null): Promise<void> {
  const s = cloud.getSession()
  if (!s) throw new cloud.CloudError('Sign in to publish your card.')
  const body = { slug: c.publicSlug, data: await publicData(c, photo, cover) }
  const upsert = () => cloud.rest('public_cards?on_conflict=slug', { method: 'POST', prefer: 'resolution=merge-duplicates,return=minimal', body })
  const taken = (m: string) => /\b403\b|row-level security/i.test(m)
  try {
    await upsert()
  } catch (e) {
    const m = (e as Error).message
    if (taken(m)) throw new cloud.CloudError('That name is taken. Try another one.')
    if (!/\b409\b|duplicate|unique/i.test(m)) throw e
    // One card per person: you already have one under another name, so move it to the new one.
    await cloud.rest(`public_cards?user_id=eq.${s.userID}&slug=neq.${encodeURIComponent(c.publicSlug)}`, { method: 'DELETE', prefer: 'return=minimal' })
    try { await upsert() } catch (e2) { if (taken((e2 as Error).message)) throw new cloud.CloudError('That name is taken. Try another one.'); throw e2 }
  }
}

// MARK: Sheet

export default function PhoneCard({ open, onClose }: { open: boolean; onClose: () => void }) {
  if (!open) return null
  return (
    <Modal open onClose={onClose} width={560}>
      <div className="ps-root">
        <SheetNav title="My Card" onDone={onClose}
          leading={<button className="ps-pillbtn icon" aria-label="Choose your photo" onClick={chooseProfilePhoto}><ImagePlus size={20} /></button>} />
        <div className="ps-body"><CardSheet onClose={onClose} /></div>
      </div>
    </Modal>
  )
}

function CardSheet({ onClose }: { onClose: () => void }) {
  const [card, save] = useCard()
  const photo = usePhoto()
  const cover = useCover()
  const set = (patch: Partial<PhoneCardData>) => save({ ...card, ...patch })
  const canvas = useRef<HTMLCanvasElement>(null)
  const [back, setBack] = useState(false)
  const [turning, setTurning] = useState(false)
  const [copied, setCopied] = useState('')
  const json = JSON.stringify(card)
  const isPhotoCard = card.style === 'photo' && card.showPhoto && !!(cover ?? photo)

  useEffect(() => {
    let live = true
    const c = document.createElement('canvas')
    drawPhoneCard(c, card, { photo, cover, back: back && isPhotoCard, interactive: true, scale: 3 }).then(() => {
      const el = canvas.current
      if (!live || !el) return
      el.width = c.width; el.height = c.height
      el.getContext('2d')!.drawImage(c, 0, 0)
    })
    return () => { live = false }
  }, [json, photo, cover, back, isPhotoCard])

  const flip = () => {
    if (!isPhotoCard) return
    setTurning(true)
    setTimeout(() => { setBack((b) => !b); setTurning(false) }, 160)
  }
  const flash = (s: string) => { setCopied(s); setTimeout(() => setCopied((c) => (c === s ? '' : c)), 3500) }
  const stem = (card.name || 'My card').replace(/[\\/:*?"<>|]/g, '-')

  const share = async () => {
    const link = card.publishPublic && SLUG_RE.test(card.publicSlug) ? publicURL(card.publicSlug) : undefined
    try {
      const png = new File([await phoneCardPNG(card, photo, cover)], `${stem}.png`, { type: 'image/png' })
      const vcf = new File([vCard(card)], `${stem}.vcf`, { type: 'text/vcard' })
      if (navigator.canShare?.({ files: [png, vcf] })) { await navigator.share({ files: [png, vcf], title: card.name }); return }
      if (navigator.canShare?.({ files: [png] })) { await navigator.share({ files: [png], title: card.name, text: link }); return }
      if (navigator.share) { await navigator.share({ title: card.name, text: shareText(card), url: link }); return }
    } catch (e) { if ((e as Error).name === 'AbortError') return }
    await navigator.clipboard.writeText(shareText(card) + (link ? `\n${link}` : '')).catch(() => {})
    flash('Sharing isn\'t available here, so your links were copied instead.')
  }
  const copyImage = async () => {
    try { await navigator.clipboard.write([new ClipboardItem({ 'image/png': phoneCardPNG(card, photo, cover) })]); flash('Card image copied. Paste it into a chat or email.') }
    catch { flash("Couldn't copy the image here. Use Share card… instead.") }
  }
  const copyLinks = () => navigator.clipboard.writeText(shareText(card)).then(() => flash('Links copied.')).catch(() => flash("Couldn't copy."))

  return (
    <>
      <div className="ps-card-wrap" onClick={back ? flip : undefined}>
        <div className={`ps-card-turn${turning ? ' out' : ''}`}><canvas ref={canvas} /></div>
        {isPhotoCard && !back && <button className="ps-card-flip" aria-label="Show my QR code" onClick={(e) => { e.stopPropagation(); flip() }} />}
      </div>
      <div className="ps-card-actions">
        <button className="ps-primary ps-wide" onClick={share}><Share2 size={17} /> Share card…</button>
        <div className="ps-btnrow">
          <button className="ps-soft ps-wide" onClick={copyImage}><Copy size={16} /> Copy image</button>
          <button className="ps-soft ps-wide" onClick={copyLinks}><LinkIcon size={16} /> Copy links</button>
        </div>
        {copied && <div className="ps-copied">{copied}</div>}
      </div>
      <Editor card={card} set={set} photo={photo} cover={cover} onClose={onClose} />
    </>
  )
}

// MARK: Editor

function Editor({ card, set, photo, cover, onClose }: { card: PhoneCardData; set: (p: Partial<PhoneCardData>) => void; photo: string | null; cover: string | null; onClose: () => void }) {
  const hasOwnCover = !!cover
  const chooseCover = async () => {
    const url = await pickImage()
    if (!url) return
    const data = await jpeg(url, 1400, 0.8)
    setCover(data.replace(/^data:image\/jpeg;base64,/, ''))
  }
  const qrOptions = [{ id: 'contact', label: 'My contact card' }, ...(card.publishPublic && SLUG_RE.test(card.publicSlug) ? [{ id: 'web', label: 'My web page' }] : []),
    ...filledLinks(card).map((l) => ({ id: l.id, label: linkTitle(l.kind) }))]

  return (
    <div className="ps-card-editor">
      <div className="row">
        <h2>My card</h2>
        <span className="spacer" />
        <button className="ps-x" aria-label="Close" onClick={onClose}><X size={20} strokeWidth={2.6} color="var(--ink)" /></button>
      </div>
      <span className="secondary" style={{ fontSize: 13, marginTop: -8 }}>Add your links once, then share your card as an image or a contact anyone can save.</span>

      <EG title="About you">
        <Field value={card.name} placeholder="Your name" onChange={(v) => set({ name: v })} />
        <Field value={card.headline} placeholder="Product designer, Founder…" onChange={(v) => set({ headline: v })} />
        <Field value={card.company} placeholder="Where you work (optional)" onChange={(v) => set({ company: v })} />
        <Field value={card.location} placeholder="Cairo, Egypt" onChange={(v) => set({ location: v })} />
        <textarea className="ps-field" rows={2} placeholder="A line about you (optional)" value={card.bio} onChange={(e) => set({ bio: e.target.value })} />
        <div className="ps-check"><span>Show my profile photo</span><Switch on={card.showPhoto} onChange={(v) => set({ showPhoto: v })} /></div>
        {!photo && <button className="ps-blue" style={{ alignSelf: 'flex-start' }} onClick={chooseProfilePhoto}>Add a profile photo</button>}
      </EG>

      <EG title="Contact">
        <Field value={card.email} placeholder="you@example.com" type="email" onChange={(v) => set({ email: v })} />
        <Field value={card.phone} placeholder="+20 …" type="tel" onChange={(v) => set({ phone: v })} />
      </EG>

      <EG title="Links">
        {card.links.map((l, i) => (
          <div key={l.id} className="ps-linkrow">
            <div className="row" style={{ gap: 8 }}>
              <select className="ps-select" style={{ textAlign: 'left', color: 'var(--ink)', fontWeight: 600, maxWidth: '70%', paddingLeft: 0 }} value={l.kind}
                onChange={(e) => set({ links: card.links.map((x, j) => (j === i ? { ...x, kind: e.target.value as LinkKind } : x)) })}>
                {LINK_KINDS.map((k) => <option key={k} value={k}>{linkTitle(k)}</option>)}
              </select>
              <span className="spacer" />
              <button className="ps-x" aria-label="Remove link"
                onClick={() => set({ links: card.links.filter((x) => x.id !== l.id), qrTarget: card.qrTarget === l.id ? 'contact' : card.qrTarget })}><MinusCircle size={18} /></button>
            </div>
            <input className="ps-field" placeholder={LINK_PLACEHOLDER[l.kind]} value={l.value} autoCapitalize="none" autoCorrect="off" inputMode="url"
              onChange={(e) => set({ links: card.links.map((x, j) => (j === i ? { ...x, value: e.target.value.replace(/\n/g, '') } : x)) })} />
          </div>
        ))}
        <AddLink onAdd={(k) => set({ links: [...card.links, { id: newLinkID(), kind: k, value: '' }] })} />
      </EG>

      <PublicLink card={card} set={set} photo={photo} cover={cover} />

      <EG title="Look">
        <div className="ps-seg">
          <button className={card.style === 'photo' ? 'on' : ''} onClick={() => set({ style: 'photo' })}>Photo</button>
          <button className={card.style === 'color' ? 'on' : ''} onClick={() => set({ style: 'color' })}>Colour</button>
        </div>
        {card.style === 'photo' && <>
          <div className="row" style={{ gap: 10 }}>
            <button className="ps-soft" onClick={chooseCover}>{hasOwnCover ? 'Change card photo' : 'Choose a card photo'}</button>
            {hasOwnCover && <button className="ps-blue" style={{ fontSize: 13 }} onClick={() => setCover('')}>Use my profile photo</button>}
          </div>
          <span className="muted" style={{ fontSize: 12 }}>
            {!cover && !photo ? 'Choose a photo to fill the card. A portrait photo with your face in the top half works best.'
              : 'A portrait photo with your face in the top half works best. The colour below is used for your links.'}
          </span>
        </>}
        <div className="row" style={{ gap: 10, flexWrap: 'wrap' }}>
          {CARD_COLORS.map((c, i) => (
            <button key={c} aria-label="Card colour" className={`ps-swatch${card.colorIndex === i ? ' on' : ''}`} style={{ background: c }} onClick={() => set({ colorIndex: i })} />
          ))}
        </div>
        <label className="ps-check">
          <span>QR code opens</span>
          <select className="ps-select" value={qrOptions.some((o) => o.id === card.qrTarget) ? card.qrTarget : 'contact'} onChange={(e) => set({ qrTarget: e.target.value })}>
            {qrOptions.map((o) => <option key={o.id} value={o.id}>{o.label}</option>)}
          </select>
        </label>
      </EG>
    </div>
  )
}

function EG({ title, children }: { title: string; children: ReactNode }) {
  return <div className="ps-eg"><span className="ps-eg-title">{title}</span>{children}</div>
}

function Field({ value, placeholder, onChange, type = 'text' }: { value: string; placeholder: string; onChange: (v: string) => void; type?: string }) {
  return <input className="ps-field" type={type} value={value} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} />
}

function AddLink({ onAdd }: { onAdd: (k: LinkKind) => void }) {
  const [open, setOpen] = useState(false)
  return (
    <div style={{ position: 'relative', alignSelf: 'flex-start' }}>
      <button className="ps-soft" onClick={() => setOpen((o) => !o)}><Plus size={15} /> Add link</button>
      {open && <>
        <div style={{ position: 'fixed', inset: 0, zIndex: 4 }} onClick={() => setOpen(false)} />
        <div className="ps-menu">
          {LINK_KINDS.map((k) => <button key={k} onClick={() => { onAdd(k); setOpen(false) }}>{linkTitle(k)}</button>)}
        </div>
      </>}
    </div>
  )
}

/** Public link: a web page anyone can open, kept up to date while publishing is on. */
function PublicLink({ card, set, photo, cover }: { card: PhoneCardData; set: (p: Partial<PhoneCardData>) => void; photo: string | null; cover: string | null }) {
  const signedIn = !!cloud.getSession()
  const [status, setStatus] = useState('')
  const valid = SLUG_RE.test(card.publicSlug)
  const key = JSON.stringify(card) + (photo ?? '').length + (cover ?? '').length
  const wasOn = useRef(card.publishPublic)

  useEffect(() => {
    if (!signedIn) return
    if (wasOn.current && !card.publishPublic) {
      unpublishPublicCard().then(() => setStatus('Your card is no longer on the web.')).catch((e) => setStatus((e as Error).message))
    }
    wasOn.current = card.publishPublic
    if (!card.publishPublic || !valid) return
    const t = setTimeout(() => {
      setStatus('Publishing…')
      publish(card, photo, cover).then(() => setStatus('Live: anyone with the link sees your latest card.')).catch((e) => setStatus((e as Error).message))
    }, 1500)
    return () => clearTimeout(t)
  }, [key, signedIn])

  const toggle = (on: boolean) => set({ publishPublic: on, ...(on && !card.publicSlug ? { publicSlug: suggestSlug(card.name) } : {}) })
  const url = card.publishPublic && valid ? publicURL(card.publicSlug) : null

  return (
    <EG title="Public link">
      {!signedIn ? <span className="secondary" style={{ fontSize: 13 }}>Sign in under Settings › Account & sync to get a web link for your card.</span> : <>
        <div className="ps-check"><span>Publish my card on the web</span><Switch on={card.publishPublic} onChange={toggle} /></div>
        {card.publishPublic && <>
          <div className="row" style={{ gap: 6 }}>
            <span className="muted" style={{ fontSize: 13, whiteSpace: 'nowrap' }}>…/card/?u=</span>
            <input className="ps-field" value={card.publicSlug} placeholder="your-name" autoCapitalize="none" autoCorrect="off"
              onChange={(e) => set({ publicSlug: e.target.value.toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/-+/g, '-').replace(/^-/, '').slice(0, 40) })} />
          </div>
          <div className="ps-check"><span>Show my email and phone on the page</span><Switch on={card.publicShowContact} onChange={(v) => set({ publicShowContact: v })} /></div>
          {url ? (
            <div className="row" style={{ gap: 8 }}>
              <button className="ps-blue clamp1" style={{ flex: 1, minWidth: 0, textAlign: 'left', fontSize: 12 }} onClick={() => window.orbit.openExternal(url)}>{url.replace('https://', '')}</button>
              <button className="ps-soft" onClick={() => navigator.clipboard.writeText(url).then(() => setStatus('Link copied.'))}>Copy link</button>
            </div>
          ) : <span className="muted" style={{ fontSize: 12 }}>Use 3–40 lowercase letters, numbers or dashes.</span>}
          {status && <span className="secondary" style={{ fontSize: 12 }}>{status}</span>}
        </>}
      </>}
    </EG>
  )
}

