import { Table2 } from 'lucide-react'
import { EmptyState } from './EmptyState'
import { LoadingState } from './LoadingState'

export function DataTable({ columns, data, loading = false, emptyTitle, emptyDescription, emptyActionLabel, onEmptyAction, actions, rowKey = 'id', compact = false }) {
  if (loading) return <LoadingState rows={6} />
  if (!data?.length) return <EmptyState title={emptyTitle} description={emptyDescription} actionLabel={emptyActionLabel} onAction={onEmptyAction} icon={Table2} />
  return <div className="overflow-hidden rounded-2xl border border-border/80 bg-card/95 shadow-card"><div className="overflow-x-auto"><table className="w-full min-w-[680px] text-right text-sm"><thead className="border-b border-border bg-muted/65 text-[11px] font-black uppercase tracking-wide text-muted-foreground"><tr>{columns.map((column) => <th key={column.key || column.header} className={`whitespace-nowrap px-5 ${compact ? 'py-3' : 'py-4'} ${column.className || ''}`}>{column.header}</th>)}{actions ? <th className="px-5 py-4">إجراءات</th> : null}</tr></thead><tbody className="divide-y divide-border/70">{data.map((row, index) => <tr key={row[rowKey] ?? index} className="group transition-colors hover:bg-primary/[.025]">{columns.map((column) => <td key={column.key || column.header} className={`px-5 ${compact ? 'py-3' : 'py-4'} ${column.className || ''}`}>{column.cell ? column.cell(row) : (row[column.key] ?? '—')}</td>)}{actions ? <td className="px-5 py-3">{actions(row)}</td> : null}</tr>)}</tbody></table></div></div>
}
