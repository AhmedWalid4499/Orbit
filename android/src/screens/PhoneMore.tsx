// More, like PhoneMore in iOS/OrbitPhone/PhoneSections.swift: every section that isn't in the tab bar (in the Mac's
// Tab order, minus the ones you turned off in Settings › General › Tabs, the synced "hiddenTabs" setting), then
// My Card, Week in review, Plan tomorrow and Search, then Settings. The shell draws the large "More" title.
import { ReactNode } from 'react'
import {
  ChartLine, Calendar, Flame, Mountain, BookOpenText, Lightbulb, Library, Github, Linkedin, ChevronRight,
  IdCard, TrendingUp, MoonStar, Search, Settings,
} from 'lucide-react'
import { useRecords, useSetting } from '@/lib/store'
import type { MoreTab } from './More'
import './pm2.css'

/** The Mac's Tab cases that live under More on the iPhone, in Tab.allCases order. `raw` is the Mac's rawValue (hiddenTabs). */
const SECTIONS: { raw: string; tab: MoreTab; title: string; icon: ReactNode; color: string; brand?: 'github' | 'linkedin' }[] = [
  { raw: 'insights', tab: 'insights', title: 'Insights', icon: <ChartLine size={15} strokeWidth={2.4} />, color: 'var(--lime)' },
  { raw: 'calendar', tab: 'calendar', title: 'Calendar', icon: <Calendar size={15} strokeWidth={2.4} />, color: 'var(--cyan)' },
  { raw: 'habits', tab: 'habits', title: 'Habits', icon: <Flame size={15} strokeWidth={2.4} fill="currentColor" />, color: 'var(--orange)' },
  { raw: 'bucket', tab: 'bucket', title: 'Bucket list', icon: <Mountain size={15} strokeWidth={2.4} fill="currentColor" />, color: 'var(--cyan)' },
  { raw: 'notes', tab: 'notes', title: 'Journal & Notes', icon: <BookOpenText size={15} strokeWidth={2.4} />, color: 'var(--peach)' },
  { raw: 'ideas', tab: 'ideas', title: 'Ideas', icon: <Lightbulb size={15} strokeWidth={2.4} fill="currentColor" />, color: 'var(--pm2-sand)' },
  { raw: 'reading', tab: 'reading', title: 'Reading', icon: <Library size={15} strokeWidth={2.4} />, color: 'var(--purple)' },
  { raw: 'github', tab: 'github', title: 'GitHub', icon: <Github size={16} strokeWidth={2.2} />, color: '#111111', brand: 'github' },
  { raw: 'linkedin', tab: 'jobs', title: 'LinkedIn', icon: <Linkedin size={15} strokeWidth={2.2} fill="currentColor" />, color: '#0A66C2', brand: 'linkedin' },
]

/** Tabs turned off on any device (Settings › General › Tabs on the Mac and iPhone): a synced setting, comma-separated. */
export function useHiddenTabs(): Set<string> {
  const settings = useRecords<{ key?: string; value?: unknown }>('setting')
  const raw = settings.find((r) => r.data.key === 'hiddenTabs')?.data.value
  return new Set(typeof raw === 'string' ? raw.split(',').filter(Boolean) : [])
}

export default function PhoneMore({ onOpen, onCard, onReview, onPlan, onSearch, onSettings }: {
  onOpen: (t: MoreTab) => void; onCard: () => void; onReview: () => void; onPlan: () => void; onSearch: () => void; onSettings: () => void
}) {
  const hidden = useHiddenTabs()
  const first = useSetting<string>('userName', '').trim().split(' ')[0]
  const sections = SECTIONS.filter((s) => !hidden.has(s.raw))

  return (
    <div className="pm2 pm2-more">
      {sections.length > 0 && (
        <div className="pm2-group">
          {sections.map((s) => (
            <button key={s.raw} className="pm2-mrow" onClick={() => onOpen(s.tab)}>
              <span className="pm2-micon" style={{ background: s.color, color: s.brand ? '#fff' : undefined }}>{s.icon}</span>
              <span className="label">{s.raw === 'reading' && first ? `${first}'s Reading` : s.title}</span>
              <ChevronRight size={17} color="var(--ink3)" strokeWidth={2.4} />
            </button>
          ))}
        </div>
      )}
      <div className="pm2-group">
        <Row icon={<IdCard size={15} strokeWidth={2.4} />} color="var(--pink)" label="My Card" onClick={onCard} />
        <Row icon={<TrendingUp size={15} strokeWidth={2.4} />} color="var(--mint)" label="Week in review" onClick={onReview} />
        <Row icon={<MoonStar size={15} strokeWidth={2.4} fill="currentColor" />} color="var(--lime)" label="Plan tomorrow" onClick={onPlan} />
        <Row icon={<Search size={15} strokeWidth={2.6} />} color="var(--cyan)" label="Search" onClick={onSearch} />
      </div>
      <div className="pm2-group">
        <Row icon={<Settings size={15} strokeWidth={2.4} />} color="var(--pm2-silver)" label="Settings" onClick={onSettings} />
      </div>
    </div>
  )
}

function Row({ icon, color, label, onClick }: { icon: ReactNode; color: string; label: string; onClick: () => void }) {
  return (
    <button className="pm2-mrow" onClick={onClick}>
      <span className="pm2-micon" style={{ background: color }}>{icon}</span>
      <span className="label">{label}</span>
    </button>
  )
}
