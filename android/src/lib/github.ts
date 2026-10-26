// GitHub profile, repositories, pull requests, issues and activity (the Mac's GitHubStore).
// A username is enough for public data; a token adds private repos and the contribution calendar.

export interface Profile { login: string; name: string; bio: string; avatarURL: string; followers: number; following: number; publicRepos: number; htmlURL: string }
export interface Repo {
  id: number; name: string; fullName: string; description: string; language: string; stars: number; forks: number
  openIssues: number; isPrivate: boolean; isFork: boolean; isArchived: boolean; pushedAt: string | null; htmlURL: string
}
export interface IssueItem { id: number; title: string; repo: string; number: number; updatedAt: string | null; htmlURL: string; isDraft: boolean }
export interface Activity { id: string; summary: string; repo: string; at: string | null; kind: string }
export interface ContributionDay { date: string; count: number }

export interface GitHubData {
  profile: Profile; repos: Repo[]; pullRequests: IssueItem[]; issues: IssueItem[]; activity: Activity[]
  contributions: ContributionDay[]; totalContributions: number; refreshedAt: number
}

const CACHE = 'orbit.github'
export function cachedGitHub(): GitHubData | null {
  try { return JSON.parse(localStorage.getItem(CACHE) ?? 'null') } catch { return null }
}
export function clearGitHubCache(): void { try { localStorage.removeItem(CACHE) } catch { /* ignore */ } }

async function api(path: string, token?: string, init: RequestInit = {}): Promise<any> {
  const headers: Record<string, string> = { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' }
  if (token) headers.Authorization = `Bearer ${token}`
  const r = await fetch(path.startsWith('http') ? path : `https://api.github.com${path}`, { ...init, headers: { ...headers, ...(init.headers as any) } })
  if (r.ok) return r.json()
  if (r.status === 401) throw new Error('GitHub rejected the token. Check it and try again.')
  if (r.status === 403 || r.status === 429) throw new Error('GitHub rate limit reached. Adding a token raises the limit.')
  if (r.status === 404) throw new Error('GitHub user not found.')
  throw new Error(`GitHub returned an error (${r.status}).`)
}

const repo = (j: any): Repo => ({
  id: j.id ?? 0, name: j.name ?? '', fullName: j.full_name ?? '', description: j.description ?? '', language: j.language ?? '',
  stars: j.stargazers_count ?? 0, forks: j.forks_count ?? 0, openIssues: j.open_issues_count ?? 0, isPrivate: !!j.private,
  isFork: !!j.fork, isArchived: !!j.archived, pushedAt: j.pushed_at ?? null, htmlURL: j.html_url ?? '',
})

const issue = (j: any): IssueItem => ({
  id: j.id ?? 0, title: j.title ?? '', repo: String(j.repository_url ?? '').split('/').slice(-2).join('/'),
  number: j.number ?? 0, updatedAt: j.updated_at ?? null, htmlURL: j.html_url ?? '', isDraft: !!j.draft,
})

const capitalize = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s)

function activity(j: any): Activity | null {
  const p = j.payload ?? {}, action = capitalize(p.action ?? '')
  let summary: string
  switch (j.type) {
    case 'PushEvent': {
      const n = p.size ?? p.commits?.length ?? 1
      const branch = String(p.ref ?? '').replace('refs/heads/', '')
      summary = `Pushed ${n} commit${n === 1 ? '' : 's'}${branch ? ` to ${branch}` : ''}`; break
    }
    case 'PullRequestEvent': summary = `${action} PR: ${p.pull_request?.title ?? ''}`; break
    case 'IssuesEvent': summary = `${action} issue: ${p.issue?.title ?? ''}`; break
    case 'IssueCommentEvent': case 'PullRequestReviewCommentEvent': case 'CommitCommentEvent': summary = 'Commented'; break
    case 'PullRequestReviewEvent': summary = 'Reviewed a pull request'; break
    case 'CreateEvent': summary = `Created ${p.ref_type ?? ''}${p.ref ? ` ${p.ref}` : ''}`; break
    case 'DeleteEvent': summary = `Deleted ${p.ref_type ?? ''} ${p.ref ?? ''}`; break
    case 'WatchEvent': summary = 'Starred'; break
    case 'ForkEvent': summary = 'Forked'; break
    case 'ReleaseEvent': summary = 'Published a release'; break
    case 'PublicEvent': summary = 'Made public'; break
    default: return null
  }
  return { id: String(j.id ?? crypto.randomUUID()), summary, repo: j.repo?.name ?? '', at: j.created_at ?? null, kind: j.type }
}

async function contributions(login: string, token: string): Promise<{ days: ContributionDay[]; total: number }> {
  const query = `query($login: String!) { user(login: $login) { contributionsCollection { contributionCalendar {
    totalContributions weeks { contributionDays { date contributionCount } } } } } }`
  const json = await api('/graphql', token, { method: 'POST', body: JSON.stringify({ query, variables: { login } }), headers: { 'Content-Type': 'application/json' } })
  const cal = json?.data?.user?.contributionsCollection?.contributionCalendar
  const days = (cal?.weeks ?? []).flatMap((w: any) => (w.contributionDays ?? []).map((d: any) => ({ date: d.date, count: d.contributionCount ?? 0 })))
  return { days, total: cal?.totalContributions ?? 0 }
}

/** Loads everything and caches it. */
export async function loadGitHub(username: string, token?: string): Promise<GitHubData> {
  const me = await api(token ? '/user' : `/users/${encodeURIComponent(username)}`, token)
  const login: string = me.login ?? username
  const profile: Profile = {
    login, name: me.name ?? '', bio: me.bio ?? '', avatarURL: me.avatar_url ?? '', followers: me.followers ?? 0, following: me.following ?? 0,
    publicRepos: (me.public_repos ?? 0) + (me.total_private_repos ?? 0), htmlURL: me.html_url ?? `https://github.com/${login}`,
  }
  const q = (s: string) => encodeURIComponent(s)
  const [repos, prs, issues, events] = await Promise.all([
    api(token ? '/user/repos?sort=pushed&per_page=100&affiliation=owner,collaborator,organization_member' : `/users/${login}/repos?sort=pushed&per_page=100`, token),
    api(`/search/issues?q=${q(`is:open is:pr author:${login} archived:false`)}&sort=updated&per_page=20`, token),
    api(`/search/issues?q=${q(`is:open is:issue assignee:${login} archived:false`)}&sort=updated&per_page=20`, token),
    api(`/users/${login}/events?per_page=40`, token),
  ])
  const cal = token ? await contributions(login, token).catch(() => ({ days: [], total: 0 })) : { days: [], total: 0 }
  const data: GitHubData = {
    profile, repos: (repos ?? []).map(repo), pullRequests: (prs?.items ?? []).map(issue), issues: (issues?.items ?? []).map(issue),
    activity: (events ?? []).map(activity).filter(Boolean) as Activity[], contributions: cal.days, totalContributions: cal.total, refreshedAt: Date.now(),
  }
  try { localStorage.setItem(CACHE, JSON.stringify(data)) } catch { /* full */ }
  return data
}

export const LANGUAGE_COLOR: Record<string, string> = {
  Swift: '#F05138', TypeScript: '#3178C6', JavaScript: '#F1E05A', Python: '#3572A5', Go: '#00ADD8', Rust: '#DEA584', Java: '#B07219',
  Kotlin: '#A97BFF', 'C#': '#178600', 'C++': '#F34B7D', C: '#555555', Ruby: '#701516', PHP: '#4F5D95', HTML: '#E34C26', CSS: '#563D7C',
  Shell: '#89E051', Dart: '#00B4AB', 'Jupyter Notebook': '#DA5B0B',
}

/** "@name", "github.com/name/" or a profile link → "name". */
export const cleanUsername = (s: string): string =>
  s.trim().replace(/^@/, '').replace(/^https?:\/\//, '').replace(/^(www\.)?github\.com\//, '').replace(/^\/+|\/+$/g, '')
