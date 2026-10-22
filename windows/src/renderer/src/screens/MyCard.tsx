// "My Card": edit on the left, live preview on the right, share as an image, a contact file or a public link.
// Mirrors ProfileCardSheet in ProfileCardView.swift (Mac).
import { ReactNode, useEffect, useRef, useState } from 'react'
import { Plus, MinusCircle, Copy, Image as ImageIcon, Contact, Link as LinkIcon, X, Check, Globe } from 'lucide-react'
import * as cloud from '@/lib/cloud'
import {
  ProfileCard, LINK_KINDS, LinkKind, CARD_COLORS, LINK_PLACEHOLDER, linkTitle, filledLinks, newLinkID, vCard, shareText,
  useProfileCard, saveProfileCard, useProfilePhoto, chooseProfilePhoto, SLUG_RE, publicURL, suggestSlug, publishPublicCard, unpublishPublicCard,
} from '@/lib/profileCard'
import { drawCard, cardPNG, CARD_W, CARD_H } from '@/components/cardRender'

export default function MyCard({ open, onClose }: { open: boolean; onClose: () => void }) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])
  if (!open) return null
  return (
    <div className="backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div className="modal" style={{ width: 920, height: 'min(740px, 92vh)', padding: 0, display: 'flex', overflow: 'hidden' }}>
        <Sheet onClose={onClose} />
      </div>
    </div>
  )
}

function Sheet({ onClose }: { onClose: () => void }) {
  const card = useProfileCard()
  const photo = useProfilePhoto()
  const set = (patch: Partial<ProfileCard>) => saveProfileCard({ ...card, ...patch })
  const canvas = useRef<HTMLCanvasElement>(null)
  const [copied, setCopied] = useState('')
  const json = JSON.stringify(card)

  // Redraw the preview whenever the card or photo changes.
  useEffect(() => {
    let live = true
    const c = document.createElement('canvas')
    drawCard(c, card, photo, 2).then(() => {
      const el = canvas.current
      if (!live || !el) return
      el.width = c.width; el.height = c.height
      el.getContext('2d')!.drawImage(c, 0, 0)
    })
    return () => { live = false }
  }, [json, photo])

  const stem = (card.name || 'My card').replace(/[\\/:*?"<>|]/g, '-')
  const download = (blob: Blob, name: string) => {
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = name
    a.click()
    setTimeout(() => URL.revokeObjectURL(a.href), 10_000)
  }
  const flash = (s: string) => { setCopied(s); setTimeout(() => setCopied((c) => (c === s ? '' : c)), 3000) }

  return (
    <>
      <div className="scroll" style={{ width: 420, flex: 'none', padding: 24, fontSize: 13 }}>
        <div className="col" style={{ gap: 16 }}>
          <div className="row">
            <h2 className="page-title" style={{ fontSize: 28 }}>My card</h2>
            <span className="spacer" />
            <button className="icon-btn" style={{ width: 30, height: 30 }} onClick={onClose} title="Close"><X size={15} /></button>
          </div>
          <div className="secondary" style={{ fontSize: 12 }}>Add your links once, then share your card as an image or a contact anyone can save.</div>

          <Group title="About you">
            <TextField value={card.name} placeholder="Your name" onChange={(v) => set({ name: v })} />
            <TextField value={card.headline} placeholder="Product designer, Founder…" onChange={(v) => set({ headline: v })} />
            <TextField value={card.company} placeholder="Where you work (optional)" onChange={(v) => set({ company: v })} />
            <TextField value={card.location} placeholder="Cairo, Egypt" onChange={(v) => set({ location: v })} />
            <textarea className="field" rows={2} placeholder="A line about you (optional)" value={card.bio} onChange={(e) => set({ bio: e.target.value })} />
            <label className="row" style={{ gap: 8 }}>
              <input type="checkbox" checked={card.showPhoto} onChange={(e) => set({ showPhoto: e.target.checked })} />Show my profile photo
            </label>
            {!photo && <button className="link" style={{ alignSelf: 'flex-start' }} onClick={chooseProfilePhoto}>Add a profile photo…</button>}
          </Group>

          <Group title="Contact">
            <TextField value={card.email} placeholder="you@example.com" onChange={(v) => set({ email: v })} />
            <TextField value={card.phone} placeholder="+20 …" onChange={(v) => set({ phone: v })} />
          </Group>

          <Group title="Links">
            {card.links.map((l, i) => (
              <div key={l.id} className="row" style={{ gap: 8 }}>
                <select className="field" style={{ width: 130, flex: 'none' }} value={l.kind}
                  onChange={(e) => set({ links: card.links.map((x, j) => (j === i ? { ...x, kind: e.target.value as LinkKind } : x)) })}>
                  {LINK_KINDS.map((k) => <option key={k} value={k}>{linkTitle(k)}</option>)}
                </select>
                <input className="field" placeholder={LINK_PLACEHOLDER[l.kind]} value={l.value}
                  onChange={(e) => set({ links: card.links.map((x, j) => (j === i ? { ...x, value: e.target.value } : x)) })} />
                <button title="Remove" className="muted" onClick={() => set({ links: card.links.filter((x) => x.id !== l.id), qrTarget: card.qrTarget === l.id ? 'contact' : card.qrTarget })}>
                  <MinusCircle size={16} />
                </button>
              </div>
            ))}
            <AddLink onAdd={(k) => set({ links: [...card.links, { id: newLinkID(), kind: k, value: '' }] })} />
          </Group>

          <Group title="Look">
            <div className="row" style={{ gap: 8 }}>
              {CARD_COLORS.map((c, i) => (
                <button key={c} title="Card colour" onClick={() => set({ colorIndex: i })}
                  style={{ width: 28, height: 28, borderRadius: '50%', background: c, outline: card.colorIndex === i ? '2px solid var(--ink)' : 'none', outlineOffset: 1 }} />
              ))}
            </div>
            <label className="row" style={{ gap: 8 }}>
              <span>QR code opens</span>
              <select className="field" style={{ width: 200 }} value={card.qrTarget} onChange={(e) => set({ qrTarget: e.target.value })}>
                <option value="contact">My contact card</option>
                {filledLinks(card).map((l) => <option key={l.id} value={l.id}>{linkTitle(l.kind)}</option>)}
              </select>
            </label>
          </Group>

          <PublicLink card={card} photo={photo} set={set} />
        </div>
      </div>
      <div style={{ width: 1, background: 'var(--line)' }} />
      <div className="col" style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 18, padding: 24, background: 'var(--card)' }}>
        <canvas ref={canvas} style={{ width: CARD_W * 0.9, height: CARD_H * 0.9, borderRadius: 29, boxShadow: '0 10px 36px rgba(0,0,0,0.15)' }} />
        <div className="col" style={{ gap: 10, alignItems: 'center' }}>
          <div className="row" style={{ gap: 10 }}>
            <button className="btn-primary" onClick={async () => {
              try { await navigator.clipboard.write([new ClipboardItem({ 'image/png': await cardPNG(card, photo) })]); flash('Card image copied. Paste it into a chat or email.') }
              catch { flash("Couldn't copy the image. Try Save image instead.") }
            }}><Copy size={14} />Copy image</button>
            <button className="btn-soft" style={{ background: 'var(--canvas)' }} onClick={() => navigator.clipboard.writeText(shareText(card)).then(() => flash('Links copied.'))}><LinkIcon size={14} />Copy links</button>
          </div>
          <div className="row" style={{ gap: 10 }}>
            <button className="btn-soft" style={{ background: 'var(--canvas)' }} onClick={async () => download(await cardPNG(card, photo), `${stem}.png`)}><ImageIcon size={14} />Save image…</button>
            <button className="btn-soft" style={{ background: 'var(--canvas)' }} onClick={() => download(new Blob([vCard(card)], { type: 'text/vcard' }), `${stem}.vcf`)}><Contact size={14} />Save contact…</button>
          </div>
          <div style={{ fontSize: 11, fontWeight: 500, color: 'var(--good)', minHeight: 16 }}>{copied}</div>
        </div>
      </div>
    </>
  )
}

function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="col" style={{ gap: 8 }}>
      <div className="muted" style={{ fontSize: 12, fontWeight: 600 }}>{title}</div>
      {children}
    </div>
  )
}

function TextField({ value, placeholder, onChange }: { value: string; placeholder: string; onChange: (v: string) => void }) {
  return <input className="field" value={value} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} />
}

function AddLink({ onAdd }: { onAdd: (k: LinkKind) => void }) {
  const [open, setOpen] = useState(false)
  return (
    <div style={{ position: 'relative', alignSelf: 'flex-start' }}>
      <button className="btn-soft" onClick={() => setOpen((o) => !o)}><Plus size={14} />Add link</button>
      {open && (
        <div className="pop-menu" style={{ left: 0, right: 'auto', top: 40, maxHeight: 260, overflowY: 'auto' }} onMouseLeave={() => setOpen(false)}>
          {LINK_KINDS.map((k) => <button key={k} onClick={() => { onAdd(k); setOpen(false) }}>{linkTitle(k)}</button>)}
        </div>
      )}
    </div>
  )
}

/** Public web page for the card (public_cards in Supabase), kept up to date while it's on. */
function PublicLink({ card, photo, set }: { card: ProfileCard; photo: string | null; set: (p: Partial<ProfileCard>) => void }) {
  const signedIn = !!cloud.getSession()
  const [slug, setSlug] = useState(card.publicSlug || suggestSlug(card.name))
  const [status, setStatus] = useState('')
  const [copied, setCopied] = useState(false)
  const validSlug = SLUG_RE.test(card.publicSlug)
  const key = JSON.stringify(card) + (photo ?? '').length

  // Publish a couple of seconds after the last change while it's on.
  useEffect(() => {
    if (!card.publishPublic || !signedIn || !validSlug) return
    setStatus('Publishing…')
    const t = setTimeout(() => {
      publishPublicCard(card, photo).then(() => setStatus('Live')).catch((e) => setStatus((e as Error).message))
    }, 1500)
    return () => clearTimeout(t)
  }, [key, signedIn])

  const turnOn = () => {
    const s = slug.trim().toLowerCase()
    if (!SLUG_RE.test(s)) { setStatus('Use 3–40 lowercase letters, numbers or dashes (not at the start or end).'); return }
    set({ publishPublic: true, publicSlug: s })
  }
  const turnOff = () => {
    set({ publishPublic: false })
    setStatus('')
    unpublishPublicCard().catch((e) => setStatus((e as Error).message))
  }

  return (
    <Group title="Public link">
      {!signedIn ? <div className="muted" style={{ fontSize: 12 }}>Sign in to your Orbit account to get a link to your card.</div> : card.publishPublic ? (
        <>
          <div className="row" style={{ gap: 8 }}>
            <Globe size={14} />
            <span className="clamp1" style={{ flex: 1, minWidth: 0, fontSize: 12, userSelect: 'text' }}>{publicURL(card.publicSlug)}</span>
            <button className="btn-soft" onClick={() => navigator.clipboard.writeText(publicURL(card.publicSlug)).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1500) })}>
              {copied ? <Check size={13} /> : <Copy size={13} />}{copied ? 'Copied' : 'Copy'}
            </button>
          </div>
          <label className="row" style={{ gap: 8 }}>
            <input type="checkbox" checked={card.publicShowContact} onChange={(e) => set({ publicShowContact: e.target.checked })} />Show my email and phone on the page
          </label>
          <div className="row">
            <span className="muted" style={{ fontSize: 11, flex: 1 }}>{status}</span>
            <button className="btn-soft" onClick={turnOff}>Turn off</button>
          </div>
        </>
      ) : (
        <>
          <div className="secondary" style={{ fontSize: 12 }}>A web page anyone can open, with your links and a button to save your contact. Email and phone stay off it unless you choose.</div>
          <div className="row" style={{ gap: 8 }}>
            <span className="muted" style={{ fontSize: 12, whiteSpace: 'nowrap' }}>…/card/?u=</span>
            <input className="field" value={slug} placeholder="your-name" onChange={(e) => setSlug(e.target.value.toLowerCase())} onKeyDown={(e) => e.key === 'Enter' && turnOn()} />
            <button className="btn-primary" onClick={turnOn}>Publish</button>
          </div>
          {status && <span style={{ fontSize: 11, color: 'var(--critical)' }}>{status}</span>}
        </>
      )}
    </Group>
  )
}
