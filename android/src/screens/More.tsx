// Everything that isn't a bottom tab, like the iPhone's More list.
import { ReactNode } from 'react'
import { Calendar, Flame, Mountain, BookOpenText, Library, FileText, Lightbulb, Target, Receipt, Github, Briefcase, BarChart3, Settings, IdCard, ClipboardCheck, Moon, Wallet } from 'lucide-react'
import { useSetting } from '@/lib/store'

export type MoreTab = 'calendar' | 'habits' | 'bucket' | 'notes' | 'reading' | 'documents' | 'ideas' | 'goals' | 'bills' | 'accounts' | 'github' | 'jobs' | 'insights'

export const MORE_TITLES: Record<MoreTab, string> = {
  calendar: 'Calendar', habits: 'Habits', bucket: 'Bucket list', notes: 'Journal & Notes', reading: 'Reading', documents: 'Documents',
  ideas: 'Ideas', goals: 'Goals', bills: 'Bills', accounts: 'Accounts', github: 'GitHub', jobs: 'LinkedIn', insights: 'Insights',
}

const TILES: { id: MoreTab; icon: ReactNode; color: string }[] = [
  { id: 'calendar', icon: <Calendar size={20} />, color: 'var(--cyan)' },
  { id: 'habits', icon: <Flame size={20} />, color: 'var(--orange)' },
  { id: 'notes', icon: <BookOpenText size={20} />, color: 'var(--peach)' },
  { id: 'reading', icon: <Library size={20} />, color: 'var(--purple)' },
  { id: 'bucket', icon: <Mountain size={20} />, color: 'var(--mint)' },
  { id: 'goals', icon: <Target size={20} />, color: 'var(--lime)' },
  { id: 'ideas', icon: <Lightbulb size={20} />, color: 'var(--pink)' },
  { id: 'bills', icon: <Receipt size={20} />, color: 'var(--peach)' },
  { id: 'accounts', icon: <Wallet size={20} />, color: 'var(--cyan)' },
  { id: 'insights', icon: <BarChart3 size={20} />, color: 'var(--purple)' },
  { id: 'documents', icon: <FileText size={20} />, color: 'var(--mint)' },
  { id: 'jobs', icon: <Briefcase size={20} />, color: 'var(--orange)' },
  { id: 'github', icon: <Github size={20} />, color: 'var(--card-hover)' },
]

export default function More({ onOpen, onSettings, onCard, onReview, onPlan }: {
  onOpen: (t: MoreTab) => void; onSettings: () => void; onCard: () => void; onReview: () => void; onPlan: () => void
}) {
  const first = useSetting<string>('userName', '').split(' ')[0]
  return (
    <div className="page col" style={{ gap: 16 }}>
      <h1 className="page-title">More</h1>
      <div className="more-grid">
        {TILES.map((t) => (
          <button key={t.id} className="more-tile" onClick={() => onOpen(t.id)}>
            <span className="more-icon" style={{ background: t.color }}>{t.icon}</span>
            <span>{t.id === 'reading' && first ? `${first}'s Reading` : MORE_TITLES[t.id]}</span>
          </button>
        ))}
      </div>
      <div className="card col" style={{ gap: 4, padding: 8 }}>
        <Line icon={<Moon size={17} />} label="Plan tomorrow" onClick={onPlan} />
        <Line icon={<ClipboardCheck size={17} />} label="Weekly review" onClick={onReview} />
        <Line icon={<IdCard size={17} />} label="My card" onClick={onCard} />
        <Line icon={<Settings size={17} />} label="Settings" onClick={onSettings} />
      </div>
    </div>
  )
}

function Line({ icon, label, onClick }: { icon: ReactNode; label: string; onClick: () => void }) {
  return <button className="list-row" style={{ background: 'transparent', minHeight: 48 }} onClick={onClick}>{icon}<span style={{ fontWeight: 500 }}>{label}</span></button>
}
