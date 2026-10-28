// GitHub (the Mac's GitHubView): your profile, projects, open pull requests, assigned issues and recent activity.
// Username and optional token live in the phone's encrypted secret store.
import { useEffect, useState, ReactNode } from 'react'
import { RefreshCw, ArrowUpRight, Star, GitFork, CircleAlert, GitPullRequest, Lock, Search, Code2, Clock, AlertTriangle, CircleArrowUp,
  MessageSquareText, CheckCheck, CirclePlus, CircleMinus, Package, Globe, Folder, BadgeCheck } from 'lucide-react'
import { PtTitle } from '../components/PtCommon'
import { secrets, loadSecrets } from '~/secrets'
import { relativeTime, parse } from '@/lib/dates'
import { Card, EmptyHint } from '@/components/ui'
import { GitHubData, IssueItem, Repo, loadGitHub, cachedGitHub, cleanUsername, LANGUAGE_COLOR } from '../lib/github'

const open = (url: string) => { if (url) window.orbit.openExternal(url) }
const ago = (s: string | null) => { const d = parse(s); return d ? relativeTime(d) : '' }
const FILTERS = ['Active', 'All', 'Public', 'Private', 'Forks', 'Archived'] as const

export default function GitHub() {
  const [ready, setReady] = useState(false)
  const [user, setUser] = useState('')
  const [token, setToken] = useState('')
  const [data, setData] = useState<GitHubData | null>(cachedGitHub())
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    loadSecrets().then(() => { setUser(secrets.get('github-user') ?? ''); setToken(secrets.get('github-token') ?? ''); setReady(true) })
  }, [])

  const refresh = async (u = user, t = token) => {
    if ((!u && !t) || loading) return
    setLoading(true); setError('')
    try {
      const d = await loadGitHub(u, t || undefined)
      setData(d)
      if (d.profile.login !== u) { setUser(d.profile.login); await window.orbit.setSecret('github-user', d.profile.login) }
    } catch (e: any) { setError(e?.message ?? String(e)) }
    setLoading(false)
  }

  // Refresh when opened, at most every 10 minutes (as on the Mac).
  useEffect(() => {
    if (ready && (user || token) && (!data || Date.now() - data.refreshedAt > 600_000)) refresh()
  }, [ready]) // eslint-disable-line react-hooks/exhaustive-deps

  const connect = async (u: string, t: string) => {
    await window.orbit.setSecret('github-user', u)
    await window.orbit.setSecret('github-token', t)
    setUser(u); setToken(t); setData(null)
    await refresh(u, t)
  }

  if (!ready) return <div className="page pt-page"><PtTitle>GitHub</PtTitle></div>
  if (!user && !token) return <div className="page pt-page"><PtTitle>GitHub</PtTitle><ConnectCard onConnect={connect} /></div>

  const p = data?.profile
  return (
    <div className="page pt-page" style={{ gap: 22, paddingBottom: 32 }}>
      <PtTitle>GitHub</PtTitle>
      <div className="col" style={{ gap: 12 }}>
        <div className="row" style={{ gap: 16, alignItems: 'center' }}>
          {p?.avatarURL ? <img src={p.avatarURL} alt="" style={{ width: 60, height: 60, borderRadius: '50%', flex: 'none' }} />
            : <span style={{ width: 60, height: 60, borderRadius: '50%', background: 'var(--card)', flex: 'none' }} />}
          <div className="col" style={{ gap: 3, minWidth: 0 }}>
            <div className="display clamp1" style={{ fontSize: 26 }}>{p?.name || `@${user}`}</div>
            <div className="secondary" style={{ fontSize: 13 }}>
              @{user}{p && ` · ${p.followers} followers · ${p.following} following`}{!token && <span className="muted"> · public data only</span>}
            </div>
            {p?.bio && <div className="secondary" style={{ fontSize: 13 }}>{p.bio}</div>}
          </div>
        </div>
        <div className="row" style={{ flexWrap: 'wrap', gap: 8 }}>
          {loading ? <span className="muted" style={{ fontSize: 11 }}>Refreshing…</span>
            : data && <span className="muted" style={{ fontSize: 11 }}>Updated {relativeTime(new Date(data.refreshedAt))}</span>}
          <button className="btn-soft" disabled={loading} onClick={() => refresh()}><RefreshCw size={14} />Refresh</button>
          {p && <button className="btn-soft" onClick={() => open(p.htmlURL)}><ArrowUpRight size={14} />Open GitHub</button>}
        </div>
      </div>

      {error && (
        <div className="row" style={{ gap: 8, background: 'color-mix(in srgb, var(--peach) 50%, transparent)', borderRadius: 12, padding: 12, fontSize: 13, alignItems: 'flex-start' }}>
          <AlertTriangle size={14} style={{ flex: 'none', marginTop: 2 }} />{error}
        </div>
      )}

      {data && <>
        <Stats data={data} hasToken={!!token} />
        {data.contributions.length > 0 && <Contributions data={data} />}
        <Repos repos={data.repos} loading={loading} />
        <IssueList title="Your open pull requests" items={data.pullRequests} empty="No open pull requests." pr />
        <IssueList title="Issues assigned to you" items={data.issues} empty="Nothing assigned." />
        <Card>
          <div className="display" style={{ fontSize: 20, marginBottom: 10 }}>Recent activity</div>
          {data.activity.length === 0 && <EmptyHint icon={<Clock size={14} />} text="No recent public activity." />}
          <div className="col" style={{ gap: 10 }}>
            {data.activity.slice(0, 12).map((a) => (
              <div key={a.id} className="row" style={{ gap: 10, alignItems: 'flex-start' }}>
                <span className="secondary" style={{ width: 18, flex: 'none', paddingTop: 2, display: 'inline-flex', justifyContent: 'center' }}>{activityIcon(a.kind)}</span>
                <div className="col" style={{ gap: 2, minWidth: 0 }}>
                  <div className="clamp2" style={{ fontSize: 13 }}>{a.summary}</div>
                  <div className="muted" style={{ fontSize: 11 }}>{a.repo}{a.at && ` · ${ago(a.at)}`}</div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      </>}
      {!data && loading && <div className="muted" style={{ fontSize: 13 }}>Loading @{user}…</div>}
    </div>
  )
}

/** The icon for each kind of event (GitHubStore's Activity.symbol). */
function activityIcon(kind: string): ReactNode {
  const s = 12
  switch (kind) {
    case 'PushEvent': return <CircleArrowUp size={s} />
    case 'PullRequestEvent': return <GitPullRequest size={s} />
    case 'IssuesEvent': return <CircleAlert size={s} />
    case 'IssueCommentEvent': case 'PullRequestReviewCommentEvent': case 'CommitCommentEvent': return <MessageSquareText size={s} />
    case 'PullRequestReviewEvent': return <CheckCheck size={s} />
    case 'CreateEvent': return <CirclePlus size={s} />
    case 'DeleteEvent': return <CircleMinus size={s} />
    case 'WatchEvent': return <Star size={s} />
    case 'ForkEvent': return <GitFork size={s} />
    case 'ReleaseEvent': return <Package size={s} />
    case 'PublicEvent': return <Globe size={s} />
    default: return <Clock size={s} />
  }
}

function Stats({ data, hasToken }: { data: GitHubData; hasToken: boolean }) {
  const tiles: [string, string, string][] = [
    [String(data.repos.filter((r) => !r.isArchived).length), 'Repositories', 'var(--lime)'],
    [String(data.repos.filter((r) => !r.isFork).reduce((n, r) => n + r.stars, 0)), 'Stars earned', 'var(--orange)'],
    [String(data.pullRequests.length), 'Open PRs', 'var(--cyan)'],
    [String(data.issues.length), 'Assigned issues', 'var(--pink)'],
    [hasToken ? String(data.totalContributions) : '—', 'Contributions (year)', 'var(--purple)'],
  ]
  return (
    <div className="pt-grid2">
      {tiles.map(([v, l, c]) => (
        <div key={l} className="pt-tile" style={{ background: c, gap: 6 }}>
          <div className="v" style={{ fontSize: 28 }}>{v}</div>
          <div className="l">{l}</div>
        </div>
      ))}
    </div>
  )
}

/** Last year of contributions, scrolled to the latest weeks. */
function Contributions({ data }: { data: GitHubData }) {
  const max = Math.max(1, ...data.contributions.map((d) => d.count))
  const weeks: typeof data.contributions[] = []
  for (let i = 0; i < data.contributions.length; i += 7) weeks.push(data.contributions.slice(i, i + 7))
  return (
    <Card>
      <div className="row" style={{ alignItems: 'baseline', marginBottom: 12 }}>
        <span className="display" style={{ fontSize: 22 }}>Contributions</span>
        <span className="spacer" />
        <span className="secondary" style={{ fontSize: 12 }}>{data.totalContributions} in the last year</span>
      </div>
      <div ref={(el) => { if (el) el.scrollLeft = el.scrollWidth }} style={{ overflowX: 'auto', scrollbarWidth: 'none' }}>
        <div style={{ display: 'flex', gap: 3, width: 'max-content' }}>
          {weeks.map((w, i) => (
            <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
              {w.map((d) => (
                <span key={d.date} title={`${d.count} contribution${d.count === 1 ? '' : 's'} on ${d.date}`} style={{
                  width: 11, height: 11, borderRadius: 2.5,
                  background: d.count === 0 ? 'var(--line)' : 'var(--ink)', opacity: d.count === 0 ? 1 : 0.25 + 0.75 * d.count / max,
                }} />
              ))}
            </div>
          ))}
        </div>
      </div>
    </Card>
  )
}

function Repos({ repos, loading }: { repos: Repo[]; loading: boolean }) {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>('Active')
  const [query, setQuery] = useState('')
  let list = repos.filter((r) =>
    filter === 'Active' ? !r.isArchived && !r.isFork : filter === 'Private' ? r.isPrivate : filter === 'Public' ? !r.isPrivate
      : filter === 'Forks' ? r.isFork : filter === 'Archived' ? r.isArchived : true)
  const q = query.trim().toLowerCase()
  if (q) list = list.filter((r) => r.name.toLowerCase().includes(q) || r.description.toLowerCase().includes(q))
  return (
    <Card>
      <div className="col" style={{ gap: 12 }}>
        <div className="row" style={{ gap: 8 }}>
          <span className="display" style={{ fontSize: 22 }}>Projects</span>
          <span className="display muted" style={{ fontSize: 22, fontWeight: 400 }}>{list.length}</span>
          <span className="spacer" />
          <label className="row" style={{ gap: 6, background: 'var(--canvas)', borderRadius: 999, padding: '6px 10px', flex: 'none' }}>
            <Search size={14} className="muted" />
            <input className="plain" style={{ width: 80, fontSize: 15 }} placeholder="Filter" value={query} onChange={(e) => setQuery(e.target.value)} />
          </label>
        </div>
        <div className="pt-chips" style={{ gap: 6, margin: '0 -18px', padding: '0 18px' }}>
          {FILTERS.map((f) => (
            <button key={f} className={`pt-chip sm ${filter === f ? 'on' : ''}`} style={{ fontWeight: 500, background: filter === f ? undefined : 'var(--canvas)' }}
              onClick={() => setFilter(f)}>{f}</button>
          ))}
        </div>
        {list.length === 0 && !loading && <EmptyHint icon={<Folder size={14} />} text="No repositories here." />}
        {list.map((r) => (
          <button key={r.id} className="col" style={{ gap: 6, padding: 12, borderRadius: 14, background: 'var(--canvas)', textAlign: 'left', color: 'var(--ink)', alignItems: 'stretch' }}
            onClick={() => open(r.htmlURL)}>
            <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
              <span style={{ fontSize: 15, fontWeight: 600, wordBreak: 'break-word' }}>{r.name}</span>
              {r.isPrivate && <Tag><Lock size={9} />Private</Tag>}
              {r.isFork && <Tag>Fork</Tag>}
              {r.isArchived && <span style={{ fontSize: 10, fontWeight: 600, color: 'var(--orange)' }}>Archived</span>}
            </div>
            {r.description && <div className="secondary clamp2" style={{ fontSize: 12 }}>{r.description}</div>}
            <div className="row muted" style={{ fontSize: 11, gap: 14, flexWrap: 'wrap' }}>
              {r.language && <span className="row" style={{ gap: 5 }}>
                <span style={{ width: 9, height: 9, borderRadius: '50%', background: LANGUAGE_COLOR[r.language] ?? 'var(--ink3)' }} />{r.language}
              </span>}
              {r.stars > 0 && <span className="row" style={{ gap: 3 }}><Star size={11} />{r.stars}</span>}
              {r.forks > 0 && <span className="row" style={{ gap: 3 }}><GitFork size={11} />{r.forks}</span>}
              {r.openIssues > 0 && <span className="row" style={{ gap: 3 }}><CircleAlert size={11} />{r.openIssues} open</span>}
              <span className="spacer" />
              {r.pushedAt && <span>Updated {ago(r.pushedAt)}</span>}
            </div>
          </button>
        ))}
      </div>
    </Card>
  )
}

const Tag = ({ children }: { children: ReactNode }) => (
  <span className="row" style={{ gap: 3, fontSize: 10, fontWeight: 600, padding: '2px 6px', borderRadius: 999, border: '1px solid var(--line)' }}>{children}</span>
)

function IssueList({ title, items, empty, pr }: { title: string; items: IssueItem[]; empty: string; pr?: boolean }) {
  const Icon = pr ? GitPullRequest : CircleAlert
  return (
    <Card>
      <div className="display" style={{ fontSize: 20, marginBottom: 10 }}>{title}</div>
      {items.length === 0 && <EmptyHint icon={<BadgeCheck size={14} />} text={empty} />}
      <div className="col" style={{ gap: 10 }}>
        {items.slice(0, 8).map((i) => (
          <button key={i.id} className="row" style={{ gap: 10, alignItems: 'flex-start', padding: 10, borderRadius: 12, background: 'var(--canvas)', textAlign: 'left', color: 'var(--ink)' }}
            onClick={() => open(i.htmlURL)}>
            <Icon size={15} style={{ marginTop: 2, flex: 'none', color: i.isDraft ? 'var(--ink3)' : 'var(--good)' }} />
            <div style={{ minWidth: 0 }}>
              <div className="clamp2" style={{ fontSize: 13, fontWeight: 500 }}>{i.title}</div>
              <div className="muted" style={{ fontSize: 11 }}>{i.repo} #{i.number}{i.updatedAt && ` · ${ago(i.updatedAt)}`}</div>
            </div>
          </button>
        ))}
      </div>
    </Card>
  )
}

/** Three steps, as on the Mac: username, optional token, connecting. */
function ConnectCard({ onConnect }: { onConnect: (user: string, token: string) => Promise<void> }) {
  const [step, setStep] = useState(1)
  const [user, setUser] = useState('')
  const [token, setToken] = useState('')
  const u = cleanUsername(user)
  const TOKEN_URL = 'https://github.com/settings/tokens/new?description=Joshu&scopes=repo,read:user'
  return (
    <Card padding={22} style={{ marginTop: 12 }}>
      <div className="col" style={{ gap: 16 }}>
        <div className="row" style={{ gap: 12, alignItems: 'flex-start' }}>
          <span style={{ width: 44, height: 44, borderRadius: '50%', background: 'var(--inverse)', color: 'var(--on-inverse)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
            <Code2 size={18} />
          </span>
          <div>
            <div className="display" style={{ fontSize: 24 }}>Connect GitHub</div>
            <div className="secondary" style={{ fontSize: 13 }}>Your projects, pull requests, issues and activity, next to the rest of your day.</div>
          </div>
        </div>
        <div className="row" style={{ gap: 6 }}>
          {[1, 2, 3].map((i) => <span key={i} style={{ flex: 1, height: 4, borderRadius: 2, background: i <= step ? 'var(--ink)' : 'var(--line)' }} />)}
        </div>

        {step === 1 && <>
          <div style={{ fontSize: 13, fontWeight: 600 }}>Step 1 of 3 · Your username</div>
          <div className="secondary" style={{ fontSize: 12 }}>It's the name in your profile link: github.com/<b>username</b>.</div>
          <input className="field" style={{ background: 'var(--canvas)', height: 44 }} placeholder="GitHub username" autoCapitalize="none" autoCorrect="off"
            value={user} onChange={(e) => setUser(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && u) setStep(2) }} />
          <div className="row">
            <button className="link" style={{ minHeight: 40 }} onClick={() => open('https://github.com/signup')}>Don't have an account? Sign up</button>
            <span className="spacer" />
            <button className="btn-primary" style={{ height: 44, width: 110 }} disabled={!u} onClick={() => setStep(2)}>Next</button>
          </div>
        </>}

        {step === 2 && <>
          <div style={{ fontSize: 13, fontWeight: 600 }}>Step 2 of 3 · Private repos (optional)</div>
          <div className="secondary" style={{ fontSize: 12 }}>With just your username, Joshu shows your public work. To include private repos and your contribution graph, give it a token:</div>
          {['Tap Open GitHub below and sign in. The token is already filled in for Joshu.', 'Pick how long it lasts under Expiration (e.g. 90 days).',
            'Scroll down and tap Generate token.', 'Copy the token (it starts with ghp_) and paste it here.'].map((t, i) => (
            <div key={i} className="row" style={{ alignItems: 'flex-start', gap: 10, fontSize: 13 }}>
              <span style={{ width: 20, height: 20, borderRadius: '50%', background: 'var(--canvas)', fontSize: 11, fontWeight: 700, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>{i + 1}</span>
              {t}
            </div>
          ))}
          <div><button className="btn-soft" style={{ height: 40, background: 'var(--canvas)' }} onClick={() => open(TOKEN_URL)}><ArrowUpRight size={14} />Open GitHub</button></div>
          <input className="field" type="password" style={{ background: 'var(--canvas)', height: 44 }} placeholder="Paste your token (ghp_…)" autoCapitalize="none"
            value={token} onChange={(e) => setToken(e.target.value)} />
          <div className="muted" style={{ fontSize: 11 }}>It's kept encrypted on this phone and only used to read your GitHub data.</div>
          <div className="row">
            <button className="link" style={{ minHeight: 40, padding: '0 6px' }} onClick={() => setStep(1)}>Back</button>
            <span className="spacer" />
            <button className="btn-primary" style={{ height: 44 }} onClick={() => { setStep(3); onConnect(u, token.trim()) }}>
              {token.trim() ? 'Connect' : 'Skip, public only'}
            </button>
          </div>
        </>}

        {step === 3 && <div className="secondary" style={{ fontSize: 13 }}>Loading @{u}…</div>}
      </div>
    </Card>
  )
}
