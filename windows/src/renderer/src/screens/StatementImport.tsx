// "Import statement…" in Money: a bank statement CSV or PDF, previewed with column mapping and duplicate checks.
import { useEffect, useRef, useState } from 'react'
import { FileUp, Sparkles } from 'lucide-react'
import { MONEY_CATEGORIES } from '@/lib/models'
import { useKeys } from '@/lib/ai'
import { fmtDay } from '@/lib/dates'
import {
  parseCSV, guessColumns, rowsFromCSV, CSVGuess, Field, FIELD_LABEL, pdfText, rowsFromPDFText, preview, PreviewRow, categorize, importRows, StatementRow,
} from '@/lib/statement'
import { Modal, useMoney } from '@/components/ui'

type Source = { kind: 'csv'; rows: string[][]; guess: CSVGuess } | { kind: 'pdf' }

export function ImportStatementButton() {
  const input = useRef<HTMLInputElement>(null)
  const keys = useKeys()
  const [file, setFile] = useState<File | null>(null)
  return (
    <>
      <button className="btn-soft" onClick={() => input.current?.click()} title="Import a bank statement (CSV or PDF)"><FileUp size={14} /><span className="wide-only">Import statement…</span></button>
      <input ref={input} type="file" accept=".csv,.txt,.pdf,text/csv,application/pdf" style={{ display: 'none' }}
        onChange={(e) => { setFile(e.target.files?.[0] ?? null); e.target.value = '' }} />
      {file && <ImportSheet file={file} hasKey={keys.anthropic} onClose={() => setFile(null)} />}
    </>
  )
}

function ImportSheet({ file, hasKey, onClose }: { file: File; hasKey: boolean; onClose: () => void }) {
  const money = useMoney()
  const [source, setSource] = useState<Source | null>(null)
  const [rows, setRows] = useState<PreviewRow[]>([])
  const [status, setStatus] = useState('Reading the file…')
  const [error, setError] = useState('')
  const [done, setDone] = useState('')
  const run = useRef(0)

  const show = async (parsed: StatementRow[]) => {
    const id = ++run.current
    const p = await preview(parsed)
    if (id !== run.current) return
    setRows(p)
    if (!p.length) { setStatus(''); setError("Couldn't find any transactions. Check the column mapping."); return }
    setError('')
    if (!hasKey) { setStatus(''); return }
    setStatus('Categorising…')
    try {
      const cats: string[] = []
      for (let i = 0; i < p.length; i += 150) cats.push(...await categorize(p.slice(i, i + 150)))
      if (id === run.current) setRows((rs) => rs.map((r, i) => ({ ...r, category: cats[i] ?? r.category })))
    } catch { /* keep the keyword guesses */ }
    if (id === run.current) setStatus('')
  }

  useEffect(() => {
    (async () => {
      try {
        if (/\.pdf$/i.test(file.name) || file.type === 'application/pdf') {
          if (!hasKey) { setStatus(''); setError('Reading PDF statements needs your Anthropic API key (Settings › AI). A CSV export works without it.'); return }
          setSource({ kind: 'pdf' })
          const text = await pdfText(file)
          if (!text.trim()) { setStatus(''); setError("This PDF has no text in it (it may be a scan). Try your bank's CSV export."); return }
          setStatus('Reading the statement with Claude…')
          await show(await rowsFromPDFText(text))
        } else {
          const csv = parseCSV(await file.text())
          const guess = guessColumns(csv)
          setSource({ kind: 'csv', rows: csv, guess })
          await show(rowsFromCSV(csv, guess))
        }
      } catch (e) {
        setStatus(''); setError((e as Error).message)
      }
    })()
  }, [])

  const remap = (col: number, f: Field) => {
    if (source?.kind !== 'csv') return
    const mapping = source.guess.mapping.map((x, i) => (i === col ? f : x === f && f !== 'ignore' ? 'ignore' : x))
    const guess = { ...source.guess, mapping }
    setSource({ ...source, guess })
    show(rowsFromCSV(source.rows, guess))
  }
  const set = (i: number, p: Partial<PreviewRow>) => setRows((rs) => rs.map((r, j) => (j === i ? { ...r, ...p } : r)))
  const checked = rows.filter((r) => r.checked)
  const dupes = rows.filter((r) => r.duplicate).length

  if (done) {
    return (
      <Modal open onClose={onClose} width={420}>
        <div className="col" style={{ gap: 14 }}>
          <h2 className="display" style={{ fontSize: 26, margin: 0 }}>Imported ✓</h2>
          <div className="secondary">{done}</div>
          <button className="btn-primary" style={{ alignSelf: 'flex-end', width: 110 }} onClick={onClose}>Done</button>
        </div>
      </Modal>
    )
  }

  const csv = source?.kind === 'csv' ? source : null
  const headerRow = csv ? (csv.guess.header >= 0 ? csv.rows[csv.guess.header] : csv.rows[0]) : []
  return (
    <Modal open onClose={onClose} width={900}>
      <div className="col" style={{ gap: 14 }}>
        <div>
          <h2 className="display" style={{ fontSize: 26, margin: 0 }}>Import statement</h2>
          <div className="secondary" style={{ fontSize: 12 }}>{file.name}{rows.length > 0 && ` · ${rows.length} transactions${dupes ? `, ${dupes} already in Orbit` : ''}`}</div>
        </div>
        {csv && (
          <div className="col" style={{ gap: 6 }}>
            <div className="muted" style={{ fontSize: 12, fontWeight: 600 }}>Columns</div>
            <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
              {csv.guess.mapping.map((f, i) => (
                <label key={i} className="col" style={{ gap: 3, width: 150 }}>
                  <span className="clamp1 muted" style={{ fontSize: 11 }} title={headerRow[i]}>{csv.guess.header >= 0 ? headerRow[i] || `Column ${i + 1}` : `Column ${i + 1}: ${headerRow[i] ?? ''}`}</span>
                  <select className="field" style={{ padding: '6px 8px', fontSize: 12 }} value={f} onChange={(e) => remap(i, e.target.value as Field)}>
                    {(Object.keys(FIELD_LABEL) as Field[]).map((k) => <option key={k} value={k}>{FIELD_LABEL[k]}</option>)}
                  </select>
                </label>
              ))}
            </div>
          </div>
        )}
        {status && <div className="row secondary" style={{ fontSize: 12, gap: 6 }}><Sparkles size={12} />{status}</div>}
        {error && <div style={{ fontSize: 12, color: 'var(--critical)' }}>{error}</div>}
        {rows.length > 0 && (
          <div className="scroll col" style={{ gap: 4, maxHeight: 380 }}>
            <div className="row muted" style={{ fontSize: 11, fontWeight: 600, padding: '0 10px', gap: 10 }}>
              <input type="checkbox" checked={checked.length === rows.length} onChange={(e) => setRows((rs) => rs.map((r) => ({ ...r, checked: e.target.checked })))} />
              <span style={{ width: 90 }}>Date</span><span style={{ flex: 1 }}>Description</span><span style={{ width: 140 }}>Category</span><span style={{ width: 110, textAlign: 'right' }}>Amount</span>
            </div>
            {rows.map((r, i) => (
              <label key={i} className="inner row" style={{ gap: 10, padding: '6px 10px', opacity: r.checked ? 1 : 0.5 }}>
                <input type="checkbox" checked={r.checked} onChange={(e) => set(i, { checked: e.target.checked })} />
                <span style={{ width: 90, fontSize: 12 }}>{fmtDay(r.date, { day: 'numeric', month: 'short', year: 'numeric' })}</span>
                <span className="clamp1" style={{ flex: 1, fontSize: 13 }} title={r.description}>{r.description}</span>
                {r.duplicate && <span className="pill compact" style={{ background: 'var(--card-hover)', color: 'var(--ink2)' }}>Already in Orbit</span>}
                <select className="field" style={{ width: 140, padding: '4px 8px', fontSize: 12 }} value={r.category} onChange={(e) => set(i, { category: e.target.value })}>
                  {MONEY_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
                <strong style={{ width: 110, textAlign: 'right', fontSize: 13, color: r.amount > 0 ? 'var(--good)' : undefined }}>{money(r.amount, true)}</strong>
              </label>
            ))}
          </div>
        )}
        <div className="row">
          <button className="btn-soft" onClick={onClose}>Cancel</button>
          <span className="spacer" />
          <button className="btn-primary" disabled={!checked.length} onClick={() => {
            const n = importRows(rows)
            setDone(`Added ${n} transaction${n === 1 ? '' : 's'} from ${file.name}.`)
          }}>Import {checked.length} transaction{checked.length === 1 ? '' : 's'}</button>
        </div>
      </div>
    </Modal>
  )
}
