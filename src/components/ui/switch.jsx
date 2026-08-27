import { cn } from '../../lib/utils'
export function Switch({ checked, onChange, disabled = false, label }) {
  return <button type="button" role="switch" aria-checked={checked} disabled={disabled} onClick={() => onChange?.(!checked)} className={cn('relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors disabled:opacity-50', checked ? 'bg-primary' : 'bg-slate-300 dark:bg-slate-700')}><span className={cn('h-4 w-4 rounded-full bg-white shadow-sm transition-transform', checked ? '-translate-x-6' : '-translate-x-1')} />{label ? <span className="sr-only">{label}</span> : null}</button>
}
