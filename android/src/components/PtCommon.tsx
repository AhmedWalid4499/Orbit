// Shared pieces of the phone sections: the large title a More section draws under the shell's back button
// (.phoneChrome on iPhone), the iPhone's switch, and ProUpsell (ProView.swift) with its "Get Pro" sheet.
import { ReactNode, useState } from 'react'
import { RefreshCw } from 'lucide-react'
import { Modal } from '@/components/ui'
import { refreshKeys } from '@/lib/ai'
import { refreshPro, isPro } from '../pro'
import { Orb } from './Orb'
import './PtCommon.css'

export function PtTitle({ children }: { children: ReactNode }) {
  return <h1 className="pt-title">{children}</h1>
}

/** A SwiftUI-style toggle. */
export function PtSwitch({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label?: string }) {
  return <button type="button" role="switch" aria-checked={on} aria-label={label} className={`pt-switch ${on ? 'on' : ''}`} onClick={() => onChange(!on)} />
}

/** "Part of Joshu Pro": the orb, what it does, and Get Pro. */
export function ProUpsell({ title, detail }: { title: string; detail: string }) {
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState('')
  const check = async () => {
    setBusy(true)
    const on = await refreshPro()
    await refreshKeys()
    setBusy(false)
    if (on || isPro()) setOpen(false)
    else setNote("Pro isn't on this account yet.")
  }
  return (
    <div className="pt-upsell">
      <Orb size={40} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="t">{title}</div>
        <div className="d">{detail}</div>
      </div>
      <button className="btn-primary" onClick={() => { setNote(''); setOpen(true) }}>Get Pro</button>
      <Modal open={open} onClose={() => setOpen(false)}>
        <div className="col" style={{ gap: 14 }}>
          <Orb size={56} />
          <h2 className="pt-sheet-title">Joshu Pro</h2>
          <div className="secondary" style={{ fontSize: 14 }}>
            Everything in Joshu, plus your AI assistant and the smart features that save you time. Pro is added to your Joshu account;
            once it is, it works here straight away.
          </div>
          {note && <div style={{ fontSize: 12, color: 'var(--orange)' }}>{note}</div>}
          <button className="btn-primary" style={{ minHeight: 44 }} disabled={busy} onClick={check}>
            <RefreshCw size={14} />{busy ? 'Checking…' : 'Check my plan'}
          </button>
        </div>
      </Modal>
    </div>
  )
}
