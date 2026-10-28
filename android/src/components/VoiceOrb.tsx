// Voice mode (VoiceOrbView.swift): the assistant's orb in the middle of the screen. Rings ripple out and it swells
// with your voice while it listens, a comet circles it while it thinks, and a halo breathes with its words while it
// answers. Tap the orb to interrupt; say "stop" or tap ✕ to end.
import { useEffect, useState } from 'react'
import { X } from 'lucide-react'
import { Orb } from './Orb'
import { onVoice, voiceState, endConversation, interrupt, plain } from '../voice'
import { useSession } from '../assistantSession'
import { useAssistantName } from '@/lib/ai'
import '../screens/Assistant.css'

export default function VoiceOrb() {
  const [v, setV] = useState(voiceState())
  const session = useSession()
  const name = useAssistantName()
  useEffect(() => onVoice(setV), [])
  if (!v.inConversation) return null

  const phase = v.speaking ? 'speaking' : session.busy ? 'thinking' : 'listening'
  const glow = phase === 'thinking' ? 'var(--purple)' : phase === 'speaking' ? 'var(--cyan)' : 'var(--lime)'
  const lastAnswer = [...session.convo.items].reverse().find((i) => i.role === 'assistant')?.text ?? ''
  const answer = plain(session.revealed || lastAnswer)
  const size = 200
  const error = session.error || v.error

  return (
    <div className="pa-voice" style={{ ['--pa-glow' as string]: glow }}>
      <div className="pa-voice-glow">
        <i style={{ width: 340, height: 340, left: -120, top: '8%', background: 'var(--lime)' }} />
        <i style={{ width: 300, height: 300, right: -140, top: '30%', background: 'var(--mint)' }} />
        <i style={{ width: 280, height: 280, left: '20%', bottom: '-6%', background: 'var(--cyan)', opacity: 0.2 }} />
      </div>
      <div className="pa-voice-stage">
        <button className={`pa-orb-wrap ${phase}`} aria-label={phase === 'speaking' ? 'Stop talking' : name} onClick={interrupt}>
          {phase === 'listening' && <><span className="pa-ring" /><span className="pa-ring" /><span className="pa-ring" /></>}
          {phase === 'thinking' && <span className="pa-comet" />}
          {phase === 'speaking' && <span className="pa-halo" />}
          <Orb size={size} busy={phase !== 'listening'}
            style={{ transform: phase === 'listening' ? `scale(${1 + v.level * 0.22})` : undefined, boxShadow: `0 0 60px color-mix(in srgb, ${glow} 45%, transparent), inset 0 0 0 1px rgba(255,255,255,0.45)` }} />
        </button>
        <div className="pa-caption">
          {phase === 'listening' && <>
            <div className={`big ${v.heard ? '' : 'dim'}`} style={{ fontSize: v.heard ? 24 : 26 }}>{v.heard || 'Listening…'}</div>
            {!v.heard && <div className="sub">Ask {name} anything</div>}
          </>}
          {phase === 'thinking' && <>
            {v.question && <div className="q">“{v.question}”</div>}
            <div className="big" style={{ fontSize: 24 }}>Thinking…</div>
          </>}
          {phase === 'speaking' && <div className="ans">{answer}</div>}
          {error && <div className="err">{error}</div>}
        </div>
      </div>
      <div className="pa-voice-end">
        <button aria-label="End conversation" onClick={endConversation}><X size={20} strokeWidth={2.6} /></button>
        <span>{phase === 'speaking' ? 'Tap the orb to interrupt · say “stop” to end' : 'Say “stop” or tap ✕ to end'}</span>
      </div>
    </div>
  )
}
