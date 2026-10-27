// The big orb in the middle of the screen while you talk to your assistant (VoiceOrbView.swift).
import { useEffect, useState } from 'react'
import { X } from 'lucide-react'
import { Orb } from './Orb'
import { onVoice, voiceState, endConversation } from '../voice'
import { useAssistantName } from '@/lib/ai'

export default function VoiceOrb() {
  const [s, setS] = useState(voiceState())
  const name = useAssistantName()
  useEffect(() => onVoice(setS), [])
  if (s.phase === 'off') return null
  const plain = s.answer.replace(/\*\*?|`+/g, '').replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
  return (
    <div className="voice-orb">
      <button className="icon-btn voice-close" aria-label="End" onClick={endConversation}><X size={18} /></button>
      <div className={`voice-ball ${s.phase}`}><Orb size={170} busy={s.phase === 'thinking'} /></div>
      <div className="col" style={{ gap: 10, alignItems: 'center', textAlign: 'center', padding: '0 28px', minHeight: 140 }}>
        {s.phase === 'listening' && <>
          <div className="display" style={{ fontSize: s.heard ? 24 : 26, color: s.heard ? 'var(--ink)' : 'var(--ink2)' }}>{s.heard || 'Listening…'}</div>
          {!s.heard && <div className="muted" style={{ fontSize: 14 }}>Ask {name} anything</div>}
        </>}
        {s.phase === 'thinking' && <>
          {s.question && <div className="secondary clamp2" style={{ fontSize: 15 }}>“{s.question}”</div>}
          <div className="display" style={{ fontSize: 24 }}>Thinking…</div>
        </>}
        {s.phase === 'speaking' && <div style={{ fontSize: 18, fontWeight: 500, lineHeight: 1.4, display: '-webkit-box', WebkitLineClamp: 6, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{plain}</div>}
        {s.error && <div style={{ fontSize: 12, color: 'var(--orange)' }}>{s.error}</div>}
        <div className="muted" style={{ fontSize: 12, marginTop: 8 }}>Say “stop” or “bye” when you're done</div>
      </div>
    </div>
  )
}
