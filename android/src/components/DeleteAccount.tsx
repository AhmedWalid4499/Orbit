// Settings › Account › Delete Account (the Mac's CloudSync.deleteAccount): the server's delete_my_account RPC
// (supabase/pro.sql) removes the sign-in and, through "on delete cascade", everything synced for it. Then this
// phone's copy goes too (the same things signing out without keeping a copy removes) and you're signed out,
// back on the Welcome page.
import { useState } from 'react'
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

/** A row in Settings › Account & sync; asks first, in place. */
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
    return <button className="ps-cell" onClick={() => setConfirming(true)}><span className="ps-cell-title ps-danger" style={{ fontWeight: 400 }}>Delete Account…</span></button>
  }

  return (
    <div className="ps-cell col">
      <strong style={{ fontSize: 15 }}>Delete your Joshu account?</strong>
      <span className="ps-cell-sub">
        This deletes your account and everything synced to it, on all your devices, and removes it from this phone with your chats and
        connected accounts. A Pro subscription bought on iPhone is cancelled in your Apple ID settings, not here.
      </span>
      {error && <span className="ps-bad" style={{ fontSize: 13 }}>{error}</span>}
      <button className="ps-primary ps-wide" style={{ background: 'var(--critical)', color: '#fff' }} disabled={busy} onClick={remove}>
        {busy ? 'Deleting…' : 'Delete Account'}
      </button>
      <button className="ps-soft ps-wide" disabled={busy} onClick={() => { setConfirming(false); setError('') }}>Cancel</button>
    </div>
  )
}
