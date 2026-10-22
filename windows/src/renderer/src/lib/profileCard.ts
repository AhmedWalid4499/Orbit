// "My Card": your shareable contact card. Ported from ProfileCard.swift (Mac).
// Stored as a JSON string in the synced "profileCard" setting, in the same shape the Mac's Codable writes,
// so editing it on either app shows up on the other.
import { useEffect, useState } from 'react'
import { create as createQR } from 'qrcode'
import { store, useSetting } from './store'
import { getSession, rest, CloudError } from './cloud'

export type LinkKind = 'linkedin' | 'website' | 'github' | 'instagram' | 'x' | 'youtube' | 'tiktok' | 'facebook' | 'behance' | 'dribbble' | 'calendly' | 'whatsapp' | 'other'
export const LINK_KINDS: LinkKind[] = ['linkedin', 'website', 'github', 'instagram', 'x', 'youtube', 'tiktok', 'facebook', 'behance', 'dribbble', 'calendly', 'whatsapp', 'other']

export interface CardLink { id: string; kind: LinkKind; value: string }

export interface ProfileCard {
  name: string
  headline: string
  company: string
  email: string
  phone: string
  location: string
  bio: string
  links: CardLink[]
  /** Index into CARD_COLORS. */
  colorIndex: number
  showPhoto: boolean
  /** What the QR code opens: "contact" (adds you to their contacts) or a link id. */
  qrTarget: string
  /** Public web page: ahmedwalid4499.github.io/Orbit/card/?u=<slug> */
  publicSlug: string
  publishPublic: boolean
  /** Email and phone stay off the public page unless you turn this on. */
  publicShowContact: boolean
}

export const CARD_COLORS = ['#E6FF1F', '#F7C2EC', '#27D3F6', '#B58CF7', '#EDAA2F', '#8EEDBF', '#141416']
export const cardColor = (c: ProfileCard): string => CARD_COLORS[Math.min(Math.max(c.colorIndex, 0), CARD_COLORS.length - 1)]
export const cardIsDark = (c: ProfileCard): boolean => c.colorIndex === CARD_COLORS.length - 1

const TITLES: Partial<Record<LinkKind, string>> = { linkedin: 'LinkedIn', x: 'X (Twitter)', github: 'GitHub', youtube: 'YouTube', tiktok: 'TikTok', whatsapp: 'WhatsApp' }
export const linkTitle = (k: LinkKind): string => TITLES[k] ?? k[0].toUpperCase() + k.slice(1)
export const LINK_PLACEHOLDER: Record<LinkKind, string> = {
  linkedin: 'linkedin.com/in/yourname', website: 'yourname.com', github: 'github.com/yourname', instagram: '@yourname', x: '@yourname',
  youtube: 'youtube.com/@yourname', tiktok: '@yourname', facebook: 'facebook.com/yourname', behance: 'behance.net/yourname',
  dribbble: 'dribbble.com/yourname', calendly: 'calendly.com/yourname', whatsapp: '+20 100 000 0000', other: 'https://…',
}

/** Swift's UUID().uuidString: upper case, which is what qrTarget compares against. */
export const newLinkID = (): string => crypto.randomUUID().toUpperCase()

/** A full URL for the link: handles "@name" and bare domains (same as Link.url on the Mac). */
export function linkURL(l: CardLink): string {
  const v = l.value.trim()
  if (v.toLowerCase().startsWith('http')) return v
  const handle = v.startsWith('@') ? v.slice(1) : v
  const isHandle = v.startsWith('@') || !v.includes('.')
  switch (l.kind) {
    case 'instagram': if (isHandle) return `https://instagram.com/${handle}`; break
    case 'x': if (isHandle) return `https://x.com/${handle}`; break
    case 'tiktok': if (isHandle) return `https://tiktok.com/@${handle}`; break
    case 'github': if (isHandle) return `https://github.com/${handle}`; break
    case 'linkedin': if (isHandle) return `https://linkedin.com/in/${handle}`; break
    case 'youtube': if (isHandle) return `https://youtube.com/@${handle}`; break
    case 'whatsapp': return `https://wa.me/${[...v].filter((ch) => /\p{N}/u.test(ch)).join('')}`
  }
  return `https://${v}`
}

/** Short text shown on the card (no https://, no trailing slash). */
export const linkDisplay = (l: CardLink): string => l.value.trim().replace(/^https?:\/\/(www\.)?/, '').replace(/^\/+|\/+$/g, '')

export const filledLinks = (c: ProfileCard): CardLink[] => c.links.filter((l) => l.value.replace(/^[ \t]+|[ \t]+$/g, '').length > 0)

/** vCard 3.0, identical to ProfileCard.vCard on the Mac. */
export function vCard(c: ProfileCard): string {
  const esc = (s: string) => s.replace(/\\/g, '\\\\').replace(/,/g, '\\,').replace(/;/g, '\\;').replace(/\n/g, '\\n')
  const parts = c.name.split(' ').filter(Boolean)
  const last = parts.length > 1 ? parts[parts.length - 1] : ''
  const first = parts.length > 1 ? parts.slice(0, -1).join(' ') : c.name
  const lines = ['BEGIN:VCARD', 'VERSION:3.0', `N:${esc(last)};${esc(first)};;;`, `FN:${esc(c.name)}`]
  if (c.headline) lines.push(`TITLE:${esc(c.headline)}`)
  if (c.company) lines.push(`ORG:${esc(c.company)}`)
  if (c.email) lines.push(`EMAIL;TYPE=INTERNET:${c.email}`)
  if (c.phone) lines.push(`TEL;TYPE=CELL:${c.phone}`)
  if (c.location) lines.push(`ADR;TYPE=HOME:;;;${esc(c.location)};;;`)
  for (const l of filledLinks(c)) {
    if (['linkedin', 'x', 'instagram', 'facebook', 'tiktok', 'github', 'youtube'].includes(l.kind)) lines.push(`X-SOCIALPROFILE;TYPE=${l.kind}:${linkURL(l)}`)
    lines.push(`URL;TYPE=${linkTitle(l.kind)}:${linkURL(l)}`)
  }
  if (c.bio) lines.push(`NOTE:${esc(c.bio)}`)
  lines.push('END:VCARD')
  return lines.join('\r\n')
}

/** What the QR code holds. */
export function qrPayload(c: ProfileCard): string {
  if (c.qrTarget !== 'contact') { const l = filledLinks(c).find((x) => x.id === c.qrTarget); if (l) return linkURL(l) }
  return vCard(c)
}

export function shareText(c: ProfileCard): string {
  return [
    ...[c.name, [c.headline, c.company].filter(Boolean).join(' · ')].filter(Boolean),
    ...[c.email, c.phone].filter(Boolean),
    ...filledLinks(c).map((l) => `${linkTitle(l.kind)}: ${linkURL(l)}`),
  ].join('\n')
}

/** QR modules (medium error correction, like the Mac's CIQRCodeGenerator "M"). */
export function qrMatrix(text: string): { size: number; get: (r: number, c: number) => boolean } {
  const q = createQR(text, { errorCorrectionLevel: 'M' })
  return { size: q.modules.size, get: (r, c) => !!q.modules.get(r, c) }
}

// MARK: Storage

function decode(raw: unknown, userName: string): ProfileCard {
  let j: any = null
  if (typeof raw === 'string') { try { j = JSON.parse(raw) } catch { /* fall back */ } } else if (raw && typeof raw === 'object') j = raw
  const str = (v: unknown, d = '') => (typeof v === 'string' ? v : d)
  if (!j) {
    return {
      name: userName, headline: '', company: '', email: '', phone: '', location: '', bio: '',
      links: [{ id: newLinkID(), kind: 'linkedin', value: '' }, { id: newLinkID(), kind: 'website', value: '' }],
      colorIndex: 0, showPhoto: true, qrTarget: 'contact', publicSlug: '', publishPublic: false, publicShowContact: false,
    }
  }
  return {
    name: str(j.name), headline: str(j.headline), company: str(j.company), email: str(j.email), phone: str(j.phone),
    location: str(j.location), bio: str(j.bio),
    links: Array.isArray(j.links) ? j.links.filter((l: any) => l && LINK_KINDS.includes(l.kind)).map((l: any) => ({ id: str(l.id) || newLinkID(), kind: l.kind, value: str(l.value) })) : [],
    colorIndex: Number.isInteger(j.colorIndex) ? j.colorIndex : 0,
    showPhoto: typeof j.showPhoto === 'boolean' ? j.showPhoto : true,
    qrTarget: str(j.qrTarget, 'contact') || 'contact',
    publicSlug: str(j.publicSlug), publishPublic: !!j.publishPublic, publicShowContact: !!j.publicShowContact,
  }
}

export function useProfileCard(): ProfileCard {
  const raw = useSetting<unknown>('profileCard', null)
  const userName = useSetting<string>('userName', '')
  return decode(raw, userName)
}

/** Saves as a JSON string, the way the Mac stores it. */
export function saveProfileCard(c: ProfileCard): void {
  store.setSetting('profileCard', JSON.stringify(c))
}

// MARK: Profile photo (this PC only, like the Mac's ProfileStore)

const PHOTO_KEY = 'orbit.profilePhoto'
const photoSubs = new Set<() => void>()

export function profilePhoto(): string | null {
  try { return localStorage.getItem(PHOTO_KEY) } catch { return null }
}

export function useProfilePhoto(): string | null {
  const [p, set] = useState(profilePhoto)
  useEffect(() => { const f = () => set(profilePhoto()); photoSubs.add(f); return () => { photoSubs.delete(f) } }, [])
  return p
}

/** Lets you pick an image, crops it to a square and keeps a 256 px copy. */
export function chooseProfilePhoto(): void {
  const input = document.createElement('input')
  input.type = 'file'
  input.accept = 'image/*'
  input.onchange = async () => {
    const f = input.files?.[0]
    if (!f) return
    const url = await resizeSquare(URL.createObjectURL(f), 256, 'image/png')
    try { localStorage.setItem(PHOTO_KEY, url) } catch { return }
    photoSubs.forEach((s) => s())
  }
  input.click()
}

export function removeProfilePhoto(): void {
  localStorage.removeItem(PHOTO_KEY)
  photoSubs.forEach((s) => s())
}

export function resizeSquare(src: string, size: number, type: string, quality?: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => {
      const c = document.createElement('canvas')
      c.width = c.height = size
      const s = Math.min(img.naturalWidth, img.naturalHeight)
      const ctx = c.getContext('2d')!
      if (type === 'image/jpeg') { ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, size, size) }
      ctx.drawImage(img, (img.naturalWidth - s) / 2, (img.naturalHeight - s) / 2, s, s, 0, 0, size, size)
      resolve(c.toDataURL(type, quality))
    }
    img.onerror = reject
    img.src = src
  })
}

// MARK: Public page

export const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/
export const publicURL = (slug: string): string => `https://ahmedwalid4499.github.io/Orbit/card/?u=${slug}`

/** A slug suggestion from your name, e.g. "Yuto Tanaka" → "yuto-tanaka". */
export function suggestSlug(name: string): string {
  return name.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40).replace(/-+$/, '')
}

/** The row for `public_cards` (shape documented in supabase/public_cards.sql). */
export async function publicCardData(c: ProfileCard, photo: string | null): Promise<Record<string, unknown>> {
  let small = ''
  if (c.showPhoto && photo) { try { small = await resizeSquare(photo, 160, 'image/jpeg', 0.8) } catch { small = '' } }
  return {
    name: c.name, headline: c.headline, company: c.company, location: c.location, bio: c.bio, colorIndex: c.colorIndex,
    links: filledLinks(c).map((l) => ({ kind: l.kind, url: linkURL(l), display: linkDisplay(l) })),
    email: c.publicShowContact ? c.email : '',
    phone: c.publicShowContact ? c.phone : '',
    photo: small,
  }
}

/** Publishes (or updates) your public card. When you renamed it, your row under the old name is replaced. */
export async function publishPublicCard(c: ProfileCard, photo: string | null): Promise<void> {
  const s = getSession()
  if (!s) throw new CloudError('Sign in to publish your card.')
  if (!SLUG_RE.test(c.publicSlug)) throw new CloudError('Use 3–40 lowercase letters, numbers or dashes (not at the start or end).')
  const body = { slug: c.publicSlug, data: await publicCardData(c, photo) }
  const upsert = () => rest('public_cards?on_conflict=slug', { method: 'POST', prefer: 'resolution=merge-duplicates,return=minimal', body })
  const taken = (m: string) => /\b403\b|row-level security/i.test(m)
  try {
    await upsert()
  } catch (e) {
    const m = (e as Error).message
    if (taken(m)) throw new CloudError('That name is taken. Try another one.')
    if (!/\b409\b|duplicate|unique/i.test(m)) throw e
    // One card per person: you already have one under another name, so move it to the new one.
    await rest(`public_cards?user_id=eq.${s.userID}&slug=neq.${encodeURIComponent(c.publicSlug)}`, { method: 'DELETE', prefer: 'return=minimal' })
    try { await upsert() } catch (e2) {
      if (taken((e2 as Error).message)) throw new CloudError('That name is taken. Try another one.')
      throw e2
    }
  }
}

/** Removes your public card. */
export async function unpublishPublicCard(): Promise<void> {
  const s = getSession()
  if (!s) return
  await rest(`public_cards?user_id=eq.${s.userID}`, { method: 'DELETE', prefer: 'return=minimal' })
}
