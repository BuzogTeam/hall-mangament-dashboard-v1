export function Label({ children, htmlFor, className = '' }) {
  return <label htmlFor={htmlFor} className={`mb-1.5 block text-sm font-semibold text-foreground ${className}`}>{children}</label>
}
