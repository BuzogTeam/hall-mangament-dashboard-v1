import { AlertTriangle, RefreshCw } from 'lucide-react'
import { Button } from '../ui/button'
import { getErrorMessage } from '../../lib/utils'

export function ErrorState({ error, onRetry, title = 'تعذر تحميل البيانات' }) {
  return <div className="flex min-h-56 flex-col items-center justify-center rounded-2xl border border-rose-200 bg-rose-50/60 px-5 text-center dark:border-rose-900/60 dark:bg-rose-950/20"><div className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-rose-500/10 text-rose-600"><AlertTriangle className="h-6 w-6" /></div><h3 className="font-bold text-rose-700 dark:text-rose-300">{title}</h3><p className="mt-1 max-w-lg text-sm leading-6 text-rose-600/80 dark:text-rose-300/80">{getErrorMessage(error, 'تحقق من الاتصال بقاعدة البيانات ثم حاول مرة أخرى.')}</p>{onRetry ? <Button className="mt-4" size="sm" variant="outline" onClick={onRetry}><RefreshCw className="h-4 w-4" />إعادة المحاولة</Button> : null}</div>
}
