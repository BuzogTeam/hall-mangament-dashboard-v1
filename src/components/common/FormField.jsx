import { Label } from '../ui/label'

export function FormField({ label, name, error, required = false, children, hint }) {
  return <div className="space-y-1.5"><Label htmlFor={name}>{label}{required ? <span className="mr-1 text-rose-500">*</span> : null}</Label>{children}{hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}{error ? <p className="text-xs font-medium text-rose-600 dark:text-rose-400">{error.message || error}</p> : null}</div>
}
