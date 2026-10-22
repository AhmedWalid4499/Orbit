// Shared building blocks, mirroring Theme.swift on the Mac.
import { ReactNode, useEffect } from 'react'
import { Check, X } from 'lucide-react'
import { Area, AREA_COLOR, cap } from '@/lib/models'
import { useSetting } from '@/lib/store'

export function Card({ children, fill, padding = 18, className = '', style }: {
  children: ReactNode; fill?: string; padding?: number; className?: string; style?: React.CSSProperties
}) {
  return <div className={`card ${className}`} style={{ background: fill, padding, ...style }}>{children}</div>
}

export function SectionHeader({ title, trailing, onTrailing }: { title: string; trailing?: string; onTrailing?: () => void }) {
  return (
    <div className="row" style={{ alignItems: 'baseline' }}>
      <h3 className="section-title">{title}</h3>
      <span className="spacer" />
      {trailing && <button className="link" onClick={onTrailing}>{trailing}</button>}
    </div>
  )
}

export function AreaPill({ area, compact, selected = true, onClick }: { area: Area; compact?: boolean; selected?: boolean; onClick?: () => void }) {
  return (
    <span className={`pill ${compact ? 'compact' : ''}`} onClick={onClick}
      style={{ background: AREA_COLOR[area], opacity: selected ? 1 : 0.35, cursor: onClick ? 'pointer' : undefined }}>
      {cap(area)}
    </span>
  )
}

export function AreaPicker({ value, onChange }: { value: Area; onChange: (a: Area) => void }) {
  const areas: Area[] = ['health', 'work', 'study', 'money', 'home', 'social', 'personal']
  return (
    <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
      {areas.map((a) => (
        <span key={a} style={{ borderRadius: 999, outline: value === a ? '1.5px solid var(--ink)' : 'none' }}>
          <AreaPill area={a} compact selected={value === a} onClick={() => onChange(a)} />
        </span>
      ))}
    </div>
  )
}

export function CheckCircle({ on, tint, size = 20, onClick }: { on: boolean; tint?: string; size?: number; onClick?: () => void }) {
  return (
    <button className={`check ${on ? 'on' : ''}`} onClick={onClick}
      style={{ width: size, height: size, ...(on && tint ? { background: tint, borderColor: tint, color: 'var(--sticker-ink)' } : {}) }}>
      {on && <Check size={size * 0.55} strokeWidth={3} />}
    </button>
  )
}

export function StatTile({ value, label, icon, color, onClick }: { value: string; label: string; icon: ReactNode; color: string; onClick?: () => void }) {
  return (
    <button onClick={onClick} className="stat-tile" style={{ background: color }}>
      <div style={{ minWidth: 0, textAlign: 'left' }}>
        <div className="display clamp1" style={{ fontSize: 24 }}>{value}</div>
        <div className="clamp1" style={{ fontSize: 11, fontWeight: 600, opacity: 0.8 }}>{label}</div>
      </div>
      <span className="spacer" />
      <span className="tile-icon">{icon}</span>
    </button>
  )
}

export function EmptyHint({ icon, text }: { icon?: ReactNode; text: string }) {
  return <div className="row muted" style={{ fontSize: 13, padding: '6px 0' }}>{icon}{text}</div>
}

export function Segmented<T extends string>({ options, value, onChange }: { options: { id: T; label: string }[]; value: T; onChange: (v: T) => void }) {
  return (
    <div className="seg">
      {options.map((o) => <button key={o.id} className={value === o.id ? 'on' : ''} onClick={() => onChange(o.id)}>{o.label}</button>)}
    </div>
  )
}

export function Modal({ open, onClose, children, width = 480 }: { open: boolean; onClose: () => void; children: ReactNode; width?: number }) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])
  if (!open) return null
  return (
    <div className="backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div className="modal" style={{ width }}>
        <button className="icon-btn" style={{ float: 'right', width: 30, height: 30 }} onClick={onClose} title="Close"><X size={15} /></button>
        {children}
      </div>
    </div>
  )
}

/** Formats money in your Orbit currency (synced from the Mac). */
export function useMoney(): (v: number, signed?: boolean) => string {
  const code = useSetting<string>('currencyCode', defaultCurrency())
  return (v, signed) => {
    let s: string
    try {
      s = new Intl.NumberFormat(undefined, { style: 'currency', currency: code, maximumFractionDigits: 2, minimumFractionDigits: 0 }).format(Math.abs(v))
    } catch {
      s = `${code} ${Math.abs(v).toFixed(0)}`
    }
    if (signed) return v < 0 ? `−${s}` : `+${s}`
    return v < 0 ? `-${s}` : s
  }
}

export function defaultCurrency(): string {
  const region = (navigator.language.split('-')[1] ?? '').toUpperCase()
  const byRegion: Record<string, string> = { EG: 'EGP', US: 'USD', GB: 'GBP', AE: 'AED', SA: 'SAR', KW: 'KWD', QA: 'QAR', JP: 'JPY', CA: 'CAD', AU: 'AUD', IN: 'INR', DE: 'EUR', FR: 'EUR', ES: 'EUR', IT: 'EUR', NL: 'EUR' }
  return byRegion[region] ?? 'USD'
}

/** A date picker for an optional ISO date (stored at noon local time, so it never slips a day). */
export function DateInput({ value, onChange, allowClear = true, style }: {
  value: string | null; onChange: (v: string | null) => void; allowClear?: boolean; style?: React.CSSProperties
}) {
  const d = value ? new Date(value) : null
  const v = d && !isNaN(d.getTime()) ? `${String(d.getFullYear()).padStart(4, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}` : ''
  return (
    <input type="date" className="field" style={{ width: 170, ...style }} value={v}
      onChange={(e) => {
        if (!e.target.value) { if (allowClear) onChange(null); return }
        const [y, m, day] = e.target.value.split('-').map(Number)
        const n = new Date(2000, m - 1, day, 12)
        n.setFullYear(y)
        onChange(n.toISOString().replace(/\.\d{3}Z$/, 'Z'))
      }} />
  )
}

/** Small labelled row for edit sheets. */
export function FormRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="row" style={{ gap: 12, fontSize: 13 }}>
      <span className="secondary" style={{ width: 110, flex: 'none' }}>{label}</span>
      {children}
    </label>
  )
}
