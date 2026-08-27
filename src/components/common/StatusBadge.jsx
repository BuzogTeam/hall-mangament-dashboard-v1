import { CheckCircle2, Circle, Clock3, XCircle } from 'lucide-react'
import { Badge } from '../ui/badge'
import { getStatusClass, getStatusLabel } from '../../lib/utils'

export function StatusBadge({ status, label }) {
  const Icon = status === 'canceled' ? XCircle : status === 'live' ? Clock3 : status === 'available' || status === 'active' ? CheckCircle2 : Circle
  return <Badge className={getStatusClass(status)}><Icon className="h-3.5 w-3.5" />{label || getStatusLabel(status)}</Badge>
}
