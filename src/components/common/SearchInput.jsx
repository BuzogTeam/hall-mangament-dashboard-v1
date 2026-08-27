import { Search, X } from 'lucide-react'
import { Input } from '../ui/input'
import { Button } from '../ui/button'

export function SearchInput({ value, onChange, placeholder = 'بحث…', className = '' }) {
  return <div className={`relative min-w-0 flex-1 ${className}`}><Search className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} className="pe-10 ps-9" />{value ? <Button type="button" variant="ghost" size="icon" onClick={() => onChange('')} className="absolute left-1 top-1/2 h-8 w-8 -translate-y-1/2"><X className="h-4 w-4" /></Button> : null}</div>
}
