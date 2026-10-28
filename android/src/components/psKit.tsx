// Small pieces for the iPhone-style sheets on Android (Settings, My Card, Week in review, Plan tomorrow):
// the navigation bar, grouped lists, rows, switches and pickers. Styles in screens/phoneSheets.css (ps-).
import { ReactNode } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import '../screens/phoneSheets.css'

/** Back (when given) · title · Done. */
export function SheetNav({ title, onBack, onDone, doneLabel = 'Done', leading }: {
  title: string; onBack?: () => void; onDone?: () => void; doneLabel?: string; leading?: ReactNode
}) {
  return (
    <header className="ps-nav">
      {onBack
        ? <button className="ps-pillbtn icon" aria-label="Back" onClick={onBack}><ChevronLeft size={22} /></button>
        : leading ?? <span />}
      <span className="ps-nav-title">{title}</span>
      {onDone ? <button className="ps-pillbtn" onClick={onDone}>{doneLabel}</button> : <span />}
    </header>
  )
}

export function Group({ title, footer, children, icons }: { title?: ReactNode; footer?: ReactNode; children: ReactNode; icons?: boolean }) {
  return (
    <section className="ps-group">
      {title && <div className="ps-group-head">{title}</div>}
      <div className={`ps-cells${icons ? ' icons' : ''}`}>{children}</div>
      {footer && <div className="ps-group-foot">{footer}</div>}
    </section>
  )
}

/** A coloured square with a white-ish glyph, like the iPhone's settings icons. */
export function Tile({ color, children, ink = 'var(--sticker-ink)', large }: { color: string; children: ReactNode; ink?: string; large?: boolean }) {
  return <span className={`ps-tile${large ? ' lg' : ''}`} style={{ background: color, color: ink }}>{children}</span>
}

/** A row: optional icon, title with a line under it, and something on the right. */
export function Cell({ icon, title, sub, detail, trailing, onClick, chevron, top, className = '' }: {
  icon?: ReactNode; title: ReactNode; sub?: ReactNode; detail?: ReactNode; trailing?: ReactNode; onClick?: () => void
  chevron?: boolean; top?: boolean; className?: string
}) {
  const inner = (
    <>
      {icon}
      <span className="ps-cell-main">
        <span className="ps-cell-title">{title}</span>
        {sub && <span className="ps-cell-sub">{sub}</span>}
      </span>
      {detail !== undefined && detail !== null && detail !== '' && <span className="ps-cell-detail">{detail}</span>}
      {trailing}
      {chevron && <ChevronRight size={18} className="ps-chev" />}
    </>
  )
  const cls = `ps-cell${top ? ' top' : ''} ${className}`
  return onClick ? <button className={cls} onClick={onClick}>{inner}</button> : <div className={cls}>{inner}</div>
}

export function Switch({ on, onChange, disabled, label }: { on: boolean; onChange: (on: boolean) => void; disabled?: boolean; label?: string }) {
  return <button role="switch" aria-checked={on} aria-label={label} disabled={disabled} className={`ps-switch${on ? ' on' : ''}`} onClick={() => onChange(!on)} />
}

/** A row with a switch; the whole row toggles it. */
export function ToggleCell({ title, sub, on, onChange, icon, disabled }: {
  title: ReactNode; sub?: ReactNode; on: boolean; onChange: (on: boolean) => void; icon?: ReactNode; disabled?: boolean
}) {
  return (
    <div className={`ps-cell${sub ? ' top' : ''}`} onClick={() => !disabled && onChange(!on)} style={{ cursor: 'pointer' }}>
      {icon}
      <span className="ps-cell-main">
        <span className="ps-cell-title" style={{ fontSize: 15.5, fontWeight: 400 }}>{title}</span>
        {sub && <span className="ps-cell-sub">{sub}</span>}
      </span>
      <span onClick={(e) => e.stopPropagation()} style={{ display: 'inline-flex' }}>
        <Switch on={on} onChange={onChange} disabled={disabled} label={typeof title === 'string' ? title : undefined} />
      </span>
    </div>
  )
}

/** "Label ……… value ⌄", like a SwiftUI Picker in a Form. */
export function PickerCell<T extends string | number>({ title, value, options, onChange }: {
  title: ReactNode; value: T; options: { value: T; label: string }[]; onChange: (v: T) => void
}) {
  return (
    <label className="ps-cell">
      <span className="ps-cell-main"><span className="ps-cell-title" style={{ fontSize: 15.5, fontWeight: 400 }}>{title}</span></span>
      <select className="ps-select" value={String(value)}
        onChange={(e) => { const o = options.find((x) => String(x.value) === e.target.value); if (o) onChange(o.value) }}>
        {options.map((o) => <option key={String(o.value)} value={String(o.value)}>{o.label}</option>)}
      </select>
    </label>
  )
}

/** "Label ……… [text]" that saves when you leave the field. */
export function TextCell({ title, value, placeholder, onSave, type = 'text', inputMode }: {
  title: ReactNode; value: string; placeholder?: string; onSave: (v: string) => void; type?: string; inputMode?: 'text' | 'decimal' | 'numeric' | 'email'
}) {
  return (
    <label className="ps-cell">
      <span className="ps-cell-title" style={{ fontSize: 15.5, fontWeight: 400, flex: 'none' }}>{title}</span>
      <input key={value} className="ps-input" type={type} inputMode={inputMode} defaultValue={value} placeholder={placeholder}
        onBlur={(e) => { if (e.target.value !== value) onSave(e.target.value) }}
        onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} />
    </label>
  )
}
