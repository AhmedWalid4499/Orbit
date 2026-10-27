// The assistant's orb, as on the Mac and iPhone (AssistantAvatar / OrbDot in AssistantPanel.swift):
// a colour wheel with a soft highlight, plus a white spark on the full-size orb. It turns only while busy.
import { CSSProperties } from 'react'

export const ORB_WHEEL = 'conic-gradient(from 120deg, #C6F432, #3DDC97, #22D3EE, #8B7CF6, #F472B6, #C6F432)'
const HIGHLIGHT = 'radial-gradient(circle at 32% 26%, rgba(255,255,255,0.65), rgba(255,255,255,0) 62%)'

export function Orb({ size = 32, busy = false, spark = true, style }: { size?: number; busy?: boolean; spark?: boolean; style?: CSSProperties }) {
  return (
    <span className="orb" style={{ width: size, height: size, ...style }} aria-hidden>
      <span className={`orb-wheel ${busy ? 'busy' : ''}`} style={{ background: ORB_WHEEL }} />
      <span className="orb-shine" style={{ background: HIGHLIGHT }} />
      {spark && (
        <svg viewBox="0 0 24 24" width={size * 0.46} height={size * 0.46} className="orb-spark">
          <path d="M12 2c.6 4.9 2.6 7.6 8 10-5.4 2.4-7.4 5.1-8 10-.6-4.9-2.6-7.6-8-10 5.4-2.4 7.4-5.1 8-10z" fill="#fff" />
        </svg>
      )}
    </span>
  )
}
