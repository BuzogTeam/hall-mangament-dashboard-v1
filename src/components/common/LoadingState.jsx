import { Skeleton } from '../ui/skeleton'

export function LoadingState({ rows = 5, cards = false }) {
  if (cards) return <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{Array.from({ length: rows }).map((_, index) => <Skeleton key={index} className="h-32 rounded-2xl" />)}</div>
  return <div className="space-y-3 rounded-2xl border border-border bg-card p-5">{Array.from({ length: rows }).map((_, index) => <div key={index} className="flex items-center gap-4"><Skeleton className="h-10 w-10 rounded-lg" /><Skeleton className="h-4 flex-1" /><Skeleton className="h-4 w-24" /></div>)}</div>
}
