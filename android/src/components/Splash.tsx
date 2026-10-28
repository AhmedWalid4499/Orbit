// Launch splash, as on the Mac and iPhone (SplashView.swift, same sizes): the orb drops in before "joshu", hops over the word and
// lands at the end like a full stop, with a soft three-note chime. Then the app fades in.
import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { Orb } from './Orb'

const LANDING = 1.25
const LENGTH = 1.55
const ORB = 34

/** The orb's offset from its resting place after the word, its squash and spin, at time t (seconds). */
function pose(t: number, wordWidth: number) {
  const startX = -(wordWidth + ORB * 0.9)
  const ease = (v: number) => v * v * (3 - 2 * v)
  if (t < 0.32) { const p = Math.max(t, 0) / 0.32; return { x: startX, y: -170 * (1 - p * p), sx: 1, sy: 1, spin: 0 } }
  if (t < 0.42) { const k = Math.sin(((t - 0.32) / 0.1) * Math.PI); return { x: startX, y: 0, sx: 1 + 0.22 * k, sy: 1 - 0.25 * k, spin: 0 } }
  if (t < LANDING) {
    const p = (t - 0.42) / (LANDING - 0.42), s = 0.12 * Math.sin(p * Math.PI)
    return { x: startX * (1 - ease(p)), y: -160 * 4 * p * (1 - p), sx: 1 - s, sy: 1 + s, spin: 360 * ease(p) }
  }
  if (t < LANDING + 0.12) { const k = Math.sin(((t - LANDING) / 0.12) * Math.PI); return { x: 0, y: 0, sx: 1 + 0.28 * k, sy: 1 - 0.3 * k, spin: 360 } }
  if (t < LENGTH) { const p = (t - LANDING - 0.12) / (LENGTH - LANDING - 0.12); return { x: 0, y: -16 * 4 * p * (1 - p), sx: 1, sy: 1, spin: 360 } }
  return { x: 0, y: 0, sx: 1, sy: 1, spin: 360 }
}

/** G5, C6, E6 bell tones, like the Mac's LaunchChime. */
function chime(): void {
  try {
    const ctx = new AudioContext()
    for (const [freq, start] of [[783.99, 0], [1046.5, 0.09], [1318.5, 0.18]]) {
      for (const [mult, level] of [[1, 0.1], [2, 0.025]]) {
        const osc = ctx.createOscillator(), gain = ctx.createGain()
        osc.frequency.value = freq * mult
        const t0 = ctx.currentTime + start
        gain.gain.setValueAtTime(0, t0)
        gain.gain.linearRampToValueAtTime(level, t0 + 0.006)
        gain.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.9)
        osc.connect(gain).connect(ctx.destination)
        osc.start(t0); osc.stop(t0 + 0.95)
      }
    }
    setTimeout(() => ctx.close(), 1500)
  } catch { /* no audio: fine */ }
}

export default function Splash({ onDone }: { onDone: () => void }) {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
  const word = useRef<HTMLSpanElement>(null)
  const [width, setWidth] = useState(200)
  const [t, setT] = useState(reduced ? LENGTH : 0)
  const [out, setOut] = useState(false)

  useLayoutEffect(() => { if (word.current) setWidth(word.current.getBoundingClientRect().width) }, [])
  useEffect(() => {
    let raf = 0
    const t0 = performance.now()
    if (!reduced) {
      const step = (now: number) => { const s = (now - t0) / 1000; setT(s); if (s < LENGTH) raf = requestAnimationFrame(step) }
      raf = requestAnimationFrame(step)
    }
    const ring = setTimeout(() => { if (localStorage.getItem('launchSound') !== 'false') chime() }, reduced ? 0 : LANDING * 1000)
    const hold = reduced ? 600 : (LENGTH + 0.45) * 1000
    const fade = setTimeout(() => setOut(true), hold)
    const done = setTimeout(onDone, hold + 350)
    return () => { cancelAnimationFrame(raf); clearTimeout(ring); clearTimeout(fade); clearTimeout(done) }
  }, [])

  const p = pose(t, width)
  return (
    <div className={`splash ${out ? 'out' : ''}`}>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 4, transform: `translateX(${-ORB / 2}px)` }}>
        <span ref={word} style={{ font: '900 min(104px, 25vw)/0.9 var(--ui)', letterSpacing: -3, color: 'var(--ink)' }}>joshu</span>
        <span style={{
          display: 'inline-flex', marginBottom: 2, transformOrigin: '50% 100%',
          transform: `translate(${p.x}px, ${p.y}px) scale(${p.sx}, ${p.sy}) rotate(${p.spin}deg)`,
          filter: `drop-shadow(0 3px ${p.y < -20 ? 14 : 6}px rgba(230, 255, 31, 0.5))`,
        }}><Orb size={ORB} /></span>
      </div>
    </div>
  )
}
