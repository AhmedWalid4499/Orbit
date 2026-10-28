// Small pieces the ported iPhone sections share (PhoneMore, PhoneCalendar, PhoneHabits, PhoneNotes, PhoneBucket):
// the large section title, a pushed screen with its own back button (NavigationStack push on the iPhone),
// an action sheet (the iPhone's context menus and Menu buttons), a switch, and a long press.
import { ReactNode, useEffect, useRef } from 'react'
import { ChevronLeft, Check } from 'lucide-react'
import { Modal } from '@/components/ui'
import './pm2.css'

/** The large title a section shows under the back button (.toolbarTitleDisplayMode(.inlineLarge)). */
export function SectionTitle({ children }: { children: ReactNode }) {
  return <h1 className="pm2-title">{children}</h1>
}

/** A screen pushed over the section. Android's back button (an Escape from the shell) closes it, unless a sheet is open on top. */
export function PushPage({ title, onBack, className = '', children }: { title?: string; onBack: () => void; className?: string; children: ReactNode }) {
  const back = useRef(onBack)
  back.current = onBack
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      if (document.querySelector('.modal')) return // the sheet on top closes first
      back.current()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])
  return (
    <div className={`backdrop pm2-push ${className}`}>
      <div className="pm2-push-bar">
        <button className="pm2-back" aria-label="Back" onClick={onBack}><ChevronLeft size={22} /></button>
        <span className="t">{title ?? ''}</span>
      </div>
      <div className="pm2-push-body">{children}</div>
    </div>
  )
}

export interface SheetAction { label: string; icon?: ReactNode; danger?: boolean; onClick: () => void }

/** The iPhone's Menu / context menu as a bottom sheet of choices. */
export function ActionSheet({ open, title, actions, onClose, children }: {
  open: boolean; title?: string; actions: SheetAction[]; onClose: () => void; children?: ReactNode
}) {
  return (
    <Modal open={open} onClose={onClose}>
      <div className="pm2-sheet">
        {title && <h2 style={{ fontSize: 17, fontWeight: 600 }}>{title}</h2>}
        {children}
        <div className="pm2-actions">
          {actions.map((a) => (
            <button key={a.label} className={a.danger ? 'pm2-danger' : ''} onClick={() => { onClose(); a.onClick() }}>{a.icon}{a.label}</button>
          ))}
        </div>
      </div>
    </Modal>
  )
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label?: string }) {
  return <button role="switch" aria-checked={on} aria-label={label} className={`pm2-toggle ${on ? 'on' : ''}`} onClick={() => onChange(!on)} />
}

/** CheckCircle on the Mac. */
export function CheckDot({ on, size = 22, tint, onClick }: { on: boolean; size?: number; tint?: string; onClick?: () => void }) {
  return (
    <span role={onClick ? 'button' : undefined} onClick={onClick} className={`pm2-check ${on ? 'on' : ''}`}
      style={{ width: size, height: size, ...(on && tint ? { background: tint, borderColor: tint, color: 'var(--canvas)' } : {}), ...(tint && !on ? { borderColor: tint } : {}) }}>
      {on && <Check size={size * 0.6} strokeWidth={3} />}
    </span>
  )
}

/** Press and hold (the iPhone's context menu). Returns handlers to spread on the element. */
export function useLongPress(onLong: () => void, ms = 480) {
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const fired = useRef(false)
  const start = useRef<{ x: number; y: number } | null>(null)
  const clear = () => { if (timer.current) clearTimeout(timer.current); timer.current = null }
  return {
    onPointerDown: (e: React.PointerEvent) => {
      fired.current = false
      start.current = { x: e.clientX, y: e.clientY }
      clear()
      timer.current = setTimeout(() => { fired.current = true; if (navigator.vibrate) navigator.vibrate(10); onLong() }, ms)
    },
    onPointerMove: (e: React.PointerEvent) => {
      if (start.current && Math.hypot(e.clientX - start.current.x, e.clientY - start.current.y) > 10) clear()
    },
    onPointerUp: clear,
    onPointerCancel: clear,
    onContextMenu: (e: React.MouseEvent) => { e.preventDefault(); if (!fired.current) { clear(); fired.current = true; onLong() } },
    /** True right after a long press, so the tap that ends it can be ignored. */
    consumed: () => { const f = fired.current; fired.current = false; return f },
  }
}

/** Days from today to `d` (Calendar.dateComponents([.day], from: today, to: d.startOfDay)). */
export function daysFromToday(d: Date): number {
  const a = new Date(); const s = new Date(a.getFullYear(), a.getMonth(), a.getDate())
  const b = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  return Math.round((b.getTime() - s.getTime()) / 86_400_000)
}
