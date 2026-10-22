// Draws "My Card" on a canvas, laid out like CardFace in ProfileCardView.swift (420 × 620 points).
// The same drawing is the live preview and the exported PNG, so what you see is what you share.
import { ComponentType } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import {
  Briefcase, Globe, CodeXml, Camera, AtSign, SquarePlay, Music, Users, Palette, Calendar, MessageCircle, Link, Mail, Phone, MapPin, LucideProps,
} from 'lucide-react'
import { ProfileCard, LinkKind, cardColor, cardIsDark, filledLinks, linkDisplay, qrMatrix, qrPayload } from '@/lib/profileCard'

export const CARD_W = 420, CARD_H = 620

const LINK_ICON: Record<LinkKind, ComponentType<LucideProps>> = {
  linkedin: Briefcase, website: Globe, github: CodeXml, instagram: Camera, x: AtSign, youtube: SquarePlay, tiktok: Music,
  facebook: Users, behance: Palette, dribbble: Palette, calendly: Calendar, whatsapp: MessageCircle, other: Link,
}
export const linkIcon = (k: LinkKind) => LINK_ICON[k] ?? Link

const iconCache = new Map<string, Promise<HTMLImageElement>>()
function iconImage(Icon: ComponentType<LucideProps>, color: string): Promise<HTMLImageElement> {
  const svg = renderToStaticMarkup(<Icon size={24} color={color} strokeWidth={2.4} />)
  const key = svg
  if (!iconCache.has(key)) {
    iconCache.set(key, new Promise((resolve, reject) => {
      const img = new Image()
      img.onload = () => resolve(img)
      img.onerror = reject
      img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`
    }))
  }
  return iconCache.get(key)!
}

function loadImage(src: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => resolve(null)
    img.src = src
  })
}

/** Word-wraps into at most `max` lines (the last one ends in … when cut). Returns the lines and whether it all fit. */
function wrap(ctx: CanvasRenderingContext2D, text: string, width: number, max: number): { lines: string[]; fit: boolean } {
  const lines: string[] = []
  for (const para of text.split('\n')) {
    let line = ''
    for (const word of para.split(/\s+/).filter(Boolean)) {
      const tryLine = line ? `${line} ${word}` : word
      if (ctx.measureText(tryLine).width <= width || !line) line = tryLine
      else { lines.push(line); line = word }
    }
    lines.push(line)
  }
  if (lines.length <= max && lines.every((l) => ctx.measureText(l).width <= width)) return { lines, fit: true }
  const out = lines.slice(0, max)
  let last = out[max - 1] ?? ''
  if (lines.length > max) last += '…'
  while (last.length > 1 && ctx.measureText(last).width > width) last = `${last.slice(0, -2)}…`
  out[out.length - 1] = last
  return { lines: out, fit: false }
}

/** Truncates in the middle, like SwiftUI's .truncationMode(.middle). */
function middleTruncate(ctx: CanvasRenderingContext2D, text: string, width: number): string {
  if (ctx.measureText(text).width <= width) return text
  let a = Math.ceil(text.length / 2), b = Math.floor(text.length / 2)
  while (a > 1) {
    const t = `${text.slice(0, a)}…${text.slice(text.length - b)}`
    if (ctx.measureText(t).width <= width) return t
    a--; b--
  }
  return '…'
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath()
  ctx.roundRect(x, y, w, h, r)
}

const SERIF = "Fraunces, Georgia, 'Times New Roman', serif"
const SANS = "Inter, 'Segoe UI', system-ui, sans-serif"

/**
 * Draws the card into `canvas` at `scale` (device pixels per point), with `pad` points of transparent margin
 * (the exported image has 20, like the Mac's).
 */
export async function drawCard(canvas: HTMLCanvasElement, card: ProfileCard, photo: string | null, scale = 2, pad = 0): Promise<void> {
  await Promise.all([document.fonts.load(`700 30px Fraunces`), document.fonts.load(`500 14px Fraunces`), document.fonts.load(`600 14px Inter`)]).catch(() => {})
  const ink = cardIsDark(card) ? '#F4F4F5' : '#111111'
  const links = filledLinks(card).slice(0, 7)
  const rows: { icon: ComponentType<LucideProps>; text: string }[] = [
    ...(card.email ? [{ icon: Mail, text: card.email }] : []),
    ...(card.phone ? [{ icon: Phone, text: card.phone }] : []),
    ...links.map((l) => ({ icon: linkIcon(l.kind), text: linkDisplay(l) })),
  ]
  const [photoImg, rowIcons, pin] = await Promise.all([
    card.showPhoto && photo ? loadImage(photo) : Promise.resolve(null),
    Promise.all(rows.map((r) => iconImage(r.icon, ink))),
    iconImage(MapPin, ink),
  ])

  canvas.width = (CARD_W + pad * 2) * scale
  canvas.height = (CARD_H + pad * 2) * scale
  const ctx = canvas.getContext('2d')!
  ctx.setTransform(scale, 0, 0, scale, pad * scale, pad * scale)
  ctx.clearRect(-pad, -pad, CARD_W + pad * 2, CARD_H + pad * 2)
  ctx.textBaseline = 'alphabetic'

  roundRect(ctx, 0, 0, CARD_W, CARD_H, 32)
  ctx.fillStyle = cardColor(card)
  ctx.fill()
  ctx.save()
  ctx.clip()
  ctx.fillStyle = ink
  ctx.strokeStyle = ink

  const P = 30, inner = CARD_W - P * 2
  // Header: photo + name, subtitle, location.
  const photoSize = photoImg ? 86 : 0
  const textX = P + (photoImg ? photoSize + 16 : 0), textW = CARD_W - P - textX
  let nameSize = 30, name: { lines: string[]; fit: boolean } = { lines: [], fit: true }
  for (; nameSize >= 18; nameSize--) {
    ctx.font = `700 ${nameSize}px ${SERIF}`
    name = wrap(ctx, card.name || 'Your name', textW, 2)
    if (name.fit) break
  }
  nameSize = Math.max(nameSize, 18)
  ctx.font = `500 15px ${SANS}`
  const sub = [card.headline, card.company].filter(Boolean).join(' · ')
  const subLines = sub ? wrap(ctx, sub, textW, 2).lines : []
  const nameLH = nameSize * 1.15, subLH = 19
  const textH = name.lines.length * nameLH + (subLines.length ? 4 + subLines.length * subLH : 0) + (card.location ? 4 + 16 : 0)
  const headH = Math.max(photoSize, textH)
  if (photoImg) {
    const cy = P + headH / 2
    ctx.save()
    ctx.beginPath(); ctx.arc(P + 43, cy, 43, 0, Math.PI * 2); ctx.clip()
    const s = Math.min(photoImg.naturalWidth, photoImg.naturalHeight)
    ctx.drawImage(photoImg, (photoImg.naturalWidth - s) / 2, (photoImg.naturalHeight - s) / 2, s, s, P, cy - 43, 86, 86)
    ctx.restore()
    ctx.globalAlpha = 0.15; ctx.lineWidth = 3
    ctx.beginPath(); ctx.arc(P + 43, cy, 41.5, 0, Math.PI * 2); ctx.stroke()
    ctx.globalAlpha = 1
  }
  let y = P + (headH - textH) / 2
  ctx.font = `700 ${nameSize}px ${SERIF}`
  for (const l of name.lines) { y += nameLH; ctx.fillText(l, textX, y - nameSize * 0.22) }
  if (subLines.length) {
    y += 4; ctx.font = `500 15px ${SANS}`; ctx.globalAlpha = 0.8
    for (const l of subLines) { y += subLH; ctx.fillText(l, textX, y - 4) }
    ctx.globalAlpha = 1
  }
  if (card.location) {
    y += 4 + 16
    ctx.globalAlpha = 0.65; ctx.font = `500 12px ${SANS}`
    ctx.drawImage(pin, textX, y - 13, 12, 12)
    ctx.fillText(wrap(ctx, card.location, textW - 18, 1).lines[0], textX + 17, y - 3)
    ctx.globalAlpha = 1
  }
  y = P + headH + 18

  // Bio
  if (card.bio) {
    ctx.font = `500 14px ${SERIF}`; ctx.globalAlpha = 0.85
    for (const l of wrap(ctx, card.bio, inner, 3).lines) { ctx.fillText(l, P, y + 14); y += 19 }
    ctx.globalAlpha = 1
    y += 18
  }

  // Contact rows
  ctx.font = `500 14px ${SANS}`
  rows.forEach((r, i) => {
    ctx.globalAlpha = 0.1
    ctx.beginPath(); ctx.arc(P + 14, y + 14, 14, 0, Math.PI * 2); ctx.fill()
    ctx.globalAlpha = 1
    ctx.drawImage(rowIcons[i], P + 8, y + 8, 12, 12)
    ctx.fillText(middleTruncate(ctx, r.text, inner - 38), P + 38, y + 19)
    y += 28 + 9
  })

  // Footer: caption + orbit logo, QR code.
  const qrBox = 166, qrX = CARD_W - P - qrBox, qrY = CARD_H - P - qrBox
  roundRect(ctx, qrX, qrY, qrBox, qrBox, 14)
  ctx.fillStyle = '#ffffff'; ctx.fill()
  try {
    const m = qrMatrix(qrPayload(card))
    const cell = 150 / (m.size + 2)
    ctx.fillStyle = '#000000'
    for (let r = 0; r < m.size; r++) for (let c = 0; c < m.size; c++) {
      if (m.get(r, c)) ctx.fillRect(qrX + 8 + (c + 1) * cell, qrY + 8 + (r + 1) * cell, cell + 0.02, cell + 0.02)
    }
  } catch { /* too much text for a QR code */ }
  ctx.fillStyle = ink
  ctx.font = `600 12px ${SANS}`
  ctx.fillText(card.qrTarget === 'contact' ? 'Scan to save my contact' : 'Scan to open', P, CARD_H - P - 22)
  ctx.globalAlpha = 0.5
  ctx.font = `900 13px ${SANS}`
  ctx.fillText('orbit', P, CARD_H - P - 2)
  const w = ctx.measureText('orbit').width
  ctx.fillStyle = cardIsDark(card) ? '#E6FF1F' : ink
  ctx.beginPath(); ctx.arc(P + w + 4, CARD_H - P - 4, 2, 0, Math.PI * 2); ctx.fill()
  ctx.globalAlpha = 1
  ctx.restore()
}

/** The card as a PNG at 3×, with a 20-point margin (same as the Mac's export). */
export async function cardPNG(card: ProfileCard, photo: string | null): Promise<Blob> {
  const c = document.createElement('canvas')
  await drawCard(c, card, photo, 3, 20)
  return new Promise((resolve, reject) => c.toBlob((b) => (b ? resolve(b) : reject(new Error('Could not draw the card.'))), 'image/png'))
}
