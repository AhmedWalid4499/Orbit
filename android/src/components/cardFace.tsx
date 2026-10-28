// "My Card" drawn on a canvas, laid out like CardFace in ProfileCardView.swift (420 × 620 points): the photo card
// (your photo fading into a dark panel, links as pills, the QR code on the back) and the colour card (links as
// rows, the QR code in the corner). The same drawing is the preview and the image you share.
import { ComponentType } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import {
  Linkedin, Globe, Github, Instagram, Twitter, Youtube, Music, Facebook, Palette, Dribbble, Calendar, MessageCircle, Link,
  Mail, Phone, MapPin, BadgeCheck, QrCode, Undo2, ArrowUpRight, LucideProps,
} from 'lucide-react'
import { ProfileCard, CardLink, LinkKind, CARD_COLORS, cardColor, cardIsDark, filledLinks, linkURL, linkDisplay, linkTitle, vCard, qrMatrix, SLUG_RE, publicURL } from '@/lib/profileCard'

export const CARD_W = 420, CARD_H = 620

/** The card as the Mac and iPhone store it, with the field the shared decoder doesn't know yet. */
export type PhoneCardData = ProfileCard & { style: 'photo' | 'color' }

const SERIF = "Fraunces, Georgia, 'Times New Roman', serif"
const SANS = "Inter, system-ui, -apple-system, 'Segoe UI', sans-serif"
const ROUNDED = "'Nunito', 'SF Pro Rounded', ui-rounded, Inter, system-ui, sans-serif"

const BRAND: Record<LinkKind, { icon: ComponentType<LucideProps>; color: string | null }> = {
  linkedin: { icon: Linkedin, color: '#0A66C2' }, website: { icon: Globe, color: null }, github: { icon: Github, color: '#181717' },
  instagram: { icon: Instagram, color: '#E1306C' }, x: { icon: Twitter, color: '#000000' }, youtube: { icon: Youtube, color: '#FF0000' },
  tiktok: { icon: Music, color: '#010101' }, facebook: { icon: Facebook, color: '#1877F2' }, behance: { icon: Palette, color: '#1769FF' },
  dribbble: { icon: Dribbble, color: '#EA4C89' }, calendly: { icon: Calendar, color: '#006BFF' }, whatsapp: { icon: MessageCircle, color: '#25D366' },
  other: { icon: Link, color: null },
}

/** The short "who" under the service name (Link.handle on the Mac): in/yourname, @yourname, or the site's address. */
export function linkHandle(l: CardLink): string {
  const d = linkDisplay(l)
  const slash = d.indexOf('/')
  const first = slash < 0 ? d : d.slice(0, slash), path = slash < 0 ? '' : d.slice(slash + 1)
  switch (l.kind) {
    case 'linkedin': return path || d
    case 'github': case 'x': case 'instagram': case 'tiktok': case 'youtube': case 'facebook': case 'behance': case 'dribbble': {
      if (d.startsWith('@')) return d
      const last = path ? path.split('/').filter(Boolean).pop() ?? '' : (!d.includes('.') ? d : '')
      return !last ? d : last.startsWith('@') ? last : `@${last}`
    }
    case 'whatsapp': return l.value.trim()
    default: return first || d
  }
}

const linkLabel = (l: CardLink): string => l.kind === 'other' ? (linkHandle(l) || 'Link') : linkTitle(l.kind)

/** What the QR code opens: your contact, your web page, or one of your links (ProfileCard.qrPayload). */
export function cardQRPayload(c: ProfileCard): string {
  if (c.qrTarget === 'web' && c.publishPublic && SLUG_RE.test(c.publicSlug)) return publicURL(c.publicSlug)
  if (c.qrTarget !== 'contact') { const l = filledLinks(c).find((x) => x.id === c.qrTarget); if (l) return linkURL(l) }
  return vCard(c)
}

// MARK: Drawing helpers

const iconCache = new Map<string, Promise<HTMLImageElement | null>>()
function icon(Icon: ComponentType<LucideProps>, color: string, fill = 'none'): Promise<HTMLImageElement | null> {
  const svg = renderToStaticMarkup(<Icon size={24} color={color} fill={fill} strokeWidth={2.4} />)
  if (!iconCache.has(svg)) iconCache.set(svg, loadImage(`data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`))
  return iconCache.get(svg)!
}

function loadImage(src: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => resolve(null)
    img.src = src
  })
}

function wrap(ctx: CanvasRenderingContext2D, text: string, width: number, max: number): string[] {
  const lines: string[] = []
  for (const para of text.split('\n')) {
    let line = ''
    for (const word of para.split(/\s+/).filter(Boolean)) {
      const t = line ? `${line} ${word}` : word
      if (ctx.measureText(t).width <= width || !line) line = t
      else { lines.push(line); line = word }
    }
    if (line) lines.push(line)
  }
  const out = lines.slice(0, max)
  if (lines.length > max || (out.length && ctx.measureText(out[out.length - 1]).width > width)) {
    let last = out[out.length - 1]
    while (last.length > 1 && ctx.measureText(`${last}…`).width > width) last = last.slice(0, -1)
    out[out.length - 1] = `${last.trimEnd()}…`
  }
  return out
}

function fit(ctx: CanvasRenderingContext2D, text: string, width: number): string {
  if (ctx.measureText(text).width <= width) return text
  let t = text
  while (t.length > 1 && ctx.measureText(`${t}…`).width > width) t = t.slice(0, -1)
  return `${t}…`
}

function rr(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath()
  ctx.roundRect(x, y, w, h, Math.min(r, w / 2, h / 2))
}

function alpha(hex: string, a: number): string {
  const n = parseInt(hex.slice(1), 16)
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`
}

function drawQR(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, size: number): void {
  try {
    const m = qrMatrix(text)
    const cell = size / m.size
    ctx.fillStyle = '#000'
    for (let r = 0; r < m.size; r++) for (let c = 0; c < m.size; c++) if (m.get(r, c)) ctx.fillRect(x + c * cell, y + r * cell, cell + 0.03, cell + 0.03)
  } catch { /* too much text for a QR code */ }
}

/** "joshu" with its dot. */
function wordmark(ctx: CanvasRenderingContext2D, x: number, baseline: number, size: number, ink: string, dot: string, a = 1): void {
  ctx.save()
  ctx.globalAlpha = a
  ctx.fillStyle = ink
  ctx.font = `900 ${size}px ${ROUNDED}`
  ctx.fillText('joshu', x, baseline)
  const w = ctx.measureText('joshu').width
  ctx.fillStyle = dot
  ctx.beginPath(); ctx.arc(x + w + 4.5, baseline - 1.5, size * 0.17, 0, Math.PI * 2); ctx.fill()
  ctx.restore()
}

/** The link's logo: the brand's colour with its glyph in white, or a soft circle for a website or other link. */
async function linkLogo(ctx: CanvasRenderingContext2D, kind: LinkKind, x: number, y: number, size: number, ink: string): Promise<void> {
  const b = BRAND[kind]
  ctx.save()
  ctx.beginPath(); ctx.arc(x + size / 2, y + size / 2, size / 2, 0, Math.PI * 2)
  if (b.color) { ctx.fillStyle = b.color; ctx.fill() } else { ctx.fillStyle = ink; ctx.globalAlpha = 0.12; ctx.fill(); ctx.globalAlpha = 1 }
  const img = await icon(b.icon, b.color ? '#ffffff' : ink)
  const g = size * 0.5
  if (img) ctx.drawImage(img, x + (size - g) / 2, y + (size - g) / 2, g, g)
  ctx.restore()
}

// MARK: Faces

export interface DrawOptions { photo: string | null; cover: string | null; back?: boolean; interactive?: boolean; scale?: number; pad?: number }

/** Draws the card (front, or the QR side of the photo card) into `canvas`. */
export async function drawPhoneCard(canvas: HTMLCanvasElement, card: PhoneCardData, o: DrawOptions): Promise<void> {
  await Promise.all([document.fonts.load(`700 30px Fraunces`), document.fonts.load(`600 14px Inter`)]).catch(() => {})
  const scale = o.scale ?? 2, pad = o.pad ?? 0
  const coverSrc = card.showPhoto ? (o.cover ?? o.photo) : null
  const photoCard = card.style === 'photo' && !!coverSrc
  const [photoImg, coverImg] = await Promise.all([
    card.showPhoto && o.photo ? loadImage(o.photo) : Promise.resolve(null),
    photoCard ? loadImage(coverSrc!) : Promise.resolve(null),
  ])
  canvas.width = (CARD_W + pad * 2) * scale
  canvas.height = (CARD_H + pad * 2) * scale
  const ctx = canvas.getContext('2d')!
  ctx.setTransform(scale, 0, 0, scale, pad * scale, pad * scale)
  ctx.clearRect(-pad, -pad, CARD_W + pad * 2, CARD_H + pad * 2)
  ctx.textBaseline = 'alphabetic'
  if (photoCard && coverImg && o.back) await qrBack(ctx, card, !!o.interactive)
  else if (photoCard && coverImg) await photoFace(ctx, card, coverImg, !!o.interactive)
  else await colorFace(ctx, card, photoImg)
}

async function colorFace(ctx: CanvasRenderingContext2D, card: PhoneCardData, photo: HTMLImageElement | null): Promise<void> {
  const dark = cardIsDark(card), ink = dark ? '#F4F4F5' : '#111111'
  rr(ctx, 0, 0, CARD_W, CARD_H, 32); ctx.fillStyle = cardColor(card); ctx.fill()
  ctx.save(); ctx.clip()
  const P = 30, inner = CARD_W - P * 2
  ctx.fillStyle = ink

  // Header: photo, name, what you do, where.
  const ph = photo ? 86 : 0
  const tx = P + (photo ? ph + 16 : 0), tw = CARD_W - P - tx
  let nameSize = 30, name: string[] = []
  for (; nameSize >= 18; nameSize--) {
    ctx.font = `700 ${nameSize}px ${SERIF}`
    name = wrap(ctx, card.name || 'Your name', tw, 2)
    if (!name[name.length - 1].endsWith('…')) break
  }
  ctx.font = `500 15px ${SANS}`
  const sub = [card.headline, card.company].filter(Boolean).join(' · ')
  const subLines = sub ? wrap(ctx, sub, tw, 2) : []
  const nameLH = nameSize * 1.15
  const textH = name.length * nameLH + (subLines.length ? 4 + subLines.length * 19 : 0) + (card.location ? 4 + 16 : 0)
  const headH = Math.max(ph, textH)
  if (photo) {
    const cy = P + headH / 2
    ctx.save(); ctx.beginPath(); ctx.arc(P + 43, cy, 43, 0, Math.PI * 2); ctx.clip()
    const s = Math.min(photo.naturalWidth, photo.naturalHeight)
    ctx.drawImage(photo, (photo.naturalWidth - s) / 2, (photo.naturalHeight - s) / 2, s, s, P, cy - 43, 86, 86)
    ctx.restore()
    ctx.save(); ctx.strokeStyle = ink; ctx.globalAlpha = 0.15; ctx.lineWidth = 3
    ctx.beginPath(); ctx.arc(P + 43, cy, 41.5, 0, Math.PI * 2); ctx.stroke(); ctx.restore()
  }
  let y = P + (headH - textH) / 2
  ctx.font = `700 ${nameSize}px ${SERIF}`
  for (const l of name) { y += nameLH; ctx.fillText(l, tx, y - nameSize * 0.22) }
  if (subLines.length) {
    y += 4; ctx.font = `500 15px ${SANS}`; ctx.globalAlpha = 0.8
    for (const l of subLines) { y += 19; ctx.fillText(l, tx, y - 4) }
    ctx.globalAlpha = 1
  }
  if (card.location) {
    y += 20; ctx.globalAlpha = 0.65; ctx.font = `500 12px ${SANS}`
    const pin = await icon(MapPin, ink)
    if (pin) ctx.drawImage(pin, tx, y - 13, 12, 12)
    ctx.fillText(fit(ctx, card.location, tw - 18), tx + 17, y - 3)
    ctx.globalAlpha = 1
  }
  y = P + headH + 18

  if (card.bio) {
    ctx.font = `400 14px ${SERIF}`; ctx.globalAlpha = 0.85
    for (const l of wrap(ctx, card.bio, inner, 3)) { ctx.fillText(l, P, y + 14); y += 19 }
    ctx.globalAlpha = 1
    y += 18
  }

  // Email and phone as small capsules.
  if (card.email || card.phone) {
    let x = P
    ctx.font = `500 12px ${SANS}`
    for (const [Icon, text] of [[Mail, card.email], [Phone, card.phone]] as const) {
      if (!text) continue
      const label = fit(ctx, text, inner / 2 - 40)
      const w = 10 + 11 + 6 + ctx.measureText(label).width + 10
      ctx.save(); rr(ctx, x, y, w, 26, 13); ctx.fillStyle = ink; ctx.globalAlpha = 0.1; ctx.fill(); ctx.restore()
      const img = await icon(Icon, ink, ink)
      if (img) ctx.drawImage(img, x + 10, y + 7.5, 11, 11)
      ctx.fillStyle = ink; ctx.fillText(label, x + 27, y + 17)
      x += w + 8
    }
    y += 26 + 18
  }

  // Links: logo, service name, handle, ↗.
  const qrTop = CARD_H - P - 140
  for (const l of filledLinks(card).slice(0, 6)) {
    if (y + 44 > qrTop - 6) break
    ctx.save(); rr(ctx, P, y, inner, 44, 14); ctx.fillStyle = ink; ctx.globalAlpha = 0.07; ctx.fill(); ctx.restore()
    await linkLogo(ctx, l.kind, P + 10, y + 7, 30, ink)
    ctx.fillStyle = ink
    const tx2 = P + 51, tw2 = inner - 51 - 30
    if (l.kind === 'other') {
      ctx.font = `600 14px ${SANS}`; ctx.fillText(fit(ctx, linkLabel(l), tw2), tx2, y + 27)
    } else {
      ctx.font = `600 14px ${SANS}`; ctx.fillText(linkTitle(l.kind), tx2, y + 20)
      ctx.font = `500 11px ${SANS}`; ctx.globalAlpha = 0.65; ctx.fillText(fit(ctx, linkHandle(l), tw2), tx2, y + 35); ctx.globalAlpha = 1
    }
    const arrow = await icon(ArrowUpRight, ink)
    if (arrow) { ctx.globalAlpha = 0.55; ctx.drawImage(arrow, P + inner - 22, y + 16, 12, 12); ctx.globalAlpha = 1 }
    y += 44 + 7
  }

  // Footer: caption and wordmark; the QR code on white.
  const box = 140, qx = CARD_W - P - box, qy = CARD_H - P - box
  rr(ctx, qx, qy, box, box, 14); ctx.fillStyle = '#ffffff'; ctx.fill()
  drawQR(ctx, cardQRPayload(card), qx + 8, qy + 8, box - 16)
  ctx.fillStyle = ink
  ctx.font = `600 12px ${SANS}`
  ctx.fillText(card.qrTarget === 'contact' ? 'Scan to save my contact' : 'Scan to open', P, CARD_H - P - 22)
  wordmark(ctx, P, CARD_H - P - 3, 13, ink, dark ? CARD_COLORS[0] : ink, 0.5)
  ctx.restore()
}

async function photoFace(ctx: CanvasRenderingContext2D, card: PhoneCardData, cover: HTMLImageElement, interactive: boolean): Promise<void> {
  const accent = cardIsDark(card) ? '#EDAA2F' : cardColor(card)
  const P = 26, inner = CARD_W - P * 2
  rr(ctx, 0, 0, CARD_W, CARD_H, 32)
  ctx.save(); ctx.clip()
  ctx.fillStyle = '#111113'; ctx.fillRect(0, 0, CARD_W, CARD_H)
  // The photo fills the top 430 points (scaled to fill), then melts into the dark panel.
  const s = Math.max(CARD_W / cover.naturalWidth, 430 / cover.naturalHeight)
  const w = cover.naturalWidth * s, h = cover.naturalHeight * s
  ctx.save(); ctx.beginPath(); ctx.rect(0, 0, CARD_W, 430); ctx.clip()
  ctx.drawImage(cover, (CARD_W - w) / 2, (430 - h) / 2, w, h)
  ctx.restore()
  const g = ctx.createLinearGradient(0, 0, 0, CARD_H)
  g.addColorStop(0, 'rgba(0,0,0,0.3)'); g.addColorStop(0.16, 'rgba(0,0,0,0)'); g.addColorStop(0.36, 'rgba(17,17,19,0)')
  g.addColorStop(0.58, 'rgba(17,17,19,0.85)'); g.addColorStop(0.7, '#111113'); g.addColorStop(1, '#111113')
  ctx.fillStyle = g; ctx.fillRect(0, 0, CARD_W, CARD_H)

  ctx.save(); ctx.shadowColor = 'rgba(0,0,0,0.4)'; ctx.shadowBlur = 6
  wordmark(ctx, P, P + 15, 15, '#ffffff', accent)
  ctx.restore()
  if (interactive) {
    // The round button that turns the card over (the preview's tap target sits on top of it).
    ctx.save(); ctx.beginPath(); ctx.arc(CARD_W - P - 23, P + 10, 23, 0, Math.PI * 2)
    ctx.fillStyle = 'rgba(40,40,44,0.55)'; ctx.fill(); ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 1; ctx.stroke(); ctx.restore()
    const qr = await icon(QrCode, '#ffffff')
    if (qr) ctx.drawImage(qr, CARD_W - P - 33, P, 20, 20)
  }

  // The panel, laid out from the bottom up.
  const role = [card.headline, card.company].filter(Boolean).join(card.headline && card.company ? ' at ' : '')
  ctx.font = `700 34px ${SANS}`
  let nameSize = 34, name: string[] = []
  for (; nameSize >= 22; nameSize -= 2) { ctx.font = `700 ${nameSize}px ${SANS}`; name = wrap(ctx, card.name || 'Your name', inner - 34, 2); if (!name[name.length - 1].endsWith('…')) break }
  ctx.font = `400 18px ${SANS}`; const roleLines = role ? wrap(ctx, role, inner, 2) : []
  ctx.font = `400 14px ${SANS}`; const bioLines = card.bio ? wrap(ctx, card.bio, inner, 3) : []
  const pills: { Icon: ComponentType<LucideProps> | null; kind?: LinkKind; text: string }[] = [
    ...(card.email ? [{ Icon: Mail, text: 'Email' }] : []),
    ...(card.phone ? [{ Icon: Phone, text: 'Call' }] : []),
    ...filledLinks(card).slice(0, 6).map((l) => ({ Icon: null, kind: l.kind, text: linkLabel(l) })),
  ]
  // Pills flow into rows.
  ctx.font = `500 14px ${SANS}`
  const rows: { w: number; items: { text: string; w: number; Icon: ComponentType<LucideProps> | null; kind?: LinkKind }[] }[] = []
  for (const p of pills) {
    const text = fit(ctx, p.text, inner - 60)
    const pw = 14 + 18 + 7 + ctx.measureText(text).width + 14
    const row = rows[rows.length - 1]
    if (row && row.w + 8 + pw <= inner) { row.items.push({ ...p, text, w: pw }); row.w += 8 + pw } else rows.push({ w: pw, items: [{ ...p, text, w: pw }] })
  }
  const pillsH = rows.length ? 8 + rows.length * 36 + (rows.length - 1) * 8 : 0
  const nameLH = nameSize * 1.12
  const total = (card.location ? 16 + 8 : 0) + name.length * nameLH + (roleLines.length ? 8 + roleLines.length * 22 : 0)
    + (bioLines.length ? 12 + bioLines.length * 19 : 0) + pillsH
  let y = CARD_H - P - total

  ctx.fillStyle = '#ffffff'
  if (card.location) {
    ctx.save(); ctx.globalAlpha = 0.85
    const pin = await icon(MapPin, '#ffffff')
    if (pin) ctx.drawImage(pin, P, y + 1, 13, 13)
    ctx.font = `600 12px ${SANS}`
    ctx.letterSpacing = '2.2px'
    ctx.fillText(fit(ctx, card.location.toUpperCase(), inner - 20), P + 19, y + 12)
    ctx.restore()
    y += 24
  }
  const seal = await icon(BadgeCheck, '#111113', accent)
  ctx.font = `700 ${nameSize}px ${SANS}`
  for (const l of name) {
    y += nameLH
    ctx.fillText(l, P, y - nameSize * 0.2)
    if (l === name[name.length - 1] && seal) ctx.drawImage(seal, P + ctx.measureText(l).width + 8, y - nameSize * 0.2 - 20, 22, 22)
  }
  if (roleLines.length) {
    y += 8; ctx.font = `400 18px ${SANS}`; ctx.globalAlpha = 0.82
    for (const l of roleLines) { y += 22; ctx.fillText(l, P, y - 5) }
    ctx.globalAlpha = 1
  }
  if (bioLines.length) {
    y += 12; ctx.font = `400 14px ${SANS}`; ctx.globalAlpha = 0.9
    for (const l of bioLines) { y += 19; ctx.fillText(l, P, y - 4) }
    ctx.globalAlpha = 1
  }
  if (rows.length) {
    y += 8
    for (const row of rows) {
      let x = P
      for (const p of row.items) {
        rr(ctx, x, y, p.w, 36, 18)
        ctx.fillStyle = 'rgba(255,255,255,0.07)'; ctx.fill()
        ctx.strokeStyle = 'rgba(255,255,255,0.16)'; ctx.lineWidth = 1; ctx.stroke()
        if (p.kind) {
          const b = BRAND[p.kind]
          if (b.color) await linkLogo(ctx, p.kind, x + 14, y + 9, 18, '#ffffff')
          else { const img = await icon(b.icon, accent); if (img) ctx.drawImage(img, x + 16, y + 11, 14, 14) }
        } else if (p.Icon) { const img = await icon(p.Icon, accent); if (img) ctx.drawImage(img, x + 16, y + 11, 14, 14) }
        ctx.fillStyle = '#ffffff'; ctx.font = `500 14px ${SANS}`
        ctx.fillText(p.text, x + 39, y + 23)
        x += p.w + 8
      }
      y += 44
    }
  }
  ctx.restore()
}

async function qrBack(ctx: CanvasRenderingContext2D, card: PhoneCardData, interactive: boolean): Promise<void> {
  const color = cardColor(card)
  rr(ctx, 0, 0, CARD_W, CARD_H, 32); ctx.fillStyle = '#141416'; ctx.fill()
  ctx.save(); rr(ctx, 1, 1, CARD_W - 2, CARD_H - 2, 31); ctx.strokeStyle = alpha(color, 0.5); ctx.lineWidth = 2; ctx.stroke(); ctx.restore()
  const P = 28
  wordmark(ctx, P, P + 20, 15, '#ffffff', color, 0.85)
  if (interactive) {
    ctx.save(); ctx.beginPath(); ctx.arc(CARD_W - P - 20, P + 15, 20, 0, Math.PI * 2); ctx.fillStyle = 'rgba(255,255,255,0.16)'; ctx.fill(); ctx.restore()
    const back = await icon(Undo2, '#ffffff')
    if (back) ctx.drawImage(back, CARD_W - P - 28, P + 7, 16, 16)
  }
  const box = 282, bx = (CARD_W - box) / 2, by = 150
  rr(ctx, bx, by, box, box, 26); ctx.fillStyle = '#ffffff'; ctx.fill()
  drawQR(ctx, cardQRPayload(card), bx + 16, by + 16, box - 32)
  ctx.textAlign = 'center'
  ctx.fillStyle = '#ffffff'
  ctx.font = `700 26px ${SERIF}`
  ctx.fillText(fit(ctx, card.name || 'Your name', CARD_W - P * 2), CARD_W / 2, by + box + 46)
  ctx.font = `600 13px ${SANS}`
  ctx.fillStyle = cardIsDark(card) ? '#ffffff' : color
  ctx.fillText(card.qrTarget === 'contact' ? 'Scan to save my contact' : 'Scan to open my link', CARD_W / 2, by + box + 70)
  if (interactive) { ctx.fillStyle = 'rgba(255,255,255,0.5)'; ctx.font = `500 11px ${SANS}`; ctx.fillText('Tap anywhere to turn back', CARD_W / 2, CARD_H - P - 4) }
  ctx.textAlign = 'left'
}

/** The card as a PNG at 3×, with a 20-point margin (same as the Mac's export). */
export async function phoneCardPNG(card: PhoneCardData, photo: string | null, cover: string | null): Promise<Blob> {
  const c = document.createElement('canvas')
  await drawPhoneCard(c, card, { photo, cover, scale: 3, pad: 20 })
  return new Promise((resolve, reject) => c.toBlob((b) => (b ? resolve(b) : reject(new Error('Could not draw the card.'))), 'image/png'))
}
