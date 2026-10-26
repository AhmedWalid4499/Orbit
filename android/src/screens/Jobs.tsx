// LinkedIn jobs (the Mac's LinkedInView): every job from LinkedIn's job-alert emails, by the day the alert came.
import { useEffect, useState } from 'react'
import { RefreshCw, ArrowUpRight, Briefcase, Mail, Building2, Clock, MapPin, Plus, CheckCircle2 } from 'lucide-react'
import { useKeys } from '@/lib/ai'
import { store } from '@/lib/store'
import { Task } from '@/lib/models'
import { iso, addDays, startOfDay, relativeTime, fmtDay } from '@/lib/dates'
import { Card } from '@/components/ui'
import { Alert, Job, loadJobs, refreshJobs } from '../lib/linkedin'

const JOBS_URL = 'https://www.linkedin.com/jobs/'
const open = (url: string, fallback = JOBS_URL) => window.orbit.openExternal(url || fallback)
const initials = (s: string) => s.split(' ').slice(0, 2).map((w) => w[0] ?? '').join('').toUpperCase()

export default function Jobs() {
  const keys = useKeys()
  const [state, setState] = useState(loadJobs)
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState('')
  const [selected, setSelected] = useState<string | null>(null)
  const [saved, setSaved] = useState('')
  const alerts = [...state.items].sort((a, b) => b.date.localeCompare(a.date))

  const refresh = async () => {
    if (loading || !keys.gmail.length) return
    setLoading(true)
    try { setState(await refreshJobs(keys.gmail, keys.anthropic, setStatus)) } catch (e: any) { setStatus(e?.message ?? String(e)) }
    setLoading(false)
  }

  // Check at most hourly when the screen opens (refreshIfDue on the Mac).
  const accounts = keys.gmail.join(',')
  useEffect(() => { if (accounts && Date.now() - state.lastSync > 3600_000) refresh() }, [accounts]) // eslint-disable-line react-hooks/exhaustive-deps

  const saveJob = (job: Job) => {
    store.create<Task>('task', {
      title: `Apply: ${job.title}${job.company ? ` at ${job.company}` : ''}`, notes: job.url, area: 'work',
      due: iso(addDays(startOfDay(new Date()), 2)), priority: 2, isDone: false, completedAt: null, createdAt: iso(new Date()), repeat: 'none',
    })
    setSaved(`Saved “${job.title}” to Tasks, due in 2 days.`)
  }

  const week = addDays(new Date(), -7).toISOString()
  const companies = new Set(alerts.flatMap((a) => a.jobs.map((j) => j.company)).filter(Boolean))
  const shown = selected ? alerts.filter((a) => a.id === selected) : alerts

  return (
    <div className="page">
      <div className="col" style={{ gap: 18, paddingBottom: 32 }}>
        <div className="row">
          <h1 className="page-title">Jobs</h1>
          <span className="spacer" />
          {keys.gmail.length > 0 && <button className="icon-btn" disabled={loading} onClick={refresh} aria-label="Check for new job alerts"><RefreshCw size={16} /></button>}
          <button className="btn-soft" style={{ height: 40 }} onClick={() => open(JOBS_URL)}><ArrowUpRight size={14} />LinkedIn</button>
        </div>

        {keys.gmail.length === 0 ? (
          <Card padding={22}>
            <div className="display" style={{ fontSize: 24, marginBottom: 8 }}>Your job alerts, in one place</div>
            <div className="secondary" style={{ fontSize: 14 }}>
              Joshu reads the job alert emails LinkedIn sends you and lists every job, by the day the email came. Connect the Gmail account LinkedIn emails in Settings › Connections.
            </div>
            <div className="muted" style={{ fontSize: 12, marginTop: 10 }}>No alerts yet? On LinkedIn, search for a job and turn on “Set alert”.</div>
          </Card>
        ) : <>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <Tile value={String(alerts.filter((a) => a.date > week).reduce((n, a) => n + Math.max(1, a.jobs.length), 0))} label="New jobs this week" icon={<Briefcase size={14} />} color="var(--orange)" />
            <Tile value={String(alerts.length)} label="Alert emails (60 days)" icon={<Mail size={14} />} color="var(--cyan)" />
            <Tile value={String(companies.size)} label="Companies hiring" icon={<Building2 size={14} />} color="var(--lime)" />
            <Tile value={alerts[0] ? relativeTime(new Date(alerts[0].date)) : '—'} label="Latest alert" icon={<Clock size={14} />} color="var(--pink)" />
          </div>
          {!keys.anthropic && <div className="muted" style={{ fontSize: 12 }}>Add a Claude key in Settings for more accurate job lists.</div>}
          {loading && status && <div className="row secondary" style={{ fontSize: 12, gap: 6 }}><RefreshCw size={12} />{status}</div>}

          {/* One chip per alert email. */}
          {alerts.length > 0 && (
            <div className="row" style={{ gap: 8, overflowX: 'auto', scrollbarWidth: 'none', margin: '0 -16px', padding: '0 16px' }}>
              <Chip title="All jobs" sub={`${alerts.reduce((n, a) => n + a.jobs.length, 0)} jobs`} on={!selected} onClick={() => setSelected(null)} />
              {alerts.map((a) => (
                <Chip key={a.id} title={a.title} on={selected === a.id} onClick={() => setSelected(a.id)}
                  sub={[fmtDay(new Date(a.date), { weekday: 'short', day: 'numeric', month: 'short' }), a.jobs.length ? `${a.jobs.length} job${a.jobs.length === 1 ? '' : 's'}` : ''].filter(Boolean).join(' · ')} />
              ))}
            </div>
          )}

          {alerts.length === 0 && <div className="secondary" style={{ fontSize: 13 }}>{loading ? 'Looking for job alerts…' : 'No LinkedIn job alerts in the last 60 days.'}</div>}
          {saved && <div className="row" style={{ fontSize: 12, gap: 6, color: 'var(--good)' }}><CheckCircle2 size={14} />{saved}</div>}
          {shown.map((a) => <AlertSection key={a.id} alert={a} onSave={saveJob} />)}
        </>}
      </div>
    </div>
  )
}

function Tile({ value, label, icon, color }: { value: string; label: string; icon: React.ReactNode; color: string }) {
  return (
    <div className="row" style={{ background: color, color: 'var(--sticker-ink)', borderRadius: 18, padding: 14, alignItems: 'flex-start' }}>
      <div style={{ minWidth: 0 }}>
        <div className="display clamp1" style={{ fontSize: 22 }}>{value}</div>
        <div style={{ fontSize: 11, fontWeight: 600, opacity: 0.8 }}>{label}</div>
      </div>
      <span className="spacer" />
      <span className="tile-icon">{icon}</span>
    </div>
  )
}

function Chip({ title, sub, on, onClick }: { title: string; sub: string; on: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} style={{
      flex: 'none', maxWidth: 220, minHeight: 44, textAlign: 'left', padding: '8px 14px', borderRadius: 999,
      background: on ? 'var(--inverse)' : 'var(--card)', color: on ? 'var(--on-inverse)' : 'var(--ink)',
    }}>
      <div className="clamp1" style={{ fontSize: 13, fontWeight: 600 }}>{title}</div>
      <div className="clamp1" style={{ fontSize: 11, opacity: 0.7 }}>{sub}</div>
    </button>
  )
}

function AlertSection({ alert, onSave }: { alert: Alert; onSave: (j: Job) => void }) {
  return (
    <div className="col" style={{ gap: 10 }}>
      <div>
        <div className="display clamp2" style={{ fontSize: 19 }}>{alert.title}</div>
        <div className="row muted" style={{ fontSize: 11, gap: 4 }}>
          <Mail size={11} />{fmtDay(new Date(alert.date), { weekday: 'long', day: 'numeric', month: 'long', hour: 'numeric', minute: '2-digit' })}
        </div>
      </div>
      {alert.jobs.length === 0 ? (
        <div><button className="btn-soft" style={{ height: 40 }} onClick={() => open(alert.url)}><ArrowUpRight size={14} />Open this alert on LinkedIn</button></div>
      ) : alert.jobs.map((job, i) => (
        <Card key={i} padding={14}>
          <div className="row" style={{ alignItems: 'flex-start', gap: 10 }}>
            <span style={{ width: 38, height: 38, borderRadius: 10, background: '#0A66C2', color: '#fff', fontSize: 12, fontWeight: 700, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
              {initials(job.company || job.title)}
            </span>
            <div style={{ minWidth: 0 }}>
              <div className="clamp2" style={{ fontSize: 14, fontWeight: 600 }}>{job.title}</div>
              {job.company && <div className="secondary clamp1" style={{ fontSize: 12, fontWeight: 500 }}>{job.company}</div>}
              {job.location && <div className="row muted clamp1" style={{ fontSize: 11, gap: 3 }}><MapPin size={11} />{job.location}</div>}
            </div>
          </div>
          <div className="row" style={{ marginTop: 10, gap: 8 }}>
            <button className="btn-soft" style={{ height: 40, background: 'var(--canvas)' }} onClick={() => open(job.url, alert.url || JOBS_URL)}>View job</button>
            <button className="btn-soft" style={{ height: 40, background: 'transparent', color: 'var(--ink2)' }} onClick={() => onSave(job)}><Plus size={14} />Save as task</button>
          </div>
        </Card>
      ))}
    </div>
  )
}
