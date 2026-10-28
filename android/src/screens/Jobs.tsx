// LinkedIn on the phone (LinkedInView in LinkedIn.swift, as the iPhone shows it): your LinkedIn profile link at the top,
// then every job from LinkedIn's job-alert emails, by the day the alert came. Reading the alerts is part of Joshu Pro.
import { ReactNode, useEffect, useState } from 'react'
import { RefreshCw, ArrowUpRight, Briefcase, Mail, Building2, Clock, MapPin, Plus, CheckCircle2, BadgeCheck } from 'lucide-react'
import { useKeys, useAssistantName } from '@/lib/ai'
import { store } from '@/lib/store'
import { Task } from '@/lib/models'
import { iso, addDays, startOfDay, relativeTime, fmtDay } from '@/lib/dates'
import { useProfileCard, saveProfileCard, newLinkID, filledLinks } from '@/lib/profileCard'
import { Alert, Job, loadJobs, refreshJobs } from '../lib/linkedin'
import { PtTitle, ProUpsell } from '../components/PtCommon'

const DEMO = new URLSearchParams(location.search).has('demo')
const JOBS_URL = 'https://www.linkedin.com/jobs/'
const open = (url: string, fallback = JOBS_URL) => window.orbit.openExternal(url || fallback)
const initials = (s: string) => s.split(' ').slice(0, 2).map((w) => w[0] ?? '').join('').toUpperCase()

/** LinkedInStore.demo's job alert, for the preview. */
const DEMO_ALERTS: Alert[] = [{
  id: 'd4', account: '', date: new Date(Date.now() - 20 * 3600_000).toISOString(), title: '6 new Project Manager jobs in Cairo', url: '',
  jobs: [
    { title: 'Senior Delivery Manager', company: 'Instabug', location: 'Cairo (Hybrid)', url: '' },
    { title: 'Technical Project Manager', company: 'Valeo', location: 'Giza', url: '' },
    { title: 'Program Manager, Payments', company: 'Paymob', location: 'Cairo', url: '' },
    { title: 'IT Project Manager', company: 'Orange Business', location: 'New Cairo', url: '' },
  ],
}]

export default function Jobs() {
  const keys = useKeys()
  const assistant = useAssistantName()
  const [state, setState] = useState(loadJobs)
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState('')
  const [selected, setSelected] = useState<string | null>(null)
  const [saved, setSaved] = useState('')
  const alerts = DEMO ? DEMO_ALERTS : [...state.items].sort((a, b) => b.date.localeCompare(a.date))

  const refresh = async () => {
    if (loading || !keys.gmail.length || !keys.anthropic) return
    setLoading(true)
    try { setState(await refreshJobs(keys.gmail, keys.anthropic, setStatus)) } catch (e: any) { setStatus(e?.message ?? String(e)) }
    setLoading(false)
  }

  // Check at most hourly when the screen opens (refreshIfDue on the Mac and iPhone).
  const accounts = keys.gmail.join(',')
  useEffect(() => { if (accounts && keys.anthropic && Date.now() - state.lastSync > 3600_000) refresh() }, [accounts, keys.anthropic]) // eslint-disable-line react-hooks/exhaustive-deps

  const saveJob = (job: Job) => {
    // Every field the Mac encodes for a task.
    store.create<Task & { remindAt: string | null; place: { name: string; lat: number; lon: number; onLeave: boolean } }>('task', {
      title: `Apply: ${job.title}${job.company ? ` at ${job.company}` : ''}`, notes: job.url, area: 'work',
      due: iso(addDays(startOfDay(new Date()), 2)), priority: 2, isDone: false, completedAt: null, createdAt: iso(new Date()), repeat: 'none',
      remindAt: null, place: { name: '', lat: 0, lon: 0, onLeave: false },
    })
    setSaved(`Saved “${job.title}” to Tasks, due in 2 days.`)
  }

  const week = addDays(new Date(), -7).toISOString()
  const companies = new Set(alerts.flatMap((a) => a.jobs.map((j) => j.company)).filter(Boolean))
  const shown = selected ? alerts.filter((a) => a.id === selected) : alerts

  return (
    <div className="page pt-page" style={{ gap: 20, paddingBottom: 32 }}>
      <PtTitle>LinkedIn</PtTitle>
      <div className="row" style={{ gap: 12, justifyContent: 'flex-end', marginTop: -6 }}>
        {loading && <span className="muted" style={{ fontSize: 11 }}>Checking…</span>}
        <button className="btn-soft" style={{ width: 40, padding: 0, justifyContent: 'center' }} disabled={loading} onClick={refresh}
          aria-label="Check for new job alert emails"><RefreshCw size={15} /></button>
        <button className="btn-soft" onClick={() => open(JOBS_URL)}><ArrowUpRight size={14} />LinkedIn Jobs</button>
      </div>

      <AccountCard />

      {!keys.anthropic ? (
        <ProUpsell title="LinkedIn job alerts" detail={`${assistant} reads LinkedIn's job alert emails and lists every job by the day it came. Part of Joshu Pro.`} />
      ) : keys.gmail.length === 0 && !DEMO ? (
        <div className="col" style={{ gap: 12, padding: 28, borderRadius: 24, background: 'var(--card)' }}>
          <LinkedInLogo size={56} />
          <div className="display" style={{ fontSize: 26 }}>Your job alerts, in one place</div>
          <div className="secondary" style={{ fontSize: 14 }}>
            Joshu reads the job alert emails LinkedIn sends you and lists every job, by the day the email came. Connect the Gmail account LinkedIn emails in Settings › Connections.
          </div>
          <div className="muted" style={{ fontSize: 12 }}>No alerts yet? On LinkedIn, search for a job and turn on “Set alert”.</div>
        </div>
      ) : <>
        <div className="pt-grid2">
          <Tile value={String(alerts.filter((a) => a.date > week).reduce((n, a) => n + Math.max(1, a.jobs.length), 0))} label="New jobs this week" icon={<Briefcase size={16} />} color="var(--orange)" />
          <Tile value={String(alerts.length)} label="Alert emails (60 days)" icon={<Mail size={16} />} color="var(--cyan)" />
          <Tile value={String(companies.size)} label="Companies hiring" icon={<Building2 size={16} />} color="var(--lime)" />
          <Tile value={alerts[0] ? relativeTime(new Date(alerts[0].date)) : '—'} label="Latest alert" icon={<Clock size={16} />} color="var(--pink)" />
        </div>
        {loading && status && <div className="row secondary" style={{ fontSize: 12, gap: 6 }}><RefreshCw size={12} />{status}</div>}

        {/* One tab per alert email: what it was about and the day it came. */}
        <div className="pt-chips">
          <Chip title="All jobs" sub={`${alerts.reduce((n, a) => n + a.jobs.length, 0)} jobs`} on={!selected} onClick={() => setSelected(null)} />
          {alerts.map((a) => (
            <Chip key={a.id} title={a.title} on={selected === a.id} onClick={() => setSelected(a.id)}
              sub={[fmtDay(new Date(a.date), { weekday: 'short', day: 'numeric', month: 'short' }), a.jobs.length ? `${a.jobs.length} job${a.jobs.length === 1 ? '' : 's'}` : ''].filter(Boolean).join(' · ')} />
          ))}
        </div>

        {alerts.length === 0 && <div className="secondary" style={{ fontSize: 13 }}>{loading ? 'Looking for job alerts…' : 'No LinkedIn job alerts in the last 60 days.'}</div>}
        {saved && <div className="row" style={{ fontSize: 12, gap: 6, color: 'var(--good)' }}><CheckCircle2 size={14} />{saved}</div>}
        {shown.map((a) => <AlertSection key={a.id} alert={a} onSave={saveJob} />)}
      </>}
    </div>
  )
}

/** LinkedIn's "in" on its blue tile (BrandLogo .linkedin). */
function LinkedInLogo({ size }: { size: number }) {
  return (
    <span style={{ width: size, height: size, borderRadius: size * 0.22, background: '#0A66C2', color: '#fff', flex: 'none', display: 'inline-flex',
      alignItems: 'center', justifyContent: 'center', font: `700 ${Math.round(size * 0.52)}px/1 var(--ui)`, letterSpacing: -0.5 }}>in</span>
  )
}

/** "ahmed-elbourgy-4488201b0" from anything people paste: a full link, linkedin.com/in/…, in/…, or the name alone. */
function slug(raw: string): string | null {
  let t = raw.trim()
  try { t = decodeURIComponent(t) } catch { /* keep as typed */ }
  const m = t.match(/(?:linkedin\.com)?\/?in\/([^/?#\s]+)/i)
  if (m) return m[1] || null
  return /^[\p{L}\p{N}_-]{3,100}$/u.test(t) ? t : null
}

/** Your LinkedIn, kept as the LinkedIn link on your card (so it syncs and shows on the card too): LinkedInAccountCard. */
function AccountCard() {
  const card = useProfileCard()
  const [link, setLink] = useState('')
  const [error, setError] = useState('')
  const existing = filledLinks(card).find((l) => l.kind === 'linkedin')
  const s = existing ? slug(existing.value) : null
  const url = s ? `https://www.linkedin.com/in/${s}` : null

  const connect = () => {
    const found = slug(link)
    if (!found) { setError("That doesn't look like a LinkedIn profile link. It should look like linkedin.com/in/your-name."); return }
    const value = `linkedin.com/in/${found}`
    const i = card.links.findIndex((l) => l.kind === 'linkedin')
    const links = i >= 0 ? card.links.map((l, n) => (n === i ? { ...l, value } : l)) : [{ id: newLinkID(), kind: 'linkedin' as const, value }, ...card.links]
    saveProfileCard({ ...card, links })
    setLink(''); setError('')
  }

  return (
    <div className="row" style={{ gap: 12, padding: 14, borderRadius: 18, background: 'var(--card)' }}>
      {url ? <>
        <LinkedInLogo size={44} />
        <div className="col" style={{ gap: 2, flex: 1, minWidth: 0 }}>
          <div className="clamp1" style={{ fontSize: 16, fontWeight: 600 }}>{card.name || 'Your LinkedIn'}</div>
          <div className="secondary clamp1" style={{ fontSize: 12 }}>{url.replace('https://www.linkedin.com/', 'linkedin.com/')}</div>
          <div className="row" style={{ gap: 4, fontSize: 11, color: 'var(--good)' }}><BadgeCheck size={12} />Connected</div>
        </div>
        <button className="btn-soft" style={{ background: 'var(--canvas)' }} onClick={() => open(url)}><ArrowUpRight size={14} />My profile</button>
      </> : (
        <div className="col" style={{ gap: 8, flex: 1, minWidth: 0 }}>
          <div className="row" style={{ gap: 10 }}>
            <LinkedInLogo size={36} />
            <div className="col" style={{ gap: 1 }}>
              <div style={{ fontSize: 15, fontWeight: 600 }}>Connect your LinkedIn</div>
              <div className="secondary" style={{ fontSize: 12 }}>Paste your profile link.</div>
            </div>
          </div>
          <div className="row" style={{ gap: 8 }}>
            <input className="field" style={{ flex: 1, minWidth: 0, background: 'var(--canvas)', border: '1px solid var(--line)', borderRadius: 8 }}
              placeholder="linkedin.com/in/your-name" inputMode="url" autoCapitalize="none" autoCorrect="off" spellCheck={false} value={link}
              onChange={(e) => setLink(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && link.trim()) connect() }} />
            <button className="btn-primary" style={{ minHeight: 44 }} disabled={!link.trim()} onClick={connect}>Connect</button>
          </div>
          {error && <div style={{ fontSize: 11, color: 'var(--orange)' }}>{error}</div>}
        </div>
      )}
    </div>
  )
}

function Tile({ value, label, icon, color }: { value: string; label: string; icon: ReactNode; color: string }) {
  return (
    <div className="pt-tile" style={{ background: color, flexDirection: 'row', alignItems: 'center', gap: 8 }}>
      <div style={{ minWidth: 0, flex: 1 }}>
        <div className="v">{value}</div>
        <div className="l" style={{ whiteSpace: 'normal' }}>{label}</div>
      </div>
      <span style={{ width: 34, height: 34, borderRadius: '50%', background: 'rgba(255,255,255,0.5)', flex: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>{icon}</span>
    </div>
  )
}

function Chip({ title, sub, on, onClick }: { title: string; sub: string; on: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} style={{
      flex: 'none', maxWidth: 240, textAlign: 'left', padding: '9px 14px', borderRadius: 999,
      background: on ? 'var(--inverse)' : 'var(--card)', color: on ? 'var(--canvas)' : 'var(--ink)',
    }}>
      <div className="clamp1" style={{ fontSize: 13, fontWeight: 600 }}>{title}</div>
      <div className="clamp1" style={{ fontSize: 11, opacity: 0.7 }}>{sub}</div>
    </button>
  )
}

function AlertSection({ alert, onSave }: { alert: Alert; onSave: (j: Job) => void }) {
  return (
    <div className="col" style={{ gap: 10 }}>
      <div className="col" style={{ gap: 4 }}>
        <div className="display clamp2" style={{ fontSize: 20 }}>{alert.title}</div>
        <div className="row muted" style={{ fontSize: 11, gap: 4 }}>
          <Mail size={11} />{fmtDay(new Date(alert.date), { weekday: 'long', day: 'numeric', month: 'long', hour: 'numeric', minute: '2-digit' })}
        </div>
      </div>
      {alert.jobs.length === 0 ? (
        <div><button className="btn-soft" onClick={() => open(alert.url)}><ArrowUpRight size={14} />Open this alert on LinkedIn</button></div>
      ) : alert.jobs.map((job, i) => (
        <div key={i} className="col" style={{ gap: 6, padding: 14, borderRadius: 16, background: 'var(--card)' }}>
          <div className="row" style={{ alignItems: 'flex-start', gap: 10 }}>
            <span style={{ width: 38, height: 38, borderRadius: 10, background: '#0A66C2', color: '#fff', fontSize: 12, fontWeight: 700, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
              {initials(job.company || job.title)}
            </span>
            <div className="col" style={{ gap: 2, minWidth: 0 }}>
              <div className="clamp2" style={{ fontSize: 14, fontWeight: 600 }}>{job.title}</div>
              {job.company && <div className="secondary clamp1" style={{ fontSize: 12, fontWeight: 500 }}>{job.company}</div>}
              {job.location && <div className="row muted" style={{ fontSize: 11, gap: 3 }}><MapPin size={11} /><span className="clamp1">{job.location}</span></div>}
            </div>
          </div>
          <div className="row" style={{ gap: 8, paddingTop: 2 }}>
            <button className="btn-soft" style={{ background: 'var(--canvas)' }} onClick={() => open(job.url, alert.url || JOBS_URL)}>View job</button>
            <button className="row" style={{ gap: 4, fontSize: 12, fontWeight: 600, color: 'var(--ink2)', padding: '8px 6px' }} onClick={() => onSave(job)}><Plus size={13} />Save as task</button>
          </div>
        </div>
      ))}
    </div>
  )
}
