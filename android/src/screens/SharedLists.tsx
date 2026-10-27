// Tasks › Shared lists, like SharedListsView.swift: lists you share with other Joshu users by a six-letter code.
// Changes show up for everyone within a few seconds while the list is open.
import { useEffect, useState } from 'react'
import { Plus, UserPlus, Users, ChevronDown, ChevronUp, X, Share2, Copy, Check, AlertTriangle } from 'lucide-react'
import { Card, CheckCircle, EmptyHint, Modal } from '@/components/ui'
import {
  SharedList, useSharedLists, refresh, createList, joinList, putItem, removeItem, clearDone, leaveList, newItem,
  isAvailable, isMine, openCount, inviteText,
} from '../lib/sharedLists'

export default function SharedLists() {
  const { lists, loading, error } = useSharedLists()
  const [newTitle, setNewTitle] = useState('')
  const [joining, setJoining] = useState(false)
  const [code, setCode] = useState('')
  const [openID, setOpenID] = useState<string | null>(null)
  const available = isAvailable()

  // Keep the lists fresh while they're on screen.
  useEffect(() => {
    if (!available) return
    refresh()
    const t = setInterval(() => { if (!document.hidden) refresh() }, 8000)
    return () => clearInterval(t)
  }, [available])

  if (!available) {
    return (
      <Card>
        <div className="col" style={{ gap: 8 }}>
          <div className="row" style={{ gap: 8, fontSize: 15, fontWeight: 600 }}><Users size={16} />Sign in to share lists</div>
          <div className="secondary" style={{ fontSize: 13 }}>
            Shared lists go through your Joshu account. Sign in under Settings › Account, then make a list and send its code to anyone with Joshu.
          </div>
        </div>
      </Card>
    )
  }

  const create = async () => {
    const t = newTitle
    setNewTitle('')
    const l = await createList(t)
    if (l) setOpenID(l.id)
  }
  const join = async () => {
    if (await joinList(code)) { setCode(''); setJoining(false) }
  }

  return (
    <div className="col" style={{ gap: 14 }}>
      <div className="row" style={{ gap: 10 }}>
        <div className="row" style={{ flex: 1, minWidth: 0, gap: 8, background: 'var(--card)', borderRadius: 12, padding: '11px 14px' }}>
          <Plus size={16} className="muted" style={{ flex: 'none' }} />
          <input className="plain" style={{ fontSize: 15 }} value={newTitle} placeholder="New shared list: Groceries, Dahab trip…"
            enterKeyHint="done" onChange={(e) => setNewTitle(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') create() }} />
        </div>
        <button className="btn-soft" onClick={() => setJoining((j) => !j)}><UserPlus size={14} />Join</button>
      </div>
      {joining && (
        <div className="row" style={{ gap: 10 }}>
          <input className="field" autoFocus value={code} placeholder="Code from the invite" autoCapitalize="characters" autoCorrect="off" spellCheck={false}
            enterKeyHint="go" style={{ flex: 1, minWidth: 0, fontFamily: 'ui-monospace, monospace', fontWeight: 600, fontSize: 15, padding: '11px 14px' }}
            onChange={(e) => setCode(e.target.value.toUpperCase())} onKeyDown={(e) => { if (e.key === 'Enter') join() }} />
          <button className="btn-primary" disabled={code.trim().length < 4} style={{ opacity: code.trim().length < 4 ? 0.5 : 1 }} onClick={join}>Join list</button>
        </div>
      )}
      {error && (
        <div className="row" style={{ gap: 6, fontSize: 12, color: 'var(--orange)', alignItems: 'flex-start' }}>
          <AlertTriangle size={13} style={{ flex: 'none', marginTop: 1 }} /><span>{error}</span>
        </div>
      )}
      {!lists.length && !loading && <EmptyHint icon={<Users size={14} />} text="No shared lists yet. Make one above, or join with a code." />}
      {lists.map((list) => {
        // The first list starts open.
        const open = openID === list.id || (openID === null && list.id === lists[0]?.id)
        return <SharedListCard key={list.id} list={list} expanded={open} toggle={() => setOpenID(open ? '' : list.id)} />
      })}
    </div>
  )
}

function SharedListCard({ list, expanded, toggle }: { list: SharedList; expanded: boolean; toggle: () => void }) {
  const [draft, setDraft] = useState('')
  const [confirmLeave, setConfirmLeave] = useState(false)
  const [copied, setCopied] = useState(false)
  const mine = isMine(list)
  const people = list.memberCount === 1 ? 'person' : 'people'

  const add = () => {
    const t = draft.trim()
    if (!t) return
    setDraft('')
    putItem(newItem(t), list)
  }
  const copy = async (text: string) => {
    try { await navigator.clipboard.writeText(text) } catch { return false }
    setCopied(true)
    setTimeout(() => setCopied(false), 1800)
    return true
  }
  const invite = async () => {
    const text = inviteText(list)
    if (typeof navigator.share === 'function') {
      try { await navigator.share({ text }); return } catch (e) { if ((e as Error).name === 'AbortError') return }
    }
    await copy(text) // no share sheet in this WebView: the invite goes to the clipboard instead
  }

  return (
    <Card padding={16}>
      <div className="col" style={{ gap: 10 }}>
        <button className="row" style={{ gap: 10, width: '100%', textAlign: 'left' }} onClick={toggle}>
          <span style={{ width: 30, height: 30, borderRadius: '50%', background: 'var(--mint)', color: 'var(--sticker-ink)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
            <Users size={13} strokeWidth={2.5} />
          </span>
          <span style={{ flex: 1, minWidth: 0 }}>
            <div className="clamp1" style={{ fontSize: 16, fontWeight: 600 }}>{list.title}</div>
            <div className="secondary" style={{ fontSize: 12 }}>{openCount(list)} to do · {list.memberCount} {people}</div>
          </span>
          <span className="muted">{expanded ? <ChevronUp size={16} /> : <ChevronDown size={16} />}</span>
        </button>

        {expanded && (
          <>
            {list.items.map((item) => (
              <div key={item.id} className="row" style={{ gap: 10, minHeight: 30 }}>
                <CheckCircle on={item.done} size={18} onClick={() => putItem({ ...item, done: !item.done }, list)} />
                <span style={{ flex: 1, minWidth: 0, fontSize: 14, color: item.done ? 'var(--ink3)' : 'var(--ink)', textDecoration: item.done ? 'line-through' : 'none' }}>{item.text}</span>
                {item.by && <span className="muted" style={{ fontSize: 11, flex: 'none' }}>{item.by}</span>}
                <button className="muted" aria-label="Remove" style={{ padding: 6, flex: 'none' }} onClick={() => removeItem(item, list)}><X size={12} strokeWidth={2.5} /></button>
              </div>
            ))}
            <div className="row" style={{ gap: 8, background: 'var(--canvas)', borderRadius: 10, padding: '9px 12px' }}>
              <Plus size={14} className="muted" style={{ flex: 'none' }} />
              <input className="plain" style={{ fontSize: 14 }} value={draft} placeholder="Add an item" enterKeyHint="done"
                onChange={(e) => setDraft(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') add() }} />
            </div>
            <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
              <button className="btn-soft" style={{ background: 'var(--canvas)' }} onClick={invite}><Share2 size={13} />Invite · {list.code}</button>
              <button className="btn-soft" style={{ background: 'var(--canvas)' }} aria-label="Copy the code" onClick={() => copy(list.code)}>
                {copied ? <Check size={13} /> : <Copy size={13} />}
              </button>
              <span className="spacer" />
              {list.items.some((i) => i.done) && <button className="btn-soft" style={{ background: 'var(--canvas)' }} onClick={() => clearDone(list)}>Clear done</button>}
              <button className="btn-soft" style={{ background: 'var(--canvas)', color: 'var(--critical)' }} onClick={() => setConfirmLeave(true)}>{mine ? 'Delete' : 'Leave'}</button>
            </div>
          </>
        )}
      </div>
      <Modal open={confirmLeave} onClose={() => setConfirmLeave(false)}>
        <div className="col" style={{ gap: 16 }}>
          <div style={{ fontSize: 17, fontWeight: 600, paddingRight: 36 }}>{mine ? `Delete “${list.title}” for everyone?` : `Leave “${list.title}”?`}</div>
          <button className="btn-primary" style={{ background: 'var(--critical)', color: '#fff' }}
            onClick={() => { setConfirmLeave(false); leaveList(list) }}>{mine ? 'Delete list' : 'Leave list'}</button>
          <button className="btn-soft" style={{ justifyContent: 'center' }} onClick={() => setConfirmLeave(false)}>Cancel</button>
        </div>
      </Modal>
    </Card>
  )
}
