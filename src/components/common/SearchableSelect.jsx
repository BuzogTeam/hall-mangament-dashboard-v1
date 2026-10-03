import { useEffect, useMemo, useRef, useState } from 'react'
import { Check, ChevronDown, Search, X } from 'lucide-react'
import { cn, includesText } from '../../lib/utils'

function optionLabel(option) {
  return option?.label ?? option?.value ?? ''
}

function optionSearchText(option) {
  return [option?.label, option?.description, option?.searchText, option?.value]
    .filter((value) => value !== undefined && value !== null)
    .join(' ')
}

export function SearchableSelect({
  options = [],
  value = '',
  onChange,
  onBlur,
  placeholder = 'اكتب للبحث أو اختر…',
  searchPlaceholder = 'اكتب للبحث…',
  disabled = false,
  className = '',
  clearable = true,
  noResultsText = 'لا توجد نتائج مطابقة',
  id,
}) {
  const rootRef = useRef(null)
  const inputRef = useRef(null)
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [searchStarted, setSearchStarted] = useState(false)
  const [activeIndex, setActiveIndex] = useState(0)
  const selected = options.find((option) => String(option.value) === String(value))
  const selectedLabel = selected ? String(optionLabel(selected)) : ''
  const filtered = useMemo(() => {
    if (!searchStarted || !query.trim()) return options
    return options.filter((option) => includesText(optionSearchText(option), query))
  }, [options, query, searchStarted])

  useEffect(() => {
    const handlePointerDown = (event) => {
      if (!rootRef.current?.contains(event.target)) {
        setOpen(false)
        setQuery('')
        setSearchStarted(false)
        onBlur?.()
      }
    }
    document.addEventListener('mousedown', handlePointerDown)
    return () => document.removeEventListener('mousedown', handlePointerDown)
  }, [onBlur])

  const openMenu = () => {
    if (disabled) return
    setOpen(true)
    setQuery(selectedLabel)
    setSearchStarted(false)
    setActiveIndex(0)
    requestAnimationFrame(() => {
      inputRef.current?.focus()
      inputRef.current?.select()
    })
  }

  const selectOption = (option) => {
    if (!option || option.disabled) return
    onChange?.(option.value)
    setOpen(false)
    setQuery('')
    setSearchStarted(false)
    onBlur?.()
  }

  const clearValue = (event) => {
    event.preventDefault()
    event.stopPropagation()
    onChange?.('')
    setQuery('')
    setSearchStarted(false)
    setOpen(true)
    requestAnimationFrame(() => inputRef.current?.focus())
  }

  const handleInputChange = (event) => {
    setQuery(event.target.value)
    setSearchStarted(true)
    setActiveIndex(0)
    if (!open) setOpen(true)
  }

  const handleKeyDown = (event) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault()
      if (!open) openMenu()
      else setActiveIndex((index) => Math.min(index + 1, Math.max(filtered.length - 1, 0)))
    } else if (event.key === 'ArrowUp') {
      event.preventDefault()
      if (open) setActiveIndex((index) => Math.max(index - 1, 0))
    } else if (event.key === 'Enter') {
      if (open && filtered[activeIndex]) {
        event.preventDefault()
        selectOption(filtered[activeIndex])
      }
    } else if (event.key === 'Escape') {
      event.preventDefault()
      setOpen(false)
      setQuery('')
      setSearchStarted(false)
    } else if (event.key === 'Tab') {
      setOpen(false)
      setQuery('')
      setSearchStarted(false)
      onBlur?.()
    }
  }

  const displayValue = open ? query : selectedLabel

  return <div ref={rootRef} className={cn('relative', open && 'z-[100]', className)}>
    <Search className="pointer-events-none absolute right-3 top-1/2 z-10 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
    <input
      id={id}
      ref={inputRef}
      role="combobox"
      aria-expanded={open}
      aria-haspopup="listbox"
      aria-autocomplete="list"
      aria-controls={open ? `${id || 'searchable-select'}-listbox` : undefined}
      value={displayValue}
      placeholder={open ? searchPlaceholder : placeholder}
      disabled={disabled}
      autoComplete="off"
      onFocus={openMenu}
      onClick={() => { if (!open) openMenu() }}
      onChange={handleInputChange}
      onKeyDown={handleKeyDown}
      onBlur={() => { if (!open) onBlur?.() }}
      className="flex h-11 w-full rounded-xl border border-input bg-background/80 px-10 py-2.5 text-right text-sm outline-none shadow-sm transition-all placeholder:text-muted-foreground hover:border-primary/50 focus:border-primary focus:bg-background focus:ring-4 focus:ring-primary/10 disabled:cursor-not-allowed disabled:opacity-50"
    />
    <div className="absolute left-2 top-1/2 z-10 flex -translate-y-1/2 items-center gap-0.5">
      {clearable && value !== '' && value !== null && value !== undefined && !disabled ? <button type="button" aria-label="مسح الاختيار" onMouseDown={clearValue} className="rounded-md p-1 text-muted-foreground hover:bg-muted hover:text-foreground"><X className="h-4 w-4" /></button> : null}
      <ChevronDown className={cn('h-4 w-4 text-muted-foreground transition-transform', open && 'rotate-180')} />
    </div>
    {open ? <div id={`${id || 'searchable-select'}-listbox`} className="absolute left-0 right-0 top-full z-[100] mt-1 w-full overflow-hidden rounded-md border border-slate-200 bg-white shadow-xl ring-1 ring-black/5 dark:border-slate-700 dark:bg-slate-900 dark:ring-white/10" role="listbox">
      <div className="max-h-64 overflow-y-auto p-1">
        {filtered.length ? filtered.map((option, index) => <button key={`${option.value}-${index}`} type="button" role="option" aria-selected={String(option.value) === String(value)} disabled={option.disabled} onMouseEnter={() => setActiveIndex(index)} onMouseDown={(event) => event.preventDefault()} onClick={() => selectOption(option)} className={cn('flex w-full items-center gap-2 rounded-lg px-3 py-2.5 text-right text-sm transition-colors disabled:cursor-not-allowed disabled:opacity-50', index === activeIndex ? 'bg-primary/10 text-primary' : 'hover:bg-muted', String(option.value) === String(value) && 'font-bold')}><span className="min-w-0 flex-1"><span className="block truncate">{optionLabel(option)}</span>{option.description ? <span className="mt-0.5 block truncate text-[11px] text-muted-foreground">{option.description}</span> : null}</span>{String(option.value) === String(value) ? <Check className="h-4 w-4 shrink-0 text-primary" /> : null}</button>) : <p className="p-4 text-center text-xs text-muted-foreground">{noResultsText}</p>}
      </div>
    </div> : null}
  </div>
}

export function SearchableSelectField({ name, register, watch, setValue, options, ...props }) {
  const registration = register(name)
  const value = watch(name)
  return <>
    <input type="hidden" {...registration} value={value ?? ''} readOnly />
    <SearchableSelect id={name} name={name} value={value ?? ''} onChange={(nextValue) => setValue(name, nextValue, { shouldDirty: true, shouldTouch: true, shouldValidate: true })} options={options} {...props} />
  </>
}
