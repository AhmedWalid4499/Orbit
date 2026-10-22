// Launch splash: "orbit" with the logo's lime dot orbiting it on a tilted ellipse (like the Mac's).
import { useEffect, useLayoutEffect, useRef, useState } from 'react'

const LAP = 1100 // ms per orbit
const SHOW = 1700 // ms before fading out
const FADE = 350
const TILT = (-10 * Math.PI) / 180

export default function Splash({ onDone }: { onDone: () => void }) {
  const reduced = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches
  const word = useRef<HTMLDivElement>(null)
  const [size, setSize] = useState({ w: 240, h: 96 })
  const [theta, setTheta] = useState(Math.PI / 2) // front, below the word
  const [out, setOut] = useState(false)

  useLayoutEffect(() => {
    const r = word.current?.getBoundingClientRect()
    if (r) setSize({ w: r.width, h: r.height })
  }, [])

  useEffect(() => {
    let raf = 0
    const t0 = performance.now()
    if (!reduced) {
      const step = (now: number) => { setTheta(Math.PI / 2 + ((now - t0) / LAP) * Math.PI * 2); raf = requestAnimationFrame(step) }
      raf = requestAnimationFrame(step)
    }
    const fade = setTimeout(() => setOut(true), reduced ? 600 : SHOW)
    const done = setTimeout(onDone, (reduced ? 600 : SHOW) + FADE)
    return () => { cancelAnimationFrame(raf); clearTimeout(fade); clearTimeout(done) }
  }, [])

  const rx = size.w * 0.62, ry = size.h * 0.3
  const ex = rx * Math.cos(theta), ey = ry * Math.sin(theta)
  const x = ex * Math.cos(TILT) - ey * Math.sin(TILT)
  const y = ex * Math.sin(TILT) + ey * Math.cos(TILT)
  const far = Math.sin(theta) < 0 // top half of the ellipse is the far side: the dot goes behind the word
  const dot = 18 * (far ? 0.8 : 1)

  return (
    <div className={`splash ${out ? 'out' : ''}`}>
      <div style={{ position: 'relative' }}>
        <svg width={rx * 2 + 40} height={rx * 2 + 40} style={{ position: 'absolute', left: '50%', top: '50%', transform: 'translate(-50%, -50%)', overflow: 'visible', pointerEvents: 'none' }}>
          <ellipse cx={rx + 20} cy={rx + 20} rx={rx} ry={ry} fill="none" stroke="var(--ink)" strokeOpacity={0.12} strokeWidth={1.5}
            transform={`rotate(-10 ${rx + 20} ${rx + 20})`} />
        </svg>
        <div ref={word} style={{ position: 'relative', zIndex: 2, font: '900 96px/1 var(--ui)', letterSpacing: -4, color: 'var(--ink)', padding: '0 4px' }}>orbit</div>
        <span style={{
          position: 'absolute', left: '50%', top: '50%', width: dot, height: dot, borderRadius: '50%', background: 'var(--lime)',
          transform: `translate(${x - dot / 2}px, ${y - dot / 2}px)`, zIndex: far ? 1 : 3, opacity: far ? 0.6 : 1,
        }} />
      </div>
    </div>
  )
}
