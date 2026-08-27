import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Button } from '../ui/button'

export function Pagination({ page, pageCount, onPageChange, total, pageSize }) {
  if (pageCount <= 1) return <div className="text-xs text-muted-foreground">{total} عنصر</div>
  const start = (page - 1) * pageSize + 1
  const end = Math.min(page * pageSize, total)
  return <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-5 py-3"><span className="text-xs text-muted-foreground">عرض {start}–{end} من {total}</span><div className="flex items-center gap-1"><Button variant="outline" size="icon" className="h-8 w-8" disabled={page <= 1} onClick={() => onPageChange(page - 1)}><ChevronRight className="h-4 w-4" /></Button><span className="min-w-16 text-center text-xs font-semibold">{page} / {pageCount}</span><Button variant="outline" size="icon" className="h-8 w-8" disabled={page >= pageCount} onClick={() => onPageChange(page + 1)}><ChevronLeft className="h-4 w-4" /></Button></div></div>
}
