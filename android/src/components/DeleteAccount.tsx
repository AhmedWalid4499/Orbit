// Settings › Account › Delete Account (the Mac's CloudSync.deleteAccount): the server's delete_my_account RPC
// (supabase/pro.sql) removes the sign-in and, through "on delete cascade", everything synced for it. Then this
// phone's copy goes too (the same things signing out without keeping a copy removes) and you're signed out,
// back on the Welcome page.
import { useState } from 'react'
import { Trash2 } from 'lucide-react'
import * as cloud from '@/lib/cloud'
import { store, LOCAL_CACHE } from '@/lib/store'
import { clearSecrets } from '../secrets'
import { setUsesJoshuWithoutAccount } from '../screens/Welcome'

/** Everything Joshu keeps on this phone for an account (as SignOutChoice in Settings), plus the plan. */
function clearPhone(userID: string): void {
  for (const k of Object.keys(localStorage)) {
    if (k === `orbit.cache.${userID}` || k === LOCAL_CACHE || k.startsWith('orbit.ask.') || k.startsWith('orbit.github') || k.startsWith('orbit.linkedin')
      || k === 'orbit.gcal' || k.startsWith('bankSMS.') || k === 'orbit.profilePhoto' || k === 'pro.until') localStorage.removeItem(k)
  }
}

export default function DeleteAccount({ onDone }: { onDone?: () => void }) {
  const [confirming, setConfirming] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const remove = async () => {
    const session = cloud.getSession()
    if (!session) return
    setBusy(true); setError('')
    try {
      await cloud.rest('rpc/delete_my_account', { method: 'POST', body: {} })
    } catch (e: any) {
      setError(e?.message ?? String(e))
      setBusy(false)
      return
    }
    store.stop() // first, so a pending save can't write the cache back
    clearPhone(session.userID)
    await clearSecrets()
    setUsesJoshuWithoutAccount(false)
    cloud.signOut()
    setBusy(false)
    setConfirming(false)
    onDone?.()
  }

  if (!confirming) {
    return (
      <button className="btn-soft" style={{ color: 'var(--critical)', alignSelf: 'flex-start' }} onClick={() => setConfirming(true)}>
        <Trash2 size={13} /> Delete account…
      </button>
    )
  }

  return (
    <div className="card col" style={{ gap: 10, background: 'var(--blush)' }}>
      <strong>Delete your Joshu account?</strong>
      <span className="secondary" style={{ fontSize: 13 }}>
        This deletes your account and everything synced to it, on all your devices, and removes it from this phone with your chats and
        connected accounts. A Pro subscription is cancelled in your Apple ID settings, not here.
      </span>
      {error && <span style={{ fontSize: 13, color: 'var(--critical)' }}>{error}</span>}
      <button className="btn-primary" style={{ background: 'var(--critical)', color: '#fff' }} disabled={busy} onClick={remove}>
        {busy ? 'Deleting…' : 'Delete account'}
      </button>
      <button className="link" disabled={busy} onClick={() => { setConfirming(false); setError('') }}>Cancel</button>
    </div>
  )
}
